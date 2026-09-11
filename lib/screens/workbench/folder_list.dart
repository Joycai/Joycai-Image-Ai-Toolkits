import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/gallery_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/panel_resizer.dart';
import 'directory_tree_item.dart';
import 'widgets/result_tree_item.dart';

/// A registered folder the user has asked to take off the list, waiting on
/// the inline confirmation card.
typedef _PendingRemoval = ({String path, String name});

/// The folder column — `A1 1a` on the workbench, and the file browser's
/// directory tree.
///
/// Paints no ground of its own: the column (`surfaceContainerLow`) comes from
/// whatever hosts it — the layout's column panel or the drawer.
class FolderList extends StatefulWidget {
  final bool useFileBrowserState;

  const FolderList({
    super.key,
    this.useFileBrowserState = false,
  });

  @override
  State<FolderList> createState() => _FolderListState();
}

class _FolderListState extends State<FolderList> {
  _PendingRemoval? _pendingRemoval;

  bool get useFileBrowserState => widget.useFileBrowserState;

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

    // A folder that left the list some other way has nothing left to confirm.
    final pending = _pendingRemoval != null && sourceDirectories.contains(_pendingRemoval!.path)
        ? _pendingRemoval
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (Platform.isIOS || Platform.isAndroid)
          _buildSandboxNotice(context, colorScheme, l10n)
        else if (!useFileBrowserState)
          Padding(
            padding: const EdgeInsets.all(AppSpace.s10),
            // An outline, not a fill: adding a folder sets up the work;
            // running the model is the work, and the workbench keeps exactly
            // one solid accent button for that. The *label* carries the deep
            // ink (`A1 1a`) — the column has nothing else in it to act on.
            child: AppButton(
              label: l10n.addFolder,
              icon: Icons.create_new_folder_outlined,
              variant: AppButtonVariant.secondary,
              accentLabel: true,
              fullWidth: true,
              onPressed: () => _pickDirectory(context, appState),
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
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '${sourceDirectories.length}',
                    style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
                      fontWeight: FontWeight.w600,
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
          Divider(height: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: sourceDirectories.isEmpty
                ? _buildEmptyState(context, colorScheme, l10n)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
                    itemCount: sourceDirectories.length,
                    itemBuilder: (context, index) {
                      final path = sourceDirectories[index];
                      return DirectoryTreeItem(
                        key: ValueKey(path),
                        path: path,
                        isRoot: true,
                        useFileBrowserState: useFileBrowserState,
                        onRemove: _requestRemove,
                      );
                    },
                  ),
          ),
        ] else
          Expanded(
            child: _buildGalleryGroups(context, galleryState, colorScheme, l10n, sourceDirectories),
          ),

        // `A1 1c`: removing a folder is confirmed in the column it is being
        // removed from, not in a dialog over the whole window.
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.bottomCenter,
          child: pending == null
              ? const SizedBox(width: double.infinity)
              : _RemoveFolderCard(
                  key: ValueKey(pending.path),
                  folderName: pending.name,
                  onCancel: () => setState(() => _pendingRemoval = null),
                  onConfirm: () => _removePending(appState),
                ),
        ),
      ],
    );
  }

  Widget _buildGalleryGroups(
    BuildContext context,
    GalleryState galleryState,
    ColorScheme colorScheme,
    AppLocalizations l10n,
    List<String> sourceDirectories,
  ) {
    final resultRoots = galleryState.resultRootDirectories;
    final metrics = FolderTreeMetrics.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.s10),
      children: [
        // SOURCES — the aggregate "All Sources" view is the head of the group,
        // with the browsable source-folder tree nested beneath it.
        _buildSectionHeader(context, metrics, l10n.sectionSources, count: sourceDirectories.length, first: true),
        _buildFixedNode(
          metrics,
          icon: Icons.photo_library_outlined,
          label: l10n.allSources,
          isSelected: galleryState.viewMode == GalleryViewMode.all,
          onTap: () => galleryState.setViewMode(GalleryViewMode.all),
          count: galleryState.galleryImages.length,
        ),
        if (sourceDirectories.isEmpty)
          _buildInlineHint(context, metrics, l10n.noFolders)
        else
          ...sourceDirectories.map((path) => DirectoryTreeItem(
                key: ValueKey(path),
                path: path,
                isRoot: true,
                useFileBrowserState: false,
                onRemove: _requestRemove,
              )),

        // RESULTS — the result cache is also a real folder tree, now browsable.
        _buildSectionHeader(context, metrics, l10n.sectionResults, count: resultRoots.length),
        _buildFixedNode(
          metrics,
          icon: Icons.auto_awesome_motion_outlined,
          label: l10n.allResults,
          isSelected: galleryState.viewMode == GalleryViewMode.processed,
          onTap: () => galleryState.setViewMode(GalleryViewMode.processed),
          count: galleryState.processedImages.length,
        ),
        if (resultRoots.isEmpty)
          _buildInlineHint(context, metrics, l10n.noResultsYet)
        else
          ...resultRoots.map((path) => ResultTreeItem(key: ValueKey(path), path: path, isRoot: true)),

        // WORKSPACE — transient drop zone.
        _buildSectionHeader(context, metrics, l10n.sectionWorkspace),
        _buildFixedNode(
          metrics,
          icon: Icons.inbox_outlined,
          label: l10n.tempWorkspace,
          isSelected: galleryState.viewMode == GalleryViewMode.temp,
          onTap: () => galleryState.setViewMode(GalleryViewMode.temp),
          count: galleryState.droppedImages.length,
        ),
      ],
    );
  }

  /// A group caption — 11/500 tracked, in the deep ink (`--p-deep`), with its
  /// count untracked in mono. The first sits close under the Add Folder
  /// button; the rest open a gap above themselves instead of a divider.
  Widget _buildSectionHeader(
    BuildContext context,
    FolderTreeMetrics metrics,
    String label, {
    int? count,
    bool first = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(metrics.headerInset, first ? AppSpace.s6 : 14, metrics.headerInset, AppSpace.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: AppType.trackedLabelSpacing,
                color: colorScheme.onAccentTint,
              ),
            ),
          ),
          if (count != null)
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.mono.copyWith(
                letterSpacing: 0,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// A quiet row where a group's folders would be, starting just past a root
  /// row's chevron slot.
  Widget _buildInlineHint(BuildContext context, FolderTreeMetrics metrics, String text) {
    final theme = Theme.of(context);
    final inset = metrics.margin + metrics.padding + FolderTreeMetrics.disclosureSize + metrics.gap;
    return Container(
      constraints: BoxConstraints(minHeight: metrics.height),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.fromLTRB(inset, 0, metrics.headerInset, 0),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildFixedNode(
    FolderTreeMetrics metrics, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    int? count,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.margin),
      child: FolderTreeRow(
        icon: icon,
        label: label,
        count: count == null ? null : '$count',
        selected: isSelected,
        onTap: onTap,
      ),
    );
  }

  /// `A1 1e`: an outlined card in the Add Folder button's place, with the
  /// explanation set quietly under it.
  Widget _buildSandboxNotice(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, AppSpace.s10, 12, AppSpace.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: AppSize.touch),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: AppSize.iconMd, color: colorScheme.onAccentTint),
                const SizedBox(width: AppSpace.s6),
                Flexible(
                  child: Text(
                    Platform.isIOS ? l10n.iosSandboxActive : l10n.mobileSandboxActive,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onAccentTint),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s6, AppSpace.s4, 0),
            child: Text(
              Platform.isIOS ? l10n.iosSandboxDesc : l10n.mobileSandboxDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: AppType.proseHeight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _requestRemove(String path, String folderName) {
    setState(() => _pendingRemoval = (path: path, name: folderName));
  }

  void _removePending(AppState appState) {
    final pending = _pendingRemoval;
    if (pending == null) return;
    setState(() => _pendingRemoval = null);
    if (useFileBrowserState) {
      appState.fileBrowserState.removeBaseDirectory(pending.path);
    } else {
      appState.removeBaseDirectory(pending.path);
    }
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

/// `A1 1c`: the remove-folder confirmation, set at the foot of the column.
///
/// Panel ground on the column, hairline, r10. Cancel is the deep-ink text
/// button; Remove is the one solid error fill, and only appears here — after
/// the user has already asked.
class _RemoveFolderCard extends StatelessWidget {
  final String folderName;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _RemoveFolderCard({
    super.key,
    required this.folderName,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final body = theme.textTheme.bodySmall?.copyWith(height: AppType.proseHeight);

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(AppSpace.s6),
        padding: const EdgeInsets.all(AppSpace.s10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.removeFolderConfirmTitle,
              style: body?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
            ),
            Text(
              l10n.removeFolderConfirmMessage(folderName),
              style: body?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpace.s6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpace.s4,
              runSpacing: AppSpace.s4,
              children: [
                AppButton(
                  label: l10n.cancel,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.compact,
                  onPressed: onCancel,
                ),
                AppButton(
                  label: l10n.remove,
                  variant: AppButtonVariant.destructive,
                  size: AppButtonSize.compact,
                  onPressed: onConfirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
