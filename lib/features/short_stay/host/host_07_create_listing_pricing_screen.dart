// Step 6: price, cleaning fee, cancellation policy and booking mode.
//
// WIRED 8 August 2026. The Stitch version showed "£120" as static text with no
// input, a policy selector that wrote nowhere, and one empty handler.
//
// ── EVERY FIGURE ON THIS SCREEN IS HELD IN PENCE ───────────────────────────
//
// nightlyRatePence and cleaningFeePence, not pounds. Money as a double is how
// £120.10 becomes £120.09999999999999 and a guest is charged a penny less
// than the host was told. The server takes pence too — num(d.nightlyRate,
// 100, 500000) — so pounds anywhere in this file would be a units mismatch
// that reads as a plausible price.
//
// The minimum is 100 pence. A host who types 0.50 is rejected by the server
// with "invalid-argument", so it is caught here instead with an explanation.
//
// ── WHAT THE HOST IS ACTUALLY CHOOSING ─────────────────────────────────────
//
// The cancellation policy is not a label. cancellationSnapshot() in
// stay_booking.js reads it at booking time and writes the refund terms ONTO
// the booking, so the choice made here decides what a guest gets back months
// later. The wording below describes the real behaviour rather than saying
// "moderate" and leaving a host to guess.
//
// ⚠ The exact windows come from platform_config, which this app cannot read
// (admin-only, deliberately — a client that can read the commission rate is
// one step from a client that computes prices). So the descriptions are
// qualitative on purpose. Do not hardcode day counts here; they would drift
// from the server the first time an admin edits the economics.
//
// Booking mode is the bigger decision and is described as such. 'instant'
// means a stranger can book the property without the host ever approving it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_routes.dart';
import 'listing_draft.dart';
import 'wizard_shell.dart';

class PricingAndRulesScreen extends StatefulWidget {
  const PricingAndRulesScreen({super.key});

  @override
  State<PricingAndRulesScreen> createState() => _PricingAndRulesScreenState();
}

class _PricingAndRulesScreenState extends State<PricingAndRulesScreen> {
  final _draft = ListingDraft.instance;

  final _rateCtrl = TextEditingController();
  final _cleaningCtrl = TextEditingController();

  late String _policy;
  late String _mode;

  static const int _minPence = 100; // server floor
  static const int _maxPence = 500000;

  @override
  void initState() {
    super.initState();
    if (_draft.nightlyRatePence > 0) {
      _rateCtrl.text = _poundsFrom(_draft.nightlyRatePence);
    }
    if (_draft.cleaningFeePence > 0) {
      _cleaningCtrl.text = _poundsFrom(_draft.cleaningFeePence);
    }
    _policy = _draft.cancellationPolicy;
    _mode = _draft.bookingMode;
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    _cleaningCtrl.dispose();
    super.dispose();
  }

  static String _poundsFrom(int pence) =>
      pence % 100 == 0 ? '${pence ~/ 100}' : (pence / 100).toStringAsFixed(2);

  /// Pounds text -> pence. Returns null when it is not a usable number, so the
  /// caller can tell "empty" from "zero".
  static int? _penceFrom(String text) {
    final cleaned = text.trim().replaceAll('£', '').replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    final pounds = double.tryParse(cleaned);
    if (pounds == null || pounds.isNaN || pounds.isInfinite) return null;
    // Rounded, not truncated: 12.005 typed by hand should not become £12.00.
    return (pounds * 100).round();
  }

  int? get _ratePence => _penceFrom(_rateCtrl.text);
  int get _cleaningPence => _penceFrom(_cleaningCtrl.text) ?? 0;

  String? get _rateError {
    final p = _ratePence;
    if (p == null) return null; // nothing typed yet — not an error, just empty
    if (p < _minPence) return 'The minimum nightly rate is £1.00.';
    if (p > _maxPence) return 'That is above the maximum of £5,000 a night.';
    return null;
  }

  bool get _canContinue {
    final p = _ratePence;
    return p != null && p >= _minPence && p <= _maxPence && _cleaningPence <= 100000;
  }

  void _save() {
    _draft.nightlyRatePence = _ratePence!;
    _draft.cleaningFeePence = _cleaningPence;
    _draft.cancellationPolicy = _policy;
    _draft.bookingMode = _mode;
    Navigator.of(context).pushNamed(HostRoutes.newLegal);
  }

  @override
  Widget build(BuildContext context) {
    return HostWizardScaffold(
      step: 6,
      heading: 'Set your price and rules',
      subheading: 'You can change all of this at any time once the property '
          'is live.',
      canContinue: _canContinue,
      onNext: _save,
      children: <Widget>[
        WizardSection(
          title: 'Nightly rate',
          note: 'What you charge per night, before the cleaning fee.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _rateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  prefixText: '£ ',
                  hintText: '0.00',
                  errorText: _rateError,
                ),
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: GoOutsColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'GoOuts takes its commission from this. The amount you '
                'receive is shown on every booking request before you accept '
                'it.',
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: GoOutsColors.body, height: 1.4),
              ),
            ],
          ),
        ),
        WizardSection(
          title: 'Cleaning fee',
          note: 'Optional. Charged once per stay, not per night.',
          child: TextField(
            controller: _cleaningCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              LengthLimitingTextInputFormatter(7),
            ],
            decoration: const InputDecoration(
              prefixText: '£ ',
              hintText: '0.00',
            ),
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: GoOutsColors.navy,
            ),
          ),
        ),
        WizardSection(
          title: 'How guests book',
          note: 'This one matters. Change it later if you are unsure now.',
          child: Column(
            children: <Widget>[
              _radio(
                value: 'request',
                group: _mode,
                onChanged: (v) => setState(() => _mode = v),
                title: 'Ask me first',
                body: 'Every booking comes to you as a request. Nothing is '
                    'confirmed until you accept it. The nights are held while '
                    'you decide.',
              ),
              const SizedBox(height: 6),
              _radio(
                value: 'instant',
                group: _mode,
                onChanged: (v) => setState(() => _mode = v),
                title: 'Book instantly',
                body: 'Guests book without asking. You get more bookings and '
                    'no say over who stays. Only choose this if your calendar '
                    'is always up to date.',
              ),
            ],
          ),
        ),
        WizardSection(
          title: 'Cancellation policy',
          note: 'Decides what a guest gets refunded, and when. The terms are '
              'recorded on each booking as it is made, so changing this later '
              'never alters a booking somebody already has.',
          child: Column(
            children: <Widget>[
              _radio(
                value: 'flexible',
                group: _policy,
                onChanged: (v) => setState(() => _policy = v),
                title: 'Flexible',
                body: 'Full refund until shortly before check-in. Most '
                    'appealing to guests, least protection for you.',
              ),
              const SizedBox(height: 6),
              _radio(
                value: 'moderate',
                group: _policy,
                onChanged: (v) => setState(() => _policy = v),
                title: 'Moderate',
                body: 'Full refund up to a few days before, part refund after '
                    'that. The middle ground, and the default.',
              ),
              const SizedBox(height: 6),
              _radio(
                value: 'strict',
                group: _policy,
                onChanged: (v) => setState(() => _policy = v),
                title: 'Strict',
                body: 'Full refund only well in advance, smaller refund after. '
                    'Protects you most, puts some guests off.',
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
                  'Every guest also gets a short grace period to change their '
                  'mind after booking, on top of whichever policy you choose.',
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

  Widget _radio({
    required String value,
    required String group,
    required ValueChanged<String> onChanged,
    required String title,
    required String body,
  }) {
    final on = value == group;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on
              ? GoOutsColors.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? GoOutsColors.primary : GoOutsColors.border,
            width: on ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              on ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: on ? GoOutsColors.primary : GoOutsColors.border,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GoOutsColors.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: GoOutsColors.body,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
