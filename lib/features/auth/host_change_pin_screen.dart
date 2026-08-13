// Change PIN.
//
// ── ⚠ NOT A PORT OF goouts_app's profile_security_screen. ─────────────────
//
// Created 10 August 2026. The consumer app stores a HASHED pin in
// /users/{uid}.pin via PinHasher, checks the old one by comparing hashes, and
// writes the new hash with UserService. Copying that here would produce a
// screen that appears to work and changes nothing that anyone signs in with.
//
// A HOST'S PIN IS THE FIREBASE AUTH PASSWORD. Registration links an
// EmailAuthProvider credential using a synthetic address derived from the
// phone number (see _linkEmailPasswordCredential in
// business_registration_screen), and login_screen signs in with
// signInWithEmailAndPassword against it. So changing the PIN means
// reauthenticate, then updatePassword — nothing is written to Firestore at
// all.
//
// ── WHY REAUTHENTICATE ───────────────────────────────────────────────────
//
// Firebase requires a recent sign-in before updatePassword and throws
// requires-recent-login otherwise. That is also the security property we
// want: someone who picks up an unlocked phone must not be able to change the
// PIN without knowing the current one and lock the real host out.
//
// So the current PIN is not merely compared — it is used to reauthenticate.
// A wrong one fails at Firebase, not at us.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/goouts_colors.dart';
import '../short_stay/host/host_routes.dart';
import 'host_pin_credential.dart';

class HostChangePinScreen extends StatefulWidget {
  const HostChangePinScreen({super.key});

  @override
  State<HostChangePinScreen> createState() => _HostChangePinScreenState();
}

class _HostChangePinScreenState extends State<HostChangePinScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _saving = false;
  String? _error;

  // ── DOES THIS ACCOUNT EVEN HAVE A PIN? ─────────────────────────────────
  //
  // ADDED 10 August 2026. This screen assumed one always existed, so it
  // reauthenticated with the current PIN and called updatePassword.
  //
  // Hosts who registered before PIN linking existed — or whose link silently
  // failed, because _linkEmailPasswordCredential in business_registration
  // swallows every error — have NO password provider on their account. For
  // them reauthenticate fails, so they could never set a PIN, so they could
  // never use PIN sign-in, so every login went through SMS forever.
  //
  // With no provider we LINK a credential instead of updating one, and the
  // "current PIN" field is hidden because there is nothing to type.
  bool get _hasPin =>
      FirebaseAuth.instance.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// The synthetic address the account's credential is linked to.
  ///
  /// MUST match business_registration_screen and login_screen exactly. If one
  /// of the three ever changes format, reauthentication fails here with
  /// user-not-found and nobody will be able to change their PIN.
  String? _authEmail(User user) {
    final phone = user.phoneNumber;
    if (phone == null || phone.isEmpty) return null;
    return hostAuthEmail(phone);
  }

  Future<void> _save() async {
    final current = _currentCtrl.text.trim();
    final next = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    final setting = !_hasPin; // first-time set, not a change

    setState(() => _error = null);

    if (!setting && current.length < 4) {
      setState(() => _error = 'Enter your current 4-digit PIN.');
      return;
    }
    if (next.length < 4) {
      setState(() => _error = 'Your new PIN must be 4 digits.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'The two new PINs do not match.');
      return;
    }
    if (!setting && next == current) {
      setState(() => _error = 'That is your current PIN. Choose a new one.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'You are signed out. Please sign in again.');
      return;
    }
    final email = _authEmail(user);
    if (email == null) {
      setState(() => _error =
          'This account has no phone number on it, so the PIN cannot be '
          'changed here. Contact support.');
      return;
    }

    setState(() => _saving = true);
    try {
      // Reauthenticate with the CURRENT pin, then set the new one. Both steps
      // are required: updatePassword alone throws requires-recent-login for
      // anyone who has not signed in in the last few minutes.
      if (setting) {
        // No password provider yet — create one. linkWithCredential is the
        // only call that works here; updatePassword needs a credential to
        // already exist, and reauthenticate needs one to check against.
        await user.linkWithCredential(
          EmailAuthProvider.credential(
              email: email, password: hostPinPassword(next)),
        );
      } else {
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
              email: email, password: hostPinPassword(current)),
        );
        await user.updatePassword(hostPinPassword(next));
      }

      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_hasPin
            ? 'PIN changed. Use the new one next time you sign in.'
            : 'PIN set. You can sign in with it next time.'),
        backgroundColor: GoOutsColors.success,
      ));
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e.code) {
          'wrong-password' || 'invalid-credential' =>
            'That is not your current PIN.',
          // Should now be unreachable — hostPinPassword always clears
          // Firebase's 6-character minimum. Kept honest rather than guessing
          // at digit patterns, which is what the old wording did and it sent
          // people hunting for a rule that never existed.
          'weak-password' =>
            'Firebase refused that PIN. Please contact support — this should '
                'not happen.',
          'too-many-requests' =>
            'Too many attempts. Wait a few minutes and try again.',
          'user-not-found' =>
            'No PIN is set on this account yet. Sign in with a text code '
                'instead, or contact support.',
          'provider-already-linked' || 'credential-already-in-use' =>
            'A PIN already exists on this account. Close this screen and open '
                'it again.',
          'requires-recent-login' =>
            'For security, please sign out and sign in again, then set your '
                'PIN straight away.',
          _ => e.message ?? 'Could not change your PIN. Please try again.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not change your PIN. Check your connection and try '
            'again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GoOutsColors.background,
      appBar: AppBar(
        backgroundColor: GoOutsColors.surface,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GoOutsColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_hasPin ? 'Change PIN' : 'Set your PIN',
            style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GoOutsColors.infoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: GoOutsColors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.lock_outline_rounded,
                    size: 18, color: GoOutsColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _hasPin
                        ? 'Your PIN signs you in without waiting for a text '
                            'message. Changing it takes effect straight away.'
                        : 'You do not have a PIN yet, so every sign-in needs a '
                            'text code. Set one here and you can sign straight '
                            'in next time.',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: GoOutsColors.body, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          // Nothing to confirm against when no PIN exists yet.
          if (_hasPin) ...<Widget>[
            _label('CURRENT PIN'),
            _pinField(_currentCtrl, _obscureCurrent,
                () => setState(() => _obscureCurrent = !_obscureCurrent)),
            const SizedBox(height: 18),
          ],
          _label(_hasPin ? 'NEW PIN' : 'CHOOSE A PIN'),
          _pinField(_newCtrl, _obscureNew,
              () => setState(() => _obscureNew = !_obscureNew)),
          const SizedBox(height: 18),
          _label(_hasPin ? 'CONFIRM NEW PIN' : 'CONFIRM PIN'),
          // Shares the new-PIN visibility toggle rather than having its own —
          // two independent eyes on two boxes that must match is fiddly, and
          // people end up comparing one masked field with one visible one.
          _pinField(_confirmCtrl, _obscureNew,
              () => setState(() => _obscureNew = !_obscureNew)),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GoOutsColors.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.error_outline_rounded,
                      size: 17, color: GoOutsColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: GoOutsColors.navy,
                            height: 1.4)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: GoOutsColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_hasPin ? 'Update PIN' : 'Set PIN',
                      style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
            ),
          ),
          const SizedBox(height: 14),
          if (_hasPin)
            Center(
              child: GestureDetector(
                onTap: () =>
                    Navigator.of(context).pushNamed(HostRoutes.contactSupport),
                child: Text(
                  'Forgotten your current PIN?',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: GoOutsColors.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text(text,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: GoOutsColors.onSurfaceVariant,
                letterSpacing: 0.6)),
      );

  Widget _pinField(
          TextEditingController ctrl, bool obscure, VoidCallback onToggle) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        style: GoogleFonts.inter(
            fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 8),
        decoration: InputDecoration(
          counterText: '',
          hintText: '••••',
          filled: true,
          fillColor: GoOutsColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GoOutsColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GoOutsColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: GoOutsColors.primary, width: 1.5),
          ),
          suffixIcon: IconButton(
            icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: GoOutsColors.onSurfaceVariant,
                size: 20),
            onPressed: onToggle,
          ),
        ),
      );
}
