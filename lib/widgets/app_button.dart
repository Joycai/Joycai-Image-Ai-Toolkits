import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';

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

  /// A secondary action beside a primary one: a hairline outline on the
  /// surface, carrying no accent of its own.
  ///
  /// Was [FilledButton.tonal] — a `secondaryContainer` slab. That spent the
  /// seed's colour on the action the user *isn't* meant to take, which is the
  /// one thing the design spec is emphatic about ("主题色只出现在选中态、主
  /// CTA 与徽标上"). An outline separates it from the primary by weight
  /// instead of by hue, leaving the accent to mean something.
  ///
  /// [tonalButtonStyle] is still exported for the handful of hand-rolled
  /// [FilledButton.tonal]s elsewhere, which still need it — the app-wide
  /// filled-button theme outranks the tonal variant's own default and would
  /// otherwise paint them fully primary.
  secondary,

  /// A secondary action that is still the accent's: an accent wash behind an
  /// accent label, one tier under [primary].
  ///
  /// For the *second* place on a screen where the accent belongs — the spec's
  /// `8a` names exactly one, the 应用 inside the assistant's result card, in
  /// the same annotation that establishes 应用到工作台 as the only solid fill.
  /// [secondary] would flatten that: it is the neutral tier, and using it here
  /// makes the button that applies the model's output look like any other
  /// button on the card.
  ///
  /// Deliberately **not** Material's tonal. [tonalButtonStyle] is a
  /// `secondaryContainer` slab, and `secondaryContainer` is a muted derivative
  /// of the seed that reads as grey-with-a-tint at several of them. This takes
  /// the app's own accent ladder instead — [AppAccent.accentTint] behind
  /// [AppAccent.onAccentTint], the same pairing every selected thing in the app
  /// uses, whose contrast `design_tokens_test` already asserts at every seed in
  /// both brightnesses.
  ///
  /// Use it sparingly. §1 allows the accent in three places — selection, the
  /// main CTA, badges — and this is a fourth. It earns that only where the
  /// action really is the accent's and merely outranked by another one on the
  /// same screen.
  tonal,

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
          AppSize.compact,
          VisualDensity.compact,
          const EdgeInsets.symmetric(horizontal: 10),
          textTheme.labelMedium,
        ),
      AppButtonSize.normal => (AppSize.control, null, null, null),
      // A screen's main action carries a little more weight than the buttons
      // beside it; several of these had spelled that out as a bold label.
      AppButtonSize.large => (
          AppSize.large,
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
      case AppButtonVariant.destructive:
        return FilledButton(style: style, onPressed: onPressed, child: child);
      case AppButtonVariant.text:
      case AppButtonVariant.destructiveText:
        return TextButton(style: style, onPressed: onPressed, child: child);
      case AppButtonVariant.secondary:
      case AppButtonVariant.tonal:
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
      case AppButtonVariant.secondary:
      case AppButtonVariant.tonal:
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
        AppButtonSize.compact => AppSize.iconSm,
        AppButtonSize.normal => AppSize.iconMd,
        AppButtonSize.large => AppSize.iconLg,
      };

  ButtonStyle? _styleFor(BuildContext context, ColorScheme colorScheme) {
    switch (variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.text:
        // Both take the app-wide theme's default for their widget type —
        // naming a style here would just repeat it.
        return null;
      case AppButtonVariant.secondary:
        return OutlinedButton.styleFrom(
          // `surface`, not transparent: these sit on the canvas and on cards
          // alike, and an unfilled outline over a card's own tone reads as a
          // hole punched in it rather than as a button.
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outlineVariant),
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
        );
      case AppButtonVariant.tonal:
        // An OutlinedButton with a fill, not a FilledButton with a side: the
        // spec draws both a wash and an edge, and the edge is what keeps the
        // 12% wash from dissolving into a card that is itself nearly white.
        return OutlinedButton.styleFrom(
          backgroundColor: colorScheme.accentTint,
          foregroundColor: colorScheme.onAccentTint,
          side: BorderSide(color: colorScheme.accentRing),
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
        );
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
          side: BorderSide(color: colorScheme.error.withValues(alpha: AppAlpha.edge)),
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
        );
      case AppButtonVariant.destructiveText:
        return TextButton.styleFrom(
          foregroundColor: colorScheme.error,
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
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
        return colorScheme.onSurface;
      case AppButtonVariant.tonal:
        return colorScheme.onAccentTint;
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
