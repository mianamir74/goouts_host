import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/auth/auth_flow_guard.dart';
import 'features/home/host_home_screen.dart';
import 'features/intro/host_intro_screen.dart';
import 'features/short_stay/host/host_routes.dart';
import 'features/splash/host_splash_screen.dart';
import 'firebase_options.dart';
import 'theme/goouts_colors.dart';
import 'features/auth/fresh_install_guard.dart';

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

    // ── SIGN OUT A SESSION THAT SURVIVED A REINSTALL ────────────────────────
  //
  // MUST run after Firebase.initializeApp (it needs FirebaseAuth) and BEFORE
  // runApp (so no screen ever renders for a user who is about to be signed
  // out). See features/auth/fresh_install_guard.dart for why this exists.
  await enforceFreshInstallSignOut();

  // ── HAS THIS HOST SEEN THE INTRO? ───────────────────────────────────────
  //
  // Read HERE rather than inside the launch coordinator, because the
  // coordinator is a StreamBuilder and has to decide synchronously. Resolving
  // a Future in there would show the welcome splash for a frame and then
  // replace it with the intro, which reads as a glitch on the very first
  // launch — the one launch where it matters most.
  //
  // Must run AFTER enforceFreshInstallSignOut: that clears a session left in
  // the Keychain by a previous install, and a reinstalled app should get the
  // intro again.
  await loadHostIntroSeen();

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

        // Auth has not resolved. The splash rather than a bare spinner — a
        // cold start on a poor connection can sit here for a second or two,
        // and a blue screen with the brand on it is a better second than a
        // grey one with a circle.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const HostSplashScreen(mode: HostSplashMode.loading);
        }

        // ── SIGNED IN ────────────────────────────────────────────────────
        //
        // FIXED 8 August 2026. This used to return LoginScreen for EVERYONE,
        // with a TODO admitting it: "Until those screens are here, both paths
        // land on login." Those screens are here now.
        //
        // The old behaviour was not merely untidy. A returning host saw the
        // login form appear, then get replaced a moment later once
        // LoginScreen's own auth listener noticed they were already signed in
        // and navigated away. Being shown a login form you do not need reads
        // as "it has forgotten me".
        //
        // HostHomeScreen, not the dashboard, and deliberately: it is the
        // screen that reads /stay_hosts and tells a host whether they are
        // verified. createStayListing refuses anyone unverified, so a host
        // dropped straight into the listing wizard would fill in seven screens
        // and be refused at the last one.
        if (snapshot.data != null) {
          return const HostHomeScreen();
        }

        // ── NOBODY SIGNED IN ─────────────────────────────────────────────
        //
        // First launch gets the six intro screens, which are the only place
        // that answers "why list here instead of Airbnb". After that — or if
        // the preference could not be read — straight to the welcome splash.
        //
        // The intro marks itself seen and pushReplacement-es to signup or
        // login, so it never appears twice and never stacks behind them.
        if (!hostIntroSeen) {
          return const HostIntroScreen();
        }

        // Returning, signed out. Same splash, with the ways in.
        return const HostSplashScreen(mode: HostSplashMode.welcome);
      },
    );
  }
}
