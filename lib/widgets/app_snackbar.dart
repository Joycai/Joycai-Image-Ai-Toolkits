import 'package:flutter/material.dart';

enum _AppSnackBarKind { success, error, warning, info }

/// A single button on a toast, for the case where the message names something
/// the user has to go and do — "no model configured" is only actionable if
/// the toast can also offer the way to Settings.
class AppSnackBarAction {
  final String label;
  final VoidCallback onPressed;

  const AppSnackBarAction({required this.label, required this.onPressed});
}

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

  static void success(BuildContext context, String message, {AppSnackBarAction? action}) =>
      _show(context, message, _AppSnackBarKind.success, action);

  static void error(BuildContext context, String message, {AppSnackBarAction? action}) =>
      _show(context, message, _AppSnackBarKind.error, action);

  /// A precondition the user has to satisfy before the thing they asked for
  /// can happen — no model configured, no output folder chosen, a required
  /// field left empty.
  ///
  /// Distinct from [error] on purpose: nothing has gone wrong and nothing was
  /// lost, so painting it in the same red as a failed save teaches the user to
  /// discount red. Distinct from [info] too — this one blocks.
  static void warning(BuildContext context, String message, {AppSnackBarAction? action}) =>
      _show(context, message, _AppSnackBarKind.warning, action);

  static void info(BuildContext context, String message, {AppSnackBarAction? action}) =>
      _show(context, message, _AppSnackBarKind.info, action);

  static void _show(
    BuildContext context,
    String message,
    _AppSnackBarKind kind,
    AppSnackBarAction? action,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (background, foreground, icon) = switch (kind) {
      _AppSnackBarKind.success => (
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
          Icons.check_circle_outline,
        ),
      _AppSnackBarKind.error => (colorScheme.errorContainer, colorScheme.onErrorContainer, Icons.error_outline),
      // Amber literals rather than a scheme role, and deliberately so. Material
      // has no warning role; the nearest, tertiaryContainer, is derived from
      // whatever seed the user picked, so "warning" would be teal for one user
      // and pink for another — which is no signal at all. Amber is the one
      // status colour that carries meaning independently of the palette, and
      // the log console already spells its levels out the same way.
      _AppSnackBarKind.warning => (
          isDark ? const Color(0xFF4A3A00) : const Color(0xFFFFF1C7),
          isDark ? const Color(0xFFFFD180) : const Color(0xFF6B4E00),
          Icons.warning_amber_rounded,
        ),
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
          // A toast the user is meant to act on has to outlast the four
          // seconds it takes to read one they only have to notice.
          duration: Duration(seconds: action == null ? 4 : 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: action == null
              ? null
              : SnackBarAction(
                  label: action.label,
                  textColor: foreground,
                  onPressed: action.onPressed,
                ),
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
