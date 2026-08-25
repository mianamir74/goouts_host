// ─────────────────────────────────────────────────────────────────────────────
//  AutoSelfieController — watches the preview and takes the photo itself.
//
//  Written 20 August 2026, reported as "I tried ten times and it would not take
//  my selfie".
//
//  ── THE PROBLEM ─────────────────────────────────────────────────────────────
//
//  The old flow took the photo first and judged it afterwards. Every failure
//  arrived as "Please retake", with nothing to aim at. The person is guessing,
//  and the app knows the answer the whole time and says nothing until it is too
//  late to act on.
//
//  ── THE FIX ─────────────────────────────────────────────────────────────────
//
//  Run the SAME checks on the live preview, say what is wrong while it can
//  still be corrected, and fire the shutter only once they already pass. The
//  photo then passes by construction, because the gate that takes it is the
//  code that validates it.
//
//  ── FOUR THINGS THAT MAKE IT FEEL RIGHT RATHER THAN CLEVER ──────────────────
//
//  1. THROTTLED. ML Kit cannot run at 30fps and trying cooks the battery.
//     Frames arriving while one is in flight are DROPPED, not queued — a queue
//     on a live stream grows for ever and the guidance ends up describing
//     where the face was two seconds ago.
//
//     The interval is not fixed: see checkEveryMs. Framing needs ~3 checks a
//     second; a MOVING head needs far more, so the liveness sweep raises it.
//
//  2. CONSECUTIVE good frames, not one. A single lucky frame between two blinks
//     is not a person holding still, and a shutter that fires on it produces
//     exactly the blurred half-blink the old flow rejected.
//
//  3. A HOLD-STILL PAUSE before firing. Without it the shutter goes off with no
//     warning and feels broken even when it worked.
//
//  4. A MARGIN. The live pass mark is higher than the still one, because the
//     preview runs ML Kit in fast mode and the saved photo is judged in
//     accurate mode. A frame that only just scrapes past live could fail the
//     real check, and an auto-shutter that fires and is then rejected is worse
//     than the manual button it replaced.
//
//  ── AND IF THE STILL CHECK STILL FAILS ──────────────────────────────────────
//
//  It goes back to scanning and keeps guiding. It does NOT show "Please
//  retake." The person did nothing wrong and has nothing to do differently —
//  telling them to try again is asking them to repeat an action they never
//  chose to take.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'camera_frame_converter.dart';
import 'face_check_service.dart';

enum AutoSelfieState { idle, scanning, holdStill, capturing, captured }

class AutoSelfieController {
  AutoSelfieController({
    required this.controller,
    required this.onCaptured,
  });

  final CameraController controller;

  /// Called with the file path once a photo has been taken. The screen still
  /// runs its own full-quality check on it — this does not replace that.
  final Future<bool> Function(String path) onCaptured;

  // ── Tuning. See the numbered notes at the top. ────────────────────────────

  /// Rest between analysed frames, in milliseconds. NOT const — the liveness
  /// ring turns this down while it is sweeping.
  ///
  /// ── ⚠ WHY THIS IS ADJUSTABLE, ADDED 24 AUGUST 2026 ────────────────────────
  ///
  /// 300ms is right for FRAMING. The face is roughly still, the guidance only
  /// has to say "move closer", and three checks a second is more than enough
  /// to feel responsive while leaving the battery alone.
  ///
  /// It is far too slow for MEASURING A MOVING HEAD. The ring paints the arc
  /// between consecutive samples, so the sample rate sets how finely the head's
  /// path is known — at 300ms a normal head turn is described by four or five
  /// points, and the ring lurches round in visible jumps even when it is
  /// filling correctly. The person reads that stutter as the app struggling
  /// with them and slows down, which is the opposite of what helps.
  ///
  /// So the sweep raises the rate for the few seconds it is running and puts it
  /// back afterwards. kyc_screen owns that, because it owns both controllers.
  int checkEveryMs = framingCheckEveryMs;

  /// The resting rate, used for framing. Named rather than written as a bare
  /// 300 at each site, because the sweep has to put it BACK and a literal in
  /// two files is how these two numbers would quietly stop matching.
  static const int framingCheckEveryMs = 300;

  /// What [checkEveryMs] should be while the liveness ring is sweeping.
  ///
  /// Not lower than this: ML Kit in fast mode takes roughly 30–80ms a frame on
  /// a mid-range Android, and asking for frames faster than it can answer just
  /// grows the number DROPPED by the isBusy guard — more heat, no more data.
  static const int sweepCheckEveryMs = 120;

  static const int _neededGoodFrames = 3;
  static const int _holdStillMs = 700;

  /// Live pass mark. Deliberately above the still check's own bar so a
  /// borderline frame does not fire a shutter the accurate pass would reject.
  static const double _liveMinOverall = 0.65;

  /// The target zone, as fractions of the frame. The screen draws corner
  /// brackets at exactly these proportions.
  ///
  /// 0.55 x 0.40 = 0.220 of the frame, which is FaceCheckService's
  /// _idealFaceArea to three decimal places. That is not a coincidence and it
  /// must stay true: it is what makes "fill the brackets" and "your face is
  /// the right size" the same instruction. The old oval was ~40% of the frame
  /// while the check wanted 22%, so the app drew one target and measured
  /// against another — and the person in the middle was told to move closer
  /// while already filling the guide.
  static const double targetW = 0.55;
  static const double targetH = 0.40;

  /// ── THE RUNAWAY LOOP, FIXED 20 August 2026 ────────────────────────────────
  ///
  /// Reported as "it keeps capturing every second".
  ///
  /// The first version, on a rejected photo, reset the counter and restarted
  /// scanning immediately. If the live check passes and the still check does
  /// not — which is exactly what happens when the preview and the saved photo
  /// are framed differently — that is an infinite loop: capture, reject,
  /// rescan, capture, about once a second, for ever.
  ///
  /// Silently retrying a thing that just failed, at speed, is worse than
  /// failing once and saying so. Three attempts, spaced, then hand it to the
  /// person with the real reason.
  static const int _maxAutoAttempts = 3;
  static const int _cooldownMs = 2500;

  final LiveFaceDetector _detector = LiveFaceDetector();

  final ValueNotifier<AutoSelfieState> state =
      ValueNotifier<AutoSelfieState>(AutoSelfieState.idle);

  /// What the person should do right now. Empty means "nothing, you are fine".
  final ValueNotifier<String> guidance = ValueNotifier<String>('');

  /// 0.0 to 1.0 — how far through the hold-still countdown. Drives the ring.
  final ValueNotifier<double> holdProgress = ValueNotifier<double>(0.0);

  /// Where the face is right now, as fractions of the frame. Null when there
  /// is no face. The screen draws this so a person can SEE what to move, which
  /// is the difference between guiding and merely refusing.
  final ValueNotifier<Rect?> faceBox = ValueNotifier<Rect?>(null);

  /// True once auto-capture has given up. The manual button stays, and the
  /// screen says why rather than pretending nothing happened.
  final ValueNotifier<bool> gaveUp = ValueNotifier<bool>(false);

  /// Every face result, pass or fail, handed straight to whoever wants it.
  ///
  /// Added 22 August 2026 so the liveness ring can read the head angle from
  /// the SAME detector and the SAME frames this controller is already
  /// running. A second detector on a second stream would double the CPU cost
  /// and — worse — the two could disagree about whether a face is present.
  void Function(FaceCheckResult result)? onResult;

  /// While true the shutter is held, no matter how good the framing is.
  ///
  /// ⚠ THIS IS WHAT MAKES THE SWEEP HAPPEN BEFORE THE PHOTO. The liveness
  /// ring sets this false only once it has finished, so the auto-capture
  /// cannot fire mid-turn and photograph a profile. It is a gate on the
  /// SHUTTER, never on the guidance: the hints keep working throughout, which
  /// is what stops the screen feeling frozen while the ring is being filled.
  bool holdShutter = false;

  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _goodFrames = 0;
  int _autoAttempts = 0;
  Timer? _holdTimer;
  bool _streaming = false;
  bool _stopped = false;

  bool get isRunning => _streaming;

  Future<void> start() async {
    if (_streaming || _stopped) return;
    if (!controller.value.isInitialized) return;
    try {
      _streaming = true;
      state.value = AutoSelfieState.scanning;
      guidance.value = 'Looking for your face…';
      await controller.startImageStream(_onFrame);
    } catch (e) {
      // Image streaming is unavailable on some devices and in some emulators.
      // Not fatal: the manual shutter is still there, which is why this only
      // logs. An identity check that cannot be completed at all is the one
      // outcome worth avoiding.
      debugPrint('AutoSelfieController: stream unavailable — $e');
      _streaming = false;
      state.value = AutoSelfieState.idle;
      guidance.value = '';
    }
  }

  /// Puts the controller back to scanning and restarts the frame stream.
  ///
  /// ── ⚠ WHY A RESTART IS NOT JUST start() ──────────────────────────────────
  ///
  /// Added 24 August 2026 so the liveness check can be retried without leaving
  /// the screen.
  ///
  /// By the time somebody asks to try again, this controller has usually
  /// finished: _capture() stopped the stream and left the state on `captured`,
  /// where _onFrame returns immediately. Calling start() alone would restart
  /// the stream into a controller that ignores every frame it receives — a
  /// live preview with nothing reading it, which looks exactly like working.
  ///
  /// The attempt counter is cleared too. Three auto-attempts is a limit on one
  /// try, not a budget for the session; a person who deliberately asked to go
  /// again should not inherit the previous attempt's exhaustion.
  Future<void> restart() async {
    if (_stopped) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    _goodFrames = 0;
    _autoAttempts = 0;
    _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);
    holdProgress.value = 0.0;
    gaveUp.value = false;
    faceBox.value = null;
    guidance.value = '';
    // Back to idle so start() is willing to move it on to scanning, and so a
    // frame arriving in the meantime is not discarded as post-capture.
    state.value = AutoSelfieState.idle;
    await start();
  }

  /// Fire the shutter now, without waiting for this controller's own framing
  /// gate to agree.
  ///
  /// ── ⚠ WHY THIS EXISTS: TWO GATES MEASURING THE SAME THING ────────────────
  ///
  /// Added 25 August 2026. Reported as "once the face is in centre it detects
  /// and trigger selfie automatically — at this moment it is manual".
  ///
  /// The liveness ring finishes by PROVING the face is centred and has been
  /// held there. Then it released the shutter and this controller started
  /// counting from scratch: three consecutive frames passing its own
  /// thresholds, then a hold-still pause. Two separate gates asking the same
  /// question with different numbers — and if this one's bar
  /// (_liveMinOverall, and a face-size check measuring against the whole
  /// frame) was not met, the shutter never fired at all and the person was
  /// left pressing the button.
  ///
  /// That is the exact failure family this project keeps paying for: one fact,
  /// two places, only one of them maintained. The ring already knows the
  /// answer. It should be allowed to say so.
  ///
  /// ⚠ THE GUIDANCE AND THE CHECKS ARE NOT SKIPPED. The photograph is still
  /// judged by the full accurate-mode inspector in onCaptured, and still
  /// rejected there if it is genuinely unusable. What is skipped is asking the
  /// same question twice.
  Future<void> captureNow() async {
    if (_stopped) return;
    if (state.value == AutoSelfieState.capturing ||
        state.value == AutoSelfieState.captured) {
      return;
    }
    _goodFrames = 0;
    _cancelHold();
    holdShutter = false;
    await _capture();
  }

  Future<void> stop() async {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_streaming) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _stopped = true;
    await stop();
    await _detector.dispose();
    state.dispose();
    guidance.dispose();
    holdProgress.dispose();
    faceBox.dispose();
    gaveUp.dispose();
  }

  void _onFrame(CameraImage image) {
    if (!_streaming || _stopped) return;
    if (state.value == AutoSelfieState.capturing ||
        state.value == AutoSelfieState.captured) {
      return;
    }
    // Drop rather than queue. See note 1.
    if (_detector.isBusy) return;

    final DateTime now = DateTime.now();
    if (now.isBefore(_cooldownUntil)) return;
    if (now.difference(_lastCheck).inMilliseconds < checkEveryMs) return;
    _lastCheck = now;

    final InputImageLike? converted = _convert(image);
    if (converted == null) return; // unsupported frame, not a failed check

    _detector
        .check(converted.image,
            imageWidth: converted.width, imageHeight: converted.height)
        .then(_onResult);
  }

  InputImageLike? _convert(CameraImage image) {
    final input = CameraFrameConverter.toInputImage(
      image,
      controller.description,
      DeviceOrientation.portraitUp,
    );
    if (input == null) return null;
    return InputImageLike(input, image.width, image.height);
  }

  void _onResult(FaceCheckResult? result) {
    if (result == null || _stopped || !_streaming) return;

    // Published BEFORE the early returns below, so the ring keeps receiving
    // frames even while this controller is busy capturing or has given up.
    onResult?.call(result);

    if (state.value == AutoSelfieState.capturing) return;

    // ML Kit unavailable on this device. Say nothing, change nothing, and let
    // the manual shutter carry it — the same fail-open policy the still check
    // already uses.
    if (!result.available) {
      guidance.value = '';
      faceBox.value = null;
      return;
    }

    // Publish the position on EVERY result, passing or failing. A hint that
    // only appears once you are already correct is not a hint.
    faceBox.value = result.faceBox;

    final bool good = result.isValid && result.overall >= _liveMinOverall;

    if (!good) {
      _goodFrames = 0;
      _cancelHold();
      // The check's own words. One source of truth for what is wrong, so the
      // live hint and the final message cannot contradict each other.
      // Prefer a DIRECTION over a diagnosis. "Move closer" is actionable;
      // "your face is too small in the photo" describes a photo that does not
      // exist yet and does not say what to do about it.
      guidance.value = _positionHint(result.faceBox) ??
          (result.errorMessage?.isNotEmpty == true
              ? _liveWording(result.errorMessage!)
              : 'Hold steady…');
      state.value = AutoSelfieState.scanning;
      return;
    }

    _goodFrames++;

    // Framing is fine but the sweep is not finished. Do not count towards the
    // shutter and do not clear the guidance — the ring is showing its own
    // instruction and this must not fight it.
    if (holdShutter) {
      _goodFrames = 0;
      _cancelHold();
      return;
    }

    guidance.value = '';
    if (_goodFrames >= _neededGoodFrames &&
        state.value != AutoSelfieState.holdStill) {
      _beginHold();
    }
  }

  /// Turns the face position into an instruction, or null when the framing is
  /// already fine and something else is wrong (eyes shut, head turned).
  ///
  /// Direction only. Exact pixels would need the preview's letterboxing
  /// accounted for, and a hint that is confidently a few pixels wrong is worse
  /// than one that only says which way to move.
  String? _positionHint(Rect? box) {
    if (box == null) return 'Bring your face into the frame';

    final double area = box.width * box.height;
    if (area < targetW * targetH * 0.45) return 'Move closer';
    if (area > targetW * targetH * 2.0) return 'Move back a little';

    final double cx = box.left + box.width / 2;
    final double cy = box.top + box.height / 2;

    // The preview is mirrored for a front camera, so a face sitting left in
    // the FRAME appears right to the person looking at it. The instruction has
    // to match what they see, not what the sensor sees.
    if (cx < 0.34) return 'Move right a little';
    if (cx > 0.66) return 'Move left a little';
    if (cy < 0.30) return 'Move down a little';
    if (cy > 0.70) return 'Move up a little';
    return null;
  }

  /// True when the face is inside the bracket zone at roughly the right size.
  /// Drives the brackets turning green.
  bool isFramed(Rect? box) {
    if (box == null) return false;
    final double area = box.width * box.height;
    if (area < targetW * targetH * 0.45) return false;
    if (area > targetW * targetH * 2.0) return false;
    final double cx = box.left + box.width / 2;
    final double cy = box.top + box.height / 2;
    return cx >= 0.34 && cx <= 0.66 && cy >= 0.30 && cy <= 0.70;
  }

  /// The still-photo messages are written for after the event — "take it
  /// again". Live, the photo has not been taken yet, so they are rewritten in
  /// the present tense. Same checks, same order, correct tense.
  String _liveWording(String stillMessage) {
    final String m = stillMessage.toLowerCase();
    if (m.contains('find a face')) return 'Bring your face into the circle';
    if (m.contains('more than one')) return 'Only you in the frame, please';
    if (m.contains('too small')) return 'Move a little closer';
    if (m.contains('look straight')) return 'Look straight at the camera';
    if (m.contains('tilted')) return 'Hold the phone level';
    if (m.contains('eyes look closed')) return 'Open both eyes';
    if (m.contains('covered')) return 'Uncover your face';
    return 'Hold steady…';
  }

  void _beginHold() {
    state.value = AutoSelfieState.holdStill;
    guidance.value = 'Hold still…';
    holdProgress.value = 0.0;

    const int tick = 50;
    int elapsed = 0;
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: tick), (t) {
      elapsed += tick;
      holdProgress.value = (elapsed / _holdStillMs).clamp(0.0, 1.0);
      if (elapsed >= _holdStillMs) {
        t.cancel();
        _capture();
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    holdProgress.value = 0.0;
  }

  /// What happens when a photo we chose to take was then rejected.
  ///
  /// Retry, but SLOWLY and not for ever. The live checks passed and the still
  /// checks did not, which means something differs between the preview and the
  /// saved photo — usually framing. Firing again immediately cannot fix that,
  /// it just does the same thing faster.
  Future<void> _afterRejection() async {
    _goodFrames = 0;
    _cancelHold();
    _cooldownUntil =
        DateTime.now().add(const Duration(milliseconds: _cooldownMs));

    if (_autoAttempts >= _maxAutoAttempts) {
      // Stop trying. Say so, leave the manual button, and stop taking
      // photographs of somebody who did not ask for any of them.
      gaveUp.value = true;
      state.value = AutoSelfieState.idle;
      guidance.value = 'Tap the button below when you are ready';
      await stop();
      return;
    }

    state.value = AutoSelfieState.scanning;
    guidance.value = 'Adjusting…';
    await start();
  }

  Future<void> _capture() async {
    if (_stopped || state.value == AutoSelfieState.capturing) return;
    state.value = AutoSelfieState.capturing;
    guidance.value = '';

    // The stream MUST stop before takePicture. Several Android devices fail
    // outright if both run at once, and the failure is a native exception with
    // no useful message.
    await stop();

    try {
      _autoAttempts++;
      final XFile shot = await controller.takePicture();
      final bool accepted = await onCaptured(shot.path);
      if (_stopped) return;
      if (accepted) {
        state.value = AutoSelfieState.captured;
        return;
      }
      await _afterRejection();
    } catch (e) {
      debugPrint('AutoSelfieController: capture failed — $e');
      if (_stopped) return;
      await _afterRejection();
    }
  }
}

/// Carries the converted frame together with the dimensions the checks need.
/// The size must come from the CameraImage, not the InputImage, because the
/// face-area threshold is a fraction of the frame and a wrong denominator
/// silently changes how close the person is asked to sit.
class InputImageLike {
  const InputImageLike(this.image, this.width, this.height);
  final InputImage image;
  final int width;
  final int height;
}
