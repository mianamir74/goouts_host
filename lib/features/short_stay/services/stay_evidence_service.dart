import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/stay_evidence.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Capture, compress, upload, record.
//
// ⚠ PORTED FROM goouts_app ON 8 AUGUST 2026 AND KEPT DELIBERATELY IDENTICAL.
//
// The guest photographs each room on arrival and departure; the host
// photographs the same rooms before the guest arrives. Both write into
// stay_bookings/{bookingId}/evidence. A claim is settled by comparing the two
// sets — so if the apps compress, name or shape things differently the packs
// are not comparable and the mechanism is decorative.
//
// The pubspec pins `image` and `path_provider` to the SAME versions as
// goouts_app for the same reason: two different majors would resize and encode
// differently, producing visibly different photographs on either side of one
// dispute.
//
// If this file and goouts_app/lib/features/short_stay/services/
// stay_evidence_service.dart ever diverge, THAT is the bug.
//
// ── MEMORY DISCIPLINE IS NOT OPTIONAL HERE ─────────────────────────────────
//
// iOS has killed this app for memory before. A modern phone photograph is 4 to
// 8 MB decoded, and a seven room capture wants seven of them. The rule is
// absolute:
//
//     NEVER HOLD MORE THAN ONE FULL RESOLUTION IMAGE IN MEMORY.
//     Compress to a temp file, upload FROM THE FILE, delete the temp file.
//
// Do not "optimise" this by keeping bytes in a list to retry an upload. That
// is what kills the app.
// ─────────────────────────────────────────────────────────────────────────────

class StayEvidenceService {
  StayEvidenceService._();
  static final instance = StayEvidenceService._();

  static const int _maxEdge = 1600;
  static const int _jpegQuality = 80;

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _col(String bookingId) =>
      _db.collection('stay_bookings').doc(bookingId).collection('evidence');

  /// Everything captured for a booking, both sides, oldest first.
  Stream<List<StayEvidence>> watch(String bookingId) => _col(bookingId)
      .orderBy('takenAt')
      .limit(200)
      .snapshots()
      .map((q) => q.docs.map(StayEvidence.fromDoc).toList(growable: false));

  /// One side of the pack. Used by the host to see their own pre-arrival set
  /// without the guest's photographs mixed in.
  Stream<List<StayEvidence>> watchKind(String bookingId, CaptureKind kind) =>
      _col(bookingId)
          .where('kind', isEqualTo: kind.wire)
          .limit(100)
          .snapshots()
          .map((q) => q.docs.map(StayEvidence.fromDoc).toList(growable: false));

  /// Compresses in place and returns a temp file. The caller MUST delete it,
  /// and `capture` below does.
  Future<File> _compress(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source;

    final resized = decoded.width > decoded.height
        ? img.copyResize(decoded, width: _maxEdge)
        : img.copyResize(decoded, height: _maxEdge);

    final jpg = img.encodeJpg(resized, quality: _jpegQuality);
    final dir = await getTemporaryDirectory();
    final out = File(
        '${dir.path}/stay_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await out.writeAsBytes(jpg, flush: true);
    return out;
  }

  /// The whole capture path for one room.
  ///
  /// `takenAt` is a SERVER timestamp. A device clock can be changed by the
  /// person holding the phone, and a timestamp either party controls would
  /// make the entire pack worthless in a dispute. firestore.rules rejects any
  /// create where takenAt != request.time, so getting this wrong fails loudly.
  Future<void> capture({
    required String bookingId,
    required CaptureKind kind,
    required String room,
    required File photo,
    required String platform,
    required String appVersion,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    File? temp;
    try {
      temp = await _compress(photo);

      final id = _col(bookingId).doc().id;
      // Matches storage.rules: stay/{bookingId}/{kind}/{fileName}
      final path = 'stay/$bookingId/${kind.wire}/$id.jpg';
      final ref = _storage.ref(path);

      await ref.putFile(
        temp,
        SettableMetadata(
          contentType: 'image/jpeg',
          cacheControl: 'public, max-age=31536000',
        ),
      );
      final url = await ref.getDownloadURL();

      await _col(bookingId).doc(id).set(StayEvidence.createPayload(
            kind: kind,
            room: room,
            storagePath: path,
            url: url,
            capturedBy: uid,
            platform: platform,
            appVersion: appVersion,
          ));
    } finally {
      // Always, even if the upload threw. A leaked temp file per capture would
      // fill the device.
      if (temp != null && temp.path != photo.path) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  /// A skip is evidence too. It is recorded, and it counts against whoever
  /// skipped it if there is ever a claim. Never silently ignore one.
  Future<void> skip({
    required String bookingId,
    required CaptureKind kind,
    required String room,
    required String reason,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _col(bookingId).add(StayEvidence.skipPayload(
      kind: kind,
      room: room,
      capturedBy: uid,
      reason: reason,
    ));
  }
}
