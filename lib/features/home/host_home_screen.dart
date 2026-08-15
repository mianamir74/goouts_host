import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/goouts_colors.dart';
import '../auth/host_sign_out.dart';
import '../short_stay/host/host_routes.dart';

/// Landing screen for a signed-in host, shown before the dashboard.
import '../short_stay/host/host_collection.dart';
///
/// It exists as a separate screen from HostDashboardScreen for one reason:
/// KYC state. createStayListing rejects any host whose /businesses record is
/// not approved, so a host who cannot yet list needs to be told so HERE —
/// not after filling in an eight-screen listing wizard.
///
/// The Stitch dashboard has no concept of verification status, and giving it
/// one means rebuilding it properly rather than editing placeholder copy. So
/// this stays as the entry point until the dashboard is genuinely wired.
class HostHomeScreen extends StatelessWidget {
  const HostHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GoOuts Host'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            // One shared helper — see features/auth/host_sign_out.dart.
            onPressed: () => hostSignOut(context),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Not signed in.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(kStayHostsCollection)
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final Map<String, dynamic> data = snapshot.data?.data() ?? {};

                // THREE field names are checked, because three different
                // parts of the estate write verification to three different
                // places:
                //
                //   kycStatus                            server / newer code
                //   businessProfileVerificationStatus    driver_app
                //   status                               the ADMIN PANEL
                //
                // The third was added 8 August 2026 after a host was
                // approved in the admin panel and still saw "Verification in
                // progress" on their phone. The admin panel's Approve button
                // wrote only `status: 'APPROVED'`, which nothing read. The
                // panel now writes all three, but this fallback stays: any
                // record approved BEFORE that fix has only `status`, and
                // without this line those hosts would stay locked out
                // forever with no way to tell why.
                //
                // Read in order of authority — kycStatus is the field the
                // server trusts, so it wins if present.
                final String kyc = (data['kycStatus'] ??
                        data['businessProfileVerificationStatus'] ??
                        data['status'] ??
                        'pending')
                    .toString()
                    .toLowerCase();

                final bool approved = kyc == 'approved' || kyc == 'verified';
                final String name =
                    (data['businessName'] ?? data['name'] ?? 'Host').toString();

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    Text(
                      'Welcome back, $name',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: GoOutsColors.navy,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _KycCard(approved: approved, status: kyc),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context)
                          .pushNamed(HostRoutes.dashboard),
                      icon: const Icon(Icons.dashboard_outlined),
                      label: const Text('Open host dashboard'),
                    ),
                    const SizedBox(height: 10),
                    // Deliberately worded as a warning rather than a feature
                    // list. The 25 screens behind this button render Stitch
                    // placeholder copy — real-looking names, dates and money
                    // that are not real. Anyone opening them should know that
                    // before they read a number off one.
                    const Text(
                      'The dashboard screens are still placeholders. Figures '
                      'and bookings shown there are sample data, not your '
                      'account.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _KycCard extends StatelessWidget {
  const _KycCard({required this.approved, required this.status});

  final bool approved;
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color tint = approved
        ? const Color(0xFF1B8A5A)
        : (status == 'rejected'
            ? const Color(0xFFB3261E)
            : const Color(0xFFB26A00));

    final String headline = approved
        ? 'Verified — you can publish listings'
        : (status == 'rejected'
            ? 'Verification was not approved'
            : 'Verification in progress');

    final String detail = approved
        ? 'Your identity and business details have been checked.'
        : (status == 'rejected'
            ? 'Please contact support so we can tell you what was missing.'
            : 'We are reviewing your documents. You can look around in the '
                'meantime, but listings cannot be published until this '
                'finishes.');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            approved
                ? Icons.verified_rounded
                : (status == 'rejected'
                    ? Icons.error_outline_rounded
                    : Icons.hourglass_top_rounded),
            color: tint,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
