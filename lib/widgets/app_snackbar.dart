import 'package:flutter/material.dart';

import '../core/app_semantic_colors.dart';
import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import 'glass/app_glass.dart';
import 'shell/phone_dock.dart';

enum _AppSnackBarKind { success, error, warning, info }

/// A single button on a toast, for a message that names something the user has
/// to go and do — "no model configured" is only actionable with a way to the
/// models screen.
class AppSnackBarAction {
  final String label;
  final VoidCallback onPressed;

  const AppSnackBarAction({required this.label, required this.onPressed});
}

/// The app's toast (`01 · 1d`, `1h`).
///
/// One dark glass pill for all four outcomes — 44 tall at r16, centred at the
/// bottom — with the state carried by the glyph alone, in the dark status
/// hues. Four differently coloured slabs read as four components; one ground
/// in four states reads as one. The action label is the accent's dark half,
/// because the ground is dark whatever the app's brightness.
class AppSnackBar {
  AppSnackBar._();

  static void success(BuildContext context, String message, {AppSnackBarAction? action}) =>
      _show(context, message, _AppSnackBarKind.success, action);

  static void error(BuildContext context, String message, {AppSnackBarAction? action}) =>
      _show(context, message, _AppSnackBarKind.error, action);

  /// A precondition the user has to satisfy first — no model, no output
  /// folder, an empty required field. Not red: nothing went wrong.
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
    final scheme = Theme.of(context).colorScheme;

    final (Color glyph, IconData icon) = switch (kind) {
      _AppSnackBarKind.success => (AppSemanticColors.dark.success, Icons.check_circle),
      _AppSnackBarKind.error => (AppOverlay.danger, Icons.error),
      _AppSnackBarKind.warning => (AppSemanticColors.dark.warning, Icons.warning),
      _AppSnackBarKind.info => (AppSemanticColors.dark.info, Icons.info),
    };

    // The dark half of the pair: `primary` in dark, its tone-80 relative in
    // light, which is the accent at the tone a dark ground reads.
    final Color actionColor =
        scheme.brightness == Brightness.dark ? scheme.primary : scheme.accentOnOverlay;

    final bottom = Responsive.isMobile(context)
        ? PhoneDock.clearanceOf(context)
        : AppSpace.s16;

    final messenger = ScaffoldMessenger.of(context);
    // Removed, not hidden: a burst of calls (one failure per file) swaps the
    // message in place instead of playing eight exits and entrances.
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.none,
          margin: EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, bottom),
          // A toast the user is meant to act on outlasts one they only notice.
          duration: Duration(seconds: action == null ? 4 : 8),
          content: Center(
            child: _SnackPill(
              icon: icon,
              glyph: glyph,
              message: message,
              actionLabel: action?.label,
              actionColor: actionColor,
              onAction: action == null
                  ? null
                  : () {
                      messenger.hideCurrentSnackBar();
                      action.onPressed();
                    },
            ),
          ),
        ),
      );
  }
}

class _SnackPill extends StatelessWidget {
  const _SnackPill({
    required this.icon,
    required this.glyph,
    required this.message,
    required this.actionLabel,
    required this.actionColor,
    required this.onAction,
  });

  final IconData icon;
  final Color glyph;
  final String message;
  final String? actionLabel;
  final Color actionColor;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppGlass(
      grade: GlassGrade.float,
      tone: GlassTone.dark,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: EdgeInsets.only(left: 12, right: actionLabel == null ? 14 : 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppSize.iconLg, color: glyph),
              const SizedBox(width: AppSpace.s10),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium!.metricsOnly,
                  ),
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(width: AppSpace.s10),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: actionColor,
                    textStyle: textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
