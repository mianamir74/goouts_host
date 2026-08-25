// ─────────────────────────────────────────────────────────────────────────────
//  Your damage claims.
//
//  Rewritten 25 August 2026. Was Stitch output from 4 August, never wired —
//  unreachable, with placeholder figures and an empty handler.
//
//  ── ⚠ IT SHOWS WHAT IS TRUE, INCLUDING WHEN THAT IS UNCOMFORTABLE ───────────
//
//  A claims list is a screen a host opens wanting good news. The temptation is
//  to phrase everything as progress — "in review", "being processed" — and
//  never quite say that nothing is coming.
//
//  So the wording here is deliberate:
//
//    NO PROVIDER IS CONNECTED. depositPreAuth.status is "none" on every booking
//    and no deposit is held anywhere. An upheld claim says the amount was
//    AWARDED and that settlement follows. It does not say the money is on its
//    way, because it is not, and a host told otherwise will chase it and be
//    right to.
//
//    A DISPUTE IS NOT A SETBACK AND IS NOT SHOWN AS ONE. The guest exercising
//    their reply is the process working. Colouring it red would teach hosts to
//    read a normal step as a problem with the guest.
//
//    "NOT UPHELD" IS SAID PLAINLY. Not "closed", not "resolved". A host whose
//    claim failed needs to know it failed and why — the reason an admin typed
//    is shown here, not summarised away.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_claims_service.dart';

class ClaimStatusScreen extends StatelessWidget {
  const ClaimStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GoOutsColors.background,
      appBar: AppBar(
        backgroundColor: GoOutsColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GoOutsColors.navy),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Damage claims',
            style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: GoOutsColors.navy)),
      ),
      body: StreamBuilder<List<StayClaim>>(
        stream: HostClaimsService.instance.watchMyClaims(),
        builder: (BuildContext c, AsyncSnapshot<List<StayClaim>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // ⚠ AN ERROR IS NOT AN EMPTY LIST. Showing "no claims" when the query
          // failed tells a host their claim vanished. The most likely cause is
          // a missing composite index on (hostUid, openedAt) — which is exactly
          // the sort of thing that only appears in production.
          if (snap.hasError) {
            return _message(
                Icons.wifi_off_rounded,
                'We could not load your claims just now.\n\n'
                'Nothing has been lost — please try again in a moment.');
          }
          final List<StayClaim> claims = snap.data ?? const <StayClaim>[];
          if (claims.isEmpty) {
            return _message(
                Icons.verified_outlined,
                'No damage claims.\n\n'
                'You can report damage from a booking within 72 hours of your '
                'guest checking out.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            itemCount: claims.length,
            separatorBuilder: (BuildContext ctx, int index) => const SizedBox(height: 12),
            itemBuilder: (BuildContext c, int i) => _card(claims[i]),
          );
        },
      ),
    );
  }

  Widget _message(IconData icon, String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 52, color: GoOutsColors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.55,
                      color: GoOutsColors.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _card(StayClaim c) {
    final (String label, Color colour, String meaning) = _describe(c);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GoOutsColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('£${c.amount.toStringAsFixed(2)} claimed',
                    style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: GoOutsColors.navy)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: colour)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(meaning,
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.45,
                  color: GoOutsColors.onSurfaceVariant)),
          if (c.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(c.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 13, height: 1.45, color: GoOutsColors.body)),
          ],
          // The guest's own words, shown to the host. They are going to be part
          // of the decision, and a host who never sees them cannot answer them.
          if ((c.guestResponseNote ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GoOutsColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('What your guest said',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GoOutsColors.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(c.guestResponseNote!,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.45,
                          color: GoOutsColors.body)),
                ],
              ),
            ),
          ],
          if ((c.decisionReason ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text('Reason: ${c.decisionReason}',
                style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    color: GoOutsColors.onSurfaceVariant)),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(Icons.photo_library_outlined,
                  size: 15, color: GoOutsColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '${c.evidenceCount} guest '
                '${c.evidenceCount == 1 ? 'photo' : 'photos'} attached',
                style: GoogleFonts.inter(
                    fontSize: 11.5, color: GoOutsColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ⚠ THE THIRD STRING IS THE ONE THAT MATTERS. A badge saying "Awarded" with
  /// nothing beside it reads as "paid". The sentence is what stops a host
  /// waiting for money that no provider exists to send yet.
  (String, Color, String) _describe(StayClaim c) {
    switch (c.status) {
      case ClaimStatus.awaitingGuest:
        return (
          'With your guest',
          GoOutsColors.warning,
          'Your guest has 72 hours to respond. We will tell you either way.'
        );
      case ClaimStatus.accepted:
        return (
          'Accepted',
          GoOutsColors.success,
          'Your guest agreed. GoOuts reviews it before anything is settled.'
        );
      case ClaimStatus.disputed:
        return (
          'Disputed',
          GoOutsColors.navy,
          'Your guest disagrees, which is their right. A person at GoOuts will '
              'read both sides and decide.'
        );
      case ClaimStatus.decided:
        if (c.decision == 'rejected' || c.awardedPence == 0) {
          return (
            'Not upheld',
            GoOutsColors.onSurfaceVariant,
            'This claim was not upheld and nothing is owed.'
          );
        }
        return (
          'Awarded',
          GoOutsColors.success,
          // ⚠ THE HONEST SENTENCE. No payment provider is connected and no
          // deposit is held. "Awarded" is true; "on its way" would not be.
          '£${c.awarded.toStringAsFixed(2)} was awarded. Settlement follows '
              'once card payments are live — we will confirm it.'
        );
      case ClaimStatus.unknown:
        return (
          'In progress',
          GoOutsColors.onSurfaceVariant,
          'We will update this shortly.'
        );
    }
  }
}
