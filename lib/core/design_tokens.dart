import 'package:flutter/material.dart';

/// The geometry and accent-tint ladders the widget library measures against,
/// instead of a literal number at each call site.
///
/// These come from the *Joycai 设计规范* sheet. That sheet is drawn once, in
/// a single blue — but the seed is the user's to pick, so nothing here stores
/// a hue.
/// Geometry is absolute; anything coloured is expressed as a role on the
/// ambient [ColorScheme] plus an alpha from [AppAlpha], which is what lets the
/// same rule render in whichever colour the user picked. See
/// `docs/architecture/design-tokens.md` for the full mapping.

/// Corner radii.
///
/// The spec draws eleven distinct radii (5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
/// 16). Most of those differences are a pixel or two and read as noise rather
/// than as a system — 7 and 9 sit either side of 8 on the *same* control, the
/// segmented track and the chip inside it. Quantised to five steps plus
/// [pill]: the spec's 5–7 collapse to [xs], 8–9 to [control], 10–11 to [md],
/// 13–14 to [lg], 16 to [dialog].
///
/// The restyle moved exactly one of these, [dialog]. Twice now §1's table has
/// disagreed with what the frames actually draw, and both times the frames
/// were right: it tabulates 按钮·输入·下拉 at 10px where every frame draws 8,
/// and its 窗口·大卡片 row means the window frame rather than the cards inside
/// it. Read the table for orientation, take the number off a frame.
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
  ///
  /// This was briefly moved to 14 on the strength of the spec's 窗口·大卡片
  /// row. That row means the **window frame**: 14 is the radius of the 1400×900
  /// rounded rectangle each page mockup is drawn inside, and it is the only 14
  /// in any of them. The panels *within* that window are drawn at 10–12 — 12 in
  /// `D1`'s two settings cards, 10–11 in `10c`. So this stays at 12, where it
  /// already was.
  static const double lg = 12;

  /// Dialog surfaces. The one shape allowed to be rounder than a card, because
  /// it floats over everything rather than sitting in the grid with it.
  ///
  /// 16 since the restyle, up from 14 — `E1`'s `12i` frame draws the dialog
  /// shell at 16, and §1's 弹窗容器 row agrees. Unlike [lg] this one really did
  /// move: it is now two steps clear of a card rather than one, which is what
  /// the spec wants a dialog to look like.
  static const double dialog = 16;

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

/// Type measurements the scale in [buildAppTheme] does not carry.
class AppType {
  /// Letter spacing for the small tracked caption that names a group of
  /// controls — see [AppSectionLabel].
  ///
  /// The spec writes it as `.08em`, which on its 12px caption is 0.96px. The
  /// app's `labelMedium` is 11.5px, so the same ratio would be 0.92; rounded to
  /// 1.0, which is what the workbench copy already used and what the eye reads
  /// as "tracked" at this size either way.
  static const double trackedLabelSpacing = 1.0;
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
  /// Two things fall out, both true at every seed:
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

/// Motion tokens. One duration per job, one curve per direction of travel —
/// not per hand-typed value. Before this class the app had nine durations
/// (90–350ms) and three curves doing four jobs, 19 sites shipping Flutter's
/// default `Curves.linear`. The ladder is quantised the same way AppRadius
/// and AppAlpha are: using a value not on it is how motion drifts.
class AppMotion {
  /// Hover / focus micro-feedback. Short enough to feel attached to the
  /// pointer; anything longer trails it.
  static const Duration hover = Duration(milliseconds: 120);

  /// Selection state: card borders, chip fills, segment pills. 160 sits in
  /// the press-feedback band (100–160ms) — selection is feedback, not a scene
  /// change, and grids animate many tiles at once (Ctrl+A), so shorter is
  /// calmer.
  static const Duration state = Duration(milliseconds: 160);

  /// Disclosure and reveal: expand/collapse, crossfades, overlay fades.
  static const Duration reveal = Duration(milliseconds: 200);

  /// Panels and paging: drawers, side panels, wizard pages. Top of the UI
  /// budget; nothing in the app should exceed this.
  static const Duration panel = Duration(milliseconds: 300);

  /// Entrances, exits and state changes — starts fast, lands softly, so the
  /// change registers the moment it begins. Never use easeIn on UI.
  static const Curve enter = Curves.easeOutCubic;

  /// On-screen movement (width morphs, page slides): accelerates and
  /// decelerates because both endpoints are visible.
  static const Curve move = Curves.easeInOutCubic;
}
