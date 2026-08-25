import 'package:flutter/material.dart';

import '../core/app_semantic_colors.dart';
import '../core/design_tokens.dart';

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
    final textTheme = Theme.of(context).textTheme;

    // One ground for all four, and the state carried by the glyph alone.
    //
    // Each kind used to paint the whole toast in its own semantic *container*
    // — a pale green slab, then a pale amber one, then a pale red one. `12i`
    // draws them as one dark card with a coloured icon, and it is right: four
    // differently coloured blocks floating over the page read as four
    // unrelated components, while one ground in four states reads as what it
    // is. It also makes a toast unmistakably a *label over* the app rather
    // than another surface in it — the same thing [AppOverlay] already says
    // about tooltips, and the reason the two now share an ink.
    //
    // The hues come from [AppSemanticColors.dark] whatever the app's
    // brightness, because the ground does not flip either. `12i` draws them at
    // exactly those values.
    final (Color glyph, IconData icon) = switch (kind) {
      _AppSnackBarKind.success => (AppSemanticColors.dark.success, Icons.check_circle_outline),
      _AppSnackBarKind.error => (AppOverlay.danger, Icons.error_outline),
      _AppSnackBarKind.warning => (AppSemanticColors.dark.warning, Icons.warning_amber_rounded),
      _AppSnackBarKind.info => (AppSemanticColors.dark.info, Icons.info_outline),
    };

    // Hidden first so a rapid string of calls (e.g. one failure per file in a
    // batch) doesn't queue up a stack of toasts the user has to dismiss one
    // at a time — only the latest state is worth showing.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppOverlay.ink,
          behavior: SnackBarBehavior.floating,
          // A toast the user is meant to act on has to outlast the four
          // seconds it takes to read one they only have to notice.
          duration: Duration(seconds: action == null ? 4 : 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          // `12i`'s own insets. Material's default is 16 horizontal with the
          // vertical left to the content, which put the glyph a step further
          // from the edge than the card's corner radius wants.
          padding: EdgeInsets.only(left: 14, right: action == null ? 14 : 6),
          action: action == null
              ? null
              : SnackBarAction(
                  label: action.label,
                  // The user's own accent, at the one tone that is pinned
                  // against the brightness — see [AppAccent.accentOnOverlay].
                  textColor: colorScheme.accentOnOverlay,
                  onPressed: action.onPressed,
                ),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: glyph, size: AppSize.iconSm),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppOverlay.onInk,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}
