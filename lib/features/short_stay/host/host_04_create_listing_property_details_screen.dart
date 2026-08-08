// Step 3: what the property is, and how many people it sleeps.
//
// WIRED 8 August 2026. The Stitch version had a property-type selector that
// worked but wrote nowhere, bedroom/bed/bathroom counters that were static
// text with no controls, no title field and no description field at all —
// even though createStayListing REQUIRES a title and rejects the listing
// without one.
//
// ── maxGuests IS NOT COSMETIC ──────────────────────────────────────────────
//
// It is validated on every booking. A guest cannot book for more people than
// this, and createStayBooking refuses over it. Set too low, the host loses
// bookings they would have taken and will never know why.
//
// Infants do not count towards it — the same rule the booking model and the
// server both apply. Said on screen so a host sets it against the number the
// system will actually check.
//
// ── PROPERTY TYPE VALUES ARE THE SERVER'S, NOT THE LABELS ──────────────────
//
// The screen shows "Apartment"; the draft carries 'flat'. Stitch's labels are
// American and the data model is not. Mapping here keeps the display readable
// without letting a display string become a stored value.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_routes.dart';
import 'listing_draft.dart';
import 'wizard_shell.dart';

class PropertyDetailsScreen extends StatefulWidget {
  const PropertyDetailsScreen({super.key});

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  final _draft = ListingDraft.instance;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  late String _type;
  late int _bedrooms;
  late int _beds;
  late int _bathrooms;
  late int _maxGuests;

  /// Stored value -> what a host would call it.
  static const Map<String, String> _types = <String, String>{
    'flat': 'Flat or apartment',
    'house': 'House',
    'annexe': 'Annexe or outbuilding',
    'room': 'Private room',
    'cottage': 'Cottage',
    'other': 'Something else',
  };

  @override
  void initState() {
    super.initState();
    // Read back from the draft so Back-then-forward does not wipe the answers.
    _titleCtrl.text = _draft.title;
    _descCtrl.text = _draft.description;
    _type = _types.containsKey(_draft.propertyType) ? _draft.propertyType : 'flat';
    _bedrooms = _draft.bedrooms;
    _beds = _draft.beds;
    _bathrooms = _draft.bathrooms;
    _maxGuests = _draft.maxGuests;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _canContinue => _titleCtrl.text.trim().length >= 5;

  void _save() {
    _draft.title = _titleCtrl.text.trim();
    _draft.description = _descCtrl.text.trim();
    _draft.propertyType = _type;
    _draft.bedrooms = _bedrooms;
    _draft.beds = _beds;
    _draft.bathrooms = _bathrooms;
    _draft.maxGuests = _maxGuests;
    Navigator.of(context).pushNamed(HostRoutes.newAmenities);
  }

  @override
  Widget build(BuildContext context) {
    return HostWizardScaffold(
      step: 3,
      heading: 'Tell us about the place',
      subheading: 'This is what a guest sees first when your listing appears '
          'in search.',
      canContinue: _canContinue,
      onNext: _save,
      children: <Widget>[
        WizardSection(
          title: 'Listing title',
          note: 'Short and specific. "Quiet one-bed near the canal" works '
              'better than "Lovely flat".',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _titleCtrl,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'e.g. Bright two-bed with parking',
                  counterText: '',
                ),
              ),
              if (_titleCtrl.text.trim().isNotEmpty && !_canContinue)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'A little longer, please — at least five characters.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: GoOutsColors.warning),
                  ),
                ),
            ],
          ),
        ),
        WizardSection(
          title: 'Description',
          note: 'Optional, and worth doing. You can add it later.',
          child: TextField(
            controller: _descCtrl,
            maxLines: 5,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What is it like to stay here? What is nearby?',
              alignLabelWithHint: true,
            ),
          ),
        ),
        WizardSection(
          title: 'Property type',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _types.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _type == e.key,
                      onSelected: (_) => setState(() => _type = e.key),
                      labelStyle: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _type == e.key
                            ? Colors.white
                            : GoOutsColors.navy,
                      ),
                      selectedColor: GoOutsColors.primary,
                      backgroundColor: GoOutsColors.background,
                      showCheckmark: false,
                    ))
                .toList(),
          ),
        ),
        WizardSection(
          title: 'Size and sleeping',
          note: 'Guests filter on these, so they decide whether your property '
              'appears at all.',
          child: Column(
            children: <Widget>[
              WizardStepper(
                label: 'Bedrooms',
                value: _bedrooms,
                min: 0,
                max: 20,
                onChanged: (v) => setState(() => _bedrooms = v),
              ),
              WizardStepper(
                label: 'Beds',
                sublabel: 'Total, across all rooms',
                value: _beds,
                max: 30,
                onChanged: (v) => setState(() => _beds = v),
              ),
              WizardStepper(
                label: 'Bathrooms',
                value: _bathrooms,
                max: 8,
                onChanged: (v) => setState(() => _bathrooms = v),
              ),
              const Divider(height: 24),
              WizardStepper(
                label: 'Maximum guests',
                sublabel: 'Infants do not count towards this',
                value: _maxGuests,
                max: 30,
                onChanged: (v) => setState(() => _maxGuests = v),
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
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: GoOutsColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A booking for more than your maximum is refused '
                  'automatically, so setting this too low quietly costs you '
                  'bookings.',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: GoOutsColors.body, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
