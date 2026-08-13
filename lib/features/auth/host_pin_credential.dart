// The two values that turn a host's phone + PIN into a Firebase credential.
//
// ── WHY THIS FILE EXISTS ─────────────────────────────────────────────────
//
// 11 August 2026. Reported as "no matter what 4 digit pin I choose, it always
// says the PIN was refused".
//
// THE ROOT CAUSE: Firebase Auth requires a password of AT LEAST 6 CHARACTERS.
// A 4-digit PIN is four. Every call that passed the raw PIN straight to
// EmailAuthProvider.credential therefore threw weak-password — always, for
// everyone, since the day PIN sign-in was written.
//
// That includes _linkEmailPasswordCredential at registration, which wraps the
// whole thing in `catch (_) { /* ignore */ }`. So the link failed silently for
// every host who ever registered, no host ever had a password credential, and
// PIN sign-in could never have worked for anybody. The "Login Failed" reports
// were not an edge case — they were the only possible outcome.
//
// ── THE FIX ──────────────────────────────────────────────────────────────
//
// Derive a longer password from the PIN, deterministically, so the same PIN
// always produces the same password. Nothing is stored anywhere.
//
// The prefix is not a secret and is not pretending to be one. It only exists
// to clear Firebase's length rule. A 4-digit PIN has 10,000 combinations
// whatever we wrap it in — the real protection is Firebase's own rate
// limiting on repeated sign-in failures, plus the fact that the synthetic
// email is derived from a phone number the attacker must also know.
//
// ── ⚠ THE ONE RULE ───────────────────────────────────────────────────────
//
// EVERY site that creates, checks or changes a host PIN must call these two
// functions. There are four:
//
//   business_registration_screen  _linkEmailPasswordCredential   (create)
//   login_screen                  signInWithEmailAndPassword     (check)
//   host_change_pin_screen        link / reauthenticate + update (change)
//
// If one of them ever computes the email or password inline again, hosts who
// set a PIN on one screen will be unable to use it on another, and the
// failure will look exactly like a wrong PIN. That is the bug this file was
// created to make impossible — the same class as the unreadByUser /
// unreadByDriver split on support tickets.
//
// ── MIGRATION ────────────────────────────────────────────────────────────
//
// Safe to introduce with no migration path. Because the raw-PIN version could
// never succeed, there are ZERO existing password credentials to invalidate.
// Verified before writing this: the only caller at registration swallowed its
// error, and both other callers are new this week.
library;

/// The synthetic address a host's credential is linked to.
///
/// Derived from the phone number so nothing extra has to be stored. Must
/// match on every screen — a mismatch reads as "no such account", which under
/// Firebase's email-enumeration protection is reported as invalid-credential,
/// i.e. indistinguishable from a wrong PIN.
String hostAuthEmail(String phoneNumber) =>
    '${phoneNumber.replaceAll('+', '').replaceAll(' ', '')}@goouts.app';

/// The password Firebase actually stores for a given 4-digit PIN.
///
/// Firebase minimum is 6 characters; this returns 11. Do not shorten it and
/// do not change the prefix — either would lock out every host who has set a
/// PIN since this shipped.
String hostPinPassword(String pin) => 'GoOutsPin-${pin.trim()}';
