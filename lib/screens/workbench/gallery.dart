import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';

class GalleryWidget extends StatelessWidget {
  const GalleryWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.sourceGallery),
                    if (appState.galleryImages.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _buildBadge(context, appState.galleryImages.length),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.processResults),
                    if (appState.processedImages.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _buildBadge(context, appState.processedImages.length, isResult: true),
                    ],
                  ],
                ),
              ),
            ],
          ),
          _buildToolbar(context, appState),
          Expanded(
            child: TabBarView(
              children: [
                _buildImageGrid(context, appState.galleryImages, appState, isResult: false),
                _buildImageGrid(context, appState.processedImages, appState, isResult: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context, int count, {bool isResult = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isResult ? colorScheme.secondaryContainer : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          color: isResult ? colorScheme.onSecondaryContainer : colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, AppState appState) {
    final l10n = AppLocalizations.of(context)!;
    if (appState.galleryImages.isEmpty && appState.processedImages.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            l10n.selectedCount(appState.selectedImages.length),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: appState.selectAllImages,
            icon: const Icon(Icons.select_all, size: 18),
            label: Text(l10n.selectAll),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: appState.selectedImages.isEmpty ? null : appState.clearImageSelection,
            icon: const Icon(Icons.deselect, size: 18),
            label: Text(l10n.clear),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context, List<File> images, AppState appState, {required bool isResult}) {
    final l10n = AppLocalizations.of(context)!;
    if (images.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              isResult ? l10n.noResultsYet : l10n.noImagesFound,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        final imageFile = images[index];
        final isSelected = appState.selectedImages.any((img) => img.path == imageFile.path);
        
        return _ImageCard(
          imageFile: imageFile,
          isSelected: isSelected,
          isResult: isResult,
          onTap: () {
            if (isResult) {
              _showPreviewDialog(context, imageFile);
            } else {
              appState.toggleImageSelection(imageFile);
            }
          },
        );
      },
    );
  }

  void _showPreviewDialog(BuildContext context, File imageFile) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(100),
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(
                  imageFile,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
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
                    imageFile.path.split(Platform.pathSeparator).last,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCard extends StatefulWidget {
  final File imageFile;
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
      final bytes = await widget.imageFile.readAsBytes();
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
      // Ignore errors for non-image files or corrupted images
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
            color: colorScheme.surfaceVariant.withOpacity(0.5),
            border: Border.all(
              color: widget.isSelected ? colorScheme.primary : colorScheme.outlineVariant.withOpacity(0.2),
              width: widget.isSelected ? 3 : 1,
            ),
            boxShadow: widget.isSelected ? [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.2),
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
                child: Image.file(
                  widget.imageFile,
                  fit: BoxFit.contain,
                  cacheWidth: 400,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
              
              // Metadata Overlay (Top)
              if (_dimensions.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                    color: Colors.black.withOpacity(0.4),
                    child: Text(
                      _dimensions,
                      style: const TextStyle(color: Colors.white, fontSize: 9),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              if (widget.isSelected)
                Container(
                  color: colorScheme.primary.withOpacity(0.1),
                ),
              
              // Filename Overlay (Bottom)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                  ),
                  child: Text(
                    widget.imageFile.path.split(Platform.pathSeparator).last,
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
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.copy, size: 18),
            title: Text(l10n.copyFilename),
            dense: true,
          ),
          onTap: () {
            final filename = widget.imageFile.path.split(Platform.pathSeparator).last;
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
            final folderPath = widget.imageFile.parent.path;
            final uri = Uri.directory(folderPath);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          },
        ),
      ],
    );
  }
}
