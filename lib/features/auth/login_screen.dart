// ── COPIED VERBATIM FROM goouts_app, THEN REWIRED. 10 August 2026. ────────
//
// Mian asked for the consumer app's sign-in screens rather than a reskin of
// the host ones, and he was right. My earlier attempt changed the header of
// the old host screen but left its field layout underneath, so the +44
// country selector collided with the number field. A half-ported layout is
// worse than either original.
//
// So this file is goouts_app/lib/screens/login_screen.dart copied whole. Only four
// things are changed, and they are the four that MUST change:
//
//   1. IMPORTS. The host app puts auth_service under features/auth/services,
//      the support sheet under features/auth/widgets, and goouts_sheet under
//      features/common.
//
//   2. NAVIGATION. goouts_app uses named routes ('/otp', '/home'). This app
//      has no such route table — HostRoutes.onGenerateRoute owns /host/* only
//      and returns null for anything else, which would land on
//      onUnknownRoute and show "Page not found". Replaced with direct
//      MaterialPageRoute pushes to the real host screens.
//
//   3. HOST TEXT. "Welcome back to GoOuts Host." and host-appropriate copy.
//
//   4. HOST AUTH RULES, re-added below. These did not exist in the consumer
//      file and losing them would undo work that cost roughly twenty builds:
//        • AuthFlowGuard around the OTP journey
//        • the legal tick box, which must be ticked before any SMS is sent
//        • accountType 'business' carried into the OTP screen
//
// ⚠ If you re-copy from goouts_app, re-apply all four. The auth rules are not
// cosmetic and their absence is invisible until someone cannot sign in.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/auth_service.dart';
import 'widgets/pre_auth_support_sheet.dart';
import '../common/goouts_sheet.dart';
import 'widgets/goouts_loading_overlay.dart';
import 'auth_flow_guard.dart';
import 'otp_verification_screen.dart';
import 'signup_screen.dart';
import '../home/host_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isPinVisible = false;
  bool _isLoading = false;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final _authService = AuthService();

  static const Color _primary = Color(0xFF0392CA);

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _showForgotPinSheet() {
    final phoneCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F4FB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lock_reset_rounded,
                        color: _primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Forgot PIN?',
                          style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0D1B3E))),
                      Text('We\'ll send a reset code to your number.',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('MOBILE NUMBER',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                      letterSpacing: 1.0)),
              const SizedBox(height: 8),
              Container(
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F6FA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Text('🇬🇧',
                        style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text('+44',
                        style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0D1B3E))),
                    const SizedBox(width: 10),
                    Container(width: 1, height: 24, color: Colors.grey[300]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        autofocus: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: '07xxxxxxxxx',
                          hintStyle: GoogleFonts.inter(
                              color: Colors.grey[400], fontSize: 16),
                        ),
                        style: GoogleFonts.inter(
                            fontSize: 16, color: const Color(0xFF0D1B3E)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    final num = phoneCtrl.text.trim();
                    if (num.length < 10) {
                      GoOutsSheet.warning(context,
                        title: 'Invalid Number',
                        message: 'Please enter a valid UK mobile number.',
                      );
                      return;
                    }
                    Navigator.pop(context);
                    // ⚠ The consumer version pushed '/otp' with NO ARGUMENTS
                    // here, relying on a route table to fill them. Ported
                    // literally that opens the OTP screen with no
                    // verificationId and no number — it cannot verify
                    // anything. Send the code first, then navigate.
                    _sendResetCode(num);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Send Reset Code',
                      style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sends an OTP for the Forgot-PIN journey, then opens the OTP screen.
  ///
  /// The consumer version pushed '/otp' with no arguments and let a route
  /// table supply them. This app has no such table, so the code is sent here
  /// and the real verificationId is handed to the screen directly.
  Future<void> _sendResetCode(String localNumber) async {
    final fullPhone = '+44'
        '${localNumber.startsWith('0') ? localNumber.substring(1) : localNumber}';
    setState(() => _isLoading = true);
    await _authService.sendOtp(
      phoneNumber: fullPhone,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        AuthFlowGuard.start();
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => OtpVerificationScreen(
            verificationId: verificationId,
            phoneNumber: fullPhone,
            localMobileNumber: localNumber,
            resendToken: resendToken,
          ),
        ));
      },
      onAutoVerified: () {
        if (!mounted) return;
        setState(() => _isLoading = false);
        AuthFlowGuard.end();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const HostHomeScreen()),
          (_) => false,
        );
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        GoOutsSheet.error(context, title: 'Could not send code', message: message);
      },
    );
  }

  Future<void> _login() async {
    final number = _phoneController.text.trim();
    final pin = _pinController.text.trim();
    if (number.length < 10) {
      GoOutsSheet.warning(context,
        title: 'Invalid Number',
        message: 'Please enter a valid UK mobile number.',
      );
      return;
    }
    if (pin.length < 4) {
      GoOutsSheet.warning(context,
        title: 'PIN Required',
        message: 'Please enter your 4-digit PIN.',
      );
      return;
    }
    final fullPhone =
        '+44${number.startsWith('0') ? number.substring(1) : number}';

    // ── ⚠ PIN SIGN-IN. RESTORED 10 August 2026. I HAD BROKEN THIS. ─────────
    //
    // When I replaced this screen with goouts_app's, PIN authentication went
    // with it. The consumer version collects a PIN, checks it is four digits,
    // then sends an OTP and passes the PIN along as a route argument for some
    // later screen to verify. The host OTP screen has no PIN handling at all,
    // and my rewiring dropped the argument — so the PIN box was theatre. Any
    // four digits passed, everyone got an SMS, and the field checked nothing.
    //
    // That is worse than the screen it replaced, in three ways: it cost an SMS
    // on every sign-in, it was slower, and it presented a security control
    // that did nothing.
    //
    // A host's PIN is NOT a Firestore hash like the consumer's. Registration
    // links an EmailAuthProvider credential using a synthetic address derived
    // from the phone number, so the PIN IS the Firebase Auth password. Signing
    // in is therefore a real signInWithEmailAndPassword, and a wrong PIN is
    // rejected by Firebase rather than by us.
    //
    // OTP remains the fallback: no linked credential, or a forgotten PIN,
    // falls through to the SMS path below.
    final String emailForAuth =
        '${fullPhone.replaceAll('+', '').replaceAll(' ', '')}@goouts.app';

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailForAuth,
        password: pin,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Straight in. No SMS, no OTP screen, and no AuthFlowGuard — there is no
      // verification journey to protect.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HostHomeScreen()),
        (_) => false,
      );
      return;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // Only 'user-not-found' falls through to OTP — that is a host who
      // registered before the credential was linked, and sending them a code
      // is the right recovery. A WRONG PIN must NOT silently send an SMS:
      // that would charge us for every typo and teach hosts the PIN is
      // optional.
      if (e.code != 'user-not-found') {
        setState(() => _isLoading = false);
        GoOutsSheet.error(
          context,
          title: 'Login Failed',
          message: switch (e.code) {
            'wrong-password' || 'invalid-credential' =>
              'Incorrect PIN. Try again, or tap "Forgot PIN?" to reset it by '
                  'text message.',
            'too-many-requests' =>
              'Too many attempts. Please wait a moment and try again.',
            _ => e.message ?? 'Something went wrong. Please try again.',
          },
        );
        return;
      }
      // user-not-found — continue to the OTP path below.
    } catch (_) {
      // Network or anything unexpected: fall through to OTP rather than
      // stranding someone who cannot sign in.
    }

    await _authService.sendOtp(
      phoneNumber: fullPhone,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        // AuthFlowGuard.start() BEFORE navigating, end() in the OTP screen.
        // Without it authStateChanges() fires partway through verification,
        // _HostLaunchCoordinator rebuilds, and the tree is replaced UNDER the
        // OTP screen — the host is thrown back to the start with no error and
        // nothing in the logs. This cost driver_app roughly twenty builds.
        AuthFlowGuard.start();
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => OtpVerificationScreen(
            verificationId: verificationId,
            phoneNumber: fullPhone,
            localMobileNumber: number,
            resendToken: resendToken,
          ),
        ));
      },
      onAutoVerified: () {
        if (!mounted) return;
        setState(() => _isLoading = false);
        AuthFlowGuard.end();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const HostHomeScreen()),
          (_) => false,
        );
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        GoOutsSheet.error(context,
          title: 'Login Failed',
          message: message,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color inputBackgroundColor = Color(0x33FFFFFF);
    const Color textColor = Colors.white;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return Scaffold(
      backgroundColor: _primary,
      body: Stack(
        children: [
          SafeArea(
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),

                // Brand Header - Centered
                Center(
                  child: Text(
                    'GoOuts',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Hero Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/signup_hero.webp',
                    width: double.infinity,
                    height: 190,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stack) => Container(
                      width: double.infinity,
                      height: 190,
                      decoration: BoxDecoration(
                        color: const Color(0xFF026899),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.local_cafe_rounded,
                          size: 60, color: Colors.white38),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Welcome Section
                Text(
                  'Welcome Back!',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Welcome back to GoOuts.',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: textColor.withValues(alpha: 0.9),
                  ),
                ),

                const SizedBox(height: 20),

                // Mobile Number Label
                Text(
                  'MOBILE NUMBER',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),

                // Mobile Input Field Row
                Row(
                  children: [
                    // UK Flag + +44
                    Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: inputBackgroundColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: textColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Text('🇬🇧',
                              style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Text(
                            '+44',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Phone Number Input
                    Expanded(
                      child: Container(
                        height: 60,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: inputBackgroundColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: textColor.withValues(alpha: 0.2)),
                        ),
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: GoogleFonts.inter(
                            color: Colors.black,
                            fontSize: 18,
                            letterSpacing: 1.2,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 18),
                            hintText: '07xxxxxxxxx',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 18,
                              color: Colors.black38,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // PIN Number Label
                Text(
                  'PIN NUMBER',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),

                // PIN Input Field
                Container(
                  height: 60,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: inputBackgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: textColor.withValues(alpha: 0.2)),
                  ),
                  child: TextField(
                    controller: _pinController,
                    obscureText: !_isPinVisible,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 18,
                      letterSpacing: 4.0,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 18),
                      hintText: '••••',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 18,
                        color: Colors.black38,
                        letterSpacing: 4.0,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPinVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: _primary,
                          size: 22,
                        ),
                        onPressed: () =>
                            setState(() => _isPinVisible = !_isPinVisible),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: _primary),
                          )
                        : Text(
                      'Login',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Forgot PIN
                Center(
                  child: GestureDetector(
                    onTap: () => _showForgotPinSheet(),
                    child: Text(
                      'Forgot PIN?',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Signup Footer
                Center(
                  child: GestureDetector(
                    onTap: () =>
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                              builder: (_) => const SignupScreen()),
                        ),
                    child: RichText(
                      text: TextSpan(
                        style:
                            GoogleFonts.inter(fontSize: 16, color: textColor),
                        children: [
                          const TextSpan(text: "Don't have an account? "),
                          TextSpan(
                            text: 'Sign Up',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: textColor,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                // Pre-auth support link
                Center(
                  child: GestureDetector(
                    onTap: () => showPreAuthSupportSheet(context),
                    child: Text(
                      'Having trouble? Get help',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white70,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
          if (_isLoading) const GoOutsLoadingOverlay(),
        ],
      ),
    );
  }
}
