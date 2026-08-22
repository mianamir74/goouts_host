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

import '../../../services/host_fcm_service.dart';
import '../../../theme/goouts_colors.dart';
import '../services/stay_host_service.dart';
import 'host_routes.dart';

import 'host_collection.dart';
import 'friendly_error.dart';
import 'host_bottom_nav.dart';
import '../../support/host_support_service.dart';
import 'host_26_notifications_screen.dart';

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

    // ── THE ONLY PLACE THE NOTIFICATION PERMISSION IS ASKED FOR ───────────
    //
    // Post login, post first frame, and nowhere else.
    //
    // requestPermission() internally calls registerForRemoteNotifications(),
    // which this app's AppDelegate ALREADY calls at startup for Firebase
    // Phone Auth. Calling it during app startup causes a second APNs
    // registration and an iOS crash with no useful stack — crash type C in
    // memory_claud/ios_firebase_phone_auth_crash_fix.md, thirteen builds of
    // driver_app to find. Here, after the dashboard has drawn, it is safe.
    //
    // Fire and forget. A host who declines still gets a working dashboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HostFcmService.instance.askPermission();
    });
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
          // Was a bare Icon — decoration that looked like a button. All of
          // these now go somewhere.
          _messagesAction(),
          // The bell opens the FEED, not the toggles.
          //
          // It used to open notification preferences — a page of switches. In
          // goouts_app a bell with a red count means "things happened, come
          // and look", and that is what people expect. The toggles now live
          // under Settings where a preference belongs.
          _notificationsAction(),
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
      // Shared nav, same as the other thirteen screens.
      //
      // This screen used to build its own five tabs, and tab 4 was
      // "Inbox" here while it is "Earnings" everywhere else. Tapping it
      // opened the guest-chat screen, which then drew the SHARED nav with
      // Bookings highlighted — so a host landed on a page titled Messages,
      // saw "not open yet", and had Bookings lit up underneath. Three
      // wrongs in one tap. Messages now lives in the app bar above.
      bottomNavigationBar: const HostBottomNav(current: HostTab.home),
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

        // ── HERO CARD. Polished 10 August 2026. ──────────────────────────
        //
        // Was two lines of plain text on the page background. The screen had
        // no anchor and no colour, so it read as a settings list rather than
        // a dashboard.
        //
        // The gradient is navy → primary, the same pair the splash and the
        // sign-in screens use, so opening the app feels continuous.
        //
        // ⚠ THE VERIFICATION CHIP IS THE POINT, NOT THE DECORATION.
        //
        // Whether a host is verified decides whether createStayListing will
        // accept anything they do. Before this, that fact lived only on the
        // home screen and inside a server error message — a host could fill in
        // eight wizard screens and be refused at the last one. Now it is the
        // first thing on the dashboard, with the next step written next to it.
        //
        // Same three fields, same order of authority, as host_home_screen and
        // requireVerifiedHost() on the server. If this list changes, those
        // change.
        final kyc = (d['kycStatus'] ??
                d['businessProfileVerificationStatus'] ??
                d['status'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
        final approved = kyc == 'approved' || kyc == 'verified';
        final rejected = kyc == 'rejected';

        final (String chipText, IconData chipIcon, Color chipColour) = switch (
            (approved, rejected)) {
          (true, _) => ('Verified', Icons.verified_rounded, GoOutsColors.success),
          (_, true) => (
              'Not approved',
              Icons.cancel_outlined,
              GoOutsColors.error
            ),
          _ => (
              'Verification in progress',
              Icons.hourglass_top_rounded,
              GoOutsColors.warning
            ),
        };

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[GoOutsColors.navy, GoOutsColors.teal],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                partOfDay,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name.isEmpty ? 'Welcome back' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(chipIcon, size: 15, color: chipColour),
                    const SizedBox(width: 7),
                    Text(
                      chipText,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (!approved) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  rejected
                      ? 'Your identity check was not approved. Contact support '
                          'and we will explain what is needed.'
                      : 'You can build a listing now. GoOuts must verify you '
                          'before guests can see it.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
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
                    icon: Icons.holiday_village_rounded,
                    accent: GoOutsColors.success,
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
                    icon: Icons.pending_actions_rounded,
                    accent: GoOutsColors.warning,
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
              icon: Icons.payments_outlined,
              accent: GoOutsColors.onSurfaceVariant,
              sub: 'Payments are not live. There is nothing to report yet.',
              muted: true,
            ),
          ],
        );
      },
    );
  }

  /// A single figure, with an icon chip to give the card a focal point.
  ///
  /// [accent] tints only the icon, never the number. A green "2" and an amber
  /// "1" would imply one is good and the other bad, when both are just counts
  /// — and the moment a number carries a judgement, someone acts on the colour
  /// instead of reading the label.
  Widget _statCard(String label, String value,
      {String? sub,
      bool muted = false,
      IconData? icon,
      Color accent = GoOutsColors.primary}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GoOutsColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GoOutsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: GoOutsColors.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
      // Guest conversations. NOT HostRoutes.messageCenter — that is GoOuts
      // support, a different inbox entirely, and the two were one tap apart
      // in the app bar with nothing distinguishing them.
      _QuickAction('Message guests', Icons.chat_bubble_outline_rounded,
          HostRoutes.messaging),
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
        // ── A GRID, NOT A LIST. Polished 10 August 2026. ─────────────────
        //
        // Six identical rows with an icon and a chevron is a settings menu,
        // and it made the dashboard look like one. A 2-column grid of cards
        // gives each destination equal visual weight and halves the vertical
        // space, so "Manage" and the booking requests above it both fit on a
        // phone without scrolling.
        //
        // Same shape as the Quick Help grid on the FAQ screen, deliberately —
        // one grid pattern across the app rather than two.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.55,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).pushNamed(items[i].route),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GoOutsColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: GoOutsColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: GoOutsColors.tint,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(items[i].icon,
                        size: 19, color: GoOutsColors.primary),
                  ),
                  Text(
                    items[i].label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: GoOutsColors.navy,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
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


  // ── NOTIFICATIONS BELL ───────────────────────────────────────────────────
  //
  // Same badge treatment as the messages icon beside it. Count comes from
  // hostUnreadNotificationsStream, which counts in Dart rather than with a
  // where clause — see the note on that function for why.
  Widget _notificationsAction() => StreamBuilder<int>(
        stream: hostUnreadNotificationsStream(),
        builder: (context, snap) {
          final n = snap.data ?? 0;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(Icons.notifications_none,
                    color: GoOutsColors.navy),
                onPressed: () => Navigator.of(context)
                    .pushNamed(HostRoutes.notificationFeed),
              ),
              if (n > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: GoOutsColors.error,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: GoOutsColors.surface, width: 1.5),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 17, minHeight: 17),
                    child: Text(
                      n > 9 ? '9+' : '$n',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
            ],
          );
        },
      );
  // ── MESSAGES ─────────────────────────────────────────────────────────────
  //
  // Badge count comes from HostSupportService.unreadCountStream(), the same
  // stream the profile tile and the Message Center's Support chip use. One
  // source, so the three can never show different numbers.
  Widget _messagesAction() => StreamBuilder<int>(
        stream: HostSupportService().unreadCountStream(),
        builder: (context, snap) {
          final n = snap.data ?? 0;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              IconButton(
                tooltip: 'Messages',
                icon: const Icon(Icons.mail_outline, color: GoOutsColors.navy),
                onPressed: () => Navigator.of(context)
                    .pushNamed(HostRoutes.messageCenter),
              ),
              if (n > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: GoOutsColors.error,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: GoOutsColors.surface, width: 1.5),
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 17, minHeight: 17),
                    child: Text(
                      n > 9 ? '9+' : '$n',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
            ],
          );
        },
      );
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
