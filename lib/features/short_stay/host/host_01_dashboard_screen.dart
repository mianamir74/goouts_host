// Host dashboard.
//
// ── REWRITTEN 8 AUGUST 2026. WHAT WAS WRONG ────────────────────────────────
//
// The original was the Google Stitch export, imported 4 August. On a real
// phone it read as a completely broken screen, and that reading was correct:
//
//   • BottomNavigationBar had NO onTap. Five tabs, none of which navigated.
//     Tapping "Listings" moved the highlight and nothing else.
//   • Accept and Decline were `onPressed: () {}` — they animated on press
//     and did nothing, on a booking that did not exist.
//   • "View all" was a Text, not a button.
//   • Every figure was invented: "£2,450 earnings", "12 upcoming stays",
//     "4.9 rating", a guest called Sarah Jenkins requesting The Seaside
//     Cottage, three named arrivals. All rendered as though real, none of it
//     connected to anything.
//   • Two guest photographs were hot-linked from Unsplash — strangers' faces
//     presented as this host's guests.
//
// It now reads the signed-in host's own account. Where there is no data it
// says so plainly rather than filling the space with something invented,
// because a dashboard that guesses is worse than one that admits it is
// empty — a host cannot tell the difference until they act on a number.
//
// The backends it calls (listHostBookingRequests, acceptStayBooking,
// declineStayBooking) are LIVE. Earnings and ratings are not, and are
// labelled as not yet available instead of being filled with a plausible
// number.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import '../services/stay_host_service.dart';
import 'host_routes.dart';

import 'host_collection.dart';
import 'friendly_error.dart';

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({super.key});

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  final _service = StayHostService.instance;

  bool _loadingRequests = true;
  String? _requestsError;
  List<HostBookingRequest> _requests = const [];

  /// The booking currently being accepted or declined, so only that card
  /// shows a spinner and a second tap on it is ignored.
  String? _busyBookingId;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loadingRequests = true;
      _requestsError = null;
    });
    try {
      final list = await _service.pendingRequests();
      if (!mounted) return;
      setState(() {
        _requests = list;
        _loadingRequests = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Shown, never swallowed. A silently empty "Action Required" section
      // means a host misses a booking request and never learns there was
      // one — the same failure mode as the eight fake restaurants.
      setState(() {
        _requestsError = _friendlyError(e);
        _loadingRequests = false;
      });
    }
  }

  /// Firebase Functions errors arrive as a wall of jargon. The two that
  /// actually happen here get plain English; anything else falls through
  /// with its message intact so a real fault is still diagnosable.
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('unauthenticated')) {
      return 'Your session expired. Please sign out and back in.';
    }
    if (s.contains('unavailable') || s.contains('DEADLINE')) {
      return 'Could not reach GoOuts. Check your connection and pull down '
          'to refresh.';
    }
    // Was 'Could not load booking requests.\n$s' — and $s is e.toString(),
    // which carries the full Dart stack trace onto the dashboard. See
    // friendly_error.dart.
    return friendlyError(e, fallback: 'Could not load booking requests.');
  }

  Future<void> _respond(HostBookingRequest r, {required bool accept}) async {
    setState(() => _busyBookingId = r.bookingId);
    try {
      final String message;
      if (accept) {
        final didAccept = await _service.accept(r.bookingId);
        message = didAccept
            ? 'Booking accepted. The guest has been told.'
            : 'That booking was already accepted.';
      } else {
        final freed = await _service.decline(r.bookingId);
        message = freed > 0
            ? 'Declined. $freed ${freed == 1 ? "night" : "nights"} are '
                'available again.'
            : 'Declined.';
      }
      if (!mounted) return;
      setState(() {
        _requests =
            _requests.where((x) => x.bookingId != r.bookingId).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor:
            accept ? GoOutsColors.success : GoOutsColors.onSurfaceVariant,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not update the booking. ${_friendlyError(e)}'),
        backgroundColor: GoOutsColors.error,
      ));
    } finally {
      if (mounted) setState(() => _busyBookingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: GoOutsColors.background,
      appBar: AppBar(
        backgroundColor: GoOutsColors.surface,
        elevation: 0.5,
        title: Text(
          'Dashboard',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GoOutsColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          // Was a bare Icon — decoration that looked like a button. Both of
          // these now go somewhere.
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.notifications_none,
                color: GoOutsColors.navy),
            onPressed: () =>
                Navigator.of(context).pushNamed(HostRoutes.notifications),
          ),
          IconButton(
            tooltip: 'Your profile',
            icon: const Icon(Icons.account_circle_outlined,
                color: GoOutsColors.navy),
            onPressed: () =>
                Navigator.of(context).pushNamed(HostRoutes.profile),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRequests,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _greeting(uid),
            const SizedBox(height: 20),
            _summary(uid),
            const SizedBox(height: 24),
            _actionRequired(),
            const SizedBox(height: 28),
            _quickActions(),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  // ── GREETING ─────────────────────────────────────────────────────────────
  //
  // Reads the host's own business name. Said "Good morning, Sarah" at every
  // hour of the day, to everyone.
  Widget _greeting(String? uid) {
    final hour = DateTime.now().hour;
    final partOfDay = hour < 12
        ? 'Good morning'
        : (hour < 18 ? 'Good afternoon' : 'Good evening');

    if (uid == null) {
      return Text(partOfDay,
          style: GoogleFonts.inter(
              color: GoOutsColors.navy,
              fontSize: 24,
              fontWeight: FontWeight.w700));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(kStayHostsCollection)
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? const <String, dynamic>{};
        final name = (d['legalBusinessName'] ??
                d['businessName'] ??
                d['firstName'] ??
                '')
            .toString()
            .trim();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              name.isEmpty ? partOfDay : '$partOfDay, $name',
              style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'An overview of your hosting.',
              style:
                  GoogleFonts.inter(color: GoOutsColors.body, fontSize: 15),
            ),
          ],
        );
      },
    );
  }

  // ── SUMMARY ──────────────────────────────────────────────────────────────
  //
  // Only the listing counts are real, so only they are shown as numbers.
  // Earnings and rating were the two most convincing invented figures on the
  // old screen and are the two that would do the most damage if believed, so
  // they are stated as unavailable rather than estimated.
  Widget _summary(String? uid) {
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stay_listings')
          .where('hostUid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _notice(
            'Could not load your properties. ${snap.error}',
            GoOutsColors.error,
            Icons.error_outline_rounded,
          );
        }
        final docs = snap.data?.docs ?? const [];
        final live =
            docs.where((d) => d.data()['status'] == 'live').length;
        final drafts =
            docs.where((d) => d.data()['status'] == 'draft').length;

        return Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _statCard(
                    'LIVE PROPERTIES',
                    snap.hasData ? '$live' : '—',
                    sub: live == 0
                        ? 'None visible to guests yet'
                        : 'Visible to guests',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard(
                    'AWAITING APPROVAL',
                    snap.hasData ? '$drafts' : '—',
                    sub: drafts == 0
                        ? 'Nothing pending'
                        : 'Being checked by GoOuts',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _statCard(
              'EARNINGS',
              'Not yet available',
              sub: 'Payments are not live. There is nothing to report yet.',
              muted: true,
            ),
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value,
      {String? sub, bool muted = false}) {
    return Container(
      width: double.infinity,
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
            label,
            style: GoogleFonts.inter(
              color: GoOutsColors.onSurfaceVariant,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              color: muted ? GoOutsColors.onSurfaceVariant : GoOutsColors.navy,
              fontSize: muted ? 15 : 26,
              fontWeight: muted ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
          if (sub != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              sub,
              style: GoogleFonts.inter(
                  color: GoOutsColors.body, fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  // ── ACTION REQUIRED ──────────────────────────────────────────────────────
  Widget _actionRequired() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Action required',
              style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            // Was a Text styled to look like a link. Now a real button.
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(HostRoutes.requests),
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_loadingRequests)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_requestsError != null)
          _notice(_requestsError!, GoOutsColors.error,
              Icons.error_outline_rounded)
        else if (_requests.isEmpty)
          _notice(
            'No booking requests waiting for you.',
            GoOutsColors.onSurfaceVariant,
            Icons.check_circle_outline_rounded,
          )
        else
          ..._requests.map(_requestCard),
      ],
    );
  }

  Widget _requestCard(HostBookingRequest r) {
    final busy = _busyBookingId == r.bookingId;
    final dates = _dateRange(r.checkIn, r.checkOut);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GoOutsColors.tint.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: GoOutsColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Booking request',
            style: GoogleFonts.inter(
              color: GoOutsColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$dates · ${r.nights} ${r.nights == 1 ? "night" : "nights"} · '
            '${r.countedGuests} ${r.countedGuests == 1 ? "guest" : "guests"}',
            style:
                GoogleFonts.inter(color: GoOutsColors.body, fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          // What the HOST receives, never the guest total. Showing the
          // guest's total here is the easiest way to make this screen lie.
          Text(
            'You would receive ${r.hostPayout.formatted}',
            style: GoogleFonts.inter(
              color: GoOutsColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'After GoOuts commission. No payment has been taken yet.',
            style: GoogleFonts.inter(
                color: GoOutsColors.onSurfaceVariant, fontSize: 11.5),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      busy ? null : () => _respond(r, accept: false),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: GoOutsColors.surface,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Decline',
                      style: GoogleFonts.inter(
                          color: GoOutsColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _respond(r, accept: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GoOutsColors.primary,
                    minimumSize: const Size(0, 48),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Accept',
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── QUICK ACTIONS ────────────────────────────────────────────────────────
  //
  // Replaces "Next Arrivals", which listed three invented guests. These are
  // the destinations a host actually needs, and all of them open.
  Widget _quickActions() {
    const items = <_QuickAction>[
      _QuickAction(
          'Add a property', Icons.add_home_outlined, HostRoutes.newAddress),
      _QuickAction('My properties', Icons.holiday_village_outlined,
          HostRoutes.myListings),
      _QuickAction('Availability calendar', Icons.calendar_today_outlined,
          HostRoutes.calendar),
      _QuickAction('Booking requests', Icons.mark_email_unread_outlined,
          HostRoutes.requests),
      _QuickAction('Payout details', Icons.account_balance_outlined,
          HostRoutes.payoutDetails),
      _QuickAction('Help centre', Icons.help_outline_rounded, HostRoutes.help),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Manage',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: GoOutsColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: GoOutsColors.border),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < items.length; i++) ...<Widget>[
                ListTile(
                  leading: Icon(items[i].icon, color: GoOutsColors.primary),
                  title: Text(
                    items[i].label,
                    style: GoogleFonts.inter(
                        color: GoOutsColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: GoOutsColors.onSurfaceVariant),
                  onTap: () =>
                      Navigator.of(context).pushNamed(items[i].route),
                ),
                if (i != items.length - 1)
                  const Divider(
                      height: 1, indent: 56, color: GoOutsColors.border),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _notice(
          'Some screens behind these links are still being built and will '
          'show placeholder content. Anything you can tap on this dashboard '
          'is real.',
          GoOutsColors.onSurfaceVariant,
          Icons.info_outline_rounded,
        ),
      ],
    );
  }

  // ── BOTTOM NAV ───────────────────────────────────────────────────────────
  //
  // ⚠ THE ORIGINAL HAD NO onTap AT ALL. Five tabs that moved a highlight and
  // navigated nowhere — the single most visible fault on the screen.
  Widget _bottomNav() {
    const destinations = <String>[
      '', // Dashboard — already here, so nothing to push.
      HostRoutes.requests,
      HostRoutes.myListings,
      HostRoutes.messaging,
      HostRoutes.profile,
    ];

    return Container(
      decoration: const BoxDecoration(
        color: GoOutsColors.surface,
        border:
            Border(top: BorderSide(color: GoOutsColors.border, width: 1)),
      ),
      child: BottomNavigationBar(
        elevation: 0,
        backgroundColor: GoOutsColors.surface,
        selectedItemColor: GoOutsColors.primary,
        unselectedItemColor: GoOutsColors.body,
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        selectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
        onTap: (i) {
          final route = destinations[i];
          if (route.isEmpty) return; // Dashboard tab, already showing.
          Navigator.of(context).pushNamed(route);
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined), label: 'Bookings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.holiday_village_outlined), label: 'Listings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.mail_outline), label: 'Inbox'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  // ── SHARED BITS ──────────────────────────────────────────────────────────

  Widget _notice(String text, Color colour, IconData icon) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colour.withValues(alpha: 0.20)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: colour),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                    fontSize: 12.5, color: GoOutsColors.body, height: 1.4),
              ),
            ),
          ],
        ),
      );

  static const _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dateRange(DateTime? from, DateTime? to) {
    if (from == null || to == null) return 'Dates to be confirmed';
    final f = '${from.day} ${_months[from.month - 1]}';
    final t = '${to.day} ${_months[to.month - 1]}';
    return '$f – $t';
  }
}

/// One row of the Manage list. A named class rather than a record so the
/// three fields read as `label`, `icon`, `route` at the point of use instead
/// of `$1`, `$2`, `$3` — three positional strings are easy to transpose.
class _QuickAction {
  const _QuickAction(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}
