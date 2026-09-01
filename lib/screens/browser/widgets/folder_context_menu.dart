import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/file_transfer_service.dart';
import '../../../state/app_state.dart';
import '../../../state/file_staging_state.dart';
import '../staging_paste_flow.dart';

/// The folder context menu in the browser's directory tree — `B1 12d`.
///
/// This is where a paste destination is named. The browser lists several
/// active directories merged, so "here" has no meaning in the grid; a folder
/// in the tree is the only thing on this screen the user can point at and mean
/// one place.
void showFolderContextMenu({
  required BuildContext context,
  required String path,
  required Offset position,
}) {
  final l10n = AppLocalizations.of(context)!;
  final colorScheme = Theme.of(context).colorScheme;
  final appState = Provider.of<AppState>(context, listen: false);
  final staging = Provider.of<FileStagingState>(context, listen: false);

  final staged = staging.count;

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
    ],
  );
}

PopupMenuItem<void> _item({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  return PopupMenuItem<void>(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    onTap: onTap,
    child: Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SizedBox(
          height: 32,
          child: Row(
            children: [
              Icon(icon, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
