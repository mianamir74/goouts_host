import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/auth/auth_flow_guard.dart';
import 'features/auth/login_screen.dart';
import 'firebase_options.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GoOuts Host. Bundle com.goouts.host on BOTH platforms.
//
// Created 6 August 2026. The auth folder is copied from driver_app, which is
// the enrolment app — a host signs in exactly like a Business Partner does,
// against the same /users records and the same phone OTP.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Crash reports go to the same Firebase project as the other apps, but are
  // OFF in debug so local experiments do not pollute the production crash
  // list. driver_app's crash history is how its phone-auth bug was eventually
  // found, and that only works if the noise stays out.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  runApp(const GoOutsHostApp());
}

class GoOutsHostApp extends StatelessWidget {
  const GoOutsHostApp({super.key});

  // Matches the palette in the Stitch host screens and STITCH_2_HOST.md.
  static const Color _primary = Color(0xFF0392CA);
  static const Color _navy = Color(0xFF0D1B3E);
  static const Color _background = Color(0xFFF2F4F7);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoOuts Host',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primary,
          primary: _primary,
        ),
        scaffoldBackgroundColor: _background,
        textTheme: GoogleFonts.interTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0.5,
          foregroundColor: _navy,
        ),
      ),
      home: const _HostLaunchCoordinator(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Decides what a host sees on launch.
//
//  ⚠ THE AuthFlowGuard CHECK IS NOT OPTIONAL. It exists because of a real bug
//  in driver_app: authStateChanges() fires partway through phone verification,
//  this StreamBuilder rebuilds, and the widget tree is replaced UNDER the OTP
//  screen mid-flow. The user is thrown back to the start with no error and
//  nothing in the logs.
//
//  LoginScreen calls AuthFlowGuard.start() before verification and .end()
//  immediately before its final navigation. While the guard is active this
//  must not rebuild.
// ─────────────────────────────────────────────────────────────────────────────
class _HostLaunchCoordinator extends StatelessWidget {
  const _HostLaunchCoordinator();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (AuthFlowGuard.isActive) {
          // Mid-login. Hold what is on screen rather than rebuilding it away.
          return const SizedBox.shrink();
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // TODO when the host screens move across from goouts_app: a signed-in
        // host goes to HostRoutes.dashboard, and a host WITHOUT an approved
        // /businesses record goes to KYC registration first. createStayListing
        // refuses anyone unverified, so sending them straight to the listing
        // wizard would let them fill in eight screens and fail at the last one.
        //
        // Until those screens are here, both paths land on login.
        return const LoginScreen();
      },
    );
  }
}
