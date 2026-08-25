// ─────────────────────────────────────────────────────────────────────────────
//  The circle the face goes in, and the ring that fills as the head turns.
//
//  Built 22 August 2026. Driven by services/liveness_ring_controller.dart —
//  read that file first, it explains why the sweep is ±30 degrees rather than
//  a full rotation.
//
//  ── WHY A RING RATHER THAN A PROGRESS BAR ───────────────────────────────────
//
//  Because the ring IS the head movement. A segment on the left lights when
//  the head is turned left; the shape on screen and the motion of the body
//  are the same shape, so nobody has to be told what the relationship is.
//
//  A bar filling 0 to 100 would carry identical information and teach nothing
//  — the user would still be guessing which way to turn and how far.
//
//  ⚠ THE SEGMENT COUNT LIVES IN THE CONTROLLER, not here. This widget paints
//  whatever length of list it is given. Two constants would drift.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';

class LivenessRing extends StatelessWidget {
  const LivenessRing({
    super.key,
    required this.lit,
    this.diameter = 260,
    this.ringColour = const Color(0xFF22C55E),
    this.trackColour = const Color(0x33FFFFFF),
    this.centreActive = false,
  });

  /// One entry per segment, true where the head has already been.
  final List<bool> lit;

  final double diameter;
  final Color ringColour;
  final Color trackColour;

  /// True while the person is being asked to bring their face back to the
  /// middle. Brightens and lengthens the centre mark so there is somewhere
  /// specific to aim at.
  final bool centreActive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _RingPainter(
          lit: lit,
          ringColour: ringColour,
          trackColour: trackColour,
          centreActive: centreActive,
        ),
      ),
    );
  }
}

/// Two chevrons under the circle that brighten as each side of the ring fills.
///
/// ── WHAT IT ADDS THAT THE RING DOES NOT ─────────────────────────────────────
///
/// The ring answers "how much have I done". It cannot answer "which way now" —
/// that lives only in the hint text, and text has to be read. On a screen where
/// somebody is concentrating on holding a phone steady and turning their head,
/// reading is the thing they have least attention for.
///
/// A chevron is understood without being read. Dim on one side means "you have
/// not been this way yet"; both bright means the sweep is done.
///
/// ── ⚠ DRIVEN BY THE LIT SEGMENTS, NEVER BY THE HEAD ANGLE ───────────────────
///
/// This is the whole design and it is not a detail.
///
/// The preview is MIRRORED, and ML Kit's sign convention for yaw is not
/// something to guess at. Read the angle directly and there is a fifty percent
/// chance the arrows point opposite to the way the ring is filling — which is
/// disorienting in a way people feel immediately and cannot put into words.
///
/// Taking the same `lit` list the painter uses makes that impossible: the
/// arrows agree with the ring by construction. And if a real device shows the
/// ring itself filling the wrong way round, that is ONE fix in the controller's
/// index mapping and the arrows follow it for free.
///
/// ── NO ANIMATION, DELIBERATELY ──────────────────────────────────────────────
///
/// No pulse, no bounce, no sliding. Movement on a screen that is asking you to
/// hold still reads as urgency, and the point of this is the opposite. Opacity
/// alone is enough, and it is calm.
class LivenessArrows extends StatelessWidget {
  const LivenessArrows({
    super.key,
    required this.lit,
    this.litColour = const Color(0xFF22C55E),
    this.idleColour = Colors.white,
    this.size = 34,
    this.gap = 92,
  });

  /// The same list the ring is painting. See the note above.
  final List<bool> lit;

  final Color litColour;
  final Color idleColour;
  final double size;

  /// Space between the two chevrons. Wide enough that they read as two ends of
  /// a movement rather than as a pair of buttons.
  final double gap;

  static double _fraction(Iterable<bool> half) {
    final List<bool> l = half.toList();
    if (l.isEmpty) return 0;
    return l.where((bool b) => b).length / l.length;
  }

  @override
  Widget build(BuildContext context) {
    final int half = lit.length ~/ 2;

    // ⚠ WHICH HALF BELONGS TO WHICH CHEVRON.
    //
    // The painter starts segment 0 at twelve o'clock and runs CLOCKWISE, so
    // segments 0..half-1 occupy the RIGHT side of the circle and half..end
    // occupy the LEFT. Centre — a head facing forward — sits at the bottom, and
    // the two extremes meet at the top.
    //
    // So the chevron lights on the same side of the screen as the arc that is
    // filling. That is the only relationship that has to hold; see the header
    // for why it is expressed this way and not in degrees.
    final double rightLit = _fraction(lit.take(half));
    final double leftLit = _fraction(lit.skip(half));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _chevron(Icons.chevron_left_rounded, leftLit),
        SizedBox(width: gap),
        _chevron(Icons.chevron_right_rounded, rightLit),
      ],
    );
  }

  Widget _chevron(IconData icon, double filled) => Icon(
        icon,
        size: size,
        // Never fully invisible. A chevron that disappears entirely reads as a
        // rendering fault rather than as "not yet" — 0.3 is present but plainly
        // waiting.
        color: (filled > 0 ? litColour : idleColour)
            .withValues(alpha: 0.30 + 0.70 * filled),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.lit,
    required this.ringColour,
    required this.trackColour,
    this.centreActive = false,
  });

  final List<bool> lit;
  final Color ringColour;
  final Color trackColour;
  final bool centreActive;

  /// Gap between segments, in radians. Without it the ring reads as one solid
  /// circle and the sense of "filling up piece by piece" is lost.
  static const double _gap = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    if (lit.isEmpty) return;

    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height)
        .deflate(6);
    final double sweep = (2 * math.pi) / lit.length;

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = trackColour;

    final Paint on = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = ringColour;

    for (int i = 0; i < lit.length; i++) {
      // ⚠ STARTS AT THE TOP AND RUNS CLOCKWISE.
      //
      // Canvas angles start at 3 o'clock, so -pi/2 rotates the origin to 12
      // o'clock. Segment 0 is the far LEFT of the head sweep and must appear
      // on the left of the ring — the preview is mirrored, like a mirror, so
      // turning left moves the image left and the ring must agree. Getting
      // this backwards makes the ring fill away from the direction the head
      // is moving, which is disorienting in a way people cannot articulate.
      final double start = -math.pi / 2 + (i * sweep) + (_gap / 2);
      canvas.drawArc(
        rect,
        start,
        sweep - _gap,
        false,
        lit[i] ? on : track,
      );
    }

    _paintCentreMark(canvas, rect);
  }

  /// A short tick at the bottom of the ring, marking dead centre.
  ///
  /// ── ⚠ WHY THE MARK IS AT THE BOTTOM AND NOT THE TOP ─────────────────────
  ///
  /// Because that is where a head facing forward actually sits on this ring.
  /// The painter starts segment 0 at twelve o'clock and runs clockwise, and the
  /// controller maps the two EXTREMES of the sweep to the two ends of that run
  /// — so the extremes meet at the top and centre lands at six o'clock. Putting
  /// the mark anywhere more obvious would be putting it somewhere wrong.
  ///
  /// ── WHY IT EXISTS AT ALL, ADDED 24 August 2026 ───────────────────────────
  ///
  /// Asked for directly after a device test: "give centre line to round, once
  /// both side done with green line and face bring to centre then only auto
  /// selfie trigger".
  ///
  /// The instruction "look straight at the camera" is a description of a
  /// feeling, not a target. People overcorrect past centre and hunt around it,
  /// because nothing on screen says where centre IS. A tick does — and it costs
  /// one line of paint.
  void _paintCentreMark(Canvas canvas, Rect rect) {
    final double cx = rect.center.dx;
    final double r = rect.width / 2;
    final double top = rect.center.dy + r - (centreActive ? 18 : 11);
    final double bottom = rect.center.dy + r + (centreActive ? 10 : 5);

    final Paint mark = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = centreActive ? 4 : 2.5
      // Dim until it matters. During the sweep the person is meant to be
      // looking AWAY from centre, and a bright marker there would be arguing
      // with the instruction they are following.
      ..color = centreActive
          ? ringColour
          : const Color(0xFFFFFFFF).withValues(alpha: 0.55);

    canvas.drawLine(Offset(cx, top), Offset(cx, bottom), mark);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) {
    if (old.lit.length != lit.length) return true;
    // ⚠ centreActive MUST be compared here. Leave it out and the mark never
    // brightens, because nothing else about the ring changes at the moment the
    // sweep ends — the painter would be asked to repaint and correctly decline.
    if (old.centreActive != centreActive) return true;
    for (int i = 0; i < lit.length; i++) {
      if (old.lit[i] != lit[i]) return true;
    }
    return old.ringColour != ringColour || old.trackColour != trackColour;
  }
}
