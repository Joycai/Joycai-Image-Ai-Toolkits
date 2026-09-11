import 'package:flutter/material.dart';

/// Success, warning and information — the meanings the theme colour is not
/// allowed to touch.
///
/// A success badge that turned orange because the user likes orange would be
/// telling them something false, so these are literals, a set per brightness,
/// from `00 设计系统 · 1b`. Containers are **opaque**: they land on panels,
/// columns and cards alike, and a translucent wash would read as a different
/// colour on each.
///
/// Destructive is [ColorScheme.error], which `buildAppColorScheme` writes from
/// the same table (`--err` / `--err-bg` / `--err-ink`). Identity colours —
/// fee groups, model-type chips — are not states and do not belong here.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  /// Full strength: an icon, a dot, a progress bar, a 1px rule.
  final Color success;

  /// A label on a solid [success] fill.
  final Color onSuccess;

  /// The opaque wash behind a success badge (`--ok-bg`).
  final Color successContainer;

  /// Text on [successContainer] (`--ok-ink`).
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

  static const AppSemanticColors light = AppSemanticColors(
    success: Color(0xFF1F7A3E),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDDF2E3),
    onSuccessContainer: Color(0xFF155C2E),
    warning: Color(0xFFA1620A),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFBEBD0),
    onWarningContainer: Color(0xFF6E4306),
    info: Color(0xFF2F6FB0),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFDDEAF8),
    onInfoContainer: Color(0xFF1F4E80),
  );

  /// Not light inverted: each hue is lifted to survive a near-black ground,
  /// and its container sinks to sit on one.
  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF4FB86F),
    onSuccess: Color(0xFF0A2414),
    successContainer: Color(0xFF173A24),
    onSuccessContainer: Color(0xFFB8EBC6),
    warning: Color(0xFFE5A040),
    onWarning: Color(0xFF2A1A00),
    warningContainer: Color(0xFF3F2C10),
    onWarningContainer: Color(0xFFFBD9A0),
    info: Color(0xFF6AA7E8),
    onInfo: Color(0xFF0A1E33),
    infoContainer: Color(0xFF1B3350),
    onInfoContainer: Color(0xFFBFDBFA),
  );

  /// The set registered on the ambient theme, falling back on brightness for
  /// a bare `MaterialApp` in a widget test.
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

/// `context.semantic.success` at a call site.
extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semantic => AppSemanticColors.of(this);
}
