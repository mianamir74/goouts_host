// Support tickets — the list, and the thread.
//
// ── WHY BOTH SCREENS ARE IN ONE FILE ───────────────────────────────────────
//
// goouts_app keeps these apart (support_tickets_screen.dart and
// support_ticket_chat_screen.dart). Here they are together because one is
// never opened without the other, they share the status-chip styling, and the
// host app has 26 files where the consumer app has 125 — splitting a 400-line
// pair into two files buys nothing and costs a jump every time you read it.
//
// If this grows past ~600 lines, split it the way goouts_app does.
//
// ── WHAT THESE FIX ─────────────────────────────────────────────────────────
//
// Created 9 August 2026. A host could send a support ticket and never see the
// reply — the admin answered into a void. See host_support_service.dart.
//
// Visual language is deliberately the consumer app's: the same status chips,
// the same colours, the same right-aligned-you / left-aligned-them bubbles. A
// host who also uses GoOuts as a customer should not have to learn two
// support screens.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/goouts_colors.dart';
import 'host_support_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  LIST
// ═══════════════════════════════════════════════════════════════════════════
class HostSupportTicketsScreen extends StatefulWidget {
  const HostSupportTicketsScreen({super.key});

  @override
  State<HostSupportTicketsScreen> createState() =>
      _HostSupportTicketsScreenState();
}

class _HostSupportTicketsScreenState extends State<HostSupportTicketsScreen> {
  final _service = HostSupportService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.getMyTickets();
      if (!mounted) return;
      setState(() {
        _tickets = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Shown, not swallowed. An error rendered as "no messages" is how a host
      // concludes nobody replied when in fact somebody did.
      setState(() {
        _error = 'Could not load your messages. Pull down to try again.';
        _loading = false;
      });
    }
  }

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
        title: Text('Messages',
            style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _centered(Icons.error_outline_rounded, _error!)
                : _tickets.isEmpty
                    ? _centered(
                        Icons.forum_outlined,
                        'No messages yet.\n\nWhen you contact support, the '
                        'conversation appears here and you will see the reply.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _tickets.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _card(_tickets[i]),
                      ),
      ),
    );
  }

  Widget _centered(IconData icon, String text) => ListView(
        // ListView, not Center — RefreshIndicator needs a scrollable child or
        // pull-to-refresh does nothing on an empty list, which is exactly when
        // someone most wants to retry.
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 120),
          Icon(icon, size: 44, color: GoOutsColors.onSurfaceVariant),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 14, color: GoOutsColors.body, height: 1.55)),
          ),
        ],
      );

  Widget _card(Map<String, dynamic> t) {
    final style = HostSupportService.statusStyle((t['status'] ?? '').toString());
    final unread = t['unreadByUser'] == true;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => HostSupportChatScreen(
            ticketId: (t['id'] ?? '').toString(),
            ticketNumber: (t['ticketNumber'] ?? '').toString(),
          ),
        ));
        // Reload on return so the unread dot clears without a manual pull.
        if (mounted) _load();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: unread ? GoOutsColors.primary : GoOutsColors.border,
              width: unread ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (unread) ...<Widget>[
                  Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: GoOutsColors.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    (t['subject'] ?? t['categoryLabel'] ?? 'Support request')
                        .toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                        color: GoOutsColors.navy),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Color(style['bg'] as int),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(style['label'] as String,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(style['color'] as int))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              (t['lastMessage'] ?? t['message'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 13, color: GoOutsColors.body, height: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Text((t['ticketNumber'] ?? '').toString(),
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: GoOutsColors.onSurfaceVariant)),
                const Spacer(),
                Text(
                    HostSupportService.formatRelative(
                        t['lastMessageAt'] ?? t['createdAt']),
                    style: GoogleFonts.inter(
                        fontSize: 11, color: GoOutsColors.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  THREAD
// ═══════════════════════════════════════════════════════════════════════════
class HostSupportChatScreen extends StatefulWidget {
  final String ticketId;
  final String ticketNumber;

  const HostSupportChatScreen({
    super.key,
    required this.ticketId,
    this.ticketNumber = '',
  });

  @override
  State<HostSupportChatScreen> createState() => _HostSupportChatScreenState();
}

class _HostSupportChatScreenState extends State<HostSupportChatScreen> {
  final _service = HostSupportService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Clear the unread flag as soon as the thread is opened, not when it is
    // closed — a host who reads and backs out has still read it.
    _service.markAdminMessagesRead(widget.ticketId);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    // Cleared immediately so a slow network cannot produce a double send from
    // an impatient second tap.
    _ctrl.clear();
    try {
      await _service.sendMessage(ticketId: widget.ticketId, text: text);
    } catch (_) {
      if (!mounted) return;
      // Put the text back — losing what someone typed is worse than an error.
      _ctrl.text = text;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not send. Check your connection and try again.'),
        backgroundColor: GoOutsColors.error,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('GoOuts Support',
                style: GoogleFonts.inter(
                    color: GoOutsColors.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            if (widget.ticketNumber.isNotEmpty)
              Text(widget.ticketNumber,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: GoOutsColors.onSurfaceVariant)),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          _statusBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.messagesStream(widget.ticketId),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text('Could not load this conversation.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              fontSize: 13.5, color: GoOutsColors.body)),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Text('No messages yet.',
                        style: GoogleFonts.inter(
                            fontSize: 13.5, color: GoOutsColors.body)),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  // reverse:true with a reversed index keeps the newest message
                  // pinned at the bottom without any scroll maths.
                  itemBuilder: (context, i) =>
                      _bubble(docs[docs.length - 1 - i].data()),
                );
              },
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _statusBar() =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _service.ticketStream(widget.ticketId),
        builder: (context, snap) {
          final d = snap.data?.data();
          if (d == null) return const SizedBox.shrink();
          final style =
              HostSupportService.statusStyle((d['status'] ?? '').toString());
          return Container(
            width: double.infinity,
            color: Color(style['bg'] as int),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Status: ${style['label']}',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(style['color'] as int)),
            ),
          );
        },
      );

  Widget _bubble(Map<String, dynamic> m) {
    // 'sender' and 'senderType' are both written by every GoOuts app; read
    // both so a message written by any of them renders on the right side.
    final who = (m['senderType'] ?? m['sender'] ?? '').toString();
    final mine = who == 'user';
    final text = (m['text'] ?? '').toString();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76),
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
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  (m['senderName'] ?? 'GoOuts Support').toString(),
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: GoOutsColors.primary),
                ),
              ),
            Text(
              text,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: mine ? Colors.white : GoOutsColors.navy),
            ),
            const SizedBox(height: 4),
            Text(
              HostSupportService.formatRelative(m['createdAt']),
              style: GoogleFonts.inter(
                fontSize: 10,
                color: mine
                    ? Colors.white.withValues(alpha: 0.75)
                    : GoOutsColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: GoOutsColors.surface,
          border: Border(top: BorderSide(color: GoOutsColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Write a message',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _sending ? null : _send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: GoOutsColors.primary,
                      borderRadius: BorderRadius.circular(22)),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      );
}
