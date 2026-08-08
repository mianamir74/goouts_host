// One property, as the host's own record of it.
//
// ── WIRED 8 August 2026. WHAT IT WAS ───────────────────────────────────────
//
// A Stitch export with an invented property, a stock photograph and two empty
// handlers. It read nothing.
//
// ── IT TAKES AN ID, NOT AN OBJECT ──────────────────────────────────────────
//
// `arguments` is the listing id string, passed from screen 10. Passing the
// whole listing map instead is tempting and wrong: a route argument holding an
// object breaks deep links, breaks state restoration after iOS kills the app
// in the background, and is a known cause of null crashes on resume. This app
// has been killed for memory before.
//
// ── WHY IT IS "YOUR PROPERTY", NOT "PREVIEW AS A GUEST" ────────────────────
//
// Stitch titled it Review Listing and implied a guest-eye view. It cannot
// honestly be that: the guest-facing listing page shows availability, reviews
// and a booking widget, and those are guest-side screens that do not exist
// yet. Dressing this up as a guest preview would show a host something a guest
// will never see and let them sign off on a layout that is not real.
//
// So it is what it can truthfully be: everything stored about the property,
// including the compliance statements, which a host has no other way to read
// back after they have agreed to them.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import '../models/money.dart';

class ListingPreviewScreen extends StatelessWidget {
  const ListingPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final arg = ModalRoute.of(context)?.settings.arguments;
    final id = arg is String ? arg : '';

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
          'Your property',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: id.isEmpty
          // Reachable if the route is opened without an argument — a deep link,
          // or a restored route. Says so rather than showing an empty shell.
          ? _notice('No property was selected. Go back and choose one from '
              'My properties.')
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('stay_listings')
                  .doc(id)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _notice('Could not load this property.\n'
                      '${snap.error}');
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.data!.exists) {
                  return _notice('This property no longer exists.');
                }
                return _body(context, snap.data!.data()!);
              },
            ),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> m) {
    final photos = (m['photos'] as List?) ?? const <dynamic>[];
    final addr = (m['address'] as Map?) ?? const <String, dynamic>{};
    final comp = (m['compliance'] as Map?) ?? const <String, dynamic>{};
    final loc = m['locationContext'] as Map?;
    final amenities = ((m['amenities'] as List?) ?? const <dynamic>[])
        .map((e) => e.toString())
        .toList();
    final rooms = ((m['captureRooms'] as List?) ?? const <dynamic>[])
        .map((e) => e.toString())
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        if (photos.isNotEmpty)
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  ((photos[i] as Map?)?['url'] ?? '').toString(),
                  width: 260,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 260,
                    color: GoOutsColors.surface,
                    child: const Icon(Icons.broken_image_outlined,
                        color: GoOutsColors.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          )
        else
          _section('Photographs', <Widget>[
            Text(
              'None uploaded. GoOuts will not approve a property without any.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: GoOutsColors.warning, height: 1.4),
            ),
          ]),
        const SizedBox(height: 18),
        Text(
          (m['title'] ?? 'Untitled property').toString(),
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${addr['line1'] ?? ''}, ${addr['town'] ?? ''} '
          '${addr['postcode'] ?? ''}',
          style: GoogleFonts.inter(color: GoOutsColors.body, fontSize: 13.5),
        ),
        const SizedBox(height: 18),
        _section('The basics', <Widget>[
          _row('Type', (m['propertyType'] ?? '').toString()),
          _row('Bedrooms', '${m['bedrooms'] ?? 0}'),
          _row('Beds', '${m['beds'] ?? 0}'),
          _row('Bathrooms', '${m['bathrooms'] ?? 0}'),
          _row('Maximum guests', '${m['maxGuests'] ?? 0}'),
        ]),
        _section('Price', <Widget>[
          _row('Nightly rate', Pence.fromFirestore(m['nightlyRate']).formatted),
          _row('Cleaning fee',
              Pence.fromFirestore(m['cleaningFee']).formatted),
          _row('Cancellation', (m['cancellationPolicy'] ?? '').toString()),
          _row(
              'Bookings',
              (m['bookingMode'] ?? '') == 'instant'
                  ? 'Guests book instantly'
                  : 'You approve each request'),
        ]),
        if ((m['description'] ?? '').toString().trim().isNotEmpty)
          _section('Description', <Widget>[
            Text(
              m['description'].toString(),
              style: GoogleFonts.inter(
                  fontSize: 13.5, color: GoOutsColors.body, height: 1.55),
            ),
          ]),
        if (amenities.isNotEmpty)
          _section('Amenities', <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: amenities
                  .map((a) => Chip(
                        label: Text(_pretty(a)),
                        labelStyle: GoogleFonts.inter(
                            fontSize: 12.5, color: GoOutsColors.navy),
                        backgroundColor: GoOutsColors.background,
                        side: const BorderSide(color: GoOutsColors.border),
                      ))
                  .toList(),
            ),
          ]),
        if (loc != null)
          _section('What is nearby', <Widget>[
            _row('GoOuts partners within half a mile',
                '${((loc['partnerCounts'] as Map?)?['halfMile']) ?? 0}'),
            _row('Within a mile',
                '${((loc['partnerCounts'] as Map?)?['oneMile']) ?? 0}'),
            if ((loc['centreName'] ?? '').toString().isNotEmpty)
              _row('Nearest centre', loc['centreName'].toString()),
          ]),
        // ── THE PART A HOST CANNOT SEE ANYWHERE ELSE ──────────────────────
        //
        // Three legal statements they made on step 7, timestamped on the
        // server. They should be able to read back what they agreed to.
        _section('What you confirmed', <Widget>[
          _tick('You have permission to let this property',
              comp['mortgagePermit'] == true),
          _tick('You have met your fire and gas safety duties',
              comp['safetyDuty'] == true),
          _tick('You are aware of local limits on letting nights',
              comp['nightLimitAwareness'] == true),
          if ((comp['registrationNumber'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            _row('Registration number', comp['registrationNumber'].toString()),
          ],
        ]),
        // captureRooms is set by the SERVER from the room counts and cannot be
        // shortened by the host — a host who could choose it might leave out
        // the room they intend to claim for. Shown so it is not a surprise.
        if (rooms.isNotEmpty)
          _section('Rooms a guest must photograph on arrival', <Widget>[
            Text(
              rooms.map(_pretty).join(', '),
              style: GoogleFonts.inter(
                  fontSize: 13.5, color: GoOutsColors.body, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              'Set by GoOuts from the size of the property. This is the '
              'evidence pack a damage claim would rest on.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: GoOutsColors.onSurfaceVariant),
            ),
          ]),
      ],
    );
  }

  /// 'free_parking' -> 'Free parking'. Amenities are stored as slugs so a
  /// label rewrite cannot silently break search filters.
  static String _pretty(String slug) {
    if (slug.isEmpty) return slug;
    final words = slug.replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }

  Widget _section(String title, List<Widget> children) => Container(
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
            Text(
              title,
              style: GoogleFonts.inter(
                color: GoOutsColors.navy,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Text(k,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: GoOutsColors.body)),
            ),
            Expanded(
              flex: 4,
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

  Widget _tick(String label, bool on) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              on ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18,
              color: on ? GoOutsColors.success : GoOutsColors.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                    fontSize: 13, color: GoOutsColors.body, height: 1.4),
              ),
            ),
          ],
        ),
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
