import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'transfer_dialog_parts.dart';

/// Confirms and performs the deletion of a folder in the browser's tree —
/// `B1b 1d`'s two delete dialogs, then the tidy-up the tree needs afterwards.
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
    await FolderOperationsService.delete(
      path,
      toTrash: toTrash,
      protectedRoots: appState.fileBrowserState.sourceDirectories,
    );
  } on FileSystemException catch (e) {
    if (context.mounted) AppSnackBar.error(context, l10n.folderOpFailed(e.message));
    return;
  }

  // Said now, from the row that asked: the refresh below reloads its
  // parent's children and this row is gone before the lists are in step.
  if (context.mounted) {
    AppSnackBar.success(context, toTrash ? l10n.folderTrashed(name) : l10n.folderDeleted(name));
  }

  // The marks under it are now genuinely missing — that is the state
  // `revalidate` exists to report, so it is asked to rather than told.
  await appState.fileBrowserState.pruneRemoved(path);
  await staging.revalidate();
  await appState.fileBrowserState.refresh();
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

    // Enter lands on Cancel. The red button confirms, and so does a second
    // press of the key that opened this — once the count is in. Repeats are
    // ignored so a held key cannot delete on its own.
    void confirm() => Navigator.pop(context, true);
    return CallbackShortcuts(
      bindings: counting
          ? const <ShortcutActivator, VoidCallback>{}
          : <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.delete, includeRepeats: false): confirm,
              const SingleActivator(LogicalKeyboardKey.backspace, includeRepeats: false): confirm,
            },
      child: AppDialog(
        // Trash is recoverable, so it is a warning; a delete that skips the
        // trash is the error plate with the "forever" glyph.
        titleWidget: TransferDialogHeading(
          icon: widget.toTrash ? Icons.delete_outline : Icons.delete_forever_outlined,
          tone: widget.toTrash ? TransferTone.warn : TransferTone.err,
          title: widget.toTrash ? l10n.trashFolderTitle : l10n.deleteFolderTitle,
          subtitle: transferShortPath(widget.path),
          subtitleTooltip: widget.path,
        ),
        maxWidth: 440,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!counting && empty)
              Text(
                widget.toTrash ? l10n.trashFolderEmptyDesc : l10n.deleteFolderEmptyDesc,
                style: textTheme.bodySmall!.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              )
            else
              _InventoryCard(inventory: inventory),
            if (widget.toTrash && !(empty && !counting)) ...[
              const SizedBox(height: AppSpace.s10),
              TransferNote(
                text: l10n.trashFolderRestorable,
                tone: TransferTone.ok,
                icon: Icons.restore_from_trash_outlined,
              ),
            ],
            if (!widget.toTrash && !(empty && !counting)) ...[
              const SizedBox(height: AppSpace.s10),
              TransferNote(
                text: l10n.deleteFolderIrreversible,
                tone: TransferTone.err,
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ],
        ),
        actions: [
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
      ),
    );
  }
}

/// `1d`'s inventory card: Subfolders / Files / Size on the column colour, the
/// figures right-aligned in mono, "Counting…" in their place until the
/// isolate reports.
class _InventoryCard extends StatelessWidget {
  final FolderInventory? inventory;

  const _InventoryCard({required this.inventory});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final value = inventory;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        children: [
          _InventoryRow(label: l10n.inventorySubfolders, value: value?.folders.toString()),
          _InventoryRow(label: l10n.inventoryFiles, value: value?.files.toString()),
          _InventoryRow(
            label: l10n.inventorySize,
            value: value == null ? null : AppConstants.formatFileSize(value.bytes),
          ),
        ],
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  final String label;

  /// Null while counting.
  final String? value;

  const _InventoryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      height: AppSize.compact,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium!.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          Text(
            value ?? l10n.inventoryCounting,
            style: value == null
                ? textTheme.bodySmall!.copyWith(color: colorScheme.outline)
                : textTheme.bodySmall!.mono.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ],
      ),
    );
  }
}
