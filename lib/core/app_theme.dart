import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'design_tokens.dart';

/// Corner radius shared by buttons and the boxed controls beside them, so a
/// header of mixed shapes still reads as one row.
///
/// Kept well under half a button's height on purpose: at half, a rounded rect
/// becomes a capsule, and 12 on the ~30px buttons this app renders was close
/// enough to read as one. The design spec draws 8, which at the heights below
/// is squarer still — so the reasoning holds, only the number moved. Aliased
/// rather than replaced: 35 call sites already import this name.
const double appButtonRadius = AppRadius.control;

/// Height of a filled button, matching the boxed icon actions it sits next to.
///
/// Held by pinning visual density as well as the minimum size: on desktop
/// Material defaults to compact, which quietly subtracts 8px from a button's
/// minimum height. That left these ~30px tall, and at 30 a 10px corner is two
/// thirds of the way to a capsule — which is exactly what they looked like.
///
/// The spec's icon buttons are two pixels shorter than its labelled ones, so
/// [AppIconButton] no longer defaults to this; see [AppSize.iconButton].
const double appButtonMinHeight = AppSize.control;

/// The neutral ramp the whole app sits on — one set per brightness, shared
/// by every seed.
///
/// Until the restyle these came from a *monochrome* [ColorScheme.fromSeed]:
/// true greys, zero chroma. That rule was really two rules stacked, and only
/// one of them was load-bearing. The one that was: the ramp must not move
/// when the seed does, or every surface tuned against one seed is wrong at
/// the next, and an element that is *actually* the accent has nothing left to
/// say. The one that wasn't: that the greys be neutral. The new spec's are
/// deliberately cool — its canvas is `#ECEFF8` and its body text `#171C3B`,
/// both several points of blue off grey — and that tint is the look. It is
/// fixed here, so it stays exactly the same blue when the user picks orange;
/// it is not the seed hue leaking into the background, which is the failure
/// the monochrome scheme was guarding against.
///
/// The roles are named for the job this app gives them, not for Material's
/// ordering:
///
/// - [surfaceContainer] is the **canvas** a screen paints behind everything.
/// - [surface] is a **panel** floating on that canvas — one step *up* in
///   both brightnesses, so a panel is lighter than the canvas in light and
///   also lighter than it in dark. Material's dark scheme has these the other
///   way round; the spec's `10b` frame draws 背景 `#0E131F` under 表面
///   `#192132`, and the design wins here.
/// - [surfaceContainerHigh] is a **card sitting on a panel** (see [AppCard]),
///   one more step away from the panel — which means darker in light and
///   lighter in dark. That is the reason this is a hand-written table and not
///   a monotonic ladder.
/// - [surfaceContainerHighest] is a **filled control track**: a text field's
///   fill, a switch's off state.
class _Neutrals {
  const _Neutrals({
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.surfaceTint,
  });

  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color surfaceTint;

  /// Spec `10a`, and the values the page mockups actually paint.
  ///
  /// `outlineVariant` is the sheet's `#DBE0EF` input border rather than the
  /// paler `#E4E8F4` it uses for an icon button's edge, because this role is
  /// also every hairline divider in the app — at `#E4E8F4` a divider is a
  /// point and a half off the panel it sits on and simply disappears.
  static const light = _Neutrals(
    surface: Color(0xFFF5F7FD),
    surfaceDim: Color(0xFFE6EAF5),
    surfaceBright: Color(0xFFFAFBFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAFBFF),
    surfaceContainer: Color(0xFFECEFF8),
    surfaceContainerHigh: Color(0xFFE6EAF5),
    surfaceContainerHighest: Color(0xFFDFE5F4),
    onSurface: Color(0xFF171C3B),
    onSurfaceVariant: Color(0xFF4D5470),
    outline: Color(0xFFC0C6D8),
    outlineVariant: Color(0xFFDBE0EF),
    inverseSurface: Color(0xFF232B4A),
    onInverseSurface: Color(0xFFECEFF8),
    surfaceTint: Color(0xFF868DA8),
  );

  /// Derived from [light], not copied from the sheet.
  ///
  /// The spec's `10b` frame was never restyled — its accent is still the old
  /// teal and its greys are still tinted green — so the only part of it worth
  /// taking is the surface ladder `#0E131F` / `#192132` / `#28354C`, which
  /// *is* already the new blue. Everything else here is [light]'s structure
  /// mapped onto that ladder: the same steps, the same hue, inverted. Replace
  /// this wholesale if `10b` is ever redrawn.
  static const dark = _Neutrals(
    surface: Color(0xFF192132),
    surfaceDim: Color(0xFF0B0F1A),
    surfaceBright: Color(0xFF2A354B),
    surfaceContainerLowest: Color(0xFF090D16),
    surfaceContainerLow: Color(0xFF131A28),
    surfaceContainer: Color(0xFF0E131F),
    surfaceContainerHigh: Color(0xFF212B3F),
    surfaceContainerHighest: Color(0xFF28334A),
    onSurface: Color(0xFFE6EAF5),
    onSurfaceVariant: Color(0xFFA3ABC2),
    outline: Color(0xFF5C6784),
    outlineVariant: Color(0xFF28354C),
    inverseSurface: Color(0xFFE6EAF5),
    onInverseSurface: Color(0xFF171C3B),
    surfaceTint: Color(0xFF79809A),
  );
}

/// The app's palette: accents from the user's seed, greys from [_Neutrals].
///
/// [ColorScheme.fromSeed] tints *every* role with the seed's hue, greys
/// included — pick teal and every panel, border and body line comes out
/// faintly teal. Two things go wrong with that. The greys shift underneath
/// the whole app each time the seed changes, so any surface tuned to look
/// right against one seed is wrong at the next; and with the accent hue
/// already in the background, an element that is *actually* the accent
/// colour — selected, focused, pressed — has less left to say.
///
/// So the neutral roles are overwritten with the fixed ramp instead. The
/// seeded scheme still supplies primary/secondary/tertiary/error and their
/// containers, so the accent survives exactly where it should: on things the
/// user acts on.
ColorScheme buildAppColorScheme({
  required Color seedColor,
  required Brightness brightness,
}) {
  final seeded = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  final neutral = brightness == Brightness.dark ? _Neutrals.dark : _Neutrals.light;

  return seeded.copyWith(
    surface: neutral.surface,
    surfaceDim: neutral.surfaceDim,
    surfaceBright: neutral.surfaceBright,
    surfaceContainerLowest: neutral.surfaceContainerLowest,
    surfaceContainerLow: neutral.surfaceContainerLow,
    surfaceContainer: neutral.surfaceContainer,
    surfaceContainerHigh: neutral.surfaceContainerHigh,
    surfaceContainerHighest: neutral.surfaceContainerHighest,
    onSurface: neutral.onSurface,
    onSurfaceVariant: neutral.onSurfaceVariant,
    outline: neutral.outline,
    outlineVariant: neutral.outlineVariant,
    inverseSurface: neutral.inverseSurface,
    onInverseSurface: neutral.onInverseSurface,
    // Material paints this over any elevated surface. Left seeded it would
    // put the hue back into the very greys this function just took it out of.
    surfaceTint: neutral.surfaceTint,
  );
}

/// The app's theme, built from the seed colour the user picked in settings.
///
/// Accents are derived from that seed rather than hard-coded, so a button
/// stays the user's colour and not a designer's. Greys deliberately are not —
/// see [buildAppColorScheme].
ThemeData buildAppTheme({
  required Color seedColor,
  required Brightness brightness,
  String? fontFamily,
}) {
  final colorScheme = buildAppColorScheme(seedColor: seedColor, brightness: brightness);
  final fill = buttonFillScheme(seedColor);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    textTheme: _buildTextTheme(colorScheme, fontFamily),
    extensions: [
      brightness == Brightness.dark ? AppSemanticColors.dark : AppSemanticColors.light,
    ],
    // The sub-themes below exist because of where the app's controls actually
    // come from. There are ~40 bare `TextField`s and ~24 bare `Switch`/
    // `Checkbox`es scattered across the screens, none of them routed through a
    // shared widget — so a component is the wrong lever for those and the
    // theme is the right one. Styling them here reaches every call site
    // without touching any of them.
    inputDecorationTheme: _buildInputDecorationTheme(colorScheme),
    switchTheme: _buildSwitchTheme(colorScheme),
    checkboxTheme: _buildCheckboxTheme(colorScheme),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      // `.copyWith` on top of `styleFrom`, because `styleFrom` has no
      // `disabledElevation`: it lifts the button in *every* state, disabled
      // included. Paired with the accent `shadowColor` below, a disabled
      // button was casting a full-strength glow in the user's own theme
      // colour — on a dark canvas it read as a ring around the button, making
      // the one control that does nothing the loudest thing in the row.
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
      ).copyWith(
        elevation: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? 0 : 2,
        ),
      ),
    ),
    // The other two button types need the same shape, or the library's own
    // abstraction leaks: AppButton's `text` and `destructiveOutline` variants
    // are built on TextButton and OutlinedButton, and with no theme of their
    // own they keep Material 3's StadiumBorder. A row of Reset / Overwrite /
    // Save then renders as two pills beside a rounded rectangle — the shared
    // component is being used, but the theme never reaches through it.
    //
    // Only geometry is set here. Foreground colour is deliberately left to
    // Material, so a dialog's "Cancel" keeps the accent tint it is supposed
    // to have; a button that wants to be quiet says so at its call site.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
        minimumSize: const Size(0, appButtonMinHeight),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.6)),
        visualDensity: VisualDensity.standard,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
        minimumSize: const Size(0, appButtonMinHeight),
        visualDensity: VisualDensity.standard,
      ),
    ),
  );
}

/// The spec's input: a hairline box on the surface, not a grey slab.
///
/// This reverses a decision [AppTextField] documents — it fills with
/// `surfaceContainerHighest` so inputs and the segmented control's track read
/// as one system. Worth recording why the reversal is right rather than just
/// deferential to the spec: that pairing only ever governed two call sites,
/// because `AppTextField` was never adopted (`api_key_field.dart` is its only
/// user). The other ~40 inputs in the app are bare `TextField`s rendering
/// Material's stock outlined default. So the app already ships an outlined
/// input almost everywhere, and adopting the spec here makes it *more*
/// internally consistent, not less.
///
/// The focus glow the spec draws around a focused field — a 3px accent ring
/// outside the border — is not expressible through [InputDecoration], which
/// owns only the border itself. [AppTextField] draws it; a bare `TextField`
/// gets the 1.5px accent border below and no halo.
InputDecorationTheme _buildInputDecorationTheme(ColorScheme colorScheme) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecorationTheme(
    filled: false,
    isDense: true,
    // Tighter than Material's default, which budgets for a floating label on
    // every field. Most of this app's inputs sit in dense config panels and
    // carry a separate label above them instead.
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: border(colorScheme.outlineVariant, 1),
    enabledBorder: border(colorScheme.outlineVariant, 1),
    // A disabled field keeps its box — without one it reads as a gap in the
    // form rather than as a control that is temporarily unavailable.
    disabledBorder: border(colorScheme.outlineVariant.withValues(alpha: AppAlpha.disabled), 1),
    focusedBorder: border(colorScheme.primary, 1.5),
    errorBorder: border(colorScheme.error, 1),
    focusedErrorBorder: border(colorScheme.error, 1.5),
  );
}

/// The spec's switch: a 36×20 track with a 16px thumb.
///
/// Only the colours are set. Material 3's switch geometry — a 52×32 track and
/// a thumb that grows on selection — is baked into `Switch`'s own painting and
/// is not reachable from [SwitchThemeData]; the spec's proportions would need
/// a `Transform.scale` per call site or a replacement widget. That is a
/// separate change from this one, and doing half of it here (colours at spec,
/// geometry at Material's) is the honest stopping point: every switch in the
/// app becomes the user's accent colour, and none of them changes size.
SwitchThemeData _buildSwitchTheme(ColorScheme colorScheme) {
  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: AppAlpha.disabled);
      }
      // White on the accent when on, matching the spec's floating thumb; the
      // scheme's own `onPrimary` would be dark under a pale seed.
      return states.contains(WidgetState.selected) ? Colors.white : colorScheme.outline;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.12);
      }
      return states.contains(WidgetState.selected)
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith((states) {
      // The spec's "off" track is a flat grey pill with no edge. Material
      // draws one by default, which at this size reads as a second border
      // around the thumb.
      return states.contains(WidgetState.selected) ? Colors.transparent : colorScheme.outlineVariant;
    }),
  );
}

/// The spec's checkbox: 18px, 6px corners, 1.5px edge when unchecked.
///
/// Unlike the switch, all of this *is* reachable from the theme — `Checkbox`
/// takes its shape and side from here — so this one lands on spec exactly.
CheckboxThemeData _buildCheckboxTheme(ColorScheme colorScheme) {
  return CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
    side: WidgetStateBorderSide.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(
          color: colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
          width: 1.5,
        );
      }
      return BorderSide(color: colorScheme.outline, width: 1.5);
    }),
    fillColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: 0.12);
      }
      // Unselected must be transparent, not a fill: the `side` above is what
      // draws an unchecked box, and a fill would paint over it.
      return states.contains(WidgetState.selected) ? colorScheme.primary : Colors.transparent;
    }),
    checkColor: WidgetStatePropertyAll(Colors.white),
    // Material reserves a 48px tap target around a 40px checkbox by default,
    // which in a dense settings list leaves the box marooned in whitespace.
    visualDensity: VisualDensity.compact,
  );
}

/// The type scale the rest of the widget library reads instead of a literal
/// `TextStyle(fontSize: N)`.
///
/// Sizes/weights collapse the app's ad hoc call sites (13, 14, 18... each
/// picked per screen) onto Material's named [TextTheme] slots. Colour is left
/// to [base] — merging keeps a slot's colour whenever this override doesn't
/// set one, so text stays tied to [colorScheme] the way Material's own
/// default theme is, and only size/weight are opinionated here.
TextTheme _buildTextTheme(ColorScheme colorScheme, String? fontFamily) {
  final base = ThemeData(useMaterial3: true, colorScheme: colorScheme).textTheme;

  final merged = base.merge(const TextTheme(
    // 16, not Material's 22 and not the 18 this app shipped before the
    // restyle: the spec's 页面标题 row reads 16/600, and every page mockup
    // draws its heading at that size. It is the only slot the restyle moved.
    titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    labelMedium: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
  ));

  // Applied here rather than left to ThemeData's own `fontFamily` parameter:
  // that parameter does not reliably reach every slot of a caller-supplied
  // `textTheme`, so a font switch could silently miss anything styled from
  // this scale. Doing it explicitly means every slot always carries it.
  return fontFamily == null ? merged : merged.apply(fontFamily: fontFamily);
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

/// The source red every destructive *fill* is derived from.
///
/// Material's own error source. Named rather than inlined because it is the
/// one hex in this file that is neither a neutral nor the user's seed, and a
/// reader has to be able to tell it isn't a hand-picked red.
const Color _errorSource = Color(0xFFB3261E);

/// The scheme a destructive button takes its fill and label from.
///
/// [buttonFillScheme]'s counterpart, and it exists for exactly the same reason
/// — restated because the symmetry is the whole argument. A filled button
/// needs a *dark, saturated* ground under a light label in both brightnesses;
/// [ColorScheme.error] is not that. It is tone 40 in light and tone 80 in
/// dark, because its job is to be legible *as a foreground* — which is right
/// for [AppButtonVariant.destructiveOutline] and `destructiveText`, and wrong
/// for a fill. Used as one it produced a pale pink slab with dark text in dark
/// mode: the app's only irreversible action rendering *lighter* than the
/// ordinary primary beside it, inverting the emphasis on the one button where
/// emphasis matters most. At the Rose and Orange seeds the two were also the
/// same hue family, so colour told the user nothing at all.
///
/// Always light + vibrant, so the fill is the same committed red under both
/// brightnesses — the same trick [buttonFillScheme] plays with the seed, and
/// the reason it takes no [Brightness].
ColorScheme errorFillScheme() {
  return ColorScheme.fromSeed(
    seedColor: _errorSource,
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

/// The monospaced faces to ask for, best first.
///
/// The spec sets every number, path, timestamp and log line in IBM Plex Mono,
/// and the app takes the role without taking the font: a bundled face would be
/// megabytes for text that is nowhere near a headline, and the point of a
/// monospace here is that digits line up in a column, which any of these do.
///
/// Ordered so each desktop platform finds its own system face before the
/// generic fallback. `monospace` last is what stops this degrading to the UI
/// font on a machine that has none of them.
const List<String> kMonoFontFamilyFallback = <String>[
  'Cascadia Mono', // Windows 11
  'Consolas', // Windows
  'SF Mono', // macOS
  'Menlo', // macOS, older
  'DejaVu Sans Mono', // Linux
  'monospace',
];

/// Numbers, code, paths and log lines set in a monospaced face.
///
/// A role rather than a size: take whichever scale slot the surrounding text
/// uses and pass it through here, so a measurement beside a label stays the
/// same size as the label and only changes shape.
///
/// Worth having beyond looks. A column of file sizes or dimensions in a
/// proportional face has its digits at different widths, so the numbers do not
/// line up and the eye cannot compare them down the column — which is the one
/// thing a metadata panel exists for.
extension AppMonoText on TextStyle {
  /// This style, set in a monospaced face.
  ///
  /// Sets `fontFamily` to null on purpose. A [TextStyle] carrying an explicit
  /// family would win over the fallback list, and the app sets one on every
  /// slot — see [_buildTextTheme]'s `apply`. Leaving it null lets the fallback
  /// chain decide, which is the whole mechanism.
  TextStyle get mono => copyWith(
        fontFamily: null,
        fontFamilyFallback: kMonoFontFamilyFallback,
        // Digits at a uniform width even in a face that would otherwise
        // proportion them. Free where the face is already monospaced, and a
        // rescue where the fallback landed somewhere unexpected.
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Taking a type-scale slot's size without its colour.
extension AppTextScaleMetrics on TextStyle {
  /// This slot's metrics, carrying no colour of its own.
  ///
  /// Every slot of a Material 3 [TextTheme] arrives stamped with `onSurface`
  /// — `Typography.material2021` puts it there — and an explicit colour on a
  /// [Text] beats the ambient [DefaultTextStyle]. So handing a raw slot to a
  /// label whose colour belongs to the widget *around* it paints `onSurface`
  /// over that widget's own choice: near-invisible on a filled button, and
  /// dead to the selected/unselected switch on a chip or list tile.
  ///
  /// The cases, all of which came up migrating the app onto the scale:
  ///
  /// - a [FilledButton]/[TextButton] label, whose colour is the button's
  ///   resolved foreground;
  /// - a [ChoiceChip]/[FilterChip] label, `onSecondaryContainer` when
  ///   selected and `onSurfaceVariant` when not;
  /// - a [ListTile] title or subtitle under `selected: true`, which tints to
  ///   `primary`;
  /// - an [ExpansionTile] header, whose colour is an animated tween between
  ///   two of those.
  ///
  /// `copyWith(color: null)` cannot express this — null there means "leave it
  /// alone" — so the metrics are restated explicitly.
  /// `inherit: true` is forced, not copied. It is the switch that decides
  /// whether [Text] merges this over the ambient [DefaultTextStyle] or
  /// replaces it outright — `TextStyle.merge` returns the incoming style
  /// wholesale when it is false, which would drop the very colour this is
  /// trying to inherit. A `TextTheme` slot's own value for it is an
  /// implementation detail of whoever built the theme.
  TextStyle get metricsOnly => const TextStyle().copyWith(
        inherit: true,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        height: height,
        leadingDistribution: leadingDistribution,
        textBaseline: textBaseline,
        fontFeatures: fontFeatures,
        fontVariations: fontVariations,
      );
}
