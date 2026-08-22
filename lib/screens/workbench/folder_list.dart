import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/gallery_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/panel_resizer.dart';
import 'directory_tree_item.dart';
import 'widgets/result_tree_item.dart';
import '../../core/design_tokens.dart';

class FolderList extends StatelessWidget {
  final bool useFileBrowserState;

  const FolderList({
    super.key,
    this.useFileBrowserState = false,
  });

  Future<void> _pickDirectory(BuildContext context, AppState appState) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      String? selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: l10n.selectSourceDirectory,
      );

      if (selectedDirectory != null) {
        if (useFileBrowserState) {
          appState.fileBrowserState.addBaseDirectory(selectedDirectory);
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
    final appState = Provider.of<AppState>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // Subscribed to the notifier that owns each list. AppState no longer
    // forwards its sub-states, and this list is the one place both trees are
    // drawn, so it has to name the one it is actually showing.
    final galleryState = context.watch<GalleryState>();
    final sourceDirectories = useFileBrowserState
        ? context.watch<FileBrowserState>().sourceDirectories
        : galleryState.sourceDirectories;

    return Column(
        children: [
          if (Platform.isIOS || Platform.isAndroid)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(100),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.photo_library_outlined, color: colorScheme.primary, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      Platform.isIOS ? l10n.iosSandboxActive : l10n.mobileSandboxActive,
                      style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Platform.isIOS ? l10n.iosSandboxDesc : l10n.mobileSandboxDesc,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onPrimaryContainer),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (!useFileBrowserState)
            Padding(
              padding: const EdgeInsets.all(16.0),
              // An outline, not a fill and not a tonal. Adding a folder sets
              // up the work; running the model is the work. Two accent buttons
              // on one screen make the user choose which is the point, so the
              // workbench keeps exactly one — the process button in the right
              // panel.
              //
              // `10c` draws this one tonal, on an accent wash. Not followed:
              // its own annotation asks for the button to be *demoted* so that
              // one solid accent button is left on the screen, and an outline
              // demotes it further while also keeping §1's rule that the accent
              // appears only on selection, the main CTA and badges. Tonal here
              // would put the accent on the action the user is not meant to
              // take, which is the reason `AppButtonVariant.secondary` stopped
              // being a tonal in the first place.
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: l10n.addFolder,
                  icon: Icons.create_new_folder_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _pickDirectory(context, appState),
                ),
              ),
            ),

          // File Browser: a plain directory tree (no aggregate nodes), with a
          // compact header row hosting the add-folder / deselect-all actions.
          // Workbench gallery: grouped Sources / Results / Workspace.
          if (useFileBrowserState) ...[
            Container(
              height: kPanelHeaderHeight,
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
              child: Row(
                children: [
                  Text(
                    l10n.directories,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${sourceDirectories.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  AppIconButton(
                    icon: Icons.remove_done,
                    tooltip: l10n.deselectAllDirectories,
                    size: 34,
                    onPressed: appState.fileBrowserState.activeDirectories.isEmpty
                        ? null
                        : () => appState.fileBrowserState.clearActiveDirectories(),
                  ),
                  const SizedBox(width: 6),
                  AppIconButton(
                    icon: Icons.create_new_folder_outlined,
                    tooltip: l10n.addFolder,
                    size: 34,
                    onPressed: () => _pickDirectory(context, appState),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(90)),
            Expanded(
              child: sourceDirectories.isEmpty
                  ? _buildEmptyState(context, colorScheme, l10n)
                  : ListView.builder(
                      itemCount: sourceDirectories.length,
                      itemBuilder: (context, index) {
                        final path = sourceDirectories[index];
                        return DirectoryTreeItem(
                          key: ValueKey(path),
                          path: path,
                          isRoot: true,
                          useFileBrowserState: useFileBrowserState,
                          onRemove: (p, name) => _confirmRemove(context, appState, p, name),
                        );
                      },
                    ),
            ),
          ] else
            Expanded(
              child: _buildGalleryGroups(context, appState, galleryState, colorScheme, l10n, sourceDirectories),
            ),
        ],
    );
  }

  Widget _buildGalleryGroups(
    BuildContext context,
    AppState appState,
    GalleryState galleryState,
    ColorScheme colorScheme,
    AppLocalizations l10n,
    List<String> sourceDirectories,
  ) {
    final resultRoots = galleryState.resultRootDirectories;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // SOURCES — the aggregate "All Sources" view is the head of the group,
        // with the browsable source-folder tree nested beneath it.
        _buildSectionHeader(context, colorScheme, l10n.sectionSources, count: sourceDirectories.length),
        _buildFixedNode(
          context,
          icon: Icons.photo_library_outlined,
          label: l10n.allSources,
          isSelected: galleryState.viewMode == GalleryViewMode.all,
          onTap: () => galleryState.setViewMode(GalleryViewMode.all),
          colorScheme: colorScheme,
          count: galleryState.galleryImages.length,
        ),
        if (sourceDirectories.isEmpty)
          _buildInlineHint(context, colorScheme, l10n.noFolders)
        else
          ...sourceDirectories.map((path) => DirectoryTreeItem(
                key: ValueKey(path),
                path: path,
                isRoot: true,
                useFileBrowserState: false,
                onRemove: (p, name) => _confirmRemove(context, appState, p, name),
              )),

        const Divider(height: 16),

        // RESULTS — the result cache is also a real folder tree, now browsable.
        _buildSectionHeader(context, colorScheme, l10n.sectionResults, count: resultRoots.length),
        _buildFixedNode(
          context,
          icon: Icons.auto_awesome_motion,
          label: l10n.allResults,
          isSelected: galleryState.viewMode == GalleryViewMode.processed,
          onTap: () => galleryState.setViewMode(GalleryViewMode.processed),
          colorScheme: colorScheme,
          count: galleryState.processedImages.length,
        ),
        if (resultRoots.isEmpty)
          _buildInlineHint(context, colorScheme, l10n.noResultsYet)
        else
          ...resultRoots.map((path) => ResultTreeItem(key: ValueKey(path), path: path, isRoot: true)),

        const Divider(height: 16),

        // WORKSPACE — transient drop zone.
        _buildSectionHeader(context, colorScheme, l10n.sectionWorkspace),
        _buildFixedNode(
          context,
          icon: Icons.workspaces_outline,
          label: l10n.tempWorkspace,
          isSelected: galleryState.viewMode == GalleryViewMode.temp,
          onTap: () => galleryState.setViewMode(GalleryViewMode.temp),
          colorScheme: colorScheme,
          count: galleryState.droppedImages.length,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, ColorScheme colorScheme, String label, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                  letterSpacing: AppType.trackedLabelSpacing,
                ),
          ),
          const Spacer(),
          if (count != null)
            Text('$count',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildInlineHint(BuildContext context, ColorScheme colorScheme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 10),
      child: Text(text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
    );
  }

  Widget _buildFixedNode(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    int? count,
  }) {
    return ListTile(
      leading: Icon(icon, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant, size: 20),
      title: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
        ),
      ),
      trailing: count != null
          ? Text(
              '$count',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isSelected ? colorScheme.primary : colorScheme.outline,
              ),
            )
          : null,
      selected: isSelected,
      dense: true,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      visualDensity: VisualDensity.compact,
    );
  }

  void _confirmRemove(BuildContext context, AppState appState, String path, String folderName) {
    final l10n = AppLocalizations.of(context)!;
    AppDialog.show<void>(
      context,
      title: l10n.removeFolderConfirmTitle,
      content: Text(l10n.removeFolderConfirmMessage(folderName)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.remove,
          variant: AppButtonVariant.destructive,
          onPressed: () {
            if (useFileBrowserState) {
              appState.fileBrowserState.removeBaseDirectory(path);
            } else {
              appState.removeBaseDirectory(path);
            }
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.clickAddFolder,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
