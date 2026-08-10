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
// ── HOUSE NUMBER + POSTCODE, MATCHING EVERY REGISTRATION SCREEN ────────────
//
// CHANGED 9 August 2026. This screen used to send the postcode alone to
// validatePostcode(). That is not what the rest of GoOuts does, and it is
// worse for a reason that is easy to miss:
//
//   ⚠ A BARE POSTCODE ONLY EVER RESOLVES TO THE POSTCODE CENTROID.
//     Mapbox does not return a per-building list from a postcode by itself.
//     Give it "{house number} {postcode}" together and it matches the SPECIFIC
//     building. That is why driver_app's business_registration_screen asks for
//     Shop/Unit No first, and it is the pattern all four registration screens
//     settled on after the postcode work in early August.
//
// So this screen now asks for the house or flat number and the postcode, and
// calls suggest() with both joined — identical to registration, just relabelled
// for a home rather than a shop.
//
// ── suggest() THEN retrieve(), NOT validatePostcode() ──────────────────────
//
// suggest() is the free, session-billed call that returns candidate buildings.
// retrieve() is the billed one that returns full detail — street, town,
// coordinates — and is only called once, when the host taps their address.
//
// The session token is ROTATED immediately after retrieve(). Mapbox bills a
// session, not a keystroke: every suggest() inside one session is free and the
// retrieve() closes it. Reusing a spent token would start charging for the
// suggests too. AddressLookupService.generateSessionToken() exists for this.
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

  final _houseNoCtrl = TextEditingController();
  final _postcodeCtrl = TextEditingController();
  final _line1Ctrl = TextEditingController();
  final _townCtrl = TextEditingController();

  /// One Mapbox session covers every free suggest() until a retrieve() closes
  /// it. Rotated after each retrieve — see the note at the top of the file.
  String _sessionToken = AddressLookupService.generateSessionToken();

  bool _searching = false;
  bool _resolving = false;
  String? _error;
  List<MapboxSuggestResult> _suggestions = const <MapboxSuggestResult>[];

  /// The address the host picked, fully resolved. Null until they tap one.
  MapboxAddressResult? _chosen;

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
    _houseNoCtrl.dispose();
    _postcodeCtrl.dispose();
    _line1Ctrl.dispose();
    _townCtrl.dispose();
    super.dispose();
  }

  /// Asks Mapbox for buildings matching "{house number} {postcode}".
  ///
  /// Both parts are required. Sending the postcode alone returns the postcode
  /// centroid rather than a list of buildings — the reason this screen was
  /// changed. See the header note.
  Future<void> _findAddress() async {
    final house = _houseNoCtrl.text.trim();
    final postcode = _postcodeCtrl.text.trim();

    if (house.isEmpty) {
      setState(() => _error = 'Enter the house or flat number first.');
      return;
    }
    if (postcode.isEmpty) {
      setState(() => _error = 'Enter a postcode too.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _suggestions = const <MapboxSuggestResult>[];
      _chosen = null;
    });

    try {
      final found = await _lookup.suggest('$house $postcode', _sessionToken);
      if (!mounted) return;
      setState(() {
        _suggestions = found;
        _searching = false;
        if (found.isEmpty) {
          _error = 'No address found for that number and postcode. Check both, '
              'or enter the address yourself below.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      // Shown, not swallowed. A lookup that fails silently leaves the host
      // staring at an empty list with no idea whether to wait or retype.
      setState(() {
        _searching = false;
        _error = 'Could not look up that address. Check your connection, or '
            'enter the address yourself below.';
      });
    }
  }

  /// The host tapped a suggestion. retrieve() is the billed call and returns
  /// the full detail — street, town, coordinates.
  Future<void> _onSuggestionTapped(MapboxSuggestResult s) async {
    setState(() {
      _resolving = true;
      _error = null;
    });

    try {
      final full = await _lookup.retrieve(s.mapboxId, _sessionToken);

      // Rotate REGARDLESS of the outcome. The session is spent either way, and
      // reusing a spent token starts billing the free suggests.
      _sessionToken = AddressLookupService.generateSessionToken();

      if (!mounted) return;
      if (full == null) {
        setState(() {
          _resolving = false;
          _error = 'Could not load that address — please try again.';
        });
        return;
      }
      setState(() {
        _chosen = full;
        _suggestions = const <MapboxSuggestResult>[];
        _resolving = false;
      });
    } catch (_) {
      _sessionToken = AddressLookupService.generateSessionToken();
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'Could not load that address — please try again.';
      });
    }
  }

  bool get _canContinue {
    if (_manual) {
      return _postcodeCtrl.text.trim().isNotEmpty &&
          _line1Ctrl.text.trim().isNotEmpty &&
          _townCtrl.text.trim().isNotEmpty;
    }
    return _chosen != null;
  }

  void _saveAndContinue() {
    if (_manual) {
      _draft.line1 = _line1Ctrl.text.trim();
      _draft.town = _townCtrl.text.trim();
      _draft.postcode = AddressLookupService.normalise(_postcodeCtrl.text);
    } else {
      final r = _chosen!;
      // line1 is house number + street where Mapbox gives both, falling back
      // to the first line of the formatted address. Sending the whole
      // fullAddress would repeat the town and postcode inside line1, and they
      // would then appear twice on the listing.
      //
      // The typed house number is the fallback for the fallback: Mapbox
      // occasionally resolves a flat to its building without a number, and the
      // host has already told us which one it is.
      final number = (r.houseNumber ?? '').trim().isNotEmpty
          ? r.houseNumber!.trim()
          : _houseNoCtrl.text.trim();
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
        if (!_manual) _lookupSection(),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          _notice(_error!),
        ],
        if (_suggestions.isNotEmpty && !_manual) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            'Select your address',
            style: GoogleFonts.inter(
              color: GoOutsColors.navy,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _suggestionList(),
        ],
        if (_chosen != null && !_manual) ...<Widget>[
          const SizedBox(height: 20),
          _chosenCard(),
        ],
        const SizedBox(height: 16),
        _manualSection(),
      ],
    );
  }

  /// House/flat number and postcode, side by side, then Find.
  ///
  /// The number is FIRST and narrower — it is the shorter answer and the one
  /// people reach for first when asked where they live.
  Widget _lookupSection() {
    return WizardSection(
      title: 'Find your address',
      note: 'Your postcode decides which GoOuts cafés and restaurants show as '
          'nearby on your listing, so it needs to be right.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Narrower: a house number is rarely more than 3-4 characters,
              // and giving it equal width to the postcode makes the postcode
              // field feel cramped on a small phone.
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _houseNoCtrl,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'House/Flat No',
                    hintText: 'e.g. 12B',
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                    TextInputFormatter.withFunction((old, now) =>
                        now.copyWith(text: now.text.toUpperCase())),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Postcode',
                    hintText: 'e.g. SW1A 1AA',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_searching || _resolving) ? null : _findAddress,
              style: ElevatedButton.styleFrom(
                backgroundColor: GoOutsColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: (_searching || _resolving)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Find address',
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

  Widget _suggestionList() {
    return Container(
      decoration: BoxDecoration(
        color: GoOutsColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < _suggestions.length; i++) ...<Widget>[
            InkWell(
              onTap: _resolving ? null : () => _onSuggestionTapped(_suggestions[i]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.location_on_outlined,
                        size: 20, color: GoOutsColors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _suggestions[i].name,
                            style: GoogleFonts.inter(
                              color: GoOutsColors.navy,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          // placeFormatted, NOT fullAddress. fullAddress is the
                          // combined string and already contains `name`, so
                          // pairing the two repeats the house number twice in
                          // the same row.
                          if (_suggestions[i].placeFormatted.trim().isNotEmpty)
                            Text(
                              _suggestions[i].placeFormatted,
                              style: GoogleFonts.inter(
                                color: GoOutsColors.body,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: GoOutsColors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (i != _suggestions.length - 1)
              const Divider(
                  height: 1, indent: 50, color: GoOutsColors.background),
          ],
        ],
      ),
    );
  }

  /// Shown once retrieve() has resolved the address, so the host can see
  /// exactly what will go on the listing before continuing.
  Widget _chosenCard() {
    final r = _chosen!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GoOutsColors.successBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GoOutsColors.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: GoOutsColors.success),
              const SizedBox(width: 8),
              Text(
                'Address confirmed',
                style: GoogleFonts.inter(
                  color: GoOutsColors.navy,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            r.fullAddress,
            style: GoogleFonts.inter(
              color: GoOutsColors.navy,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() {
              _chosen = null;
              _suggestions = const <MapboxSuggestResult>[];
            }),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: const Text('Search again'),
          ),
        ],
      ),
    );
  }

  Widget _manualSection() {
    if (!_manual) {
      return TextButton.icon(
        onPressed: () => setState(() {
          _manual = true;
          _chosen = null;
          _suggestions = const <MapboxSuggestResult>[];
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
