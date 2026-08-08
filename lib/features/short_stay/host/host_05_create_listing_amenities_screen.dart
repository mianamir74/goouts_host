// Step 4: amenities.
//
// WIRED 8 August 2026. The Stitch version had working checkboxes whose state
// went nowhere — tick everything, press Continue, and the draft still had an
// empty amenities list.
//
// ── STORED VALUES ARE SLUGS, NOT LABELS ────────────────────────────────────
//
// The chip says "Free parking on premises"; the draft carries 'free_parking'.
// Guest-side search will filter on these, and filtering on display text means
// the day somebody rewrites a label to fit on a narrow phone, every listing
// silently stops matching that filter. The label is for the host; the slug is
// the data.
//
// ── THE SAFETY GROUP IS LISTED SEPARATELY AND ON PURPOSE ───────────────────
//
// Smoke alarm, carbon monoxide alarm, fire extinguisher and first aid kit sit
// under their own heading rather than mixed into the general list. A host who
// scrolls past them has still been shown them, which matters because step 7
// asks them to warrant that they have met their fire-safety duty. This screen
// is where they find out what that means in practice.
//
// ⚠ Ticking a safety box here is NOT the legal warranty. That is step 7, it is
// worded as a statement, and it is timestamped on the server.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_routes.dart';
import 'listing_draft.dart';
import 'wizard_shell.dart';

class AmenitiesSelectionScreen extends StatefulWidget {
  const AmenitiesSelectionScreen({super.key});

  @override
  State<AmenitiesSelectionScreen> createState() =>
      _AmenitiesSelectionScreenState();
}

class _AmenitiesSelectionScreenState extends State<AmenitiesSelectionScreen> {
  final _draft = ListingDraft.instance;
  late Set<String> _selected;

  /// slug -> label. Order within a group is the order shown.
  static const Map<String, Map<String, String>> _groups =
      <String, Map<String, String>>{
    'Popular': <String, String>{
      'wifi': 'Wifi',
      'heating': 'Heating',
      'kitchen': 'Kitchen',
      'washer': 'Washing machine',
      'free_parking': 'Free parking on premises',
      'tv': 'TV',
    },
    'Kitchen and dining': <String, String>{
      'cooking_basics': 'Cooking basics',
      'refrigerator': 'Refrigerator',
      'microwave': 'Microwave',
      'dishwasher': 'Dishwasher',
      'oven': 'Oven',
      'kettle': 'Kettle',
    },
    'Bathroom and laundry': <String, String>{
      'bathtub': 'Bath',
      'shower': 'Shower',
      'hair_dryer': 'Hair dryer',
      'shampoo': 'Shampoo',
      'towels': 'Towels provided',
      'iron': 'Iron',
      'hangers': 'Hangers',
    },
    'Comfort and work': <String, String>{
      'air_conditioning': 'Air conditioning',
      'workspace': 'Dedicated workspace',
      'indoor_fireplace': 'Indoor fireplace',
      'books': 'Books and reading material',
    },
    'Outdoor and access': <String, String>{
      'garden': 'Garden or yard',
      'patio_balcony': 'Patio or balcony',
      'lift': 'Lift',
      'step_free': 'Step-free access',
    },
    'Family': <String, String>{
      'cot': 'Cot',
      'high_chair': 'High chair',
      'travel_bed': 'Travel bed',
    },
  };

  /// Kept apart from _groups so it renders under its own heading.
  static const Map<String, String> _safety = <String, String>{
    'smoke_alarm': 'Smoke alarm',
    'carbon_monoxide_alarm': 'Carbon monoxide alarm',
    'fire_extinguisher': 'Fire extinguisher',
    'first_aid_kit': 'First aid kit',
  };

  @override
  void initState() {
    super.initState();
    _selected = _draft.amenities.toSet();
  }

  void _toggle(String slug) => setState(() {
        if (!_selected.remove(slug)) _selected.add(slug);
      });

  void _save() {
    // Sorted so two listings with the same amenities store them identically —
    // set iteration order is not guaranteed, and an unstable order makes any
    // future diff of two listings noisy for no reason.
    _draft.amenities = _selected.toList()..sort();
    Navigator.of(context).pushNamed(HostRoutes.newPhotos);
  }

  @override
  Widget build(BuildContext context) {
    final safetyCount =
        _safety.keys.where((k) => _selected.contains(k)).length;

    return HostWizardScaffold(
      step: 4,
      heading: 'What does your place offer?',
      subheading:
          'Guests filter on these. You can change them at any time after the '
          'listing goes live.',
      // Deliberately always true. A property with no amenities is unusual but
      // not invalid, and blocking here would trap a host on a screen with
      // nothing obviously wrong.
      canContinue: true,
      onNext: _save,
      children: <Widget>[
        for (final entry in _groups.entries)
          WizardSection(
            title: entry.key,
            child: _chips(entry.value),
          ),
        WizardSection(
          title: 'Safety',
          note: safetyCount == 0
              ? 'Nothing selected. Step 7 asks you to confirm you have met '
                  'your fire-safety duty — this is what that means in practice.'
              : '$safetyCount selected.',
          child: _chips(_safety),
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
              const Icon(Icons.check_circle_outline_rounded,
                  size: 18, color: GoOutsColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selected.isEmpty
                      ? 'Nothing selected yet. You can add amenities later, '
                          'but listings with none get fewer views.'
                      : '${_selected.length} '
                          '${_selected.length == 1 ? "amenity" : "amenities"} '
                          'selected.',
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

  Widget _chips(Map<String, String> items) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.entries.map((e) {
          final on = _selected.contains(e.key);
          return FilterChip(
            label: Text(e.value),
            selected: on,
            onSelected: (_) => _toggle(e.key),
            labelStyle: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: on ? Colors.white : GoOutsColors.navy,
            ),
            selectedColor: GoOutsColors.primary,
            backgroundColor: GoOutsColors.background,
            checkmarkColor: Colors.white,
            side: BorderSide(
              color: on ? GoOutsColors.primary : GoOutsColors.border,
            ),
          );
        }).toList(),
      );
}
