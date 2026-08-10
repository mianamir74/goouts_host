// Host self-service lookups — the data behind "Check for Help".
//
// Ported in shape from goouts_app/lib/services/self_service_service.dart, but
// every query is different because a host's world is different. The consumer
// version reads /users/{uid}/transactions. A host has no transactions; a host
// has listings, bookings and a verification status.
//
// ── THERE IS NO AI HERE ──────────────────────────────────────────────────
//
// The consumer screen tells the user "our AI assistant will try to resolve
// your issue first". That is marketing copy for what is actually a set of
// plain Firestore reads that surface the record the user is probably asking
// about. Same here. Nothing is inferred, generated or predicted — every value
// shown to a host came out of their own documents.
//
// ── HONESTY RULES THAT MUST NOT BE BROKEN ────────────────────────────────
//
// Payments are NOT live. Claims are NOT built. Two of these topics therefore
// return an explicit "not available yet" state rather than a number. Do not
// replace those with estimates, projections or placeholder figures — the
// earnings screen already had invented money in it once (£14,840, a 2023
// payout history) and it had to be torn out. A host who is told a figure will
// believe it.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../short_stay/host/host_collection.dart';

class HostSelfServiceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Fetch whatever is relevant to [topicValue].
  ///
  /// Never throws. A failed lookup returns `{'error': ...}` and the screen
  /// falls back to "we could not check" — a support form that dies because a
  /// read failed is worse than one that just takes the ticket.
  Future<Map<String, dynamic>> fetchForTopic(String topicValue) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return <String, dynamic>{'signedOut': true};

    try {
      return switch (topicValue) {
        'booking_guest' => await _bookings(uid),
        'listing_issue' => await _listings(uid),
        'calendar_availability' => await _calendar(uid),
        'payout_earnings' => await _payouts(uid),
        'verification_account' => await _verification(uid),
        'damage_evidence' => await _evidence(uid),
        _ => <String, dynamic>{},
      };
    } catch (e) {
      return <String, dynamic>{'error': e.toString()};
    }
  }

  // ── Bookings ─────────────────────────────────────────────────────────────
  //
  // NOTE the .limit(20). firestore.rules requires request.query.limit <= 100
  // on stay_bookings list, so an unbounded query is denied outright rather
  // than truncated. Removing the limit breaks this silently.
  Future<Map<String, dynamic>> _bookings(String uid) async {
    final snap = await _db
        .collection('stay_bookings')
        .where('hostUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();

    final all = snap.docs.map((d) {
      final b = d.data();
      return <String, dynamic>{
        'id': d.id,
        'ref': (b['bookingId'] as String?) ?? d.id,
        'status': (b['status'] as String?) ?? 'pending',
        'checkIn': _day(b['checkIn']),
        'checkOut': _day(b['checkOut']),
        'nights': b['nights'],
        'guests': b['guests'],
      };
    }).toList();

    return <String, dynamic>{
      'bookings': all,
      'pending': all.where((b) => b['status'] == 'pending').length,
      'confirmed': all.where((b) => b['status'] == 'confirmed').length,
      'cancelled': all
          .where((b) =>
              b['status'] == 'cancelled' || b['status'] == 'declined')
          .length,
    };
  }

  // ── Listings ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _listings(String uid) async {
    final snap = await _db
        .collection('stay_listings')
        .where('hostUid', isEqualTo: uid)
        .limit(50)
        .get();

    final all = snap.docs.map((d) {
      final l = d.data();
      return <String, dynamic>{
        'id': d.id,
        'title': (l['title'] as String?)?.trim().isNotEmpty == true
            ? l['title'] as String
            : 'Untitled property',
        'status': (l['status'] as String?) ?? 'draft',
        'town': (l['town'] as String?) ?? '',
      };
    }).toList();

    return <String, dynamic>{
      'listings': all,
      'live': all.where((l) => l['status'] == 'live').length,
      'draft': all.where((l) => l['status'] == 'draft').length,
      'rejected': all.where((l) => l['status'] == 'rejected').length,
    };
  }

  // ── Calendar ─────────────────────────────────────────────────────────────
  //
  // Blocked dates live in a subcollection per listing, so counting them all
  // would be one read per listing. For a support screen that is not worth it —
  // what the host needs to know is which property to look at.
  Future<Map<String, dynamic>> _calendar(String uid) async {
    final data = await _listings(uid);
    return <String, dynamic>{...data, 'calendarView': true};
  }

  // ── Payouts ──────────────────────────────────────────────────────────────
  //
  // Deliberately returns NO figures. Payments are not integrated, so there is
  // no balance, no pending payout and no history to show. Saying so plainly is
  // the whole point of this branch.
  Future<Map<String, dynamic>> _payouts(String uid) async {
    final data = await _bookings(uid);
    return <String, dynamic>{
      'paymentsLive': false,
      'confirmed': data['confirmed'] ?? 0,
      'payoutPolicy':
          'Once payments go live: released 24 hours after check-in, or 30 days '
              'after check-in for your first few stays as a new host.',
    };
  }

  // ── Verification ─────────────────────────────────────────────────────────
  //
  // Reads the same three fields, in the same order of authority, as the
  // dashboard hero, the profile banner, and requireVerifiedHost() on the
  // server. If this order ever drifts, a host sees one status in one place and
  // a different one two taps away — which is exactly the bug that was fixed in
  // the admin panel in July.
  Future<Map<String, dynamic>> _verification(String uid) async {
    final doc = await _db.collection(kStayHostsCollection).doc(uid).get();
    final d = doc.data() ?? <String, dynamic>{};

    // toString(), not `as String`. Admin tooling has written this field
    // as a bool before now, and a failed cast here would blank the whole
    // self-service panel rather than just this one line.
    final raw = (d['kycStatus'] ??
            d['businessProfileVerificationStatus'] ??
            d['status'] ??
            'pending')
        .toString()
        .toLowerCase()
        .trim();

    final approved = raw == 'approved' || raw == 'verified';
    final rejected = raw == 'rejected' || raw == 'declined';

    return <String, dynamic>{
      'kycStatus': raw,
      'kycApproved': approved,
      'kycRejected': rejected,
      'kycLabel': approved
          ? 'Verified'
          : rejected
              ? 'Not approved'
              : 'In progress',
      'businessName': (d['legalBusinessName'] ?? d['businessName'] ?? '')
          .toString()
          .trim(),
      'accountActive': d['isActive'] != false,
    };
  }

  // ── Evidence ─────────────────────────────────────────────────────────────
  //
  // Claims are not built yet (they are blocked on payments — there is no
  // deposit to claim against). Evidence capture IS built, so the honest answer
  // is: your photos are being stored and they will support a claim when claims
  // exist. Not: "submit a claim here".
  Future<Map<String, dynamic>> _evidence(String uid) async {
    final data = await _bookings(uid);
    return <String, dynamic>{
      'claimsLive': false,
      'bookings': data['bookings'] ?? const <Map<String, dynamic>>[],
      'confirmed': data['confirmed'] ?? 0,
    };
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static String _day(dynamic v) {
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
    if (v is String && v.isNotEmpty) return v;
    return '—';
  }
}
