// The host's own account.
//
// ── WIRED 8 August 2026. WHAT IT WAS ───────────────────────────────────────
//
// Stitch invented a host called "HostPro", a stock avatar and two empty
// handlers. It read nothing.
//
// ── WHAT A HOST MAY AND MAY NOT CHANGE ─────────────────────────────────────
//
// firestore.rules guards /stay_hosts updates with selfEditAllowed, which
// refuses any write touching driverProtectedFields():
//
//     walletBalance, kycStatus, accountStatus, status, isActive, role,
//     rating, verified, approved, adminManualVerification, overallResult,
//     dobMatch, firstNameMatch, surnameMatch
//
// ⚠ THE RULE FAILS THE WHOLE WRITE, NOT JUST THE BAD FIELD. Including one
// protected key in an otherwise innocent update denies everything in it. That
// is not theoretical — it is exactly the bug on the registration screen, where
// re-submitting sent `status: 'PENDING'` and silently denied every other
// correction the host had made.
//
// So this screen edits a deliberately short, safe list: contact name, email,
// phone. Everything that decides whether a host may trade is read-only here
// and shown as read-only, with a line saying who can change it. A field that
// looks editable and rejects the save is worse than one that never offered.
//
// Business name and company number are also read-only: they are what GoOuts
// verified. Letting a host edit them after approval would leave the record
// saying one thing and the KYC decision resting on another.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import '../../auth/login_screen.dart';
import '../../short_stay/host/host_collection.dart';
import 'host_bottom_nav.dart';
import 'host_routes.dart';
import '../../support/host_support_service.dart';
import 'host_26_notifications_screen.dart';

class HostProfileScreen extends StatefulWidget {
  const HostProfileScreen({super.key});

  @override
  State<HostProfileScreen> createState() => _HostProfileScreenState();
}

class _HostProfileScreenState extends State<HostProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _editing = false;
  bool _saving = false;
  bool _loadedOnce = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(String uid) async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.isEmpty) {
      _say('Enter a contact name.', isError: true);
      return;
    }
    if (email.isNotEmpty && !email.contains('@')) {
      _say('That email address does not look right.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      // ONLY these keys. Adding 'status' or 'kycStatus' here would deny the
      // entire write — see the note at the top of the file.
      await FirebaseFirestore.instance
          .collection(kStayHostsCollection)
          .doc(uid)
          .update(<String, dynamic>{
        'fullName': name,
        'contactPersonName': name,
        'email': email.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      _say('Saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _say('Could not save. $e', isError: true);
    }
  }

  void _say(String m, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: isError ? GoOutsColors.error : GoOutsColors.success,
    ));
  }

  Future<void> _signOut() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your phone number and a new code '
            'to sign back in.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay signed in')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (go != true) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

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
          'Profile',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Not signed in.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(kStayHostsCollection)
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _notice('Could not load your profile.\n'
                      '${snap.error}');
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final d = snap.data!.data() ?? const <String, dynamic>{};

                // Fill the controllers once. Doing it on every snapshot would
                // overwrite what the host is typing the moment anything else
                // on the document changes.
                if (!_loadedOnce) {
                  _loadedOnce = true;
                  _nameCtrl.text =
                      (d['fullName'] ?? d['contactPersonName'] ?? '')
                          .toString();
                  _emailCtrl.text = (d['email'] ?? '').toString();
                }

                return _body(uid, d);
              },
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.profile),
    );
  }

  Widget _body(String uid, Map<String, dynamic> d) {
    // Same three fields, same order of authority, as host_home_screen and
    // requireVerifiedHost on the server. If this list changes, those change.
    final kyc = (d['kycStatus'] ??
            d['businessProfileVerificationStatus'] ??
            d['status'] ??
            'pending')
        .toString()
        .toLowerCase();
    final approved = kyc == 'approved' || kyc == 'verified';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 30,
              backgroundColor: GoOutsColors.tint,
              backgroundImage:
                  (d['selfieUrl'] ?? d['profilePhotoUrl'] ?? '')
                          .toString()
                          .isEmpty
                      ? null
                      : NetworkImage(
                          (d['selfieUrl'] ?? d['profilePhotoUrl']).toString()),
              child: (d['selfieUrl'] ?? d['profilePhotoUrl'] ?? '')
                      .toString()
                      .isEmpty
                  ? const Icon(Icons.person, color: GoOutsColors.primary)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    (d['legalBusinessName'] ?? d['fullName'] ?? 'Host')
                        .toString(),
                    style: GoogleFonts.inter(
                      color: GoOutsColors.navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Icon(
                        approved
                            ? Icons.verified_rounded
                            : Icons.hourglass_top_rounded,
                        size: 15,
                        color: approved
                            ? GoOutsColors.success
                            : GoOutsColors.warning,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        approved ? 'Verified' : 'Verification in progress',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: approved
                              ? GoOutsColors.success
                              : GoOutsColors.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        _section(
          'Your details',
          trailing: _editing
              ? null
              : TextButton(
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('Edit'),
                ),
          children: <Widget>[
            TextField(
              controller: _nameCtrl,
              enabled: _editing,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Contact name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              enabled: _editing,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            if (_editing) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _editing = false;
                                _loadedOnce = false; // reload from the doc
                              }),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(uid),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),

        // ── READ ONLY, AND SAYS WHY ──────────────────────────────────────
        _section('Verified by GoOuts', children: <Widget>[
          _ro('Business name', (d['legalBusinessName'] ?? '').toString()),
          _ro('Company number', (d['companyNumber'] ?? '').toString()),
          _ro('Phone', (d['phoneNumber'] ?? d['phone'] ?? '').toString()),
          _ro('Postcode', (d['postcode'] ?? '').toString()),
          const SizedBox(height: 8),
          Text(
            'These are what GoOuts checked when verifying you, so they cannot '
            'be changed from the app. Contact support if something is wrong.',
            style: GoogleFonts.inter(
                fontSize: 12, color: GoOutsColors.onSurfaceVariant,
                height: 1.45),
          ),
        ]),

        // ── KYC BANNER, MATCHING goouts_app's _buildKycBanner ────────────
        //
        // ADDED 10 August 2026. The host profile listed the verified fields as
        // read-only text but never said what STATE the account was in. The
        // consumer app has a colour-coded banner for exactly this, and profile
        // is where someone goes to answer "am I approved?"
        //
        // Three states, three colours, each with the next action written out —
        // green verified, amber in progress, red not approved. Same three
        // fields and same order of authority as the dashboard hero,
        // host_home_screen, and requireVerifiedHost() on the server.
        _kycBanner(kyc, approved),
        const SizedBox(height: 8),

        // ── PREFERENCES ────────────────────────────────────────────────────
        //
        // The consumer app's Preferences card, ported. Same _sectionCard
        // (white, radius 16, soft shadow), same tune_rounded header, same
        // _menuRow (grey icon 20, title 14/w500, chevron, thin dividers).
        //
        // Pixel-identical rather than merely similar: GoOutsColors.primary is
        // 0xFF0392CA and .navy is 0xFF0D1B3E, the exact values the consumer
        // hardcodes as _primary and _dark.
        //
        // Refer a Friend is the one row deliberately NOT ported. There is no
        // host referral scheme, and a row offering a reward that does not
        // exist is worse than no row.
        _preferencesCard(),

        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: GoOutsColors.error,
            side: const BorderSide(color: GoOutsColors.error),
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ],
    );
  }

  // ── PREFERENCES CARD — ported from goouts_app profile_screen ───────────
  Widget _sectionCard({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );

  Widget _menuRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: GoOutsColors.primary.withValues(alpha: 0.08),
          highlightColor: GoOutsColors.primary.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Row(
              children: <Widget>[
                Icon(icon, color: Colors.grey[500], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: GoOutsColors.navy)),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      );

  /// Red count pill + chevron, the consumer's trailing treatment.
  Widget _countTrailing(int n) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (n > 0)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: GoOutsColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(n > 9 ? '9+' : '$n',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.grey, size: 20),
        ],
      );

  Widget _divider() => Divider(height: 1, color: Colors.grey[100]);

  Widget _preferencesCard() => _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.tune_rounded,
                    color: GoOutsColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Preferences',
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: GoOutsColors.navy)),
              ],
            ),
            const SizedBox(height: 14),

            // Notifications = the FEED, as it means in goouts_app.
            StreamBuilder<int>(
              stream: hostUnreadNotificationsStream(),
              builder: (context, snap) => _menuRow(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                trailing: _countTrailing(snap.data ?? 0),
                onTap: () => Navigator.of(context)
                    .pushNamed(HostRoutes.notificationFeed),
              ),
            ),
            _divider(),

            StreamBuilder<int>(
              stream: HostSupportService().unreadCountStream(),
              builder: (context, snap) => _menuRow(
                icon: Icons.message_outlined,
                title: 'Messages',
                trailing: _countTrailing(snap.data ?? 0),
                onTap: () => Navigator.of(context)
                    .pushNamed(HostRoutes.messageCenter),
              ),
            ),
            _divider(),

            // Not in the consumer's card — hosts need somewhere for the
            // toggles, PIN and legal documents to live.
            _menuRow(
              icon: Icons.settings_outlined,
              title: 'Settings',
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: Colors.grey, size: 20),
              onTap: () =>
                  Navigator.of(context).pushNamed(HostRoutes.settings),
            ),
            _divider(),

            _menuRow(
              icon: Icons.help_outline_rounded,
              title: 'FAQ',
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: Colors.grey, size: 20),
              onTap: () => Navigator.of(context).pushNamed(HostRoutes.help),
            ),
            _divider(),

            // One row, two jobs — if support has replied it opens the
            // conversation, otherwise the form to start one.
            StreamBuilder<int>(
              stream: HostSupportService().unreadCountStream(),
              builder: (context, snap) {
                final unread = snap.data ?? 0;
                return _menuRow(
                  icon: Icons.headset_mic_outlined,
                  title: 'Contact Support',
                  trailing: _countTrailing(unread),
                  onTap: () => Navigator.of(context).pushNamed(
                      unread > 0
                          ? HostRoutes.messageCenter
                          : HostRoutes.contactSupport,
                      arguments: unread > 0 ? 1 : null),
                );
              },
            ),
          ],
        ),
      );

  Widget _section(String title,
          {required List<Widget> children, Widget? trailing}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      color: GoOutsColors.navy,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  Widget _ro(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 4,
              child: Text(k,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: GoOutsColors.body)),
            ),
            Expanded(
              flex: 5,
              child: Text(
                v.isEmpty ? '—' : v,
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GoOutsColors.navy,
                ),
              ),
            ),
          ],
        ),
      );

  /// Verification state, said plainly, with the next step.
  ///
  /// Deliberately NOT a link to re-verify. KYC happens once at registration
  /// and the decision is the admin's or the engine's — offering "verify again"
  /// here would let a host resubmit after approval and desync the record from
  /// the decision that was made on it.
  Widget _kycBanner(String kyc, bool approved) {
    final rejected = kyc == 'rejected';

    final (Color bg, Color line, Color tone, IconData icon, String title,
            String body) =
        switch ((approved, rejected)) {
      (true, _) => (
          const Color(0xFFEDF7F1),
          GoOutsColors.success,
          GoOutsColors.success,
          Icons.verified_user_rounded,
          'You are verified',
          'Your listings can go live and guests can book them.',
        ),
      (_, true) => (
          const Color(0xFFFEF2F2),
          GoOutsColors.error,
          GoOutsColors.error,
          Icons.gpp_bad_outlined,
          'Identity check not approved',
          'We could not verify you from what was submitted. Contact support '
              'and we will tell you exactly what is needed.',
        ),
      _ => (
          const Color(0xFFFFF8E7),
          GoOutsColors.warning,
          GoOutsColors.warning,
          Icons.hourglass_top_rounded,
          'Verification in progress',
          'You can add a property and prepare your listing now. GoOuts must '
              'verify you before guests can see it.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line.withValues(alpha: 0.40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: GoOutsColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: GoOutsColors.body,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                if (rejected) ...<Widget>[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed(HostRoutes.contactSupport),
                    child: Text(
                      'Contact support',
                      style: GoogleFonts.inter(
                        color: GoOutsColors.error,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 13.5, color: GoOutsColors.body, height: 1.5),
          ),
        ),
      );
}
