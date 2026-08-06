import 'package:flutter/material.dart';

/// The single colour source for GoOuts Host.
///
/// ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
///
/// Stitch generated the 25 host screens on 4 August 2026 and gave EACH ONE its
/// own private copy of a `GoOutsColors` class. Nineteen copies, eighteen of
/// which differed from each other. Dart compiles that happily — a class
/// declared in the current library shadows an imported one, and nothing
/// imported across screens — so it analyzed clean the whole time.
///
/// It was not merely untidy. Six colours had genuinely conflicting values, so
/// the screens did not match one another on screen:
///
///   background   0xFFF8F9FF (18 files)  vs  0xFFF2F4F7 (1)
///   border       0xFFE2E8F0 (12)        vs  0xFFEDF2F7 (1)
///   success      0xFF22C55E (7)         vs  0xFF16A34A (2)
///   teal         0xFF00668C (6)         vs  0xFF0A6E8A (1)
///   infoBg       0xFFE0F3FB (1)         vs  0xFFEBF5FF (1)
///   alertBg      0xFF005F84 (1)         vs  0xFF6B7280 (1)
///
/// Resolved by majority vote, with two ties broken on evidence rather than
/// preference:
///
///   infoBg  -> 0xFFE0F3FB, because that is already the value of `tint`, which
///              9 files agree on. The two are the same pale blue doing the same
///              job, so aligning them removes a distinction that was never
///              intentional.
///   alertBg -> 0xFF005F84. It is used as a text and icon colour throughout
///              14_pricing_alert_screen, not just as a fill, so it has to be
///              dark and on-brand. The alternative, 0xFF6B7280, is a neutral
///              grey that would have read as disabled text.
///
/// ── THE RULE FROM HERE ──────────────────────────────────────────────────────
///
/// Never declare a `GoOutsColors` class in a screen file. Import this one.
/// A local declaration will silently shadow it and the drift starts again,
/// with no warning from any tool.
class GoOutsColors {
  const GoOutsColors._();

  // ── Brand ─────────────────────────────────────────────────────────────────
  /// GoOuts blue. Agreed by all 19 original copies.
  static const Color primary = Color(0xFF0392CA);
  static const Color navy = Color(0xFF0D1B3E);
  static const Color teal = Color(0xFF00668C);

  // ── Surfaces ──────────────────────────────────────────────────────────────
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8F9FF);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color border = Color(0xFFE2E8F0);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color body = Color(0xFF475569);
  static const Color onSurfaceVariant = Color(0xFF64748B);

  // ── Status ────────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color danger = Color(0xFFDC2626);

  // ── Listing lifecycle ─────────────────────────────────────────────────────
  static const Color live = Color(0xFF22C55E);
  static const Color paused = Color(0xFFF59E0B);
  static const Color draft = Color(0xFF94A3B8);

  // ── Containers ────────────────────────────────────────────────────────────
  static const Color tint = Color(0xFFE0F3FB);
  static const Color infoBg = Color(0xFFE0F3FB);
  static const Color infoBackground = Color(0xFFF1F5F9);
  static const Color infoBorder = Color(0xFF0392CA);
  static const Color successBg = Color(0xFFE6F9EE);
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color alertBg = Color(0xFF005F84);
  static const Color alertText = Color(0xFFFFFFFF);

  // Only the six PRIVATE _GoOutsColors copies carried these two — the public
  // ones never had them. Despite the name they are a red pair, not amber:
  // 08_create_listing_legal uses them for the "you are responsible for your
  // own licensing" notice, which is a warning in the legal sense.
  static const Color warningBg = Color(0xFFFFF1F2);
  static const Color warningText = Color(0xFF991B1B);
}
