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

/// The one dark ground the app pins *over* its content, and what reads on it.
///
/// Tooltips (`10e`) and toasts (`E1 12i`) are the two things in this app that
/// are not surfaces within the page but labels laid on top of it, and both
/// specs say the same thing about them: light and dark take the **same**
/// ground. No scheme role can do that — `inverseSurface` is the idiomatic
/// choice and it flips with the brightness — so the ink is a literal, and the
/// hues that sit on it have to be pinned alongside it or they would flip while
/// it did not.
///
/// A toast painted in the semantic *containers* instead — a pale green slab,
/// then a pale amber one — is what this replaced. Four differently coloured
/// blocks floating over the page read as four unrelated components; one ground
/// with a coloured glyph reads as one component in four states, which is what
/// it is.
class AppOverlay {
  /// The ground. `10e` pins it at `rgba(23,28,59,.94)`.
  static const Color ink = Color(0xF0171C3B);

  /// Labels on [ink]. Not pure white: at 94% it stops vibrating against a
  /// near-black at small sizes, which is the size these labels are.
  static const Color onInk = Color(0xF0FFFFFF);

  /// Red on [ink].
  ///
  /// The one state hue [AppSemanticColors] has no field for — everywhere else
  /// the app takes red from [ColorScheme.error], which is tone 40 in light
  /// mode and would all but vanish here. Success, info and warning need no
  /// equivalent: [AppSemanticColors.dark] already holds them at exactly the
  /// tones `12i` draws, and they are correct on this ground whatever the app's
  /// brightness.
  static const Color danger = Color(0xFFE26355);
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
  ///
  /// This is a *deliberate* opening-up, for a caption set in caps that is
  /// naming a group. It is not on the [trackingFor] ladder and must not be
  /// used as though it were: a run of body text at 1.0 is not tracked, it is
  /// broken.
  static const double trackedLabelSpacing = 1.0;

  /// Tracking for UI text drawn at [fontSize], in logical pixels.
  ///
  /// Letter spacing is a function of **size**, never of which slot happened to
  /// ask. That is the rule the app was breaking in three places at once, and
  /// the reason this is a ladder rather than a value per slot.
  ///
  /// The scale in [buildAppTheme] sets size and weight and left tracking to
  /// Material, whose values are tuned to *Material's* sizes — all of which
  /// this app moved. What actually shipped:
  ///
  /// | size | slots | tracking |
  /// |---|---|---|
  /// | 16 | `titleLarge`, `bodyLarge` | **0.0 and 0.5** |
  /// | 14 | `titleMedium` | 0.15 |
  /// | 13 | `titleSmall`, `labelLarge`, `bodyMedium` | **0.1 and 0.25** |
  /// | 12 | `bodySmall` | 0.4 |
  /// | 11.5 | `labelMedium` | 0.5 |
  /// | 10 | `labelSmall` | **0.5 — the same as 11.5** |
  ///
  /// Two collisions (the same size set two ways depending on the slot name)
  /// and one flat step at the bottom, where tracking should be opening up
  /// fastest. A 16px heading and a 16px paragraph are the same letters at the
  /// same size; nothing about the slot they came from should move them apart.
  ///
  /// The ladder below is monotonic and runs the right way: ~0 at the top of
  /// the scale, opening steadily as the text gets smaller, because small text
  /// needs the air and large text reads as loose if it keeps it. In em that is
  /// 0 · .007 · .012 · .025 · .035 · .05. Sizes off the ladder interpolate
  /// between their neighbours rather than snapping, so a slot added at 15px
  /// does not land on a step by luck.
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

  /// Line height for a paragraph of prose — a chat message, a rendered
  /// markdown body, a wrapped description.
  ///
  /// The app had ten hand-typed heights between 1.3 and 1.5, including a 1.45
  /// sitting alone between the two values either side of it. Two steps, each
  /// with one job, the same way [AppAlpha] has four.
  static const double proseHeight = 1.4;

  /// Line height for prose that wants more air — secondary copy the eye is
  /// meant to skim rather than read straight through.
  static const double looseHeight = 1.5;

  /// Line height for a wrapped *label*: a two-line filename under a thumbnail,
  /// a caption in a dense grid. Tighter than [proseHeight] because the lines
  /// are a single phrase broken in two, not a paragraph.
  static const double tightHeight = 1.3;

  /// Line height for a large figure set on its own — the headline numbers on
  /// the usage screen.
  ///
  /// The bottom of the same rule [trackingFor] encodes: leading runs *against*
  /// size. Small text needs air between its lines; a 30px number given the
  /// same ratio floats in a box half again as tall as it needs, and reads as
  /// misaligned with whatever it is labelled by.
  static const double displayHeight = 1.1;
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

  /// The seed's own colour, at a tone that reads on [AppOverlay.ink] — a
  /// toast's action label.
  ///
  /// `primaryFixedDim` for the reason the table above already establishes: the
  /// `Fixed` roles are pinned by definition and do not move with the
  /// brightness, and this one is tone 80. That is exactly what a fixed dark
  /// ground needs, and it is the *only* accent role that stays put while the
  /// ground it sits on does.
  Color get accentOnOverlay => primaryFixedDim;
}

/// The shadows a floating surface is allowed to cast.
///
/// Before this extension the app drew ten hand-typed shadows: six already on
/// `colorScheme.shadow` at almost-monotonic strengths (.05 → .20), and four on
/// `Colors.black` literals — which the theme itself warns about ("on a
/// near-black canvas a grey shadow is invisible"): the scheme's shadow role is
/// the one colour that knows what brightness it is being cast in, a black
/// literal is not. Quantised to four rungs the same way [AppRadius] and
/// [AppAlpha] are, plus two direction variants for edge-anchored chrome.
///
/// Not this ladder's business: anything *coloured* — the accent glow on a
/// selected card, a CTA's tinted lift, chips sitting on user photographs.
/// Those say something (selection, commitment, legibility over an image) that
/// a neutral depth cue does not, and they keep their own values.
extension AppShadow on ColorScheme {
  /// A tile at rest in a grid. Just enough lift to read as laid on the mesh
  /// rather than punched through it.
  List<BoxShadow> get shadowResting => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// A selected chip lifted out of its strip: a raised segment, a toggle
  /// pill. One step above the row it sits in.
  List<BoxShadow> get shadowRaised => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.08),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  /// [shadowRaised] cast upward, for chrome anchored to the bottom edge — a
  /// mobile toolbar casts onto the content above it.
  List<BoxShadow> get shadowRaisedUp => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.08),
          blurRadius: 4,
          offset: const Offset(0, -2),
        ),
      ];

  /// A bar or capsule floating over scrolling content: the task capsule, a
  /// selection action bar, a canvas overlay, a sticky composer.
  List<BoxShadow> get shadowOverlay => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// The largest floating surfaces — the ones that read as *thick*: an edge
  /// panel's sheet, the mask editor's lifted canvas. Bigger surfaces cast
  /// deeper, which is what keeps a 450px panel from reading as a chip.
  List<BoxShadow> get shadowPanel => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.20),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// [shadowPanel] cast sideways, for a panel anchored to the window's right
  /// edge casting onto the work beside it.
  List<BoxShadow> get shadowPanelSide => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.20),
          blurRadius: 24,
          offset: const Offset(-6, 0),
        ),
      ];
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

  /// Whether the platform has been asked for less motion — macOS's *Reduce
  /// motion*, Windows' *Show animations in Windows*, Android's *Remove
  /// animations*, iOS's *Reduce Motion*.
  ///
  /// Distinct from `AppState.reduceVisualEffects`, which is the app's own
  /// setting and governs *translucency* (the title bar's backdrop blur) rather
  /// than movement. They answer two different accessibility preferences and
  /// the platform exposes them separately; a user who cannot tolerate motion
  /// has not thereby asked to lose the frosted glass, and vice versa.
  static bool prefersReduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// [token], or no duration at all where the platform has asked for less
  /// motion.
  ///
  /// Every `duration:` in the app goes through this. Reaching for the raw
  /// token at a call site is now the drift, the same way a literal `160` was
  /// before the tokens existed.
  ///
  /// Collapsing to zero rather than merely shortening is deliberate: what
  /// makes motion a problem is the travel, not its length, and a 40ms slide is
  /// a slide. The end state is identical and arrives immediately, so nothing
  /// is lost but the journey — which is exactly what was asked for. Where a
  /// transition carries *meaning* that a cut would destroy — a panel that has
  /// to be seen arriving from somewhere — swap the transition itself for a
  /// cross-fade instead, keyed off [prefersReduced]; [AppSidePanel] is the
  /// worked example.
  static Duration durationOf(BuildContext context, Duration token) =>
      prefersReduced(context) ? Duration.zero : token;
}
