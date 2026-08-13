// The six intro screens. First thing a new host ever sees.
//
// ── WHY THIS EXISTS ──────────────────────────────────────────────────────
//
// 13 August 2026. Until now a host who opened the app for the first time got
// the welcome splash and a Sign In button, and nothing anywhere answered the
// only question they actually have: why would I list here instead of Airbnb.
//
// ── WHY THE COPY IS LOCKED IN THIS FILE ──────────────────────────────────
//
// The first pass of these screens was generated with its own copy, and four of
// the six described features that do not exist: a compliance document vault,
// an integrated message inbox, automated HMRC reporting, and a "funds clear 24
// hours after check-in" payout promise. One screen said timestamped photos are
// "undeniable proof" and that the host is "always protected".
//
// None of that is true. Payments are not integrated. Claims are not built. We
// do not file anything with HMRC and we do not adjudicate disputes.
//
// So every line below is deliberate, and each one is something the app does
// today:
//
//   partners within half a mile  -> enrichListingLocation, deployed
//   accept / decline             -> host accept-decline, deployed
//   calendar + rate + min stay   -> calendar writes, built
//   check-in / check-out photos  -> evidence capture, built
//   verified before you list     -> createStayListing refuses unverified hosts
//   commission on completed stay -> the configured model, no date, no rate
//
// ⚠ BEFORE CHANGING ANY STRING HERE, check the feature is built. This screen
// is a promise to someone deciding whether to trust us with their house.
//
// ── WHAT IS DELIBERATELY ABSENT ──────────────────────────────────────────
//
// No earnings figure. No commission percentage — it is admin-configurable and
// a number in a build is false the day it changes. No payout timing. No
// guarantee, no "protected", no "proof". No shield or padlock iconography,
// which reads as insurance we do not provide. No count of hosts, no ratings.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen.dart';
import '../auth/signup_screen.dart';
import '../../theme/goouts_colors.dart';

// ── Has this host seen the intro? ────────────────────────────────────────
//
// Read once in main() before runApp, so the launch coordinator can decide
// synchronously and never flashes the wrong screen while a Future resolves.
const String kHostIntroSeenKey = 'goouts_host_intro_seen_v1';

/// Defaults to TRUE on purpose. If SharedPreferences throws, the intro is
/// skipped rather than shown — the cost of missing it once is nothing, the
/// cost of trapping every host behind it on every launch is the app.
bool hostIntroSeen = true;

Future<void> loadHostIntroSeen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    hostIntroSeen = prefs.getBool(kHostIntroSeenKey) ?? false;
  } catch (e) {
    hostIntroSeen = true;
    debugPrint('host intro: pref read failed, skipping intro — $e');
  }
}

Future<void> _markIntroSeen() async {
  hostIntroSeen = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kHostIntroSeenKey, true);
  } catch (e) {
    debugPrint('host intro: pref write failed — $e');
  }
}

// ── One slide ────────────────────────────────────────────────────────────
class _Slide {
  const _Slide({
    required this.asset,
    required this.fallbackIcon,
    required this.eyebrow,
    required this.headline,
    required this.body,
    this.cardIcon,
    this.cardTitle,
    this.cardLine,
  });

  final String asset;

  /// Every illustration has one. A missing asset must never be a crash or a
  /// blank rectangle — the sequence has to build and run before the artwork
  /// lands, and it has to survive a bad export afterwards.
  final IconData fallbackIcon;

  final String eyebrow;
  final String headline;
  final String body;

  final IconData? cardIcon;
  final String? cardTitle;
  final String? cardLine;

  bool get hasCard => cardTitle != null;
}

// Sentence case throughout, including the eyebrows. Two of them came back in
// capitals, which on a screen aimed at a cautious 55-year-old landlord reads
// as marketing rather than information.
const List<_Slide> _slides = <_Slide>[
  _Slide(
    asset: 'assets/images/host_intro1_illustration.webp',
    fallbackIcon: Icons.storefront_rounded,
    eyebrow: 'Only on GoOuts',
    headline: 'The cafés near you sell your listing',
    body: 'Guests see every GoOuts partner within half a mile of your door, '
        'and earn cashback there while they stay.',
    cardIcon: Icons.groups_rounded,
    cardTitle: 'Your guests are already here',
    cardLine: 'Thousands of GoOuts members already pay at our partner cafés, '
        'pubs and restaurants every day.',
  ),
  _Slide(
    asset: 'assets/images/host_intro2_illustration.webp',
    fallbackIcon: Icons.inbox_rounded,
    eyebrow: 'You decide',
    headline: 'Every booking is your call',
    body: 'Requests come to you first. Accept, decline or ask a question '
        'before anyone books.',
    // Not a speech bubble. The artwork on this slide already looks like a chat
    // thread, and a messaging icon next to it would promise an inbox we have
    // not built.
    cardIcon: Icons.fact_check_rounded,
    cardTitle: 'Nothing is automatic',
    cardLine: 'No booking is ever confirmed without you.',
  ),
  _Slide(
    asset: 'assets/images/host_intro3_illustration.webp',
    fallbackIcon: Icons.calendar_month_rounded,
    eyebrow: 'Your rules',
    headline: 'Open only the nights you want',
    body: 'Set your rate, block dates, set a minimum stay. Change any of it '
        'whenever you like.',
    cardIcon: Icons.edit_calendar_rounded,
    cardTitle: 'Yours to change',
    cardLine: 'Nothing is locked in. Close a night at any time.',
  ),
  _Slide(
    asset: 'assets/images/host_intro4_illustration.webp',
    fallbackIcon: Icons.photo_camera_rounded,
    eyebrow: 'On the record',
    headline: 'Photograph it, before and after',
    // Process, never outcome. It says what happens. It does not say the host
    // wins the argument, because that is not ours to promise.
    body: 'Timestamped check-in and check-out photos, saved against the '
        'booking.',
    cardIcon: Icons.photo_camera_rounded,
    cardTitle: 'A shared record',
    cardLine: 'You and your guest see the same photos. Neither side can '
        'delete them.',
  ),
  _Slide(
    asset: 'assets/images/host_intro5_illustration.webp',
    fallbackIcon: Icons.how_to_reg_rounded,
    eyebrow: 'Checked first',
    headline: 'Verified before you list',
    // "Approved" is doing a job here. The illustration is a sealed, signed
    // certificate, so the copy has to name something that actually gets
    // approved — otherwise the picture is making a bigger claim than the words.
    // What gets approved is the HOST, and that is real: createStayListing
    // refuses anyone whose kycStatus is not verified, so a property genuinely
    // cannot go live until an admin has signed it off.
    //
    // What is NOT claimed, and must never be: that GoOuts certifies the
    // property is legally compliant. We do not check gas, fire or electrical
    // safety certificates and we do not hold them. If that ever appears in
    // this copy it is wrong, whatever the artwork shows.
    body: "We check every host's identity and business details. A property "
        "only goes live once that's approved.",
    // NOT verified_user — that is a shield, and a shield on this screen reads
    // as insurance. It is a person being checked, so it is a person icon.
    cardIcon: Icons.how_to_reg_rounded,
    cardTitle: 'Both ways',
    cardLine: 'Guests know who they are booking with, and you know GoOuts '
        'checked.',
  ),
  _Slide(
    asset: 'assets/images/host_intro6_illustration.webp',
    fallbackIcon: Icons.sell_rounded,
    eyebrow: 'Free to list',
    headline: "Nothing to pay until you're booked",
    body: 'Listing is free. We take a commission only on completed stays.',
    // No card. This screen carries the button, and a card above it competes.
  ),
];

class HostIntroScreen extends StatefulWidget {
  const HostIntroScreen({super.key});

  @override
  State<HostIntroScreen> createState() => _HostIntroScreenState();
}

class _HostIntroScreenState extends State<HostIntroScreen> {
  final PageController _pc = PageController();
  int _i = 0;

  bool get _isLast => _i == _slides.length - 1;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() => _pc.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );

  void _back() => _pc.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );

  Future<void> _leave(Widget destination) async {
    await _markIntroSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  // Skip and "Create your listing" go to the same place deliberately. Someone
  // skipping an intro is not saying "I do not want to list", they are saying
  // "I have read enough" — so sending them anywhere other than the front door
  // just adds a tap.
  void _toSignup() => _leave(const SignupScreen());
  void _toLogin() => _leave(const LoginScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Blue behind the illustration, so the artwork's own background blends
      // into the page instead of sitting on it as a visible rectangle.
      backgroundColor: GoOutsColors.primary,
      body: Column(
        children: <Widget>[
          _header(),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _slides.length,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (_, i) => _page(_slides[i]),
            ),
          ),
          _controls(),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────
  //
  // The wordmark is on EVERY screen. Two of the six came back without it and
  // the sequence stopped feeling like one app.
  Widget _header() => SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Text(
                'GoOuts Host',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              // Hidden on screen 1 rather than greyed out. There is nowhere to
              // go back to, and a dead control invites a tap that does nothing.
              if (_i > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 22),
                    onPressed: _back,
                  ),
                ),
              // Hidden on the last screen only — the real button is already on
              // the page there, and two ways forward is one too many.
              if (!_isLast)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _toSignup,
                    child: Text(
                      'Skip',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  // ── One page ───────────────────────────────────────────────────────────
  //
  // Fixed 52 / 48 split on every slide. Sizing the white sheet to its own text
  // instead would move its top edge as you swipe, and a panel that jumps
  // between slides is the difference between "designed" and "generated".
  Widget _page(_Slide s) => Column(
        children: <Widget>[
          Expanded(
            flex: 52,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Image.asset(
                s.asset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stack) => Center(
                  child: Icon(
                    s.fallbackIcon,
                    size: 88,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 48,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: GoOutsColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 8),
              child: SingleChildScrollView(
                child: Column(
                  // LEFT, on every slide. Four of the six came back centred.
                  // Centred body copy is a poster; a host reading three lines
                  // about who can delete their photographs is reading a
                  // document.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.eyebrow,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GoOutsColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.headline,
                      style: GoogleFonts.inter(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                        color: GoOutsColors.navy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s.body,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        height: 1.5,
                        color: GoOutsColors.body,
                      ),
                    ),
                    if (s.hasCard) ...<Widget>[
                      const SizedBox(height: 18),
                      _card(s),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );

  Widget _card(_Slide s) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GoOutsColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GoOutsColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: GoOutsColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(s.cardIcon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.cardTitle!,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: GoOutsColors.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.cardLine!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: GoOutsColors.body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Dots and controls ──────────────────────────────────────────────────
  //
  // OUTSIDE the PageView on purpose. Inside it they swipe away with the
  // content, which is how the generated set ended up showing six dots with the
  // last one active on the first screen.
  Widget _controls() => Container(
        color: GoOutsColors.background,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _dots(),
              const SizedBox(height: 16),
              if (_isLast) ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _toSignup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GoOutsColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Create your listing',
                      style: GoogleFonts.inter(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _textButton('Back', _back),
                    // A host who already has an account should not have to go
                    // through the front door to find the side one.
                    _textButton('Sign in', _toLogin),
                  ],
                ),
              ] else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    // An invisible spacer, not a disabled button, so "Next"
                    // stays in exactly the same place on screen 1 as it does
                    // on screens 2 to 5.
                    _i == 0
                        ? const SizedBox(width: 64, height: 44)
                        : _textButton('Back', _back),
                    _textButton('Next', _next),
                  ],
                ),
            ],
          ),
        ),
      );

  Widget _textButton(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: GoOutsColors.primary,
          ),
        ),
      );

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(_slides.length, (i) {
          final on = i == _i;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: on ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: on ? GoOutsColors.primary : const Color(0xFFD4DAE5),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      );
}
