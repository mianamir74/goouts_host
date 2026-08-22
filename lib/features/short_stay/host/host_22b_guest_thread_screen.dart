// ─────────────────────────────────────────────────────────────────────────────
//  One conversation, for one booking.
//
//  Built 21 August 2026.
//
//  ── THE BOOKING IS THE THREAD ───────────────────────────────────────────────
//
//  There is no /stay_threads collection and there should not be one. Messages
//  live at stay_bookings/{id}/messages, so a conversation cannot exist without
//  a booking behind it, and the people entitled to read it are already written
//  on the parent document: guestUid and hostUid.
//
//  That is not just tidy. A separate threads collection would need its own
//  membership list, and the day that list disagreed with the booking — a
//  cancelled stay, a changed guest — somebody would be reading a conversation
//  they are no longer party to. Here it cannot drift, because there is only
//  one copy of who is involved.
//
//  ── WHAT THE RULES ENFORCE, AND WHY IT MATTERS HERE ─────────────────────────
//
//  firestore.rules on this subcollection (fixed the same day as this screen):
//
//    read    you are the guest or the host on the parent booking
//    create  the same, AND senderUid is you, AND `text` is a 1..2000 character
//            string, AND sentAt == request.time
//    update  never
//    delete  never
//
//  Three consequences this screen has to respect:
//
//  1. sentAt MUST be FieldValue.serverTimestamp(). A DateTime.now() from the
//     phone is rejected outright — request.time is the server's clock and the
//     rule compares against it. This is deliberate: a message timestamp is
//     evidence in a dispute and the person holding the phone can change their
//     device clock.
//
//  2. NOTHING CAN BE EDITED OR DELETED, by anyone, including us. A host who
//     can revise what they promised about check-in wins every argument about
//     what they promised. The UI must not offer an edit that would fail.
//
//  3. The field is `text`. Not body, not message, not content. The consumer
//     app writes this same collection and the rule now refuses any other name,
//     so the two apps cannot drift apart the way this codebase's field names
//     have several times before.
//
//  ── WHAT IS DELIBERATELY NOT HERE ───────────────────────────────────────────
//
//  No read receipts and no "delivered" tick. Nothing on the server records
//  that the other person opened this, so either would be a claim we cannot
//  back. Push notifications DO exist as of 21 August 2026 — see
//  services/host_fcm_service.dart and admin_panel/functions/stay_messages.js.
//  Delivery to the phone is not the same as the other person having read it,
//  and only the second would justify a tick.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/goouts_colors.dart';

/// SharedPreferences key for "I have seen this thread up to here".
///
/// Read state is LOCAL AND PER DEVICE on purpose. stay_bookings is
/// `allow update: if false` for clients — every write is a Cloud Function —
/// so a client cannot record read state on the server without a function that
/// does not exist yet. Storing it locally is honest: it makes the unread dot
/// a note to yourself on this phone, not a claim about what anyone has read.
String threadSeenKey(String bookingId) => 'stay_thread_seen_$bookingId';

class GuestThreadScreen extends StatefulWidget {
  const GuestThreadScreen({super.key});

  @override
  State<GuestThreadScreen> createState() => _GuestThreadScreenState();
}

class _GuestThreadScreenState extends State<GuestThreadScreen> {
  /// A thread is not a feed. 200 messages is far more than a stay generates
  /// and keeps one conversation to a single, bounded read.
  static const int _messageLimit = 200;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _sending = false;
  String? _sendError;
  bool _markedSeen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute is not available in initState, and build() is the wrong
    // place — a StreamBuilder rebuild on every incoming message would mean a
    // preferences write per message. Once per open is what is meant.
    if (_markedSeen) return;
    final Object? arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.isNotEmpty) {
      _markedSeen = true;
      _markSeen(arg);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Object? arg = ModalRoute.of(context)?.settings.arguments;
    final String bookingId = arg is String ? arg : '';
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
          'Message your guest',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: bookingId.isEmpty || uid == null
          ? _notice(
              'This conversation could not be opened.',
              'Go back and choose a booking.',
            )
          : Column(
              children: <Widget>[
                _permanentRecordNotice(),
                Expanded(child: _messages(bookingId, uid)),
                _composer(bookingId, uid),
              ],
            ),
    );
  }

  // ── MESSAGES ──────────────────────────────────────────────────────────────

  Widget _messages(String bookingId, String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stay_bookings')
          .doc(bookingId)
          .collection('messages')
          .orderBy('sentAt')
          .limit(_messageLimit)
          .snapshots(),
      builder: (context, snap) {
        // Failed is not empty. An empty thread and a thread that would not
        // load look identical to a host, and one of them means "reply now".
        if (snap.hasError) {
          return _notice(
            'We could not load this conversation.',
            '${snap.error}',
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(
                color: GoOutsColors.primary, strokeWidth: 2),
          );
        }

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            snap.data!.docs;
        if (docs.isEmpty) return _emptyThread();

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final Map<String, dynamic> m = docs[i].data();
            final bool mine = (m['senderUid'] ?? '').toString() == uid;

            // A message written a second ago has a null sentAt until the
            // server timestamp lands. Showing "null" or falling back to the
            // device clock are both wrong; "Sending…" is what is happening.
            final Timestamp? ts = m['sentAt'] as Timestamp?;

            final bool showDay = i == 0 ||
                !_sameDay(ts, docs[i - 1].data()['sentAt'] as Timestamp?);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (showDay && ts != null) _dayDivider(ts.toDate()),
                _bubble(
                  text: (m['text'] ?? '').toString(),
                  mine: mine,
                  stamp: ts == null ? 'Sending…' : _time(ts.toDate()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _bubble({
    required String text,
    required bool mine,
    required String stamp,
  }) =>
      Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine ? GoOutsColors.primary : GoOutsColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
            border: mine ? null : Border.all(color: GoOutsColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: mine ? Colors.white : GoOutsColors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stamp,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: mine
                      ? Colors.white.withValues(alpha: 0.75)
                      : GoOutsColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _dayDivider(DateTime d) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GoOutsColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _dayLabel(d),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: GoOutsColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );

  Widget _emptyThread() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 34, color: GoOutsColors.draft),
              const SizedBox(height: 12),
              Text(
                'No messages yet',
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: GoOutsColors.navy),
              ),
              const SizedBox(height: 6),
              Text(
                'Say hello, confirm your arrival arrangements, or answer a '
                'question. Your guest sees this in their GoOuts app.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13, height: 1.5, color: GoOutsColors.body),
              ),
            ],
          ),
        ),
      );

  /// ⚠ SAYS SO BEFORE THE FIRST MESSAGE, NOT IN A POLICY NOBODY READS.
  /// Nothing here can be edited or deleted by anyone, and a host is entitled
  /// to know that before they type rather than after they wish they hadn't.
  Widget _permanentRecordNotice() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        color: GoOutsColors.infoBackground,
        child: Row(
          children: <Widget>[
            const Icon(Icons.lock_outline_rounded,
                size: 14, color: GoOutsColors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Messages cannot be edited or deleted, by you, your guest or '
                'GoOuts. They can be used to settle a dispute.',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  height: 1.4,
                  color: GoOutsColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );

  // ── COMPOSER ──────────────────────────────────────────────────────────────

  Widget _composer(String bookingId, String uid) => Container(
        padding: EdgeInsets.fromLTRB(
          12,
          10,
          12,
          10 + MediaQuery.of(context).viewPadding.bottom,
        ),
        decoration: const BoxDecoration(
          color: GoOutsColors.surface,
          border: Border(top: BorderSide(color: GoOutsColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_sendError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline_rounded,
                        size: 15, color: GoOutsColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _sendError!,
                        style: GoogleFonts.inter(
                            fontSize: 11.5, color: GoOutsColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    // The rule rejects anything over 2000 characters. Stopping
                    // it at the keyboard is kinder than a permission error
                    // after the host has written an essay.
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.inter(
                        fontSize: 14, color: GoOutsColors.navy),
                    decoration: InputDecoration(
                      hintText: 'Write a message',
                      counterText: '',
                      hintStyle: GoogleFonts.inter(
                          fontSize: 14, color: GoOutsColors.draft),
                      filled: true,
                      fillColor: GoOutsColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide:
                            const BorderSide(color: GoOutsColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide:
                            const BorderSide(color: GoOutsColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide:
                            const BorderSide(color: GoOutsColors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: _sending
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: GoOutsColors.primary),
                          ),
                        )
                      : IconButton.filled(
                          onPressed: () => _send(bookingId, uid),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: GoOutsColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> _send(String bookingId, String uid) async {
    final String text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _sendError = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('stay_bookings')
          .doc(bookingId)
          .collection('messages')
          .add(<String, dynamic>{
        // Required by the rule. Not decorative — it is how the thread knows
        // which side of the screen this belongs on.
        'senderUid': uid,
        'senderRole': 'host',
        'text': text,
        // ⚠ SERVER TIME. FieldValue.serverTimestamp() resolves to
        // request.time during rule evaluation, which is what the rule
        // compares against. A DateTime.now() here is rejected, and that is
        // the point — a device clock can be changed by its owner.
        'sentAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _input.clear();
      setState(() => _sending = false);
      await _markSeen(bookingId);
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        // The host's words stay in the box. Clearing the field on a failed
        // send loses what they wrote and they have no way to get it back.
        _sendError = 'That did not send. Check your connection and try '
            'again. ($e)';
      });
    }
  }

  void _scrollToEnd() {
    // The new message has not been laid out yet when this runs, so jump after
    // the frame rather than to a maxScrollExtent that is already stale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _markSeen(String bookingId) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setInt(
          threadSeenKey(bookingId), DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // A preference that will not save costs an unread dot, nothing more.
    }
  }

  // ── FORMATTING ────────────────────────────────────────────────────────────

  static bool _sameDay(Timestamp? a, Timestamp? b) {
    if (a == null || b == null) return false;
    final DateTime x = a.toDate();
    final DateTime y = b.toDate();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  static String _time(DateTime d) => DateFormat('HH:mm').format(d);

  static String _dayLabel(DateTime d) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime that = DateTime(d.year, d.month, d.day);
    final int diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('d MMMM yyyy').format(d);
  }

  Widget _notice(String title, String detail) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded,
                  size: 34, color: GoOutsColors.draft),
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
}
