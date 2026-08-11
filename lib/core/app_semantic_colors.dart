import 'package:flutter/material.dart';

/// Success, warning and information — the three meanings the seed colour is
/// not allowed to touch.
///
/// Everything else in the app takes its hue from whichever of the seven
/// [AppConstants.presetThemes] the user picked. These three must not: green
/// means *this worked* and amber means *look at this* in every theme, and a
/// success badge that turned orange because the user likes orange would be
/// telling them something false. So these are literals — the only literals in
/// the theme — with a pair per brightness, taken from the *Joycai 设计规范*
/// sheet.
///
/// **Destructive is deliberately absent.** [ColorScheme.error] already is this
/// colour: [ColorScheme.fromSeed] builds the error palette from a fixed hue
/// rather than from the seed, so it is seed-independent for the same reason
/// these are, and Material supplies the container/on-container pair too. A
/// fourth field here would be a second answer to a question already answered —
/// which is exactly how the app ended up with the same amber written out in
/// three files. Use `colorScheme.error` / `errorContainer` / `onErrorContainer`.
///
/// **Identity colours are also absent** — the per-metric accents in
/// `usage_summary.dart` and the model-type chip colours in `models_screen.dart`
/// pick a hue to tell categories apart, not to state a condition. Those belong
/// in their own palette module beside `core/fee_group_palette.dart`; putting
/// them here would make this a junk drawer of every colour that isn't the seed.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  /// The colour at full strength: an icon, a dot, a progress bar, a 1px rule.
  ///
  /// For *text*, prefer [onSuccessContainer] on [successContainer] — a label
  /// in this colour on a plain surface is legible but shouty, and the spec
  /// only ever draws it as a fill.
  final Color success;

  /// A label sitting on a solid [success] fill.
  final Color onSuccess;

  /// The wash behind a success badge. Opaque, not an alpha over the surface:
  /// these land on cards, panels and the canvas alike, and a translucent
  /// version would read as a different colour on each.
  final Color successContainer;

  /// Text and icons on [successContainer]. A tone darker (light) or lighter
  /// (dark) than [success], which is what keeps a badge's label readable
  /// without the badge itself going solid.
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  /// Spec §色板, light. Base hues are the sheet's own values; the containers
  /// are those hues flattened at ~11% over the sheet's white surface, so they
  /// match what it draws while staying opaque.
  static const AppSemanticColors light = AppSemanticColors(
    success: Color(0xFF1A9E57),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFE5F4ED),
    // The sheet draws #158046 here. That measures 4.40:1 on the container
    // above — near enough to look right and just under AA, which is the worst
    // place for a value to sit. Darkened one step to clear 4.5; see
    // design_tokens_test.
    onSuccessContainer: Color(0xFF127843),
    warning: Color(0xFFE09030),
    // Amber is the one hue where white is unreadable at any usable tone, so a
    // solid warning fill carries dark text. This is why `onWarning` exists as
    // a field rather than every semantic fill assuming white.
    onWarning: Color(0xFF3A2600),
    warningContainer: Color(0xFFFBF3E8),
    onWarningContainer: Color(0xFF9A6417),
    info: Color(0xFF1F6FD6),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFE6EFFB),
    onInfoContainer: Color(0xFF1A5AAE),
  );

  /// Spec §色板, dark. Not the light values inverted: the sheet lifts each hue
  /// toward its lighter tones so it survives a near-black canvas, the same
  /// move Material makes between its own light and dark schemes.
  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF3FC47F),
    onSuccess: Color(0xFF062616),
    successContainer: Color(0xFF172D22),
    onSuccessContainer: Color(0xFF5FD494),
    warning: Color(0xFFE8A852),
    onWarning: Color(0xFF2E1D00),
    warningContainer: Color(0xFF2E291C),
    onWarningContainer: Color(0xFFF0BC74),
    info: Color(0xFF5F9FF2),
    onInfo: Color(0xFF06264D),
    infoContainer: Color(0xFF1B2732),
    onInfoContainer: Color(0xFF8CBAF6),
  );

  /// The set registered on the ambient theme.
  ///
  /// Falls back on [ThemeData.brightness] rather than asserting: a widget test
  /// that mounts a bare [MaterialApp], and the several dialogs the app builds
  /// under a locally-constructed theme, would otherwise crash on a null
  /// extension for a colour that was never in doubt.
  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
    );
  }
}

/// `context.semantic.success` at a call site, matching how `colorScheme` is
/// reached for everywhere else in the app.
extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semantic => AppSemanticColors.of(this);
}
