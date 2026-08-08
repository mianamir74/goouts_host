// The host's own properties.
//
// ── WIRED 8 August 2026. WHAT IT WAS ───────────────────────────────────────
//
// Hardcoded. Line 64 of the Stitch export was `title: 'The Shoreditch Loft'`,
// with two more invented properties beside it and zero Firestore reads.
//
// This is the screen a host opens straight after creating a property. It
// showed them a flat that does not exist and did not show them theirs — while
// the dashboard one tap away counted their real listings correctly. Two
// screens contradicting each other in front of the user is worse than either
// being wrong alone, because now neither can be trusted.
//
// ── THE QUERY IS THE SAME ONE THE DASHBOARD ALREADY USES ───────────────────
//
// stay_listings where hostUid == me. Single field, so no composite index is
// needed — unlike listHostBookingRequests, whose missing index took down the
// dashboard today.
//
// It is rule-safe: firestore.rules allows a listing to be read by its owner,
// and every document this returns is owned by the caller.
//
// ⚠ NO orderBy. Adding one would turn this into hostUid + orderBy, which DOES
// need a composite index — and the failure mode is the whole screen erroring,
// exactly like the dashboard did. Sorted in Dart instead, on a list that is
// never going to be long enough for it to matter.
//
// ── STATUS IS TRANSLATED, NOT SHOWN RAW ────────────────────────────────────
//
// The stored value is 'draft'. To a host, "Draft" means something they have
// not finished. It actually means finished and waiting for GoOuts to approve
// it — a completely different thing, and the difference decides whether they
// sit waiting or go looking for a Submit button that does not exist.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import '../models/money.dart';
import 'host_bottom_nav.dart';
import 'host_routes.dart';

class MyListingsScreen extends StatelessWidget {
  const MyListingsScreen({super.key});

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
          'My properties',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add a property',
            icon: const Icon(Icons.add_home_outlined,
                color: GoOutsColors.primary),
            onPressed: () =>
                Navigator.of(context).pushNamed(HostRoutes.newAddress),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: uid == null
          ? _notice('You are not signed in.', GoOutsColors.error,
              Icons.error_outline_rounded)
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('stay_listings')
                  .where('hostUid', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                // Shown, never swallowed. A read failure rendered as "no
                // properties" would tell a host their listing had vanished.
                if (snap.hasError) {
                  return _notice(
                    'Could not load your properties.\n${snap.error}',
                    GoOutsColors.error,
                    Icons.error_outline_rounded,
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs.toList()
                  // Newest first. Done here rather than with orderBy — see the
                  // note at the top of the file.
                  ..sort((a, b) {
                    final ta = a.data()['createdAt'];
                    final tb = b.data()['createdAt'];
                    if (ta is Timestamp && tb is Timestamp) {
                      return tb.compareTo(ta);
                    }
                    return 0;
                  });

                if (docs.isEmpty) {
                  return _empty(context);
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _card(context, docs[i].id, docs[i].data()),
                );
              },
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.listings),
    );
  }

  Widget _card(BuildContext context, String id, Map<String, dynamic> m) {
    final status = (m['status'] ?? 'draft').toString();
    final title = (m['title'] ?? 'Untitled property').toString();
    final addr = (m['address'] as Map?) ?? const <String, dynamic>{};
    final photos = (m['photos'] as List?) ?? const <dynamic>[];
    final rate = Pence.fromFirestore(m['nightlyRate']);
    final loc = m['locationContext'] as Map?;

    final cover = photos.isEmpty
        ? null
        : ((photos.first as Map?)?['url'] ?? '').toString();

    // 'draft' does NOT mean unfinished. See the note at the top.
    final (String label, String meaning, Color colour) = switch (status) {
      'live' => (
          'LIVE',
          'Guests can find and book this.',
          GoOutsColors.live
        ),
      'suspended' => (
          'SUSPENDED',
          'Taken down by GoOuts. Contact support.',
          GoOutsColors.warning
        ),
      _ => (
          'BEING REVIEWED',
          'Submitted. GoOuts checks every property before guests see it. '
              'Nothing more for you to do.',
          GoOutsColors.paused
        ),
    };

    return Container(
      decoration: BoxDecoration(
        color: GoOutsColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GoOutsColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (cover != null && cover.isNotEmpty)
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: GoOutsColors.background,
                  child: const Icon(Icons.broken_image_outlined,
                      color: GoOutsColors.onSurfaceVariant),
                ),
              ),
            )
          else
            Container(
              height: 96,
              width: double.infinity,
              color: GoOutsColors.background,
              child: const Center(
                child: Icon(Icons.image_not_supported_rounded,
                    color: GoOutsColors.onSurfaceVariant),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: GoOutsColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _chip(label, colour),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${addr['line1'] ?? ''}, ${addr['town'] ?? ''} '
                  '${addr['postcode'] ?? ''}',
                  style: GoogleFonts.inter(
                      color: GoOutsColors.body, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                Text(
                  '${rate.compact} a night',
                  style: GoogleFonts.inter(
                    color: GoOutsColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    meaning,
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: GoOutsColors.body,
                        height: 1.4),
                  ),
                ),
                if (photos.isEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'No photographs. GoOuts will not approve a property '
                    'without any.',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: GoOutsColors.warning),
                  ),
                ],
                // Only shown once the server has resolved it. Absent on a
                // brand-new listing because enrichListingLocation runs on
                // write and takes a moment — saying nothing is better than
                // saying "0 partners nearby" about a property in Soho.
                if (loc != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.storefront_rounded,
                          size: 15, color: GoOutsColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${((loc['partnerCounts'] as Map?)?['halfMile']) ?? 0}'
                          ' GoOuts partners within half a mile',
                          style: GoogleFonts.inter(
                              fontSize: 12.5, color: GoOutsColors.primary),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        // PASS THE ID, NEVER THE OBJECT. A route argument
                        // holding a whole listing breaks deep links and
                        // breaks state restoration after iOS kills the app.
                        onPressed: () => Navigator.of(context).pushNamed(
                          HostRoutes.listingPreview,
                          arguments: id,
                        ),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Preview'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed(
                          HostRoutes.calendar,
                          arguments: id,
                        ),
                        icon: const Icon(Icons.calendar_month_outlined,
                            size: 18),
                        label: const Text('Calendar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.holiday_village_outlined,
                  size: 44, color: GoOutsColors.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(
                'No properties yet',
                style: GoogleFonts.inter(
                  color: GoOutsColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your first property and GoOuts will review it before '
                'guests can see it.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13.5, color: GoOutsColors.body, height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(HostRoutes.newAddress),
                icon: const Icon(Icons.add),
                label: const Text('Add a property'),
              ),
            ],
          ),
        ),
      );

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
              fontSize: 9.5, fontWeight: FontWeight.w800, color: c),
        ),
      );

  Widget _notice(String text, Color colour, IconData icon) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 36, color: colour),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13.5, color: GoOutsColors.body, height: 1.5),
              ),
            ],
          ),
        ),
      );
}
