import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Usage:
//   GoOutsSheet.success(context, title: 'Done!', message: 'Your wallet was topped up.');
//   GoOutsSheet.error(context, title: 'Oops!', message: 'Something went wrong.');
//   GoOutsSheet.info(context, title: 'Heads up', message: 'Amount capped at £250.');
//   GoOutsSheet.warning(context, title: 'Wait', message: 'You have insufficient balance.');
//
//   All support optional actionLabel / onAction / secondaryLabel / onSecondary
// ─────────────────────────────────────────────────────────────────────────────

enum _SheetType { success, error, info, warning }

class GoOutsSheet {
  GoOutsSheet._();

  // ── Convenience constructors ─────────────────────────────
  static Future<void> success(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool isDismissible = true,
  }) =>
      _show(context,
          type: _SheetType.success,
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
          secondaryLabel: secondaryLabel,
          onSecondary: onSecondary,
          isDismissible: isDismissible);

  static Future<void> error(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool isDismissible = true,
  }) =>
      _show(context,
          type: _SheetType.error,
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
          secondaryLabel: secondaryLabel,
          onSecondary: onSecondary,
          isDismissible: isDismissible);

  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool isDismissible = true,
  }) =>
      _show(context,
          type: _SheetType.info,
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
          secondaryLabel: secondaryLabel,
          onSecondary: onSecondary,
          isDismissible: isDismissible);

  static Future<void> warning(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool isDismissible = true,
  }) =>
      _show(context,
          type: _SheetType.warning,
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
          secondaryLabel: secondaryLabel,
          onSecondary: onSecondary,
          isDismissible: isDismissible);

  // ── Destructive confirm (Delete + Cancel) ────────────────
  /// Returns true if the user tapped the confirm/delete button.
  static Future<bool> confirm(
    BuildContext context, {
    String title = 'Are you sure?',
    String message = 'This action cannot be undone.',
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    IconData icon = Icons.delete_rounded,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      builder: (_) => _GoOutsConfirmSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
      ),
    );
    return result == true;
  }

  // ── Core show ────────────────────────────────────────────
  static Future<void> _show(
    BuildContext context, {
    required _SheetType type,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      isScrollControlled: true,
      builder: (_) => _GoOutsSheetContent(
        type: type,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal sheet widget
// ─────────────────────────────────────────────────────────────────────────────
class _GoOutsSheetContent extends StatelessWidget {
  final _SheetType type;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _GoOutsSheetContent({
    required this.type,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  // ── Type config ──────────────────────────────────────────
  Color get _color => switch (type) {
        _SheetType.success => const Color(0xFF0A7A3E),
        _SheetType.error   => const Color(0xFFDC2626),
        _SheetType.info    => const Color(0xFF0392CA),
        _SheetType.warning => const Color(0xFFF59E0B),
      };

  IconData get _icon => switch (type) {
        _SheetType.success => Icons.check_circle_rounded,
        _SheetType.error   => Icons.cancel_rounded,
        _SheetType.info    => Icons.info_rounded,
        _SheetType.warning => Icons.warning_rounded,
      };

  String get _defaultLabel => switch (type) {
        _SheetType.success => 'Great, thanks!',
        _SheetType.error   => 'Got it',
        _SheetType.info    => 'Understood',
        _SheetType.warning => 'OK',
      };

  Color get _buttonTextColor =>
      type == _SheetType.warning ? const Color(0xFF1A1A1A) : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Gradient tint behind handle + icon ─────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 1.0],
                colors: [
                  _color.withValues(alpha: 0.07),
                  Colors.white,
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                // ── Handle ────────────────────────────────
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Aura icon ─────────────────────────────
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer aura
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: _color.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                    ),
                    // Mid aura
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                    ),
                    // Icon circle with glow shadow
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: _color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _color.withValues(alpha: 0.40),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(_icon, color: Colors.white, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // ── Content ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            child: Column(
              children: [
                // Title
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0D1B3E),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),

                // Message
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[500],
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Divider ───────────────────────────────
                Container(
                  height: 1,
                  color: Colors.grey[100],
                ),
                const SizedBox(height: 20),

                // ── Primary button ────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onAction?.call();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _color,
                      foregroundColor: _buttonTextColor,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      actionLabel ?? _defaultLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _buttonTextColor,
                      ),
                    ),
                  ),
                ),

                // ── Secondary action ──────────────────────
                if (secondaryLabel != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onSecondary?.call();
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    child: Text(
                      secondaryLabel!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(height: 8),

                // Safe area bottom padding
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Destructive confirm sheet  (iOS action-sheet inspired, GoOuts branded)
// ─────────────────────────────────────────────────────────────────────────────
class _GoOutsConfirmSheet extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;

  const _GoOutsConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
  });

  static const Color _red = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Main card ─────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 30,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── Header with icon ───────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _red.withValues(alpha: 0.06),
                        Colors.white,
                      ],
                    ),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      // Aura icon
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: _red.withValues(alpha: 0.07),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: _red.withValues(alpha: 0.13),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: _red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _red.withValues(alpha: 0.38),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(icon, color: Colors.white, size: 22),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Title
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0D1B3E),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Message
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[500],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Divider ────────────────────────────────
                Container(height: 1, color: Colors.grey[100]),

                // ── Delete button ──────────────────────────
                InkWell(
                  onTap: () => Navigator.pop(context, true),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20)),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: Center(
                      child: Text(
                        confirmLabel,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _red,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Cancel card (separate, iOS style) ─────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              onTap: () => Navigator.pop(context, false),
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: Center(
                  child: Text(
                    cancelLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0392CA),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
        ],
      ),
    );
  }
}
