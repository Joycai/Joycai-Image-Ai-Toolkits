import 'package:flutter/widgets.dart';

/// The app's *reduce visual effects* setting, made readable without a
/// provider.
///
/// Placed once in `MaterialApp.builder` from `AppState.reduceVisualEffects`.
/// Glass, the window backdrop and scene-length motion read it through
/// [reduced]; a widget test that mounts a bare `MaterialApp` gets the full
/// effects, which is what those tests are photographing.
///
/// `00 · 1c` / `01 · 1k`: with the setting on, every glass layer becomes an
/// opaque surface of the same tone — blur, saturation, refraction edge and
/// inner shadow go — while layout, size and radius do not move by a pixel.
class AppEffects extends InheritedWidget {
  const AppEffects({
    super.key,
    required this.reduceVisualEffects,
    required super.child,
  });

  final bool reduceVisualEffects;

  /// Whether glass should render as its opaque fallback here.
  static bool reduced(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppEffects>()?.reduceVisualEffects ??
      false;

  @override
  bool updateShouldNotify(AppEffects oldWidget) =>
      oldWidget.reduceVisualEffects != reduceVisualEffects;
}
