import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../state/app_state.dart';

class SourceExplorerWidget extends StatelessWidget {
  const SourceExplorerWidget({super.key});

  Future<void> _pickDirectory(BuildContext context, AppState appState) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Source Directory',
      );

      if (selectedDirectory != null) {
        appState.addBaseDirectory(selectedDirectory);
      }
    } catch (e) {
      appState.addLog('Error picking directory: $e', level: 'ERROR');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 250,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton.icon(
              onPressed: () => _pickDirectory(context, appState),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add Folder'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'DIRECTORIES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '${appState.baseDirectories.length}',
                  style: TextStyle(fontSize: 11, color: colorScheme.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: appState.baseDirectories.isEmpty
                ? _buildEmptyState(colorScheme)
                : ListView.builder(
                    itemCount: appState.baseDirectories.length,
                    itemBuilder: (context, index) {
                      final path = appState.baseDirectories[index];
                      final isSelected = appState.selectedDirectories.contains(path);
                      final folderName = path.split(Platform.pathSeparator).last;

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 8, right: 4),
                        leading: Checkbox(
                          value: isSelected,
                          onChanged: (_) => appState.toggleDirectory(path),
                          visualDensity: VisualDensity.compact,
                        ),
                        title: Text(
                          folderName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          path,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => _confirmRemove(context, appState, path, folderName),
                          tooltip: 'Remove folder',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, AppState appState, String path, String folderName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Folder?'),
        content: Text('Are you sure you want to remove "$folderName" from the list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              appState.removeBaseDirectory(path);
              Navigator.pop(context);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_outlined, size: 48, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'No folders added',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Click "Add Folder" to start scanning for images.',
              style: TextStyle(color: colorScheme.outline, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
