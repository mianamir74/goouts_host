// What a host wants to be told about.
//
// ── WIRED 8 August 2026. WHAT IT WAS ───────────────────────────────────────
//
// Stitch drew the switches and they flipped, which made it look like the most
// working screen in the app. Nothing was read and nothing was saved: reopening
// the screen put every switch back to its hardcoded default.
//
// ── STORED ON /stay_hosts, AND ALLOWED TO BE ───────────────────────────────
//
// Under a `notificationPrefs` map. None of those keys appear in
// driverProtectedFields(), so selfEditAllowed permits the host to write them.
// Checked rather than assumed — a self-write touching a protected key denies
// the ENTIRE update, silently, which is the bug still open on the registration
// screen.
//
// ⚠ THESE PREFERENCES ARE RECORDED, NOT YET OBEYED.
//
// GoOuts Host sends no notifications of its own. It has the APNs entitlement
// only because Firebase Phone Auth needs a silent push to verify the app, and
// firebase_messaging is not even a dependency. Nothing reads this map yet.
//
// Saying so on the screen is not optional. A host who turns OFF "booking
// requests" and believes it would be right to think they had been told to
// expect silence — and a host who leaves everything ON expects alerts that
// will never come, and blames GoOuts for a missed booking. The switches are
// honest about being a preference for later.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import '../../short_stay/host/host_collection.dart';
import 'host_bottom_nav.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  /// key -> (label, description, default)
  static const Map<String, List<String>> _prefs = <String, List<String>>{
    'bookingRequests': <String>[
      'Booking requests',
      'When a guest asks to stay.',
    ],
    'bookingChanges': <String>[
      'Changes and cancellations',
      'When a confirmed booking is cancelled or altered.',
    ],
    'arrivals': <String>[
      'Arrivals and departures',
      'A reminder the day before a guest arrives or leaves.',
    ],
    'listingStatus': <String>[
      'Property approvals',
      'When GoOuts approves, suspends or returns a property.',
    ],
    'claims': <String>[
      'Damage claims',
      'Updates on a claim you have made.',
    ],
    'payouts': <String>[
      'Payouts',
      'When money is on its way to you.',
    ],
    'marketing': <String>[
      'News from GoOuts',
      'Occasional updates about the platform. Off by default.',
    ],
  };

  static const Set<String> _defaultOff = <String>{'marketing'};

  Map<String, bool> _values = <String, bool>{};
  bool _loadedOnce = false;
  bool _saving = false;

  Future<void> _toggle(String uid, String key, bool on) async {
    // Optimistic: flip immediately, revert if the write is refused. A switch
    // that waits on a round trip before moving feels broken on a poor
    // connection, and this app's audience is not forgiving of that.
    final previous = _values[key] ?? false;
    setState(() {
      _values[key] = on;
      _saving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection(kStayHostsCollection)
          .doc(uid)
          .set(<String, dynamic>{
        'notificationPrefs': <String, dynamic>{key: on},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _values[key] = previous;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save that. $e'),
        backgroundColor: GoOutsColors.error,
      ));
    }
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
          'Notifications',
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
                  return _notice('Could not load your settings.\n'
                      '${snap.error}');
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!_loadedOnce) {
                  _loadedOnce = true;
                  final saved = (snap.data!.data()?['notificationPrefs']
                          as Map?) ??
                      const <String, dynamic>{};
                  _values = <String, bool>{
                    for (final k in _prefs.keys)
                      k: saved[k] is bool
                          ? saved[k] as bool
                          : !_defaultOff.contains(k),
                  };
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: <Widget>[
                    // ── THE HONEST BIT ────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: GoOutsColors.warning.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                GoOutsColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(Icons.info_outline_rounded,
                              size: 18, color: GoOutsColors.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'GoOuts Host does not send notifications yet. '
                              'Your choices here are saved and will be used '
                              'when it does — but for now, check the app for '
                              'new booking requests rather than waiting to be '
                              'told.',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: GoOutsColors.body,
                                  height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(
                        color: GoOutsColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: GoOutsColors.border),
                      ),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < _prefs.length; i++) ...<Widget>[
                            _switchTile(uid, _prefs.keys.elementAt(i)),
                            if (i != _prefs.length - 1)
                              const Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: GoOutsColors.background),
                          ],
                        ],
                      ),
                    ),
                    if (_saving) ...<Widget>[
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text('Saving…',
                              style: GoogleFonts.inter(
                                  fontSize: 12.5, color: GoOutsColors.body)),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.profile),
    );
  }

  Widget _switchTile(String uid, String key) {
    final meta = _prefs[key]!;
    return SwitchListTile(
      value: _values[key] ?? false,
      onChanged: (v) => _toggle(uid, key, v),
      activeThumbColor: GoOutsColors.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        meta[0],
        style: GoogleFonts.inter(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: GoOutsColors.navy,
        ),
      ),
      subtitle: Text(
        meta[1],
        style: GoogleFonts.inter(
            fontSize: 12.5, color: GoOutsColors.body, height: 1.35),
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
