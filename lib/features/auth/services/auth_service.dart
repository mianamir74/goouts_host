import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Send OTP to a phone number in E.164 format (e.g. +447911123456).
  /// Mirrors the working pattern used in the GoOuts consumer app.
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function() onAutoVerified,
    required void Function(String message) onError,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        // TEMP FIX (build 527): DO NOT auto-sign-in here anymore.
        // This callback stays alive in the background even after the user
        // navigates to OtpVerificationScreen (LoginScreen's State is just
        // buried under the pushed route, not disposed). If Firebase's
        // silent-push auto-verification arrives late - common and exactly
        // matches the variable 3-13s delay seen before every OTP-Continue
        // crash - this fired a SECOND, concurrent signInWithCredential call
        // at the same time as the user's own manual one on the OTP screen.
        // Two simultaneous credential-exchange calls racing in Firebase's
        // native iOS SDK is a known class of bug (matches upstream
        // firebase-ios-sdk reports of concurrent auth RPCs causing native
        // memory/lock blowups) and fits every symptom we've seen: always
        // the same call, uncatchable by app code, reproducible every time.
        // This app's UX always wants manual code entry anyway, so dropping
        // the auto-verified credential here is zero downside.
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (FirebaseAuthException e) {
          onError(e.message ?? 'Failed to send OTP. Please try again.');
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      onError(
        'Could not send verification code. '
        'Please check your connection and try again.',
      );
    }
  }

  /// Resend OTP using the resend token.
  Future<void> resendOtp({
    required String phoneNumber,
    required int? resendToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onError,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: resendToken,
        verificationCompleted: (_) {},
        verificationFailed: (FirebaseAuthException e) {
          onError(e.message ?? 'Failed to resend OTP.');
        },
        codeSent: (String verificationId, int? newResendToken) {
          onCodeSent(verificationId, newResendToken);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      onError('Could not resend code. Please check your connection and try again.');
    }
  }

  User? get currentUser => _auth.currentUser;
  Future<void> signOut() => _auth.signOut();
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
