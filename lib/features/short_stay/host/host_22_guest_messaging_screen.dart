// ─────────────────────────────────────────────────────────────────────────────
//  Messages — the host's conversations, one per booking.
//
//  Built 21 August 2026, replacing the guard placed on 9 August.
//
//  ── WHAT THE GUARD SAID ─────────────────────────────────────────────────────
//
//  This screen shipped from Stitch showing three invented conversations —
//  "Sarah Jenkins", "Marcus Thorne" and "The Millers" — each with a property
//  name, a truncated message, a stock photograph of a stranger, and an unread
//  badge. An unread badge is a claim that somebody is waiting for you. Three
//  people who do not exist appeared to be waiting for a reply, and tapping
//  them did nothing.
//
//  It is real now. Every row below is a booking that exists, and every unread
//  mark is counted from messages that were actually sent.
//
//  ── WHY THERE IS NO /stay_threads COLLECTION ────────────────────────────────
//
//  The booking IS the thread. Messages live at stay_bookings/{id}/messages and
//  the two people entitled to read them are already on the parent document.
//  A separate threads collection would carry a second copy of who is involved,
//  and the day the two disagreed somebody would be reading a conversation they
//  are no longer party to. See host_22b_guest_thread_screen for the rest.
//
//  ── WHY ONLY CURRENT AND UPCOMING STAYS ARE LISTED ──────────────────────────
//
//  This screen fetches the last message for each row it shows. Listing every
//  booking a host has ever had would mean one extra live query per booking on
//  every open — a hundred listeners for a busy host, most of them on
//  conversations that ended months ago.
//
//  So the list is scoped to what a host is actually managing: anything not yet
//  checked out, plus the last fortnight. Older threads are not lost — they are
//  reachable from the booking itself, which is where a host looks for them.
//  _windowDays is the one number that controls this.
//
//  ── UNREAD IS LOCAL, AND THAT IS DELIBERATE ─────────────────────────────────
//
//  stay_bookings is `allow update: if false` for clients — every write is a
//  Cloud Function — so a client cannot record read state on the server without
//  a function that does not exist yet. It is stored in SharedPreferences
//  instead, which makes the dot a note to yourself on this phone rather than a
//  claim about what anybody has read. When a notifications function is built,
//  this moves server side.
//
//  ── PUSH NOTIFICATIONS, ADDED 21 AUGUST ─────────────────────────────────────
//
//  This screen used to say a host's phone would not alert them, and that was
//  true: notifyOnStayMessage was deployed and correct, but this app had no
//  firebase_messaging, so no host had a token and the function had nowhere to
//  send. services/host_fcm_service.dart fixed that and the notice on screen
//  was rewritten the same day.
//
//  ⚠ IT DEPENDS ON stay_hosts/{uid}.fcmToken AND ON
//  notificationPrefs.guestMessages, both of which the Cloud Function reads by
//  exactly those names. Renaming either breaks push silently.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/goouts_colors.dart';
import 'host_22b_guest_thread_screen.dart' show threadSeenKey;
import 'host_bottom_nav.dart';
import 'host_routes.dart';

class GuestMessagingScreen extends StatefulWidget {
  const GuestMessagingScreen({super.key});

  @override
  State<GuestMessagingScreen> createState() => _GuestMessagingScreenState();
}

class _GuestMessagingScreenState extends State<GuestMessagingScreen> {
  /// The rules cap list queries on stay_bookings at 100. Raising this breaks
  /// the read for every host at once with a permission error that looks
  /// nothing like a limit problem.
  static const int _queryLimit = 100;

  /// How long after check-out a conversation stays in this list. See header.
  static const int _windowDays = 14;

  Map<String, int> _seen = <String, int>{};

  @override
  void initState() {
    super.initState();
    _loadSeen();
  }

  Future<void> _loadSeen() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      // The prefix comes from threadSeenKey, never from a literal repeated
      // here. Two copies of a key string is how a rename silently orphans
      // every stored value in this project.
      final String prefix = threadSeenKey('');
      final Map<String, int> out = <String, int>{};
      for (final String k in p.getKeys()) {
        if (k.startsWith(prefix)) {
          out[k.substring(prefix.length)] = p.getInt(k) ?? 0;
        }
      }
      if (!mounted) return;
      setState(() => _seen = out);
    } catch (_) {
      // No read state means everything looks unread. Annoying, not wrong.
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
          'Messages',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        // The avatar that sat here was a stock photograph of a stranger,
        // presented as the host's own account picture. It stays removed.
      ),
      body: uid == null
          ? _notice(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to see your messages.',
              detail: 'Conversations belong to your bookings.',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('stay_bookings')
                  .where('hostUid', isEqualTo: uid)
                  .orderBy('createdAt', descending: true)
                  .limit(_queryLimit)
                  .snapshots(),
              builder: (context, snap) {
                // Failed is not empty. "No conversations" and "we could not
                // load your conversations" mean opposite things to a host.
                if (snap.hasError) {
                  return _notice(
                    icon: Icons.cloud_off_rounded,
                    title: 'We could not load your messages.',
                    detail: '${snap.error}',
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: GoOutsColors.primary, strokeWidth: 2),
                  );
                }

                final List<_Thread> threads = _threadsFrom(snap.data!.docs);

                return RefreshIndicator(
                  onRefresh: _loadSeen,
                  color: GoOutsColors.primary,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: <Widget>[
                      _noPushNotice(),
                      const SizedBox(height: 14),
                      if (threads.isEmpty)
                        _empty()
                      else
                        for (final _Thread t in threads) _row(t, uid),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.bookings),
    );
  }

  /// Confirmed and pending bookings inside the window, soonest first.
  ///
  /// Cancelled and declined bookings are excluded: there is nothing left to
  /// arrange, and a cancelled stay sitting at the top of a message list reads
  /// like something needs doing.
  List<_Thread> _threadsFrom(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final DateTime cutoff =
        DateTime.now().subtract(const Duration(days: _windowDays));
    final List<_Thread> out = <_Thread>[];

    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in docs) {
      // One malformed booking must not empty the whole screen.
      try {
        final Map<String, dynamic> b = d.data();
        final String status = (b['status'] ?? '').toString();
        if (status != 'confirmed' && status != 'pending') continue;

        final DateTime? checkIn = _date(b['checkIn']);
        final DateTime? checkOut = _date(b['checkOut']);
        if (checkOut != null && checkOut.isBefore(cutoff)) continue;

        out.add(_Thread(
          bookingId: d.id,
          checkIn: checkIn,
          checkOut: checkOut,
          status: status,
        ));
      } catch (_) {
        continue;
      }
    }

    out.sort((a, b) {
      final DateTime x = a.checkIn ?? DateTime(2100);
      final DateTime y = b.checkIn ?? DateTime(2100);
      return x.compareTo(y);
    });
    return out;
  }

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  // ── ROW ───────────────────────────────────────────────────────────────────

  Widget _row(_Thread t, String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // One message, the latest. Ordered descending and limited to 1 so this
      // is a single document read per row rather than the whole thread.
      stream: FirebaseFirestore.instance
          .collection('stay_bookings')
          .doc(t.bookingId)
          .collection('messages')
          .orderBy('sentAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        String preview = 'No messages yet';
        String stamp = '';
        bool unread = false;

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            snap.data?.docs ?? const [];
        if (docs.isNotEmpty) {
          final Map<String, dynamic> m = docs.first.data();
          final String text = (m['text'] ?? '').toString();
          // ⚠ senderUid, NOT senderRole. senderRole is written by the client
          // and nothing in the rules validates it, so a guest could set it to
          // 'host' and have their own message render as "You: …" in the
          // host's list. senderUid is checked by the rules against the
          // caller's auth, so it cannot be forged.
          final bool mine = (m['senderUid'] ?? '').toString() == uid;
          preview = mine ? 'You: $text' : text;

          final Timestamp? ts = m['sentAt'] as Timestamp?;
          if (ts != null) {
            stamp = _shortStamp(ts.toDate());
            // Unread only when THEY wrote it and this device has not opened
            // the thread since. Your own message is never unread to you.
            final int seen = _seen[t.bookingId] ?? 0;
            unread = !mine && ts.toDate().millisecondsSinceEpoch > seen;
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: GoOutsColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: unread ? GoOutsColors.primary : GoOutsColors.border,
              width: unread ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.of(context).pushNamed(
                HostRoutes.guestThread,
                arguments: t.bookingId,
              );
              await _loadSeen();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.status == 'pending'
                          ? GoOutsColors.tint
                          : GoOutsColors.successBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    // An initial, not a stock photograph of a stranger. We do
                    // not hold a guest photo and inventing one was the
                    // original fault on this screen.
                    child: Icon(
                      t.status == 'pending'
                          ? Icons.hourglass_empty_rounded
                          : Icons.person_outline_rounded,
                      size: 19,
                      color: t.status == 'pending'
                          ? GoOutsColors.primary
                          : GoOutsColors.success,
                    ),
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
                                t.dates,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: GoOutsColors.navy,
                                ),
                              ),
                            ),
                            if (stamp.isNotEmpty)
                              Text(
                                stamp,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: GoOutsColors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: unread
                                ? GoOutsColors.navy
                                : GoOutsColors.onSurfaceVariant,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        if (t.status == 'pending') ...<Widget>[
                          const SizedBox(height: 5),
                          Text(
                            'You have not accepted this booking yet',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: GoOutsColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (unread)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: GoOutsColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── FURNITURE ─────────────────────────────────────────────────────────────

  /// Was "your phone will not alert you", which was true until 21 August 2026
  /// when firebase_messaging was added to this app and notifyOnStayMessage
  /// finally had somewhere to send to. Changed the same day, because a
  /// limitation left on screen after it is fixed teaches hosts to ignore the
  /// app.
  Widget _noPushNotice() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GoOutsColors.infoBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.notifications_active_outlined,
                size: 16, color: GoOutsColors.onSurfaceVariant),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'You will be notified when a guest writes, as long as you '
                'allowed notifications. Change that under Settings, '
                'Notifications.',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  height: 1.45,
                  color: GoOutsColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _empty() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: Column(
          children: <Widget>[
            const Icon(Icons.chat_bubble_outline_rounded,
                size: 32, color: GoOutsColors.draft),
            const SizedBox(height: 12),
            Text('No conversations yet',
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: GoOutsColors.navy)),
            const SizedBox(height: 6),
            Text(
              'When someone books one of your properties you can message them '
              'here, up to a fortnight after they check out.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, height: 1.5, color: GoOutsColors.body),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(HostRoutes.requests),
              icon: const Icon(Icons.calendar_month_outlined, size: 17),
              label: const Text('See your bookings'),
              style: OutlinedButton.styleFrom(
                foregroundColor: GoOutsColors.primary,
                side: const BorderSide(color: GoOutsColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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

  static String _shortStamp(DateTime d) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime that = DateTime(d.year, d.month, d.day);
    final int diff = today.difference(that).inDays;
    if (diff == 0) return DateFormat('HH:mm').format(d);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEE').format(d);
    return DateFormat('d MMM').format(d);
  }
}

class _Thread {
  _Thread({
    required this.bookingId,
    required this.checkIn,
    required this.checkOut,
    required this.status,
  });

  final String bookingId;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String status;

  String get dates {
    if (checkIn == null) return 'Booking';
    final String a = DateFormat('d MMM').format(checkIn!);
    if (checkOut == null) return a;
    return '$a – ${DateFormat('d MMM').format(checkOut!)}';
  }
}
