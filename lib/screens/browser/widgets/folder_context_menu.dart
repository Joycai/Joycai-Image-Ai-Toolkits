import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/file_transfer_service.dart';
import '../../../state/app_state.dart';
import '../../../state/file_staging_state.dart';
import '../staging_paste_flow.dart';

/// The folder context menu in the browser's directory tree — `B1a 12d` plus
/// the management group `B1b 13a` adds beneath it.
///
/// This is where a paste destination is named. The browser lists several
/// active directories merged, so "here" has no meaning in the grid; a folder
/// in the tree is the only thing on this screen the user can point at and mean
/// one place.
///
/// The management callbacks are optional so the menu degrades to `12d` where
/// the caller has nothing to manage with. [isRoot] switches the last group to
/// the registered-root rules: "Delete" becomes "Remove from list" (the list
/// entry goes, the disk is untouched) and "Move to…" is shown disabled with
/// the reason under it — a root is a registration, not a folder to be moved.
void showFolderContextMenu({
  required BuildContext context,
  required String path,
  required Offset position,
  bool isRoot = false,
  VoidCallback? onNewSubfolder,
  VoidCallback? onRename,
  VoidCallback? onMoveTo,
  VoidCallback? onDelete,
  VoidCallback? onRemoveFromList,
}) {
  final l10n = AppLocalizations.of(context)!;
  final colorScheme = Theme.of(context).colorScheme;
  final appState = Provider.of<AppState>(context, listen: false);
  final staging = Provider.of<FileStagingState>(context, listen: false);

  final staged = staging.count;
  final manages = onNewSubfolder != null || onRename != null || onDelete != null;

  showMenu<void>(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
    constraints: const BoxConstraints(minWidth: 230, maxWidth: 230),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    color: colorScheme.surface,
    items: <PopupMenuEntry<void>>[
      _item(
        icon: Icons.filter_list,
        label: l10n.onlyThisDirectory,
        onTap: () => appState.fileBrowserState.setExclusiveDirectory(path),
      ),
      _item(
        icon: Icons.deselect,
        label: l10n.deselectAllDirectories,
        onTap: () => appState.fileBrowserState.clearActiveDirectories(),
      ),
      if (staged > 0) ...[
        const PopupMenuDivider(),
        // The count is in the label because this menu commits immediately —
        // there is no second screen between the click and the files moving,
        // so the number of files has to be on the thing being clicked.
        _item(
          icon: Icons.drive_file_move_outlined,
          label: l10n.moveCountHere(staged),
          onTap: () => runStagingPaste(context, mode: FileTransferMode.move, destination: path),
        ),
        _item(
          icon: Icons.file_copy_outlined,
          label: l10n.copyCountHere(staged),
          onTap: () => runStagingPaste(context, mode: FileTransferMode.copy, destination: path),
        ),
      ],
      const PopupMenuDivider(),
      _item(
        icon: Icons.open_in_new,
        label: l10n.showInSystem,
        onTap: () => FileUtils.openPath(path),
      ),
      if (manages) ...[
        const PopupMenuDivider(),
        _item(
          icon: Icons.create_new_folder_outlined,
          label: l10n.newSubfolder,
          onTap: onNewSubfolder ?? () {},
          enabled: onNewSubfolder != null,
        ),
        _item(
          icon: Icons.drive_file_rename_outline,
          label: l10n.rename,
          shortcut: 'F2',
          onTap: onRename ?? () {},
          enabled: onRename != null,
        ),
        _item(
          icon: Icons.drive_file_move_outline,
          label: l10n.moveFolderTo,
          onTap: onMoveTo ?? () {},
          enabled: !isRoot && onMoveTo != null,
          note: isRoot ? l10n.rootCannotMove : null,
        ),
        if (isRoot)
          _item(
            icon: Icons.playlist_remove,
            label: l10n.removeFromList,
            onTap: onRemoveFromList ?? () {},
            enabled: onRemoveFromList != null,
          )
        else
          _item(
            icon: Icons.delete_outline,
            label: l10n.delete,
            shortcut: 'Delete',
            danger: true,
            onTap: onDelete ?? () {},
            enabled: onDelete != null,
          ),
      ],
    ],
  );
}

PopupMenuItem<void> _item({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  String? shortcut,
  bool danger = false,
  bool enabled = true,

  /// A second, quieter line under the label explaining a disabled item. Only
  /// drawn when the item is disabled — an enabled item needs no excuse.
  String? note,
}) {
  final showNote = !enabled && note != null;
  final height = showNote ? 46.0 : 32.0;
  return PopupMenuItem<void>(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    enabled: enabled,
    onTap: onTap,
    child: Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final Color iconColor;
        final Color labelColor;
        if (!enabled) {
          iconColor = colorScheme.outline;
          labelColor = colorScheme.outline;
        } else if (danger) {
          iconColor = colorScheme.error;
          labelColor = colorScheme.error;
        } else {
          iconColor = colorScheme.onSurfaceVariant;
          labelColor = colorScheme.onSurface;
        }

        return SizedBox(
          height: height,
          child: Row(
            children: [
              Icon(icon, size: AppSize.iconSm, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: textTheme.bodySmall?.copyWith(
                        color: labelColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showNote)
                      Text(
                        note,
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (shortcut != null) ...[
                const SizedBox(width: 10),
                Text(
                  shortcut,
                  style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
