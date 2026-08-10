import 'package:auto_size_text/auto_size_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:goouts_host/features/common/goouts_sheet.dart';

/// Standalone pre-authentication support bottom sheet.
import '../../short_stay/host/host_collection.dart';
/// Used on Login and Registration screens — no uid required.
/// Writes directly to support_requests with preAuthTicket: true.
void showPreAuthSupportSheet(BuildContext context, {String accountType = 'driver'}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PreAuthSupportSheet(accountType: accountType),
  );
}

class _PreAuthSupportSheet extends StatefulWidget {
  final String accountType;
  const _PreAuthSupportSheet({required this.accountType});

  @override
  State<_PreAuthSupportSheet> createState() => _PreAuthSupportSheetState();
}

class _PreAuthSupportSheetState extends State<_PreAuthSupportSheet> {
  static const Color _blue   = Color(0xFF0392CA);
  static const Color _dark   = Color(0xFF1C1C1C);
  static const Color _grey   = Color(0xFF6B7280);
  static const Color _bg     = Color(0xFFF4FAFD);
  static const Color _border = Color(0xFFE8EEF3);

  static const List<Map<String, String>> _topics = [
    {'value': 'otp_not_received',      'label': "Didn't receive OTP"},
    {'value': 'wrong_number',          'label': 'Wrong phone number used'},
    {'value': 'account_suspended',     'label': 'Account suspended or rejected'},
    {'value': 'referral_code_issue',   'label': 'Referral code not working'},
    {'value': 'cant_register',         'label': "Can't complete registration"},
    {'value': 'other',                 'label': 'Something else'},
  ];

  String? _selectedTopic;
  bool    _submitting = false;
  bool    _submitted  = false;

  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _msgCtrl   = TextEditingController();
  final _formKey   = GlobalKey<FormState>();

  // ── SIGNED-IN HOSTS. Added 10 August 2026. ────────────────────────────────
  //
  // This sheet was written for the PRE-authentication case — the sign-in
  // screen, where nobody is logged in and there is no record to read. It is
  // now also opened from Profile and the FAQ screen, where the host IS signed
  // in, and it was still asking them to type their own name and phone number.
  //
  // Worse than the retyping: it wrote uid: '' and preAuthTicket: true
  // regardless. So a ticket raised from Profile by a fully verified host
  // arrived in the admin panel labelled as a pre-login enquiry from nobody,
  // and getMyTickets() could only find it by matching the phone number they
  // happened to type. Get the number slightly wrong — spaces, +44 vs 07 — and
  // the host would never see the reply to their own ticket.
  //
  // So: when signed in, prefill from /stay_hosts and stamp the real uid.
  User? get _user => FirebaseAuth.instance.currentUser;
  bool get _isSignedIn => _user != null;

  /// True once the profile read has finished, so the fields are not shown as
  /// editable-and-empty for the half second before they fill.
  bool _prefilling = false;

  @override
  void initState() {
    super.initState();
    if (_isSignedIn) _prefillFromProfile();
  }

  Future<void> _prefillFromProfile() async {
    setState(() => _prefilling = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_sourceCollection)
          .doc(_user!.uid)
          .get();
      final d = snap.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = (d['legalBusinessName'] ??
                d['fullName'] ??
                d['contactPersonName'] ??
                '')
            .toString()
            .trim();
        _phoneCtrl.text =
            (d['phoneNumber'] ?? _user?.phoneNumber ?? '').toString().trim();
        _prefilling = false;
      });
    } catch (_) {
      // A failed read must never block someone asking for help. Fall back to
      // the auth phone number and let them type the rest.
      if (!mounted) return;
      setState(() {
        _phoneCtrl.text = _user?.phoneNumber ?? '';
        _prefilling = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  String get _sourceCollection {
    switch (widget.accountType) {
      case 'business':   return kStayHostsCollection;
      case 'cab_driver': return 'cab_drivers';
      default:           return 'drivers';
    }
  }

  Future<void> _submit() async {
    if (_selectedTopic == null) {
      GoOutsSheet.warning(context, title: 'Select Topic', message: 'Please select a topic.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    final topicLabel = _topics
        .firstWhere((t) => t['value'] == _selectedTopic)['label'] ?? '';

    try {
      final ref     = FirebaseFirestore.instance.collection('support_requests').doc();
      final shortId = ref.id.substring(0, 8).toUpperCase();
      final name    = _nameCtrl.text.trim();

      await ref.set({
        // The real uid when signed in, so the host can find this ticket and
        // read the reply. '' only when genuinely pre-authentication.
        'uid':                _user?.uid ?? '',
        'preAuthTicket':      !_isSignedIn,
        'fullName':           name,
        'firstName':          name.split(' ').first,
        'surname':            name.contains(' ')
                                  ? name.substring(name.indexOf(' ') + 1)
                                  : '',
        'email':              '',
        'mobileNumber':       _phoneCtrl.text.trim(),
        'accountType':        widget.accountType,
        'sourceCollection':   _sourceCollection,
        'category':           _selectedTopic,
        'categoryLabel':      topicLabel,
        'subTopic':           '',
        // 'Pre-login:' only when it actually is. A verified host raising a
        // ticket from Profile was getting every subject prefixed "Pre-login",
        // which tells the admin the opposite of the truth.
        'subject':            _isSignedIn ? topicLabel : 'Pre-login: $topicLabel',
        'message':            _msgCtrl.text.trim(),
        'status':             'new',
        'priority':           _selectedTopic == 'account_suspended' ? 'high' : 'medium',
        'ticketNumber':       'SR-$shortId',
        'referralCode':       '',
        'lastMessage':        _msgCtrl.text.trim(),
        'lastMessageAt':      FieldValue.serverTimestamp(),
        // ── ⚠ FIELD NAMES. Corrected 10 August 2026. ────────────────────
        //
        // This sheet was written for driver_app and still spoke its dialect:
        // lastMessageBy 'driver' and unreadByDriver. host_support_service
        // reads unreadByUser — so a ticket raised HERE would never light the
        // unread badge on Profile, and the host would never learn support had
        // replied. Same class of drift as the FAQ cat/q/a and kycStatus bugs.
        //
        // BOTH unread keys are written. The admin panel reads unreadByDriver
        // for driver tickets and unreadByUser for the rest; writing one would
        // fix this app and quietly break that one.
        'lastMessageBy':      'user',
        'unreadByAdmin':      true,
        'unreadByUser':       false,
        'unreadByDriver':     false,
        'adminReply':         '',
        'adminRepliedBy':     '',
        'rating':             0,
        'ratingComment':      '',
        'ratingLabel':        '',
        'selfServiceAttempted': false,
        'createdAt':          FieldValue.serverTimestamp(),
        'updatedAt':          FieldValue.serverTimestamp(),
      });

      await ref.collection('messages').add({
        // 'user', not 'driver', and senderType alongside it.
        //
        // host_support_screens decides which side of the thread a bubble sits
        // on with `senderType ?? sender`. Written as 'driver' this message —
        // the host's own — rendered LEFT-aligned and labelled "GoOuts
        // Support", so a host opening their ticket saw their own words
        // attributed to us.
        'sender':     'user',
        'senderType': 'user',
        'senderName': name,
        'text':       _msgCtrl.text.trim(),
        'imageUrl':   '',
        'isRead':     false,
        'createdAt':  FieldValue.serverTimestamp(),
      });

      if (mounted) setState(() { _submitting = false; _submitted = true; });
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        GoOutsSheet.error(context, title: 'Send Failed', message: 'Failed to send. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: _submitted ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  Widget _buildSuccess() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 12),
      Container(
        width: 56, height: 56,
        decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7), shape: BoxShape.circle),
        child: const Icon(Icons.check_circle_rounded,
            color: Color(0xFF16A34A), size: 30),
      ),
      const SizedBox(height: 14),
      const AutoSizeText('Message Sent',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
              color: _dark)),
      const SizedBox(height: 8),
      const AutoSizeText(
          'Our support team will get back to you shortly.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _grey, height: 1.5)),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity, height: 48,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: _blue, elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
          child: const AutoSizeText('Done',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      ),
    ],
  );

  /// Small caps label above each field.
  ///
  /// The sheet previously relied on hint text alone, which vanishes the moment
  /// someone starts typing — so halfway through the form the fields have no
  /// labels at all and you cannot tell which box you are in.
  static Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: _grey,
                letterSpacing: 0.6)),
      );

  Widget _buildForm() => Form(
    key: _formKey,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),

          // Header
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: _bg, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.support_agent_rounded,
                  color: _blue, size: 20)),
            const SizedBox(width: 10),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AutoSizeText('Having trouble?',
                    style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w800, color: _dark)),
                AutoSizeText('We\'ll get back to you quickly.',
                    style: TextStyle(fontSize: 12, color: _grey)),
              ],
            )),
            // ── ⚠ THE WAY OUT. Added 10 August 2026. ──────────────────────
            //
            // Reported: "there is no back button to cancel and return back,
            // there is only one way — the user has to complete the form".
            //
            // That reading was right in practice. The sheet is technically
            // dismissible — showModalBottomSheet defaults isDismissible to
            // true, so the barrier and a downward swipe both work — but with
            // isScrollControlled: true and the keyboard up, the sheet fills
            // the screen and there is no barrier left to tap. The only
            // Navigator.pop in the whole file was the Done button AFTER
            // submitting.
            //
            // So the only visible exit was to send a support ticket you did
            // not want to send. A grey 4px drag handle is not an exit anyone
            // reads as one.
            //
            // An explicit X, always visible, above the keyboard.
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: _grey, size: 22),
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Topic chips ────────────────────────────────────────────────
          //
          // A selected chip now FILLS with blue and shows a tick, rather than
          // an 8%-alpha tint with a slightly thicker border. The old pair was
          // nearly indistinguishable at arm's length, so people re-tapped
          // chips unsure whether the first tap registered.
          const Text('What\'s the issue?',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: _grey)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _topics.map((t) {
              final bool sel = _selectedTopic == t['value'];
              return GestureDetector(
                onTap: () => setState(() => _selectedTopic = t['value']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? _blue : _bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? _blue : _border, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sel) ...[
                        const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 5),
                      ],
                      Text(t['label']!,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : _dark)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ── Name + phone ───────────────────────────────────────────────
          //
          // Prefilled from /stay_hosts when signed in. Left EDITABLE on
          // purpose: the number on the account may be the very thing that is
          // wrong ("Wrong phone number used" is one of the topics above), so
          // locking these would block the one enquiry that needs them changed.
          if (_isSignedIn) ...[
            Row(
              children: [
                Icon(_prefilling
                        ? Icons.hourglass_top_rounded
                        : Icons.check_circle_rounded,
                    size: 14,
                    color: _prefilling ? _grey : const Color(0xFF16A34A)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _prefilling
                        ? 'Getting your details…'
                        : 'Filled in from your account. Change them if needed.',
                    style: const TextStyle(fontSize: 11.5, color: _grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          _fieldLabel('YOUR NAME'),
          TextFormField(
            controller: _nameCtrl,
            enabled: !_prefilling,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: _inputDec('Your full name'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Name is required' : null,
          ),
          const SizedBox(height: 14),

          _fieldLabel('PHONE NUMBER'),
          TextFormField(
            controller: _phoneCtrl,
            enabled: !_prefilling,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: _inputDec('e.g. 07400 123456'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Phone number is required' : null,
          ),
          const SizedBox(height: 14),

          // Message
          _fieldLabel('WHAT HAPPENED?'),
          TextFormField(
            controller: _msgCtrl,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: _inputDec(
                'Tell us what went wrong and we will look into it.'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please describe your issue' : null,
          ),
          const SizedBox(height: 20),

          // Submit
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const AutoSizeText('Send Message',
                      style: TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    ),
  );

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFADB5BD)),
    filled: true,
    fillColor: _bg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _blue, width: 1.4)),
    errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red)),
    focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red, width: 1.4)),
  );
}
