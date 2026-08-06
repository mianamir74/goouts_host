import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/auth/auth_flow_guard.dart';
import 'features/auth/login_screen.dart';
import 'features/short_stay/host/host_routes.dart';
import 'firebase_options.dart';
import 'theme/goouts_colors.dart';

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

  // Colours come from theme/goouts_colors.dart, not from local constants.
  //
  // This used to declare its own _primary/_navy/_background, and _background
  // was 0xFFF2F4F7 while 18 of the 25 host screens painted themselves
  // 0xFFF8F9FF. Any screen that did not set its own Scaffold background got
  // the app one, so the shade shifted depending on which screen you were on.
  // Reading from the shared file makes that impossible rather than unlikely.

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoOuts Host',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GoOutsColors.primary,
          primary: GoOutsColors.primary,
        ),
        scaffoldBackgroundColor: GoOutsColors.background,
        textTheme: GoogleFonts.interTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: GoOutsColors.surface,
          elevation: 0.5,
          foregroundColor: GoOutsColors.navy,
        ),
      ),
      home: const _HostLaunchCoordinator(),

      // The 25 host screens. One line rather than 25 entries, because
      // HostRoutes owns its own names and parses its own arguments — adding a
      // screen means touching host_routes.dart only, never this file.
      //
      // ⚠ THESE SCREENS ARE REACHABLE, NOT FUNCTIONAL. They came from Stitch
      // on 4 August 2026: every handler is empty and every figure on screen is
      // placeholder copy. Routing them makes them openable. It does not make
      // them work, and the two are very easy to confuse when a screen looks
      // finished.
      onGenerateRoute: HostRoutes.onGenerateRoute,

      // REQUIRED HERE, unlike in goouts_app.
      //
      // HostRoutes.onGenerateRoute returns NULL for a name it does not own.
      // In the consumer app that was correct — the null fell through to a
      // `routes:` map with 60 more entries. This app has no such map, so a
      // null return would reach Flutter with nowhere to go and throw. A typo
      // in a route name would become a crash rather than a visible mistake.
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Page not found')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No screen is registered for "${settings.name}".',
                textAlign: TextAlign.center,
                style: const TextStyle(color: GoOutsColors.body),
              ),
            ),
          ),
        ),
      ),
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
