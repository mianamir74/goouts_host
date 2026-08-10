// Turns a caught error into something a host should actually read.
//
// ── WHY THIS EXISTS ────────────────────────────────────────────────────────
//
// Created 9 August 2026, after a host tapped "Save my property" and got this
// on screen, in red, filling the phone:
//
//     Your identity check is still being reviewed. You can add a property as
//     soon as it is approved.
//
//     #0  _extractReplyValueOrThrow (package:cloud_functions_platform_interface
//         /src/pigeon/messages.pigeon.dart:26)
//     #1  CloudFunctionsHostApi.call (package:cloud_functions_platform_interface
//         /src/pigeon/messages.pigeon.dart:99)
//     <asynchronous suspension>
//     ...
//
// The server had answered correctly and courteously. The first line was the
// whole message. Everything below it was a Dart stack trace pasted into the
// user interface.
//
// The cause was this pattern, which existed in FOUR screens independently:
//
//     final s = e.toString();
//     final i = s.indexOf('] ');
//     _say(i >= 0 ? s.substring(i + 2) : 'Something went wrong');
//
// It assumes toString() is exactly "[plugin/code] message". For a
// FirebaseFunctionsException it is not — the trace comes with it, and
// substring keeps everything after the first '] ', trace included.
//
// ── THE RULE ───────────────────────────────────────────────────────────────
//
// Never put e.toString() in front of a user. Read the typed field instead:
// FirebaseFunctionsException.message is the server's HttpsError message on
// its own, already written for a person to read — every one of them in
// stay_host.js and stay_booking.js is a full, polite sentence.
//
// Anything that is not a functions error is a device or network problem the
// host cannot act on, so it gets the caller's plain fallback.
import 'package:cloud_functions/cloud_functions.dart';

/// The message to show a host for [error], or [fallback] when there is nothing
/// worth showing.
///
/// [fallback] should be specific to the screen and phrased as a next step —
/// "Check your connection and try again" beats "An error occurred".
String friendlyError(Object error, {required String fallback}) {
  if (error is FirebaseFunctionsException) {
    final message = (error.message ?? '').trim();

    // 'internal' is what onCall returns when a function throws something that
    // is not an HttpsError. Its message is the raw exception text — useful in
    // a log, meaningless to a host.
    if (message.isNotEmpty && error.code != 'internal') return message;
  }
  return fallback;
}
