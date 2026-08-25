// ─────────────────────────────────────────────────────────────────────────────
//  Make a damage claim.
//
//  Rewritten 25 August 2026. Was Stitch output, imported 4 August and never
//  wired — unreachable, with `onPressed: () {}` on every button and placeholder
//  figures on screen.
//
//  ── ⚠ WHAT THIS SCREEN IS ACTUALLY DOING ────────────────────────────────────
//
//  Taking up to £150 off a named person on the strength of a photograph. It is
//  the most consequential form in the host app, and it is the one that had no
//  code behind it.
//
//  So it is built to be answerable, not just to be submitted:
//
//    THE CAP IS SHOWN, NOT DISCOVERED. The deposit is read off the booking and
//    displayed before anything is typed. A host who enters £900 is told why it
//    will not go through while they can still change it — not after.
//
//    THE GUEST'S EVIDENCE IS NAMED BEFORE SUBMITTING. The panel says how many
//    arrival photographs will be attached automatically. A host who knows the
//    other side is documented writes a more careful claim.
//
//    THE WINDOW IS ON SCREEN. 72 hours from check-out, from the booking's own
//    snapshot — not from today's config, which could have changed since.
//
//    ⚠ NOTHING IS PROMISED ABOUT MONEY. No payment provider is connected;
//    depositPreAuth.status is "none" on every booking and nothing is held
//    anywhere. This screen says a decision is made by GoOuts and settles later.
//    It must never say the money is on its way.
//
//  ⚠ EVERY REFUSAL SHOWN HERE IS THE SERVER'S OWN WORDING. submitStayClaim
//  writes its errors to be read by a host. Replacing them with "Something went
//  wrong" throws away the only part that tells them what to do.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/goouts_colors.dart';
import '../../../services/image_orientation.dart';
import 'host_claims_service.dart';

class MakeClaimScreen extends StatefulWidget {
  const MakeClaimScreen({super.key, this.bookingId});

  /// Passed as a route argument from the booking details screen. Null only if
  /// something navigated here directly, which the build guards against rather
  /// than crashing.
  final String? bookingId;

  @override
  State<MakeClaimScreen> createState() => _MakeClaimScreenState();
}

class _MakeClaimScreenState extends State<MakeClaimScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final List<File> _photos = <File>[];

  bool _loading = true;
  bool _submitting = false;
  String _error = '';

  String _bookingId = '';
  String _guestName = '';
  DateTime? _checkOut;
  int _depositPence = 15000;
  int _windowHours = 72;
  int _evidenceCount = 0;
  bool _alreadyOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String id = widget.bookingId ??
        (ModalRoute.of(context)?.settings.arguments as String? ?? '');
    if (id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No booking was selected.';
      });
      return;
    }
    _bookingId = id;

    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('stay_bookings')
          .doc(id)
          .get();
      if (!mounted) return;

      if (!snap.exists) {
        setState(() {
          _loading = false;
          _error = 'That booking no longer exists.';
        });
        return;
      }
      final Map<String, dynamic> b = snap.data() ?? const <String, dynamic>{};

      // ⚠ THE WINDOW COMES OFF THE BOOKING, NOT OFF TODAY'S CONFIG.
      // createStayBooking snapshots it precisely so that changing
      // platform_config cannot retroactively close a window a host was relying
      // on. The server reads it the same way — see submitStayClaim.
      _windowHours = (b['claimWindowHours'] as num?)?.toInt() ?? 72;
      _depositPence = (b['depositPence'] as num?)?.toInt() ??
          ((b['depositPreAuth'] as Map<dynamic, dynamic>?)?['amount'] as num?)
              ?.toInt() ??
          15000;
      _checkOut = (b['checkOut'] as Timestamp?)?.toDate();
      _guestName = (b['guestName'] ?? b['guestFullName'] ?? '') as String;

      // How many arrival photographs exist. Shown before submitting so the host
      // knows the other side is documented.
      final AggregateQuerySnapshot count = await FirebaseFirestore.instance
          .collection('stay_bookings')
          .doc(id)
          .collection('evidence')
          .count()
          .get();
      final bool open = await HostClaimsService.instance.hasOpenClaim(id);

      if (!mounted) return;
      setState(() {
        _evidenceCount = count.count ?? 0;
        _alreadyOpen = open;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load that booking. $e';
      });
    }
  }

  DateTime? get _deadline =>
      _checkOut?.add(Duration(hours: _windowHours));

  bool get _windowClosed {
    final DateTime? d = _deadline;
    return d != null && DateTime.now().isAfter(d);
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 6) return;
    try {
      // ⚠ NO imageQuality / maxWidth. Either makes image_picker re-encode and
      // DROP the EXIF orientation tag without rotating the pixels — a sideways
      // photograph with nothing left to say so. The resize happens in
      // normaliseOrientation, after the rotation is baked in.
      final XFile? shot = await _picker.pickImage(source: ImageSource.camera);
      if (shot == null || !mounted) return;
      final String upright = await normaliseOrientation(shot.path);
      if (!mounted) return;
      setState(() => _photos.add(File(upright)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not add that photo. $e');
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final String description = _descriptionController.text.trim();
    final double amount =
        double.tryParse(_amountController.text.trim().replaceAll(',', '')) ?? 0;
    final int pence = (amount * 100).round();

    if (description.length < 20) {
      setState(() => _error =
          'Describe the damage in a little more detail — at least a sentence.');
      return;
    }
    if (pence <= 0) {
      setState(() => _error = 'Enter the amount you are claiming.');
      return;
    }
    if (pence > _depositPence) {
      setState(() => _error =
          'A claim cannot be more than the £${_money(_depositPence)} deposit.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      final List<String> urls = <String>[];
      for (final File f in _photos) {
        final String? u =
            await HostClaimsService.instance.uploadClaimPhoto(f);
        // ⚠ A FAILED UPLOAD DOES NOT SILENTLY DROP A PHOTOGRAPH. The host
        // believes they attached six; submitting four without saying so
        // weakens their own case and they would never know why.
        if (u == null) {
          throw ClaimError(
              'One of the photos would not upload. Check your connection '
              'and try again.');
        }
        urls.add(u);
      }

      await HostClaimsService.instance.submit(
        bookingId: _bookingId,
        amountPence: pence,
        description: description,
        photoUrls: urls,
      );
      if (!mounted) return;
      await _showSubmitted();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ClaimError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  Future<void> _showSubmitted() => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Claim submitted'),
          content: Text(
            // ⚠ NO PROMISE OF MONEY. Nothing is held on this booking and there
            // is no provider connected. Saying "the funds will be released"
            // here would be a host chasing us in 48 hours.
            'Your guest has been notified and has 72 hours to respond. '
            'Their arrival photos were attached to the claim automatically.\n\n'
            'GoOuts reviews every claim and will confirm the outcome.',
            style: GoogleFonts.inter(fontSize: 13.5, height: 1.5),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  static String _money(int pence) => (pence / 100).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GoOutsColors.background,
      appBar: AppBar(
        backgroundColor: GoOutsColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GoOutsColors.navy),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Report damage',
            style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: GoOutsColors.navy)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blockedReason() ?? _form(),
    );
  }

  /// The three states where the form must not be shown at all, each saying
  /// which one it is. A greyed-out form with no explanation is the thing people
  /// fill in twice before giving up.
  Widget? _blockedReason() {
    if (_bookingId.isEmpty) return _notice(Icons.error_outline, _error);
    if (_alreadyOpen) {
      return _notice(Icons.hourglass_top_rounded,
          'There is already an open claim on this booking. You can follow it '
          'from your claims list.');
    }
    if (_windowClosed) {
      return _notice(
          Icons.lock_clock,
          'The $_windowHours hour window for claiming on this stay closed on '
          '${_fmt(_deadline)}. Claims cannot be opened after it.');
    }
    return null;
  }

  Widget _notice(IconData icon, String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 52, color: GoOutsColors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.55,
                      color: GoOutsColors.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _form() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: <Widget>[
          _guestCard(),
          _deadlineCard(),
          const SizedBox(height: 16),
          _evidenceCard(),
          const SizedBox(height: 20),
          _label('What was damaged?'),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            maxLines: 6,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Which room, what was damaged, and what it will cost '
                  'to put right. Be specific — your guest and a reviewer will '
                  'both read this.',
              hintStyle: GoogleFonts.inter(
                  color: GoOutsColors.onSurfaceVariant, fontSize: 13),
              filled: true,
              fillColor: GoOutsColors.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          _label('Amount you are claiming'),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              prefixText: '£ ',
              hintText: '0.00',
              // ⚠ THE CAP IS STATED UP FRONT. Finding out after typing £900
              // that the ceiling is £150 reads as a bait and switch.
              helperText:
                  'Up to £${_money(_depositPence)} — the deposit held for '
                  'this booking',
              helperStyle: GoogleFonts.inter(fontSize: 11.5),
              filled: true,
              fillColor: GoOutsColors.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          _label('Your photos of the damage'),
          const SizedBox(height: 8),
          _photoRow(),
          const SizedBox(height: 24),
          if (_error.isNotEmpty) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: const Color(0xFFB91C1C))),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: GoOutsColors.navy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Submit claim',
                      style: GoogleFonts.inter(
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'GoOuts reviews every claim. Submitting one does not take money '
            'from your guest by itself.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 11.5,
                height: 1.45,
                color: GoOutsColors.onSurfaceVariant),
          ),
        ],
      );

  /// ⚠ THE GUEST IS NAMED ON THE FORM THAT ACCUSES THEM.
  ///
  /// The analyzer caught _guestName as unused on 25 August — I loaded it off
  /// the booking and never put it on screen. The lazy fix is to delete the
  /// field. It is the wrong one.
  ///
  /// This form takes up to £150 off a specific person. A host filling it in
  /// while looking at a name writes differently from one filling in a form
  /// about "the guest", and the sentence they write is read by that person and
  /// by whoever decides. Anonymity on this screen only ever helps the side
  /// making the accusation.
  Widget _guestCard() {
    if (_guestName.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.person_outline_rounded,
                size: 20, color: GoOutsColors.navy),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This claim is against $_guestName. They will see everything '
                'you write here.',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: GoOutsColors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deadlineCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.schedule, color: Color(0xFFC2410C), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _deadline == null
                    ? 'Claims must be opened within $_windowHours hours of '
                        'check-out.'
                    : 'You have until ${_fmt(_deadline)} to open a claim on '
                        'this stay.',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: const Color(0xFF9A3412)),
              ),
            ),
          ],
        ),
      );

  /// ⚠ THIS PANEL IS WHY THE GUEST CAPTURE FLOW EXISTS. Saying it out loud
  /// before the host writes their claim is the whole point — it is the moment
  /// the promise made to the guest becomes visible to the other party.
  Widget _evidenceCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.photo_library_outlined,
                color: GoOutsColors.navy, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _evidenceCount == 0
                    ? 'Your guest did not photograph this property on arrival. '
                        'A reviewer will see that too.'
                    : '$_evidenceCount arrival ${_evidenceCount == 1 ? 'photo' : 'photos'} '
                        'from your guest will be attached to this claim '
                        'automatically, and frozen as they are now.',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: GoOutsColors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );

  Widget _photoRow() => SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _photos.length + (_photos.length < 6 ? 1 : 0),
          separatorBuilder: (BuildContext ctx, int index) => const SizedBox(width: 10),
          itemBuilder: (BuildContext c, int i) {
            if (i == _photos.length) {
              return InkWell(
                onTap: _addPhoto,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 88,
                  decoration: BoxDecoration(
                    color: GoOutsColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GoOutsColors.border),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined,
                      color: GoOutsColors.navy),
                ),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_photos[i],
                  width: 88, height: 88, fit: BoxFit.cover),
            );
          },
        ),
      );

  Widget _label(String s) => Text(s,
      style: GoogleFonts.inter(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: GoOutsColors.navy));

  static String _fmt(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} at ${two(d.hour)}:${two(d.minute)}';
  }
}
