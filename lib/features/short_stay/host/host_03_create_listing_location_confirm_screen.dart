// Step 2: confirm the address before going any further.
//
// WIRED 8 August 2026. The Stitch version showed a decorative map pin over a
// hardcoded address and had one empty handler.
//
// ── WHY THIS SCREEN EARNS ITS PLACE ────────────────────────────────────────
//
// It looks like a formality and is not. The postcode entered on step 1 is what
// enrichListingLocation resolves on the server to compute how many GoOuts
// cafés and restaurants sit within half a mile — the number that IS the Short
// Stay pitch to a guest. A wrong postcode does not fail; it produces a listing
// with a plausible but wrong neighbourhood, and nobody finds out.
//
// So this shows back exactly what will be sent, in the shape it will be sent,
// with one obvious way to go and fix it.
//
// There is no map. A map would need coordinates the draft does not carry and
// createStayListing does not accept — the server resolves position from the
// postcode itself. Drawing a pin from a guessed location would be a picture
// that disagrees with the data.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_routes.dart';
import 'listing_draft.dart';
import 'wizard_shell.dart';

class CreateListingLocationConfirmScreen extends StatelessWidget {
  const CreateListingLocationConfirmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final d = ListingDraft.instance;

    // Reachable only after step 1, but a deep link or a restored route could
    // land here with nothing. Say so rather than showing three blank lines.
    if (!d.addressComplete) {
      return HostWizardScaffold(
        step: 2,
        heading: 'No address yet',
        subheading:
            'Go back a step and enter the postcode of the property you are '
            'letting.',
        canContinue: false,
        onNext: () {},
        children: const <Widget>[],
      );
    }

    return HostWizardScaffold(
      step: 2,
      heading: 'Is this right?',
      subheading:
          'Check it carefully. Your postcode decides which GoOuts partners '
          'show as nearby on your listing.',
      canContinue: true,
      onNext: () => Navigator.of(context).pushNamed(HostRoutes.newDetails),
      children: <Widget>[
        WizardSection(
          title: 'Property address',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _line(d.line1),
              _line(d.town),
              _line(d.postcode, bold: true),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Change address'),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: GoOutsColors.tint.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: GoOutsColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Guests see only the area and the postcode district until '
                  'they have booked. The full address is shared after a '
                  'booking is confirmed.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: GoOutsColors.body,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 16,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
}
