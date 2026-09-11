import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/glass_controls.dart';

/// The mask editor's controls in the workbench's floating glass toolbar
/// (`A4A6 · 1e`, `1f`): brush size, mask opacity, colour, the mask's real
/// size, undo, binary mode, clear, and the two saves.
///
/// It fills the slot the toolbar gives it after the back button and the tool
/// switch — no ground, edge or padding frame of its own — and degrades inside
/// that slot by measurement, never by breakpoint (four languages, scaled
/// text), in the spec's order:
///
/// 1. decoration: the mask size, the slider label words, the save subtitles;
/// 2. labels: binary mode, clear and save composite become glyphs;
/// 3. the ⋮ menu: the sliders (leaving a compact `48 px · 70%` readout
///    inline), binary mode, save composite and clear fold in one at a time,
///    then the swatches;
/// 4. never: undo and Save Mask. Past every step the readout goes, and as a
///    last resort Save Mask keeps its glyph instead of its word.
class MaskEditorToolbar extends StatefulWidget {
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final VoidCallback onSaveMask;
  final Function(Color) onColorChanged;
  final Function(double) onBrushSizeChanged;
  final Function(double) onOpacityChanged;
  final VoidCallback onToggleBinary;
  final Color selectedColor;
  final double brushSize;
  final double opacity;
  final bool isBinaryMode;
  final bool hasPaths;

  const MaskEditorToolbar({
    super.key,
    required this.onUndo,
    required this.onClear,
    required this.onSave,
    required this.onSaveMask,
    required this.onColorChanged,
    required this.onBrushSizeChanged,
    required this.onOpacityChanged,
    required this.onToggleBinary,
    required this.selectedColor,
    required this.brushSize,
    required this.opacity,
    required this.isBinaryMode,
    required this.hasPaths,
  });

  static const double _gap = 4;

  /// Before the first control. The sliders' thumbs overhang their track by
  /// 8 at either end, so this is what keeps a thumb at zero off the divider.
  static const double _leading = 8;

  /// The least the flexible gap between the editing controls and the actions
  /// may shrink to before something has to give way.
  static const double _minSpacer = 8;

  /// The widest readouts, whose widths are reserved so a changing digit never
  /// moves the controls after them. Mono with tabular figures, so any digits
  /// will do.
  static const String _brushReserve = '100';
  static const String _opacityReserve = '100%';
  static final String _compactReserve = _compactReadout(100, 1);

  static TextStyle _captionStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.metricsOnly.copyWith(fontWeight: FontWeight.w400);

  static TextStyle _monoStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.metricsOnly.mono.copyWith(fontWeight: FontWeight.w400);

  static String _compactReadout(double brushSize, double opacity) =>
      '${brushSize.round()} px · ${(opacity * 100).round()}%';

  /// The mask-size caption, if the source's dimensions are known.
  static String? _caption(AppLocalizations l10n, ImageMetadata? meta) =>
      meta != null && meta.width > 0 ? l10n.maskSourceCaption(meta.width, meta.height) : null;

  /// The width these controls take with everything shown and labelled — what
  /// the glass toolbar weighs its tool switch against.
  ///
  /// Counts all four swatches, and reserves the mask-size caption while the
  /// source's dimensions are still loading so the answer does not grow once
  /// they arrive.
  static double preferredWidth(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final source = Provider.of<WorkbenchUIState>(context, listen: false).maskEditorSourceImage;
    String? caption;
    if (source != null) {
      caption = _caption(l10n, ImageMetadataService().peek(source.path)) ??
          l10n.maskSourceCaption(8888, 8888);
    }
    final metrics = _Metrics.of(context, caption: caption);
    return _Plan(subtitles: metrics.subtitlesFit).widthWith(metrics, swatchCount: 4).ceilToDouble();
  }

  @override
  State<MaskEditorToolbar> createState() => _MaskEditorToolbarState();
}

/// Every width the layout weighs, measured once per build: the plan is
/// re-weighed up to a dozen times, and the toolbar rebuilds on every frame of
/// a slider drag.
class _Metrics {
  const _Metrics._({
    required this.brushLabel,
    required this.opacityLabel,
    required this.brushReserve,
    required this.opacityReserve,
    required this.readout,
    required this.caption,
    required this.binaryLabelled,
    required this.clearLabelled,
    required this.compositeLabel,
    required this.saveLabel,
    required this.subtitle,
    required this.subtitlesFit,
  });

  final double brushLabel;
  final double opacityLabel;
  final double brushReserve;
  final double opacityReserve;
  final double readout;
  final double? caption;
  final double binaryLabelled;
  final double clearLabelled;
  final double compositeLabel;
  final double saveLabel;
  final double subtitle;

  /// Whether a two-line save label fits the 32px control at the current text
  /// scale. Past a modest scale the subtitle would spill out of the button,
  /// so it is dropped however wide the bar is.
  final bool subtitlesFit;

  static _Metrics of(BuildContext context, {required String? caption}) {
    final l10n = AppLocalizations.of(context)!;
    final scaler = MediaQuery.textScalerOf(context);
    final mono = MaskEditorToolbar._monoStyle(context);
    final captionStyle = MaskEditorToolbar._captionStyle(context);
    final saveStyle = _TintedSaveButton.labelStyle(context);
    final subtitleStyle = _TintedSaveButton.subtitleStyle(context);
    double width(String text, TextStyle style) => measureGlassText(context, text, style).ceilToDouble();
    double lineHeight(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final h = painter.height;
      painter.dispose();
      return h;
    }

    return _Metrics._(
      brushLabel: width(l10n.brushSize, captionStyle),
      opacityLabel: width(l10n.maskOpacity, captionStyle),
      brushReserve: width(MaskEditorToolbar._brushReserve, mono),
      opacityReserve: width(MaskEditorToolbar._opacityReserve, mono),
      readout: width(MaskEditorToolbar._compactReserve, mono),
      caption: caption == null ? null : width(caption, mono),
      binaryLabelled: GlassIconButton.widthFor(context, label: l10n.binaryMode),
      clearLabelled: GlassIconButton.widthFor(context, label: l10n.clear, hasIcon: false),
      compositeLabel: width(l10n.maskSaveComposite, _OutlinedSaveButton.labelStyle(context)),
      saveLabel: width(l10n.maskSaveMask, saveStyle),
      subtitle: width(l10n.cropResizeSaveDestinationHint, subtitleStyle),
      subtitlesFit: lineHeight(saveStyle) + lineHeight(subtitleStyle) <= AppSize.control - 2,
    );
  }
}

/// Which pieces of the toolbar are showing, in the order they give way.
class _Plan {
  _Plan({required this.subtitles});

  bool caption = true;
  bool sliderLabels = true;
  bool subtitles;
  bool labels = true;
  bool foldSliders = false;
  bool foldBinary = false;
  bool foldComposite = false;
  bool foldClear = false;
  bool foldColors = false;
  bool readout = true;
  bool saveLabel = true;

  bool get hasMenu => foldSliders || foldBinary || foldComposite || foldClear || foldColors;

  /// The row's width under this plan. Mirrors `_buildRow` item for item.
  double widthWith(_Metrics m, {required int swatchCount}) {
    double slider(double label, double reserve) =>
        (sliderLabels ? label + _GlassSlider.side : 0) + _GlassSlider.track + _GlassSlider.side + reserve;
    double twoLine(double label) => subtitles ? math.max(label, m.subtitle) : label;

    final parts = <double>[
      if (foldSliders) ...[
        if (readout) m.readout,
      ] else ...[
        slider(m.brushLabel, m.brushReserve),
        slider(m.opacityLabel, m.opacityReserve),
      ],
      if (!foldColors) _Swatches.widthFor(swatchCount),
      if (caption && m.caption != null) m.caption!,
      MaskEditorToolbar._minSpacer,
      AppSize.control, // undo
      if (!foldBinary) labels ? m.binaryLabelled : AppSize.control,
      if (!foldClear) labels ? m.clearLabelled : AppSize.control,
      if (!foldComposite)
        labels ? _OutlinedSaveButton.chrome + twoLine(m.compositeLabel) : AppSize.control,
      if (hasMenu) AppSize.control,
      saveLabel ? _TintedSaveButton.chrome + twoLine(m.saveLabel) : AppSize.control,
    ];
    return MaskEditorToolbar._leading +
        parts.fold<double>(0, (a, b) => a + b) +
        MaskEditorToolbar._gap * (parts.length - 1);
  }
}

class _MaskEditorToolbarState extends State<MaskEditorToolbar> {
  /// Source dimensions for the caption. The view loads this too;
  /// [ImageMetadataService] caches by path, so the second reader costs a map
  /// lookup rather than a second decode.
  ImageMetadata? _meta;
  String? _metaPath;

  void _loadMeta(String path) {
    if (_metaPath == path) return;
    _metaPath = path;
    // Whatever the cache already has, now — not the previous image's size
    // until the future lands.
    _meta = ImageMetadataService().peek(path);
    ImageMetadataService().getMetadata(path).then((meta) {
      if (mounted && _metaPath == path) setState(() => _meta = meta);
    });
  }

  /// White and black always. Binary mode drops red and green: they would be
  /// flattened to one of the two extremes on export, so offering them there
  /// would be offering a choice the file cannot keep.
  List<(Color, String)> _swatches(AppLocalizations l10n) => [
        (Colors.white, l10n.white),
        (Colors.black, l10n.black),
        if (!widget.isBinaryMode) ...[
          (Colors.red, l10n.red),
          (Colors.green, l10n.green),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final source = Provider.of<WorkbenchUIState>(context).maskEditorSourceImage;
    if (source != null) _loadMeta(source.path);
    final caption = source == null ? null : MaskEditorToolbar._caption(l10n, _meta);

    return LayoutBuilder(
      builder: (context, constraints) => _buildRow(context, l10n, constraints.maxWidth, caption),
    );
  }

  Widget _buildRow(BuildContext context, AppLocalizations l10n, double width, String? caption) {
    final scheme = Theme.of(context).colorScheme;
    final ink2 = GlassInk.maybeOf(context)?.ink2 ?? scheme.onSurfaceVariant;
    final mono = MaskEditorToolbar._monoStyle(context);
    final swatches = _swatches(l10n);
    final hint = l10n.cropResizeSaveDestinationHint;
    final m = _Metrics.of(context, caption: caption);

    final p = _Plan(subtitles: m.subtitlesFit);
    final steps = <void Function()>[
      () => p.caption = false,
      () => p.sliderLabels = false,
      () => p.subtitles = false,
      () => p.labels = false,
      () => p.foldSliders = true,
      () => p.foldBinary = true,
      () => p.foldComposite = true,
      () => p.foldClear = true,
      () => p.foldColors = true,
      () => p.readout = false,
      () => p.saveLabel = false,
    ];
    for (final step in steps) {
      if (p.widthWith(m, swatchCount: swatches.length) <= width) break;
      step();
    }

    final items = <Widget>[
      if (p.foldSliders) ...[
        if (p.readout)
          Tooltip(
            message: '${l10n.brushSize} · ${l10n.maskOpacity}',
            child: SizedBox(
              width: m.readout,
              child: Text(
                MaskEditorToolbar._compactReadout(widget.brushSize, widget.opacity),
                maxLines: 1,
                softWrap: false,
                style: mono.copyWith(color: ink2),
              ),
            ),
          ),
      ] else ...[
        _GlassSlider(
          label: p.sliderLabels ? l10n.brushSize : null,
          tooltip: l10n.brushSize,
          value: widget.brushSize,
          min: 1,
          max: 100,
          readout: widget.brushSize.round().toString(),
          readoutWidth: m.brushReserve,
          onChanged: widget.onBrushSizeChanged,
        ),
        _GlassSlider(
          label: p.sliderLabels ? l10n.maskOpacity : null,
          tooltip: l10n.maskOpacity,
          value: widget.opacity,
          min: 0.1,
          max: 1.0,
          readout: '${(widget.opacity * 100).round()}%',
          readoutWidth: m.opacityReserve,
          onChanged: widget.onOpacityChanged,
        ),
      ],
      if (!p.foldColors)
        _Swatches(
          swatches: swatches,
          selected: widget.selectedColor,
          onSelected: widget.onColorChanged,
        ),
      // What the export will be — the canvas only ever shows a fitted
      // preview, so without this the mask's real resolution is invisible.
      if (p.caption && caption != null)
        Text(caption, maxLines: 1, softWrap: false, style: mono.copyWith(color: ink2)),
      const Expanded(child: SizedBox()),
      // Undo keeps a fixed place of its own: it is the one control a hand
      // reaches for mid-stroke, and a menu is two taps too many for it.
      GlassIconButton(
        icon: Icons.undo,
        tooltip: l10n.undo,
        onPressed: widget.hasPaths ? widget.onUndo : null,
      ),
      if (!p.foldBinary)
        GlassIconButton(
          icon: Icons.contrast,
          label: p.labels ? l10n.binaryMode : null,
          tooltip: p.labels ? null : l10n.binaryMode,
          active: widget.isBinaryMode,
          onPressed: widget.onToggleBinary,
        ),
      if (!p.foldClear)
        GlassIconButton(
          icon: p.labels ? null : Icons.delete_outline,
          label: p.labels ? l10n.clear : null,
          tooltip: p.labels ? null : l10n.clear,
          danger: true,
          onPressed: widget.hasPaths ? widget.onClear : null,
        ),
      if (!p.foldComposite)
        _OutlinedSaveButton(
          label: p.labels ? l10n.maskSaveComposite : null,
          subtitle: p.subtitles ? hint : null,
          icon: Icons.layers_outlined,
          tooltip: l10n.maskSaveComposite,
          onPressed: widget.onSave,
        ),
      if (p.hasMenu) _buildOverflowMenu(context, l10n, p, swatches),
      _TintedSaveButton(
        label: p.saveLabel ? l10n.maskSaveMask : null,
        subtitle: p.subtitles ? hint : null,
        tooltip: l10n.maskSaveMask,
        onPressed: widget.onSaveMask,
      ),
    ];

    return Row(
      children: [
        const SizedBox(width: MaskEditorToolbar._leading),
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: MaskEditorToolbar._gap),
          items[i],
        ],
      ],
    );
  }

  /// Everything the bar folded, in `1f`'s order: the two sliders (each a
  /// submenu holding its slider, so the canvas stays visible while it is set),
  /// the swatches, binary mode, save composite, and clear under a rule.
  Widget _buildOverflowMenu(
    BuildContext context,
    AppLocalizations l10n,
    _Plan p,
    List<(Color, String)> swatches,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mono = MaskEditorToolbar._monoStyle(context).copyWith(color: scheme.onSurfaceVariant);
    final binaryOn = widget.isBinaryMode;

    Widget sliderSubmenu({
      required IconData icon,
      required String label,
      required String readout,
      required Widget slider,
    }) =>
        SubmenuButton(
          leadingIcon: Icon(icon, size: AppSize.iconLg),
          menuChildren: [slider],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: AppSpace.s16),
              Text(readout, style: mono),
            ],
          ),
        );

    return MenuAnchor(
      menuChildren: [
        if (p.foldSliders) ...[
          sliderSubmenu(
            icon: Icons.line_weight,
            label: l10n.brushSize,
            readout: '${widget.brushSize.round()} px',
            slider: _MenuSlider(
              value: widget.brushSize,
              min: 1,
              max: 100,
              format: (v) => '${v.round()} px',
              reserve: '100 px',
              onChanged: widget.onBrushSizeChanged,
            ),
          ),
          sliderSubmenu(
            icon: Icons.opacity,
            label: l10n.maskOpacity,
            readout: '${(widget.opacity * 100).round()}%',
            slider: _MenuSlider(
              value: widget.opacity,
              min: 0.1,
              max: 1.0,
              format: (v) => '${(v * 100).round()}%',
              reserve: '100%',
              onChanged: widget.onOpacityChanged,
            ),
          ),
        ],
        if (p.foldColors)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.maskColor,
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpace.s10),
                _Swatches(
                  swatches: swatches,
                  selected: widget.selectedColor,
                  onSelected: widget.onColorChanged,
                ),
              ],
            ),
          ),
        if (p.foldBinary)
          MenuItemButton(
            leadingIcon: Icon(
              Icons.contrast,
              size: AppSize.iconLg,
              color: binaryOn ? scheme.primary : null,
            ),
            trailingIcon: binaryOn ? const Icon(Icons.check, size: AppSize.iconMd) : null,
            onPressed: widget.onToggleBinary,
            child: Text(
              l10n.binaryMode,
              style: binaryOn
                  ? TextStyle(color: scheme.onAccentTint, fontWeight: FontWeight.w600)
                  : null,
            ),
          ),
        if (p.foldComposite)
          MenuItemButton(
            leadingIcon: const Icon(Icons.layers_outlined, size: AppSize.iconLg),
            onPressed: widget.onSave,
            child: Text(l10n.maskSaveComposite),
          ),
        if (p.foldClear) ...[
          if (p.foldSliders || p.foldColors || p.foldBinary || p.foldComposite) const Divider(height: 9),
          MenuItemButton(
            leadingIcon: Icon(
              Icons.delete_sweep_outlined,
              size: AppSize.iconLg,
              color: widget.hasPaths ? scheme.error : null,
            ),
            onPressed: widget.hasPaths ? widget.onClear : null,
            child: Text(
              l10n.clear,
              style: widget.hasPaths ? TextStyle(color: scheme.error) : null,
            ),
          ),
        ],
      ],
      builder: (context, controller, _) => GlassIconButton(
        icon: Icons.more_vert,
        tooltip: l10n.more,
        active: controller.isOpen,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// A slider on glass (`1e` 「笔刷 · 透明度」): an optional 11px label word, an
/// 80px track (4px rail, 16px round thumb, the accent pure), and the value in
/// mono. The number is the point: a brush slider with no readout can only be
/// set by drawing and undoing.
class _GlassSlider extends StatelessWidget {
  const _GlassSlider({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.min,
    required this.max,
    required this.readout,
    required this.readoutWidth,
    required this.onChanged,
  });

  final String? label;
  final String tooltip;
  final double value;
  final double min;
  final double max;
  final String readout;

  /// The widest readout's width, which the readout always takes.
  final double readoutWidth;
  final ValueChanged<double> onChanged;

  static const double track = 80;

  /// Either side of the track: the thumb overhangs it by 8, and the label and
  /// readout keep clear of the thumb at either end.
  static const double side = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            maxLines: 1,
            softWrap: false,
            style: MaskEditorToolbar._captionStyle(context).copyWith(color: ink2),
          ),
          const SizedBox(width: side),
        ],
        SizedBox(
          width: track,
          height: AppSize.control,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: scheme.primary,
              inactiveTrackColor: ink.withValues(alpha: 0.16),
              thumbColor: scheme.primary,
              overlayColor: scheme.accentTint,
              trackShape: const RoundedRectSliderTrackShape(),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              // The track is the box: no inset for the overlay, so 80 is 80.
              padding: EdgeInsets.zero,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
              semanticFormatterCallback: (_) => '$tooltip $readout',
            ),
          ),
        ),
        const SizedBox(width: side),
        Tooltip(
          message: tooltip,
          child: SizedBox(
            width: readoutWidth,
            child: Text(
              readout,
              maxLines: 1,
              softWrap: false,
              style: MaskEditorToolbar._monoStyle(context).copyWith(color: ink),
            ),
          ),
        ),
      ],
    );
  }
}

/// A folded slider inside the ⋮ menu. Holds its own value while dragging, so
/// the thumb follows the pointer whether or not the menu's owner has rebuilt.
class _MenuSlider extends StatefulWidget {
  const _MenuSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.reserve,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final String Function(double) format;
  final String reserve;
  final ValueChanged<double> onChanged;

  @override
  State<_MenuSlider> createState() => _MenuSliderState();
}

class _MenuSliderState extends State<_MenuSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant _MenuSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = MaskEditorToolbar._monoStyle(context).copyWith(color: scheme.onSurface);

    return SizedBox(
      width: 240,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Slider(
                value: _value.clamp(widget.min, widget.max).toDouble(),
                min: widget.min,
                max: widget.max,
                onChanged: (v) {
                  setState(() => _value = v);
                  widget.onChanged(v);
                },
              ),
            ),
            SizedBox(
              width: measureGlassText(context, widget.reserve, mono).ceilToDouble(),
              child: Text(widget.format(_value), textAlign: TextAlign.end, style: mono),
            ),
          ],
        ),
      ),
    );
  }
}

/// The brush colours as 20px dots, 4 apart; the selected one ringed 2px in
/// the accent (`1e`). The ring stands outside the dot rather than thickening
/// its edge — a heavier border on a white dot reads as a different colour,
/// not as a selection.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.swatches, required this.selected, required this.onSelected});

  final List<(Color, String)> swatches;
  final Color selected;
  final ValueChanged<Color> onSelected;

  static const double _dot = 20;
  static const double _spacing = 4;

  static double widthFor(int count) => _spacing * 2 + count * _dot + (count - 1) * _spacing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = GlassInk.maybeOf(context)?.ink ?? scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _spacing),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < swatches.length; i++) ...[
            if (i > 0) const SizedBox(width: _spacing),
            _swatch(swatches[i].$1, swatches[i].$2, scheme, ink),
          ],
        ],
      ),
    );
  }

  Widget _swatch(Color color, String name, ColorScheme scheme, Color ink) {
    final isSelected = selected == color;
    return Tooltip(
      message: name,
      child: Semantics(
        button: true,
        selected: isSelected,
        label: name,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(color),
            child: SizedBox(
              width: _dot,
              height: _dot,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  // A faint inner edge so white reads on light glass and
                  // black on dark.
                  border: Border.all(color: ink.withValues(alpha: 0.15)),
                  boxShadow: isSelected ? [BoxShadow(color: scheme.primary, spreadRadius: 2)] : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Save Composite (`1e`): the neutral outlined form on glass — a 32px r10 box
/// edged in the glass edge, label over an 11px `to Workspace`, or the glyph
/// alone once labels have gone.
class _OutlinedSaveButton extends StatefulWidget {
  const _OutlinedSaveButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final String? label;
  final String? subtitle;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Horizontal space around the text: the 1px edge and 10px padding a side.
  static const double chrome = 2 + 10 + 10;

  static TextStyle labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(height: 1.15);

  @override
  State<_OutlinedSaveButton> createState() => _OutlinedSaveButtonState();
}

class _OutlinedSaveButtonState extends State<_OutlinedSaveButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final edge = glass?.edge ?? scheme.outlineVariant;
    final label = widget.label;

    Widget result = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.hover),
          curve: AppMotion.quick,
          height: AppSize.control,
          width: label == null ? AppSize.control : null,
          padding: label == null ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovering ? ink.withValues(alpha: 0.08) : Colors.transparent,
            border: Border.all(color: edge),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: label == null
              ? Icon(widget.icon, size: AppSize.iconLg, color: ink)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: _OutlinedSaveButton.labelStyle(context).copyWith(color: ink),
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        softWrap: false,
                        style: _TintedSaveButton.subtitleStyle(context)
                            .copyWith(color: ink.withValues(alpha: ink.a * 0.7)),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (label == null) result = Tooltip(message: widget.tooltip, child: result);
    return Semantics(button: true, label: widget.tooltip, child: result);
  }
}

/// Save Mask (`1e`): the accent's solid form on glass — tinted glass, 32 tall
/// at r10 — label over `to Workspace`. What the screen is for, so it never
/// folds; its glyph stands in for the word only past every other step.
class _TintedSaveButton extends StatelessWidget {
  const _TintedSaveButton({
    required this.label,
    required this.subtitle,
    required this.tooltip,
    required this.onPressed,
  });

  final String? label;
  final String? subtitle;
  final String tooltip;
  final VoidCallback onPressed;

  /// Horizontal padding around the text, 12px a side.
  static const double chrome = 12 + 12;

  static TextStyle labelStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .metricsOnly
      .copyWith(fontWeight: FontWeight.w600, height: 1.15);

  static TextStyle subtitleStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelSmall!
      .metricsOnly
      .copyWith(fontWeight: FontWeight.w400, height: 1.15);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = this.label;

    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: AppTintedGlass(
          child: SizedBox(
            height: AppSize.control,
            width: label == null ? AppSize.control : null,
            child: label == null
                ? const Icon(Icons.save_outlined, size: AppSize.iconLg)
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, maxLines: 1, softWrap: false, style: labelStyle(context)),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            softWrap: false,
                            style: subtitleStyle(context).copyWith(
                              color: scheme.onPrimary.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
    if (label == null) button = Tooltip(message: tooltip, child: button);
    return Semantics(button: true, label: tooltip, child: button);
  }
}
