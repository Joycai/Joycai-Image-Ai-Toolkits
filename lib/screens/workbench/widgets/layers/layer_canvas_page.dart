import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../../core/app_theme.dart';
import '../../../../core/design_tokens.dart';
import '../../../../core/file_utils.dart';
import '../../../../core/responsive.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_image.dart';
import '../../../../models/image_layer.dart';
import '../../../../services/media/image_metadata_service.dart';
import '../../../../services/media/layer_composite_service.dart';
import '../../../../state/gallery_state.dart';
import '../../../../widgets/shell/shell_cover.dart';
import '../../../../widgets/ui/app_button.dart';
import '../../../../widgets/ui/app_icon_button.dart';
import '../../../../widgets/ui/app_section_label.dart';
import '../../../../widgets/ui/app_snackbar.dart';
import '../preview/media_preview_dialog.dart';
import 'layer_stack_view.dart';

/// Opens the layer canvas for the decomposition [path] belongs to, or says
/// why it cannot (its layers are gone from disk).
Future<void> openLayerCanvas(BuildContext context, String path) async {
  final set = await context.read<GalleryState>().layerSetFor(path);
  if (!context.mounted) return;
  if (set == null) {
    AppSnackBar.info(context, AppLocalizations.of(context)!.layerSetUnavailable);
    return;
  }
  await showLayerCanvas(context, set, path);
}

/// Pushes the layer canvas for an already loaded [set], opened from [path].
Future<void> showLayerCanvas(BuildContext context, ImageLayerSet set, String path) async {
  // Selected on entry when the user came from one of the layers, so the
  // canvas shows at once which one that was.
  final initial = set.overlays.any((l) => l.path == path) ? path : null;
  await Navigator.of(context).push(
    FullScreenCoverRoute<void>(
      fullscreenDialog: true,
      transitionDuration: AppMotion.durationOf(context, AppMotion.reveal),
      reverseTransitionDuration: AppMotion.durationOf(context, AppMotion.reveal),
      pageBuilder: (_, _, _) => LayerCanvasPage(set: set, initialSelection: initial),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The layer canvas (`A7`): a decomposition stacked back as it came out —
/// each layer in its box on the base — with per-layer visibility, a picked
/// layer outlined, and the visible stack exported as one PNG.
///
/// Restoration only: nothing here moves, resizes, reorders or renames a
/// layer. Visibility and selection are this page's alone and end with it.
class LayerCanvasPage extends StatefulWidget {
  const LayerCanvasPage({super.key, required this.set, this.initialSelection});

  final ImageLayerSet set;
  final String? initialSelection;

  @override
  State<LayerCanvasPage> createState() => _LayerCanvasPageState();
}

class _LayerCanvasPageState extends State<LayerCanvasPage> {
  final TransformationController _transformation = TransformationController();
  Set<String> _hidden = const {};
  String? _selected;
  bool _showBounds = false;
  bool _exporting = false;

  /// The base's pixel size — the canvas's coordinate system. Null until it
  /// is read; without a base, the extent of the boxes stands in.
  Size? _baseSize;

  ImageLayerSet get _set => widget.set;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _readBaseSize();
  }

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  Future<void> _readBaseSize() async {
    final base = _set.base;
    Size? size;
    if (base != null) {
      final meta = await ImageMetadataService().readNow(base.path);
      if (meta != null && meta.width > 0 && meta.height > 0) {
        size = Size(meta.width.toDouble(), meta.height.toDouble());
      }
    }
    size ??= _extentOfBoxes();
    if (mounted) setState(() => _baseSize = size);
  }

  Size _extentOfBoxes() {
    var w = 1;
    var h = 1;
    for (final l in _set.overlays) {
      final b = l.box;
      if (b == null) continue;
      w = math.max(w, b.right);
      h = math.max(h, b.bottom);
    }
    return Size(w.toDouble(), h.toDouble());
  }

  void _toggle(String path) => setState(() {
    _hidden = _hidden.contains(path) ? ({..._hidden}..remove(path)) : {..._hidden, path};
  });

  void _select(String? path) => setState(() => _selected = path == _selected ? null : path);

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context)!;
    final size = _baseSize;
    if (size == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final visible = [
        for (final l in _set.layers)
          if (!_hidden.contains(l.path)) l,
      ];
      final png = await LayerCompositeService.composite(
        visible,
        size.width.round(),
        size.height.round(),
      );
      final anchor = (_set.base ?? _set.layers.first).path;
      await LayerCompositeService.save(anchor, png);
      if (mounted) AppSnackBar.success(context, l10n.layerExported);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, l10n.layerExportFailed('$e'));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openLayer(ImageLayer layer) {
    final images = [for (final l in _set.layers) AppImage(path: l.path, name: p.basename(l.path))];
    showMediaPreview(
      context,
      galleryImages: images,
      initialIndex: _set.layers.indexWhere((l) => l.path == layer.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);
    final isDesktop = Responsive.isDesktop(context);
    final size = _baseSize;

    final canvas = size == null
        ? const SizedBox.expand()
        : LayoutBuilder(
            builder: (context, constraints) {
              return LayerStackView(
                set: _set,
                baseSize: size,
                hidden: _hidden,
                selected: _selected,
                showBounds: _showBounds,
                onSelect: (path) => setState(() => _selected = path),
                transformation: _transformation,
                padding: isMobile
                    ? EdgeInsets.only(bottom: constraints.maxHeight * 0.4)
                    : EdgeInsets.zero,
              );
            },
          );

    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(context, isMobile: isMobile, isDesktop: isDesktop),
            Expanded(
              child: isMobile
                  ? Stack(
                      children: [
                        Positioned.fill(child: canvas),
                        _mobileSheet(context),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: canvas),
                        Container(
                          width: isDesktop ? 300 : 260,
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            border: Border(left: BorderSide(color: scheme.outlineVariant)),
                          ),
                          child: _sidePanel(context, withDetails: isDesktop),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, {required bool isMobile, required bool isDesktop}) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final size = _baseSize;
    final anchor = _set.base ?? _set.layers.first;
    final count = _set.overlays.length;
    final w = size?.width.round() ?? 0;
    final h = size?.height.round() ?? 0;
    final buttonSize = isMobile ? AppSize.large : AppSize.iconButton;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            size: buttonSize,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMobile ? l10n.layerListLabel : l10n.layerCanvasTitle(p.basename(anchor.path)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (size != null)
                  Text(
                    isMobile
                        ? l10n.layerCanvasSubtitleShort(w, h, count)
                        : l10n.layerCanvasSubtitle(w, h, count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (isDesktop)
            AppButton(
              label: l10n.layerShowBounds,
              icon: Icons.select_all,
              variant: AppButtonVariant.text,
              accentLabel: _showBounds,
              onPressed: () => setState(() => _showBounds = !_showBounds),
            )
          else
            AppIconButton(
              icon: Icons.select_all,
              tooltip: l10n.layerShowBounds,
              selected: _showBounds,
              size: buttonSize,
              onPressed: () => setState(() => _showBounds = !_showBounds),
            ),
          if (!isMobile) ...[
            if (isDesktop)
              AppButton(
                label: l10n.layerFit,
                icon: Icons.fit_screen,
                variant: AppButtonVariant.text,
                onPressed: () => _transformation.value = Matrix4.identity(),
              )
            else
              AppIconButton(
                icon: Icons.fit_screen,
                tooltip: l10n.layerFit,
                onPressed: () => _transformation.value = Matrix4.identity(),
              ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
              color: scheme.outlineVariant,
            ),
          ],
          if (isMobile)
            Tooltip(
              message: l10n.layerExport,
              child: SizedBox.square(
                dimension: AppSize.large,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  onPressed: size == null || _exporting ? null : _export,
                  child: const Icon(Icons.download, size: AppSize.iconLg),
                ),
              ),
            )
          else
            AppButton(
              label: l10n.layerExport,
              icon: Icons.download,
              loading: _exporting,
              onPressed: size == null ? null : _export,
            ),
        ],
      ),
    );
  }

  /// The layer list, top of the stack first (`A7 · 7a` ②), the base last
  /// under a hairline.
  List<Widget> _rows(
    BuildContext context, {
    required bool withSubtitle,
    required double rowHeight,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final overlays = _set.overlays.reversed.toList();
    return [
      for (final l in overlays)
        _LayerRow(
          key: ValueKey(l.path),
          layer: l,
          title: l.name ?? AppLocalizations.of(context)!.layerUnnamed(l.zIndex),
          subtitle: withSubtitle && l.path == _selected && l.box != null
              ? '${AppLocalizations.of(context)!.layerPosition(l.box!.left, l.box!.top)} · '
                    '${AppLocalizations.of(context)!.layerSize(l.box!.width, l.box!.height)}'
              : l.description,
          selected: l.path == _selected,
          hidden: _hidden.contains(l.path),
          height: rowHeight,
          onTap: () => _select(l.path),
          onToggle: () => _toggle(l.path),
        ),
      if (_set.base case final base?) ...[
        Divider(
          height: 9,
          indent: AppSpace.s10,
          endIndent: AppSpace.s10,
          color: scheme.outlineVariant,
        ),
        _LayerRow(
          key: ValueKey(base.path),
          layer: base,
          title: AppLocalizations.of(context)!.layerBase,
          subtitle: _baseSize == null
              ? null
              : '${_baseSize!.width.round()}×${_baseSize!.height.round()}',
          selected: false,
          hidden: _hidden.contains(base.path),
          height: rowHeight,
          onTap: null,
          onToggle: () => _toggle(base.path),
        ),
      ],
    ];
  }

  Widget _listHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AppSectionLabel(
      l10n.layerListLabel,
      padding: const EdgeInsets.fromLTRB(AppSpace.s6, AppSpace.s10, 0, AppSpace.s4),
      suffix: TextSpan(
        text: '  ${l10n.layerListCount(_set.overlays.length)}',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
      ),
      trailing: AppIconButton(
        icon: Icons.visibility_outlined,
        tooltip: l10n.layerShowAll,
        onPressed: _hidden.isEmpty ? null : () => setState(() => _hidden = const {}),
      ),
    );
  }

  Widget _sidePanel(BuildContext context, {required bool withDetails}) {
    ImageLayer? chosen;
    for (final l in _set.overlays) {
      if (l.path == _selected) chosen = l;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
            children: [
              _listHeader(context),
              ..._rows(context, withSubtitle: !withDetails, rowHeight: 52),
            ],
          ),
        ),
        if (withDetails && chosen != null) _details(context, chosen),
      ],
    );
  }

  Widget _details(BuildContext context, ImageLayer layer) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget chip(String label) => DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(label, style: text.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant)),
      ),
    );
    final box = layer.box;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionLabel(
            layer.name ?? l10n.layerUnnamed(layer.zIndex),
            padding: const EdgeInsets.only(bottom: AppSpace.s4),
          ),
          if (layer.description != null) ...[
            Text(
              layer.description!,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: AppType.proseHeight,
              ),
            ),
            const SizedBox(height: AppSpace.s6),
          ],
          Wrap(
            spacing: AppSpace.s6,
            runSpacing: AppSpace.s4,
            children: [
              if (box != null) chip(l10n.layerPosition(box.left, box.top)),
              if (box != null) chip(l10n.layerSize(box.width, box.height)),
              chip(l10n.layerOrdinal(layer.zIndex)),
            ],
          ),
          const SizedBox(height: AppSpace.s6),
          Wrap(
            spacing: AppSpace.s4,
            children: [
              AppButton(
                label: l10n.layerOpenThis,
                icon: Icons.open_in_new,
                variant: AppButtonVariant.text,
                size: AppButtonSize.compact,
                accentLabel: true,
                onPressed: () => _openLayer(layer),
              ),
              AppButton(
                label: l10n.openInFolder,
                icon: Icons.folder_open_outlined,
                variant: AppButtonVariant.text,
                size: AppButtonSize.compact,
                accentLabel: true,
                onPressed: () => FileUtils.openFolder(layer.path),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mobileSheet(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.85,
      builder: (context, controller) => DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            AppSpace.s6,
            AppSpace.s6,
            AppSpace.s6,
            AppSpace.s22 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _listHeader(context),
            ..._rows(context, withSubtitle: true, rowHeight: 56),
          ],
        ),
      ),
    );
  }
}

/// One row of the layer list (`A7 · 7a`): thumbnail on the checkerboard,
/// name and one line under it, the eye.
class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.layer,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.hidden,
    required this.height,
    required this.onTap,
    required this.onToggle,
  });

  final ImageLayer layer;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool hidden;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final eyeSize = height > 52 ? AppSize.large : AppSize.iconButton;
    return Opacity(
      opacity: hidden ? 0.55 : 1,
      child: Material(
        color: selected ? scheme.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox.square(
                      dimension: 40,
                      child: CustomPaint(
                        painter: CheckerboardPainter(
                          light: scheme.surfaceContainerLow,
                          dark: scheme.surfaceContainerHigh,
                          cell: 8,
                        ),
                        child: Image.file(
                          File(layer.path),
                          fit: BoxFit.contain,
                          cacheWidth: 96,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? scheme.onAccentTint : scheme.onSurface,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  AppIconButton(
                    icon: hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    tooltip: hidden ? l10n.layerShow : l10n.layerHide,
                    color: selected ? scheme.primary : null,
                    size: eyeSize,
                    onPressed: onToggle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
