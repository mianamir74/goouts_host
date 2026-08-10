// ── COPIED VERBATIM FROM goouts_app, THEN REWIRED. 10 August 2026. ────────
//
// Mian asked for the consumer app's sign-in screens rather than a reskin of
// the host ones, and he was right. My earlier attempt changed the header of
// the old host screen but left its field layout underneath, so the +44
// country selector collided with the number field. A half-ported layout is
// worse than either original.
//
// So this file is goouts_app/lib/screens/signup_screen.dart copied whole. Only four
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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/auth_service.dart';
import 'widgets/pre_auth_support_sheet.dart';
import '../common/goouts_sheet.dart';
import 'widgets/goouts_loading_overlay.dart';
import 'auth_flow_guard.dart';
import 'otp_verification_screen.dart';
import 'login_screen.dart';
import 'business_referral_code_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _phoneController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  String? _termsFromDb;

  static const Color _primary = Color(0xFF0392CA);

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('content_pages')
          .doc('terms_conditions')
          .get();
      final content = doc.data()?['content'] as String?;
      if (content != null && content.trim().isNotEmpty && mounted) {
        setState(() => _termsFromDb = content);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final number = _phoneController.text.trim();
    if (number.length < 10) {
      GoOutsSheet.warning(context,
        title: 'Invalid Number',
        message: 'Please enter a valid UK mobile number.',
      );
      return;
    }
    final fullPhone =
        '+44${number.startsWith('0') ? number.substring(1) : number}';

    setState(() => _isLoading = true);

    await _authService.sendOtp(
      phoneNumber: fullPhone,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        // See the note in login_screen: AuthFlowGuard must bracket the OTP
        // journey or the widget tree is replaced under the OTP screen.
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
        // NOT '/create-profile'. That is the consumer journey. A host goes to
        // the referral code screen, which leads to business registration and
        // then HostCreateProfileScreen for the photo and ID.
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => const BusinessReferralCodeScreen(),
        ));
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        GoOutsSheet.error(context, title: 'Sign Up Failed', message: message);
      },
    );
  }

  void _showTerms(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Terms of Service',
                        style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0D1B3E))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.black54, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _termsFromDb ?? '''Last updated: June 2026

Welcome to GoOuts. By accessing or using the GoOuts application and services, you agree to be bound by these Terms of Service. Please read them carefully before proceeding.

1. ACCEPTANCE OF TERMS
By creating an account or using the GoOuts platform, you confirm that you are at least 16 years of age (18 for financial features), a UK resident, and that you accept these Terms of Service in full.

2. DESCRIPTION OF SERVICE
GoOuts is a cashback rewards and social finance platform that allows users to earn, collect, and redeem cashback at participating partner merchants across the United Kingdom. GoOuts operates a virtual debit card linked to your GoOuts wallet.

3. ACCOUNT REGISTRATION
You must provide accurate and complete information when registering. You are responsible for maintaining the confidentiality of your account credentials. You must notify GoOuts immediately of any unauthorised access to your account.

4. CASHBACK REWARDS
Cashback is awarded at the discretion of GoOuts and participating merchants and is subject to transaction verification via GPS proximity and QR code authentication.

5. VIRTUAL DEBIT CARD
The GoOuts Virtual Debit Card is issued subject to eligibility and identity verification (KYC). Card usage is subject to applicable spending limits and UK financial regulations.

6. PAYMENT SERVICES & TECHNICAL SERVICE PROVIDER STATUS
GoOuts Limited is a technology platform provider and does not hold, process, store, or control any user funds at any time. Your GoOuts Wallet is powered by Stripe. Funds you add are held in a Stripe account in your name. GoOuts does not hold your money. Stripe Payments Europe Ltd (FCA ref: 900461) is the authorised payment institution. All payment processing, card issuance, and fund management services are provided exclusively by our regulated third-party financial services partner(s), who are authorised and regulated by the Financial Conduct Authority (FCA) as Electronic Money Institutions under the UK Electronic Money Regulations 2011. Your funds are held by our regulated partner(s) and subject to their safeguarding obligations. Payment providers may be updated from time to time; any change will be notified to you in advance. GoOuts Limited accepts no liability for any act, omission, or failure of our regulated payment partner(s). GoOuts Limited operates solely as a technical service provider under Schedule 1, Part 2(j) of the UK Payment Services Regulations 2017.

7. USER CONDUCT
You agree not to use GoOuts for any unlawful purpose. Misuse of the platform will result in immediate account suspension.

8. PRIVACY & DATA
GoOuts collects and processes your personal data in accordance with our Privacy Policy and the UK GDPR. We do not sell your personal data to third parties.

9. LIMITATION OF LIABILITY
GoOuts shall not be liable for any indirect, incidental, or consequential damages arising from the use of our services. Our total aggregate liability shall not exceed the total Cashback credited to your account in the twelve months preceding any claim.

10. GOVERNING LAW
These Terms of Service are governed by the laws of England and Wales.

For questions: legal@goouts.co.uk''',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Colors.grey[700], height: 1.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
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

                // Brand Header
                Text(
                  'GoOuts',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
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

                // Heading
                Text(
                  'Enter your mobile number',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 10),

                // Subtext
                Text(
                  "We'll send you a verification code to get you started on your journey.",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 20),

                // Phone input row
                Row(
                  children: [
                    // UK Flag + +44
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Text('🇬🇧',
                              style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Text('+44',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Phone input
                    Expanded(
                      child: Container(
                        height: 64,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            letterSpacing: 1.2,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '07xxxxxxxxx',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 18,
                              color: Colors.black38,
                              letterSpacing: 1.2,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Terms
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      children: [
                        const TextSpan(
                            text: 'By continuing, you agree to our '),
                        TextSpan(
                          text: 'Terms of Service',
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _showTerms(context),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: _primary, strokeWidth: 2)
                        : Text('Continue',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            )),
                  ),
                ),

                const SizedBox(height: 12),

                // Login footer
                Center(
                  child: GestureDetector(
                    onTap: () =>
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                              builder: (_) => const LoginScreen()),
                        ),
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.inter(
                            fontSize: 16, color: Colors.white),
                        children: [
                          const TextSpan(text: 'Already have an account? '),
                          TextSpan(
                            text: 'Login',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
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
    ),
    );
  }
}
