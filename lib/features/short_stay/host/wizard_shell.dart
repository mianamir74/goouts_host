// Shared chrome for the create-listing wizard, screens 02 to 08.
//
// ── WHY ────────────────────────────────────────────────────────────────────
//
// Google Stitch generated the seven wizard screens in isolation, so each one
// arrived with its own copy of the same app bar, progress bar and footer — and
// they disagreed. Screen 02's progress bar said "Step 1 of 4" over seven
// screens. Every Back button and every "Save & Exit" was `onPressed: () {}`.
//
// Seven copies of the same broken chrome is seven places to fix it and seven
// chances to fix six. One widget instead.
//
// ── "SAVE & EXIT" IS CALLED "EXIT" HERE, DELIBERATELY ──────────────────────
//
// Stitch labelled it "Save & Exit". Nothing saves: ListingDraft is in memory
// only and there is no per-step Firestore write yet. A button promising to
// save, that discards everything, is worse than no button — the host finds out
// the next time they open the app and their property is gone.
//
// It says Exit, it warns first, and it resets the draft so a second attempt
// does not inherit half of the first.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'listing_draft.dart';

class HostWizardScaffold extends StatelessWidget {
  const HostWizardScaffold({
    super.key,
    required this.step,
    required this.heading,
    required this.subheading,
    required this.children,
    required this.canContinue,
    required this.onNext,
    this.nextLabel = 'Next',
    this.busy = false,
  });

  /// 1-based, out of [totalSteps]. Used only for the progress bar.
  final int step;

  final String heading;
  final String subheading;
  final List<Widget> children;

  /// False disables Next. The old screens were always enabled and always moved
  /// on, which is how an empty draft reached createStayListing and was
  /// rejected for a missing address after the host had answered everything.
  final bool canContinue;

  final VoidCallback onNext;
  final String nextLabel;
  final bool busy;

  /// 02 address, 03 confirm, 04 details, 05 amenities, 06 photos, 07 pricing,
  /// 08 legal. Eight files, seven steps — 08 is the last one.
  static const int totalSteps = 7;

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
        title: Text(
          'Create listing',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => confirmExit(context),
            child: Text(
              'Exit',
              style: GoogleFonts.inter(
                color: GoOutsColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: <Widget>[
          _progress(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Step $step of $totalSteps',
                    style: GoogleFonts.inter(
                      color: GoOutsColors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    heading,
                    style: GoogleFonts.inter(
                      color: GoOutsColors.navy,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (subheading.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      subheading,
                      style: GoogleFonts.inter(
                        color: GoOutsColors.body,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ...children,
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  Widget _progress() => Container(
        width: double.infinity,
        height: 4,
        color: GoOutsColors.primary.withValues(alpha: 0.12),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: step / totalSteps,
          child: Container(color: GoOutsColors.primary),
        ),
      );

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: GoOutsColors.surface,
        border: Border(top: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: SafeArea(
        child: Row(
          children: <Widget>[
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: Text(
                'Back',
                style: GoogleFonts.inter(
                  color: GoOutsColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: (canContinue && !busy) ? onNext : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: GoOutsColors.primary,
                disabledBackgroundColor:
                    GoOutsColors.primary.withValues(alpha: 0.35),
                minimumSize: const Size(150, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      nextLabel,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Warns before leaving, because the draft really is lost.
  static Future<void> confirmExit(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text(
          'Your answers are not saved until the property is submitted on the '
          'last step. Leaving now loses what you have entered.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true || !context.mounted) return;
    ListingDraft.instance.reset();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

/// A titled block, so the six wizard screens group their fields the same way.
class WizardSection extends StatelessWidget {
  const WizardSection({
    super.key,
    required this.title,
    required this.child,
    this.note,
  });

  final String title;
  final Widget child;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GoOutsColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: GoogleFonts.inter(
              color: GoOutsColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              note!,
              style: GoogleFonts.inter(
                color: GoOutsColors.body,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Minus / number / plus. Stitch drew these as static text with no controls,
/// so bedrooms could never be changed from 1.
class WizardStepper extends StatelessWidget {
  const WizardStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 30,
    this.sublabel,
  });

  final String label;
  final String? sublabel;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: GoOutsColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: GoogleFonts.inter(
                        color: GoOutsColors.body, fontSize: 12),
                  ),
              ],
            ),
          ),
          _round(Icons.remove, value > min ? () => onChanged(value - 1) : null),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _round(Icons.add, value < max ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback? onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          side: BorderSide(
            color: onTap == null
                ? GoOutsColors.border
                : GoOutsColors.primary.withValues(alpha: 0.5),
          ),
          foregroundColor:
              onTap == null ? GoOutsColors.border : GoOutsColors.primary,
          shape: const CircleBorder(),
          minimumSize: const Size(38, 38),
        ),
      );
}
