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
import '../../auth/widgets/pre_auth_support_sheet.dart';
import '../../short_stay/host/host_collection.dart';
import 'host_bottom_nav.dart';
import 'host_routes.dart';

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

        _section('Account', children: <Widget>[
          _tile(Icons.notifications_none_rounded, 'Notifications',
              () => Navigator.of(context)
                  .pushNamed(HostRoutes.notifications)),
          _tile(Icons.help_outline_rounded, 'Help centre',
              () => Navigator.of(context).pushNamed(HostRoutes.help)),
          _tile(Icons.headset_mic_outlined, 'Contact support',
              () => showPreAuthSupportSheet(context,
                  accountType: 'business')),
        ]),

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

  Widget _tile(IconData icon, String label, VoidCallback onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: GoOutsColors.primary),
        title: Text(label,
            style: GoogleFonts.inter(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: GoOutsColors.navy)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: GoOutsColors.onSurfaceVariant),
        onTap: onTap,
      );

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
