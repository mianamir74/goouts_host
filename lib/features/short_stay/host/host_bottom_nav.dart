// One bottom navigation bar for the whole host app.
//
// ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
//
// Created 8 August 2026, after "when I open dashboard nothing works including
// app nav" from the first real device test.
//
// Thirteen of the twenty-five Stitch screens shipped a BottomNavigationBar
// with NO onTap. Tapping a tab moved the highlight and navigated nowhere. It
// looked like a working app that had frozen, and it was reported as exactly
// that.
//
// They also disagreed with each other. Stitch generated each screen in
// isolation, so the tabs were:
//
//   host_01   Dashboard · Bookings · Listings · Inbox   · Profile
//   host_10   Home      · Bookings · Listings · Earnings · Menu
//   host_20   Home      · Bookings · Earnings · Menu
//
// Four tabs on one screen, five on another, in a different order, with
// different labels for the same destination. Fixing thirteen copies
// separately would have produced thirteen slightly different fixes and left
// the disagreement in place — the same shape as the three copies of
// role→access in the admin panel that silently drifted apart.
//
// So: ONE widget, one set of tabs, one place to change them.
//
// ── HOW IT NAVIGATES ───────────────────────────────────────────────────────
//
// pushNamedAndRemoveUntil back to the dashboard, then push the destination.
// Without that, five taps build a five-deep stack and the back arrow walks
// the user through every screen they visited. A tab bar should switch, not
// accumulate.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_routes.dart';

/// Which tab is highlighted. Pass the one matching the screen you are on.
enum HostTab { home, bookings, listings, earnings, profile }

class HostBottomNav extends StatelessWidget {
  const HostBottomNav({super.key, required this.current});

  final HostTab current;

  static const _routes = <HostTab, String>{
    HostTab.home: HostRoutes.dashboard,
    HostTab.bookings: HostRoutes.requests,
    HostTab.listings: HostRoutes.myListings,
    HostTab.earnings: HostRoutes.earnings,
    HostTab.profile: HostRoutes.profile,
  };

  void _go(BuildContext context, HostTab tab) {
    if (tab == current) return; // already here
    final route = _routes[tab]!;

    if (tab == HostTab.home) {
      // Back to the dashboard and clear everything above it.
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }

    // Replace rather than stack, so the tab bar switches instead of burying
    // the user five screens deep.
    Navigator.of(context).pushNamedAndRemoveUntil(
      route,
      (r) => r.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: GoOutsColors.surface,
        border: Border(top: BorderSide(color: GoOutsColors.border, width: 1)),
      ),
      child: BottomNavigationBar(
        elevation: 0,
        backgroundColor: GoOutsColors.surface,
        selectedItemColor: GoOutsColors.primary,
        unselectedItemColor: GoOutsColors.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        currentIndex: HostTab.values.indexOf(current),
        selectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle:
            GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11),
        onTap: (i) => _go(context, HostTab.values[i]),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined), label: 'Bookings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.holiday_village_outlined), label: 'Listings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.payments_outlined), label: 'Earnings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
