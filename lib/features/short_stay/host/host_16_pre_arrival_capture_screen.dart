// Pre-arrival capture — the host photographs each room before a guest arrives.
//
// ── WIRED 8 August 2026. WHAT IT WAS ───────────────────────────────────────
//
// A Stitch export with "Room 1 of 4", a hardcoded room list and one empty
// handler. It captured nothing.
//
// Its own copy said the important thing already:
//
//     "It is important to photograph your property now. You cannot later
//      claim a room was perfect if you do not have a record of it."
//
// That sentence was true and the screen did not honour it.
//
// ── WHY THIS SCREEN IS URGENT AND CLAIMS ARE NOT ───────────────────────────
//
// Claims logic can be added at any time. THIS cannot. The photographs have to
// exist before the guest walks in, and that window closes as each booking
// starts. Every stay that happens without a pre-arrival pack is a stay no
// claim can ever be made about, retrospectively or otherwise.
//
// ── SAME SERVICE, SAME COLLECTION, SAME SHAPE AS THE GUEST APP ─────────────
//
// StayEvidenceService is ported from goouts_app and writes into
// stay_bookings/{id}/evidence alongside the guest's own arrival and departure
// photographs. A claim is settled by comparing the sets, so they must be
// comparable — same compression, same field names, same server timestamps.
//
// ── APPEND ONLY. THERE IS NO DELETE, AND THAT IS THE POINT. ────────────────
//
// firestore.rules: `allow update, delete: if false` on evidence, for everyone
// including admins. A host cannot retake a photograph to look better later,
// and neither can we. Retention deletion is a scheduled Admin SDK job.
//
// So the screen never offers a delete, and says why. A host who expects to be
// able to tidy up afterwards should learn that before they photograph, not
// after.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/goouts_colors.dart';
import '../models/stay_evidence.dart';
import '../services/stay_evidence_service.dart';
import 'host_bottom_nav.dart';

class HostPreArrivalCaptureScreen extends StatefulWidget {
  const HostPreArrivalCaptureScreen({super.key});

  @override
  State<HostPreArrivalCaptureScreen> createState() =>
      _HostPreArrivalCaptureScreenState();
}

class _HostPreArrivalCaptureScreenState
    extends State<HostPreArrivalCaptureScreen> {
  final _picker = ImagePicker();
  final _service = StayEvidenceService.instance;

  String? _bookingId;
  String? _busyRoom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bookingId ??= ModalRoute.of(context)?.settings.arguments as String?;
  }

  /// Recorded on every photograph so a dispute can tell an iPhone capture from
  /// an Android one. No package_info_plus in this project, so the version is a
  /// constant — it changes when the app does.
  static const String _appVersion = 'goouts_host 1.0';
  String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<void> _capture(String room) async {
    if (_bookingId == null) return;
    setState(() => _busyRoom = room);
    try {
      // CAMERA ONLY, not the gallery. A pre-arrival photograph chosen from the
      // camera roll could be of anything, taken at any time — which is exactly
      // what the other side would argue in a dispute. Taking it now, in the
      // room, is the whole value.
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        imageQuality: 92,
      );
      if (shot == null) {
        if (mounted) setState(() => _busyRoom = null);
        return;
      }

      await _service.capture(
        bookingId: _bookingId!,
        kind: CaptureKind.hostPreArrival,
        room: room,
        photo: File(shot.path),
        platform: _platform,
        appVersion: _appVersion,
      );
      if (!mounted) return;
      setState(() => _busyRoom = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyRoom = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save that photograph. $e'),
        backgroundColor: GoOutsColors.error,
      ));
    }
  }

  Future<void> _skip(String room) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Skip this room?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'A skip is recorded permanently and cannot be undone. If '
                'there is ever a dispute about this room, the record will '
                'show you chose not to photograph it.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Why are you skipping it?',
                  hintText: 'e.g. room is locked and not part of the let',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Go back')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Skip it'),
            ),
          ],
        );
      },
    );
    if (reason == null || _bookingId == null) return;

    setState(() => _busyRoom = room);
    try {
      await _service.skip(
        bookingId: _bookingId!,
        kind: CaptureKind.hostPreArrival,
        room: room,
        reason: reason.isEmpty ? 'No reason given' : reason,
      );
      if (mounted) setState(() => _busyRoom = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyRoom = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not record that. $e'),
        backgroundColor: GoOutsColors.error,
      ));
    }
  }

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
          'Before the guest arrives',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _bookingId == null
          ? _notice('No booking was selected. Open a booking and choose '
              '"Photograph the rooms".')
          : _bookingBody(_bookingId!),
      bottomNavigationBar: const HostBottomNav(current: HostTab.bookings),
    );
  }

  /// booking -> listingId -> captureRooms.
  ///
  /// ⚠ captureRooms is read from the LISTING, not the booking, because
  /// createStayBooking does not snapshot it. That means a host who edits their
  /// property mid-stay could change the room list under an evidence pack that
  /// is already half captured. Recorded rather than quietly accepted: the fix
  /// is to snapshot captureRooms onto the booking at creation, which is a
  /// server change and belongs with the claims work.
  Widget _bookingBody(String bookingId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stay_bookings')
          .doc(bookingId)
          .snapshots(),
      builder: (context, bSnap) {
        if (bSnap.hasError) {
          return _notice('Could not load the booking.\n${bSnap.error}');
        }
        if (!bSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!bSnap.data!.exists) {
          return _notice('That booking no longer exists.');
        }

        final listingId = (bSnap.data!.data()?['listingId'] ?? '').toString();
        if (listingId.isEmpty) {
          return _notice('This booking has no property attached.');
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('stay_listings')
              .doc(listingId)
              .snapshots(),
          builder: (context, lSnap) {
            if (lSnap.hasError) {
              return _notice('Could not load the property.\n${lSnap.error}');
            }
            if (!lSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final rooms = ((lSnap.data!.data()?['captureRooms'] as List?) ??
                    const <dynamic>[])
                .map((e) => e.toString())
                .toList();

            if (rooms.isEmpty) {
              return _notice(
                  'No rooms are listed for this property, so there is nothing '
                  'to photograph. Contact support.');
            }

            return StreamBuilder<List<StayEvidence>>(
              stream: _service.watchKind(
                  bookingId, CaptureKind.hostPreArrival),
              builder: (context, eSnap) {
                if (eSnap.hasError) {
                  return _notice(
                      'Could not load what you have already captured.\n'
                      '${eSnap.error}');
                }
                final done = <String, StayEvidence>{};
                for (final e in eSnap.data ?? const <StayEvidence>[]) {
                  // First entry per room wins. Append-only means a second
                  // photograph of the same room is possible; the first is the
                  // one taken before the guest arrived.
                  done.putIfAbsent(e.room, () => e);
                }
                return _list(bookingId, rooms, done);
              },
            );
          },
        );
      },
    );
  }

  Widget _list(String bookingId, List<String> rooms,
      Map<String, StayEvidence> done) {
    final complete = rooms.where(done.containsKey).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        // Progress, honestly counted. Stitch said "Room 1 of 4" regardless.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: complete == rooms.length
                ? GoOutsColors.success.withValues(alpha: 0.08)
                : GoOutsColors.tint.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$complete of ${rooms.length} rooms recorded',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: GoOutsColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                complete == rooms.length
                    ? 'Done. Every room has a record from before the guest '
                        'arrived.'
                    : 'Photograph each room before the guest arrives. You '
                        'cannot later claim a room was in good order if there '
                        'is no record of it.',
                style: GoogleFonts.inter(
                    fontSize: 13, color: GoOutsColors.body, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Said BEFORE they start, not after.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: GoOutsColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: GoOutsColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: GoOutsColors.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Photographs are taken with the camera and cannot be chosen '
                  'from your library, edited or deleted afterwards — by you, '
                  'by the guest, or by GoOuts. That is what makes them worth '
                  'anything in a dispute.',
                  style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: GoOutsColors.body,
                      height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final room in rooms) ...<Widget>[
          _roomCard(bookingId, room, done[room]),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _roomCard(String bookingId, String room, StayEvidence? evidence) {
    final busy = _busyRoom == room;
    final captured = evidence != null && !evidence.skipped;
    final skipped = evidence != null && evidence.skipped;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GoOutsColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: captured
              ? GoOutsColors.success.withValues(alpha: 0.4)
              : (skipped
                  ? GoOutsColors.warning.withValues(alpha: 0.4)
                  : GoOutsColors.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (captured)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                evidence.url,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 64,
                  height: 64,
                  color: GoOutsColors.background,
                  child: const Icon(Icons.broken_image_outlined, size: 18),
                ),
              ),
            )
          else
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: GoOutsColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                skipped
                    ? Icons.remove_circle_outline_rounded
                    : Icons.photo_camera_outlined,
                color: skipped
                    ? GoOutsColors.warning
                    : GoOutsColors.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  room,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: GoOutsColors.navy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  captured
                      ? 'Recorded${evidence.takenAt == null ? "" : " ${_when(evidence.takenAt!)}"}'
                      : (skipped
                          ? 'Skipped — ${evidence.skipReason ?? ""}'
                          : 'Not recorded yet'),
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: captured
                        ? GoOutsColors.success
                        : (skipped
                            ? GoOutsColors.warning
                            : GoOutsColors.body),
                  ),
                ),
                if (!captured && !skipped) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: busy ? null : () => _capture(room),
                        icon: busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.photo_camera_rounded, size: 17),
                        label: const Text('Photograph'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: busy ? null : () => _skip(room),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _when(DateTime d) {
    final l = d.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day} ${_months[l.month - 1]}, $hh:$mm';
  }

  Widget _notice(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 13.5, color: GoOutsColors.body, height: 1.5),
          ),
        ),
      );
}
