// Support tickets for hosts — the reply half of the conversation.
//
// ── WHY THIS EXISTS ────────────────────────────────────────────────────────
//
// Created 9 August 2026. Before it, a host could SEND a support ticket and had
// no way whatsoever to see the answer.
//
// showPreAuthSupportSheet wrote a document to support_requests, the admin panel
// showed it under Support → Hosts, an admin typed a reply — and it went
// nowhere. The host app had no tickets list, no thread, no unread badge. The
// admin believed they had answered. The host believed they had been ignored.
//
// The pipeline was never the problem: goouts_app, driver_app, goouts_drapp and
// goouts_host ALL write to the same support_requests collection, which is why
// one admin screen can see every role's tickets. Only the host app was missing
// the client half.
//
// ── PORTED FROM goouts_app/lib/services/support_ticket_service.dart ────────
//
// Deliberately close to that file so the two stay recognisable to whoever
// reads them next. Four differences, all forced:
//
//   1. accountType 'business' and sourceCollection 'stay_hosts', matching what
//      pre_auth_support_sheet already stamps. Writing 'user'/'users' here — the
//      consumer values — would file host tickets into the consumer tab and the
//      host queue would look empty while hosts waited.
//
//   2. Profile fields come from /stay_hosts, not UserService. The host app has
//      no UserService; a host IS their stay_hosts record.
//
//   3. getMyTickets() also picks up PRE-AUTH tickets. Those are written with
//      uid: '' because the person was not signed in when they sent it, so a
//      uid query alone would never return them — a host who asked for help
//      before registering could never see the reply. Matched on phone number
//      instead, and only for tickets that carry the pre-auth flag.
//
//   4. No linkedTransactionId. Hosts have no transactions yet.
//
// ⚠ IF YOU CHANGE THE FIELD NAMES HERE, CHANGE THEM IN THE ADMIN PANEL TOO.
// The admin Support section reads senderType, unreadByAdmin, lastMessageBy and
// sourceCollection by exactly these names.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../short_stay/host/host_collection.dart';

class HostSupportService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// What a host record is called in support_requests. Must match
  /// pre_auth_support_sheet's mapping for accountType 'business'.
  static const String kAccountType = 'business';

  // ── Priority ─────────────────────────────────────────────────────────────
  //
  // Same shape as the consumer app's, retuned for what actually goes wrong for
  // a host. Money and access are high; "how do I" is low.
  static String _autoPriority(String category, String subTopic) {
    final s = subTopic.toLowerCase();
    final c = category.toLowerCase();

    if (s.contains('payout') ||
        s.contains('not paid') ||
        s.contains('missing money') ||
        s.contains('fraud') ||
        s.contains('damage') ||
        s.contains('claim') ||
        s.contains('account locked') ||
        s.contains('cannot log in') ||
        s.contains('security') ||
        c == 'account_security') {
      return 'high';
    }

    if (s.contains('how') || s.contains('general') || s.contains('other') ||
        c == 'other') {
      return 'low';
    }

    return 'medium';
  }

  /// The host's own name, email and phone, read from their /stay_hosts record.
  Future<Map<String, String>> _hostIdentity(String uid) async {
    try {
      final snap = await _db.collection(kStayHostsCollection).doc(uid).get();
      final d = snap.data() ?? const <String, dynamic>{};
      final name = (d['legalBusinessName'] ??
              d['fullName'] ??
              d['contactPersonName'] ??
              '')
          .toString()
          .trim();
      return <String, String>{
        'fullName': name,
        'email': (d['email'] ?? '').toString().trim(),
        'phone': (d['phoneNumber'] ?? _auth.currentUser?.phoneNumber ?? '')
            .toString()
            .trim(),
      };
    } catch (_) {
      // A failed profile read must not stop someone asking for help. The
      // ticket still goes in; the admin can see who it is from the uid.
      return <String, String>{
        'fullName': '',
        'email': '',
        'phone': _auth.currentUser?.phoneNumber ?? '',
      };
    }
  }

  // ── Create ───────────────────────────────────────────────────────────────
  Future<Map<String, String>> submitTicket({
    required String category,
    required String categoryLabel,
    required String subject,
    required String message,
    String subTopic = '',
    String priority = '',
    Map<String, dynamic> contextSnapshot = const <String, dynamic>{},
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    final id = await _hostIdentity(user.uid);
    final fullName = id['fullName'] ?? '';

    final resolved =
        priority.isNotEmpty ? priority : _autoPriority(category, subTopic);

    final ref = _db.collection('support_requests').doc();
    final ticketNum = 'SR-${ref.id.substring(0, 8).toUpperCase()}';
    final msgText = message.trim();

    await ref.set(<String, dynamic>{
      'uid': user.uid,
      'fullName': fullName,
      'firstName': fullName.split(' ').first,
      'surname': fullName.contains(' ')
          ? fullName.substring(fullName.indexOf(' ') + 1)
          : '',
      'email': id['email'] ?? '',
      'mobileNumber': id['phone'] ?? '',
      // ⚠ These two decide which tab the ticket lands in. See the note at the
      // top of this file.
      'accountType': kAccountType,
      'sourceCollection': kStayHostsCollection,
      'category': category,
      'categoryLabel': categoryLabel,
      'subTopic': subTopic,
      'subject': subject.trim(),
      'message': msgText,
      'status': 'new',
      'priority': resolved,
      'ticketNumber': ticketNum,
      if (contextSnapshot.isNotEmpty) 'contextSnapshot': contextSnapshot,
      'lastMessage': msgText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageBy': 'user',
      'unreadByAdmin': true,
      'unreadByUser': false,
      'adminReply': '',
      'adminRepliedAt': null,
      'adminRepliedBy': '',
      'rating': 0,
      'ratingComment': '',
      'ratingLabel': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await ref.collection('messages').add(<String, dynamic>{
      'sender': 'user',
      // senderType is what the admin panel reads. Both are written because the
      // consumer app writes both and the panel has grown to expect it.
      'senderType': 'user',
      'senderName': fullName,
      'text': msgText,
      'imageUrl': '',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return <String, String>{
      'ticketId': ref.id,
      'ticketNumber': ticketNum,
      'fullName': fullName,
    };
  }

  // ── Reply ────────────────────────────────────────────────────────────────
  Future<void> sendMessage({
    required String ticketId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final id = await _hostIdentity(user.uid);
    final msgText = text.trim();
    if (msgText.isEmpty) return;

    final ref = _db.collection('support_requests').doc(ticketId);

    await ref.collection('messages').add(<String, dynamic>{
      'sender': 'user',
      'senderType': 'user',
      'senderName': id['fullName'] ?? 'Host',
      'text': msgText,
      'imageUrl': '',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await ref.update(<String, dynamic>{
      'lastMessage': msgText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageBy': 'user',
      'unreadByAdmin': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Clears the unread flag once the host has actually opened the thread.
  Future<void> markAdminMessagesRead(String ticketId) async {
    try {
      final snap = await _db
          .collection('support_requests')
          .doc(ticketId)
          .collection('messages')
          .where('sender', isEqualTo: 'admin')
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, <String, dynamic>{'isRead': true});
      }
      await batch.commit();

      await _db
          .collection('support_requests')
          .doc(ticketId)
          .update(<String, dynamic>{'unreadByUser': false});
    } catch (_) {
      // Best effort. Failing to clear a badge must never block reading.
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String ticketId) =>
      _db
          .collection('support_requests')
          .doc(ticketId)
          .collection('messages')
          .orderBy('createdAt')
          .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> ticketStream(String ticketId) =>
      _db.collection('support_requests').doc(ticketId).snapshots();

  // ── Read ─────────────────────────────────────────────────────────────────
  //
  // Two queries, not one, and no orderBy on either.
  //
  //   • No orderBy: an equality filter plus an orderBy on a different field
  //     needs a composite index, and a missing index fails the whole query at
  //     runtime with an error most people never see. Sorted client-side.
  //
  //   • Two queries because a PRE-AUTH ticket carries uid: '' — the person
  //     was not signed in when they sent it. Matching on uid alone would hide
  //     every ticket sent before registration, which is exactly when someone
  //     is most likely to need help.
  Future<List<Map<String, dynamic>>> getMyTickets() async {
    final user = _auth.currentUser;
    if (user == null) return <Map<String, dynamic>>[];

    final results = <String, Map<String, dynamic>>{};

    try {
      final byUid = await _db
          .collection('support_requests')
          .where('uid', isEqualTo: user.uid)
          .where('sourceCollection', isEqualTo: kStayHostsCollection)
          .get();
      for (final d in byUid.docs) {
        results[d.id] = <String, dynamic>{'id': d.id, ...d.data()};
      }
    } catch (_) {/* fall through — a partial list beats none */}

    // Pre-auth tickets, matched on the phone number they left.
    final phone = (await _hostIdentity(user.uid))['phone'] ?? '';
    if (phone.isNotEmpty) {
      try {
        final byPhone = await _db
            .collection('support_requests')
            .where('mobileNumber', isEqualTo: phone)
            .where('preAuthTicket', isEqualTo: true)
            .get();
        for (final d in byPhone.docs) {
          results[d.id] = <String, dynamic>{'id': d.id, ...d.data()};
        }
      } catch (_) {/* pre-auth tickets are a bonus, never a blocker */}
    }

    final list = results.values.toList();
    list.sort((a, b) {
      final ta = a['createdAt'];
      final tb = b['createdAt'];
      if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return 0;
    });
    return list;
  }

  /// Drives the badge on Profile → Messages.
  Stream<int> unreadCountStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream<int>.value(0);
    return _db
        .collection('support_requests')
        .where('uid', isEqualTo: uid)
        .where('sourceCollection', isEqualTo: kStayHostsCollection)
        .where('unreadByUser', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Future<void> rateTicket({
    required String ticketId,
    required int rating,
    required String comment,
  }) async {
    const labels = <String>['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'];
    await _db.collection('support_requests').doc(ticketId).update(
      <String, dynamic>{
        'rating': rating,
        'ratingComment': comment.trim(),
        'ratingLabel': rating >= 1 && rating <= 5 ? labels[rating] : '',
        'ratedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  // ── Display helpers ──────────────────────────────────────────────────────
  //
  // Same statuses and the same colours as the consumer app, so a status chip
  // means the same thing in every GoOuts app.
  static Map<String, dynamic> statusStyle(String status) {
    switch (status.toLowerCase()) {
      case 'new':
        return {'label': 'New', 'color': 0xFF0392CA, 'bg': 0xFFD6EEF8};
      case 'in_progress':
        return {'label': 'In Progress', 'color': 0xFFD97706, 'bg': 0xFFFEF3C7};
      case 'need_more_info':
        return {'label': 'Need More Info', 'color': 0xFF7C3AED, 'bg': 0xFFEDE9FE};
      case 'waiting_driver':
      case 'waiting_user':
        return {'label': 'Waiting for You', 'color': 0xFF0891B2, 'bg': 0xFFE0F7FA};
      case 'resolved':
        return {'label': 'Resolved', 'color': 0xFF16A34A, 'bg': 0xFFDCFCE7};
      case 'closed':
        return {'label': 'Closed', 'color': 0xFF64748B, 'bg': 0xFFF1F5F9};
      default:
        return {'label': status, 'color': 0xFF757575, 'bg': 0xFFF0F0F0};
    }
  }

  static String formatDate(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    const months = <String>[
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }

  static String formatRelative(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}
