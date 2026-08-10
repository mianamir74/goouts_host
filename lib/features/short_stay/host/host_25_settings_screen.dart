// Settings.
//
// ── WHY THIS SCREEN EXISTS ───────────────────────────────────────────────
//
// 10 August 2026. The profile had grown a shape no other app uses:
//
//   Security   →  Change PIN
//   Account    →  Notifications, Messages, FAQ, Contact Support
//
// "Notifications" sat next to "FAQ" as though they were the same kind of
// thing. They are not. Notifications is a PREFERENCE — something you set once
// and forget. FAQ and Contact Support are things you DO when you have a
// problem. Every mainstream app separates those, and a host looking for
// notification toggles reasonably expects Settings, not a menu that also
// contains a help centre.
//
// The standard shape, which this now follows:
//
//   Settings  →  Notifications          preferences
//                Change PIN             security
//                Terms, Privacy         legal
//                App version            about
//                Sign out / Delete      account lifecycle
//
//   Profile   →  Settings, Messages, FAQ, Contact Support
//
// Security stopped being its own one-row section on the profile. A section
// heading above a single row is noise, and Change PIN belongs with the other
// things you set rather than the things you read.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_routes.dart';

class HostSettingsScreen extends StatefulWidget {
  const HostSettingsScreen({super.key});

  @override
  State<HostSettingsScreen> createState() => _HostSettingsScreenState();
}

class _HostSettingsScreenState extends State<HostSettingsScreen> {
  // ── NO "APP VERSION" ROW, ON PURPOSE ───────────────────────────────────
  //
  // Reading the real build number needs package_info_plus, which this app does
  // NOT depend on. Adding a plugin to a build that is about to go to
  // TestFlight is not worth one informational row, especially after a run of
  // native-side launch crashes.
  //
  // The alternative — a hardcoded version string — is worse than nothing: it
  // goes stale silently, and then a host tells support they are on build 8
  // when they are on 11 and the whole diagnosis starts from the wrong place.
  //
  // Add package_info_plus in a quiet build and this row can come back.

  // ── Legal ────────────────────────────────────────────────────────────────
  //
  // Read from content_pages, the same collection the signup screen uses, so
  // legal text is edited in ONE place — the admin panel — and every screen
  // that shows it is right the moment it is saved. A second copy pasted into
  // Dart would be a second copy to keep lawful.
  Future<void> _showLegal(String docId, String fallbackTitle) async {
    String title = fallbackTitle;
    String body = '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('content_pages')
          .doc(docId)
          .get();
      final d = snap.data() ?? const <String, dynamic>{};
      // The admin panel writes ONE field, 'content'. Checked, not
      // guessed — see _ContentPageEditor._save.
      title = fallbackTitle;
      body = (d['content'] ?? '').toString();
    } catch (_) {
      // fall through to the empty state below
    }
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: GoOutsColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: GoOutsColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(title,
                          style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: GoOutsColors.navy)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: <Widget>[
                    Text(
                      body.trim().isEmpty
                          ? 'This document is not available offline. Please '
                              'check your connection, or contact support and '
                              'we will send it to you.'
                          : body,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          color: GoOutsColors.body,
                          height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Delete account ───────────────────────────────────────────────────────
  //
  // Raises a support ticket rather than deleting anything.
  //
  // A host is a party to bookings. Deleting the record while a guest holds a
  // confirmed stay would break that guest's trip and destroy the evidence
  // photos behind any dispute. UK record-keeping obligations also outlive the
  // account. So the honest control is "ask us to close it", reviewed by a
  // person — not a button that pretends to erase everything instantly.
  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Close your host account?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Text(
          'We will raise this with our team. Any confirmed bookings must be '
          'seen through or cancelled first, and we have to keep some records '
          'for a period afterwards by law. Someone will be in touch to '
          'explain what happens next.',
          style: GoogleFonts.inter(fontSize: 13.5, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep my account')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GoOutsColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Request closure'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context)
        .pushNamed(HostRoutes.contactSupport);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      backgroundColor: GoOutsColors.background,
      appBar: AppBar(
        backgroundColor: GoOutsColors.surface,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GoOutsColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings',
            style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          _group('Preferences', <Widget>[
            // "Notification preferences", not "Notifications".
            //
            // Notifications now means the FEED, on the profile and behind the
            // bell — same as goouts_app. Two rows called the same word, one
            // showing messages and one showing switches, is how a host taps
            // the wrong one twice and gives up.
            _row(
              Icons.tune_rounded,
              'Notification preferences',
              'Choose what GoOuts tells you about',
              () => Navigator.of(context).pushNamed(HostRoutes.notifications),
            ),
          ]),

          _group('Security', <Widget>[
            _row(
              Icons.lock_reset_rounded,
              'Change PIN',
              'The 4 digits you sign in with',
              () => Navigator.of(context).pushNamed(HostRoutes.changePin),
            ),
          ]),

          _group('Legal', <Widget>[
            _row(
              Icons.description_outlined,
              'Terms & Conditions',
              null,
              () => _showLegal('terms_conditions', 'Terms & Conditions'),
            ),
            _row(
              Icons.privacy_tip_outlined,
              'Privacy Policy',
              null,
              () => _showLegal('privacy_policy', 'Privacy Policy'),
            ),
            // The admin panel maintains three pages, not two. Leaving this one
            // out would mean an admin edits it and nobody can ever read it.
            _row(
              Icons.cookie_outlined,
              'Cookies Policy',
              null,
              () => _showLegal('cookies_policy', 'Cookies Policy'),
            ),
          ]),


          if (signedIn)
            _group('Account', <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.no_accounts_outlined,
                    size: 20, color: GoOutsColors.error),
                title: Text('Close my account',
                    style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: GoOutsColors.error)),
                subtitle: Text('Reviewed by our team before anything happens',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: GoOutsColors.onSurfaceVariant)),
                trailing: const Icon(Icons.chevron_right_rounded,
                    size: 20, color: GoOutsColors.onSurfaceVariant),
                onTap: _requestDeletion,
              ),
            ]),
        ],
      ),
    );
  }

  Widget _group(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        decoration: BoxDecoration(
          color: GoOutsColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title.toUpperCase(),
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: GoOutsColors.onSurfaceVariant)),
            ...children,
          ],
        ),
      );

  Widget _row(IconData icon, String label, String? sub, VoidCallback onTap) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20, color: GoOutsColors.onSurfaceVariant),
        title: Text(label,
            style: GoogleFonts.inter(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: GoOutsColors.navy)),
        subtitle: sub == null
            ? null
            : Text(sub,
                style: GoogleFonts.inter(
                    fontSize: 12, color: GoOutsColors.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right_rounded,
            size: 20, color: GoOutsColors.onSurfaceVariant),
        onTap: onTap,
      );
}
