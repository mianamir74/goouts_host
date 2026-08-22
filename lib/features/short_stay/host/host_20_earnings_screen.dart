// ─────────────────────────────────────────────────────────────────────────────
//  Host earnings — real bookings, real payouts, nothing invented.
//
//  Built 21 August 2026, replacing the guard placed on 9 August.
//
//  ── WHAT THE GUARD SAID, AND WHY IT IS NOW GONE ─────────────────────────────
//
//  This screen shipped from Stitch showing £14,840 total earnings, a
//  "Commission (15%)" line and a payout history dated 2023 with "Bank
//  Transfer" as the method. Every figure was fiction, and it is a permanent
//  bottom-nav tab, so a real host saw it on their first run.
//
//  The guard set three conditions for building it. All three are met here:
//
//    1. READ FROM /stay_bookings FILTERED BY hostUid.   Done below.
//    2. SHOW pricing.hostPayout, NEVER pricing.total.   Done — see _Row.
//    3. TAKE THE PAYOUT RULES FROM stay_config.         Done — via the
//       getHostPayoutTerms callable, added the same day as this screen.
//
//  ── WHY A CALLABLE AND NOT THREE CONSTANTS ──────────────────────────────────
//
//  The commission is 12.5% in stay_config.js. It was 15% here. A host reading
//  one number on this screen and a different one on their booking has been
//  given two answers about what GoOuts takes from them, and the whole class of
//  bug this codebase keeps finding is one fact stored under several names.
//
//  platform_config is admin-read in the rules, correctly, so the host app
//  cannot read it directly. getHostPayoutTerms returns only what a host is
//  party to: the commission they are charged, and when they are paid. If that
//  call fails, this screen shows NO percentage at all rather than a guess.
//
//  ── WHAT IT STILL REFUSES TO DO ─────────────────────────────────────────────
//
//  No payout history. No "paid on 12 March by bank transfer". No payment
//  provider is integrated, paymentMode is "demo", and nothing has ever been
//  paid to anybody. While payoutsRunning is false a banner says so in the
//  first thing the host reads. The figures below it are real money owed by
//  real bookings — they are simply not money that has moved yet.
//
//  ⚠ THE 100-BOOKING LIMIT IS DELIBERATE AND IS DISCLOSED. The Firestore rule
//  on stay_bookings requires request.query.limit <= 100. A host past that many
//  bookings would otherwise see a lifetime total that silently stops counting,
//  which is worse than no total. _truncated drives a line that says so.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import '../models/money.dart';
import 'host_bottom_nav.dart';
import 'host_routes.dart';

class HostEarningsScreen extends StatefulWidget {
  const HostEarningsScreen({super.key});

  @override
  State<HostEarningsScreen> createState() => _HostEarningsScreenState();
}

class _HostEarningsScreenState extends State<HostEarningsScreen> {
  /// Exactly the rules cap. Raising this breaks the read for every host at
  /// once, with a permission-denied that looks nothing like a limit problem.
  static const int _queryLimit = 100;

  _Terms? _terms;
  bool _termsFailed = false;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    try {
      // Functions are deployed to europe-west1. Calling without instanceFor
      // silently hits us-central1 and fails as NOT_FOUND — the same trap
      // host_create_profile_screen documents.
      final HttpsCallableResult<dynamic> r =
          await FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('getHostPayoutTerms')
              .call<dynamic>();
      final Map<String, dynamic> m =
          Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>);
      if (!mounted) return;
      setState(() => _terms = _Terms.fromMap(m));
    } catch (_) {
      // No fallback percentage. A wrong commission figure is the exact fault
      // this screen was guarded for.
      if (!mounted) return;
      setState(() => _termsFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

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
          'Earnings',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: uid == null
          ? _notice(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to see your earnings.',
              detail: 'Your bookings are tied to your host account.',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('stay_bookings')
                  .where('hostUid', isEqualTo: uid)
                  .orderBy('createdAt', descending: true)
                  .limit(_queryLimit)
                  .snapshots(),
              builder: (context, snap) {
                // Failed is not empty. A silent catch here would render "no
                // earnings yet" to a host who has been booked all summer.
                if (snap.hasError) {
                  return _notice(
                    icon: Icons.cloud_off_rounded,
                    title: 'We could not load your earnings.',
                    detail: '${snap.error}',
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: GoOutsColors.primary, strokeWidth: 2),
                  );
                }
                return _body(_Totals.from(snap.data!.docs));
              },
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.earnings),
    );
  }

  // ── BODY ──────────────────────────────────────────────────────────────────

  Widget _body(_Totals t) {
    final bool live = _terms?.payoutsRunning ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!live) _notLiveBanner(),
          if (!live) const SizedBox(height: 18),

          _headline(t),
          const SizedBox(height: 16),

          Row(
            children: <Widget>[
              Expanded(
                child: _stat(
                  label: 'This month',
                  value: t.thisMonth.formatted,
                  hint: 'stays that ended this month',
                  colour: GoOutsColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _stat(
                  label: 'Still to come',
                  value: t.upcoming.formatted,
                  hint: '${t.upcomingCount} confirmed booking'
                      '${t.upcomingCount == 1 ? '' : 's'}',
                  colour: GoOutsColors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (t.pendingCount > 0) _pendingCard(t.pendingCount),
          if (t.pendingCount > 0) const SizedBox(height: 12),

          _termsCard(),
          const SizedBox(height: 12),

          if (t.finished.isNotEmpty) ...<Widget>[
            _sectionTitle('Completed stays'),
            for (final _Row r in t.finished.take(20)) _row(r, past: true),
            const SizedBox(height: 8),
          ],

          if (t.ahead.isNotEmpty) ...<Widget>[
            _sectionTitle('Coming up'),
            for (final _Row r in t.ahead.take(20)) _row(r, past: false),
            const SizedBox(height: 8),
          ],

          if (t.finished.isEmpty && t.ahead.isEmpty) _emptyCard(),

          if (t.truncated) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'These figures cover your most recent $_queryLimit bookings. '
              'You have more than that, so your lifetime total is higher than '
              'the number above.',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                height: 1.5,
                color: GoOutsColors.onSurfaceVariant,
              ),
            ),
          ],

          const SizedBox(height: 20),
          // ⚠ DELIBERATELY NOT HostRoutes.payoutDetails. host_09 is still
          // unwired Stitch placeholder — its own header says "every figure on
          // screen is placeholder copy... do not read a number here as real
          // data". Sending a host from this screen into fake bank details
          // undoes the entire point of it. Relink when host_09 is built.
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pushNamed(HostRoutes.requests),
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text('See all your bookings'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              foregroundColor: GoOutsColors.primary,
              side: const BorderSide(color: GoOutsColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  /// ⚠ THE MOST IMPORTANT WIDGET ON THIS SCREEN. It is first, it is not
  /// dismissible, and it says plainly that no money has moved. Removing it
  /// while paymentMode is "demo" puts the screen back where it started.
  Widget _notLiveBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GoOutsColors.warningBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GoOutsColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_outline_rounded,
                size: 18, color: GoOutsColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'No money has been paid out yet',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: GoOutsColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'GoOuts is not connected to a payment provider yet, so '
                    'guests have not been charged and nothing has reached your '
                    'bank. The amounts below are what these bookings are '
                    'worth to you, not what you have received.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.5,
                      color: GoOutsColors.body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _headline(_Totals t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Earned from completed stays',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: GoOutsColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.earned.formatted,
              style: GoogleFonts.inter(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: GoOutsColors.navy,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.finishedCount == 0
                  ? 'No stays have finished yet.'
                  : 'Across ${t.finishedCount} finished stay'
                      '${t.finishedCount == 1 ? '' : 's'}, after GoOuts '
                      'commission.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.45,
                color: GoOutsColors.body,
              ),
            ),
          ],
        ),
      );

  Widget _stat({
    required String label,
    required String value,
    required String hint,
    required Color colour,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: GoOutsColors.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: colour)),
            const SizedBox(height: 3),
            Text(hint,
                style: GoogleFonts.inter(
                    fontSize: 11, color: GoOutsColors.onSurfaceVariant)),
          ],
        ),
      );

  Widget _pendingCard(int n) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).pushNamed(HostRoutes.requests),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: GoOutsColors.tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.mark_email_unread_outlined,
                  size: 18, color: GoOutsColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$n booking request${n == 1 ? '' : 's'} waiting on you. '
                  'Nothing is earned until you accept.',
                  style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.45,
                      color: GoOutsColors.navy,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: GoOutsColors.primary),
            ],
          ),
        ),
      );

  /// Commission and payout timing, straight from stay_config via the callable.
  /// If the callable failed, this says so rather than inventing the numbers.
  Widget _termsCard() {
    final _Terms? t = _terms;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GoOutsColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GoOutsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('How you get paid',
              style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: GoOutsColors.navy)),
          const SizedBox(height: 10),
          if (t == null && !_termsFailed)
            Text('Loading your terms…',
                style: GoogleFonts.inter(
                    fontSize: 13, color: GoOutsColors.onSurfaceVariant))
          else if (t == null)
            Text(
              'We could not load your commission and payout terms just now. '
              'They are shown on every booking, and on your payout details '
              'page. Pull down or reopen this screen to try again.',
              style: GoogleFonts.inter(
                  fontSize: 13, height: 1.5, color: GoOutsColors.body),
            )
          else ...<Widget>[
            _point('GoOuts keeps ${_pct(t.commissionPct)} of the '
                'accommodation and cleaning fee. Every amount on this screen '
                'is already after that.'),
            _point('The guest service fee is charged to the guest and is not '
                'part of your payout.'),
            _point('A payout is released '
                '${t.payoutReleaseHoursAfterCheckIn} hours after the guest '
                'checks in, so a guest who arrives to a problem can raise it '
                'first.'),
            _point('New hosts wait ${t.newHostPayoutHoldDays} days from their '
                'first confirmed booking. After '
                '${t.newHostCompletedStaysThreshold} completed stay'
                '${t.newHostCompletedStaysThreshold == 1 ? '' : 's'} the '
                'normal timing applies.'),
          ],
        ],
      ),
    );
  }

  Widget _row(_Row r, {required bool past}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: InkWell(
          onTap: () => Navigator.of(context)
              .pushNamed(HostRoutes.booking, arguments: r.id),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: past ? GoOutsColors.successBg : GoOutsColors.tint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  past
                      ? Icons.check_rounded
                      : Icons.event_available_outlined,
                  size: 18,
                  color: past ? GoOutsColors.success : GoOutsColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(r.dates,
                        style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: GoOutsColors.navy)),
                    const SizedBox(height: 2),
                    Text(
                      '${r.nights} night${r.nights == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: GoOutsColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              // ⚠ hostPayout. NEVER pricing.total — that includes the guest
              // service fee and the commission, neither of which is the
              // host's. See host_15_booking_details_screen.
              Text(
                r.payout.formatted,
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: GoOutsColors.navy),
              ),
            ],
          ),
        ),
      );

  Widget _emptyCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: Column(
          children: <Widget>[
            const Icon(Icons.payments_outlined,
                size: 30, color: GoOutsColors.draft),
            const SizedBox(height: 10),
            Text('No earnings yet',
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: GoOutsColors.navy)),
            const SizedBox(height: 6),
            Text(
              'Once you accept a booking it appears here, with what you will '
              'receive after commission.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, height: 1.5, color: GoOutsColors.body),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(
          s.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: GoOutsColors.onSurfaceVariant,
          ),
        ),
      );

  static Widget _point(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(Icons.check_rounded,
                  size: 15, color: GoOutsColors.success),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                    fontSize: 13, color: GoOutsColors.body, height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _notice({
    required IconData icon,
    required String title,
    required String detail,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 34, color: GoOutsColors.draft),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: GoOutsColors.navy)),
              const SizedBox(height: 8),
              Text(detail,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.45,
                      color: GoOutsColors.onSurfaceVariant)),
            ],
          ),
        ),
      );

  /// 12.5 -> "12.5%", 12.0 -> "12%". A trailing ".0" on a commission rate
  /// reads like a system talking rather than a business.
  static String _pct(double v) =>
      '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}%';
}

// ─────────────────────────────────────────────────────────────────────────────
//  Terms, from getHostPayoutTerms. No defaults for the commission — see the
//  header. A missing figure hides its line; it never guesses one.
// ─────────────────────────────────────────────────────────────────────────────
class _Terms {
  const _Terms({
    required this.commissionPct,
    required this.payoutReleaseHoursAfterCheckIn,
    required this.newHostPayoutHoldDays,
    required this.newHostCompletedStaysThreshold,
    required this.payoutsRunning,
  });

  final double commissionPct;
  final int payoutReleaseHoursAfterCheckIn;
  final int newHostPayoutHoldDays;
  final int newHostCompletedStaysThreshold;
  final bool payoutsRunning;

  factory _Terms.fromMap(Map<String, dynamic> m) => _Terms(
        commissionPct: (m['commissionPct'] as num?)?.toDouble() ?? 0,
        payoutReleaseHoursAfterCheckIn:
            (m['payoutReleaseHoursAfterCheckIn'] as num?)?.toInt() ?? 24,
        newHostPayoutHoldDays:
            (m['newHostPayoutHoldDays'] as num?)?.toInt() ?? 30,
        newHostCompletedStaysThreshold:
            (m['newHostCompletedStaysThreshold'] as num?)?.toInt() ?? 1,
        payoutsRunning: m['payoutsRunning'] == true,
      );
}

/// One booking, reduced to what this screen shows.
class _Row {
  const _Row({
    required this.id,
    required this.dates,
    required this.nights,
    required this.payout,
    required this.checkOut,
  });

  final String id;
  final String dates;
  final int nights;
  final Pence payout;
  final DateTime checkOut;
}

// ─────────────────────────────────────────────────────────────────────────────
//  The sums. Done here rather than inline so the rules are readable and
//  testable in one place.
//
//  ── WHICH BOOKINGS COUNT ────────────────────────────────────────────────────
//
//    pending    NOT counted. The host has not accepted it, so it is not
//               theirs. It is surfaced as a nudge instead.
//    confirmed  counted, split by whether the stay has ended.
//    completed  counted as finished, whatever the check-out date says.
//    cancelled  not counted, and not shown. A cancelled booking that still
//               owes the host a fee is a cancellation-policy matter and shows
//               on the booking itself, not as earnings.
//
//  A booking whose status is none of these is ignored rather than lumped in
//  with confirmed. A future status ("disputed", "held") silently counting as
//  earnings is exactly how a wrong number gets shipped.
// ─────────────────────────────────────────────────────────────────────────────
class _Totals {
  _Totals({
    required this.earned,
    required this.upcoming,
    required this.thisMonth,
    required this.finishedCount,
    required this.upcomingCount,
    required this.pendingCount,
    required this.finished,
    required this.ahead,
    required this.truncated,
  });

  final Pence earned;
  final Pence upcoming;
  final Pence thisMonth;
  final int finishedCount;
  final int upcomingCount;
  final int pendingCount;
  final List<_Row> finished;
  final List<_Row> ahead;
  final bool truncated;

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _range(DateTime? a, DateTime? b) {
    if (a == null) return 'Dates unavailable';
    final String from = '${a.day} ${_months[a.month - 1]}';
    if (b == null) return from;
    final bool sameYear = a.year == b.year;
    final String to = '${b.day} ${_months[b.month - 1]} ${b.year}';
    return sameYear ? '$from – $to' : '$from ${a.year} – $to';
  }

  factory _Totals.from(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final DateTime now = DateTime.now();
    final DateTime monthStart = DateTime(now.year, now.month);

    int earned = 0;
    int upcoming = 0;
    int thisMonth = 0;
    int pending = 0;
    final List<_Row> finished = <_Row>[];
    final List<_Row> ahead = <_Row>[];

    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in docs) {
      // One malformed booking must not empty the whole screen. Same rule as
      // the Short Stay listings parse, for the same reason.
      try {
        final Map<String, dynamic> b = d.data();
        final String status = (b['status'] ?? '').toString();

        if (status == 'pending') {
          pending++;
          continue;
        }
        if (status != 'confirmed' && status != 'completed') continue;

        final Map<dynamic, dynamic> pricing =
            (b['pricing'] as Map<dynamic, dynamic>?) ?? const <dynamic, dynamic>{};

        // ⚠ hostPayout, not total. total is what the guest paid and includes
        // both the GoOuts commission and the guest service fee.
        final Pence payout = Pence.fromFirestore(pricing['hostPayout']);

        final DateTime? checkIn = _date(b['checkIn']);
        final DateTime? checkOut = _date(b['checkOut']);
        final int nights = (b['nights'] as num?)?.toInt() ?? 0;

        final _Row row = _Row(
          id: d.id,
          dates: _range(checkIn, checkOut),
          nights: nights,
          payout: payout,
          checkOut: checkOut ?? now,
        );

        final bool done =
            status == 'completed' || (checkOut != null && checkOut.isBefore(now));

        if (done) {
          earned += payout.value;
          finished.add(row);
          if (!row.checkOut.isBefore(monthStart)) thisMonth += payout.value;
        } else {
          upcoming += payout.value;
          ahead.add(row);
        }
      } catch (_) {
        continue;
      }
    }

    finished.sort((a, b) => b.checkOut.compareTo(a.checkOut));
    ahead.sort((a, b) => a.checkOut.compareTo(b.checkOut));

    return _Totals(
      earned: Pence(earned),
      upcoming: Pence(upcoming),
      thisMonth: Pence(thisMonth),
      finishedCount: finished.length,
      upcomingCount: ahead.length,
      pendingCount: pending,
      finished: finished,
      ahead: ahead,
      truncated: docs.length >= _HostEarningsScreenState._queryLimit,
    );
  }
}
