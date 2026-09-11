import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/file_transfer_service.dart';
import '../../../state/app_state.dart';
import '../../../state/file_staging_state.dart';
import '../staging_paste_flow.dart';
import '../../../widgets/glass/app_glass_menu.dart';

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

  showAppGlassMenu(
    context,
    position: position,
    width: 250,
    entries: <AppGlassMenuEntry>[
      AppGlassMenuItem(
        icon: Icons.filter_alt_outlined,
        label: l10n.onlyThisDirectory,
        onSelected: () => appState.fileBrowserState.setExclusiveDirectory(path),
      ),
      AppGlassMenuItem(
        icon: Icons.deselect,
        label: l10n.deselectAllDirectories,
        onSelected: () => appState.fileBrowserState.clearActiveDirectories(),
      ),
      if (staged > 0) ...[
        const AppGlassMenuDivider(),
        // The count is in the label because this menu commits immediately —
        // there is no second screen between the click and the files moving,
        // so the number of files has to be on the thing being clicked.
        AppGlassMenuItem(
          icon: Icons.drive_file_move_outlined,
          label: l10n.moveCountHere(staged),
          onSelected: () => runStagingPaste(context, mode: FileTransferMode.move, destination: path),
        ),
        AppGlassMenuItem(
          icon: Icons.content_copy_outlined,
          label: l10n.copyCountHere(staged),
          onSelected: () => runStagingPaste(context, mode: FileTransferMode.copy, destination: path),
        ),
      ],
      const AppGlassMenuDivider(),
      AppGlassMenuItem(
        icon: Icons.open_in_new,
        label: l10n.showInSystem,
        onSelected: () => FileUtils.openPath(path),
      ),
      if (manages) ...[
        const AppGlassMenuDivider(),
        AppGlassMenuItem(
          icon: Icons.create_new_folder_outlined,
          label: l10n.newSubfolder,
          onSelected: onNewSubfolder ?? () {},
          enabled: onNewSubfolder != null,
        ),
        AppGlassMenuItem(
          icon: Icons.drive_file_rename_outline,
          label: l10n.rename,
          trailing: 'F2',
          onSelected: onRename ?? () {},
          enabled: onRename != null,
        ),
        AppGlassMenuItem(
          icon: Icons.drive_file_move_outline,
          label: l10n.moveFolderTo,
          onSelected: onMoveTo ?? () {},
          enabled: !isRoot && onMoveTo != null,
          note: isRoot ? l10n.rootCannotMove : null,
        ),
        const AppGlassMenuDivider(),
        if (isRoot)
          AppGlassMenuItem(
            icon: Icons.playlist_remove,
            label: l10n.removeFromList,
            onSelected: onRemoveFromList ?? () {},
            enabled: onRemoveFromList != null,
          )
        else
          AppGlassMenuItem(
            icon: Icons.delete_outline,
            label: l10n.delete,
            trailing: 'Delete',
            danger: true,
            onSelected: onDelete ?? () {},
            enabled: onDelete != null,
          ),
      ],
    ],
  );
}
