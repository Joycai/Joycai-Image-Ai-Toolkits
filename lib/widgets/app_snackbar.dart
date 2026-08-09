import 'package:flutter/material.dart';

enum _AppSnackBarKind { success, error, info }

/// Shows a themed [SnackBar] for one of three outcomes.
///
/// Every call site around the app currently does its own
/// `ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(...)`,
/// each picking its own colour and duration by hand. This collapses that to
/// the three outcomes a toast actually reports — success, error, info —
/// rather than exposing a raw [Color] parameter another call site would have
/// to invent a fourth meaning for.
class AppSnackBar {
  AppSnackBar._();

  static void success(BuildContext context, String message) => _show(context, message, _AppSnackBarKind.success);

  static void error(BuildContext context, String message) => _show(context, message, _AppSnackBarKind.error);

  static void info(BuildContext context, String message) => _show(context, message, _AppSnackBarKind.info);

  static void _show(BuildContext context, String message, _AppSnackBarKind kind) {
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (kind) {
      _AppSnackBarKind.success => (
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
          Icons.check_circle_outline,
        ),
      _AppSnackBarKind.error => (colorScheme.errorContainer, colorScheme.onErrorContainer, Icons.error_outline),
      // Not errorContainer/primaryContainer: info is neither good nor bad
      // news, so it takes the neutral inverse-surface tone Material reserves
      // for exactly this — a toast that stands out without implying a verdict.
      _AppSnackBarKind.info => (colorScheme.inverseSurface, colorScheme.onInverseSurface, Icons.info_outline),
    };

    // Hidden first so a rapid string of calls (e.g. one failure per file in a
    // batch) doesn't queue up a stack of toasts the user has to dismiss one
    // at a time — only the latest state is worth showing.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: background,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: TextStyle(color: foreground))),
            ],
          ),
        ),
      );
  }
}
