import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_file.dart';
import '../../services/image_metadata_service.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/window_state.dart';
import '../../widgets/dialogs/file_rename_dialog.dart';

import 'widgets/image_preview_dialog.dart';

class GalleryWidget extends StatefulWidget {
  const GalleryWidget({
    super.key,
  });

  @override
  State<GalleryWidget> createState() => _GalleryWidgetState();
}

class _GalleryWidgetState extends State<GalleryWidget> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final galleryState = appState.galleryState;

    return DropTarget(
      onDragDone: (details) {
        final List<AppFile> newFiles = [];
        for (var file in details.files) {
          if (AppConstants.isImageFile(file.path)) {
            newFiles.add(AppFile(path: file.path, name: file.name));
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
        return FutureBuilder<List<AppFile>>(
          future: _loadImagesFromFolder(galleryState.viewSourcePath),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildImageGrid(context, snapshot.data ?? [], appState);
          },
        );
    }
  }

  Future<List<AppFile>> _loadImagesFromFolder(String? path) async {
    if (path == null) return [];
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        final List<AppFile> files = [];
        await for (final entity in dir.list()) {
          if (entity is File && AppConstants.isImageFile(entity.path)) {
            files.add(AppFile.fromFile(entity));
          }
        }
        return files;
      }
    } catch (_) {}
    return [];
  }

  Widget _buildImageGrid(BuildContext context, List<AppFile> images, AppState state, {bool isResult = false, bool isTemp = false}) {
    final l10n = AppLocalizations.of(context)!;
    if (images.isEmpty) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0) return const SizedBox.shrink();
        
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: state.thumbnailSize,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final imageFile = images[index];
            final isSelected = state.selectedImages.any((img) => img.path == imageFile.path);
            
            return _ImageCard(
              imageFile: imageFile,
              isSelected: isSelected,
              isResult: isResult,
              thumbnailSize: state.thumbnailSize,
              onTap: () {
                // Results open preview dialog on tap, others toggle selection
                if (isResult) {
                   showImagePreview(context, imageFile.path);
                } else {
                  state.galleryState.toggleImageSelection(imageFile);
                }
              },
            );
          },
        );
      }
    );
  }
}

class _ImageCard extends StatefulWidget {
  final AppFile imageFile;
  final bool isSelected;
  final bool isResult;
  final double thumbnailSize;
  final VoidCallback onTap;

  const _ImageCard({
    required this.imageFile,
    required this.isSelected,
    required this.isResult,
    required this.thumbnailSize,
    required this.onTap,
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildOverlayButton(
                          icon: Icons.auto_fix_high,
                          onPressed: () => _handleOptimize(context),
                          tooltip: 'Optimize',
                        ),
                        const SizedBox(width: 4),
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
                      ],
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

  void _handleOptimize(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    // Ensure image is selected or at least used for optimization
    if (!appState.selectedImages.any((img) => img.path == widget.imageFile.path)) {
      appState.galleryState.toggleImageSelection(widget.imageFile);
    }
    appState.setWorkbenchTab(3); // Prompt Optimizer
  }

  void _handleCompare(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final windowState = Provider.of<WindowState>(context, listen: false);
    windowState.sendToComparator(widget.imageFile.path);
    appState.setWorkbenchTab(1); // Comparator
  }

  void _handleMask(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final windowState = Provider.of<WindowState>(context, listen: false);
    windowState.setMaskEditorSourceImage(widget.imageFile);
    appState.setWorkbenchTab(2); // Mask Editor
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    final windowState = Provider.of<WindowState>(context, listen: false);
    final appState = Provider.of<AppState>(context, listen: false);

    final bool isPartOfSelection = appState.selectedImages.any((img) => img.path == widget.imageFile.path);
    final List<AppFile> filesToShare = isPartOfSelection ? appState.selectedImages : [widget.imageFile];

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.open_in_new, size: 18),
            title: Text(l10n.openInPreview),
            dense: true,
          ),
          onTap: () {
            showImagePreview(context, widget.imageFile.path);
          },
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
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Share failed: $e')),
                );
              }
            }
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.brush_outlined, size: 18),
            title: Text(l10n.drawMask),
            dense: true,
          ),
          onTap: () {
            windowState.setMaskEditorSourceImage(widget.imageFile);
            appState.setWorkbenchTab(2); // Mask Editor
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: Icon(widget.isSelected ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 18),
            title: Text(l10n.sendToSelection),
            dense: true,
          ),
          onTap: () {
            appState.galleryState.toggleImageSelection(widget.imageFile);
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.compare, size: 18),
            title: Text(l10n.sendToComparator),
            dense: true,
          ),
          onTap: () {
            windowState.sendToComparator(widget.imageFile.path);
            appState.setWorkbenchTab(1); // Comparator
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.compare, size: 18, color: Colors.blue),
            title: Text(l10n.sendToComparatorRaw),
            dense: true,
          ),
          onTap: () {
            windowState.sendToComparator(widget.imageFile.path, isAfter: false);
            appState.setWorkbenchTab(1); // Comparator
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.compare, size: 18, color: Colors.orange),
            title: Text(l10n.sendToComparatorAfter),
            dense: true,
          ),
          onTap: () {
            windowState.sendToComparator(widget.imageFile.path, isAfter: true);
            appState.setWorkbenchTab(1); // Comparator
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
