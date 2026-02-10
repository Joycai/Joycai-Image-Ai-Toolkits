import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/app_file.dart';
import '../../../state/app_state.dart';

class GalleryToolbar extends StatelessWidget {
  final TabController tabController;

  const GalleryToolbar({
    super.key,
    required this.tabController,
  });

  @override
  Widget build(BuildContext context) {
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
            const VerticalDivider(width: 24, indent: 8, endIndent: 8),
            TextButton.icon(
              onPressed: () async {
                final picker = ImagePicker();
                final List<XFile> picked = await picker.pickMultiImage();
                if (picked.isNotEmpty) {
                  final List<AppFile> newFiles = picked.map((f) => AppFile(path: f.path, name: f.name)).toList();
                  appState.galleryState.addDroppedFiles(newFiles);
                  tabController.animateTo(2);
                }
              },
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(l10n.importFromGallery),
            ),
          ],
        ),
      ),
    );
  }
}
