import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../core/thumbnail_fit.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../state/app_state.dart';
import '../../../state/gallery_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/dialogs/thumbnail_size_dialog.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/glass_controls.dart';
import '../../../widgets/thumbnail_fit_toggle.dart';
import '../workbench_layout.dart';
import 'gallery_selection_bar.dart';

/// The workbench's tab indices, named.
abstract final class WorkbenchTab {
  static const int image = 0;
  static const int comparator = 1;
  static const int mask = 2;
  static const int crop = 3;
  static const int assistant = 4;
  static const int video = 5;

  /// The two tabs that are the gallery: image and video generation.
  static bool isGallery(int index) => index == image || index == video;
}

/// Picks images from the system gallery into the temporary workspace.
Future<void> pickImagesIntoWorkspace(GalleryState galleryState) async {
  final picked = await ImagePicker().pickMultiImage();
  if (picked.isEmpty) return;
  galleryState.addDroppedFiles(
    picked.map((f) => AppImage(path: f.path, name: f.name)).toList(),
  );
  galleryState.setViewMode(GalleryViewMode.temp);
}

/// Takes a photo into the temporary workspace (touch platforms).
Future<void> takePhotoIntoWorkspace(GalleryState galleryState) async {
  final photo = await ImagePicker().pickImage(source: ImageSource.camera);
  if (photo == null) return;
  galleryState.addDroppedFiles([AppImage(path: photo.path, name: photo.name)]);
  galleryState.setViewMode(GalleryViewMode.temp);
}

enum _View { sources, results, workspace }

/// Icon actions the gallery bar folds into its overflow menu, cheapest-meaning
/// first (`A1` spec: 导入 → 刷新 → 填充 → 尺寸).
enum _Fold { import, refresh, fit, size }

class _ToolDef {
  const _ToolDef(this.index, this.icon, this.shortLabel, this.fullLabel);
  final int index;
  final IconData icon;
  final String shortLabel;
  final String fullLabel;
}

List<_ToolDef> _tools(AppLocalizations l10n) => [
      _ToolDef(WorkbenchTab.comparator, Icons.compare, l10n.wbToolComparatorShort, l10n.comparator),
      _ToolDef(WorkbenchTab.mask, Icons.brush_outlined, l10n.wbToolMaskShort, l10n.maskEditor),
      _ToolDef(WorkbenchTab.crop, Icons.crop, l10n.wbToolCropShort, l10n.cropAndResize),
      _ToolDef(WorkbenchTab.assistant, Icons.auto_awesome_outlined, l10n.wbToolAssistantShort,
          l10n.promptOptimizer),
    ];

/// The one toolbar of the workbench (`A1 · 1a`, `A4–A6 · 1a`).
///
/// Desktop and tablet: a G2 glass bar, 44 tall at r16, floating 10px inside
/// the centre column over the content — the gallery scrolls under it. Phone:
/// the screen's one full-width G1 bar at the top (`A1 · 1e`).
///
/// Gallery tabs: sidebar toggle · image/video · the four tools · the view
/// switch · thumbnail size · fit/fill · refresh · import · more. Tool tabs:
/// back · the tool tabs — the tool's own controls sit under the bar until
/// each tool is rebuilt onto it.
///
/// Degrades by measurement, never by breakpoint (four languages, scaled
/// text): first the tool and mode labels go; then import, refresh, fit and
/// size fold into the overflow menu one at a time; then the tools collapse
/// into a Tools menu; the view switch never gives way and scrolls if it must.
class WorkbenchGlassToolbar extends StatefulWidget {
  const WorkbenchGlassToolbar({
    super.key,
    required this.tabController,
    this.phone = false,
    this.toolControls,
    this.toolControlsWidth = 0,
  });

  final TabController tabController;

  /// The phone's full-width bar instead of the floating one.
  final bool phone;

  /// A tool tab's own controls, laid out in the rest of the bar after the
  /// back button and the tool switch (`A4-A6`: the three tools share the
  /// header's place and height and only swap its contents). They fill the
  /// slot they are given and degrade inside it.
  final Widget? toolControls;

  /// The width [toolControls] would take with everything labelled. The tool
  /// switch gives up its labels before the controls have to give up theirs.
  final double toolControlsWidth;

  static const double height = 44;
  static const double inset = AppSpace.s10;

  /// Space content under the floating bar leaves above itself.
  static const double clearance = inset + height + inset;

  /// The phone bar's own row height.
  static const double phoneHeight = 56;

  static const double _barPadding = 6;
  static const double _gap = 4;

  @override
  State<WorkbenchGlassToolbar> createState() => _WorkbenchGlassToolbarState();
}

class _WorkbenchGlassToolbarState extends State<WorkbenchGlassToolbar> {
  /// The gallery tab the back button returns to. UI-only memory, deliberately
  /// not persisted: it answers "where was I a moment ago".
  int _lastGalleryTab = WorkbenchTab.image;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.tabController,
      builder: (context, _) {
        final active = widget.tabController.index;
        if (WorkbenchTab.isGallery(active)) _lastGalleryTab = active;

        final row = LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return WorkbenchTab.isGallery(active)
                ? _GalleryRow(
                    tabController: widget.tabController,
                    active: active,
                    width: width,
                    phone: widget.phone,
                  )
                : _ToolRow(
                    tabController: widget.tabController,
                    active: active,
                    width: width,
                    phone: widget.phone,
                    backTo: _lastGalleryTab,
                    controls: widget.toolControls,
                    controlsWidth: widget.toolControlsWidth,
                  );
          },
        );

        if (widget.phone) {
          return AppGlass(
            grade: GlassGrade.bar,
            edges: GlassEdges.bottom,
            shadow: false,
            child: SizedBox(
              height: WorkbenchGlassToolbar.phoneHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WorkbenchGlassToolbar._barPadding),
                child: row,
              ),
            ),
          );
        }
        return SizedBox(
          height: WorkbenchGlassToolbar.height,
          child: AppGlass(
            grade: GlassGrade.float,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            padding: const EdgeInsets.symmetric(horizontal: WorkbenchGlassToolbar._barPadding),
            child: row,
          ),
        );
      },
    );
  }
}

/// Lays [children] out with the bar's 4px gap.
Widget _barRow(List<Widget> children) => Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: WorkbenchGlassToolbar._gap),
          children[i],
        ],
      ],
    );

double _sumWithGaps(List<double> widths) =>
    widths.fold<double>(0, (a, b) => a + b) +
    WorkbenchGlassToolbar._gap * (widths.length - 1) +
    WorkbenchGlassToolbar._barPadding * 2;

class _GalleryRow extends StatelessWidget {
  const _GalleryRow({
    required this.tabController,
    required this.active,
    required this.width,
    required this.phone,
  });

  final TabController tabController;
  final int active;
  final double width;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final layout = context.watch<WorkbenchLayoutState>();
    final isSidebarExpanded = context.select<AppState, bool>((s) => s.isSidebarExpanded);
    final fit = context.select<AppState, ThumbnailFit>((s) => s.thumbnailFit);
    final gallery = context.watch<GalleryState>();
    final tools = _tools(l10n);

    final isTemp = gallery.viewMode == GalleryViewMode.temp;
    final isResult = gallery.viewMode == GalleryViewMode.processed ||
        (gallery.viewMode == GalleryViewMode.folder && gallery.folderViewIsResult);
    final view = isTemp ? _View.workspace : (isResult ? _View.results : _View.sources);

    final modeSegments = [
      GlassSegment(value: WorkbenchTab.image, label: l10n.wbModeImage, icon: Icons.image_outlined),
      GlassSegment(value: WorkbenchTab.video, label: l10n.wbModeVideo, icon: Icons.movie_outlined),
    ];
    final viewSegments = [
      GlassSegment(
        value: _View.sources,
        label: phone ? l10n.galleryViewSourcesShort : l10n.allSources,
      ),
      GlassSegment(
        value: _View.results,
        label: phone ? l10n.galleryViewResultsShort : l10n.allResults,
      ),
      if (isTemp) GlassSegment(value: _View.workspace, label: l10n.galleryViewWorkspace),
    ];

    bool labels = true;
    bool toolsInline = !phone;
    bool toolsMenuCompact = false;
    final folded = <_Fold>{if (phone) ..._Fold.values};
    final showTune = layout.rightInDrawer && !phone;

    double toolsMenuWidth() => toolsMenuCompact
        ? 10 + AppSize.iconLg + 4 + AppSize.iconMd + 10
        : GlassIconButton.widthFor(context, label: l10n.wbTools, hasIcon: false) + 4 + AppSize.iconMd;
    final viewNatural = GlassSegmented.widthFor(context, viewSegments, showLabels: true);

    double measure() {
      final inlineIcons = _Fold.values.where((f) => !folded.contains(f)).length;
      final widths = <double>[
        AppSize.control, // sidebar
        GlassSegmented.widthFor(context, modeSegments, showLabels: labels),
        if (toolsInline) ...[
          GlassDivider.extent,
          for (final t in tools) GlassIconButton.widthFor(context, label: labels ? t.shortLabel : null),
        ] else
          toolsMenuWidth(),
        viewNatural,
        if (inlineIcons > 0) GlassDivider.extent,
        for (int i = 0; i < inlineIcons; i++) AppSize.control,
        AppSize.control, // more
        if (showTune) AppSize.control,
      ];
      return _sumWithGaps(widths);
    }

    if (measure() > width) labels = false;
    if (!phone) {
      for (final f in _Fold.values) {
        if (measure() <= width) break;
        folded.add(f);
      }
      if (measure() > width) toolsInline = false;
    }
    if (measure() > width) toolsMenuCompact = true;
    // The view switch never gives way: past every other step it keeps what
    // is left and scrolls inside it.
    final viewWidth = math.max(0.0, math.min(viewNatural, width - (measure() - viewNatural)));

    final appState = context.read<AppState>();
    void goTo(int index) => tabController.index = index;

    final children = <Widget>[
      if (layout.leftInDrawer)
        GlassIconButton(
          icon: Icons.menu,
          tooltip: l10n.workbench,
          onPressed: () => context.read<WorkbenchLayoutState>().openLeftPanel(),
        )
      else
        GlassIconButton(
          icon: isSidebarExpanded ? Icons.menu_open : Icons.menu,
          tooltip: l10n.workbench,
          onPressed: () => appState.setSidebarExpanded(!isSidebarExpanded),
        ),
      GlassSegmented<int>(
        segments: modeSegments,
        value: active,
        onChanged: goTo,
        showLabels: labels,
        accent: true,
        segmentHeight: phone ? AppSize.control : AppSize.compact,
      ),
      if (toolsInline) ...[
        const GlassDivider(),
        for (final t in tools)
          GlassIconButton(
            icon: t.icon,
            label: labels ? t.shortLabel : null,
            tooltip: t.fullLabel,
            onPressed: () => goTo(t.index),
          ),
      ] else
        _ToolsMenuButton(
          tools: tools,
          activeIndex: active,
          onSelect: goTo,
          includeCapture: phone,
          compact: toolsMenuCompact,
        ),
      const Expanded(child: SizedBox()),
      SizedBox(
        width: viewWidth,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: GlassSegmented<_View>(
            segments: viewSegments,
            value: view,
            segmentHeight: phone ? AppSize.control : AppSize.compact,
            onChanged: (v) => gallery.setViewMode(switch (v) {
              _View.sources => GalleryViewMode.all,
              _View.results => GalleryViewMode.processed,
              _View.workspace => GalleryViewMode.temp,
            }),
          ),
        ),
      ),
      if (_Fold.values.any((f) => !folded.contains(f))) const GlassDivider(),
      if (!folded.contains(_Fold.size)) const _ThumbnailSizeButton(),
      if (!folded.contains(_Fold.fit))
        GlassIconButton(
          icon: thumbnailFitIcon(fit),
          active: fit == ThumbnailFit.fill,
          tooltip: thumbnailFitLabel(l10n, fit),
          onPressed: () => appState.setThumbnailFit(
              fit == ThumbnailFit.fill ? ThumbnailFit.fit : ThumbnailFit.fill),
        ),
      if (!folded.contains(_Fold.refresh))
        GlassIconButton(
          icon: Icons.refresh,
          tooltip: l10n.refresh,
          onPressed: gallery.refreshImages,
        ),
      if (!folded.contains(_Fold.import))
        GlassIconButton(
          icon: Icons.add_photo_alternate_outlined,
          tooltip: l10n.importFromGallery,
          onPressed: () => pickImagesIntoWorkspace(gallery),
        ),
      _GalleryOverflowMenu(folded: folded, phone: phone),
      if (showTune)
        GlassIconButton(
          icon: Icons.tune,
          tooltip: l10n.wbGenerationConfig,
          onPressed: () => context.read<WorkbenchLayoutState>().openRightPanel(),
        ),
    ];

    return _barRow(children);
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.tabController,
    required this.active,
    required this.width,
    required this.phone,
    required this.backTo,
    required this.controls,
    required this.controlsWidth,
  });

  final TabController tabController;
  final int active;
  final double width;
  final bool phone;
  final int backTo;
  final Widget? controls;
  final double controlsWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final layout = context.watch<WorkbenchLayoutState>();
    final tools = _tools(l10n);
    final segments = [
      for (final t in tools)
        GlassSegment(value: t.index, label: t.shortLabel, icon: t.icon, tooltip: t.fullLabel),
    ];
    final showTune = layout.rightInDrawer;

    bool labels = !phone;
    bool inline = true;
    bool compact = false;
    double measure() => _sumWithGaps([
          AppSize.control,
          inline
              ? GlassSegmented.widthFor(context, segments, showLabels: labels)
              : compact
                  ? 10 + AppSize.iconLg + 4 + AppSize.iconMd + 10
                  : GlassIconButton.widthFor(context, label: l10n.wbTools, hasIcon: false) + 4 + AppSize.iconMd,
          if (controls != null) ...[GlassDivider.extent, controlsWidth],
          if (showTune) AppSize.control,
        ]);
    if (measure() > width) labels = false;
    if (measure() > width) inline = false;
    if (measure() > width) compact = true;

    return _barRow([
      GlassIconButton(
        icon: Icons.arrow_back,
        tooltip: l10n.back,
        onPressed: () => tabController.index = backTo,
      ),
      if (inline)
        GlassSegmented<int>(
          segments: segments,
          value: active,
          onChanged: (i) => tabController.index = i,
          showLabels: labels,
          accent: true,
          segmentHeight: phone ? AppSize.control : AppSize.compact,
        )
      else
        _ToolsMenuButton(
          tools: tools,
          activeIndex: active,
          onSelect: (i) => tabController.index = i,
          includeCapture: false,
          compact: compact,
        ),
      if (controls != null) ...[
        const GlassDivider(),
        Expanded(child: controls!),
      ] else
        const Expanded(child: SizedBox()),
      if (showTune)
        GlassIconButton(
          icon: Icons.tune,
          tooltip: l10n.wbGenerationConfig,
          onPressed: () => context.read<WorkbenchLayoutState>().openRightPanel(),
        ),
    ]);
  }
}

/// The tools collapsed into one menu (`A1 · 1e` 「工具」). On a phone it also
/// carries capture and import, which have no other home there.
class _ToolsMenuButton extends StatelessWidget {
  const _ToolsMenuButton({
    required this.tools,
    required this.activeIndex,
    required this.onSelect,
    required this.includeCapture,
    this.compact = false,
  });

  final List<_ToolDef> tools;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final bool includeCapture;

  /// Glyph and chevron only — the last step before the bar scrolls.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final gallery = context.read<GalleryState>();
    final activeTool = tools.where((t) => t.index == activeIndex).firstOrNull;
    final isTouch = Platform.isAndroid || Platform.isIOS;

    return MenuAnchor(
      menuChildren: [
        for (final t in tools)
          MenuItemButton(
            leadingIcon: Icon(t.icon,
                size: AppSize.iconLg,
                color: t.index == activeIndex ? scheme.primary : null),
            onPressed: () => onSelect(t.index),
            child: Text(t.fullLabel),
          ),
        if (includeCapture) ...[
          const Divider(height: 9),
          if (isTouch)
            MenuItemButton(
              leadingIcon: const Icon(Icons.photo_camera_outlined, size: AppSize.iconLg),
              onPressed: () => takePhotoIntoWorkspace(gallery),
              child: Text(l10n.takePhoto),
            ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.add_photo_alternate_outlined, size: AppSize.iconLg),
            onPressed: () => pickImagesIntoWorkspace(gallery),
            child: Text(l10n.importFromGallery),
          ),
        ],
      ],
      builder: (context, controller, _) {
        final glass = GlassInk.maybeOf(context);
        final ink = glass?.ink ?? scheme.onSurface;
        final isActive = activeTool != null;
        return GestureDetector(
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              height: AppSize.control,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive || controller.isOpen ? scheme.accentTint : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (compact)
                    Tooltip(
                      message: activeTool?.fullLabel ?? l10n.wbTools,
                      child: Icon(
                        activeTool?.icon ?? Icons.handyman_outlined,
                        size: AppSize.iconLg,
                        color: isActive ? scheme.primary : ink,
                      ),
                    )
                  else
                  Text(
                    activeTool?.shortLabel ?? l10n.wbTools,
                    style: GlassIconButton.labelStyle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: isActive ? scheme.onAccentTint : ink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more,
                      size: AppSize.iconMd, color: isActive ? scheme.onAccentTint : ink),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Thumbnail size as a popover slider (`A1 · 1a`: a G2 panel under the button,
/// 80–400 with mono end labels).
class _ThumbnailSizeButton extends StatelessWidget {
  const _ThumbnailSizeButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MenuAnchor(
      menuChildren: [
        Consumer<GalleryState>(
          builder: (context, gallery, _) {
            final textTheme = Theme.of(context).textTheme;
            final scheme = Theme.of(context).colorScheme;
            final mono = textTheme.labelSmall!.mono.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            );
            return SizedBox(
              width: 220,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.thumbnailSize,
                            style: textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(gallery.thumbnailSize.round().toString(), style: mono),
                      ],
                    ),
                    Slider(
                      value: gallery.thumbnailSize.clamp(80, 400),
                      min: 80,
                      max: 400,
                      onChanged: gallery.setThumbnailSize,
                      onChangeEnd: (_) => gallery.persistThumbnailSize(),
                    ),
                    Row(
                      children: [
                        Text('80', style: mono),
                        const Spacer(),
                        Text('400', style: mono),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
      builder: (context, controller, _) => GlassIconButton(
        icon: Icons.photo_size_select_large,
        tooltip: l10n.thumbnailSize,
        active: controller.isOpen,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Everything that did not fit on the bar, plus the actions that only ever
/// live here (select all, clearing the workspace, capture on touch, the
/// concurrency limit on a phone).
class _GalleryOverflowMenu extends StatelessWidget {
  const _GalleryOverflowMenu({required this.folded, required this.phone});

  final Set<_Fold> folded;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final gallery = context.watch<GalleryState>();
    final appState = context.read<AppState>();
    final fit = context.select<AppState, ThumbnailFit>((s) => s.thumbnailFit);
    final isTouch = Platform.isAndroid || Platform.isIOS;
    final canClearWorkspace =
        gallery.viewMode == GalleryViewMode.temp && gallery.droppedImages.isNotEmpty;

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.select_all, size: AppSize.iconLg),
          onPressed: gallery.selectAllImages,
          child: Text(l10n.selectAll),
        ),
        if (folded.contains(_Fold.size))
          MenuItemButton(
            leadingIcon: const Icon(Icons.photo_size_select_large, size: AppSize.iconLg),
            onPressed: () => showThumbnailSizeDialog(
              context,
              initialSize: gallery.thumbnailSize,
              onChanged: gallery.setThumbnailSize,
              onChangeEnd: gallery.persistThumbnailSize,
            ),
            child: Text(l10n.thumbnailSize),
          ),
        if (folded.contains(_Fold.fit))
          for (final option in ThumbnailFit.values)
            MenuItemButton(
              leadingIcon: Icon(
                option == fit ? Icons.check : thumbnailFitIcon(option),
                size: AppSize.iconLg,
                color: option == fit ? scheme.primary : null,
              ),
              onPressed: () => appState.setThumbnailFit(option),
              child: Text(thumbnailFitLabel(l10n, option)),
            ),
        if (folded.contains(_Fold.refresh))
          MenuItemButton(
            leadingIcon: const Icon(Icons.refresh, size: AppSize.iconLg),
            onPressed: gallery.refreshImages,
            child: Text(l10n.refresh),
          ),
        if (folded.contains(_Fold.import) && !phone)
          MenuItemButton(
            leadingIcon: const Icon(Icons.add_photo_alternate_outlined, size: AppSize.iconLg),
            onPressed: () => pickImagesIntoWorkspace(gallery),
            child: Text(l10n.importFromGallery),
          ),
        if (isTouch && !phone)
          MenuItemButton(
            leadingIcon: const Icon(Icons.photo_camera_outlined, size: AppSize.iconLg),
            onPressed: () => takePhotoIntoWorkspace(gallery),
            child: Text(l10n.takePhoto),
          ),
        if (phone)
          MenuItemButton(
            leadingIcon: const Icon(Icons.sync_alt, size: AppSize.iconLg),
            onPressed: () => _showConcurrencyDialog(context, l10n),
            child: Text(l10n.concurrencyLimit(appState.concurrencyLimit)),
          ),
        if (canClearWorkspace) ...[
          const Divider(height: 9),
          MenuItemButton(
            leadingIcon: Icon(Icons.delete_sweep_outlined, size: AppSize.iconLg, color: scheme.error),
            onPressed: () => confirmClearTempWorkspace(context, gallery, l10n),
            child: Text(l10n.clearTempWorkspace, style: TextStyle(color: scheme.error)),
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

  void _showConcurrencyDialog(BuildContext context, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final appState = Provider.of<AppState>(dialogContext);
          return AppDialog(
            title: l10n.concurrencyLimit(appState.concurrencyLimit),
            content: Slider(
              value: appState.concurrencyLimit.toDouble(),
              min: 1,
              max: AppConstants.maxConcurrency.toDouble(),
              divisions: AppConstants.maxConcurrency - 1,
              onChanged: (v) {
                appState.setConcurrency(v.round());
                setDialogState(() {});
              },
            ),
            actions: [
              AppButton(
                label: l10n.close,
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          );
        },
      ),
    );
  }
}
