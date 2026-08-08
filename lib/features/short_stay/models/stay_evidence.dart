import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// One captured photograph, or one recorded skip.
// Collection: stay_bookings/{bookingId}/evidence/{evidenceId}
//
// ⚠ PORTED VERBATIM FROM goouts_app ON 8 AUGUST 2026, AND THAT IS THE POINT.
//
// The guest photographs each room on arrival and again on departure. The host
// photographs the same rooms before the guest arrives. A claim is settled by
// comparing those sets — so if the two apps write different shapes into the
// same collection, the packs cannot be compared and the whole mechanism is
// decorative.
//
// If this file and goouts_app/lib/features/short_stay/models/stay_evidence.dart
// ever disagree, THAT is the bug. Change both.
//
// APPEND ONLY. No update, no delete, for anyone, including us. Enforced in
// firestore.rules rather than here:
//
//     allow create: if request.resource.data.capturedBy == request.auth.uid
//                   && request.resource.data.takenAt == request.time;
//     allow update, delete: if false;
//
// `takenAt` MUST be FieldValue.serverTimestamp(). A device clock is set by the
// person holding the phone, and a timestamp either party controls would make
// the entire pack worthless in a dispute. The rule above rejects anything else,
// so getting this wrong fails loudly rather than silently.
// ─────────────────────────────────────────────────────────────────────────────

/// Who took the photograph and when in the stay.
///
/// The `wire` values are checked by firestore.rules — a create carrying any
/// other value is refused. Do not add a case here without adding it there.
enum CaptureKind {
  hostPreArrival('host_pre_arrival'),
  guestCheckIn('guest_check_in'),
  guestCheckOut('guest_check_out');

  final String wire;
  const CaptureKind(this.wire);

  static CaptureKind from(String? v) => CaptureKind.values
      .firstWhere((e) => e.wire == v, orElse: () => CaptureKind.guestCheckIn);

  /// Worded from the HOST's point of view. goouts_app words the same values
  /// from the guest's — "You, on arrival" there is "The guest, on arrival"
  /// here. Same data, different reader.
  String get label => switch (this) {
        CaptureKind.hostPreArrival => 'You, before they arrived',
        CaptureKind.guestCheckIn => 'The guest, on arrival',
        CaptureKind.guestCheckOut => 'The guest, on departure',
      };
}

class StayEvidence {
  final String id;
  final CaptureKind kind;
  final String room;
  final String storagePath;
  final String url;
  final DateTime? takenAt;
  final String capturedBy;
  final bool skipped;
  final String? skipReason;

  const StayEvidence({
    required this.id,
    required this.kind,
    required this.room,
    required this.storagePath,
    required this.url,
    required this.takenAt,
    required this.capturedBy,
    required this.skipped,
    required this.skipReason,
  });

  factory StayEvidence.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return StayEvidence(
      id: doc.id,
      kind: CaptureKind.from(m['kind'] as String?),
      room: (m['room'] ?? '') as String,
      storagePath: (m['storagePath'] ?? '') as String,
      url: (m['url'] ?? '') as String,
      takenAt: (m['takenAt'] as Timestamp?)?.toDate(),
      capturedBy: (m['capturedBy'] ?? '') as String,
      skipped: (m['skipped'] ?? false) as bool,
      skipReason: m['skipReason'] as String?,
    );
  }

  /// The write payload. No id, no update path, and takenAt is a server value.
  static Map<String, dynamic> createPayload({
    required CaptureKind kind,
    required String room,
    required String storagePath,
    required String url,
    required String capturedBy,
    required String platform,
    required String appVersion,
  }) =>
      <String, dynamic>{
        'kind': kind.wire,
        'room': room,
        'storagePath': storagePath,
        'url': url,
        'capturedBy': capturedBy,
        'skipped': false,
        'takenAt': FieldValue.serverTimestamp(),
        'deviceMeta': <String, dynamic>{
          'platform': platform,
          'appVersion': appVersion,
        },
      };

  /// A skip is evidence too. It is recorded, and it counts against whoever
  /// skipped it if there is ever a claim. Never silently ignore one.
  static Map<String, dynamic> skipPayload({
    required CaptureKind kind,
    required String room,
    required String capturedBy,
    required String reason,
  }) =>
      <String, dynamic>{
        'kind': kind.wire,
        'room': room,
        'storagePath': '',
        'url': '',
        'capturedBy': capturedBy,
        'skipped': true,
        'skipReason': reason,
        'takenAt': FieldValue.serverTimestamp(),
      };
}
