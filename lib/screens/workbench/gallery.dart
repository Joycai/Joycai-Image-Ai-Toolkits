import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../services/file_permission_service.dart';
import '../../state/gallery_state.dart';
import '../../widgets/placeholders/permission_placeholder.dart';
import 'widgets/image_card.dart';
import 'widgets/preview/media_preview_dialog.dart';

/// Everything the grid reads out of [GalleryState], gathered so the selector
/// in `build` can compare it in one go.
///
/// Pointedly missing: the selection. It is the one thing a plain click
/// changes, it is read per cell by the `Selector` inside the sliver delegate,
/// and putting it here would rebuild every visible card for a change that
/// concerns one of them.
///
/// [images] compares by identity, which is what [GalleryState] guarantees —
/// it always assigns a fresh list before notifying rather than mutating one
/// in place.
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

class Gallery extends StatefulWidget {
  const Gallery({
    super.key,
  });

  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Straight to GalleryState. Everything this screen draws lives there, and
    // AppState no longer re-broadcasts it — going through AppState would mean
    // the grid rebuilt for every unrelated change in the app and, now that the
    // forwarding is gone, would not rebuild for gallery changes at all.
    //
    // `select`, not `watch`: a bare watch rebuilt this widget for *every*
    // GalleryState notification, which replaced the sliver delegate — and
    // `SliverChildBuilderDelegate.shouldRebuild` is unconditionally true, so
    // every visible card was rebuilt anyway and the per-cell `Selector` below
    // absorbed nothing. Selection is the change that matters here: it fires on
    // every click and it is exactly what those Selectors exist to scope.
    final galleryState = context.read<GalleryState>();
    final grid = context.select<GalleryState, _GridInputs>(_gridInputs);

    return DropTarget(
      onDragDone: (details) {
        final List<AppImage> newFiles = [];
        for (var file in details.files) {
          if (AppConstants.isSupportedFile(file.path)) {
            newFiles.add(AppImage(path: file.path, name: file.name));
          }
        }
        if (newFiles.isNotEmpty) {
          galleryState.addDroppedFiles(newFiles);
          galleryState.setViewMode(GalleryViewMode.temp);
        }
      },
      onDragEntered: (details) => setState(() => _isDragging = true),
      onDragExited: (details) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          _buildImageGrid(context, galleryState, grid),
          if (_isDragging)
            Container(
              color: Theme.of(context).colorScheme.primary.withAlpha(40),       
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.file_upload_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      l10n.dropFilesHere,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary
                      ),
                    ),
                  ],
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

  Widget _buildImageGrid(BuildContext context, GalleryState state, _GridInputs grid) {
    final l10n = AppLocalizations.of(context)!;
    final images = grid.images;
    final isResult = grid.isResult;
    final isTemp = grid.isTemp;

    if (images.isEmpty) {
      // macOS permission trouble, as of the last scan — see
      // [GalleryState.isPathUnreachable].
      if (grid.isUnreachable) {
        return PermissionPlaceholder(
          onReAuthorize: () => _reAuthorize(context, state, grid.permissionPath!, isResult),
        );
      }

      if (grid.isScanning) {
        return const Center(child: CircularProgressIndicator());
      }

      return Center(
        // scaleDown lets the placeholder shrink as a whole when the host area
        // is shorter than its natural size (e.g. the temp drop strip), which
        // otherwise overflows and spams the debug console every frame.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isTemp ? Icons.move_to_inbox_outlined : Icons.image_not_supported_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                isTemp ? l10n.dropFilesHere : (isResult ? l10n.noResultsYet : l10n.noImagesFound),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // Grouping is memoized in GalleryState — only recomputed when the list identity changes.
    final grouped = state.getGrouped(images);
    final globalIndexByPath = state.getGlobalIndex(images);
    // processedImages is pre-sorted by modification date; use memoized paths for other views.
    final sortedPaths = isResult
        ? grouped.keys.toList()
        : state.getSortedPaths(images);

    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0) return const SizedBox.shrink();

        final bool showHeaders = !isTemp && (grouped.length > 1 || grid.mode == GalleryViewMode.all);

        return ExcludeSemantics(
          child: CustomScrollView(
            primary: false,
            slivers: [
              for (final path in sortedPaths) ...[
                if (showHeaders)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.folder_open, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              path,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.secondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            "(${grouped[path]!.length})",
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: grid.thumbnailSize,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final imageGroup = grouped[path]!;
                        final imageFile = imageGroup[index];

                        // Global index for preview paging (O(1) lookup)
                        final globalIndex = globalIndexByPath[imageFile.path] ?? 0;

                        // The ordinal, not a bool: a card also has to repaint
                        // when its *place* in the selection shifts (something
                        // earlier was removed, or the strip was reordered),
                        // which a boolean cannot report.
                        return Selector<GalleryState, int>(
                          selector: (_, state) => state.selectionNumberOf(imageFile.path),
                          builder: (context, selectionNumber, _) {
                            final isVideo = AppConstants.isVideoFile(imageFile.path);
                            return ImageCard(
                              imageFile: imageFile,
                              selectionNumber: selectionNumber,
                              thumbnailSize: grid.thumbnailSize,
                              onTap: () {
                                if (isVideo) {
                                  showMediaPreview(context, galleryImages: images, initialIndex: globalIndex);
                                } else {
                                  state.toggleImageSelection(imageFile);
                                }
                              },
                              onDoubleTap: isVideo
                                  ? null
                                  : () {
                                      showMediaPreview(context, galleryImages: images, initialIndex: globalIndex);
                                    },
                            );
                          },
                        );
                      },
                      childCount: grouped[path]!.length,
                    ),
                  ),
                ),
              ],
              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        );
      }
    );
  }

}
