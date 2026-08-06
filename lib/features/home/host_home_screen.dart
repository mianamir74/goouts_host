import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_screen.dart';

/// Landing screen for a signed-in host.
///
/// PLACEHOLDER. The real dashboard is one of the 25 Stitch screens currently
/// sitting in goouts_app/lib/features/short_stay/host/ and will replace the
/// body of this file when they move across.
///
/// It is not a blank stub, though, because it has one job worth doing properly
/// now: showing the host where their KYC stands. createStayListing rejects any
/// host whose /businesses record is not approved, so a host who cannot yet
/// list needs to be told that here rather than discovering it at the end of an
/// eight-screen listing wizard.
class HostHomeScreen extends StatelessWidget {
  const HostHomeScreen({super.key});

  static const Color _navy = Color(0xFF0D1B3E);

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
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Not signed in.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('businesses')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final Map<String, dynamic> data = snapshot.data?.data() ?? {};

                // Two field names are checked because the two are not yet
                // consistent across the estate: driver_app writes
                // businessProfileVerificationStatus, the newer server code
                // reads kycStatus. requireVerifiedHost() in stay_host.js
                // accepts either, so this must too — otherwise a host the
                // server considers approved would be told they are pending.
                final String kyc = (data['kycStatus'] ??
                        data['businessProfileVerificationStatus'] ??
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
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _KycCard(approved: approved, status: kyc),
                    const SizedBox(height: 28),
                    const Text(
                      'Your dashboard is being built',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Listings, bookings, your calendar and earnings will '
                      'appear here.',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
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
