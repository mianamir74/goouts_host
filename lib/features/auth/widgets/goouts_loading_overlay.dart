import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Full-screen branded loading overlay — used during Firebase OTP / reCAPTCHA.
// Copied from GoOuts consumer app and adapted for GoOuts Lead.

class GoOutsLoadingOverlay extends StatefulWidget {
  final String message;
  final String subtitle;

  const GoOutsLoadingOverlay({
    super.key,
    this.message = 'Verifying your number…',
    this.subtitle = 'This may take a few seconds',
  });

  @override
  State<GoOutsLoadingOverlay> createState() => _GoOutsLoadingOverlayState();
}

class _GoOutsLoadingOverlayState extends State<GoOutsLoadingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  late final Animation<double> _pulseScale = Tween<double>(begin: 0.88, end: 1.12)
      .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

  late final Animation<double> _pulseOpacity = Tween<double>(begin: 0.5, end: 1.0)
      .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward();

  late final Animation<double> _fadeAnim =
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

  late final AnimationController _dotsCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0392CA),
              Color(0xFF025F87),
              Color(0xFF0D1B3E),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 60),
              Text(
                'GoOuts',
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              Text(
                // Was 'LEAD'. This overlay was copied wholesale from driver_app when the
                // host app was created, and the sub-brand came with it — so a host
                // verifying their number was shown "GoOuts LEAD" on a full-screen
                // takeover. Reported from a TestFlight screenshot, 10 August 2026.
                'HOST',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.55),
                  letterSpacing: 3,
                ),
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: _pulseScale.value * 1.15,
                      child: Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white
                              .withValues(alpha: (_pulseOpacity.value * 0.06).clamp(0, 1)),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: _pulseScale.value,
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white
                              .withValues(alpha: (_pulseOpacity.value * 0.12).clamp(0, 1)),
                        ),
                      ),
                    ),
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(
                widget.message,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.subtitle,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              AnimatedBuilder(
                animation: _dotsCtrl,
                builder: (_, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final phase = (i / 3.0);
                    final val = (_dotsCtrl.value - phase + 1.0) % 1.0;
                    final opacity = val < 0.5 ? val * 2 : (1.0 - val) * 2;
                    final scale = 0.7 + opacity * 0.4;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white
                                .withValues(alpha: opacity.clamp(0.25, 1.0)),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Text(
                  'Secured by GoOuts',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.35),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
