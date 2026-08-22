import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/auth/auth_flow_guard.dart';
import 'features/home/host_home_screen.dart';
import 'features/intro/host_intro_screen.dart';
import 'features/short_stay/host/host_routes.dart';
import 'features/splash/host_splash_screen.dart';
import 'firebase_options.dart';
import 'services/host_fcm_service.dart';
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

  // ── ⚠ NOTHING SLOW GOES BETWEEN HERE AND runApp ─────────────────────────
  //
  // FIXED 14 August 2026, reported as "I cannot see the splash screen any
  // more". It was not removed — it had stopped being reachable, and that was
  // my doing.
  //
  // enforceFreshInstallSignOut() and loadHostIntroSeen() used to be awaited
  // RIGHT HERE, before runApp. Both touch storage, and the guard was changed
  // earlier the same day to await the first authStateChanges event, which on a
  // cold start can take a moment and is allowed up to five seconds.
  //
  // Two things followed, both bad:
  //
  //   1. Until runApp is called, Flutter has painted nothing. iOS shows the
  //      static LaunchScreen image and nothing else — no logo animation, no
  //      GoOuts branding, no sign the app is doing anything. On a slow start
  //      that was up to five seconds of a frozen picture.
  //
  //   2. By the time the widget tree DID build, auth was already resolved. So
  //      the StreamBuilder never emitted ConnectionState.waiting, and the
  //      branch that shows HostSplashScreen(loading) became dead code. The
  //      splash was still there. It just could not happen.
  //
  // So: runApp IMMEDIATELY. The startup work now happens behind the splash,
  // where the user can see something, instead of in front of a blank screen.
  runApp(const GoOutsHostApp());
}

// ─────────────────────────────────────────────────────────────────────────────
//  Does the startup work WHILE the splash is on screen.
//
//  Everything here used to run before runApp. Moving it behind the splash is
//  the whole point: the guard and the preference read take as long as they
//  take, and the host watches the GoOuts logo rather than a frozen launch
//  image.
//
//  ⚠ THE ORDER MATTERS AND IS NOT ARBITRARY.
//
//  enforceFreshInstallSignOut() runs FIRST and is AWAITED before anything
//  decides what to show. It clears a session that survived an app deletion —
//  if the coordinator ran first, a reinstalled app would render the previous
//  owner's dashboard for a moment before being signed out. A moment is enough
//  to read a name and a KYC status.
//
//  loadHostIntroSeen() runs second, because a reinstall should see the intro
//  again and the guard is what makes it a reinstall.
// ─────────────────────────────────────────────────────────────────────────────
class _HostBootstrap extends StatefulWidget {
  const _HostBootstrap();

  @override
  State<_HostBootstrap> createState() => _HostBootstrapState();
}

class _HostBootstrapState extends State<_HostBootstrap> {
  bool _ready = false;
  StreamSubscription<RemoteMessage>? _openedSub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _openedSub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await enforceFreshInstallSignOut();
      await loadHostIntroSeen();

      // ── FCM STARTUP. TWO CONSTRAINTS, BOTH LEARNED THE HARD WAY. ──────
      //
      // 1. AFTER enforceFreshInstallSignOut, NEVER BEFORE. That guard signs
      //    out a session that survived an app deletion. If push registered
      //    first it would write this device's token onto the PREVIOUS owner's
      //    stay_hosts document, and this phone would receive their booking
      //    notifications until they signed in somewhere else.
      //
      // 2. AFTER THE FIRST FRAME, NEVER IN main(). Firebase's async Swift task
      //    starting before the Flutter UIWindow is active is crash type A in
      //    memory_claud/ios_firebase_phone_auth_crash_fix.md. addPostFrameCallback
      //    is what makes it safe.
      //
      // initialize() itself never shows a permission dialog — see the header
      // of host_fcm_service.dart. The dialog comes from the dashboard.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(HostFcmService.instance.initialize().then((_) {
          if (!mounted) return;
          _openedSub =
              HostFcmService.instance.opened.listen(routeFromHostMessage);

          final RemoteMessage? m =
              HostFcmService.instance.takeInitialMessage();
          if (m != null) routeFromHostMessage(m);
        }));
      });
    } catch (e) {
      // Fail open. A storage error must not leave the host staring at a splash
      // for ever — the guard and the intro flag both default to the safe
      // option on failure, so carrying on is correct.
      debugPrint('host bootstrap: continuing after error — $e');
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const HostSplashScreen(mode: HostSplashMode.loading);
    }
    return const _HostLaunchCoordinator();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Notification routing.
//
//  ⚠ THE KEY IS SET SERVER SIDE in admin_panel/functions/stay_messages.js as
//  data.screen = 'stay_message_thread'. Both apps receive the same key and map
//  it to their own route — the consumer app to StayRoutes.messageHost, this one
//  to HostRoutes.guestThread. The two route names differ; the key must not.
//
//  ⚠ ARGUMENT SHAPE DIFFERS FROM THE CONSUMER APP TOO. HostRoutes passes a
//  bare String booking id; StayRoutes passes a Map. Passing the wrong one
//  opens the thread with an empty id and shows "this conversation could not be
//  opened", which looks like a broken notification rather than a wrong type.
// ─────────────────────────────────────────────────────────────────────────────
final GlobalKey<NavigatorState> hostNavigatorKey = GlobalKey<NavigatorState>();

void routeFromHostMessage(RemoteMessage msg) {
  final NavigatorState? nav = hostNavigatorKey.currentState;
  if (nav == null) return;

  final Map<String, dynamic> data = msg.data;
  final String screen = (data['screen'] ?? '').toString();
  final String bookingId = (data['bookingId'] ?? '').toString();

  switch (screen) {
    case 'stay_message_thread':
      if (bookingId.isEmpty) return;
      nav.pushNamed(HostRoutes.guestThread, arguments: bookingId);
      break;
    default:
      // Unknown notification types do NOT navigate. Opening the dashboard
      // would be a guess, and a guess that moves the host away from whatever
      // they were doing.
      break;
  }
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
      // Required so a tapped notification can navigate from outside the
      // widget tree. See routeFromHostMessage above.
      navigatorKey: hostNavigatorKey,
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
      // _HostBootstrap, NOT _HostLaunchCoordinator. The bootstrap shows the
      // splash while it runs the fresh-install guard and reads the intro
      // preference, then hands over to the coordinator. Pointing this straight
      // at the coordinator again would skip the splash and let a reinstalled
      // app flash the previous owner's dashboard.
      home: const _HostBootstrap(),

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
