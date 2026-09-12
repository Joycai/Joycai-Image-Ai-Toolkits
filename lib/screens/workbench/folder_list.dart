import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/browser_file.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../state/gallery_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/drag/app_drag_session.dart';
import 'directory_tree_item.dart';
import 'widgets/result_tree_item.dart';

/// A registered folder the user has asked to take off the list, waiting on
/// the inline confirmation card.
typedef _PendingRemoval = ({String path, String name});

/// Everything this column draws out of [GalleryState] — and nothing else.
///
/// Pointedly missing: the selection. The column used to `watch` the whole
/// notifier, so picking a picture in the grid rebuilt the entire folder tree,
/// every [DirectoryTreeItem] and [ResultTreeItem] under it, for a change that
/// does not reach the column at all.
///
/// The list fields compare by identity, which [GalleryState] guarantees — it
/// assigns a fresh list before notifying.
typedef _FolderInputs = ({
  List<String> resultRoots,
  GalleryViewMode viewMode,
  int galleryCount,
  int processedCount,
  int droppedCount,
});

/// The same, for the file browser's tree. Its column draws the registered
/// folders and whether any of them is ticked; the browser's selection, its
/// scans and its size slider are none of its business.
typedef _BrowserInputs = ({
  List<String> sourceDirectories,
  bool hasActive,
});

_BrowserInputs _browserInputs(FileBrowserState s) => (
      sourceDirectories: s.sourceDirectories,
      hasActive: s.activeDirectories.isNotEmpty,
    );

_FolderInputs _folderInputs(GalleryState s) => (
      resultRoots: s.resultRootDirectories,
      viewMode: s.viewMode,
      galleryCount: s.galleryImages.length,
      processedCount: s.processedImages.length,
      droppedCount: s.droppedImages.length,
    );

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
    // drawn, so it has to name the one it is actually showing — and, within
    // it, only the fields it draws (see [_FolderInputs]).
    final galleryState = Provider.of<GalleryState>(context, listen: false);
    final browser = useFileBrowserState
        ? context.select<FileBrowserState, _BrowserInputs>(_browserInputs)
        : null;
    final sourceDirectories = browser?.sourceDirectories ??
        context.select<GalleryState, List<String>>((s) => s.sourceDirectories);

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
          // `B1a · 1a`: a compact 40px caption row. The tracked caption in the
          // deep ink, the count on the track, two borderless 28px actions.
          Container(
            height: 40,
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, 8, 0),
            child: Row(
              children: [
                Text(
                  l10n.directories.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        letterSpacing: AppType.trackedLabelSpacing,
                        color: colorScheme.onAccentTint,
                      ),
                ),
                const SizedBox(width: AppSpace.s6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    '${sourceDirectories.length}',
                    style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                          fontWeight: FontWeight.w400,
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const Spacer(),
                _HeaderAction(
                  icon: Icons.deselect,
                  tooltip: l10n.deselectAllDirectories,
                  onPressed: browser!.hasActive
                      ? () => appState.fileBrowserState.clearActiveDirectories()
                      : null,
                ),
                const SizedBox(width: 2),
                _HeaderAction(
                  icon: Icons.create_new_folder_outlined,
                  tooltip: l10n.addFolder,
                  onPressed: () => _pickDirectory(context, appState),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: sourceDirectories.isEmpty
                ? _buildEmptyState(context, colorScheme, l10n)
                : _ArmedTreeEdge(
                    child: ListView.builder(
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
          ),
          // `B1a · 1a`: how a drop onto a folder behaves, said once at the foot
          // of the column. Pointer platforms only — a phone has no Ctrl.
          if (sourceDirectories.isNotEmpty && !(Platform.isIOS || Platform.isAndroid))
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s10, AppSpace.s16, AppSpace.s10),
              child: Text(
                // The copy key is ⌥ on macOS, as `AppCopyModifier` reads it.
                defaultTargetPlatform == TargetPlatform.macOS
                    ? l10n.browserDragFootnoteMac
                    : l10n.browserDragFootnote,
                style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.outline,
                      height: AppType.proseHeight,
                    ),
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
    final folders = context.select<GalleryState, _FolderInputs>(_folderInputs);
    final resultRoots = folders.resultRoots;
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
          isSelected: folders.viewMode == GalleryViewMode.all,
          onTap: () => galleryState.setViewMode(GalleryViewMode.all),
          count: folders.galleryCount,
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
          isSelected: folders.viewMode == GalleryViewMode.processed,
          onTap: () => galleryState.setViewMode(GalleryViewMode.processed),
          count: folders.processedCount,
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
          isSelected: folders.viewMode == GalleryViewMode.temp,
          onTap: () => galleryState.setViewMode(GalleryViewMode.temp),
          count: folders.droppedCount,
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
            Icon(Icons.folder_off_outlined, size: 28, color: colorScheme.outline),
            const SizedBox(height: AppSpace.s6),
            Text(
              l10n.noFolders,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.s6),
            Text(
              l10n.clickAddFolder,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: AppType.proseHeight,
                  ),
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

/// `00d · 1d` 可放: while a file selection or a folder is dragged, the tree it
/// can land on takes a 1px dashed accent edge at r10 — "drop over here".
///
/// The ground does not change and nothing moves: the edge is painted over the
/// list, inset by half a row's margin, rather than put around it, so arming
/// never reflows the rows under the pointer.
class _ArmedTreeEdge extends StatelessWidget {
  const _ArmedTreeEdge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final double inset = FolderTreeMetrics.of(context).margin / 2;
    return ValueListenableBuilder<Object?>(
      valueListenable: AppDragSession.current,
      child: child,
      builder: (context, payload, child) {
        final armed = payload is List<BrowserFile> || payload is FolderDragPayload;
        return CustomPaint(
          foregroundPainter: _ArmedEdgePainter(color: armed ? accent : null, inset: inset),
          child: child,
        );
      },
    );
  }
}

class _ArmedEdgePainter extends CustomPainter {
  const _ArmedEdgePainter({required this.color, required this.inset});

  /// Null while nothing the tree takes is in flight.
  final Color? color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = color;
    if (edge == null) return;
    drawDashedRRect(
      canvas,
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(AppRadius.control)).deflate(inset),
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ArmedEdgePainter old) => old.color != color || old.inset != inset;
}

/// A borderless 28px action in the directory column's caption row
/// (`B1a · 1a`): the deep ink, and the outline once there is nothing to do.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onAccentTint,
        disabledForegroundColor: colorScheme.outline,
        iconSize: AppSize.iconMd,
        fixedSize: const Size.square(AppSize.compact),
        minimumSize: const Size.square(AppSize.compact),
        maximumSize: const Size.square(AppSize.compact),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    );
  }
}
