part of '../crop_resize_toolbar.dart';

/// The fixed set of ratio presets shown as segments, plus a `custom` mode
/// whose X:Y fields only appear once it's selected — folding them into the
/// segmented control instead of always occupying toolbar width.
enum _RatioPreset { free, r1x1, r4x3, r16x9, r3x4, r9x16, custom }

/// Resampling algorithms by the id [WorkbenchUIState.samplingMethod] stores.
/// Proper names of algorithms, not prose — the same in every language.
const Map<String, String> _kSamplingLabels = {
  'lanczos': 'Lanczos',
  'cubic': 'Cubic',
  'linear': 'Linear',
  'nearest': 'Nearest',
};

/// The glass bar's gap between groups.
const double _kGap = 4;

/// `A4 · 1a`: a 72×32 dimension input either side of a 28px link lens, 2px
/// apart — one group, measured as one.
const double _kFieldWidth = 72;
const double _kLinkSize = AppSize.compact;
const double _kFieldGap = 2;
const double _kSizeGroupWidth = _kFieldWidth + _kFieldGap + _kLinkSize + _kFieldGap + _kFieldWidth;

/// The X:Y pair that unfolds beside the ratio switch under "Custom".
const double _kCustomFieldsWidth = 80;

/// The least the flexible gap before the actions may shrink to.
const double _kMinSpacer = AppSpace.s6;

/// Mono 11 in the glass bar's secondary ink: the source's size and weight.
TextStyle _infoStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.metricsOnly.mono.copyWith(fontWeight: FontWeight.w400);

/// Mono 12: a number the user types.
TextStyle _valueStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall!.metricsOnly.mono;

/// Save Copy's two lines (`1a`: 600 label over an 11px subtitle, 1.15 apart).
TextStyle _saveLabelStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall!
    .metricsOnly
    .copyWith(fontWeight: FontWeight.w600, height: 1.15);

TextStyle _saveSubtitleStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelSmall!
    .metricsOnly
    .copyWith(fontWeight: FontWeight.w400, height: 1.15);

/// Whether Save Copy's two lines stand inside the 32px control at the user's
/// text scale. Measured, like everything else here: at a large enough scale
/// the pair is taller than the button, and the subtitle has to go before it
/// overflows vertically, whatever the width.
bool _saveSubtitleFitsHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  double lineHeight(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Hg', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  return lineHeight(_saveLabelStyle(context)) + lineHeight(_saveSubtitleStyle(context)) <=
      AppSize.control - 2;
}

List<GlassSegment<_RatioPreset>> _ratioSegments(
  AppLocalizations l10n, {
  required bool portrait,
  required bool icons,
}) =>
    [
      GlassSegment(
        value: _RatioPreset.free,
        label: l10n.cropResizeFreeRatio,
        icon: icons ? Icons.crop_free : null,
      ),
      const GlassSegment(value: _RatioPreset.r1x1, label: '1:1'),
      const GlassSegment(value: _RatioPreset.r4x3, label: '4:3'),
      const GlassSegment(value: _RatioPreset.r16x9, label: '16:9'),
      if (portrait) ...const [
        GlassSegment(value: _RatioPreset.r3x4, label: '3:4'),
        GlassSegment(value: _RatioPreset.r9x16, label: '9:16'),
      ],
      GlassSegment(
        value: _RatioPreset.custom,
        label: l10n.custom,
        icon: icons ? Icons.edit_outlined : null,
      ),
    ];

/// What the single row is currently allowed to show. Starts with everything
/// and is stepped down in [_WideRow._fitRow].
class _Fit {
  bool info = true;
  bool samplingName = true;
  bool saveSubtitle = true;
  bool portraitPresets = true;
  bool ratioWords = true;
  bool resetLabel = true;
  bool overwriteLabel = true;
  bool folded = false;
}

/// The width the single row takes under [f].
double _measureRow(
  BuildContext context,
  _Fit f, {
  required String? info,
  required bool customMode,
  required String samplingLabel,
}) {
  final l10n = AppLocalizations.of(context)!;
  final parts = <double>[
    if (f.info && info != null) ...[
      measureGlassText(context, info, _infoStyle(context)).ceilToDouble(),
      GlassDivider.extent,
    ],
    GlassSegmented.widthFor(
      context,
      _ratioSegments(l10n, portrait: f.portraitPresets, icons: !f.ratioWords),
      showLabels: f.ratioWords,
    ),
    if (customMode) _kCustomFieldsWidth,
    _kSizeGroupWidth,
    if (!f.folded) _GlassMenuButton.widthFor(context, f.samplingName ? samplingLabel : null),
    _kMinSpacer,
    if (f.folded)
      AppSize.control
    else ...[
      GlassIconButton.widthFor(context, label: f.resetLabel ? l10n.reset : null, hasIcon: false),
      GlassIconButton.widthFor(
        context,
        label: f.overwriteLabel ? l10n.overwriteSource : null,
        hasIcon: false,
      ),
    ],
    _TintedButton.widthFor(
      context,
      label: l10n.saveCopy,
      subtitle: f.saveSubtitle ? l10n.cropResizeSaveDestinationHint : null,
    ),
  ];
  return parts.fold<double>(0, (a, b) => a + b) + _kGap * (parts.length - 1);
}

/// Lays [children] out with the bar's gap between each.
List<Widget> _spaced(List<Widget> children) => [
      for (int i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: _kGap),
        children[i],
      ],
    ];
