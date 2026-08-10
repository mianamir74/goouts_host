// Notifications — the FEED.
//
// ── THE HOST APP HAD THIS BACKWARDS ──────────────────────────────────────
//
// 10 August 2026. In goouts_app, "Notifications" means a feed of things that
// happened: bell icon top right with a red count, and a row on the profile
// under Preferences. In the host app "Notifications" meant a page of on/off
// toggles, and there was NO feed at all.
//
// That is not a naming quibble. It was silently losing messages:
//
//   * stay_host.js notify() writes to /notifications when a booking is
//     accepted, declined or cancelled.
//   * index.js writes a kyc_decision notification — "Identity Verified",
//     "Verification Unsuccessful" — to {collection}/{uid}/notifications, and
//     stay_hosts IS in its allow-list.
//
// So the server has been writing host notifications to
// stay_hosts/{uid}/notifications, and nothing in the app has ever read that
// path. A host got verified and never saw the message.
//
// This screen is the missing reader. Same behaviour as the consumer's
// notifications_screen: mark-all-read, mark read on tap, swipe to delete,
// icon per type, and tap routing by the `screen` field.
//
// ── UNREAD IS THREE FIELDS, NOT ONE ──────────────────────────────────────
//
// The writers disagree. isRead was used by three of them and `read` by two
// (the KYC decision and the broadcast). Both are now written by the server,
// but documents created BEFORE that fix have only one of the two, and they
// are still in the database. _isUnread therefore treats a document as read if
// ANY of the three flags is true, which is the only reading that gets old and
// new documents right.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_bottom_nav.dart';
import 'host_collection.dart';
import 'host_routes.dart';

class HostNotificationsScreen extends StatefulWidget {
  const HostNotificationsScreen({super.key});

  @override
  State<HostNotificationsScreen> createState() =>
      _HostNotificationsScreenState();
}

class _HostNotificationsScreenState extends State<HostNotificationsScreen> {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _ref => FirebaseFirestore
      .instance
      .collection(kStayHostsCollection)
      .doc(_uid)
      .collection('notifications');

  /// Read if ANY flag says so. See the header note on field drift.
  static bool _isUnread(Map<String, dynamic> d) =>
      d['isRead'] != true && d['read'] != true && d['seen'] != true;

  Future<void> _markAllRead() async {
    if (_uid.isEmpty) return;
    // No `where` clause — an equality filter on isRead would miss every
    // document that only carries `read`, which is exactly the set that has
    // been invisible until now. Filter in Dart instead.
    final snap = await _ref.get();
    final unread = snap.docs.where((d) => _isUnread(d.data())).toList();
    if (unread.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final d in unread) {
      batch.set(
        d.reference,
        <String, dynamic>{'isRead': true, 'read': true, 'seen': true},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> _markRead(String id) => _ref.doc(id).set(
        <String, dynamic>{'isRead': true, 'read': true, 'seen': true},
        SetOptions(merge: true),
      );

  Future<void> _delete(String id) => _ref.doc(id).delete();

  // ── Tap routing ──────────────────────────────────────────────────────────
  //
  // Mirrors the consumer's switch on `screen`, mapped to the routes this app
  // actually has. An unknown value opens nothing rather than throwing — a
  // notification written by a future server version must not crash an older
  // build that does not know the destination yet.
  Future<void> _onTap(Map<String, dynamic> d, String id) async {
    await _markRead(id);
    if (!mounted) return;

    final screen = (d['screen'] ?? d['data']?['screen'] ?? '').toString();
    final route = switch (screen) {
      'kyc' || 'verification' => HostRoutes.profile,
      'profile' => HostRoutes.profile,
      'bookings' || 'booking' || 'requests' => HostRoutes.requests,
      'listings' || 'listing' => HostRoutes.myListings,
      'calendar' => HostRoutes.calendar,
      'earnings' || 'payouts' => HostRoutes.earnings,
      'messages' || 'support_ticket_chat' => HostRoutes.messageCenter,
      'notifications' => '',
      _ => '',
    };
    if (route.isEmpty) return;
    if (!mounted) return;
    Navigator.of(context).pushNamed(route);
  }

  // ── Icon per type — same vocabulary as the consumer ─────────────────────
  static (IconData, Color) _styleFor(String type) => switch (type) {
        'kyc_approved' || 'kyc_decision' => (
            Icons.verified_outlined,
            GoOutsColors.success
          ),
        'kyc_rejected' => (Icons.security_outlined, GoOutsColors.error),
        'ticket_reply' => (Icons.chat_outlined, GoOutsColors.primary),
        'ticket_status' => (Icons.support_agent_outlined, GoOutsColors.primary),
        'booking' || 'booking_request' => (
            Icons.event_available_outlined,
            GoOutsColors.primary
          ),
        'booking_cancelled' => (Icons.event_busy_outlined, GoOutsColors.error),
        'listing' || 'listing_approved' => (
            Icons.holiday_village_outlined,
            GoOutsColors.success
          ),
        'listing_rejected' => (
            Icons.holiday_village_outlined,
            GoOutsColors.error
          ),
        'payout' => (
            Icons.account_balance_wallet_outlined,
            GoOutsColors.success
          ),
        'broadcast' => (Icons.campaign_outlined, GoOutsColors.primary),
        _ => (Icons.notifications_none_outlined, GoOutsColors.onSurfaceVariant),
      };

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
        title: Text('Notifications',
            style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: <Widget>[
          TextButton(
            onPressed: _uid.isEmpty ? null : _markAllRead,
            child: Text('Mark all read',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: GoOutsColors.primary)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _uid.isEmpty
          ? _empty(Icons.lock_outline_rounded, 'You are signed out',
              'Sign in again to see your notifications.')
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  _ref.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _empty(
                      Icons.wifi_off_rounded,
                      'Could not load notifications',
                      'Check your connection and try again.');
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return _empty(
                      Icons.notifications_none_rounded,
                      'Nothing yet',
                      'Booking requests, verification decisions and news from '
                          'GoOuts will appear here.');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  itemCount: docs.length,
                  itemBuilder: (context, i) => _card(docs[i]),
                );
              },
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.home),
    );
  }

  Widget _card(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final unread = _isUnread(d);
    final (icon, tone) = _styleFor((d['type'] ?? '').toString());

    return Dismissible(
      key: ValueKey<String>(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: GoOutsColors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: GoOutsColors.error),
      ),
      onDismissed: (_) => _delete(doc.id),
      child: GestureDetector(
        onTap: () => _onTap(d, doc.id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: GoOutsColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: unread
                    ? GoOutsColors.primary.withValues(alpha: 0.35)
                    : GoOutsColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(icon, color: tone, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            (d['title'] ?? 'GoOuts').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 14.5,
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: GoOutsColors.navy),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: GoOutsColors.primary,
                                shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (d['body'] ?? d['message'] ?? '').toString(),
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: GoOutsColors.body,
                          height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(_when(d['createdAt']),
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: GoOutsColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                    color: GoOutsColors.infoBg, shape: BoxShape.circle),
                child: Icon(icon, color: GoOutsColors.primary, size: 34),
              ),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: GoOutsColors.navy)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: GoOutsColors.body,
                      height: 1.5)),
            ],
          ),
        ),
      );

  static String _when(dynamic v) {
    if (v is! Timestamp) return '';
    final d = v.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final t = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'Today $t';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $t';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year} $t';
  }
}

/// Unread count for the bell badge.
///
/// Top-level so the dashboard and the profile share one source. Streams the
/// whole collection and counts in Dart rather than filtering server-side,
/// because `where('isRead', isEqualTo: false)` would miss every document that
/// only carries `read` — which is precisely the KYC-decision notifications
/// that matter most.
Stream<int> hostUnreadNotificationsStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream<int>.value(0);
  return FirebaseFirestore.instance
      .collection(kStayHostsCollection)
      .doc(uid)
      .collection('notifications')
      .snapshots()
      .map((s) => s.docs
          .where((d) =>
              d.data()['isRead'] != true &&
              d.data()['read'] != true &&
              d.data()['seen'] != true)
          .length);
}
