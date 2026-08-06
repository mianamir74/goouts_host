import 'package:cloud_functions/cloud_functions.dart';

import '../models/money.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Host actions on a booking. Every one is a Cloud Function.
//
// There is no Firestore write in this file and there must never be one.
// stay_bookings is `allow create, update, delete: if false` for every client,
// including the host — accepting and declining change money and calendars and
// are decided server side.
//
// europe-west1. Four files in this project pointed at us-central1 and each
// failed only at runtime, on a device, with NOT_FOUND. It is a plain string,
// so nothing catches it.
// ─────────────────────────────────────────────────────────────────────────────

/// One pending request, as the host's requests screen needs it.
class HostBookingRequest {
  final String bookingId;
  final String listingId;
  final String guestUid;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int nights;
  final int adults;
  final int children;
  final int infants;

  /// What the HOST receives, not what the guest pays. Commission is already
  /// deducted. Showing a host the guest's total as though it were their payout
  /// is the single easiest way to make this screen lie.
  final Pence hostPayout;
  final Pence guestTotal;

  /// Always false today. There is no payment integration, so a screen that
  /// says "paid" is misreading this.
  final bool paymentTaken;

  const HostBookingRequest({
    required this.bookingId,
    required this.listingId,
    required this.guestUid,
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.adults,
    required this.children,
    required this.infants,
    required this.hostPayout,
    required this.guestTotal,
    required this.paymentTaken,
  });

  static Map<String, dynamic> _sub(dynamic v) =>
      (v as Map?)?.cast<String, dynamic>() ?? const {};

  factory HostBookingRequest.fromWire(Map<String, dynamic> m) {
    final g = _sub(m['guests']);
    final p = _sub(m['pricing']);
    return HostBookingRequest(
      bookingId: (m['bookingId'] ?? '') as String,
      listingId: (m['listingId'] ?? '') as String,
      guestUid: (m['guestUid'] ?? '') as String,
      checkIn: DateTime.tryParse((m['checkIn'] ?? '') as String),
      checkOut: DateTime.tryParse((m['checkOut'] ?? '') as String),
      nights: (m['nights'] as num?)?.toInt() ?? 0,
      adults: (g['adults'] as num?)?.toInt() ?? 1,
      children: (g['children'] as num?)?.toInt() ?? 0,
      infants: (g['infants'] as num?)?.toInt() ?? 0,
      hostPayout: Pence.fromFirestore(p['hostPayout']),
      guestTotal: Pence.fromFirestore(p['total']),
      paymentTaken: m['paymentTaken'] == true,
    );
  }

  /// Infants do not count towards occupancy — the same rule the booking model
  /// and the server both apply. If these three ever disagree, a host is shown
  /// a different party size than the one that was validated.
  int get countedGuests => adults + children;
}

class StayHostService {
  StayHostService._();
  static final instance = StayHostService._();

  final _fn = FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Pending requests awaiting this host's answer.
  Future<List<HostBookingRequest>> pendingRequests() async {
    final res = await _fn
        .httpsCallable('listHostBookingRequests')
        .call<Map<String, dynamic>>({});
    return ((res.data['requests'] as List?) ?? const [])
        .map((e) => HostBookingRequest.fromWire(
            (e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Accept. The nights were already held when the guest requested, so this
  /// changes status only — nothing on the calendar moves.
  ///
  /// Returns true if this call did the accepting, false if it was already
  /// accepted. A double tap is a success, not an error.
  ///
  /// NO PAYMENT IS TAKEN. Accepting charges nobody, because there is no
  /// payment integration. A confirmation screen must not say "payment
  /// received".
  Future<bool> accept(String bookingId) async {
    final res = await _fn
        .httpsCallable('acceptStayBooking')
        .call<Map<String, dynamic>>({'bookingId': bookingId});
    return res.data['alreadyAccepted'] != true;
  }

  /// Decline, and free the nights the request was holding.
  ///
  /// `reason` is stored on the booking but is deliberately NOT shown to the
  /// guest — a host's private note about why they said no is not something to
  /// push to somebody's phone.
  ///
  /// Returns how many nights were released, so the screen can confirm the
  /// calendar actually reopened rather than assuming it did.
  Future<int> decline(String bookingId, {String reason = ''}) async {
    final res = await _fn
        .httpsCallable('declineStayBooking')
        .call<Map<String, dynamic>>({
      'bookingId': bookingId,
      if (reason.isNotEmpty) 'reason': reason,
    });
    return (res.data['nightsFreed'] as num?)?.toInt() ?? 0;
  }
}
