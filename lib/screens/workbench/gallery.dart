import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_file.dart';
import '../../state/app_state.dart';
import '../../state/window_state.dart';

class GalleryWidget extends StatefulWidget {
  const GalleryWidget({super.key});

  @override
  State<GalleryWidget> createState() => _GalleryWidgetState();
}

class _GalleryWidgetState extends State<GalleryWidget> with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    
    return DropTarget(
      onDragDone: (details) {
        final List<AppFile> newFiles = [];
        for (var file in details.files) {
          if (AppConstants.isImageFile(file.path)) {
            newFiles.add(AppFile(path: file.path, name: file.name));
          }
        }
        if (newFiles.isNotEmpty) {
          appState.galleryState.addDroppedFiles(newFiles);
          // Switch to the 3rd tab (Temporary Workspace) automatically
          _tabController.animateTo(2);
        }
      },
      onDragEntered: (details) => setState(() => _isDragging = true),
      onDragExited: (details) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          Column(
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.sourceGallery),
                        if (appState.galleryImages.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _buildBadge(context, appState.galleryImages.length),
                          ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.processResults),
                        if (appState.processedImages.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _buildBadge(context, appState.processedImages.length, isResult: true),
                          ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_motion_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text(l10n.tempWorkspace),
                        if (appState.droppedImages.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _buildBadge(context, appState.droppedImages.length, isTemp: true),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              _buildToolbar(context),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildImageGrid(context, appState.galleryImages, appState, isResult: false),
                    _buildImageGrid(context, appState.processedImages, appState, isResult: true),
                    _buildImageGrid(context, appState.droppedImages, appState, isTemp: true),
                  ],
                ),
              ),
            ],
          ),
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

  Widget _buildBadge(BuildContext context, int count, {bool isResult = false, bool isTemp = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    Color bgColor = colorScheme.primaryContainer;
    Color textColor = colorScheme.onPrimaryContainer;

    if (isResult) {
      bgColor = colorScheme.secondaryContainer;
      textColor = colorScheme.onSecondaryContainer;
    } else if (isTemp) {
      bgColor = Colors.teal.withAlpha(40);
      textColor = Colors.teal;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(fontSize: 10, color: textColor, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context);
    
    final selectedCount = appState.selectedImages.length;
    final thumbnailSize = appState.thumbnailSize;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              l10n.selectedCount(selectedCount),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: () => appState.galleryState.selectAllImages(),
              icon: const Icon(Icons.select_all, size: 18),
              label: Text(l10n.selectAll),
            ),
            TextButton.icon(
              onPressed: selectedCount == 0 ? null : () => appState.galleryState.clearImageSelection(),
              icon: const Icon(Icons.deselect, size: 18),
              label: Text(l10n.clear),
            ),
            const SizedBox(width: 16),
            
            if (appState.droppedImages.isNotEmpty)
              TextButton.icon(
                onPressed: () => appState.galleryState.clearDroppedImages(),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(l10n.clearTempWorkspace),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),

            const VerticalDivider(width: 24, indent: 8, endIndent: 8),
            
            // Thumbnail Size Slider
            Tooltip(
              message: l10n.thumbnailSize,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_outlined, size: 16, color: colorScheme.outline),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: thumbnailSize,
                      min: 80,
                      max: 400,
                      onChanged: (v) => appState.galleryState.setThumbnailSize(v),
                    ),
                  ),
                  Icon(Icons.image, size: 20, color: colorScheme.outline),
                ],
              ),
            ),
            
            const VerticalDivider(width: 24, indent: 8, endIndent: 8),
            
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => appState.galleryState.refreshImages(),
              tooltip: l10n.refresh,
            ),
          ],
        ),
      ),
    );
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
          onTap: () {
            // Results open preview on tap, others toggle selection
            if (isResult) {
              _showPreviewDialog(context, images, index);
            } else {
              state.galleryState.toggleImageSelection(imageFile);
            }
          },
        );
      },
    );
  }

  void _showPreviewDialog(BuildContext context, List<AppFile> images, int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => _ImagePreviewDialog(
        images: images,
        initialIndex: initialIndex,
      ),
    );
  }
}

class _ImagePreviewDialog extends StatefulWidget {
  final List<AppFile> images;
  final int initialIndex;

  const _ImagePreviewDialog({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  late int _currentIndex;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = widget.images[_currentIndex];

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(100),
                minScale: 0.5,
                maxScale: 4.0,
                child: Image(
                  image: widget.images[index].imageProvider,
                  fit: BoxFit.contain,
                ),
              );
            },
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (_currentIndex > 0)
            Positioned(
              top: 0,
              bottom: 0,
              left: 16,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 40),
                  onPressed: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
          if (_currentIndex < widget.images.length - 1)
            Positioned(
              top: 0,
              bottom: 0,
              right: 16,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 40),
                  onPressed: () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                ),
              ),
            ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${imageFile.name} (${_currentIndex + 1} / ${widget.images.length})',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageCard extends StatefulWidget {
  final AppFile imageFile;
  final bool isSelected;
  final bool isResult;
  final VoidCallback onTap;

  const _ImageCard({
    required this.imageFile,
    required this.isSelected,
    required this.isResult,
    required this.onTap,
  });

  @override
  State<_ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<_ImageCard> {
  String _dimensions = "";

  @override
  void initState() {
    super.initState();
    _getImageDimensions();
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      var t = b;
      b = a % b;
      a = t;
    }
    return a;
  }

  Future<void> _getImageDimensions() async {
    try {
      final bytes = await File(widget.imageFile.path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (mounted) {
        setState(() {
          final commonDivisor = _gcd(image.width, image.height);
          final ratioW = image.width ~/ commonDivisor;
          final ratioH = image.height ~/ commonDivisor;
          _dimensions = "${image.width}x${image.height} ($ratioW:$ratioH)";
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
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
                  image: widget.imageFile.imageProvider,
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
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    final windowState = Provider.of<WindowState>(context, listen: false);

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
            windowState.openFloatingPreview(widget.imageFile.path);
          },
        ),
        if (!windowState.isComparatorOpen)
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.compare, size: 18),
              title: Text(l10n.sendToComparator),
              dense: true,
            ),
            onTap: () {
              windowState.sendToComparator(widget.imageFile.path);
            },
          )
        else ...[
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.compare, size: 18, color: Colors.blue),
              title: Text(l10n.sendToComparatorRaw),
              dense: true,
            ),
            onTap: () {
              windowState.sendToComparator(widget.imageFile.path, isAfter: false);
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
            },
          ),
        ],
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
            WidgetsBinding.instance.addPostFrameCallback((_) => _showRenameDialog(context));
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

  void _showRenameDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context, listen: false);
    final file = File(widget.imageFile.path);
    final dir = p.dirname(file.path);
    final extension = p.extension(file.path);
    final nameStem = p.basenameWithoutExtension(file.path);

    final controller = TextEditingController(text: nameStem);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameFile),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: l10n.newFilename,
                suffixText: extension,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (_) => _performRename(context, controller, dir, extension, appState, l10n),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => _performRename(context, controller, dir, extension, appState, l10n),
            child: Text(l10n.rename),
          ),
        ],
      ),
    );
  }

  Future<void> _performRename(
    BuildContext context, 
    TextEditingController controller, 
    String dir, 
    String extension, 
    AppState appState, 
    AppLocalizations l10n
  ) async {
    final newName = controller.text.trim();
    if (newName.isEmpty || newName == p.basenameWithoutExtension(widget.imageFile.path)) {
      Navigator.pop(context);
      return;
    }
    
    final newFilename = '$newName$extension';
    final newPath = p.join(dir, newFilename);
    
    if (File(newPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fileAlreadyExists), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      await File(widget.imageFile.path).rename(newPath);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.renameSuccess), backgroundColor: Colors.green),
        );
        appState.galleryState.refreshImages();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.renameFailed(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
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