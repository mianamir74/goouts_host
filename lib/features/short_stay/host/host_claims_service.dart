// ─────────────────────────────────────────────────────────────────────────────
//  Damage claims — the host's side.
//
//  Written 25 August 2026, with functions/stay_claims.js.
//
//  ── ⚠ EVERY WRITE IS A CLOUD FUNCTION. THERE IS NO CLIENT PATH. ─────────────
//
//  firestore.rules has /stay_claims on `allow create, update, delete: if false`.
//  That is not an oversight to work around — a claim opens a countdown against
//  another named person and can take £150 off them. Pricing, deadlines and
//  adjudication are decided server side or they are decided by whoever edits
//  the request.
//
//  So this file READS claims and CALLS functions. If you find yourself adding a
//  .set() or an .update() here, the answer is a new callable, not a rule change.
//
//  ── WHAT THE HOST CAN AND CANNOT DO ─────────────────────────────────────────
//
//    open      submitStayClaim   — once per booking, within the window that was
//                                  snapshotted onto the booking, capped at the
//                                  deposit
//    watch     a stream of their own claims
//    nothing   else. The host cannot edit a claim after opening it, cannot
//              withdraw it once the guest has seen it, and cannot decide it.
//
//  ⚠ THE PHOTOGRAPHS GO TO stay_claims/{hostUid}/ AND NOWHERE ELSE. storage.rules
//  allows that folder and only that folder, and submitStayClaim independently
//  refuses any URL not under it — because a URL is a string and a string can be
//  typed. Two checks on purpose: one stops the upload, one stops the claim.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

const String kStayClaimsCollection = 'stay_claims';

/// The states a claim can be in. Mirrors OPEN_STATES + "decided" in
/// stay_claims.js — ⚠ if that list changes, this changes. A state the app does
/// not recognise renders as nothing at all, which is how a host ends up
/// believing a claim vanished.
enum ClaimStatus { awaitingGuest, accepted, disputed, decided, unknown }

ClaimStatus claimStatusFrom(String? wire) {
  switch ((wire ?? '').trim()) {
    case 'awaiting_guest':
      return ClaimStatus.awaitingGuest;
    case 'accepted':
      return ClaimStatus.accepted;
    case 'disputed':
      return ClaimStatus.disputed;
    case 'decided':
      return ClaimStatus.decided;
    default:
      return ClaimStatus.unknown;
  }
}

class StayClaim {
  const StayClaim({
    required this.id,
    required this.bookingId,
    required this.status,
    required this.amountPence,
    required this.awardedPence,
    required this.description,
    required this.openedAt,
    required this.respondBy,
    required this.guestResponse,
    required this.guestResponseNote,
    required this.decision,
    required this.decisionReason,
    required this.evidenceCount,
    required this.hostPhotoUrls,
    required this.settlementStatus,
  });

  final String id;
  final String bookingId;
  final ClaimStatus status;
  final int amountPence;
  final int awardedPence;
  final String description;
  final DateTime? openedAt;
  final DateTime? respondBy;
  final String? guestResponse;
  final String? guestResponseNote;
  final String? decision;
  final String? decisionReason;
  final int evidenceCount;
  final List<String> hostPhotoUrls;
  final String settlementStatus;

  factory StayClaim.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final Map<String, dynamic> m = d.data() ?? const <String, dynamic>{};
    return StayClaim(
      id: d.id,
      bookingId: (m['bookingId'] ?? '') as String,
      status: claimStatusFrom(m['status'] as String?),
      amountPence: (m['amountPence'] as num?)?.toInt() ?? 0,
      awardedPence: (m['awardedPence'] as num?)?.toInt() ?? 0,
      description: (m['description'] ?? '') as String,
      openedAt: (m['openedAt'] as Timestamp?)?.toDate(),
      respondBy: (m['respondBy'] as Timestamp?)?.toDate(),
      guestResponse: m['guestResponse'] as String?,
      guestResponseNote: m['guestResponseNote'] as String?,
      decision: m['decision'] as String?,
      decisionReason: m['decisionReason'] as String?,
      evidenceCount: (m['evidenceCount'] as num?)?.toInt() ?? 0,
      hostPhotoUrls:
          ((m['hostPhotoUrls'] as List<dynamic>?) ?? const <dynamic>[])
              .map((dynamic e) => e.toString())
              .toList(growable: false),
      settlementStatus: (m['settlementStatus'] ?? '') as String,
    );
  }

  double get amount => amountPence / 100.0;
  double get awarded => awardedPence / 100.0;

  /// ⚠ NOT "is the money coming". Nothing is held anywhere — every booking
  /// carries depositPreAuth.status "none" because no payment provider is
  /// connected. This says a decision is waiting on one, and any screen phrasing
  /// it as an imminent payment is lying to a host who will then chase it.
  bool get awaitingProvider =>
      settlementStatus == 'awaiting_provider' && awardedPence > 0;
}

class HostClaimsService {
  HostClaimsService._();
  static final HostClaimsService instance = HostClaimsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _fns =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Every claim this host has opened, newest first.
  ///
  /// ⚠ FILTERED ON hostUid BECAUSE THE RULE READS resource.data.hostUid.
  /// A LIST query whose rule references `resource` is REJECTED OUTRIGHT unless
  /// the query itself filters on that field — the same trap that would have
  /// stopped guest messaging loading before it was caught on 21 August. Dropping
  /// this where() does not return everyone's claims, it returns an error.
  Stream<List<StayClaim>> watchMyClaims({int limit = 50}) {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return Stream<List<StayClaim>>.value(const <StayClaim>[]);
    return _db
        .collection(kStayClaimsCollection)
        .where('hostUid', isEqualTo: uid)
        .orderBy('openedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> q) =>
            q.docs.map(StayClaim.fromDoc).toList(growable: false));
  }

  Stream<StayClaim?> watchClaim(String claimId) => _db
      .collection(kStayClaimsCollection)
      .doc(claimId)
      .snapshots()
      .map((DocumentSnapshot<Map<String, dynamic>> d) =>
          d.exists ? StayClaim.fromDoc(d) : null);

  /// Is there already an open claim on this booking?
  ///
  /// Asked before showing the button, so the host is told up front rather than
  /// filling in a form and being refused at the end. The function checks this
  /// too — this one is courtesy, that one is the rule.
  Future<bool> hasOpenClaim(String bookingId) async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final QuerySnapshot<Map<String, dynamic>> q = await _db
          .collection(kStayClaimsCollection)
          .where('hostUid', isEqualTo: uid)
          .where('bookingId', isEqualTo: bookingId)
          .limit(5)
          .get();
      return q.docs.any((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
          claimStatusFrom(d.data()['status'] as String?) !=
          ClaimStatus.decided);
    } catch (e) {
      // Fail OPEN on a read error — showing the button and being refused by
      // the function is recoverable; hiding it because a query hiccuped leaves
      // a host who cannot claim and cannot see why.
      debugPrint('hasOpenClaim: $e');
      return false;
    }
  }

  /// Uploads one damage photograph and returns its download URL.
  ///
  /// ⚠ THE PATH IS NOT NEGOTIABLE. stay_claims/{uid}/ is the only folder
  /// storage.rules permits and the only prefix submitStayClaim will accept.
  Future<String?> uploadClaimPhoto(File file) async {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    try {
      final String name =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.hashCode}.jpg';
      final Reference ref =
          FirebaseStorage.instance.ref('stay_claims/$uid/$name');
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('uploadClaimPhoto: $e');
      return null;
    }
  }

  /// Opens the claim. Throws [ClaimError] with the server's own wording.
  Future<String> submit({
    required String bookingId,
    required int amountPence,
    required String description,
    required List<String> photoUrls,
  }) async {
    try {
      final HttpsCallableResult<dynamic> r =
          await _fns.httpsCallable('submitStayClaim').call(<String, dynamic>{
        'bookingId': bookingId,
        'amountPence': amountPence,
        'description': description,
        'photoUrls': photoUrls,
      });
      final Map<dynamic, dynamic> data =
          (r.data as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
      return (data['claimId'] ?? '').toString();
    } on FirebaseFunctionsException catch (e) {
      // ⚠ THE SERVER'S MESSAGE, NOT A GENERIC ONE. Every refusal in
      // stay_claims.js is written to be read by the host — "the 72 hour window
      // has closed", "a claim cannot exceed the £150 deposit". Replacing those
      // with "Something went wrong" throws away the only useful part.
      throw ClaimError(e.message ?? 'That claim could not be submitted.');
    } catch (e) {
      throw ClaimError('That claim could not be submitted. $e');
    }
  }
}

class ClaimError implements Exception {
  ClaimError(this.message);
  final String message;
  @override
  String toString() => message;
}
