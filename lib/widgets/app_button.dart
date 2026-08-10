import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Which of the app's four button treatments to draw.
///
/// Mirrors what the raw Material widgets ([ElevatedButton]/[TextButton]/
/// [OutlinedButton]/[FilledButton]) were each reached for around the app, so
/// a call site only has to say which *role* the action plays, not which
/// widget draws it.
enum AppButtonVariant {
  /// The one action on a screen that commits. Reads from the app-wide
  /// [FilledButtonThemeData] in [buildAppTheme] — the vibrant fill, not
  /// Material's washed-out default.
  primary,

  /// A secondary action beside a primary one. [tonalButtonStyle] passed in
  /// explicitly, because the app-wide filled-button theme otherwise outranks
  /// [FilledButton.tonal]'s own default and paints it fully primary.
  secondary,

  /// The lowest-emphasis action — cancel, dismiss, "skip this".
  text,

  /// An action that destroys or removes something, coloured from
  /// [ColorScheme.error] rather than the seed.
  destructive,

  /// A destructive action that hasn't been confirmed yet — an outline rather
  /// than [destructive]'s solid fill, so the loudest colour on screen is
  /// reserved for the confirmation the user actually commits with (inside the
  /// dialog this button opens), not the toolbar button that only proposes it.
  destructiveOutline,

  /// A destructive action at the lowest emphasis — the error colour on a
  /// borderless button. For a toolbar or selection bar of otherwise
  /// borderless controls, where [destructiveOutline]'s edge would be the
  /// only one in the row and [destructive]'s fill would shout.
  destructiveText,
}

/// How much room a button takes.
///
/// Buttons were pinned to one height until several call sites turned out to
/// need otherwise, and each had hand-rolled its own `minimumSize` or
/// `visualDensity` to get there — the same drift the component exists to
/// stop. Three sizes cover every one of them.
enum AppButtonSize {
  /// ~30px and tight. For a button inside a popup, a slim toolbar strip or
  /// a card footer, where [normal] would force the row taller than the
  /// controls it sits among.
  compact,

  /// The default, matching [AppIconButton] and the segmented control.
  normal,

  /// 48px. For a sheet's committing action, or a panel's single main call
  /// to action — where the button is what the screen is *for*, and is
  /// usually also a touch target on a phone.
  large,
}

/// A labelled action button in one of four roles ([AppButtonVariant]).
///
/// Replaces reaching for [ElevatedButton]/[TextButton]/[OutlinedButton]/
/// [FilledButton] directly at each call site — those four draw four
/// different visual weights with no shared rule for which to use where, and
/// none of them expose a loading state, so every async action re-implements
/// its own spinner-swap.
///
/// For an icon with no label, see [AppIconButton] instead — this widget
/// always renders a label.
class AppButton extends StatelessWidget {
  final String label;

  /// A qualifier trailing [label] in a lighter weight — "Save copy
  /// *to workspace*". For an action whose destination or scope is worth
  /// stating on the button itself, without giving it the same weight as the
  /// verb. Dropped by the caller, not by this widget, when space is tight.
  final String? secondaryLabel;

  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  /// Swaps the label/icon for a spinner and disables [onPressed], so a call
  /// site driving this from a `Future` doesn't need its own busy/idle switch.
  final bool loading;

  final AppButtonSize size;

  /// Stretches to the width offered. For the committing action at the foot
  /// of a bottom sheet, which is expected to span it.
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondaryLabel,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.size = AppButtonSize.normal,
    this.fullWidth = false,
  });

  /// The label, plus [secondaryLabel] trailing it when set.
  ///
  /// The qualifier carries no colour of its own — it inherits the button's
  /// foreground through [DefaultTextStyle] and is dimmed with opacity, so it
  /// reads as subordinate on a filled, outlined or text button alike without
  /// this widget having to know which one it is.
  Widget _label() {
    if (secondaryLabel == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 6),
        Opacity(
          opacity: 0.78,
          child: Text(secondaryLabel!, style: const TextStyle(fontWeight: FontWeight.w400)),
        ),
      ],
    );
  }

  /// Geometry *and type* for [size] and [fullWidth], layered under the
  /// variant's own style so colour always wins over sizing.
  ///
  /// The label scales with the box. A compact button holding a full-size
  /// label is not compact — it was still overflowing the card it had been
  /// shrunk to fit, and the call sites that predate this had each hand-set a
  /// `fontSize: 12` alongside their `visualDensity`, which is the pairing
  /// this encodes once. Sizes come from the app's type scale rather than
  /// literals, so a change there still reaches buttons.
  ///
  /// Returns null for the default, so an ordinary button keeps whatever the
  /// theme says rather than having the same numbers restated over it.
  ButtonStyle? _sizeStyle(TextTheme textTheme) {
    if (size == AppButtonSize.normal && !fullWidth) return null;

    final (height, density, padding, textStyle) = switch (size) {
      AppButtonSize.compact => (
          30.0,
          VisualDensity.compact,
          const EdgeInsets.symmetric(horizontal: 10),
          textTheme.labelMedium,
        ),
      AppButtonSize.normal => (appButtonMinHeight, null, null, null),
      // A screen's main action carries a little more weight than the buttons
      // beside it; several of these had spelled that out as a bold label.
      AppButtonSize.large => (
          48.0,
          null,
          const EdgeInsets.symmetric(horizontal: 20),
          textTheme.titleMedium,
        ),
    };

    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(fullWidth ? double.infinity : 0, height)),
      visualDensity: density,
      padding: padding == null ? null : WidgetStatePropertyAll(padding),
      textStyle: textStyle == null ? null : WidgetStatePropertyAll(textStyle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveOnPressed = loading ? null : onPressed;
    final sizeStyle = _sizeStyle(Theme.of(context).textTheme);
    final variantStyle = _styleFor(context, colorScheme);
    // Variant first: `merge` fills only what the receiver left null, so the
    // variant's colours survive and the size style supplies the geometry.
    final style = variantStyle?.merge(sizeStyle) ?? sizeStyle;

    if (loading) {
      final spinner = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _foregroundColor(context, colorScheme)),
      );
      return _button(style: style, onPressed: effectiveOnPressed, child: spinner);
    }

    if (icon != null) {
      return _iconButton(style: style, onPressed: effectiveOnPressed, icon: icon!, label: _label());
    }

    return _button(style: style, onPressed: effectiveOnPressed, child: _label());
  }

  Widget _button({required ButtonStyle? style, required VoidCallback? onPressed, required Widget child}) {
    switch (variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.secondary:
      case AppButtonVariant.destructive:
        return FilledButton(style: style, onPressed: onPressed, child: child);
      case AppButtonVariant.text:
      case AppButtonVariant.destructiveText:
        return TextButton(style: style, onPressed: onPressed, child: child);
      case AppButtonVariant.destructiveOutline:
        return OutlinedButton(style: style, onPressed: onPressed, child: child);
    }
  }

  Widget _iconButton({
    required ButtonStyle? style,
    required VoidCallback? onPressed,
    required IconData icon,
    required Widget label,
  }) {
    switch (variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.secondary:
      case AppButtonVariant.destructive:
        return FilledButton.icon(
          style: style,
          onPressed: onPressed,
          icon: Icon(icon, size: _iconSize),
          label: label,
        );
      case AppButtonVariant.text:
      case AppButtonVariant.destructiveText:
        return TextButton.icon(
          style: style,
          onPressed: onPressed,
          icon: Icon(icon, size: _iconSize),
          label: label,
        );
      case AppButtonVariant.destructiveOutline:
        return OutlinedButton.icon(
          style: style,
          onPressed: onPressed,
          icon: Icon(icon, size: _iconSize),
          label: label,
        );
    }
  }

  double get _iconSize => switch (size) {
        AppButtonSize.compact => 15,
        AppButtonSize.normal => 18,
        AppButtonSize.large => 20,
      };

  ButtonStyle? _styleFor(BuildContext context, ColorScheme colorScheme) {
    switch (variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.text:
        // Both take the app-wide theme's default for their widget type —
        // naming a style here would just repeat it.
        return null;
      case AppButtonVariant.secondary:
        return tonalButtonStyle(colorScheme);
      case AppButtonVariant.destructive:
        return FilledButton.styleFrom(
          backgroundColor: colorScheme.error,
          foregroundColor: colorScheme.onError,
          disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        );
      case AppButtonVariant.destructiveOutline:
        return OutlinedButton.styleFrom(
          foregroundColor: colorScheme.error,
          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        );
      case AppButtonVariant.destructiveText:
        return TextButton.styleFrom(
          foregroundColor: colorScheme.error,
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        );
    }
  }

  /// The label colour this variant renders at — needed up front so the
  /// loading spinner can match it instead of falling back to
  /// [CircularProgressIndicator]'s own default (the scheme's primary, which
  /// is wrong on top of a primary-filled or error-filled button).
  Color _foregroundColor(BuildContext context, ColorScheme colorScheme) {
    switch (variant) {
      case AppButtonVariant.primary:
        return Theme.of(context).filledButtonTheme.style?.foregroundColor?.resolve(const {}) ??
            colorScheme.onPrimary;
      case AppButtonVariant.secondary:
        return colorScheme.onSecondaryContainer;
      case AppButtonVariant.text:
        return colorScheme.primary;
      case AppButtonVariant.destructive:
        return colorScheme.onError;
      case AppButtonVariant.destructiveOutline:
      case AppButtonVariant.destructiveText:
        return colorScheme.error;
    }
  }
}
