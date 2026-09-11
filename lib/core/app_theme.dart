import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'design_tokens.dart';
import 'theme_accent.dart';

/// Corner radius shared by buttons and the boxed controls beside them.
const double appButtonRadius = AppRadius.control;

/// Height of a standard button, matching the icon actions it sits next to.
///
/// Held by pinning visual density as well as the minimum size: on desktop
/// Material defaults to compact, which quietly subtracts 8px.
const double appButtonMinHeight = AppSize.control;

/// The neutral ramp the whole app sits on — one table per brightness, shared
/// by every accent (`00 设计系统 · 1b`, 「暖石灰」).
///
/// The load-bearing rule is unchanged from every previous system: **the ramp
/// does not move when the accent does.** A surface tuned against one accent
/// must still be right at the next, and an element that actually *is* the
/// accent — selected, focused, pressed — must be the only accent-coloured
/// thing in view. The ramp itself is now a warm stone rather than a cool
/// blue-grey; that warmth is the look, and it is the ramp's, not the seed's.
///
/// Roles are named for the job this app gives them:
///
/// | role | job | light | dark |
/// |---|---|---|---|
/// | `surfaceContainer` | **canvas** — the window ground under the aurora | `#EBEAE6` | `#121210` |
/// | `surfaceContainerLow` | **column** — edge-to-edge bars, headers, log strip, dialog footer | `#F6F5F2` | `#191917` |
/// | `surface` | **panel** — cards and dialogs floating on the canvas | `#FCFBF9` | `#1F1F1C` |
/// | `surfaceContainerHigh` | **card on a panel** | `#F0EFEB` | `#292926` |
/// | `surfaceContainerHighest` | **track** — segmented track, switch off, slider rail, disabled fill | `#E3E1DC` | `#33322E` |
/// | `outlineVariant` | **hairline** — dividers, input strokes | `#D8D6D0` | `#33322E` |
/// | `onSurface` / `onSurfaceVariant` / `outline` | ink / secondary / muted | `#1C1B18` `#625F58` `#8F8C84` | `#ECEAE4` `#A9A69E` `#79766E` |
///
/// ⚠️ A panel is lighter than the canvas in **both** brightnesses — the
/// opposite of Material's dark ordering. `app_color_scheme_test` holds it.
///
/// ⚠️ Column and panel are not one monotonic ladder in light: the column
/// (`#F6F5F2`) sits *under* the panel (`#FCFBF9`) while the card on a panel
/// (`#F0EFEB`) is darker than both. Pick the role by job, not by lightness.
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
    required this.scrim,
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
  final Color scrim;

  static const light = _Neutrals(
    surface: Color(0xFFFCFBF9),
    surfaceDim: Color(0xFFE4E2DD),
    surfaceBright: Color(0xFFFCFBF9),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F5F2),
    surfaceContainer: Color(0xFFEBEAE6),
    surfaceContainerHigh: Color(0xFFF0EFEB),
    surfaceContainerHighest: Color(0xFFE3E1DC),
    onSurface: Color(0xFF1C1B18),
    onSurfaceVariant: Color(0xFF625F58),
    outline: Color(0xFF8F8C84),
    outlineVariant: Color(0xFFD8D6D0),
    inverseSurface: Color(0xFF1C1B18),
    onInverseSurface: Color(0xFFF2F0EA),
    surfaceTint: Color(0xFF8F8C84),
    // `ink @ .36`.
    scrim: Color(0x5C1C1B18),
  );

  static const dark = _Neutrals(
    surface: Color(0xFF1F1F1C),
    surfaceDim: Color(0xFF0E0E0C),
    surfaceBright: Color(0xFF292926),
    surfaceContainerLowest: Color(0xFF0E0E0C),
    surfaceContainerLow: Color(0xFF191917),
    surfaceContainer: Color(0xFF121210),
    surfaceContainerHigh: Color(0xFF292926),
    surfaceContainerHighest: Color(0xFF33322E),
    onSurface: Color(0xFFECEAE4),
    onSurfaceVariant: Color(0xFFA9A69E),
    outline: Color(0xFF79766E),
    outlineVariant: Color(0xFF33322E),
    inverseSurface: Color(0xFFECEAE4),
    onInverseSurface: Color(0xFF1C1B18),
    surfaceTint: Color(0xFF79766E),
    // `#000 @ .52`.
    scrim: Color(0x85000000),
  );
}

/// The status red, per brightness (`--err`, `--err-bg`, `--err-ink`). Like
/// the other status colours it ignores the accent.
class _ErrorRoles {
  const _ErrorRoles(this.error, this.onError, this.container, this.onContainer);
  final Color error;
  final Color onError;
  final Color container;
  final Color onContainer;

  static const light = _ErrorRoles(
    Color(0xFFC2312F), Color(0xFFFFFFFF), Color(0xFFFBE0DF), Color(0xFF8C1F1E));
  static const dark = _ErrorRoles(
    Color(0xFFF0655F), Color(0xFF2A0B0A), Color(0xFF4A1E1C), Color(0xFFFFC2BE));
}

/// The app's palette: accents from the pair, greys from [_Neutrals], status
/// from the fixed tables.
///
/// The accent is a [ThemeAccent] — a light/dark *pair* of finished colours.
/// Each brightness grows a scheme from its half for the palette roles, then
/// draws `primary` **as the half itself**, with its ink and deep ink beside
/// it at the half's own chroma:
///
/// - `onPrimary`: white where white reads, else the hue's tone-10 ink
///   (Orange in light; every dark half).
/// - `onPrimaryFixedVariant` (light) / `primaryFixedDim` (dark): `--p-deep`,
///   tone 30 / tone 80 — see [AppAccent.onAccentTint].
ColorScheme buildAppColorScheme({
  required ThemeAccent accent,
  required Brightness brightness,
}) {
  // Memoised: the theme-colour picker builds both schemes of every preset on
  // each rebuild, and each `fromSeed` is ~50 HCT solves.
  final cached = _schemeCache[(accent, brightness)];
  if (cached != null) return cached;

  final bool isDark = brightness == Brightness.dark;
  final Color half = accent.forBrightness(brightness);
  final seeded = ColorScheme.fromSeed(
    seedColor: half,
    brightness: brightness,
    // `vibrant`: `tonalSpot` caps chroma and turns a vivid accent into its
    // slate shadow. Only accent roles survive — neutrals are overwritten.
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  );
  final neutral = isDark ? _Neutrals.dark : _Neutrals.light;
  final err = isDark ? _ErrorRoles.dark : _ErrorRoles.light;

  final scheme = seeded.copyWith(
    primary: half,
    onPrimary: isDark ? accent.onDark : accent.onLight,
    onPrimaryFixedVariant: isDark ? null : accent.lightOnTint,
    primaryFixedDim: isDark ? accent.darkOnTint : accent.lightTone(80),
    primaryContainer: isDark ? accent.darkTone(30) : accent.lightTone(90),
    onPrimaryContainer: isDark ? accent.darkTone(90) : accent.lightOnTint,
    error: err.error,
    onError: err.onError,
    errorContainer: err.container,
    onErrorContainer: err.onContainer,
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
    surfaceTint: neutral.surfaceTint,
    scrim: neutral.scrim,
  );
  if (_schemeCache.length >= _schemeCacheCap) _schemeCache.clear();
  return _schemeCache[(accent, brightness)] = scheme;
}

final Map<(ThemeAccent, Brightness), ColorScheme> _schemeCache = {};
const int _schemeCacheCap = 64;

/// The app's theme, built from the theme colour the user picked in settings.
ThemeData buildAppTheme({
  required ThemeAccent accent,
  required Brightness brightness,
  String? fontFamily,
}) {
  final colorScheme = buildAppColorScheme(accent: accent, brightness: brightness);
  final textTheme = _buildTextTheme(colorScheme, fontFamily);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    textTheme: textTheme,
    // The scaffold never paints: the window ground is the aurora backdrop
    // behind every screen (`00` 「aurora」). A screen that wants an opaque
    // ground asks for its role explicitly.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: colorScheme.surface,
    extensions: [
      brightness == Brightness.dark ? AppSemanticColors.dark : AppSemanticColors.light,
    ],
    inputDecorationTheme: _buildInputDecorationTheme(colorScheme),
    switchTheme: _buildSwitchTheme(colorScheme),
    checkboxTheme: _buildCheckboxTheme(colorScheme),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.primary : colorScheme.outline),
      visualDensity: VisualDensity.compact,
    ),
    // `01 · 1h`: an opaque panel at r22 over the scheme's scrim.
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.dialog)),
      barrierColor: colorScheme.scrim,
      elevation: 0,
    ),
    // Menus are glass in the design (玻璃二). Material's popup route cannot
    // host a backdrop filter behind its own clip, so the theme gives the
    // reduced-effects form — an opaque panel at the same radius — and the app's
    // own menus (`AppGlassMenu`) draw the glass.
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      menuPadding: const EdgeInsets.all(AppSpace.s6),
      elevation: 6,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.4),
      iconColor: colorScheme.onSurfaceVariant,
      iconSize: AppSize.iconMd,
      textStyle: textTheme.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: colorScheme.outlineVariant),
        )),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpace.s6)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    // `00 · 1f` 「列表行」: 40 tall, r10, a 12% wash under the deep ink when
    // selected.
    listTileTheme: ListTileThemeData(
      visualDensity: VisualDensity.compact,
      minLeadingWidth: 0,
      horizontalTitleGap: AppSpace.s10,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      selectedColor: colorScheme.onAccentTint,
      selectedTileColor: colorScheme.accentTint,
      iconColor: colorScheme.onSurfaceVariant,
    ),
    // `00 · 1f` 「滑杆」: a 4px rail on the track colour, the accent to the
    // thumb, a 16px thumb.
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
      thumbColor: colorScheme.primary,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      tickMarkShape: SliderTickMarkShape.noTickMark,
    ),
    // `00 · 1f`: 3px, rounded ends, on the track colour.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearMinHeight: 3,
      borderRadius: BorderRadius.circular(2),
      linearTrackColor: colorScheme.surfaceContainerHighest,
      circularTrackColor: colorScheme.surfaceContainerHighest,
    ),
    // A tab is a segment: the wash under the deep ink, r6.
    tabBarTheme: TabBarThemeData(
      indicator: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelColor: colorScheme.onAccentTint,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelLarge,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    ),
    // `00 · 1f` 「刷新 · Ctrl+R」: the fixed ink in both brightnesses, r6.
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppOverlay.ink,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      verticalOffset: 20,
      textStyle: TextStyle(
        color: AppOverlay.onInk,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        fontFamily: fontFamily,
      ),
      waitDuration: const Duration(milliseconds: 400),
      exitDuration: const Duration(milliseconds: 80),
    ),
    // `00 · 1f` 「芯片」: r4, 11/500, a hairline at rest, the wash when chosen.
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surface,
      selectedColor: colorScheme.accentTint,
      disabledColor: colorScheme.surfaceContainerHighest,
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return BorderSide(color: colorScheme.accentRing);
        }
        return BorderSide(color: colorScheme.outlineVariant);
      }),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurfaceVariant,
        fontFamily: fontFamily,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: colorScheme.onAccentTint,
        fontFamily: fontFamily,
      ),
      labelPadding: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: colorScheme.navBackground(selected: true),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: _navInk(colorScheme, states)),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelSmall!.copyWith(color: _navInk(colorScheme, states)),
      ),
    ),
    // `A1 · 1e`: 56 at r22.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.dialog)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: colorScheme.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      scrimColor: colorScheme.scrim,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(colorScheme.onSurface.withValues(alpha: 0.22)),
    ),
    // `00 · 1f` 「主按钮」: solid accent, no lift. Disabled is the track under
    // muted ink — a disabled CTA must not glow.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: colorScheme.surfaceContainerHighest,
        disabledForegroundColor: colorScheme.outline,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
        minimumSize: const Size(0, appButtonMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        // `inherit: false` to match the merged theme slots `AppButton` hands
        // its compact and large sizes: a button animates between its old and
        // new label style, and TextStyle.lerp asserts across a change of
        // `inherit`.
        textStyle: textTheme.labelLarge?.copyWith(inherit: false, fontWeight: FontWeight.w600),
        visualDensity: VisualDensity.standard,
      ),
    ),
    // 「添加文件夹」: a panel with a hairline and body ink.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        disabledForegroundColor: colorScheme.outline,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
        minimumSize: const Size(0, appButtonMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: BorderSide(color: colorScheme.outlineVariant),
        textStyle: textTheme.labelLarge?.copyWith(inherit: false),
        visualDensity: VisualDensity.standard,
      ),
    ),
    // 「提示词历史」: the deep ink, no ground.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.accentText,
        disabledForegroundColor: colorScheme.outline,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
        minimumSize: const Size(0, appButtonMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: textTheme.labelLarge?.copyWith(inherit: false),
        visualDensity: VisualDensity.standard,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        iconSize: AppSize.iconLg,
        minimumSize: const Size(AppSize.iconButton, AppSize.iconButton),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        visualDensity: VisualDensity.standard,
      ),
    ),
  );
}

/// `00 · 1f` 「输入」: a hairline box at r10, the accent stroke when focused,
/// the error stroke when invalid.
///
/// The 3px focus ring the design draws outside the border is not
/// expressible through [InputDecoration]; `AppTextField` draws it.
InputDecorationTheme _buildInputDecorationTheme(ColorScheme colorScheme) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecorationTheme(
    filled: false,
    isDense: true,
    // Pinned, not left to the platform. Flutter's default density is compact
    // on Windows, macOS and Linux and standard on Android and iOS, and compact
    // takes 8px off every field's content height. So a field sized to 32 on
    // one platform drew 24 on the other, and the screenshot harness, which
    // runs as Android, never showed what a desktop user saw.
    visualDensity: VisualDensity.standard,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    hintStyle: TextStyle(color: colorScheme.outline),
    border: border(colorScheme.outlineVariant, 1),
    enabledBorder: border(colorScheme.outlineVariant, 1),
    disabledBorder: border(colorScheme.outlineVariant.withValues(alpha: AppAlpha.disabled), 1),
    focusedBorder: border(colorScheme.primary, 1),
    errorBorder: border(colorScheme.error, 1),
    focusedErrorBorder: border(colorScheme.error, 1.5),
  );
}

/// `00 · 1f` 「开关」: on = the accent under a white thumb; off = the track
/// with a hairline under a panel-coloured thumb.
SwitchThemeData _buildSwitchTheme(ColorScheme colorScheme) {
  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.onSurface.withValues(alpha: AppAlpha.disabled);
      }
      return states.contains(WidgetState.selected) ? Colors.white : colorScheme.surface;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
      }
      return states.contains(WidgetState.selected)
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.selected) ? Colors.transparent : colorScheme.outlineVariant;
    }),
    thumbIcon: const WidgetStatePropertyAll(null),
  );
}

/// `00 · 1f` 「复选框」: 18px at r4, a 1.5px muted edge when unchecked, the
/// accent under its own ink when checked.
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
        return colorScheme.surfaceContainerHighest;
      }
      return states.contains(WidgetState.selected) ? colorScheme.primary : Colors.transparent;
    }),
    checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
    visualDensity: VisualDensity.compact,
  );
}

/// The type scale (`00 · 1d`): seven sizes and no others.
///
/// | size/weight | job | slots |
/// |---|---|---|
/// | 28/600 | headline figure | `headlineLarge` |
/// | 20/600 | screen title | `headlineMedium`, `headlineSmall` |
/// | 16/600 | page / dialog title | `titleLarge` |
/// | 14/500 | emphasised body, card title | `titleMedium`, `bodyLarge` (400) |
/// | 13/400 | body, control labels, list rows | `bodyMedium`, `titleSmall` (500), `labelLarge` (500) |
/// | 12/400 | secondary, sub-rows, help text | `bodySmall`, `labelMedium` (500) |
/// | 11/500 | group caption (tracked), badges | `labelSmall` |
///
/// Mono 12 / 11 is a role, not a slot: `style.mono`.
TextTheme _buildTextTheme(ColorScheme colorScheme, String? fontFamily) {
  TextStyle slot(double size, FontWeight weight) => TextStyle(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: AppType.trackingFor(size),
      );

  final merged = TextTheme(
    headlineLarge: slot(28, FontWeight.w600),
    headlineMedium: slot(20, FontWeight.w600),
    headlineSmall: slot(20, FontWeight.w600),
    titleLarge: slot(16, FontWeight.w600),
    titleMedium: slot(14, FontWeight.w500),
    titleSmall: slot(13, FontWeight.w500),
    bodyLarge: slot(14, FontWeight.w400),
    bodyMedium: slot(13, FontWeight.w400),
    bodySmall: slot(12, FontWeight.w400),
    labelLarge: slot(13, FontWeight.w500),
    labelMedium: slot(12, FontWeight.w500),
    labelSmall: slot(11, FontWeight.w500),
  );

  return fontFamily == null ? merged : merged.apply(fontFamily: fontFamily);
}

Color _navInk(ColorScheme colorScheme, Set<WidgetState> states) =>
    states.contains(WidgetState.disabled)
        ? colorScheme.onSurface.withValues(alpha: AppAlpha.disabled)
        : colorScheme.navForeground(selected: states.contains(WidgetState.selected));

/// The skin a slider wears when it changes how you *look* at the work — a
/// thumbnail size, a viewport zoom — rather than the work itself. Greyscale,
/// so the brightest thing on screen is not the one control that alters
/// nothing.
SliderThemeData neutralSliderTheme(ColorScheme colorScheme) {
  return SliderThemeData(
    trackHeight: 3,
    activeTrackColor: colorScheme.onSurfaceVariant,
    inactiveTrackColor: colorScheme.surfaceContainerHighest,
    thumbColor: colorScheme.onSurfaceVariant,
    overlayColor: colorScheme.onSurface.withValues(alpha: 0.08),
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    tickMarkShape: SliderTickMarkShape.noTickMark,
  );
}

/// The scheme a destructive *fill* takes its colours from.
///
/// `00 · 1f` 「删除」 draws `--err` under white in both brightnesses. The
/// dark `--err` (`#F0655F`) is tuned to be read as a foreground and carries
/// white at only ~3:1, so the fill keeps the light red in both — the same
/// committed weight as the primary CTA, differing only in hue.
ColorScheme errorFillScheme() {
  return ColorScheme.fromSeed(seedColor: _ErrorRoles.light.error).copyWith(
    primary: _ErrorRoles.light.error,
    onPrimary: _ErrorRoles.light.onError,
  );
}

/// The tonal form (`A3a` 「版本角标 / Apply / 保存到库」): the 12% wash under the
/// deep ink, ringed. Spent only on "put the model's output to use".
///
/// Pass it to every tonal button — the app-wide filled theme names a
/// background for all filled buttons and would otherwise win.
ButtonStyle tonalButtonStyle(ColorScheme colorScheme) {
  return FilledButton.styleFrom(
    backgroundColor: colorScheme.accentTint,
    foregroundColor: colorScheme.onAccentTint,
    disabledBackgroundColor: colorScheme.surfaceContainerHighest,
    disabledForegroundColor: colorScheme.outline,
    elevation: 0,
    side: BorderSide(color: colorScheme.accentRing),
  );
}

/// The monospaced faces to ask for, best first. The design sets numbers,
/// logs, filenames and model ids in the system mono stack; nothing is
/// bundled.
const List<String> kMonoFontFamilyFallback = <String>[
  'Cascadia Mono', // Windows 11
  'Consolas', // Windows
  'SF Mono', // macOS
  'Menlo', // macOS, older
  'DejaVu Sans Mono', // Linux
  'monospace',
];

/// Numbers, code, paths and log lines set in a monospaced face.
extension AppMonoText on TextStyle {
  /// This style in a monospaced face with tabular figures.
  ///
  /// `fontFamily` is nulled on purpose: an explicit family would beat the
  /// fallback list, and the app stamps one on every slot.
  TextStyle get mono => copyWith(
        fontFamily: null,
        fontFamilyFallback: kMonoFontFamilyFallback,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Taking a type-scale slot's size without its colour.
extension AppTextScaleMetrics on TextStyle {
  /// This slot's metrics, carrying no colour of its own.
  ///
  /// A Material 3 slot arrives stamped with `onSurface`, and an explicit
  /// colour on a [Text] beats the ambient [DefaultTextStyle] — so a raw slot
  /// on a filled button, a selected chip or a glass bar paints the wrong ink.
  /// `inherit: true` is forced: `TextStyle.merge` returns the incoming style
  /// wholesale when it is false, dropping the colour this exists to inherit.
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
