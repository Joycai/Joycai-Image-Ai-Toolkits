import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../services/file_permission_service.dart';
import '../../state/app_state.dart';
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
    final appState = Provider.of<AppState>(context);
    final galleryState = appState.galleryState;

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
          _buildActiveView(context, galleryState, appState),
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
                      style: TextStyle(
                        fontSize: 20,
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

  Widget _buildActiveView(BuildContext context, GalleryState galleryState, AppState appState) {
    switch (galleryState.viewMode) {
      case GalleryViewMode.all:
        return _buildImageGrid(context, galleryState.galleryImages, appState);  
      case GalleryViewMode.processed:
        return _buildImageGrid(context, galleryState.processedImages, appState, isResult: true);
      case GalleryViewMode.temp:
        return _buildImageGrid(context, galleryState.droppedImages, appState, isTemp: true);
      case GalleryViewMode.folder:
        return _buildImageGrid(context, galleryState.folderImages, appState, isResult: galleryState.folderViewIsResult);
    }
  }

  Future<void> _reAuthorize(BuildContext context, AppState state, String path, bool isResult) async {
    final String? newPath = await FilePermissionService().reAuthorize(
      path,
      title: isResult ? "Authorize Output Directory" : "Authorize Folder: $path",
    );

    if (newPath != null) {
      if (isResult) {
        await state.updateOutputDirectory(newPath);
      } else {
        state.galleryState.setViewFolder(newPath);
        state.galleryState.refreshImages();
      }
    }
  }

  Widget _buildImageGrid(BuildContext context, List<AppImage> images, AppState state, {bool isResult = false, bool isTemp = false}) {
    final l10n = AppLocalizations.of(context)!;

    // Check for macOS permission issues
    final currentPath = isResult ? state.outputDirectory : (state.galleryState.viewMode == GalleryViewMode.folder ? state.galleryState.viewSourcePath : null);  
    final bool isUnreachable = !isTemp && currentPath != null && state.galleryState.isPathUnreachable(currentPath);

    if (images.isEmpty) {
      if (isUnreachable) {
        return PermissionPlaceholder(
          onReAuthorize: () => _reAuthorize(context, state, currentPath, isResult),
        );
      }

      if (state.galleryState.isScanning) {
        return const Center(child: CircularProgressIndicator());
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isTemp ? Icons.move_to_inbox_outlined : Icons.image_not_supported_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              isTemp ? l10n.dropFilesHere : (isResult ? l10n.noResultsYet : l10n.noImagesFound),
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Grouping is memoized in GalleryState — only recomputed when the list identity changes.
    final grouped = state.galleryState.getGrouped(images);
    final globalIndexByPath = state.galleryState.getGlobalIndex(images);
    // processedImages is pre-sorted by modification date; use memoized paths for other views.
    final sortedPaths = isResult
        ? grouped.keys.toList()
        : state.galleryState.getSortedPaths(images);

    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0) return const SizedBox.shrink();

        final bool showHeaders = !isTemp && (grouped.length > 1 || state.galleryState.viewMode == GalleryViewMode.all);

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
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.secondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            "(${grouped[path]!.length})",
                            style: TextStyle(fontSize: 11, color: colorScheme.outline),
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

                        return Selector<AppState, bool>(
                          selector: (_, state) => state.isImageSelected(imageFile.path),
                          builder: (context, isSelected, _) {
                            final isVideo = AppConstants.isVideoFile(imageFile.path);
                            return ImageCard(
                              imageFile: imageFile,
                              isSelected: isSelected,
                              isResult: isResult,
                              thumbnailSize: state.thumbnailSize,
                              onTap: () {
                                if (isVideo) {
                                  showMediaPreview(context, galleryImages: images, initialIndex: globalIndex);
                                } else {
                                  state.galleryState.toggleImageSelection(imageFile);
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
