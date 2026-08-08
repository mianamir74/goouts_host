// GoOuts Host splash.
//
// ── BUILT 8 August 2026 ────────────────────────────────────────────────────
//
// The app opened straight onto the login form.
//
// ── THE HOUSE PATTERN, TAKEN FROM BOTH APPS THAT HAVE ONE ──────────────────
//
//   goouts_app   lib/screens/splash_screen.dart
//   driver_app   lib/main.dart, class DriverSplashScreen
//
// ⚠ driver_app's lives INSIDE main.dart, not in a file with "splash" in the
// name. A filename search finds only the consumer one and concludes driver_app
// has none — which is exactly the wrong conclusion I drew first time, and the
// reason this note names both locations.
//
// goouts_drapp genuinely has none. That one is still outstanding.
//
// What the two agree on, and what this copies:
//
//   title       plain 'GoOuts' in BOTH. Not the app name. The brand is the
//               constant; the two lines under it say which app this is.
//   tagline     two lines, second line a triple.
//               driver_app: "Your journey. Your income. Your future."
//   caps line   four words separated by  ||  with DOUBLE spaces.
//               driver_app: "DRIVE  ||  DELIVER  ||  EARN  ||  GROW"
//   sub caps    "JOIN THE GOOUTS <role> NETWORK"
//   button      "GET STARTED"
//
// Same gradient, same diagonal streaks and bubble field, same glass card, same
// three dots. Only the words change. Somebody who has seen another GoOuts app
// should recognise this instantly as the same company.
//
// ── IT REPLACES A SPINNER, AND FIXES A REAL FAULT WHILE IT IS THERE ────────
//
// _HostLaunchCoordinator used to show a bare CircularProgressIndicator while
// auth resolved, and then send EVERY host to the login screen — including one
// who was already signed in. Its own TODO admitted it: "Until those screens
// are here, both paths land on login."
//
// Those screens are here now. A signed-in host goes to HostHomeScreen, and the
// login form no longer flashes in front of somebody who never needed it.
//
// ── TWO MODES, BECAUSE THE SAME PICTURE DOES TWO JOBS ──────────────────────
//
//   loading  auth has not resolved yet. Brand only, no buttons — offering a
//            button that might be replaced a frame later is how a person taps
//            something that vanishes under their finger.
//   welcome  nobody is signed in. Same screen, plus the two ways in.
//
// ── NO TIMER ──────────────────────────────────────────────────────────────
//
// goouts_app runs its auth gate on a 1200ms Future.delayed. That works but it
// races: the delay can fire before or after Firebase resolves, and on a slow
// cold start the user watches a finished splash for no reason.
//
// Here the parent StreamBuilder decides, so the screen changes exactly when
// there is something to change to. The animation is decoration over that, not
// a substitute for it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/login_screen.dart';

enum HostSplashMode {
  /// Auth is still resolving. Brand only.
  loading,

  /// Nobody is signed in. Brand plus the ways in.
  welcome,
}

class HostSplashScreen extends StatefulWidget {
  const HostSplashScreen({super.key, required this.mode});

  final HostSplashMode mode;

  @override
  State<HostSplashScreen> createState() => _HostSplashScreenState();
}

class _HostSplashScreenState extends State<HostSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    // Both, always. A repeating controller that outlives its State keeps
    // ticking and keeps the whole tree alive with it.
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toLogin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    final showActions = widget.mode == HostSplashMode.welcome;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // The same flat GoOuts blue the consumer splash uses. Written as a
        // gradient with two identical stops because that is how goouts_app
        // has it, and a future change to one should be easy to mirror.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: <Color>[Color(0xFF0392CA), Color(0xFF0392CA)],
          ),
        ),
        child: Stack(
          children: <Widget>[
            CustomPaint(
              size: Size(MediaQuery.of(context).size.width,
                  MediaQuery.of(context).size.height),
              painter: _DiagonalStreaksPainter(),
            ),
            Positioned(
              right: 16,
              bottom: 120,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _bar(48),
                  const SizedBox(height: 6),
                  _bar(32),
                  const SizedBox(height: 6),
                  _bar(20),
                ],
              ),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  const Spacer(flex: 3),
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _pulseAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 52),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 22),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                                width: 1.2,
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: <Widget>[
                                Image.asset(
                                  'assets/logo/goouts_logo_white.png',
                                  height: 150,
                                  width: 150,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  // A splash that fails on a missing asset is
                                  // a splash that crashes the app on launch.
                                  errorBuilder: (context, error, stack) =>
                                      const Icon(
                                    Icons.holiday_village_outlined,
                                    size: 96,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // 'GoOuts', not 'GoOuts Host'. Both
                                // goouts_app and driver_app title this plainly
                                // 'GoOuts' and let the two lines beneath say
                                // which app it is. Matching that is the point
                                // of a shared splash — the brand is the
                                // constant, the business is the variable.
                                Text(
                                  'GoOuts',
                                  style: GoogleFonts.inter(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // The host's side of the same idea the
                                // consumer splash sells. Guests earn cashback
                                // at nearby GoOuts partners while they stay,
                                // which is what makes a property here
                                // different from the same property anywhere
                                // else — so it is the line worth leading on.
                                // Same cadence as driver_app's "Your
                                // journey. Your income. Your future." Reads as
                                // the same company talking to a different
                                // person.
                                Text(
                                  'Your property.\nYour terms. Your income.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Colors.white.withValues(alpha: 0.95),
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'LIST  ||  HOST  ||  EARN  ||  GROW',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'JOIN THE GOOUTS HOST NETWORK',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.90),
                      letterSpacing: 2.0,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _dot(false),
                      const SizedBox(width: 8),
                      _dot(true),
                      const SizedBox(width: 8),
                      _dot(false),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Nothing tappable until we know there is nobody signed in.
                  if (showActions) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: _toLogin,
                          icon: const Icon(Icons.add_home_outlined,
                              color: Colors.white, size: 20),
                          label: Text(
                            'GET STARTED',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 1.8,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.55),
                                width: 1.5),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Both buttons go to the same screen, and that is correct
                    // rather than lazy: one phone number and one code either
                    // signs a host in or starts enrolment, depending on
                    // whether a /stay_hosts record exists. Two entry points
                    // for the two things a person might believe they are
                    // doing.
                    TextButton(
                      onPressed: _toLogin,
                      child: RichText(
                        text: TextSpan(
                          text: 'Already have an account? ',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                          children: <InlineSpan>[
                            TextSpan(
                              text: 'Sign In',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ] else ...<Widget>[
                    // Same vertical space the buttons would occupy, so the
                    // card does not jump when the mode changes.
                    const SizedBox(height: 54),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white70),
                    ),
                    const SizedBox(height: 62),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(bool active) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: active ? 14 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _bar(double height) => Container(
        width: 4,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// Wave bands and a scattered bubble field.
///
/// Copied from goouts_app so the two splashes are visually identical. Kept as
/// a painter rather than an image because it scales to any screen without a
/// second asset, and because it costs nothing — shouldRepaint is false, so it
/// is drawn once.
class _DiagonalStreaksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bandPaint = Paint()..style = PaintingStyle.stroke;

    // [startX%, startY%, endX%, endY%, controlX%, controlY%, width, opacity]
    const bands = <List<double>>[
      <double>[0.6, 0.0, -0.1, 0.7, 0.55, 0.35, 60.0, 0.06],
      <double>[0.65, 0.0, -0.05, 0.75, 0.60, 0.38, 30.0, 0.09],
      <double>[0.70, 0.0, 0.0, 0.80, 0.65, 0.40, 12.0, 0.15],
      <double>[0.75, 0.0, 0.05, 0.85, 0.70, 0.42, 5.0, 0.20],
      <double>[0.80, 0.0, 0.10, 0.90, 0.75, 0.45, 2.5, 0.12],
    ];

    for (final b in bands) {
      final path = Path()
        ..moveTo(w * b[0], h * b[1])
        ..quadraticBezierTo(w * b[4], h * b[5], w * b[2], h * b[3]);
      bandPaint
        ..color = Colors.white.withValues(alpha: b[7])
        ..strokeWidth = b[6];
      canvas.drawPath(path, bandPaint);
    }

    final bubblePaint = Paint()..style = PaintingStyle.fill;

    // [x%, y%, radius, opacity]
    const bubbles = <List<double>>[
      <double>[0.08, 0.05, 18.0, 0.10],
      <double>[0.22, 0.12, 12.0, 0.08],
      <double>[0.55, 0.08, 22.0, 0.09],
      <double>[0.80, 0.15, 14.0, 0.10],
      <double>[0.92, 0.04, 10.0, 0.07],
      <double>[0.05, 0.25, 10.0, 0.08],
      <double>[0.35, 0.22, 16.0, 0.07],
      <double>[0.68, 0.28, 12.0, 0.09],
      <double>[0.88, 0.32, 18.0, 0.08],
      <double>[0.15, 0.42, 14.0, 0.07],
      <double>[0.48, 0.38, 10.0, 0.10],
      <double>[0.78, 0.45, 16.0, 0.08],
      <double>[0.92, 0.50, 10.0, 0.07],
      <double>[0.05, 0.55, 20.0, 0.08],
      <double>[0.28, 0.58, 12.0, 0.09],
      <double>[0.60, 0.55, 18.0, 0.07],
      <double>[0.82, 0.62, 12.0, 0.10],
      <double>[0.12, 0.70, 10.0, 0.08],
      <double>[0.42, 0.72, 16.0, 0.07],
      <double>[0.70, 0.75, 10.0, 0.09],
      <double>[0.90, 0.78, 18.0, 0.08],
      <double>[0.20, 0.85, 14.0, 0.07],
      <double>[0.55, 0.88, 12.0, 0.09],
      <double>[0.78, 0.92, 10.0, 0.08],
      <double>[0.35, 0.95, 16.0, 0.07],
    ];

    for (final b in bubbles) {
      bubblePaint.color = Colors.white.withValues(alpha: b[3]);
      canvas.drawCircle(Offset(w * b[0], h * b[1]), b[2], bubblePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
