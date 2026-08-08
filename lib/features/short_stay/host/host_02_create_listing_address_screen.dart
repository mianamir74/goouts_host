// Step 1 of the create-listing wizard: where the property is.
//
// ── WIRED 8 August 2026. WHAT IT WAS BEFORE ────────────────────────────────
//
// The Stitch export looked complete and held nothing:
//
//   • the postcode "field" was a Text widget, not a TextField — you could not
//     type in it
//   • "Find address" was onPressed: () {}
//   • the three addresses offered were Buckingham Palace, Clarence House and
//     10 Downing Street, hardcoded
//   • nothing was written anywhere, so pressing Next discarded the screen
//
// That last point is the one that mattered. Screens 02 to 07 all did the same,
// so a host filled in seven screens and createStayListing was called with an
// empty draft — the server correctly rejected it for a missing address, after
// the host had ticked three legal warranties. Everything they typed had been
// thrown away one screen at a time.
//
// This screen now writes line1, town and postcode into ListingDraft.instance,
// which is what submit() on the last step reads.
//
// ── POSTCODE FIRST, THE SAME AS EVERY OTHER GoOuts FORM ────────────────────
//
// Uses AddressLookupService.validatePostcode, already in this app and already
// used by registration. One Mapbox Geocoding call returns up to 10 real
// addresses for the postcode and the host picks one — no per-keystroke
// billing, and no free-typing an address that does not exist.
//
// enrichListingLocation on the server resolves the postcode into the
// partners-within-half-a-mile count that IS the Short Stay pitch. A postcode
// Mapbox does not recognise produces a listing with no location context, so
// manual entry is offered but the postcode is still required.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/address_lookup_service.dart';
import '../../../theme/goouts_colors.dart';
import 'host_routes.dart';
import 'listing_draft.dart';
import 'wizard_shell.dart';

class CreateListingAddressScreen extends StatefulWidget {
  const CreateListingAddressScreen({super.key});

  @override
  State<CreateListingAddressScreen> createState() =>
      _CreateListingAddressScreenState();
}

class _CreateListingAddressScreenState
    extends State<CreateListingAddressScreen> {
  final _draft = ListingDraft.instance;
  final _lookup = AddressLookupService();

  final _postcodeCtrl = TextEditingController();
  final _line1Ctrl = TextEditingController();
  final _townCtrl = TextEditingController();

  bool _searching = false;
  String? _error;
  List<MapboxAddressResult> _results = const <MapboxAddressResult>[];
  int? _selected;

  /// Set when the host chooses to type the address themselves. Kept separate
  /// from "the search found nothing" so the two states cannot be confused.
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    // Repopulate from the draft. Without this, going Back from step 2 and
    // returning shows an empty form even though the answers are still held —
    // which reads as "it lost my address" and makes people retype it.
    _postcodeCtrl.text = _draft.postcode;
    _line1Ctrl.text = _draft.line1;
    _townCtrl.text = _draft.town;
    if (_draft.line1.isNotEmpty) _manual = true;
  }

  @override
  void dispose() {
    _postcodeCtrl.dispose();
    _line1Ctrl.dispose();
    _townCtrl.dispose();
    super.dispose();
  }

  Future<void> _findAddress() async {
    final raw = _postcodeCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Enter a postcode first.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _results = const <MapboxAddressResult>[];
      _selected = null;
    });

    try {
      final found = await _lookup.validatePostcode(raw);
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
        if (found.isEmpty) {
          _error = 'No addresses found for that postcode. Check it, or enter '
              'the address yourself below.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      // Shown, not swallowed. A lookup that fails silently leaves the host
      // staring at an empty list with no idea whether to wait or retype.
      setState(() {
        _searching = false;
        _error = 'Could not look up that postcode. Check your connection, or '
            'enter the address yourself below.';
      });
    }
  }

  bool get _canContinue {
    if (_postcodeCtrl.text.trim().isEmpty) return false;
    if (_manual) {
      return _line1Ctrl.text.trim().isNotEmpty &&
          _townCtrl.text.trim().isNotEmpty;
    }
    return _selected != null;
  }

  void _saveAndContinue() {
    if (_manual) {
      _draft.line1 = _line1Ctrl.text.trim();
      _draft.town = _townCtrl.text.trim();
      _draft.postcode = AddressLookupService.normalise(_postcodeCtrl.text);
    } else {
      final r = _results[_selected!];
      // line1 is house number + street where Mapbox gives both, falling back
      // to the first line of the formatted address. Sending the whole
      // fullAddress would repeat the town and postcode inside line1, and they
      // would then appear twice on the listing.
      final number = (r.houseNumber ?? '').trim();
      final street = (r.street ?? '').trim();
      final joined = <String>[number, street].where((s) => s.isNotEmpty).join(' ');
      _draft.line1 =
          joined.isNotEmpty ? joined : r.fullAddress.split(',').first.trim();
      _draft.town =
          (r.town ?? '').trim().isNotEmpty ? r.town!.trim() : r.city.trim();
      _draft.postcode = r.postcode.trim().isNotEmpty
          ? r.postcode.trim()
          : AddressLookupService.normalise(_postcodeCtrl.text);
    }

    Navigator.of(context).pushNamed(HostRoutes.newLocation);
  }

  @override
  Widget build(BuildContext context) {
    return HostWizardScaffold(
      step: 1,
      heading: 'Where is your place?',
      subheading:
          'Guests only get the exact address once they have booked.',
      canContinue: _canContinue,
      onNext: _saveAndContinue,
      children: <Widget>[
        _postcodeSection(),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _notice(_error!),
        ],
        if (_results.isNotEmpty && !_manual) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            'Select an address',
            style: GoogleFonts.inter(
              color: GoOutsColors.navy,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _addressList(),
        ],
        const SizedBox(height: 16),
        _manualSection(),
      ],
    );
  }

  Widget _postcodeSection() {
    return WizardSection(
      title: 'Postcode',
      note: 'Your postcode decides which GoOuts cafés and restaurants show as '
          'nearby on your listing, so it needs to be right.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _postcodeCtrl,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _findAddress(),
              onChanged: (_) => setState(() {}),
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(10),
                // Uppercase as you type. A postcode typed in lower case is
                // still valid but looks wrong back on the listing.
                TextInputFormatter.withFunction(
                    (old, now) => now.copyWith(text: now.text.toUpperCase())),
              ],
              decoration: const InputDecoration(
                hintText: 'e.g. SW1A 1AA',
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _searching ? null : _findAddress,
              style: ElevatedButton.styleFrom(
                backgroundColor: GoOutsColors.primary,
                minimumSize: const Size(112, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Find',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressList() {
    return Container(
      decoration: BoxDecoration(
        color: GoOutsColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < _results.length; i++) ...<Widget>[
            InkWell(
              onTap: () => setState(() => _selected = i),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _selected == i
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _selected == i
                          ? GoOutsColors.primary
                          : GoOutsColors.body.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _results[i].fullAddress,
                        style: GoogleFonts.inter(
                          color: GoOutsColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i != _results.length - 1)
              const Divider(
                  height: 1, indent: 56, color: GoOutsColors.background),
          ],
        ],
      ),
    );
  }

  Widget _manualSection() {
    if (!_manual) {
      return TextButton.icon(
        onPressed: () => setState(() {
          _manual = true;
          _selected = null;
        }),
        icon: const Icon(Icons.edit_location_alt_outlined,
            color: GoOutsColors.primary, size: 20),
        label: Text(
          'Enter address manually',
          style: GoogleFonts.inter(
            color: GoOutsColors.primary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    }

    return WizardSection(
      title: 'Address',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _line1Ctrl,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'House number and street',
              hintText: 'e.g. 12 East Hill',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _townCtrl,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Town or city',
              hintText: 'e.g. London',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _manual = false),
              child: const Text('Search by postcode instead'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GoOutsColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: GoOutsColors.warning.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded,
                size: 18, color: GoOutsColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                    fontSize: 13, color: GoOutsColors.body, height: 1.4),
              ),
            ),
          ],
        ),
      );
}
