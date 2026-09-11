import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../services/file_permission_service.dart';
import '../../state/gallery_state.dart';
import '../../widgets/drag/app_drop_zone.dart';
import '../../widgets/placeholders/permission_placeholder.dart';
import 'widgets/image_card.dart';
import 'widgets/preview/media_preview_dialog.dart';
import 'widgets/workbench_glass_toolbar.dart';
import 'workbench_layout.dart';

/// Everything the grid reads out of [GalleryState], gathered so the selector
/// in `build` can compare it in one go.
///
/// Pointedly missing: the selection. It is read per cell by the `Selector`
/// inside the sliver delegate; putting it here would rebuild every visible
/// card for a change that concerns one of them.
///
/// [images] compares by identity, which [GalleryState] guarantees — it always
/// assigns a fresh list before notifying.
typedef _GridInputs = ({
  GalleryViewMode mode,
  List<AppImage> images,
  bool isResult,
  bool isTemp,
  String? permissionPath,
  bool isUnreachable,
  bool isScanning,
  double thumbnailSize,
});

_GridInputs _gridInputs(GalleryState s) {
  final isResult = s.viewMode == GalleryViewMode.processed ||
      (s.viewMode == GalleryViewMode.folder && s.folderViewIsResult);
  final isTemp = s.viewMode == GalleryViewMode.temp;
  final permissionPath = isResult
      ? s.outputDirectory
      : (s.viewMode == GalleryViewMode.folder ? s.viewSourcePath : null);
  return (
    mode: s.viewMode,
    images: s.currentViewImages,
    isResult: isResult,
    isTemp: isTemp,
    permissionPath: permissionPath,
    isUnreachable:
        !isTemp && permissionPath != null && s.isPathUnreachable(permissionPath),
    isScanning: s.isScanning,
    thumbnailSize: s.thumbnailSize,
  );
}

/// The workbench gallery (`A1 · 1a`): cards straight on the window's aurora,
/// scrolling under the floating toolbar and above the selection bar.
class Gallery extends StatefulWidget {
  const Gallery({
    super.key,
    this.extraBottomInset = 0,
  });

  /// Space below the grid that something other than the layout's chrome
  /// covers — the video tab's player panel (`A2 · 1a`).
  final double extraBottomInset;

  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  bool _isDragging = false;

  /// Paths the last drop from the operating system added, and the token that
  /// rings their cards (`00d` 确认 「画廊新卡 --ok 环」).
  Set<String> _confirmedPaths = const {};
  Object? _confirmToken;
  Timer? _confirmTimer;

  /// How long the added paths stay marked: past the ring's own 600ms + M1
  /// (1.2s with less motion), so clearing them never cuts a ring short.
  static const Duration _confirmWindow = Duration(milliseconds: 1500);

  /// Grid gutter and inset (`A1` spec: 卡 gap 10).
  static const double _gap = AppSpace.s10;

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  void _handleDrop(DropDoneDetails details, GalleryState galleryState) {
    setState(() => _isDragging = false);
    final List<AppImage> newFiles = [];
    for (var file in details.files) {
      if (AppConstants.isSupportedFile(file.path)) {
        newFiles.add(AppImage(path: file.path, name: file.name));
      }
    }
    if (newFiles.isEmpty) return;

    final existing = {for (final image in galleryState.droppedImages) image.path};
    galleryState.addDroppedFiles(newFiles);
    galleryState.setViewMode(GalleryViewMode.temp);
    _ringNewCards({
      for (final file in newFiles)
        if (!existing.contains(file.path)) file.path,
    });
  }

  /// Rings the cards of [paths] once they are on screen.
  ///
  /// A ring fires on a *change* of its trigger, and a card mounted by this
  /// drop has nothing to change from — so this frame mounts the new cards
  /// with no trigger, and the next hands them the token.
  void _ringNewCards(Set<String> paths) {
    if (paths.isEmpty) return;
    _confirmTimer?.cancel();
    setState(() {
      _confirmedPaths = paths;
      _confirmToken = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _confirmToken = Object());
      _confirmTimer = Timer(_confirmWindow, () {
        if (!mounted) return;
        setState(() {
          _confirmedPaths = const {};
          _confirmToken = null;
        });
      });
    });
  }

  /// How much of the column the floating chrome covers, from the layout that
  /// hosts this gallery. Zero outside a workbench layout (tests, previews).
  EdgeInsets _chromeInsets(BuildContext context) {
    try {
      final layout = Provider.of<WorkbenchLayoutState>(context);
      return EdgeInsets.only(top: layout.topClearance, bottom: layout.bottomClearance);
    } on ProviderNotFoundException {
      return EdgeInsets.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    final galleryState = context.read<GalleryState>();
    final grid = context.select<GalleryState, _GridInputs>(_gridInputs);
    final chrome = _chromeInsets(context);
    final insets = chrome.copyWith(bottom: chrome.bottom + widget.extraBottomInset);

    final l10n = AppLocalizations.of(context)!;

    return DropTarget(
      onDragDone: (details) => _handleDrop(details, galleryState),
      onDragEntered: (details) => setState(() => _isDragging = true),
      onDragExited: (details) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          Positioned.fill(child: _buildImageGrid(context, galleryState, grid, insets)),
          // `00d · 1c` 整面投放: `--scrim` with no blur, between the floating
          // toolbar and the bar below — as the frame draws it, so the
          // chrome's glass never blurs a scrim.
          if (_isDragging)
            Positioned(
              left: 0,
              right: 0,
              top: insets.top,
              bottom: insets.bottom,
              child: IgnorePointer(
                child: AppDropSurfaceOverlay(
                  title: l10n.galleryDropTitle,
                  subtitle: l10n.galleryDropSystemHint,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _reAuthorize(BuildContext context, GalleryState state, String path, bool isResult) async {
    final String? newPath = await FilePermissionService().reAuthorize(
      path,
      title: isResult ? "Authorize Output Directory" : "Authorize Folder: $path",
    );

    if (newPath != null) {
      if (isResult) {
        await state.updateOutputDirectory(newPath);
      } else {
        state.setViewFolder(newPath);
        state.refreshImages();
      }
    }
  }

  Widget _buildImageGrid(
    BuildContext context,
    GalleryState state,
    _GridInputs grid,
    EdgeInsets insets,
  ) {
    final images = grid.images;
    final isResult = grid.isResult;
    final isTemp = grid.isTemp;

    if (images.isEmpty) {
      final Widget empty;
      if (grid.isUnreachable) {
        // macOS permission trouble, as of the last scan.
        empty = PermissionPlaceholder(
          onReAuthorize: () => _reAuthorize(context, state, grid.permissionPath!, isResult),
        );
      } else if (grid.isScanning) {
        empty = const _ScanningState();
      } else if (isTemp) {
        empty = _WorkspaceEmptyState(gallery: state);
      } else {
        empty = _NothingHereState(isResult: isResult);
      }
      return Padding(
        padding: insets,
        // scaleDown so a short host shrinks the placeholder instead of
        // overflowing it.
        child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: empty)),
      );
    }

    // Grouping is memoized in GalleryState — only recomputed when the list identity changes.
    final grouped = state.getGrouped(images);
    final globalIndexByPath = state.getGlobalIndex(images);
    final sortedPaths = isResult ? grouped.keys.toList() : state.getSortedPaths(images);

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0) return const SizedBox.shrink();

        final bool showHeaders = !isTemp && (grouped.length > 1 || grid.mode == GalleryViewMode.all);

        return ExcludeSemantics(
          child: CustomScrollView(
            primary: false,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: insets.top)),
              for (final path in sortedPaths) ...[
                if (showHeaders)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s10, AppSpace.s16, 0),
                      child: Row(
                        children: [
                          Icon(Icons.folder_outlined, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
                          const SizedBox(width: AppSpace.s6),
                          Expanded(
                            child: Text(
                              path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall!.mono.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.s6),
                          Text(
                            '${grouped[path]!.length}',
                            style: textTheme.labelSmall!.mono.copyWith(
                              color: scheme.outline,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.all(_gap),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: grid.thumbnailSize,
                      mainAxisSpacing: _gap,
                      crossAxisSpacing: _gap,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final imageGroup = grouped[path]!;
                        final imageFile = imageGroup[index];
                        final globalIndex = globalIndexByPath[imageFile.path] ?? 0;

                        // `00d` 确认: a card an OS drop just added rings once.
                        // Always wrapped, so the ring sees its trigger change
                        // rather than being mounted with it.
                        return AppDropConfirmRing(
                          trigger: _confirmedPaths.contains(imageFile.path) ? _confirmToken : null,
                          child: SizedBox.expand(
                            // The ordinal, not a bool: a card also has to
                            // repaint when its *place* in the selection shifts.
                            child: Selector<GalleryState, int>(
                          selector: (_, state) => state.selectionNumberOf(imageFile.path),
                          builder: (context, selectionNumber, _) {
                            final isVideo = AppConstants.isVideoFile(imageFile.path);
                            return ImageCard(
                              imageFile: imageFile,
                              selectionNumber: selectionNumber,
                              thumbnailSize: grid.thumbnailSize,
                              heroScope: kWorkbenchPreviewHeroScope,
                              onTap: () {
                                if (isVideo) {
                                  showMediaPreview(context, galleryImages: images, initialIndex: globalIndex, heroScope: kWorkbenchPreviewHeroScope);
                                } else {
                                  state.toggleImageSelection(imageFile);
                                }
                              },
                              onDoubleTap: isVideo
                                  ? null
                                  : () {
                                      showMediaPreview(context, galleryImages: images, initialIndex: globalIndex, heroScope: kWorkbenchPreviewHeroScope);
                                    },
                            );
                          },
                            ),
                          ),
                        );
                      },
                      childCount: grouped[path]!.length,
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: insets.bottom + _gap)),
            ],
          ),
        );
      },
    );
  }
}

/// `A1 · 1f` 扫描中.
class _ScanningState extends StatelessWidget {
  const _ScanningState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: AppSpace.s10),
        Text(
          AppLocalizations.of(context)!.galleryScanning,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// `A1 · 1f` 工作区空: a dashed drop target that also offers the gallery
/// import, so the empty workspace is itself the way to fill it.
class _WorkspaceEmptyState extends StatelessWidget {
  const _WorkspaceEmptyState({required this.gallery});

  final GalleryState gallery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return CustomPaint(
      foregroundPainter: _DashedRectPainter(
        color: scheme.outlineVariant,
        strokeWidth: 1,
        radius: AppRadius.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: AppSpace.s22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download, size: 28, color: scheme.outline),
            const SizedBox(height: AppSpace.s6),
            Text(
              l10n.galleryEmptyWorkspaceTitle,
              style: textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.galleryEmptyWorkspaceDesc,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpace.s4),
            TextButton(
              onPressed: () => pickImagesIntoWorkspace(gallery),
              child: Text(l10n.importFromGallery),
            ),
          ],
        ),
      ),
    );
  }
}

/// `A1 · 1f` 来源 / 结果空.
class _NothingHereState extends StatelessWidget {
  const _NothingHereState({required this.isResult});

  final bool isResult;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_search, size: 28, color: scheme.outline),
          const SizedBox(height: AppSpace.s6),
          Text(
            isResult ? l10n.noResultsYet : l10n.noImagesFound,
            style: textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600),
          ),
          if (!isResult) ...[
            const SizedBox(height: 2),
            Text(
              l10n.galleryEmptySourceDesc,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// A dashed rounded-rectangle edge.
class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, required this.strokeWidth, required this.radius});

  final Color color;
  final double strokeWidth;
  final double radius;

  static const double _dash = 6;
  static const double _space = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final inset = strokeWidth / 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth),
        Radius.circular(radius),
      ));
    for (final ui.PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _space;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.radius != radius;
}
