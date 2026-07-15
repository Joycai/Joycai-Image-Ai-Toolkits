import 'package:flutter/material.dart';

/// Corner radius shared by buttons and the boxed controls beside them, so a
/// header of mixed shapes still reads as one row.
///
/// Kept well under half a button's height on purpose: at half, a rounded rect
/// becomes a capsule, and 12 on the ~30px buttons this app renders was close
/// enough to read as one.
const double appButtonRadius = 10;

/// Height of a filled button, matching the boxed icon actions it sits next to.
///
/// Held by pinning visual density as well as the minimum size: on desktop
/// Material defaults to compact, which quietly subtracts 8px from a button's
/// minimum height. That left these ~30px tall, and at 30 a 10px corner is two
/// thirds of the way to a capsule — which is exactly what they looked like.
const double appButtonMinHeight = 38;

/// The app's theme, built from the seed colour the user picked in settings.
///
/// Everything here is derived from that seed rather than hard-coded, so a
/// button stays the user's colour and not a designer's.
ThemeData buildAppTheme({
  required Color seedColor,
  required Brightness brightness,
  String? fontFamily,
}) {
  final colorScheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  final fill = buttonFillScheme(seedColor);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: fill.primary,
        foregroundColor: fill.onPrimary,
        // Material's own disabled tones. They have to be spelled out: naming a
        // background in a theme replaces the default's whole state machine, and
        // a disabled button with no colour of its own paints nothing at all.
        disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        // A shadow in the button's own hue: on a near-black canvas a grey
        // shadow is invisible, and the lift is what separates the one button
        // that commits from the text beside it that cancels.
        elevation: 2,
        shadowColor: fill.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
        minimumSize: const Size(0, appButtonMinHeight),
        visualDensity: VisualDensity.standard,
      ),
    ),
  );
}

/// The scheme a primary button takes its fill and label from.
///
/// Two things ail the default. Material's dark scheme pairs a pale `primary`
/// with a dark `onPrimary`, so a filled button comes out a washed-out lavender
/// slab; and `tonalSpot`, the default palette, caps chroma — so *no* tone of it
/// is vivid, in either theme. Together they make the one button that commits to
/// something the greyest thing on the screen.
///
/// The fill therefore comes from a light `vibrant` scheme in both themes:
/// vibrant maxes colourfulness at the seed's own hue, and light puts white on
/// it. Both halves still come from one scheme, so the label keeps the contrast
/// Material computes for it — which a hand-picked "brighter purple" under white
/// would not, at any seed the user might pick.
ColorScheme buttonFillScheme(Color seedColor) {
  return ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  );
}

/// The colours [FilledButton.tonal] is supposed to have.
///
/// Pass this to every tonal button: the app-wide [FilledButtonTheme] above
/// names a background for *all* filled buttons, and a theme's background
/// outranks the tonal variant's own default. Without this a tonal button comes
/// out fully primary-filled — no error, just a secondary action shouting.
ButtonStyle tonalButtonStyle(ColorScheme colorScheme) {
  return FilledButton.styleFrom(
    backgroundColor: colorScheme.secondaryContainer,
    foregroundColor: colorScheme.onSecondaryContainer,
    disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
    disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
    elevation: 0,
  );
}
