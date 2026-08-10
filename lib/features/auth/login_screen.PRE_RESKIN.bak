import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart'; // TapGestureRecognizer, for the legal links
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_flow_guard.dart';
import 'services/auth_service.dart';

import '../home/host_home_screen.dart';
import 'business_referral_code_screen.dart';
import 'otp_verification_screen.dart';
import 'widgets/pre_auth_support_sheet.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:google_fonts/google_fonts.dart';

import '../short_stay/host/host_collection.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color _goOutsBlue = Color(0xFF0392CA);

  static const String _pendingAccountTypeKey = 'pending_account_type';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  // Constant in this app — this app enrols hosts and nothing else.
  //
  // The value is still the string 'business' because it is passed to the
  // OTP screen and written to /users, and both of those already understand
  // it. It does NOT mean a host is a driver_app Business Partner: as of
  // 8 August 2026 a host is a /stay_hosts record and has nothing to do with
  // /businesses. See host_collection.dart for why that changed.
  final String _selectedAccountType = 'business';
  bool _hasReadRouteArgs = false;
  bool _isReturningUser = false;
  bool _obscurePassword = true;

  // ── LEGAL ACCEPTANCE, ASKED BEFORE ANYTHING IS SENT ──────────────────────
  //
  // MOVED HERE 8 August 2026 from business_registration_screen, where the tick
  // box sat near the bottom of a long form — AFTER the host had given their
  // phone number, received an SMS code, and typed their name, address and
  // company number.
  //
  // This screen previously carried only a passive "By continuing, you agree
  // to our Terms" line. That is a weaker record of consent than a box someone
  // deliberately ticked, and it was in the wrong place in the journey.
  //
  // Nothing leaves the device until this is true: _handleContinue refuses,
  // so no phone number is submitted and no SMS is sent.
  //
  // Not shown to returning users. They agreed at signup, and asking again
  // implies the terms changed when they have not.
  bool _acceptedLegal = false;
  bool _showLegalError = false;

  final _authService = AuthService();

  // Simple country picker state
  String _selectedDialCode = '+44';
  String _selectedFlag = '🇬🇧';

  StreamSubscription<User?>? _authSubscription;
  bool _skipFirstAuthEvent = true;

  @override
  void initState() {
    super.initState();
    // Skip the first emission (current state on subscribe) — we only want to
    // react when the user actively signs in via OTP on this screen.
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (_skipFirstAuthEvent) {
        _skipFirstAuthEvent = false;
        return;
      }
      if (user != null && mounted) {
        try {
          await _navigateToHomeForExistingUser(user);
        } catch (_) {
          // Silently ignore — login screen remains visible, user can retry
        }
      }
    });

    // Unawaited on purpose. The legal text has a hardcoded fallback, so the
    // screen must never wait on a network round trip before someone can type
    // their phone number.
    _loadHostLegal();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_hasReadRouteArgs) {
      return;
    }

    _hasReadRouteArgs = true;

    final Object? args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      // GoOuts Host: account type is NOT read from route arguments.
      //
      // In driver_app this block chose between driver / cab_driver / business
      // because that one app enrols all three. This app enrols hosts only, so
      // there is nothing to choose, and accepting an accountType argument here
      // would only create a way to land in a role this app cannot serve.

      // Pre-fill mobile number if passed (e.g. after logout)
      final String mobile = (args['mobile'] ?? '').toString().trim();
      if (mobile.isNotEmpty) {
        _mobileController.text = mobile;
      }

      // Show password field if this is a returning user (came from logout)
      final bool returningUser = args['isReturningUser'] == true;
      if (returningUser) {
        _isReturningUser = true;
      }
    }
  }

  String? _mobileValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Mobile number is required';
    }

    final String cleaned = value.trim().replaceAll(RegExp(r'\s+'), '');

    if (_selectedDialCode == '+44') {
      if (!RegExp(r'^07\d{9}$').hasMatch(cleaned)) {
        return 'Enter a valid UK mobile number (e.g. 07911123456)';
      }
    } else if (_selectedDialCode == '+353') {
      if (!RegExp(r'^08\d{8}$').hasMatch(cleaned)) {
        return 'Enter a valid Irish mobile number (e.g. 0851234567)';
      }
    } else {
      if (cleaned.length < 7) {
        return 'Enter a valid mobile number';
      }
    }

    return null;
  }

  String _toE164Number(String localNumber) {
    final String cleaned = localNumber.replaceAll(RegExp(r'[\s\-()]'), '');

    // Already in E.164 — return as-is
    if (cleaned.startsWith('+')) return cleaned;

    // UK: 07xxxxxxxxx (11 digits) → +447xxxxxxxxx
    if (_selectedDialCode == '+44') {
      if (cleaned.startsWith('07') && cleaned.length == 11) {
        return '+44${cleaned.substring(1)}';
      }
      // UK number without leading 0: 7xxxxxxxxx (10 digits)
      if (cleaned.startsWith('7') && cleaned.length == 10) {
        return '+44$cleaned';
      }
    }

    // Ireland: 08xxxxxxxxx (10 digits) → +3538xxxxxxxxx (drop leading 0)
    if (_selectedDialCode == '+353') {
      if (cleaned.startsWith('0') && cleaned.length >= 9) {
        return '+353${cleaned.substring(1)}';
      }
      return '+353$cleaned';
    }

    // Other dial codes — strip non-digits then prepend dial code
    if (_selectedDialCode.isNotEmpty) {
      final String digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
      return '$_selectedDialCode$digitsOnly';
    }

    return cleaned;
  }

  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ── LEGAL DOCUMENTS ─────────────────────────────────────────────────────────
  //
  // Same pattern as driver_app and the consumer app: the text is loaded from
  // Firestore so a wording change does not need an App Store release, with a
  // hardcoded fallback so the screen still works offline or before seeding.
  //
  // A host is agreeing to something different from a driver or a consumer —
  // commission, cancellation liability, property-letting warranties — so this
  // reads its own document rather than the shared content_pages/terms.
  //
  // ⚠ MOVED 8 August 2026 from platform_config/host_legal.
  //
  // platform_config is `allow read, write: if isAdmin()`. Every read here was
  // DENIED, and the catch below swallowed it — correctly, because a legal
  // document that fails to load must never block someone signing up. The
  // result was that the fallback text at the bottom of this file was the only
  // thing any host ever saw, while the admin panel's Host Legal Documents page
  // wrote to a document nobody could read.
  //
  // legal_documents is `allow read: if true`. It has to be readable without
  // signing in, because these terms are shown ON the sign-up screen — the
  // alternative is asking someone to agree to something they cannot open until
  // after they have agreed to it.
  //
  // platform_config was NOT widened to fix this. It holds commission rates.
  //
  // NOTE: driver_app and the consumer app have the same latent bug for a
  // different reason — they read content_pages, which requires auth, from a
  // pre-auth screen. Their terms have always been the hardcoded fallback too.
  String? _hostTermsFromDb;
  String? _hostPrivacyFromDb;

  Future<void> _loadHostLegal() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('legal_documents')
          .doc('host_legal')
          .get();
      final d = snap.data();
      if (d == null || !mounted) return;
      final terms = (d['terms'] ?? '').toString();
      final privacy = (d['privacy'] ?? '').toString();
      setState(() {
        if (terms.trim().isNotEmpty) _hostTermsFromDb = terms;
        if (privacy.trim().isNotEmpty) _hostPrivacyFromDb = privacy;
      });
    } catch (_) {
      // Not fatal. The fallback text below is shown instead — a legal document
      // that fails to load must never block someone from signing up.
    }
  }

  static const String _fallbackTerms = '''
GoOuts Host — Terms & Conditions

PLACEHOLDER FOR TESTING. These terms will be replaced by professionally
drafted terms before launch.

1. About GoOuts Host
GoOuts Host lets property owners and managers in the United Kingdom and
Northern Ireland list short-stay accommodation to guests on the GoOuts
platform. GoOuts is the platform, not the accommodation provider — the
agreement to stay is between you and your guest.

2. Who can host
You must be 18 or over. You must be legally entitled to let the property,
including any permission required from a mortgage lender, freeholder or
insurer, and you must comply with any local limits on short-term letting.

3. Verification
Hosting requires identity and business verification before a listing can be
published. Listings are reviewed by GoOuts before they become visible.

4. Commission and cashback
GoOuts charges commission on each confirmed booking, and a share of that
commission funds the cashback guests earn at partner venues. Current rates
are shown in the app before you list.

5. Cancellations
Each listing carries a cancellation policy you choose. It applies to your
guests and to you.

6. Your responsibilities
You are responsible for the accuracy of your listing, for gas and fire
safety, and for the condition of the property at check-in.

Governed by the laws of England and Wales.
''';

  static const String _fallbackPrivacy = '''
GoOuts Host — Privacy Policy

PLACEHOLDER FOR TESTING. This policy will be replaced by a professionally
drafted policy before launch.

Who we are
GoOuts Worldwide Ltd is the data controller for the personal data collected
through GoOuts Host.

What we collect
Your name, date of birth and contact details. Your mobile number, used to
sign you in. Identity documents and a selfie, used to verify who you are.
Your property address and listing details. Payout details, handled by our
payment provider.

Why we collect it
To verify that you are who you say you are and are entitled to let the
property, to publish your listing, to process bookings, and to meet legal
obligations including tax reporting.

How long we keep it
Verification records are kept for as long as you host with us and for six
years afterwards, which is the period HMRC may require.

Your rights
Under UK GDPR you can ask for a copy of your data, ask us to correct it, or
ask us to delete it where we are not required to keep it.

Contact
Write to us in the app under Help, or email the address shown on the GoOuts
website.
''';

  void _showLegalSheet({required bool terms}) {
    final String title =
        terms ? 'Terms & Conditions' : 'Privacy Policy';
    final String body = terms
        ? (_hostTermsFromDb ?? _fallbackTerms)
        : (_hostPrivacyFromDb ?? _fallbackPrivacy);

    showModalBottomSheet<void>(
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
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0D1B3E),
                      ),
                    ),
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
                  body,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToHomeForExistingUser(User user) async {
    final firestore = FirebaseFirestore.instance;
    // Only /stay_hosts is read here.
    //
    // driver_app also checked /drivers and /cab_drivers, because it had a home
    // screen for each. This app does not — and the important consequence is
    // that a courier who ALSO wants to let out a property is treated as a new
    // host, not turned away. One phone number can hold both roles; they live
    // in different collections and neither blocks the other.
    //
    // ⚠ CHANGED 8 August 2026 from /businesses. That was the driver LEAD
    // business partner collection and hosts never belonged in it — see
    // host_collection.dart. Reading it here meant a lead partner who had
    // never heard of Short Stay would be signed straight into the host app.
    final DocumentSnapshot business;
    try {
      business =
          await firestore.collection(kStayHostsCollection).doc(user.uid).get();
    } catch (e) {
      if (!mounted) return;
      await _showErrorDialog('Connection Error',
          'Could not reach the server. Please check your connection and try again.\n\n$e');
      return;
    }
    if (!mounted) return;

    if (business.exists) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HostHomeScreen()),
        (route) => false,
      );
    } else {
      // No host record yet — start enrolment. KYC is mandatory and is enforced
      // server-side too: createStayListing rejects any uid whose /businesses
      // kycStatus is not approved, so there is no way to skip this and reach
      // the listing wizard.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const BusinessReferralCodeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handlePasswordLogin() async {
    if (_isLoading) return;

    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    FocusScope.of(context).unfocus();

    final String localMobile = _mobileController.text.trim();
    final String e164 = _toE164Number(localMobile);
    final String emailForAuth =
        '${e164.replaceAll('+', '').replaceAll(' ', '')}@goouts.app';

    setState(() => _isLoading = true);

    try {
      final UserCredential credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailForAuth,
        password: _passwordController.text,
      );

      // Mirror the OTP flow — save account type so main.dart routes correctly
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingAccountTypeKey, _selectedAccountType);

      if (!mounted) return;

      final User? user = credential.user;
      if (user != null) {
        await _navigateToHomeForExistingUser(user);
      } else {
        // Credential returned no user — unexpected. Show error instead of
        // crashing to splash.
        if (!mounted) return;
        await _showErrorDialog('Login Failed', 'Could not retrieve your account. Please try OTP login.');
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          message =
              'Incorrect PIN. Please try again or tap "Forgot PIN?" to reset via OTP.';
        case 'user-not-found':
          message =
              'No account linked to this number. Please use OTP login.';
        case 'too-many-requests':
          message = 'Too many attempts. Please wait a moment and try again.';
        default:
          message = e.message ?? 'Something went wrong. Please try again.';
      }
      await _showErrorDialog('Login Failed', message);
    } catch (e) {
      if (!mounted) return;
      await _showErrorDialog('Error', 'Login failed.\n\n$e');
    } finally {
      // `if (!mounted) return;` here would swallow any exception thrown inside
      // the try — a bare return in a finally block discards the in-flight
      // throw, so it never reaches Crashlytics. Guarding the setState instead
      // does the same job without eating the error.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _forgotPin() {
    setState(() {
      _isReturningUser = false;
      _passwordController.clear();
    });
  }

  Future<void> _completeVerificationFlow() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingAccountTypeKey, _selectedAccountType);

    if (!mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // See _navigateToHomeForExistingUser — only /stay_hosts is consulted.
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final DocumentSnapshot<Map<String, dynamic>> business =
        await firestore.collection(kStayHostsCollection).doc(user.uid).get();

    if (!mounted) return;

    // Release the guard just before navigation so _HostLaunchCoordinator
    // doesn't interfere while we pushAndRemoveUntil.
    AuthFlowGuard.end();

    if (business.exists) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HostHomeScreen()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const BusinessReferralCodeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handleContinue() async {
    if (_isLoading) return;

    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    // ── LEGAL GATE ─────────────────────────────────────────────────────────
    //
    // Checked BEFORE sendOtp, not after. An SMS costs money and, more to the
    // point, sending one means Firebase has already accepted the phone number
    // — so a host who had not agreed to anything would be part way into an
    // account before being asked.
    //
    // Returning users skip it: they agreed at signup.
    if (!_isReturningUser && !_acceptedLegal) {
      setState(() => _showLegalError = true);
      await _showErrorDialog(
        'Please accept the terms',
        'Tick the box to confirm you agree to the Terms & Conditions and '
            'Privacy Policy before continuing.',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    final String localMobile = _mobileController.text.trim();
    final String e164PhoneNumber = _toE164Number(localMobile);

    // Cancel auth subscription and activate flow guard BEFORE any Firebase
    // activity. The guard prevents AppLaunchCoordinator's StreamBuilder from
    // swapping DriverSplashScreen → AuthProfileGate mid-flow.
    _authSubscription?.cancel();
    _authSubscription = null;
    AuthFlowGuard.start();

    setState(() => _isLoading = true);

    await _authService.sendOtp(
      phoneNumber: e164PhoneNumber,
      onCodeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(
              arguments: <String, dynamic>{
                'accountType': _selectedAccountType,
              },
            ),
            builder: (_) => OtpVerificationScreen(
              verificationId: verificationId,
              phoneNumber: e164PhoneNumber,
              localMobileNumber: localMobile,
              resendToken: resendToken,
            ),
          ),
        );
      },
      onAutoVerified: () async {
        if (!mounted) return;
        setState(() => _isLoading = false);
        await _completeVerificationFlow();
      },
      onError: (String message) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        if (context.mounted) _showErrorDialog('OTP Failed', message);
      },
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _goOutsBlue, width: 1.4),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Colors.red, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
    );
  }

  /// ── SAYS "HOST", BECAUSE THIS IS THE HOST APP ──────────────────────────
  ///
  /// This read "Business Partner login" until 8 August 2026. It was
  /// inherited verbatim from driver_app, where the same screen serves
  /// couriers and business partners and the line tells you which one you
  /// are signing in as.
  ///
  /// Here there is only one kind of account, so the line answered a question
  /// nobody asked and answered it with the wrong word. Someone signing up to
  /// let a property was told they were logging in as a Business Partner,
  /// with no explanation of what that meant or why.
  ///
  /// The underlying record IS still a /businesses record — that part of the
  /// design is deliberate and unchanged. This is what the host is called,
  /// not what the database calls them.
  String _accountTypeHelperText() => 'Host sign in';

  @override
  Widget build(BuildContext context) {
    // ── ⚠ RESKINNED 10 August 2026 TO MATCH goouts_app's SIGN-IN. ──────────
    //
    // Was a white screen with role_icon.png and black text. goouts_app uses a
    // full-bleed GoOuts blue field, the "GoOuts" wordmark, a rounded hero
    // photograph, then white headings — and a host who has also used GoOuts as
    // a customer should recognise the door they are walking through.
    //
    // Only the PRESENTATION changed. Every behaviour underneath is untouched:
    // returning-user detection, PIN sign-in, Forgot PIN via OTP, AuthFlowGuard,
    // and the routing to BusinessReferralCodeScreen or HostHomeScreen. That is
    // deliberate — this screen took roughly twenty builds to get right and none
    // of that was a styling problem.
    //
    // Left-aligned, not centred, because goouts_app is left-aligned and the
    // two screens sitting side by side would otherwise read as different apps.
    return Scaffold(
      backgroundColor: _goOutsBlue,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SizedBox(height: 8),
                          Text(
                            'GoOuts',
                            style: GoogleFonts.inter(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/signup_hero.webp',
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              // The asset is declared in pubspec and shipped,
                              // but a missing file must not take the sign-in
                              // screen down — without this a failed decode
                              // throws inside build() and nobody can log in.
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 26),
                          AutoSizeText(
                            _isReturningUser
                                ? 'Welcome Back!'
                                : 'Enter your mobile number',
                            textAlign: TextAlign.left,
                            style: GoogleFonts.inter(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          AutoSizeText(
                            // "GoOuts Host", not "GoOuts" — this is the one
                            // place the two apps deliberately differ, so a host
                            // can tell at a glance which app they opened.
                            _isReturningUser
                                ? 'Welcome back to GoOuts Host.'
                                : "We'll send you a verification code to get "
                                    'you started as a host.',
                            textAlign: TextAlign.left,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.85),
                              height: 1.45,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          SizedBox(height: 10),
                          AutoSizeText(
                            _accountTypeHelperText(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _goOutsBlue,
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 34),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: <Widget>[
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    SizedBox(
                                      width: 120,
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        onTap: () async {
                                          final String? result =
                                              await showDialog<String>(
                                            context: context,
                                            builder:
                                                (BuildContext context) {
                                              return SimpleDialog(
                                                title: const Text(
                                                  'Select country',
                                                ),
                                                children: <Widget>[
                                                  SimpleDialogOption(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context,
                                                            'UK'),
                                                    child: const Text(
                                                      '🇬🇧  United Kingdom (+44)',
                                                    ),
                                                  ),
                                                  SimpleDialogOption(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context,
                                                            'IE'),
                                                    child: const Text(
                                                      '🇮🇪  Ireland (+353)',
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          );

                                          if (result == null) {
                                            return;
                                          }

                                          // showDialog was awaited, so the
                                          // screen may have gone away while it
                                          // was open. setState on a disposed
                                          // State throws.
                                          if (!mounted) {
                                            return;
                                          }

                                          setState(() {
                                            if (result == 'UK') {
                                              _selectedFlag = '🇬🇧';
                                              _selectedDialCode = '+44';
                                            } else if (result == 'IE') {
                                              _selectedFlag = '🇮🇪';
                                              _selectedDialCode = '+353';
                                            }
                                          });
                                        },
                                        child: InputDecorator(
                                          decoration:
                                              _inputDecoration('Code'),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment
                                                    .spaceBetween,
                                            children: <Widget>[
                                              AutoSizeText(
                                                '$_selectedFlag $_selectedDialCode',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                              const Icon(
                                                Icons
                                                    .arrow_drop_down_rounded,
                                                color: Colors.black54,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _mobileController,
                                        keyboardType: TextInputType.phone,
                                        textInputAction:
                                            TextInputAction.done,
                                        onFieldSubmitted: (_) =>
                                            _handleContinue(),
                                        inputFormatters:
                                            <TextInputFormatter>[
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(
                                            _selectedDialCode == '+353' ? 10 : 11,
                                          ),
                                        ],
                                        decoration: _inputDecoration(
                                          'Mobile Number',
                                        ).copyWith(
                                          hintText: _selectedDialCode == '+353' ? '0851234567' : '07123456780',
                                          counterText: '',
                                        ),
                                        validator: _mobileValidator,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_isReturningUser) ...<Widget>[
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    keyboardType: TextInputType.number,
                                    maxLength: 4,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    style: const TextStyle(
                                        letterSpacing: 10, fontSize: 18),
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) =>
                                        _handlePasswordLogin(),
                                    decoration:
                                        _inputDecoration('4-digit PIN').copyWith(
                                      counterText: '',
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          color: Colors.black54,
                                        ),
                                        onPressed: () => setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        }),
                                      ),
                                    ),
                                    validator: (String? value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'PIN is required';
                                      }
                                      return null;
                                    },
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _forgotPin,
                                      style: TextButton.styleFrom(
                                        foregroundColor: _goOutsBlue,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: AutoSizeText(
                                        'Forgot PIN?',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : (_isReturningUser
                                            ? _handlePasswordLogin
                                            : _handleContinue),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _goOutsBlue,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? SizedBox(
                                            height: 22,
                                            width: 22,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: Colors.white,
                                            ),
                                          )
                                        : AutoSizeText(
                                            'Continue',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 22),
                          if (!_isReturningUser)
                          AutoSizeText(
                            'You will receive a one-time verification code by SMS.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              // White-on-blue since the reskin. Was black45,
                              // which is invisible on the new background.
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),

                          // ── LEGAL — A TICK BOX, NOT A SENTENCE ─────────────
                          //
                          // MOVED HERE 8 August 2026 from the registration
                          // screen, at Mian's request, and it belongs here.
                          //
                          // It used to be a passive line — "By continuing, you
                          // agree to our Terms" — on this screen, with the
                          // actual tick box buried in a section card two
                          // screens later, most of the way down a long form.
                          //
                          // That is the wrong order twice over. The host had
                          // already handed over their phone number, received
                          // an SMS code and typed their name, address and
                          // company number BEFORE being asked to agree to
                          // anything. And a passive "by continuing" line is a
                          // weaker record of consent than a box somebody
                          // deliberately ticked.
                          //
                          // Now: nothing happens until it is ticked. The
                          // Continue button below is disabled until then, so
                          // no phone number is submitted and no SMS is sent
                          // before the host has agreed.
                          //
                          // Both documents are linked, not just terms. A host
                          // hands over identity documents and a property
                          // address, so the privacy policy is the one they are
                          // more likely to want before typing anything.
                          //
                          // Returning users do not see it — they agreed when
                          // they signed up, and re-asking implies the terms
                          // changed when they have not.
                          if (!_isReturningUser) ...<Widget>[
                            const SizedBox(height: 18),
                            InkWell(
                              onTap: () => setState(() {
                                _acceptedLegal = !_acceptedLegal;
                                _showLegalError = false;
                              }),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _showLegalError
                                      ? Colors.red.withValues(alpha: 0.04)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _showLegalError
                                        ? Colors.red.shade300
                                        : (_acceptedLegal
                                            ? _goOutsBlue
                                            : Colors.grey.shade300),
                                    width: _acceptedLegal ? 1.4 : 1,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    // Not a bare Checkbox: the whole box is
                                    // tappable, which matters for an audience
                                    // our own brief calls "often older and
                                    // less confident with apps". The links
                                    // inside still work independently.
                                    SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: Checkbox(
                                        value: _acceptedLegal,
                                        activeColor: _goOutsBlue,
                                        onChanged: (bool? v) => setState(() {
                                          _acceptedLegal = v ?? false;
                                          _showLegalError = false;
                                        }),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.black87,
                                            height: 1.5,
                                          ),
                                          children: <InlineSpan>[
                                            const TextSpan(
                                                text: 'I agree to the '),
                                            TextSpan(
                                              text: 'Terms & Conditions',
                                              recognizer:
                                                  TapGestureRecognizer()
                                                    ..onTap = () =>
                                                        _showLegalSheet(
                                                            terms: true),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: _goOutsBlue,
                                                decoration:
                                                    TextDecoration.underline,
                                                decorationColor: _goOutsBlue,
                                              ),
                                            ),
                                            const TextSpan(text: ' and the '),
                                            TextSpan(
                                              text: 'Privacy Policy',
                                              recognizer:
                                                  TapGestureRecognizer()
                                                    ..onTap = () =>
                                                        _showLegalSheet(
                                                            terms: false),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: _goOutsBlue,
                                                decoration:
                                                    TextDecoration.underline,
                                                decorationColor: _goOutsBlue,
                                              ),
                                            ),
                                            const TextSpan(text: '.'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showLegalError) ...<Widget>[
                              const SizedBox(height: 6),
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text(
                                  'Please accept the Terms & Conditions and '
                                  'Privacy Policy to continue.',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],

                          // ── ALREADY HAVE AN ACCOUNT ────────────────────────
                          //
                          // In this app one screen does both jobs: the same
                          // phone number and OTP either signs you in or starts
                          // enrolment, depending on whether a /businesses
                          // record exists. There is nothing to switch to.
                          //
                          // ⚠ REWRITTEN 8 August 2026. This used to render
                          // "Sign in" in bold GoOuts blue — which is exactly
                          // how every tappable link in this app looks. It was
                          // never tappable, because there is nowhere for it to
                          // go, and the first person to test the app on a real
                          // phone reported it as a broken login button. That
                          // is the correct reading: something that looks like
                          // a link and does nothing is a bug, whatever the
                          // intention behind it.
                          //
                          // It now states the fact plainly in ordinary body
                          // text, with no link styling anywhere. The
                          // reassurance survives; the false affordance does
                          // not.
                          if (!_isReturningUser) ...<Widget>[
                            const SizedBox(height: 18),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(
                                      Icons.info_outline_rounded,
                                      size: 16,
                                      color: Colors.black38,
                                    ),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Already have an account? Enter the same '
                                        'mobile number above — signing in and '
                                        'signing up are the same step here, and '
                                        'you will not create a second account.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),
                          Center(
                            child: GestureDetector(
                              onTap: () => showPreAuthSupportSheet(
                                context,
                                accountType: _selectedAccountType,
                              ),
                              // NOT const. Colors.white70 is a const value;
                              // Colors.white.withValues(alpha: …) is a method
                              // call and cannot appear in a const expression —
                              // which is exactly what the analyzer caught when
                              // this was reskinned. white70 is the same
                              // intended weight and keeps the widget const.
                              child: const Text(
                                'Having trouble? Get help',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white54,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

           