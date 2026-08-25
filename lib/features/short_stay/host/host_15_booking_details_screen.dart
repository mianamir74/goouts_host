// One booking, in full.
//
// ── WIRED 8 August 2026. WHAT IT WAS ───────────────────────────────────────
//
// A Stitch export with an invented guest, invented dates, an invented total
// and four empty handlers.
//
// ── TAKES A BOOKING ID ─────────────────────────────────────────────────────
//
// `arguments` is the booking id. firestore.rules allows a `get` on
// stay_bookings when the caller is the guest, the host, or an admin — so the
// host reading their own booking is permitted directly, no callable needed.
//
// ── WHAT IT SHOWS AS "MONEY" IS THE HOST PAYOUT, NEVER THE GUEST TOTAL ─────
//
// pricing.hostPayout, not pricing.total. The two differ by GoOuts commission
// and showing a host the guest's total as though it were theirs is the single
// easiest way to make this screen lie — they would plan around a number that
// never arrives.
//
// paymentTaken is stated as FALSE and said out loud. No payment provider is
// integrated, so nothing has been charged and nothing has been paid. A screen
// that implies otherwise is the driver Instant Pay mistake again, where a
// button told drivers their wages had reached their bank.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import '../models/money.dart';
import 'host_bottom_nav.dart';
import 'host_routes.dart';

class HostBookingDetailsScreen extends StatelessWidget {
  const HostBookingDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final arg = ModalRoute.of(context)?.settings.arguments;
    final id = arg is String ? arg : '';

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
          'Booking',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: id.isEmpty
          ? _notice('No booking was selected. Go back and choose one.')
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('stay_bookings')
                  .doc(id)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _notice('Could not load this booking.\n'
                      '${snap.error}');
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.data!.exists) {
                  return _notice('This booking no longer exists.');
                }
                return _body(id, snap.data!.data()!);
              },
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.bookings),
    );
  }

  Widget _body(String id, Map<String, dynamic> b) {
    final pricing = (b['pricing'] as Map?) ?? const <String, dynamic>{};
    final guests = (b['guests'] as Map?) ?? const <String, dynamic>{};
    final cancel = (b['cancellation'] as Map?) ?? const <String, dynamic>{};
    final status = (b['status'] ?? 'pending').toString();

    final adults = (guests['adults'] as num?)?.toInt() ?? 1;
    final children = (guests['children'] as num?)?.toInt() ?? 0;
    final infants = (guests['infants'] as num?)?.toInt() ?? 0;

    final (String label, Color colour, String meaning) = switch (status) {
      'confirmed' => (
          'CONFIRMED',
          GoOutsColors.success,
          'You accepted this. The guest has been told.'
        ),
      'declined' => (
          'DECLINED',
          GoOutsColors.error,
          'You declined this. The nights were released back to your calendar.'
        ),
      'cancelled' => (
          'CANCELLED',
          GoOutsColors.error,
          'Cancelled. The nights are back on your calendar.'
        ),
      'expired' => (
          'EXPIRED',
          GoOutsColors.onSurfaceVariant,
          'This request was not answered in time and has lapsed.'
        ),
      _ => (
          'AWAITING YOU',
          GoOutsColors.warning,
          'The nights are held while you decide. Answer from Booking '
              'requests.'
        ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colour.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w800, color: colour),
              ),
              const SizedBox(height: 6),
              Text(
                meaning,
                style: GoogleFonts.inter(
                    fontSize: 13, color: GoOutsColors.body, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _section('Stay', <Widget>[
          _row('Check in', _day(b['checkIn'])),
          _row('Check out', _day(b['checkOut'])),
          _row('Nights', '${b['nights'] ?? 0}'),
          _row(
            'Guests',
            infants > 0
                ? '${adults + children} plus $infants '
                    '${infants == 1 ? "infant" : "infants"}'
                : '${adults + children}',
          ),
        ]),
        // ── MONEY ────────────────────────────────────────────────────────
        //
        // hostPayout first and largest. The guest total is shown underneath
        // and labelled as the guest's, so the two can never be confused.
        _section('Money', <Widget>[
          Text(
            Pence.fromFirestore(pricing['hostPayout']).formatted,
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: GoOutsColors.navy,
            ),
          ),
          Text(
            'What you receive, after GoOuts commission',
            style: GoogleFonts.inter(
                fontSize: 12.5, color: GoOutsColors.body),
          ),
          const SizedBox(height: 14),
          _row('Guest pays in total',
              Pence.fromFirestore(pricing['total']).formatted),
          if (pricing['cleaningFee'] != null)
            _row('Of which cleaning fee',
                Pence.fromFirestore(pricing['cleaningFee']).formatted),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GoOutsColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_outline_rounded,
                    size: 17, color: GoOutsColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No payment has been taken and none has been paid out. '
                    'GoOuts is not yet connected to a payment provider, so '
                    'these figures are what the booking is worth, not money '
                    'that has moved.',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: GoOutsColors.body,
                        height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ]),
        // The refund terms were SNAPSHOTTED onto the booking when it was made,
        // so they are what applies even if the host later changes their policy.
        // Reading them from the listing instead would show terms the guest
        // never agreed to.
        if (cancel.isNotEmpty)
          _section('Cancellation terms for this booking', <Widget>[
            _row('Policy', (cancel['policy'] ?? '').toString()),
            _row('Full refund until', _day(cancel['fullRefundUntil'])),
            if (cancel['partialRefundPct'] != null)
              _row('Part refund after that',
                  '${cancel['partialRefundPct']}%'),
            const SizedBox(height: 6),
            Text(
              'Recorded when the guest booked. Changing your policy later does '
              'not change this booking.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: GoOutsColors.onSurfaceVariant),
            ),
          ]),
        // ── THE ONLY ROUTE TO PRE-ARRIVAL CAPTURE ─────────────────────────
        //
        // Screen 16 was routed but reachable from nothing, so a host could
        // never actually photograph the rooms. Offered only on a CONFIRMED
        // booking: there is no point photographing for a request that may be
        // declined, and doing it for a pending one implies it is going ahead.
        if (status == 'confirmed')
          _section('Before they arrive', <Widget>[
            Text(
              'Photograph each room before the guest checks in. Without a '
              'record from before the stay, a damage claim afterwards has '
              'nothing to rest on.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: GoOutsColors.body, height: 1.45),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) => FilledButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  HostRoutes.preArrival,
                  arguments: id,
                ),
                icon: const Icon(Icons.photo_camera_rounded, size: 18),
                label: const Text('Photograph the rooms'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
              ),
            ),
          ]),
        // ── MESSAGE THE GUEST ─────────────────────────────────────────────
        //
        // Offered on confirmed AND pending bookings, unlike the photograph
        // step above. A host deciding whether to accept a request very often
        // needs to ask something first, and the request screen gives them
        // Accept or Decline and nothing in between.
        if (status == 'confirmed' || status == 'pending')
          _section('Messages', <Widget>[
            Text(
              status == 'pending'
                  ? 'Ask your guest anything you need to know before you '
                    'accept. They see this in their GoOuts app.'
                  : 'Arrange arrival times and key collection here. Messages '
                    'cannot be edited or deleted afterwards, by either of you.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: GoOutsColors.body, height: 1.45),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) => OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  HostRoutes.guestThread,
                  arguments: id,
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('Message your guest'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  foregroundColor: GoOutsColors.primary,
                  side: const BorderSide(color: GoOutsColors.primary),
                ),
              ),
            ),
          ]),

        // ── ⚠ THE ONLY WAY INTO THE CLAIMS FLOW. ADDED 25 August 2026. ───────
        //
        // Until now there was none. The three claim screens existed, had
        // routes, and NOTHING NAVIGATED TO THEM — while the consumer app told
        // guests in five places that a damage claim might be made against them
        // and their arrival photographs were their evidence.
        //
        // ⚠ GATED ON THE CHECK-OUT DATE, NOT ON A 'completed' STATUS —
        //   BECAUSE THERE IS NO SUCH STATUS. Found 25 August 2026.
        //
        // I wrote `status == 'completed'` first. It would have been a button
        // that NEVER APPEARED, silently, for ever: grep every status a booking
        // is ever assigned and the list is pending, confirmed, declined,
        // cancelled. NOTHING IN THE BACKEND EVER MARKS A STAY AS FINISHED.
        // ("Completed" exists in stay_booking.js but on a transaction record,
        // not a booking — the same word doing two jobs.)
        //
        // So the honest test is the one the server uses: has the check-out
        // date passed. That is derivable from data which definitely exists,
        // and it matches submitStayClaim's own `now < checkOut` refusal
        // exactly — one fact, checked the same way on both sides.
        //
        // ⚠ THE MISSING COMPLETION STEP IS A REAL GAP BEYOND CLAIMS. Payouts,
        // reviews and "past stays" all want to know a stay has ended, and
        // nothing tells them. Recorded separately.
        if (_stayHasEnded(b['checkOut']))
          _section('Damage', <Widget>[
            Text(
              'If your guest damaged the property, report it within 72 hours '
              'of check-out. Their arrival photos are attached automatically '
              'and your guest gets to respond before anything is decided.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: GoOutsColors.body, height: 1.45),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) => OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  HostRoutes.makeClaim,
                  arguments: id,
                ),
                icon: const Icon(Icons.report_gmailerrorred_outlined, size: 18),
                label: const Text('Report damage'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  foregroundColor: GoOutsColors.error,
                  side: const BorderSide(color: GoOutsColors.error),
                ),
              ),
            ),
          ]),
        _section('Reference', <Widget>[
          _row('Booking', (b['bookingId'] ?? '').toString()),
          _row('Property', (b['listingId'] ?? '').toString()),
          _row('Booked', _day(b['createdAt'])),
        ]),
      ],
    );
  }

  static const _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Has the stay finished?
  ///
  /// ⚠ THE ONLY HONEST TEST AVAILABLE. There is no 'completed' booking status
  /// anywhere in this system — see the note at the claims section above. This
  /// mirrors submitStayClaim's own `now < checkOut` refusal, so the button and
  /// the server agree about what "finished" means.
  ///
  /// Returns false when checkOut is missing or unreadable, which hides the
  /// button rather than offering a claim on a booking whose dates we cannot
  /// establish.
  static bool _stayHasEnded(Object? checkOut) {
    if (checkOut is Timestamp) {
      return DateTime.now().isAfter(checkOut.toDate());
    }
    if (checkOut is String && checkOut.isNotEmpty) {
      final DateTime? d = DateTime.tryParse(checkOut);
      return d != null && DateTime.now().isAfter(d);
    }
    return false;
  }

  static String _day(Object? v) {
    if (v is Timestamp) {
      final d = v.toDate().toLocal();
      return '${d.day} ${_months[d.month - 1]} ${d.year}';
    }
    if (v is String && v.isNotEmpty) return v;
    return '—';
  }

  Widget _section(String title, List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Text(k,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: GoOutsColors.body)),
            ),
            Expanded(
              flex: 4,
              child: Text(
                v.isEmpty ? '—' : v,
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GoOutsColors.navy,
                ),
              ),
            ),
          ],
        ),
      );

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
