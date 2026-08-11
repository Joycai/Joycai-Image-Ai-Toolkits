import 'package:flutter/material.dart';

/// The geometry and accent-tint ladders the widget library measures against,
/// instead of a literal number at each call site.
///
/// These come from the *Joycai 设计规范* sheet. That sheet is drawn once, in
/// teal — but the app ships seven seed colours, so nothing here stores a hue.
/// Geometry is absolute; anything coloured is expressed as a role on the
/// ambient [ColorScheme] plus an alpha from [AppAlpha], which is what lets the
/// same rule render in whichever colour the user picked. See
/// `docs/architecture/design-tokens.md` for the full mapping.

/// Corner radii.
///
/// The spec draws eleven distinct radii (5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
/// 16). Most of those differences are a pixel or two and read as noise rather
/// than as a system — 7 and 9 sit either side of 8 on the *same* control, the
/// segmented track and the chip inside it. Quantised to six steps: the spec's
/// 5–7 collapse to [xs]/[control], 9–11 to [md]/[lg], 13–16 to [lg]/[dialog].
class AppRadius {
  /// Checkboxes and other ~18px boxes, where [control] would round a small
  /// square into a blob.
  static const double xs = 6;

  /// The app's default. Buttons, inputs, icon buttons, tool tabs, log bars —
  /// every control that sits in a row with another control.
  static const double control = 8;

  /// Containers holding controls: a segmented track, a nav rail item, an
  /// inline info box. One step out from what it wraps.
  static const double md = 10;

  /// Cards and panels.
  static const double lg = 12;

  /// Dialog surfaces. The one shape allowed to be rounder than a card, because
  /// it floats over everything rather than sitting in the grid with it.
  static const double dialog = 14;

  /// Status badges and any other capsule. Far past half the height of anything
  /// it is used on, which is what makes the ends semicircular.
  static const double pill = 999;
}

/// Control heights and icon sizes.
///
/// Heights are a hard constraint, not a preference: a row mixing a button, an
/// icon button and a segmented control only reads as one row if they agree.
class AppSize {
  /// A labelled button. The spec draws 34 on the component sheet and 36 in the
  /// dialog footers; 36 is taken as the single value because it is the more
  /// common of the two in the page mockups and leaves a usable touch target.
  static const double control = 36;

  /// A square icon action. Deliberately two pixels under [control] — the spec
  /// sets them apart so a bare glyph doesn't read as heavy as a labelled verb.
  static const double iconButton = 32;

  /// A button inside a popup, a slim toolbar strip or a card footer.
  static const double compact = 30;

  /// A sheet's committing action, or a panel's single main call to action.
  static const double large = 48;

  /// Glyph inside an [iconButton]-sized box, and beside a [compact] label.
  static const double iconSm = 16;

  /// Glyph beside a [control]-sized label.
  static const double iconMd = 18;

  /// Glyph beside a [large] label, and in a nav rail item.
  static const double iconLg = 20;
}

/// The alphas the accent is allowed to be drawn at.
///
/// The spec reaches for eleven (.08 through .60), which is more precision than
/// any of them earn — .10 and .12 appear on the same kind of surface two cards
/// apart. Four steps, each with one job. Using a value not on this ladder is
/// how the app drifted the first time.
class AppAlpha {
  /// A selected thing's background: an active tool tab, a nav rail item, a
  /// status badge, a dialog's icon plate.
  ///
  /// **Do not raise this past 0.14.** In dark mode the label on such a tint is
  /// [AppAccent.onAccentTint] (tone 80), and the tint is what sits behind it:
  /// at 0.12 that pairing computes to ~4.9:1, at 0.14 to ~4.6:1, and by 0.18
  /// it has fallen through 4.5:1 and fails AA. Light mode has an enormous
  /// margin (~8:1) and will not warn you — the failure is dark-only, and the
  /// obvious "make the selection more visible" nudge is what causes it.
  static const double tint = 0.12;

  /// The edge or focus ring around a selected thing. Reads as an outline at
  /// this strength without competing with the label inside it.
  static const double ring = 0.32;

  /// A border that carries meaning on its own — the outline of a destructive
  /// button, or the depth of a primary button's coloured shadow.
  static const double edge = 0.5;

  /// Material's own disabled tone, restated so call sites stop guessing.
  static const double disabled = 0.38;
}

/// The accent, in the three forms the design spec actually uses it.
///
/// This is the whole multi-theme rule in one place. The spec shows a single
/// teal, but never as an arbitrary hex — it appears as a solid fill, as a
/// wash behind something selected, and as text sitting on that wash. Each maps
/// to a [ColorScheme] role, so swapping the seed re-renders the same structure
/// in the new hue rather than breaking it.
///
/// Anything that means *success*, *warning* or *information* is not accent and
/// must not come from here — those keep their meaning across themes and live
/// in `AppSemanticColors`. Destructive is [ColorScheme.error], whose palette
/// [ColorScheme.fromSeed] already derives independently of the seed.
extension AppAccent on ColorScheme {
  /// The wash behind a selected or active element.
  Color get accentTint => primary.withValues(alpha: AppAlpha.tint);

  /// The edge around that element, and the glow ring on a focused input.
  Color get accentRing => primary.withValues(alpha: AppAlpha.ring);

  /// Text and icons drawn *on* [accentTint].
  ///
  /// The spec's 主色深 is a tone *near* the accent, not a near-black: measured
  /// off the sheet, light is `#0B6E64` ≈ tone 41 against a `#12897C` ≈ tone 51
  /// accent, and dark is `#4ECDC0` ≈ tone 76 against `#3FC1B0` ≈ tone 71. Ten
  /// tones of separation, so the label still reads *as the accent*.
  ///
  /// Measured against the SDK rather than reasoned from the tone tables, which
  /// have churned across Material revisions. What
  /// [ColorScheme.fromSeed] actually returns today, at teal:
  ///
  /// | | `primary` | `onPrimaryContainer` | `onPrimaryFixedVariant` | `primaryFixedDim` |
  /// |---|---|---|---|---|
  /// | light | `#006A60` | `#005048` | `#005048` | `#82D5C8` |
  /// | dark  | `#82D5C8` | `#9EF2E4` | `#005048`   | `#82D5C8` |
  ///
  /// Two things fall out, both true at all seven seeds:
  ///
  /// - In **dark**, `primaryFixedDim` is *exactly* [primary]. Using it would
  ///   make the label one tone reading against its own tint — the precise
  ///   failure this getter exists to prevent. `onPrimaryContainer` is a step
  ///   lighter than the accent, which is what dark mode needs.
  /// - In **light**, the two candidates are *identical*. The `Fixed` role is
  ///   taken anyway because its tone is pinned by definition, where
  ///   `onPrimaryContainer`'s is a brightness-dependent assignment that
  ///   Material has already moved once (it was near-black at tone 10 for a
  ///   spell, which on a 12% wash reads as plain dark text, not as the accent).
  ///   Same pixels today, insured against that revision returning.
  ///
  /// No per-seed tuning is needed because in HCT tone *is* L\*, so relative
  /// luminance is fixed regardless of hue — a contrast figure measured on teal
  /// is the same figure on orange. `design_tokens_test` asserts it for every
  /// seed in both brightnesses rather than trusting that.
  Color get onAccentTint =>
      brightness == Brightness.light ? onPrimaryFixedVariant : onPrimaryContainer;
}
