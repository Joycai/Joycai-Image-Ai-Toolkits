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
    final galleryState = context.watch<GalleryState>();

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
          _buildActiveView(context, galleryState),
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

  Widget _buildActiveView(BuildContext context, GalleryState galleryState) {
    switch (galleryState.viewMode) {
      case GalleryViewMode.all:
        return _buildImageGrid(context, galleryState.galleryImages, galleryState);
      case GalleryViewMode.processed:
        return _buildImageGrid(context, galleryState.processedImages, galleryState, isResult: true);
      case GalleryViewMode.temp:
        return _buildImageGrid(context, galleryState.droppedImages, galleryState, isTemp: true);
      case GalleryViewMode.folder:
        return _buildImageGrid(context, galleryState.folderImages, galleryState, isResult: galleryState.folderViewIsResult);
    }
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

  Widget _buildImageGrid(BuildContext context, List<AppImage> images, GalleryState state, {bool isResult = false, bool isTemp = false}) {
    final l10n = AppLocalizations.of(context)!;

    // Check for macOS permission issues
    final currentPath = isResult ? state.outputDirectory : (state.viewMode == GalleryViewMode.folder ? state.viewSourcePath : null);
    final bool isUnreachable = !isTemp && currentPath != null && state.isPathUnreachable(currentPath);

    if (images.isEmpty) {
      if (isUnreachable) {
        return PermissionPlaceholder(
          onReAuthorize: () => _reAuthorize(context, state, currentPath, isResult),
        );
      }

      if (state.isScanning) {
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

        final bool showHeaders = !isTemp && (grouped.length > 1 || state.viewMode == GalleryViewMode.all);

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
                      maxCrossAxisExtent: state.thumbnailSize,
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
                              thumbnailSize: state.thumbnailSize,
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
