import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';

class SourceExplorerWidget extends StatelessWidget {
  const SourceExplorerWidget({super.key});

  Future<void> _pickDirectory(BuildContext context, AppState appState) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.selectSourceDirectory,
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
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: 250,
      color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
      child: Column(
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  l10n.directories,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
color: colorScheme.onSurface,                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '${appState.sourceDirectories.length}',
                  style: TextStyle(fontSize: 11, color: colorScheme.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: appState.sourceDirectories.isEmpty
                ? _buildEmptyState(colorScheme, l10n)
                : ListView.builder(
                    itemCount: appState.sourceDirectories.length,
                    itemBuilder: (context, index) {
                      final path = appState.sourceDirectories[index];
                      final isSelected = appState.activeSourceDirectories.contains(path);
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
                          tooltip: l10n.removeFolderTooltip,
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
              appState.removeBaseDirectory(path);
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
