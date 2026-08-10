// Availability calendar — block and unblock nights.
//
// ── WIRED 8 August 2026. WHAT IT WAS ───────────────────────────────────────
//
// A Stitch month grid with six empty handlers. Days highlighted when tapped
// and nothing was read or saved. It had the most empty handlers of any screen
// in the app.
//
// ── READS ARE DIRECT, WRITES GO THROUGH A FUNCTION ─────────────────────────
//
// blocked_dates/{YYYY-MM} is `allow read: if true` — a guest browses a
// calendar before signing in — but `allow write: if false` for every client,
// including the host who owns the property. That is deliberate and stays: a
// client that could write this could free a night on somebody else's
// confirmed booking, and nothing would reconcile the two.
//
// So this streams the month document directly and saves through
// setStayAvailability, which checks ownership inside a transaction and
// refuses to touch any night a booking is holding.
//
// ── THREE STATES, AND THE DIFFERENCE MATTERS ───────────────────────────────
//
//   free      nobody has it
//   booked    a guest has it — the host CANNOT clear this here
//   blocked   the host took it off sale
//
// Both booked and blocked nights sit in the same `nights` map. A booked night
// stores the booking id; a host block stores the sentinel 'HOST_BLOCKED'. The
// screen must show them differently, because a host who cannot tell them apart
// will tap a booked night, watch nothing happen, and conclude the app is
// broken — when it is protecting a guest.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_bottom_nav.dart';
import 'friendly_error.dart';

/// Must match HOST_BLOCK in functions/stay_host.js. If one changes, both do.
const String kHostBlockSentinel = 'HOST_BLOCKED';

class AvailabilityCalendarScreen extends StatefulWidget {
  const AvailabilityCalendarScreen({super.key});

  @override
  State<AvailabilityCalendarScreen> createState() =>
      _AvailabilityCalendarScreenState();
}

class _AvailabilityCalendarScreenState
    extends State<AvailabilityCalendarScreen> {
  String? _listingId;
  late DateTime _month;
  final Set<String> _selected = <String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listingId ??= ModalRoute.of(context)?.settings.arguments as String?;
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _apply({required bool blocked}) async {
    if (_selected.isEmpty || _listingId == null) return;
    setState(() => _saving = true);
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('setStayAvailability')
          .call<Map<String, dynamic>>({
        'listingId': _listingId,
        'nights': _selected.toList()..sort(),
        'blocked': blocked,
      });
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((res.data['message'] ?? 'Saved.').toString()),
        backgroundColor: ((res.data['skippedBooked'] as num?) ?? 0) > 0
            ? GoOutsColors.warning
            : GoOutsColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Was e.toString() + substring, which put the Dart stack trace in the
      // snackbar. See friendly_error.dart.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyError(e,
            fallback: 'Could not save your calendar. Please try again.')),
        backgroundColor: GoOutsColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'Availability',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _listingId == null
          ? _notice('No property was selected. Open a property from My '
              'properties and choose Calendar.')
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('stay_listings')
                  .doc(_listingId)
                  .collection('blocked_dates')
                  .doc(_monthKey)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _notice('Could not load the calendar.\n'
                      '${snap.error}');
                }
                // A month with nothing in it has no document at all. That is
                // normal — an empty calendar, not an error.
                final nights = (snap.data?.data()?['nights'] as Map?) ??
                    const <String, dynamic>{};
                return _calendar(nights.cast<String, dynamic>());
              },
            ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.bookings),
    );
  }

  Widget _calendar(Map<String, dynamic> nights) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Monday = 1 in Dart, and UK calendars start on Monday.
    final leading = first.weekday - 1;
    final today = DateTime.now();
    final todayKey = _dayKey(today);

    return Column(
      children: <Widget>[
        _monthBar(),
        _legend(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Column(
              children: <Widget>[
                Row(
                  children: const <String>['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      .map((d) => Expanded(
                            child: Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(d,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            GoOutsColors.onSurfaceVariant)),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: leading + daysInMonth,
                  itemBuilder: (context, i) {
                    if (i < leading) return const SizedBox.shrink();
                    final day = i - leading + 1;
                    final date = DateTime(_month.year, _month.month, day);
                    final key = _dayKey(date);
                    final value = nights[key];

                    final isBooked =
                        value != null && value != kHostBlockSentinel;
                    final isBlocked = value == kHostBlockSentinel;
                    // A night already gone cannot be sold or held back.
                    final isPast = key.compareTo(todayKey) < 0;
                    final isSelected = _selected.contains(key);

                    return _dayCell(
                      day: day,
                      key: key,
                      isBooked: isBooked,
                      isBlocked: isBlocked,
                      isPast: isPast,
                      isSelected: isSelected,
                      isToday: key == todayKey,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        _actionBar(),
      ],
    );
  }

  Widget _dayCell({
    required int day,
    required String key,
    required bool isBooked,
    required bool isBlocked,
    required bool isPast,
    required bool isSelected,
    required bool isToday,
  }) {
    Color bg = GoOutsColors.surface;
    Color fg = GoOutsColors.navy;
    if (isPast) {
      bg = GoOutsColors.background;
      fg = GoOutsColors.onSurfaceVariant.withValues(alpha: 0.5);
    } else if (isBooked) {
      bg = GoOutsColors.primary.withValues(alpha: 0.16);
      fg = GoOutsColors.primary;
    } else if (isBlocked) {
      bg = GoOutsColors.onSurfaceVariant.withValues(alpha: 0.22);
      fg = GoOutsColors.navy;
    }
    if (isSelected) {
      bg = GoOutsColors.navy;
      fg = Colors.white;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      // Booked and past nights are not tappable. A tap that silently does
      // nothing reads as a broken app; explaining why is the whole point of
      // the message below.
      onTap: (isPast || _saving)
          ? null
          : () {
              if (isBooked) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'A guest has booked that night, so it cannot be '
                      'changed here. Decline or cancel the booking first.'),
                ));
                return;
              }
              setState(() {
                if (!_selected.remove(key)) _selected.add(key);
              });
            },
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isToday ? GoOutsColors.primary : GoOutsColors.border,
            width: isToday ? 1.6 : 1,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$day',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (isBooked && !isSelected)
                const Icon(Icons.person, size: 10,
                    color: GoOutsColors.primary),
              if (isBlocked && !isSelected)
                const Icon(Icons.block, size: 10,
                    color: GoOutsColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthBar() {
    const names = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final now = DateTime.now();
    // No going back before the current month. Nothing there can be changed.
    final canGoBack =
        _month.isAfter(DateTime(now.year, now.month));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: canGoBack
                ? () => setState(() {
                      _month = DateTime(_month.year, _month.month - 1);
                      _selected.clear();
                    })
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${names[_month.month - 1]} ${_month.year}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: GoOutsColors.navy,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() {
              _month = DateTime(_month.year, _month.month + 1);
              // Cleared on purpose. Selection is per month — the save sends
              // whatever is selected, and carrying a hidden selection from
              // another month means blocking nights the host cannot see.
              _selected.clear();
            }),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _legend() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          children: <Widget>[
            _key(GoOutsColors.primary.withValues(alpha: 0.16), 'Booked'),
            _key(GoOutsColors.onSurfaceVariant.withValues(alpha: 0.22),
                'You blocked'),
            _key(GoOutsColors.surface, 'Available'),
            _key(GoOutsColors.navy, 'Selected'),
          ],
        ),
      );

  Widget _key(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: GoOutsColors.border),
            ),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11.5, color: GoOutsColors.body)),
        ],
      );

  Widget _actionBar() {
    final n = _selected.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: GoOutsColors.surface,
        border: Border(top: BorderSide(color: GoOutsColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              n == 0
                  ? 'Tap nights to select them.'
                  : '$n ${n == 1 ? "night" : "nights"} selected',
              style: GoogleFonts.inter(
                  fontSize: 12.5, color: GoOutsColors.body),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (n == 0 || _saving)
                        ? null
                        : () => _apply(blocked: false),
                    icon: const Icon(Icons.event_available_rounded, size: 18),
                    label: const Text('Make available'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (n == 0 || _saving)
                        ? null
                        : () => _apply(blocked: true),
                    icon: _saving
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.event_busy_rounded, size: 18),
                    label: const Text('Block'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48)),
                  ),
                ),
              ],
            ),
          ],
        ),
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
