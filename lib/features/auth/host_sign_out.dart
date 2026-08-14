// The one way a host signs out.
//
// ── WHY THIS EXISTS ──────────────────────────────────────────────────────
//
// 13 August 2026. Sign-out was implemented twice, independently:
//
//   host_home_screen.dart          app bar logout icon
//   host_24_profile_screen.dart    Sign out row, with a confirm dialog
//
// Each had its own signOut() call and its own navigation. They happened to
// agree today. Nothing kept them agreeing.
//
// That is the same shape as the unreadByUser / unreadByDriver split and the
// kycStatus / status split — two copies of one idea, drifting apart until
// somebody notices that logging out from one screen behaves differently from
// logging out from the other. Both of those cost a day to find.
//
// ── WHERE SIGN-OUT LANDS, AND WHY IT IS NOT THE SPLASH ───────────────────
//
// LoginScreen, deliberately — not HostSplashScreen(welcome).
//
// A host who has just signed out HAS an account. The welcome splash exists to
// sell the app to someone who does not, so sending them there means answering
// "why should I list with GoOuts" to somebody who already did. They want the
// phone-and-PIN box.
//
// A cold start with no session still shows the welcome splash. That is not an
// inconsistency: arriving at the app fresh and choosing to leave it are
// different intents, and the splash offers both doors while this offers the
// one that was just asked for.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';

/// Signs the host out and returns them to the login screen.
///
/// Clears the whole navigation stack. Back from the login screen must not walk
/// into the dashboard of the account that was just signed out of — on a phone
/// that has been handed to someone else, that is the whole point.
Future<void> hostSignOut(BuildContext context) async {
  try {
    await FirebaseAuth.instance.signOut();
  } catch (e) {
    // Deliberately swallowed, and the navigation below still runs.
    //
    // signOut() only fails on a local storage error; the session is already
    // gone from memory. Leaving the host staring at a dashboard because the
    // Keychain write failed is worse than sending them to login with a token
    // that will be rejected the moment it is used.
    debugPrint('hostSignOut: signOut threw, continuing anyway — $e');
  }

  if (!context.mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    (Route<dynamic> route) => false,
  );
}
