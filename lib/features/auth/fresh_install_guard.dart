// Sign out on a fresh install.
//
// ── THE HOLE THIS CLOSES ─────────────────────────────────────────────────
//
// Reported 10 August 2026: "delete the app without signing out, reinstall,
// and it opens already logged in."
//
// That is real, and it is iOS-specific. Firebase Auth keeps the refresh token
// in the iOS KEYCHAIN, and the Keychain is NOT wiped when an app is deleted —
// it survives so that reinstalling a password manager does not lose your
// vault. Firebase reads it back on first launch and restores the session.
//
// On Android an uninstall clears app data, so it does not happen there.
//
// Why it matters here specifically: a host's account holds their KYC record,
// identity documents, business details and live bookings. Someone sells or
// hands on a phone, the next owner installs GoOuts Host, and they are signed
// in as the previous owner. Nobody typed a PIN and nobody received an OTP.
//
// ── HOW THE DETECTION WORKS ──────────────────────────────────────────────
//
// SharedPreferences maps to NSUserDefaults on iOS, and NSUserDefaults IS
// cleared when the app is deleted. So:
//
//   marker present  -> the app has run on this install before
//   marker absent   -> fresh install (or the user cleared app data)
//
// If the marker is absent but Firebase reports a signed-in user, that session
// can only have come from the Keychain surviving a delete. Sign it out.
//
// ── WHAT THIS DELIBERATELY DOES NOT DO ───────────────────────────────────
//
// It does NOT sign anyone out for closing the app, force-quitting, rebooting,
// or being offline. Those are normal and the session should survive them —
// nobody wants to re-authenticate a banking app every morning. The marker is
// written once and then read forever, so the only trigger is a genuinely
// fresh install.
//
// ── FAILURE MODE ─────────────────────────────────────────────────────────
//
// If SharedPreferences throws, this returns without signing anyone out. That
// is the deliberate choice: a storage error must not log out every host on
// the platform at once. The cost of failing open is one edge case on a resold
// phone; the cost of failing closed is a mass logout.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marker key. Never rename this — a rename reads as "fresh install" to every
/// existing user on the next update and signs the whole userbase out.
const String _kInstallMarker = 'goouts_install_marker_v1';

Future<void> enforceFreshInstallSignOut() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final seenBefore = prefs.getBool(_kInstallMarker) ?? false;

    if (seenBefore) return;

    // First launch on this install. If a session exists, it came out of the
    // Keychain after a delete — it did not come from anyone signing in.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      debugPrint(
        'fresh_install_guard: signing out a session that survived a reinstall '
        '(uid ${user.uid})',
      );
      await FirebaseAuth.instance.signOut();
    }

    // Written AFTER the sign-out, never before. If the app is killed between
    // the two, the next launch simply tries again — which is the safe order.
    await prefs.setBool(_kInstallMarker, true);
  } catch (e) {
    // Fail open. See the header note.
    debugPrint('fresh_install_guard: skipped — $e');
  }
}
