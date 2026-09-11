import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/file_transfer_service.dart';
import '../../../state/app_state.dart';
import '../../../state/file_staging_state.dart';
import '../staging_paste_flow.dart';
import 'folder_glass_menu.dart';

/// The folder context menu in the browser's directory tree — `B1b 1d`: a
/// 250-wide float-grade glass menu in groups of look · paste · show · manage ·
/// remove.
///
/// This is where a paste destination is named. The browser lists several
/// active directories merged, so "here" has no meaning in the grid; a folder
/// in the tree is the only thing on this screen the user can point at and mean
/// one place.
///
/// The management callbacks are optional so the menu degrades to the first
/// three groups where the caller has nothing to manage with. [isRoot] switches
/// to the registered-root rules: "Delete" becomes "Remove from list" (the list
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
  final appState = Provider.of<AppState>(context, listen: false);
  final staging = Provider.of<FileStagingState>(context, listen: false);

  final staged = staging.count;
  final manages = onNewSubfolder != null || onRename != null || onDelete != null;

  showFolderGlassMenu(
    context: context,
    position: position,
    entries: <Widget>[
      folderGlassMenuItem(
        icon: Icons.filter_alt_outlined,
        label: l10n.onlyThisDirectory,
        onTap: () => appState.fileBrowserState.setExclusiveDirectory(path),
      ),
      folderGlassMenuItem(
        icon: Icons.deselect,
        label: l10n.deselectAllDirectories,
        onTap: () => appState.fileBrowserState.clearActiveDirectories(),
      ),
      if (staged > 0) ...[
        const FolderGlassMenuDivider(),
        // The count is in the label because this menu commits immediately —
        // there is no second screen between the click and the files moving,
        // so the number of files has to be on the thing being clicked.
        folderGlassMenuItem(
          icon: Icons.drive_file_move_outlined,
          label: l10n.moveCountHere(staged),
          onTap: () => runStagingPaste(context, mode: FileTransferMode.move, destination: path),
        ),
        folderGlassMenuItem(
          icon: Icons.content_copy_outlined,
          label: l10n.copyCountHere(staged),
          onTap: () => runStagingPaste(context, mode: FileTransferMode.copy, destination: path),
        ),
      ],
      const FolderGlassMenuDivider(),
      folderGlassMenuItem(
        icon: Icons.open_in_new,
        label: l10n.showInSystem,
        onTap: () => FileUtils.openPath(path),
      ),
      if (manages) ...[
        const FolderGlassMenuDivider(),
        folderGlassMenuItem(
          icon: Icons.create_new_folder_outlined,
          label: l10n.newSubfolder,
          onTap: onNewSubfolder ?? () {},
          enabled: onNewSubfolder != null,
        ),
        folderGlassMenuItem(
          icon: Icons.drive_file_rename_outline,
          label: l10n.rename,
          shortcut: 'F2',
          onTap: onRename ?? () {},
          enabled: onRename != null,
        ),
        folderGlassMenuItem(
          icon: Icons.drive_file_move_outline,
          label: l10n.moveFolderTo,
          onTap: onMoveTo ?? () {},
          enabled: !isRoot && onMoveTo != null,
          disabledNote: isRoot ? l10n.rootCannotMove : null,
        ),
        const FolderGlassMenuDivider(),
        if (isRoot)
          folderGlassMenuItem(
            icon: Icons.playlist_remove,
            label: l10n.removeFromList,
            onTap: onRemoveFromList ?? () {},
            enabled: onRemoveFromList != null,
          )
        else
          folderGlassMenuItem(
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
