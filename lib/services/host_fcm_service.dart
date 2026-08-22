// ─────────────────────────────────────────────────────────────────────────────
//  Push notifications for GoOuts Host.
//
//  Written 21 August 2026, to close the half of messaging that did not work.
//
//  ── WHAT WAS BROKEN, AND IT WAS NOT A BUG ───────────────────────────────────
//
//  notifyOnStayMessage has been deployed and correct since messaging shipped.
//  It resolves the recipient, checks their preference, and sends. For a guest
//  it works. For a host it reached this line and stopped:
//
//      if (!token) { logger.info("no fcm token for recipient"); return; }
//
//  because this app had no firebase_messaging and therefore no host had ever
//  had a token. Nothing was failing. There was simply nowhere to send to.
//
//  ── WHERE THE TOKEN GOES, AND WHY IT IS NOT users/{uid} ─────────────────────
//
//  stay_hosts/{uid}.fcmToken.
//
//  The consumer app writes users/{uid}.fcmToken and it was tempting to reuse
//  that. It would be wrong: a person can be both a guest and a host with the
//  same account, on two different phones. One token field shared between the
//  two apps means the second app to sign in silently overwrites the first, and
//  the loser stops receiving anything with no error anywhere.
//
//  ⚠ notifyOnStayMessage READS EXACTLY stay_hosts/{uid}.fcmToken AND
//  stay_hosts/{uid}.notificationPrefs.guestMessages. Renaming either here
//  without renaming it there breaks push silently — the classic failure in
//  this codebase, where a rename leaves both halves running and neither
//  complaining.
//
//  ── ⚠ requestPermission() IS NEVER CALLED FROM initialize(). READ THIS. ─────
//
//  This is not a style preference. It is the documented cause of an iOS crash
//  that took driver_app roughly thirteen builds to find — see
//  memory_claud/ios_firebase_phone_auth_crash_fix.md, "Crash Type C".
//
//  FirebaseMessaging.requestPermission() internally calls
//  UIApplication.registerForRemoteNotifications(). This app's AppDelegate
//  ALREADY calls that at startup, because Firebase Phone Auth needs the APNs
//  token for its silent verification push. Calling requestPermission() during
//  startup therefore triggers a SECOND APNs registration, and Firebase's async
//  Swift task processing that second token hits preconditionFailure. The app
//  dies with EXC_BREAKPOINT / SIGTRAP and the stack names nothing useful.
//
//  So:
//
//    initialize()      getNotificationSettings() ONLY. Reads the current
//                      status with no APNs side effect. Saves the token if
//                      permission was already granted.
//
//    askPermission()   the only caller of requestPermission(). Called from the
//                      dashboard, post login, inside addPostFrameCallback.
//
//  Asking there is also better product behaviour — a permission dialog thrown
//  at somebody who has not yet seen what the app does is the fastest route to
//  a permanent refusal, and on iOS a refusal cannot be re-prompted.
//
//  ── THE RULES ALLOW THIS WRITE ALREADY ──────────────────────────────────────
//
//  stay_hosts/{hostId} allows update via selfEditAllowed, which refuses only
//  driverProtectedFields — walletBalance, kycStatus, accountStatus and the
//  rest. fcmToken is not among them and must never be added to that list, or
//  a host would be unable to register their own device.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../features/short_stay/host/host_collection.dart';
import '../firebase_options.dart';

/// Runs in its own isolate when a notification arrives with the app killed.
///
/// It must initialise Firebase itself — the isolate shares nothing with the
/// app — and it must do almost nothing else. Anything slow here is work the
/// operating system may kill halfway through.
@pragma('vm:entry-point')
Future<void> hostFcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('FCM [goouts_host] background: ${message.messageId}');
}

class HostFcmService {
  HostFcmService._();
  static final HostFcmService instance = HostFcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final StreamController<RemoteMessage> _opened =
      StreamController<RemoteMessage>.broadcast();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  bool _initialized = false;
  RemoteMessage? _initialMessage;

  /// Notifications the host tapped. main.dart listens and routes them.
  Stream<RemoteMessage> get opened => _opened.stream;

  /// The notification that launched the app from cold, if any. Read once —
  /// returns null afterwards so a rebuild cannot navigate twice.
  RemoteMessage? takeInitialMessage() {
    final RemoteMessage? m = _initialMessage;
    _initialMessage = null;
    return m;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      FirebaseMessaging.onBackgroundMessage(hostFcmBackgroundHandler);
      await _messaging.setAutoInitEnabled(true);

      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_opened.add);
      _initialMessage = await _messaging.getInitialMessage();

      // A rotated token is a token the server no longer has. Without this the
      // host stops receiving anything, weeks later, for no visible reason.
      _tokenSub = _messaging.onTokenRefresh.listen((String t) => _save(t));

      // Sign in, sign out, and account switching. The token belongs to whoever
      // is signed in NOW — see _clear for why the old one is removed.
      _authSub = _auth.authStateChanges().listen((User? u) async {
        if (u == null) return;
        // Status read only. The dialog, if one is needed, comes from the
        // dashboard via askPermission — never from here.
        await _saveIfAlreadyGranted();
      });

      if (_auth.currentUser != null) await _saveIfAlreadyGranted();
    } catch (e) {
      // Push is an enhancement. An app that will not start because
      // notifications failed to register is a far worse outcome than an app
      // that does not notify.
      debugPrint('host fcm: initialise failed — $e');
    }
  }

  /// Reads the CURRENT permission status and stores the token if it is
  /// already granted. Never shows a dialog.
  ///
  /// ⚠ getNotificationSettings, NOT requestPermission. See the header — the
  /// difference between these two calls is an iOS crash.
  Future<bool> _saveIfAlreadyGranted() async {
    try {
      final NotificationSettings s = await _messaging.getNotificationSettings();
      if (!_granted(s)) return false;
      return _fetchAndSave();
    } catch (e) {
      debugPrint('host fcm: status read failed — $e');
      return false;
    }
  }

  /// Shows the permission dialog, then stores the token.
  ///
  /// ⚠ THE ONLY PLACE requestPermission() MAY BE CALLED, and it must be
  /// reached from a screen the host sees AFTER signing in, inside
  /// addPostFrameCallback. Calling it during startup is the crash described in
  /// the header. host_01_dashboard_screen is the caller.
  Future<bool> askPermission() async {
    try {
      final NotificationSettings s = await _messaging.requestPermission();
      if (!_granted(s)) return false;
      return _fetchAndSave();
    } catch (e) {
      debugPrint('host fcm: askPermission failed — $e');
      return false;
    }
  }

  static bool _granted(NotificationSettings s) =>
      s.authorizationStatus == AuthorizationStatus.authorized ||
      s.authorizationStatus == AuthorizationStatus.provisional;

  Future<bool> _fetchAndSave() async {
    try {

      // ⚠ iOS RETURNS NULL UNTIL APNS HAS ISSUED ITS OWN TOKEN. Asking for the
      // FCM token in the same breath as permission returns null on a real
      // device often enough to matter, and a null token saved as an empty
      // string is worse than none — the function would treat it as present.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final String? apns = await _messaging.getAPNSToken();
        if (apns == null) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }

      final String? token = await _messaging.getToken();
      if (token == null || token.isEmpty) return false;

      await _save(token);
      return true;
    } catch (e) {
      debugPrint('host fcm: token fetch failed — $e');
      return false;
    }
  }

  Future<void> _save(String token) async {
    final User? u = _auth.currentUser;
    if (u == null) return;
    try {
      await _db.collection(kStayHostsCollection).doc(u.uid).set(
        <String, dynamic>{
          'fcmToken': token,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('host fcm: could not save token — $e');
    }
  }

  /// Removes this device's token on sign out.
  ///
  /// ⚠ CALL THIS BEFORE signOut(), NOT AFTER. Once the user is gone the rules
  /// refuse the write — ownsDoc compares the document id to the signed-in uid
  /// — and the token stays behind. The next person to sign in on this phone
  /// would then receive the previous host's booking notifications.
  Future<void> clearToken() async {
    final User? u = _auth.currentUser;
    if (u == null) return;
    try {
      await _db.collection(kStayHostsCollection).doc(u.uid).set(
        <String, dynamic>{
          'fcmToken': FieldValue.delete(),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('host fcm: could not clear token — $e');
    }
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenSub?.cancel();
    await _openedSub?.cancel();
    await _opened.close();
  }
}
