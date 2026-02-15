import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import 'directory_tree_item.dart';

class SourceExplorerWidget extends StatelessWidget {
  final bool useBrowserState;

  const SourceExplorerWidget({
    super.key,
    this.useBrowserState = false,
  });

  Future<void> _pickDirectory(BuildContext context, AppState appState) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.selectSourceDirectory,
      );

      if (selectedDirectory != null) {
        if (useBrowserState) {
          appState.browserState.addBaseDirectory(selectedDirectory);
        } else {
          appState.addBaseDirectory(selectedDirectory);
        }
      }
    } catch (e) {
      appState.addLog('Error picking directory: $e', level: 'ERROR');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final galleryState = appState.galleryState;

    final sourceDirectories = useBrowserState 
        ? appState.browserState.sourceDirectories 
        : appState.sourceDirectories;

    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton.icon(
              onPressed: () => _pickDirectory(context, appState),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(l10n.addFolder),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const Divider(height: 1),
          
          // Fixed Nodes
          if (!useBrowserState) ...[
            _buildFixedNode(
              context,
              icon: Icons.workspaces_outline,
              label: l10n.tempWorkspace,
              isSelected: galleryState.viewMode == GalleryViewMode.temp,
              onTap: () => galleryState.setViewMode(GalleryViewMode.temp),
              colorScheme: colorScheme,
            ),
            _buildFixedNode(
              context,
              icon: Icons.auto_awesome_motion,
              label: l10n.processResults,
              isSelected: galleryState.viewMode == GalleryViewMode.processed,
              onTap: () => galleryState.setViewMode(GalleryViewMode.processed),
              colorScheme: colorScheme,
            ),
            const Divider(height: 1),
          ],

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  l10n.directories,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '${sourceDirectories.length}',
                  style: TextStyle(fontSize: 11, color: colorScheme.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: sourceDirectories.isEmpty
                ? _buildEmptyState(colorScheme, l10n)
                : ListView.builder(
                    itemCount: sourceDirectories.length,
                    itemBuilder: (context, index) {
                      final path = sourceDirectories[index];
                      return DirectoryTreeItem(
                        key: ValueKey(path),
                        path: path,
                        isRoot: true,
                        useBrowserState: useBrowserState,
                        onRemove: (p, name) => _confirmRemove(context, appState, p, name),
                      );
                    },
                  ),
          ),
        ],
    );
  }

  Widget _buildFixedNode(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return ListTile(
      leading: Icon(icon, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant, size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      selected: isSelected,
      dense: true,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      visualDensity: VisualDensity.compact,
    );
  }

  void _confirmRemove(BuildContext context, AppState appState, String path, String folderName) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeFolderConfirmTitle),
        content: Text(l10n.removeFolderConfirmMessage(folderName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              if (useBrowserState) {
                appState.browserState.removeBaseDirectory(path);
              } else {
                appState.removeBaseDirectory(path);
              }
              Navigator.pop(context);
            },
            child: Text(l10n.remove, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_outlined, size: 48, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              l10n.noFolders,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.clickAddFolder,
              style: TextStyle(color: colorScheme.outline, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
