import 'package:flutter/material.dart';

import 'app_effects.dart';

/// The geometry, alpha, type and motion ladders the widget library measures
/// against, instead of a literal number at each call site.
///
/// Source: Claude Design project "Joycai Image Tool", file `00 设计系统`
/// (the 2026-09 liquid-glass rewrite). Its closing mono block is the
/// authority; frame numbers below (`1d`, `1f`…) point into that file.
///
/// Nothing here stores a hue. Anything coloured is a [ColorScheme] role plus
/// an alpha from [AppAlpha], which is what lets one rule render in whichever
/// of the eight preset pairs — or a custom colour — the user picked. See
/// `docs/architecture/design-tokens.md`.

/// Corner radii.
///
/// `00 · 1d`: **one ladder serves radius and spacing** — 4 · 6 · 10 · 16 ·
/// 22 · 28 — and nested shapes are concentric: outer = inner + the 6px of
/// padding between them. A 10px control inside a 16px floating bar inside a
/// 22px sheet all share one centre of curvature. A value off the ladder is how
/// the previous system drifted to eleven radii.
///
/// Circles (status dots, switch thumbs, slider handles, radios) are not on the
/// ladder — they are 50% of their own box — and neither is [pill].
class AppRadius {
  /// Badges, chips, checkboxes, tiny corner labels over thumbnails.
  static const double xs = 4;

  /// A control *inside* a container: a segment inside its track, a menu row,
  /// a square piece inside a switch track.
  static const double sm = 6;

  /// Buttons, inputs, thumbnails and small cards — every control that sits in
  /// a row with another control.
  static const double control = 10;

  /// A container holding controls one step out from them: a segmented
  /// track. Equal to [control] on this ladder (a 28px segment at r6 inside a
  /// 2px inset track lands on 10 — the concentric rule, not a coincidence).
  static const double md = 10;

  /// Panels and the cards laid in a column, floating glass bars, popup menus,
  /// snackbars, the collapsed task capsule.
  static const double lg = 16;

  /// Dialogs, sheets' inner content, the expanded task capsule.
  static const double dialog = 22;

  /// The phone dock and a large sheet's top corners.
  static const double sheet = 28;

  /// Capsules — anything whose ends are semicircles by construction.
  static const double pill = 999;
}

/// Spacing, on the same ladder as [AppRadius] (`00 · 1d`).
class AppSpace {
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s10 = 10;
  static const double s16 = 16;
  static const double s22 = 22;
  static const double s28 = 28;
}

/// Control heights and icon sizes (`00` spec block, 「阶梯」).
///
/// Heights are a hard constraint, not a preference: a row mixing a button, an
/// icon button and a segmented control only reads as one row if they agree.
class AppSize {
  /// A standard control: labelled button, input, icon button, dropdown.
  static const double control = 32;

  /// A square icon action. The new spec draws these at the same 32 as a
  /// labelled button — a glyph and a verb sit on one baseline.
  static const double iconButton = 32;

  /// Compact: a segment inside a track, a button inside a toolbar strip or a
  /// card header.
  static const double compact = 28;

  /// A panel's single main call to action, a list row, a touch control.
  static const double large = 40;

  /// The floor for anything a finger has to hit on a phone.
  static const double touch = 44;

  /// Glyph beside small text, inside a badge or a chip.
  static const double iconSm = 14;

  /// Glyph beside a label inside a button.
  static const double iconMd = 16;

  /// A bare glyph in an icon button, a nav destination, a toolbar.
  static const double iconLg = 20;
}

/// The alphas the accent is allowed to be drawn at.
class AppAlpha {
  /// The 12% wash behind a selected thing (`00` 「主色 12% 底」).
  ///
  /// **Do not raise this past 0.14.** In dark mode the label on the wash is
  /// the accent's tone 80, and at 0.18 that pairing falls through 4.5:1. Light
  /// mode has an enormous margin and will not warn you.
  static const double tint = 0.12;

  /// The focus ring and a selected thing's edge (`--ring`).
  static const double ring = 0.32;

  /// A border that carries meaning on its own — a destructive outline.
  static const double edge = 0.5;

  /// Material's disabled tone, restated so call sites stop guessing.
  static const double disabled = 0.38;
}

/// The one dark ground the app pins *over* its content, and what reads on it.
///
/// Tooltips (`00 · 1f`) and the reduced-effects snackbar (`01 · 1k`) take the
/// same near-black in both brightnesses — no scheme role can do that, since
/// `inverseSurface` flips. It is the warm-stone ink, so it belongs to the
/// ramp rather than floating beside it.
class AppOverlay {
  /// `#1C1B18` — the light ramp's body ink.
  static const Color ink = Color(0xFF1C1B18);

  /// `#F2F0EA` — labels on [ink].
  static const Color onInk = Color(0xFFF2F0EA);

  /// The dark status red, which is what reads on [ink].
  static const Color danger = Color(0xFFF0655F);

  /// The fixed dark plate laid over user images — thumbnail size badges,
  /// RAW/AFTER, brush readouts (`A1` 「尺寸角标」, `A4–A6`). Never themed:
  /// eight of these on one screen should not each resolve a colour, and what
  /// sits under them is a photograph, not the app.
  static const Color imagePlate = Color(0xB8141310);

  /// Ink on [imagePlate].
  static const Color onImagePlate = Color(0xFFF2F0EA);
}

/// Type measurements the scale in `buildAppTheme` does not carry.
///
/// `00` names seven sizes and no others — 28/600 · 20/600 · 16/600 · 14/500 ·
/// 13/400 · 12/400 · 11/500 — plus mono at 12 and 11.
class AppType {
  /// Letter spacing for the 11/500 group caption (`SOURCES`, `模型选择`):
  /// `.06em` at 11px.
  static const double trackedLabelSpacing = 0.66;

  /// Tracking for UI text drawn at [fontSize], in logical pixels.
  ///
  /// A function of **size**, never of which slot asked: two slots at the same
  /// size must be spaced the same. Monotonic, opening up as text gets
  /// smaller; sizes between rungs interpolate.
  static double trackingFor(double fontSize) {
    const ladder = <(double size, double tracking)>[
      (10.0, 0.5),
      (11.5, 0.4),
      (12.0, 0.3),
      (13.0, 0.15),
      (14.0, 0.1),
      (16.0, 0.0),
    ];

    if (fontSize <= ladder.first.$1) return ladder.first.$2;
    if (fontSize >= ladder.last.$1) return ladder.last.$2;
    for (int i = 0; i < ladder.length - 1; i++) {
      final (lowSize, lowTrack) = ladder[i];
      final (highSize, highTrack) = ladder[i + 1];
      if (fontSize <= highSize) {
        final t = (fontSize - lowSize) / (highSize - lowSize);
        return lowTrack + (highTrack - lowTrack) * t;
      }
    }
    return ladder.last.$2;
  }

  /// Chat messages, rendered markdown, wrapped descriptions (`1.55` in the
  /// frames, rounded onto the step).
  static const double proseHeight = 1.5;

  /// Secondary copy meant to be skimmed.
  static const double looseHeight = 1.6;

  /// A wrapped label — a two-line filename under a thumbnail.
  static const double tightHeight = 1.3;

  /// A large figure set on its own.
  static const double displayHeight = 1.1;
}

/// The accent, in the three forms `00` allows and no fourth.
///
/// 1. **Solid** — `primary` under `onPrimary`: the main button. On a glass
///    bar the same form wears tinted glass instead ([AppTintedGlass]); it is
///    still the solid form, only the material changed.
/// 2. **Pure** — `primary` as a stroke, an icon, a switch's on track, a focus
///    ring.
/// 3. **12% wash + deep ink** — [accentTint] under [onAccentTint]: a selected
///    row. The deep ink is *also* every text button, link and group caption
///    (`--p-deep`), which is what lets a hue that cannot be read as text at
///    its fill tone (Orange in light) need no special case.
///
/// Success, warning and information are not accent and live in
/// `AppSemanticColors`.
extension AppAccent on ColorScheme {
  /// The 12% wash behind a selected or active element.
  Color get accentTint => primary.withValues(alpha: AppAlpha.tint);

  /// The 32% ring around a focused or selected element.
  Color get accentRing => primary.withValues(alpha: AppAlpha.ring);

  /// Tinted glass's fill (`gp`: `--p` at 74%) — the solid form on a glass bar.
  Color get accentGlassFill => primary.withValues(alpha: 0.74);

  /// The shadow tinted glass casts in its own hue (`--p` at 35%).
  Color get accentGlow => primary.withValues(alpha: 0.35);

  /// The accent *as text on a surface* — a text button, a link, a group
  /// caption, a live-status label.
  ///
  /// Always the deep ink (`00`: 「文字按钮与链接也用主色深」). `primary` is tuned
  /// to be a fill; the deep ink is tuned to be read.
  Color get accentText => onAccentTint;

  /// What a navigation item draws under itself when [selected].
  Color navBackground({required bool selected}) =>
      selected ? accentTint : Colors.transparent;

  /// The ink a navigation item draws when [selected] — the deep ink — and the
  /// quiet grey otherwise.
  Color navForeground({required bool selected}) =>
      selected ? onAccentTint : onSurfaceVariant;

  /// `--p-deep`: text and icons on [accentTint], and every accent-as-text.
  ///
  /// Same hue and chroma as the accent: tone 30 in light (darker than the
  /// fill), tone 80 in dark (lighter). `buildAppColorScheme` writes exactly
  /// those into the two roles read here.
  Color get onAccentTint =>
      brightness == Brightness.light ? onPrimaryFixedVariant : primaryFixedDim;

  /// The accent on a fixed dark ground — a snackbar's action label. `01 · 1d`
  /// draws it as the *dark half* of the pair, whatever the app's brightness.
  Color get accentOnOverlay => primaryFixedDim;
}

/// The shadows an opaque floating surface is allowed to cast.
///
/// Glass casts its own (see `app_glass.dart`); these are for the opaque
/// layers — a dialog, a drawer, a lifted card. The colour is always
/// `colorScheme.shadow`, which is the one colour that knows the brightness.
extension AppShadow on ColorScheme {
  /// A tile at rest in a grid.
  List<BoxShadow> get shadowResting => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.06),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// A segment lifted out of its track (`00 · 1f` 「分段」).
  List<BoxShadow> get shadowRaised => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.08),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// [shadowRaised] cast upward, for chrome anchored to the bottom edge.
  List<BoxShadow> get shadowRaisedUp => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.08),
          blurRadius: 4,
          offset: const Offset(0, -2),
        ),
      ];

  /// An opaque surface floating over scrolling content.
  List<BoxShadow> get shadowOverlay => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.12),
          blurRadius: 30,
          offset: const Offset(0, 10),
        ),
      ];

  /// Dialogs (`01 · 1h`: `0 24px 64px rgba(0,0,0,.28)`).
  List<BoxShadow> get shadowPanel => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.28),
          blurRadius: 64,
          offset: const Offset(0, 24),
        ),
      ];

  /// [shadowPanel] cast sideways, for a panel anchored to the right edge.
  List<BoxShadow> get shadowPanelSide => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.20),
          blurRadius: 30,
          offset: const Offset(-8, 0),
        ),
      ];
}

/// Motion tokens (`00 · 1e`): three durations and one exception.
///
/// - **M1 · 100ms, ease-out** — hover, select/deselect, glass press, focus
///   ring. The only band high-frequency interaction may use.
/// - **M2 · 180ms, (.2,.8,.2,1)** — the segment lens sliding, switches, chips
///   entering and leaving, menus opening, toolbar items degrading.
/// - **M3 · 280ms, (.32,.72,0,1), exit ×0.6** — sheets, floating bars
///   entering and leaving, the task capsule morphing, dialogs.
/// - **Exception** — switching navigation destinations has no transition, and
///   the running status dot's 1.6s breath is the only loop.
///
/// With *reduce visual effects* on, M3 falls to M2, the loop stops and glass
/// morphs become cuts ([sceneOf], [breathes]).
class AppMotion {
  /// M1.
  static const Duration hover = Duration(milliseconds: 100);

  /// M2.
  static const Duration state = Duration(milliseconds: 180);

  /// M2 — disclosure and reveal share the state band in this system.
  static const Duration reveal = Duration(milliseconds: 180);

  /// M3.
  static const Duration panel = Duration(milliseconds: 280);

  /// The running dot's breath period.
  static const Duration breath = Duration(milliseconds: 1600);

  /// How much faster an M3 exit runs than its entrance.
  static const double exitFactor = 0.6;

  /// M1's curve.
  static const Curve quick = Cubic(0, 0, 0.2, 1);

  /// M2's curve. Also the default for entrances and state changes.
  static const Curve enter = Cubic(0.2, 0.8, 0.2, 1);

  /// M3's curve.
  static const Curve emphasized = Cubic(0.32, 0.72, 0, 1);

  /// On-screen movement whose both endpoints are visible.
  static const Curve move = Curves.easeInOutCubic;

  /// Whether the platform has been asked for less motion.
  ///
  /// Distinct from the app's own *reduce visual effects*
  /// ([AppEffects.reduced]), which governs translucency.
  static bool prefersReduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// [token], or no duration at all where the platform has asked for less
  /// motion. Every `duration:` in the app goes through this.
  static Duration durationOf(BuildContext context, Duration token) =>
      prefersReduced(context) ? Duration.zero : token;

  /// M3 for a scene change, stepped down to M2 under reduce-visual-effects,
  /// and to nothing under the platform's reduce-motion.
  static Duration sceneOf(BuildContext context) => durationOf(
        context,
        AppEffects.reduced(context) ? state : panel,
      );

  /// Whether the running dot may breathe.
  static bool breathes(BuildContext context) =>
      !prefersReduced(context) && !AppEffects.reduced(context);
}
