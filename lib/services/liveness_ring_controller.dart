// ─────────────────────────────────────────────────────────────────────────────
//  Liveness by head sweep — the ring that fills as you turn.
//
//  Built 22 August 2026.
//
//  ── WHAT IT IS ──────────────────────────────────────────────────────────────
//
//  The face goes in a circle. A hint says to turn the head slowly. As the head
//  turns, segments of the ring light up green, one band of angle at a time.
//  When enough of the ring is lit, the photograph is taken.
//
//  ── WHY THIS SHAPE, AND NOT BLINK-THEN-TURN ─────────────────────────────────
//
//  Because PROGRESS IS VISIBLE. The failure this replaces was a good selfie
//  refused ten times with nothing on screen explaining why — the person could
//  not tell whether they were close or hopeless, so they repeated the same
//  thing and gave up. A ring that fills cannot fail silently: you either see it
//  moving or you do not, and you adjust within a second.
//
//  A blink challenge has the opposite property. A blink lasts 100–400ms, ML
//  Kit in fast mode with frame dropping often never samples the closed frame,
//  and the user has no idea whether their blink "counted". That is the same
//  silent failure wearing a different hat.
//
//  ── ⚠ WHY ±30 DEGREES AND NOT 360 ──────────────────────────────────────────
//
//  A full head rotation is impossible to track with ML Kit and asking for one
//  would recreate the bug it is meant to fix.
//
//  ML Kit finds a face by seeing a face. Past roughly 45 degrees of turn it
//  loses the face entirely — so a user obediently turning further would watch
//  the ring FREEZE at the exact moment they were doing as they were told.
//  Google's own guidance is narrower still: the classification signals are
//  only reliable within about ±18 degrees.
//
//  Face ID does the full circle because it uses an infrared dot projector to
//  read depth. We have a camera and a face detector. So the ring maps a
//  comfortable head-shake — _sweepDegrees each way — onto a full circle of
//  paint. It LOOKS like a 360 and it is a movement anybody can do.
//
//  ── ⚠ NULL YAW IS NOT ZERO ──────────────────────────────────────────────────
//
//  Google documents that the Euler angles come back NULL when performance mode
//  is fast and both landmarks and classification are off. Our detector enables
//  both, so they are populated — but if that config is ever "optimised", a null
//  treated as 0.0 would peg the sweep at dead centre and the ring would never
//  fill, with no error anywhere. onYaw takes a nullable double and ignores
//  null. Do not add a `?? 0.0`.
//
//  ── IT ASSISTS. IT DOES NOT TRAP. ───────────────────────────────────────────
//
//  If the ring has not closed within _timeoutMs the controller reports
//  timedOut, and the SCREEN IS EXPECTED TO CAPTURE ANYWAY and mark the record
//  "liveness incomplete" for the admin. That is the rule established across
//  this codebase on 22 August: the app assists, the admin judges. Nobody is
//  ever stuck on a screen they cannot leave.
//
//  ── WHAT IT DEFEATS, HONESTLY ───────────────────────────────────────────────
//
//  A printed photograph, completely. A phone held up playing a video, only
//  awkwardly — the movement would have to match. It does not defeat a prepared
//  attacker, and nothing without depth sensing does. It is here because it is
//  legible and pleasant, not because it is hard to fool.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';

enum LivenessRingState {
  /// Waiting for a face, roughly centred, before anything can start.
  centring,

  /// Face is centred and held. Waiting for the person to press start.
  ///
  /// ── WHY A DELIBERATE START, ADDED 22 AUGUST ──────────────────────────────
  ///
  /// The first version began the sweep — and the twelve second clock — the
  /// instant a face happened to centre. So the instruction "turn your head
  /// slowly" appeared at the same moment the person was already being timed,
  /// and they read it while the clock ran.
  ///
  /// Now nothing starts until they say so. They get to read what is about to
  /// happen, decide they are ready, and press. The clock they are racing is
  /// one they started themselves, which is the difference between a task and
  /// an ambush.
  ready,

  /// 3 · 2 · 1 before the sweep. Long enough to put the phone where they want
  /// it and get their bearings; short enough not to be a delay.
  countdown,

  /// Face found and centred. Turning fills the ring.
  sweeping,

  /// Enough of the ring is lit. Take the photograph.
  complete,

  /// Ran out of time. The screen should capture anyway — see the header.
  timedOut,
}

class LivenessRingController {
  /// How many bands the ring is divided into.
  ///
  /// 24 gives a segment every 2.5 degrees across the sweep — fine enough to
  /// feel continuous, coarse enough that a dropped frame does not leave a
  /// visible gap the user cannot fill.
  static const int segments = 24;

  /// Half-width of the sweep, in degrees. See the header for why this is not
  /// 180. Raising it past about 40 starts losing the face on real phones.
  ///
  /// LOWERED FROM 30 TO 25 on 24 August 2026. The extremes have to be REACHED
  /// for the ring to close, and ML Kit's angle estimate gets noticeably shakier
  /// as it approaches 30 — so the last few segments were the hardest ones to
  /// light at exactly the moment the person was trying hardest. 25 is a
  /// comfortable head turn that the detector reads confidently throughout.
  static const double sweepDegrees = 25.0;

  /// How straight the head must be before the sweep begins. Without this the
  /// ring starts half filled because the user was already turned when the
  /// camera opened.
  static const double centreTolerance = 10.0;

  /// Fraction of the ring that must be lit to count as complete.
  ///
  /// Not 1.0 deliberately. Demanding every last segment means one dropped
  /// frame at the far edge leaves a single dark band the user cannot find, and
  /// they waggle their head at it until the timeout. 0.85 is a completed sweep
  /// in every practical sense.
  static const double completeFraction = 0.85;

  /// Both extremes must be reached, so a small wobble in the middle cannot
  /// fill 85% of the ring by jitter alone.
  static const double extremeFraction = 0.75;

  /// After this, give up and let the screen capture anyway.
  ///
  /// ── ⚠ RAISED FROM 12s TO 20s ON 24 August 2026 ───────────────────────────
  ///
  /// From a real device: "left side was smooth but as I turn to right the
  /// message appear". The ring was two thirds full and still travelling when
  /// the clock ran out — the check was working and simply not given enough
  /// time to finish.
  ///
  /// 12 seconds sounded generous and was not, because the sweep is not one
  /// movement. The person reads "turn to the left", turns, reads "now turn to
  /// the right", then travels the FULL WIDTH of the sweep — from one extreme
  /// through centre to the other, twice the distance of the first leg — while
  /// reading a second instruction mid-turn. A first-timer needs eight to
  /// twelve seconds for that and someone unhurried needs more.
  ///
  /// ⚠ THIS IS NOT A SECURITY PARAMETER. Nothing is proved by cutting somebody
  /// off sooner; a slow head is not a fraudulent one. The things that decide
  /// whether the check passes are reach (sweepDegrees), coverage
  /// (completeFraction) and continuity (minSweepFrames). Time is only what
  /// stops the screen hanging for ever.
  static const int timeoutMs = 20000;

  /// The fewest analysed frames a completed sweep may be built from.
  ///
  /// ── ⚠ WHY A FLOOR EXISTS AT ALL, ADDED 24 August 2026 ────────────────────
  ///
  /// _light now paints the arc BETWEEN two samples rather than the single
  /// point each sample sat on — without that the ring could not be closed at
  /// any head speed. But it means the ring could in principle be filled from
  /// two data points: one reading at each extreme, with nothing in between.
  ///
  /// A real person turning their head produces a dozen or more readings in the
  /// time it takes, so this costs them nothing. It exists so that "the ring
  /// filled" cannot mean "we saw a face twice, briefly, at two angles" — which
  /// is roughly what a photograph being waved about would produce.
  ///
  /// ⚠ THIS IS A FLOOR, NOT A DEFENCE. It raises the cost of the crudest
  /// attack and nothing more. See the header: without depth sensing this check
  /// does not defeat a prepared attacker, and the admin still judges the photo.
  static const int minSweepFrames = 8;

  final ValueNotifier<LivenessRingState> state =
      ValueNotifier<LivenessRingState>(LivenessRingState.centring);

  /// Which segments are lit. The painter reads this.
  final ValueNotifier<List<bool>> lit =
      ValueNotifier<List<bool>>(List<bool>.filled(segments, false));

  /// What to tell the user right now.
  final ValueNotifier<String> hint =
      ValueNotifier<String>('Put your face in the circle');

  /// 0..1, for anything that wants a plain progress number.
  final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  /// Seconds counted down before the sweep. Shown big, in the ring.
  static const int countdownFrom = 3;

  /// How long the face must stay centred before Start is offered. Stops the
  /// button flickering in and out while somebody is still settling.
  static const int steadyMs = 600;

  /// The number currently on screen during [LivenessRingState.countdown].
  final ValueNotifier<int> count = ValueNotifier<int>(countdownFrom);

  /// Why the sweep did not finish, in words the person can act on.
  ///
  /// ── ⚠ NAMES THE ACTUAL CAUSE, NEVER "VERIFICATION FAILED" ────────────────
  ///
  /// "It failed, try again" tells somebody nothing and invites them to repeat
  /// exactly what they just did. Each reason below is measured from what the
  /// frames actually showed — how far the head got, whether it went both ways,
  /// whether the face kept leaving the frame — so the second attempt can be
  /// different from the first.
  ///
  /// Empty when the sweep completed.
  final ValueNotifier<String> failureReason = ValueNotifier<String>('');

  Timer? _timeout;
  Timer? _countdown;
  DateTime? _steadySince;
  bool _started = false;
  bool _finished = false;

  /// Where the head was on the previous ANALYSED frame, so the arc between
  /// that position and this one can be painted. See the note in [_light].
  ///
  /// ⚠ CLEARED WHENEVER THE FACE IS LOST. A null here means "we did not watch
  /// the head get from there to here", and nothing is bridged.
  double? _lastYaw;

  /// Counted so the timeout message can tell the difference between "you did
  /// not move" and "we kept losing sight of you", which need opposite advice.
  int _framesWithFace = 0;
  int _framesNoFace = 0;

  /// Feed every frame's result in here.
  ///
  /// [yaw] is nullable ON PURPOSE — see the header. [faceFound] is false when
  /// there is no face or more than one.
  void onFrame({required bool faceFound, required double? yaw}) {
    if (_finished) return;

    if (faceFound) {
      _framesWithFace++;
    } else {
      _framesNoFace++;
    }

    if (!faceFound) {
      _steadySince = null;
      // ⚠ The bridge is broken here, deliberately. We stop being able to say
      // where the head went, so the next sample paints only its own segment
      // rather than an arc we never actually watched.
      _lastYaw = null;
      // Losing the face mid-sweep is not a failure — a hand moved, the light
      // changed. The lit segments are KEPT so the person carries on from where
      // they were rather than starting again, which is the single most
      // demoralising thing this kind of screen can do.
      hint.value = _started
          ? 'Keep your face in the circle'
          : 'Put your face in the circle';
      return;
    }

    if (yaw == null) {
      // Not measured. Say nothing new and wait — never assume dead centre.
      return;
    }

    // ── NOTHING BEGINS WITHOUT A DELIBERATE START ──────────────────────
    //
    // Centring only offers the button. The sweep, and the clock, wait for the
    // person. See the note on LivenessRingState.ready.
    if (!_started) {
      if (state.value == LivenessRingState.countdown) return;

      if (yaw.abs() > centreTolerance) {
        _steadySince = null;
        state.value = LivenessRingState.centring;
        hint.value = 'Look straight at the camera';
        return;
      }

      // Held steady for a moment, so the button does not flicker in and out
      // while somebody is still getting comfortable.
      _steadySince ??= DateTime.now();
      if (DateTime.now().difference(_steadySince!).inMilliseconds < steadyMs) {
        return;
      }

      if (state.value != LivenessRingState.ready) {
        state.value = LivenessRingState.ready;
        hint.value = 'When you are ready, press start';
      }
      return;
    }

    _light(yaw);
  }

  /// -sweep..+sweep mapped onto 0..segments-1.
  int _indexFor(double yaw) {
    final double clamped = yaw.clamp(-sweepDegrees, sweepDegrees);
    final double t = (clamped + sweepDegrees) / (2 * sweepDegrees);
    return (t * (segments - 1)).round().clamp(0, segments - 1);
  }

  void _light(double yaw) {
    final int index = _indexFor(yaw);

    // ── ⚠ PAINT THE ARC TRAVELLED, NOT THE POINT SAMPLED ──────────────────
    //
    // FIXED 24 August 2026, reported as "the camera liveness test is not good
    // as it should be". THE RING WAS ARITHMETICALLY IMPOSSIBLE TO CLOSE.
    //
    // The old line was `next[index] = true` — ONE segment per analysed frame.
    // Closing the ring needs 20 of 24 DISTINCT segments. Frames are analysed
    // at most once every AutoSelfieController.checkEveryMs, and the clock runs
    // for timeoutMs, so the absolute ceiling was a few dozen samples — of
    // which many landed on segments already lit, because the head passes back
    // through the middle on its return journey.
    //
    // Worse, a head moving at any natural speed crosses several segments
    // BETWEEN two samples, and a segment skipped that way could only ever be
    // filled by a later sample landing exactly on it. So turning briskly left
    // permanent holes in the ring, and turning slowly enough to avoid them ran
    // out the clock. THERE WAS NO HEAD SPEED AT WHICH THIS PASSED. Every
    // report of it "not working" was correct and none of them were user error.
    //
    // Now each sample fills every segment between where the head was and where
    // it is. That is also what the person already believes is happening — they
    // swept across an arc, so the arc lights — which is why the old behaviour
    // read as broken rather than as strict.
    //
    // ⚠ ONLY ACROSS CONTINUOUS TRACKING. _lastYaw is cleared the moment the
    // face is lost, so an arc is never painted across a gap we could not see.
    // A printed photograph still cannot fill the ring: it cannot turn.
    final int from = _lastYaw == null ? index : _indexFor(_lastYaw!);
    _lastYaw = yaw;

    final int lo = from < index ? from : index;
    final int hi = from < index ? index : from;

    final List<bool> next = List<bool>.from(lit.value);
    bool changed = false;
    for (int i = lo; i <= hi; i++) {
      if (!next[i]) {
        next[i] = true;
        changed = true;
      }
    }
    if (changed) lit.value = next;

    final int on = next.where((bool b) => b).length;
    progress.value = on / segments;

    // Both ends, so a wobble in the middle cannot pass.
    final int edge = (segments * (1 - extremeFraction) / 2).floor().clamp(1, 6);
    final bool leftDone = next.take(edge).any((bool b) => b);
    final bool rightDone =
        next.reversed.take(edge).any((bool b) => b);

    // ── ⚠ ASK FOR REACH, NOT FOR CARE ────────────────────────────────────
    //
    // These said "turn your head slowly" until 24 August 2026, and on a real
    // device that instruction cost somebody the check: they turned left
    // carefully, read the next instruction, and were still travelling back
    // through centre when the clock ran out at two thirds full.
    //
    // Slowness helped the OLD implementation, which sampled single points and
    // needed the head to pause on each one. It does nothing now — the arc
    // between samples is filled either way — and it actively hurts, because
    // the only way to fail a working sweep is to run out of time before
    // reaching the far side. So the words point at distance instead.
    if (!leftDone) {
      hint.value = 'Turn your head left, as far as you comfortably can';
    } else if (!rightDone) {
      hint.value = 'Now all the way to the right';
    } else {
      hint.value = 'Almost there';
    }

    if (on >= (segments * completeFraction) &&
        leftDone &&
        rightDone &&
        // See minSweepFrames. A real sweep passes this long before the ring
        // is full, so it never delays anybody — it only refuses a ring that
        // was filled from too few readings to be a head turning.
        _framesWithFace >= minSweepFrames) {
      _finish(LivenessRingState.complete);
      hint.value = 'Hold still';
    }
  }

  /// Called by the Start button. Runs 3 · 2 · 1, then opens the sweep.
  void start() {
    if (_started || _finished) return;
    if (state.value == LivenessRingState.countdown) return;

    state.value = LivenessRingState.countdown;
    count.value = countdownFrom;
    // Shown DURING the countdown, so the instruction is read before it is
    // needed rather than at the moment of acting on it.
    hint.value = 'Get ready to turn your head left, then right';

    _countdown = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (_finished) {
        t.cancel();
        return;
      }
      if (count.value > 1) {
        count.value = count.value - 1;
        return;
      }
      t.cancel();
      _countdown = null;
      _beginSweep();
    });
  }

  void _beginSweep() {
    _started = true;
    _framesWithFace = 0;
    _framesNoFace = 0;
    // Nothing to bridge from on the very first sample of a sweep.
    _lastYaw = null;
    state.value = LivenessRingState.sweeping;
    // See the note in _light: reach, not care.
    hint.value = 'Turn your head left, as far as you comfortably can';
    // ⚠ THE CLOCK STARTS HERE, not when a face was first seen. It is now
    // twelve seconds the person chose to begin.
    _timeout = Timer(const Duration(milliseconds: timeoutMs), _giveUp);
  }

  void _giveUp() {
    if (_finished) return;

    failureReason.value = _explain();
    _finish(LivenessRingState.timedOut);

    // The photo is still taken — see the header. The hint says what is
    // happening; failureReason says why the check did not finish.
    hint.value = 'Taking your photo anyway';
  }

  /// Turns what the frames showed into one specific, actionable sentence.
  String _explain() {
    final List<bool> l = lit.value;
    final int on = l.where((bool b) => b).length;
    final int edge = (segments * (1 - extremeFraction) / 2).floor().clamp(1, 6);
    final bool left = l.take(edge).any((bool b) => b);
    final bool right = l.reversed.take(edge).any((bool b) => b);

    // Face kept leaving the frame — nothing about turning will help until
    // that is fixed, so it is checked first.
    // ── ⚠ 0.18, LOWERED FROM 0.35 ON 24 August 2026 ──────────────────────────
    //
    // The old threshold was set by eye and was too high to be useful. Now that
    // the arc between samples is what fills the ring, losing the face BREAKS
    // THE BRIDGE — the next reading paints only its own segment — so lost
    // tracking hurts far more than it used to.
    //
    // Simulated: a sweep losing 20% of its frames does not close the ring. At
    // the old 0.35 threshold that person was told "turn your head further each
    // way", which is wrong and unfollowable — they turned perfectly well and
    // the camera kept losing them. A clean sweep loses only a few per cent, so
    // 0.18 separates the two cases without catching normal jitter.
    final int total = _framesWithFace + _framesNoFace;
    if (total > 0 && _framesNoFace > total * 0.18) {
      return 'Your face kept going out of view. Hold the phone at arm\'s '
          'length, keep it still, and turn only your head.';
    }

    if (on <= 2) {
      return 'We did not see your head move. Next time turn to the left, then '
          'all the way to the right, keeping your face in the circle.';
    }

    // ⚠ NO "SLOWLY" HERE EITHER — see the note in _light. This is the exact
    // message a real device produced on 24 August 2026, and the advice in it
    // was the reason the second attempt would have failed the same way: the
    // person had already run out of time, and was being told to take longer.
    if (left && !right) {
      return 'You turned to the left but not to the right. The circle needs '
          'both sides — go straight back the other way without pausing in '
          'the middle.';
    }

    if (right && !left) {
      return 'You turned to the right but not to the left. The circle needs '
          'both sides — go straight back the other way without pausing in '
          'the middle.';
    }

    // ⚠ DO NOT PUT "MORE SLOWLY" BACK IN THIS SENTENCE. It was here until 24
    // August 2026 and it was wrong advice given confidently: the ring now
    // paints the whole arc the head travels, so speed is not what was missing.
    // What is missing at this point is always REACH — the head stopped short
    // of the ends. Telling somebody to slow down when they need to turn
    // further makes the next attempt worse than the last.
    return 'The circle did not quite fill. Turn your head a little further '
        'each way — all the way until you can no longer see the screen.';
  }

  void _finish(LivenessRingState s) {
    _finished = true;
    _timeout?.cancel();
    _timeout = null;
    _countdown?.cancel();
    _countdown = null;
    state.value = s;
  }

  /// Start again from nothing. Used when a second face appears, which is the
  /// one case where keeping progress would be wrong.
  void reset() {
    _timeout?.cancel();
    _timeout = null;
    _countdown?.cancel();
    _countdown = null;
    _steadySince = null;
    _lastYaw = null;
    _framesWithFace = 0;
    _framesNoFace = 0;
    count.value = countdownFrom;
    failureReason.value = '';
    _started = false;
    _finished = false;
    lit.value = List<bool>.filled(segments, false);
    progress.value = 0.0;
    state.value = LivenessRingState.centring;
    hint.value = 'Put your face in the circle';
  }

  void dispose() {
    _timeout?.cancel();
    _countdown?.cancel();
    count.dispose();
    failureReason.dispose();
    state.dispose();
    lit.dispose();
    hint.dispose();
    progress.dispose();
  }
}
