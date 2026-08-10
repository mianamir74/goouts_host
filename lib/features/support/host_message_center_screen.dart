// Message Center — host.
//
// Ported from goouts_app/lib/screens/message_center_screen.dart. Same filter
// chips, same card layout, same unread dot, same swipe-to-delete.
//
// ── WHY THIS SCREEN EXISTS ───────────────────────────────────────────────
//
// 10 August 2026. A host asked a fair question: when an admin sends me a
// message, where does it land? The honest answer was "in two places, neither
// of them obvious":
//
//   * A DIRECT message from an admin creates a support_requests ticket. The
//     host could only find it via Profile, three taps down.
//   * A BROADCAST reached hosts nowhere at all — the fan-out never looked in
//     stay_hosts, so the job reported success having written nothing.
//
// Meanwhile the thing actually labelled "Messages" on the dashboard was the
// guest-chat screen, which is not built and says so. So a host looking for
// their messages was sent to a dead end while their real messages sat
// somewhere else entirely.
//
// This screen is now the single answer to "where are my messages".
//
// ── THE FIVE FILTERS ─────────────────────────────────────────────────────
//
// All / Support / Security / Offers / Updates.
//
// Support is the extra one the consumer app does not have, and it is a
// different SHAPE from the other four:
//
//   Support  -> support_requests (a CONVERSATION — the host can reply)
//   The rest -> stay_hosts/{uid}/messages (ANNOUNCEMENTS — one way, read only)
//
// That is why Support is not merged into the inbox list. Merging them would
// mean either a reply box on a broadcast, or a conversation the host cannot
// answer. Both are worse than one extra chip.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../short_stay/host/host_bottom_nav.dart';
import '../short_stay/host/host_collection.dart';
import 'host_support_screens.dart';
import 'host_support_service.dart';

class HostMessageCenterScreen extends StatefulWidget {
  const HostMessageCenterScreen({super.key});

  @override
  State<HostMessageCenterScreen> createState() =>
      _HostMessageCenterScreenState();
}

class _HostMessageCenterScreenState extends State<HostMessageCenterScreen> {
  static const Color _primary = Color(0xFF0392CA);
  static const Color _dark = Color(0xFF0D1B3E);
  static const Color _chipBg = Color(0xFFD6EEF8);

  final _support = HostSupportService();

  int _selected = 0; // 0=All 1=Support 2=Security 3=Offers 4=Updates
  bool _argsRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    // Callers that mean "my support replies" push with arguments: 1 so the
    // screen opens on Support instead of All. Anything else opens on All.
    final a = ModalRoute.of(context)?.settings.arguments;
    if (a is int && a >= 0 && a < _filters.length) {
      _selected = a;
    }
  }
  static const List<String> _filters = <String>[
    'All',
    'Support',
    'Security',
    'Offers',
    'Updates',
  ];

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// The announcement inbox. Written by processUserMessageJob when a broadcast
  /// targets stay_hosts. Nothing else writes here.
  CollectionReference<Map<String, dynamic>> get _inbox => FirebaseFirestore
      .instance
      .collection(kStayHostsCollection)
      .doc(_uid)
      .collection('messages');

  // ── Filtering ────────────────────────────────────────────────────────────
  bool _matches(Map<String, dynamic> d) {
    if (_selected == 0) return true;
    final cat = (d['category'] ?? '').toString().toLowerCase();
    return switch (_selected) {
      2 => cat == 'security' || cat == 'account',
      3 => cat == 'offers' || cat == 'offer' || cat == 'promo',
      4 => cat == 'updates' || cat == 'update' || cat == 'announcement',
      _ => true,
    };
  }

  Future<void> _markRead(String id) => _inbox.doc(id).set(
        <String, dynamic>{
          // Three names for one idea, all written together. The consumer app,
          // the broadcast function and the older driver inbox each check a
          // different one, and a message that stays bold forever because only
          // two of the three were set looks like a bug to the person reading.
          'isRead': true,
          'read': true,
          'seen': true,
          'readAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  Future<void> _delete(String id) => _inbox.doc(id).delete();

  static bool _isUnread(Map<String, dynamic> d) =>
      d['isRead'] != true && d['read'] != true && d['seen'] != true;

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _primary, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Messages',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700, color: _primary)),
        centerTitle: false,
      ),
      body: _uid.isEmpty
          ? _empty(Icons.lock_outline_rounded, 'You are signed out',
              'Sign in again to see your messages.')
          : Column(
              children: <Widget>[
                _filterBar(),
                Expanded(
                  child: _selected == 1 ? _supportList() : _inboxList(),
                ),
              ],
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.home),
    );
  }

  // ── Filter chips ─────────────────────────────────────────────────────────
  Widget _filterBar() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List<Widget>.generate(_filters.length, (i) {
              final on = _selected == i;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selected = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: on ? _primary : const Color(0xFFF0F6FA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: on ? _primary : Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(_filters[i],
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight:
                                    on ? FontWeight.w700 : FontWeight.w500,
                                color: on ? Colors.white : Colors.grey[700])),
                        if (i == 1) _supportBadge(on),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );

  /// Unread count on the Support chip, from the same stream the profile tile
  /// uses — so the two can never disagree.
  Widget _supportBadge(bool chipSelected) => StreamBuilder<int>(
        stream: _support.unreadCountStream(),
        builder: (context, snap) {
          final n = snap.data ?? 0;
          if (n <= 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: chipSelected ? Colors.white : const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(n > 9 ? '9+' : '$n',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: chipSelected ? _primary : Colors.white)),
            ),
          );
        },
      );

  // ── Support tab — the admin conversation ────────────────────────────────
  //
  // Not a list of its own. HostSupportTicketsScreen already renders these and
  // handles reply, read state and the pre-auth phone match. Rebuilding that
  // here would be a second copy to keep in step.
  Widget _supportList() => const HostSupportTicketsScreen(embedded: true);

  // ── Announcement inbox ───────────────────────────────────────────────────
  Widget _inboxList() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _inbox.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _empty(Icons.wifi_off_rounded, 'Could not load messages',
                'Check your connection and pull to refresh.');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs
              .where((d) => _matches(d.data()))
              .toList(growable: false);

          if (docs.isEmpty) {
            return _empty(
              Icons.mark_email_read_outlined,
              _selected == 0
                  ? 'No messages yet'
                  : 'Nothing under ${_filters[_selected]}',
              _selected == 0
                  ? 'Announcements from GoOuts will appear here. Replies to '
                      'your support tickets are under Support.'
                  : 'Try All to see everything you have been sent.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, i) => _card(docs[i]),
          );
        },
      );

  Widget _card(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final unread = _isUnread(d);
    final cat = (d['category'] ?? '').toString().toLowerCase();
    final (IconData icon, Color tone) = switch (cat) {
      'security' || 'account' => (Icons.shield_outlined, Colors.red),
      'offers' || 'offer' || 'promo' => (
          Icons.local_offer_outlined,
          const Color(0xFF388E3C)
        ),
      'updates' || 'update' || 'announcement' => (
          Icons.campaign_outlined,
          _primary
        ),
      _ => (Icons.mail_outline_rounded, _primary),
    };

    return Dismissible(
      key: ValueKey<String>(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
      ),
      onDismissed: (_) => _delete(doc.id),
      child: GestureDetector(
        onTap: () {
          if (unread) _markRead(doc.id);
          _openDetail(d);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: unread ? _primary.withValues(alpha: 0.35)
                              : Colors.grey.shade200),
            boxShadow: <BoxShadow>[
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
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
                                color: _dark),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: _primary, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (d['body'] ?? d['message'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: Colors.grey[600],
                          height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(_when(d['createdAt']),
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> d) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx2, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text((d['title'] ?? 'GoOuts').toString(),
                  style: GoogleFonts.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: _dark)),
              const SizedBox(height: 6),
              Text(_when(d['createdAt']),
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Colors.grey[400])),
              const SizedBox(height: 16),
              if ((d['imageUrl'] ?? '').toString().isNotEmpty) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    d['imageUrl'].toString(),
                    fit: BoxFit.cover,
                    // A broken image URL must not take the message with it.
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text((d['body'] ?? d['message'] ?? '').toString(),
                  style: GoogleFonts.inter(
                      fontSize: 14.5, color: _dark, height: 1.6)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _chipBg, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.info_outline_rounded,
                        color: _primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'This is an announcement from GoOuts. To reply, use '
                          'Support.',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: _dark, height: 1.4)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => _selected = 1);
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Go to Support',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
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
                    color: _chipBg, shape: BoxShape.circle),
                child: Icon(icon, color: _primary, size: 34),
              ),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _dark)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: Colors.grey[600],
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
