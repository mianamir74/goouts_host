import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/host_home_screen.dart';
import 'auth_flow_guard.dart';
import 'business_referral_code_screen.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:goouts_host/features/common/goouts_sheet.dart';

import '../short_stay/host/host_collection.dart';
import 'host_change_pin_screen.dart';
class OtpVerificationScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final String localMobileNumber;
  final int? resendToken;

  /// True when this OTP came from "Forgot PIN?" rather than a normal sign-in.
  ///
  /// ADDED 11 August 2026. The Forgot-PIN flow sent a code, verified it, and
  /// then dropped the host on the dashboard with their PIN completely
  /// unchanged. The button says "We'll send a reset code" and the sheet is
  /// titled "Forgot PIN?", so the host reasonably expects to end up setting a
  /// new one. Nothing reset. They were simply signed in.
  ///
  /// Worse, the host who most needs this is the one with NO pin at all — for
  /// them the old flow was a loop: cannot sign in with a PIN, use Forgot PIN,
  /// land on the dashboard, still no PIN, same failure next time.
  ///
  /// With this flag we land on Change PIN instead, which knows how to SET a
  /// first PIN as well as change an existing one.
  final bool resetPin;

  const OtpVerificationScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    required this.localMobileNumber,
    required this.resendToken,
    this.resetPin = false,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const Color _goOutsBlue = Color(0xFF0392CA);
  static const String _pendingAccountTypeKey = 'pending_account_type';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _otpController = TextEditingController();

  late String _verificationId;
  int? _resendToken;
  bool _isVerifying = false;
  bool _isResending = false;
  bool _hasReadRouteArgs = false;
  bool _hasNavigated = false; // guard against double navigation (verificationCompleted + manual OTP race)
  // Constant in this app — see login_screen. Only used for the
  // `pending_account_type` preference and the on-screen label.
  final String _accountType = 'business';

  // Visible on-screen status — shows exactly which step is running right now.
  // Two Jetsam memory-kill logs on this exact flow gave no stack trace, and
  // Crashlytics is currently blocked on a dSYM upload, so this is the fastest
  // way to see (with your own eyes) which step the app reaches before it dies.
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_hasReadRouteArgs) {
      return;
    }

    _hasReadRouteArgs = true;

    // Nothing to read. _accountType is constant in this app — see its
    // declaration. Kept as an override of didChangeDependencies only so the
    // _hasReadRouteArgs latch above still behaves the same way.
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  String? _otpValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'OTP is required';
    }

    final String cleaned = value.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) {
      return 'Enter the 6-digit OTP';
    }

    return null;
  }

  String _firebaseErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-verification-code':
        return 'The OTP you entered is invalid.';
      case 'session-expired':
        return 'The OTP has expired. Please request a new code.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'invalid-phone-number':
        return 'The mobile number format is invalid.';
      case 'quota-exceeded':
        return 'SMS quota exceeded for this project. Please try again later.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePendingAccountType() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingAccountTypeKey, _accountType);
  }

  String _accountTypeText() => 'Host';

  // Breadcrumbs — written to disk immediately by Crashlytics (for later), AND
  // shown on screen right now (for immediate visual confirmation of exactly
  // which step the app reaches before it dies — no logs or console needed).
  void _bc(String step) {
    FirebaseCrashlytics.instance.log('OTP-VERIFY: $step');
    if (mounted) {
      setState(() {
        _statusText = step;
      });
    }
  }

  Future<void> _completeSuccessfulVerification() async {
    // Guard against double navigation (verificationCompleted firing after codeSent on Android)
    if (_hasNavigated) return;
    _hasNavigated = true;

    _bc('completeVerification: start');
    await _savePendingAccountType();
    _bc('completeVerification: saved pending account type');

    if (!mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    _bc('completeVerification: currentUser=${user?.uid ?? "null"}');

    if (user == null) {
      // Sign-in completed but no user returned — release guard and pop to root
      AuthFlowGuard.end();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    // Check if this is an existing user (forgot password / re-login)
    // or a brand new signup that still needs registration.
    //
    // RESTORED (build 527): builds 521-523 conclusively cleared Firestore as
    // a suspect (skipping it entirely still crashed at the same point) and
    // build 527 fixes the real cause (a concurrent signInWithCredential race
    // — see services/auth_service.dart), so the diagnostic bypass that
    // misrouted every sign-in as brand-new is no longer needed and would
    // have broken returning-user routing in production. Kept the sequential
    // queries + per-call timeout from the bisection as a harmless permanent
    // safety net.
    // GoOuts Host reads ONE collection, not three.
    //
    // driver_app queried /drivers, /cab_drivers and /businesses because it
    // routes to a different home screen for each. This app has one home. The
    // two dropped queries also cost two sequential round trips with a 6-second
    // timeout each — on a bad connection that was up to 12 seconds of a user
    // staring at a spinner directly after entering their code.
    _bc('completeVerification: querying stay_hosts');
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final DocumentSnapshot<Map<String, dynamic>> businessResult = await firestore
        .collection(kStayHostsCollection)
        .doc(user.uid)
        .get()
        .timeout(const Duration(seconds: 6));
    _bc('completeVerification: firestore lookup done');

    if (!mounted) return;

    // Release guard just before navigation.
    AuthFlowGuard.end();

    if (businessResult.exists) {
      // Forgot-PIN journey: finish where the host expected to finish.
      //
      // Pushed ON TOP of the dashboard, not instead of it, so closing the PIN
      // screen leaves them signed in rather than back at login. Someone who
      // changes their mind should not be punished for it.
      if (widget.resetPin) {
        _bc('completeVerification: navigating to Change PIN (reset flow)');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HostHomeScreen()),
          (route) => false,
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HostChangePinScreen()),
        );
        _bc('completeVerification: navigation call returned');
        return;
      }
      _bc('completeVerification: navigating to HostHomeScreen');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HostHomeScreen()),
        (route) => false,
      );
    } else {
      // New host — straight into enrolment. KYC is mandatory.
      _bc('completeVerification: navigating to BusinessReferralCodeScreen');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const BusinessReferralCodeScreen()),
        (route) => false,
      );
    }
    _bc('completeVerification: navigation call returned');
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      _bc('verifyOtp: building credential');
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _otpController.text.trim(),
      );

      _bc('verifyOtp: calling signInWithCredential');
      // Timeout added as a safety net — if Firebase's native handshake here
      // hangs/spins instead of returning cleanly (our leading theory for the
      // repeated ~3GB memory blow-up on this exact call), this at least stops
      // OUR code from waiting forever and surfaces a catchable error instead
      // of the app going blank and dying.
      await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 8));
      _bc('verifyOtp: signInWithCredential returned successfully');

      await _completeSuccessfulVerification();
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        'Verification Failed',
        _firebaseErrorMessage(e),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        'Error',
        'Failed to verify OTP.\n\n$e',
      );
    } finally {
      // A `return` inside `finally` silently discards whatever the try/catch
      // above was doing (a real Dart footgun, flagged by the analyzer) — use
      // a plain `if (mounted)` guard instead of returning out of finally.
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _isResending = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        forceResendingToken: _resendToken,
        timeout: const Duration(seconds: 60),
        // TEMP FIX (build 527): don't auto-sign-in on resend either — see
        // services/auth_service.dart for why. Same race is possible here:
        // user resends, then manually types the new code and hits Continue
        // (_verifyOtp) while this callback is still alive in the background.
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (FirebaseAuthException e) async {
          if (!mounted) {
            return;
          }

          await _showErrorDialog(
            'Resend Failed',
            _firebaseErrorMessage(e),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) {
            return;
          }

          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
          });

          GoOutsSheet.info(context, title: 'Code Sent', message: 'A new OTP has been sent to your phone.');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) {
            return;
          }

          _verificationId = verificationId;
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        'Resend Failed',
        _firebaseErrorMessage(e),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        'Error',
        'Failed to resend OTP.\n\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _goOutsBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Verify OTP',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 12),
              Image.asset(
                'assets/logo/goouts_logo_white.png',
                height: 160,
                fit: BoxFit.contain,
                color: _goOutsBlue,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.verified_user_rounded,
                  size: 80,
                  color: _goOutsBlue,
                ),
              ),
              SizedBox(height: 24),
              AutoSizeText(
                'Enter Verification Code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 10),
              AutoSizeText(
                'We sent a 6-digit code to ${widget.localMobileNumber}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 10),
              AutoSizeText(
                'You are continuing as a ${_accountTypeText()}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black45,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 30),
              AutofillGroup(
                child: Form(
                key: _formKey,
                child: TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 6,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: _inputDecoration('6-digit OTP').copyWith(
                    hintText: '123456',
                    hintStyle: const TextStyle(letterSpacing: 4),
                  ),
                  validator: _otpValidator,
                ),
              ),
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _goOutsBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isVerifying
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : AutoSizeText(
                          'Verify & Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              if (_isVerifying && _statusText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Text(
                    'DEBUG STEP: $_statusText',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isResending || _isVerifying ? null : _resendCode,
                child: _isResending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Resend OTP',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}