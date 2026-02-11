import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive.dart';
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
    final isMobile = Responsive.isMobile(context);
    
    final selectedCount = appState.selectedImages.length;
    final thumbnailSize = appState.thumbnailSize;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    isMobile ? '$selectedCount' : l10n.selectedCount(selectedCount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => appState.galleryState.selectAllImages(),
                    icon: const Icon(Icons.select_all, size: 20),
                    tooltip: l10n.selectAll,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: selectedCount == 0 ? null : () => appState.galleryState.clearImageSelection(),
                    icon: const Icon(Icons.deselect, size: 20),
                    tooltip: l10n.clear,
                    visualDensity: VisualDensity.compact,
                  ),
                  
                  if (!isMobile) ...[
                    const VerticalDivider(width: 24, indent: 8, endIndent: 8),
                    if (appState.droppedImages.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => appState.galleryState.clearDroppedImages(),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: Text(l10n.clearTempWorkspace),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    
                    const VerticalDivider(width: 24, indent: 8, endIndent: 8),
                    // Thumbnail Size Slider
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined, size: 16, color: colorScheme.outline),
                        SizedBox(
                          width: 100,
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
                  ],
                ],
              ),
            ),
          ),
          
          if (isMobile) 
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) async {
                if (val == 'refresh') appState.galleryState.refreshImages();
                if (val == 'clear_temp') appState.galleryState.clearDroppedImages();
                if (val == 'import') {
                  final picker = ImagePicker();
                  final List<XFile> picked = await picker.pickMultiImage();
                  if (picked.isNotEmpty) {
                    final List<AppFile> newFiles = picked.map((f) => AppFile(path: f.path, name: f.name)).toList();
                    appState.galleryState.addDroppedFiles(newFiles);
                    tabController.animateTo(2);
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: const Icon(Icons.refresh),
                    title: Text(l10n.refresh),
                    dense: true,
                  ),
                ),
                if (appState.droppedImages.isNotEmpty)
                  PopupMenuItem(
                    value: 'clear_temp',
                    child: ListTile(
                      leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                      title: Text(l10n.clearTempWorkspace, style: const TextStyle(color: Colors.red)),
                      dense: true,
                    ),
                  ),
                PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: Text(l10n.importFromGallery),
                    dense: true,
                  ),
                ),
              ],
            )
          else ...[
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
        ],
      ),
    );
  }
}