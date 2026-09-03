import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/folder_operations_service.dart';
import '../../../state/app_state.dart';
import '../../../state/file_staging_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snackbar.dart';

/// Confirms and performs the deletion of a folder in the browser's tree —
/// `B1b 13d`, then the tidy-up the tree needs afterwards.
///
/// Goes to the system trash wherever the platform has one, and says so in the
/// dialog before the user decides; only where there is none does it delete
/// for good, and then the dialog says *that*. The two are never confused for
/// each other, and a trash call that fails is reported, not downgraded.
Future<void> runFolderDelete(BuildContext context, String path) async {
  final l10n = AppLocalizations.of(context)!;
  final appState = Provider.of<AppState>(context, listen: false);
  final staging = Provider.of<FileStagingState>(context, listen: false);
  final name = p.basename(path);

  final toTrash = await FolderOperationsService.trashSupported;
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _FolderDeleteDialog(path: path, toTrash: toTrash),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await FolderOperationsService.delete(path, toTrash: toTrash);
  } on FileSystemException catch (e) {
    if (context.mounted) AppSnackBar.error(context, l10n.folderOpFailed(e.message));
    return;
  }

  // The marks under it are now genuinely missing — that is the state
  // `revalidate` exists to report, so it is asked to rather than told.
  await appState.fileBrowserState.pruneRemoved(path);
  await staging.revalidate();
  await appState.fileBrowserState.refresh();

  if (context.mounted) {
    AppSnackBar.success(context, toTrash ? l10n.folderTrashed(name) : l10n.folderDeleted(name));
  }
}

class _FolderDeleteDialog extends StatefulWidget {
  final String path;
  final bool toTrash;

  const _FolderDeleteDialog({required this.path, required this.toTrash});

  @override
  State<_FolderDeleteDialog> createState() => _FolderDeleteDialogState();
}

class _FolderDeleteDialogState extends State<_FolderDeleteDialog> {
  FolderInventory? _inventory;

  @override
  void initState() {
    super.initState();
    // The dialog opens at once and counts in the background: a folder of ten
    // thousand files must not make the user wait to see the question.
    FolderOperationsService.inventory(widget.path).then((value) {
      if (mounted) setState(() => _inventory = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final inventory = _inventory;
    final counting = inventory == null;
    final empty = inventory?.isEmpty ?? false;

    final String confirmLabel;
    if (counting || empty) {
      confirmLabel = widget.toTrash ? l10n.moveToTrash : l10n.delete;
    } else {
      confirmLabel = widget.toTrash
          ? l10n.trashFolderCount(inventory.items)
          : l10n.deleteFolderCount(inventory.items);
    }

    return AppDialog(
      icon: Icons.delete_outline,
      iconColor: colorScheme.error,
      title: widget.toTrash ? l10n.trashFolderTitle : l10n.deleteFolderTitle,
      subtitle: counting ? '${widget.path} · ${l10n.inventoryCounting}' : widget.path,
      maxWidth: 420,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!counting && empty)
            Text(
              widget.toTrash ? l10n.trashFolderEmptyDesc : l10n.deleteFolderEmptyDesc,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: AppType.proseHeight,
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _CountCell(
                    value: inventory?.folders,
                    label: l10n.inventorySubfolders,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountCell(
                    value: inventory?.files,
                    label: l10n.inventoryFiles,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountCell(
                    text: inventory == null ? null : AppConstants.formatFileSize(inventory.bytes),
                    label: l10n.inventorySize,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  widget.toTrash ? Icons.restore_from_trash_outlined : Icons.warning_amber_rounded,
                  size: AppSize.iconSm,
                  color: widget.toTrash ? colorScheme.onSurfaceVariant : colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.toTrash ? l10n.trashFolderRestorable : l10n.deleteFolderIrreversible,
                    style: textTheme.labelMedium?.copyWith(
                      color: widget.toTrash ? colorScheme.onSurfaceVariant : colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        // Enter lands on Cancel. Delete needs a click on the red button, or
        // a second press of the key that opened this.
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: confirmLabel,
          variant: AppButtonVariant.destructive,
          loading: counting,
          onPressed: counting ? null : () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// One of the three counts — number in mono, label under it — or its
/// placeholder while the count is still coming.
class _CountCell extends StatelessWidget {
  final int? value;
  final String? text;
  final String label;

  const _CountCell({this.value, this.text, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final display = text ?? value?.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (display == null)
            Container(
              width: 36,
              height: 18,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            )
          else
            Text(
              display,
              style: textTheme.titleLarge?.mono.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 3),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
