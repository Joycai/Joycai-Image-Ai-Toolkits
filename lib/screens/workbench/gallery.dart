import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../services/file_permission_service.dart';
import '../../services/image_metadata_service.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/dialogs/file_rename_dialog.dart';
import '../../widgets/placeholders/permission_placeholder.dart';
import 'widgets/image_preview_dialog.dart';

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
          if (AppConstants.isImageFile(file.path)) {
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
        return _buildImageGrid(context, galleryState.folderImages, appState);
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

    // Group images by parent directory
    final Map<String, List<AppImage>> grouped = {};
    for (var img in images) {
      final parent = File(img.path).parent.path;
      grouped.putIfAbsent(parent, () => []).add(img);
    }

    final sortedPaths = grouped.keys.toList();
    // Sort directories so the view is stable
    if (isResult) {
      // For results, maybe keep order or sort by newest? 
      // Actually, processedImages is already sorted by modification date. 
      // If we group, we might break that. Let's only group if it's NOT the result view,
      // OR if we want to show results by directory too.
      // Usually, users want to see the latest results first regardless of directory.
    } else {
      sortedPaths.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0) return const SizedBox.shrink();
        
        // If it's a single group and not 'all' mode, or results, we can just show the grid without headers for a cleaner look.
        // However, the user specifically asked for grouping, so let's provide it whenever there's more than one source.
        final bool showHeaders = !isTemp && (grouped.length > 1 || state.galleryState.viewMode == GalleryViewMode.all);

        return CustomScrollView(
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
                      
                      // Calculate global index for preview paging
                      final globalIndex = images.indexOf(imageFile);
                      
                      return Selector<AppState, bool>(
                        selector: (_, state) => state.selectedImages.any((img) => img.path == imageFile.path),
                        builder: (context, isSelected, _) {
                          return _ImageCard(
                            imageFile: imageFile,
                            isSelected: isSelected,
                            isResult: isResult,
                            thumbnailSize: state.thumbnailSize,
                            onTap: () {
                              state.galleryState.toggleImageSelection(imageFile);
                            },
                            onDoubleTap: () {
                              showImagePreview(context, galleryImages: images, initialIndex: globalIndex);
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
        );
      }
    );
  }

}

class _ImageCard extends StatefulWidget {
  final AppImage imageFile;
  final bool isSelected;
  final bool isResult;
  final double thumbnailSize;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  const _ImageCard({
    required this.imageFile,
    required this.isSelected,
    required this.isResult,
    required this.thumbnailSize,
    required this.onTap,
    this.onDoubleTap,
  });

  @override
  State<_ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<_ImageCard> {
  String _dimensions = "";
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _getImageDimensions();
  }

  Future<void> _getImageDimensions() async {
    final metadata = await ImageMetadataService().getMetadata(widget.imageFile.path);
    if (metadata != null && mounted) {
      setState(() {
        _dimensions = metadata.displayString;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
        onLongPressStart: (details) => _showContextMenu(context, details.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.5).round()),
              border: Border.all(
                color: widget.isSelected ? colorScheme.primary : colorScheme.outlineVariant.withAlpha((255 * 0.4).round()),
                width: widget.isSelected ? 2 : 1,
              ),
              boxShadow: widget.isSelected ? [
                BoxShadow(
                  color: colorScheme.primary.withAlpha((255 * 0.2).round()),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ] : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Image(
                    image: ResizeImage(
                      widget.imageFile.imageProvider,
                      width: (widget.thumbnailSize * MediaQuery.of(context).devicePixelRatio).round(),
                    ),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
                
                if (_dimensions.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                      color: Colors.black.withAlpha((255 * 0.4).round()),
                      child: Text(
                        _dimensions,
                        style: const TextStyle(color: Colors.white, fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                if (widget.isSelected)
                  Container(
                    color: colorScheme.primary.withAlpha((255 * 0.1).round()),
                  ),
                
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha((255 * 0.6).round()),
                    ),
                    child: Text(
                      widget.imageFile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        overflow: TextOverflow.ellipsis,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // Overlay Buttons
                if (_isHovering || isMobile)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildOverlayButton(
                            icon: Icons.compare,
                            onPressed: () => _handleCompare(context),
                            tooltip: 'Compare',
                          ),
                          const SizedBox(width: 4),
                          _buildOverlayButton(
                            icon: Icons.brush,
                            onPressed: () => _handleMask(context),
                            tooltip: 'Mask',
                          ),
                          const SizedBox(width: 4),
                          _buildOverlayButton(
                            icon: Icons.crop,
                            onPressed: () => _handleCrop(context),
                            tooltip: 'Crop',
                          ),
                        ],
                      ),
                    ),
                  ),
                
                if (widget.isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(4),
      ),
      child: IconButton(
        icon: Icon(icon, size: 16, color: Colors.white),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _handleCompare(BuildContext context) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.sendToComparator(widget.imageFile.path);
    // Removed automatic tab switch
  }

  void _handleMask(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.setMaskEditorSourceImage(widget.imageFile);
    appState.setWorkbenchTab(2); // Mask Editor
  }

  void _handleCrop(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.setCropResizeSourceImage(widget.imageFile);
    appState.setWorkbenchTab(3); // Crop Tab
  }

  Future<void> _saveFile(BuildContext context, String sourcePath, String fileName, AppLocalizations l10n) async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // Desktop: Use FilePicker to save to a specific location
        final extension = sourcePath.split('.').last;
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: l10n.save,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: [extension],
        );

        if (outputFile != null) {
          final file = File(sourcePath);
          await file.copy(outputFile);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.settingsExported), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        // Mobile: Use gal to save to system gallery
        await Gal.putImage(sourcePath);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.savedToPhotos), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.saveFailed(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final appState = Provider.of<AppState>(context, listen: false);

    final bool isPartOfSelection = appState.selectedImages.any((img) => img.path == widget.imageFile.path);
    final List<AppImage> filesToShare = isPartOfSelection ? appState.selectedImages : [widget.imageFile];

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: <PopupMenuEntry<dynamic>>[
        // View & Quick Edit
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.open_in_new, size: 18),
            title: Text(l10n.openInPreview),
            dense: true,
          ),
          onTap: () {
            final images = appState.galleryState.currentViewImages;
            final idx = images.indexWhere((img) => img.path == widget.imageFile.path);
            showImagePreview(context, galleryImages: images, initialIndex: idx >= 0 ? idx : 0);
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.brush_outlined, size: 18),
            title: Text(l10n.drawMask),
            dense: true,
          ),
          onTap: () {
            workbenchUIState.setMaskEditorSourceImage(widget.imageFile);
            appState.setWorkbenchTab(2); // Mask Editor
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.crop_outlined, size: 18),
            title: Text(l10n.cropAndResize),
            dense: true,
          ),
          onTap: () {
            workbenchUIState.setCropResizeSourceImage(widget.imageFile);
            appState.setWorkbenchTab(3); // Crop & Resize Tab
          },
        ),

        const PopupMenuDivider(),

        // Selection & Comparison
        PopupMenuItem(
          child: ListTile(
            leading: Icon(isPartOfSelection ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 18),
            title: Text(isPartOfSelection ? l10n.removeFromSelection : l10n.sendToSelection),
            dense: true,
          ),
          onTap: () => appState.galleryState.toggleImageSelection(widget.imageFile),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.compare, size: 18, color: Colors.blue),
            title: Text(l10n.sendToComparatorRaw),
            dense: true,
          ),
          onTap: () {
            workbenchUIState.sendToComparator(widget.imageFile.path, isAfter: false);
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.compare, size: 18, color: Colors.orange),
            title: Text(l10n.sendToComparatorAfter),
            dense: true,
          ),
          onTap: () {
            workbenchUIState.sendToComparator(widget.imageFile.path, isAfter: true);
          },
        ),

        const PopupMenuDivider(),

        // File Management
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.edit_outlined, size: 18),
            title: Text(l10n.rename),
            dense: true,
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showFileRenameDialog(
                context: context,
                filePath: widget.imageFile.path,
                onSuccess: () => appState.galleryState.refreshImages(),
              );
            });
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.copy, size: 18),
            title: Text(l10n.copyFilename),
            dense: true,
          ),
          onTap: () {
            final filename = widget.imageFile.name;
            Clipboard.setData(ClipboardData(text: filename));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.copiedToClipboard(filename)), duration: const Duration(seconds: 1)),
            );
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.folder_open, size: 18),
            title: Text(l10n.openInFolder),
            dense: true,
          ),
          onTap: () async {
            final folderPath = File(widget.imageFile.path).parent.path;
            final uri = Uri.directory(folderPath);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          },
        ),

        const PopupMenuDivider(),

        // Save & Share
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.save_alt, size: 18, color: Colors.blue),
            title: Text(Platform.isIOS ? l10n.saveToPhotos : l10n.saveToGallery),
            dense: true,
          ),
          onTap: () => _saveFile(context, widget.imageFile.path, widget.imageFile.name, l10n),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.share_outlined, size: 18),
            title: Text(filesToShare.length > 1 ? l10n.shareFiles(filesToShare.length) : l10n.share),
            dense: true,
          ),
          onTap: () async {
            try {
              final xFiles = filesToShare.map((f) => XFile(
                f.path, 
                name: f.name,
                mimeType: AppConstants.getMimeType(f.path),
              )).toList();
              
              // ignore: deprecated_member_use
              await Share.shareXFiles(
                xFiles, 
                subject: filesToShare.length == 1 ? filesToShare.first.name : l10n.appTitle,
                sharePositionOrigin: Rect.fromLTWH(position.dx, position.dy, 1, 1),
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.shareFailed(e.toString()))),
                );
              }
            }
          },
        ),

        const PopupMenuDivider(),

        // Danger Zone
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            title: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
            dense: true,
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) => _confirmDelete(context));
          },
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final filename = widget.imageFile.name;
    final isWindows = Platform.isWindows;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteFileConfirmTitle),
        content: Text(l10n.deleteFileConfirmMessage(filename)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isWindows ? l10n.moveToTrash : l10n.permanentlyDelete),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _deleteFile(context);
    }
  }

  Future<void> _deleteFile(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context, listen: false);
    
    try {
      if (Platform.isWindows) {
        final path = widget.imageFile.path.replaceAll("'", "''"); 
        final result = await Process.run(
          'powershell', 
          [
            '-Command',
            "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('$path', 'OnlyErrorDialogs', 'SendToRecycleBin')"
          ],
        );
        
        if (result.exitCode != 0) {
          throw Exception('PowerShell Error: ${result.stderr}');
        }
      } else {
        await File(widget.imageFile.path).delete();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deleteSuccess), backgroundColor: Colors.green),
        );
        appState.galleryState.refreshImages();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deleteFailed(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }
}
