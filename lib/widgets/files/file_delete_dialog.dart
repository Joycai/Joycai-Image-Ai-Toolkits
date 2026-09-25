import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/browser_file.dart';
import '../../services/files/file_delete_service.dart';
import '../ui/app_button.dart';
import '../ui/app_dialog.dart';
import '../ui/app_snackbar.dart';
import 'transfer_dialog_parts.dart';

/// How many files the dialog names before it starts counting them instead.
const int _kNamedFiles = 4;

/// Confirms and performs the deletion of files — `B1c · 1d/1e` — for every
/// screen that deletes one.
///
/// It lives here, under `widgets/`, because the workbench gallery deletes
/// files too and used to do it with a second implementation: a one-line
/// confirmation, and on macOS and Linux `File.delete()` — a permanent delete
/// where the browser sent the same file to the trash. One key on two screens
/// is only worth having if it means one thing, so the two deletes had to
/// become one first.
///
/// The folder side of this is [runFolderDelete] and the two say the same
/// thing the same way: the system trash wherever the platform has one, and
/// only where there is none a permanent delete, with the dialog saying which
/// *before* the user decides. A trash call that fails is reported, never
/// downgraded to deleting for good.
///
/// Unlike the folder dialog there is nothing to count — a [BrowserFile]
/// carries its size from the scan — so the confirm button is live from the
/// first frame.
/// [protectedRoots] are folders the run must refuse to delete — a registered
/// source folder is not a file the user can throw away from a grid.
/// [onDeleted] is the caller's tidy-up: what each screen has to re-read once
/// something is actually gone. It runs when at least one file was deleted,
/// and **whether or not the caller is still mounted** — deliberately, and
/// unlike the snackbar above it, which is guarded. What it re-reads is
/// app-level state (`FileBrowserState.refresh`, `FileStagingState.revalidate`,
/// `GalleryState.refreshImages`), and that state has to be right whether or
/// not the screen that asked for the delete is still on screen; skipping it
/// because the user navigated away would leave a grid listing files that are
/// no longer there. The price is the rule for whoever writes one: an
/// [onDeleted] may touch state and nothing else — no `context`, no
/// `setState`, no snackbar.
Future<void> runFileDelete(
  BuildContext context,
  List<BrowserFile> files, {
  Iterable<String> protectedRoots = const <String>[],
  Future<void> Function()? onDeleted,
}) async {
  if (files.isEmpty) return;

  final l10n = AppLocalizations.of(context)!;

  final bool toTrash = await FileDeleteService.trashSupported;
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    animationStyle: appDialogAnimation(context),
    builder: (_) => _FileDeleteDialog(files: files, toTrash: toTrash),
  );
  if (confirmed != true || !context.mounted) return;

  final FileDeleteOutcome outcome;
  try {
    outcome = await FileDeleteService.delete(
      files.map((BrowserFile f) => f.path),
      toTrash: toTrash,
      protectedRoots: protectedRoots,
    );
  } on FileSystemException catch (e) {
    if (context.mounted) AppSnackBar.error(context, l10n.folderOpFailed(e.message));
    return;
  }

  // Said before the refresh, which is what makes the rows behind this dialog
  // disappear — by the time the grid is back in step there is nothing left to
  // point at.
  if (context.mounted) {
    if (outcome.isClean) {
      final String name = files.first.name;
      AppSnackBar.success(
        context,
        outcome.deleted.length == 1
            ? (toTrash ? l10n.fileTrashed(name) : l10n.fileDeleted(name))
            : (toTrash
                  ? l10n.filesTrashed(outcome.deleted.length)
                  : l10n.filesDeleted(outcome.deleted.length)),
      );
    } else {
      AppSnackBar.error(
        context,
        l10n.filesDeletePartial(
          outcome.deleted.length,
          outcome.failed.length,
          outcome.failed.first.message,
        ),
      );
    }
  }

  if (outcome.deleted.isEmpty) return;
  await onDeleted?.call();
}

class _FileDeleteDialog extends StatelessWidget {
  const _FileDeleteDialog({required this.files, required this.toTrash});

  final List<BrowserFile> files;
  final bool toTrash;

  /// The one folder every file is in, or null when they come from several —
  /// the browser merges directories, so a single path would name only one of
  /// them and quietly misdescribe the rest.
  String? get _commonFolder {
    final String first = p.dirname(files.first.path);
    for (final BrowserFile file in files.skip(1)) {
      if (!p.equals(p.dirname(file.path), first)) return null;
    }
    return first;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final int count = files.length;
    final bool single = count == 1;

    final String? folder = _commonFolder;
    final String subtitle = single
        ? transferShortPath(files.first.path)
        : (folder != null
              ? transferShortPath(folder)
              : l10n.deleteFromFolders(
                  files.map((BrowserFile f) => p.dirname(f.path)).toSet().length,
                ));

    final String confirmLabel = toTrash
        ? (single ? l10n.moveToTrash : l10n.trashFileCount(count))
        : (single ? l10n.delete : l10n.deleteFileCount(count));

    // Enter lands on Cancel. The red button confirms, and so does a second
    // press of the key that opened this; repeats are ignored so a held key
    // cannot delete on its own.
    void confirm() => Navigator.pop(context, true);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.delete, includeRepeats: false): confirm,
        const SingleActivator(LogicalKeyboardKey.backspace, includeRepeats: false): confirm,
      },
      child: AppDialog(
        // Trash is recoverable, so it is a warning; a delete that skips the
        // trash is the error plate with the "forever" glyph.
        titleWidget: TransferDialogHeading(
          icon: toTrash ? Icons.delete_outline : Icons.delete_forever_outlined,
          tone: toTrash ? TransferTone.warn : TransferTone.err,
          title: toTrash
              ? (single ? l10n.trashFileTitle : l10n.trashFilesTitle(count))
              : (single ? l10n.deleteFileTitle : l10n.deleteFilesTitle(count)),
          subtitle: subtitle,
          subtitleTooltip: single ? files.first.path : folder,
        ),
        maxWidth: 440,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _FileListCard(files: files),
            const SizedBox(height: AppSpace.s10),
            TransferNote(
              text: toTrash ? l10n.trashRestorableNote : l10n.deleteIrreversibleNote,
              tone: toTrash ? TransferTone.ok : TransferTone.err,
              icon: toTrash ? Icons.restore_from_trash_outlined : Icons.warning_amber_rounded,
            ),
          ],
        ),
        actions: [
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppButton(label: confirmLabel, variant: AppButtonVariant.destructive, onPressed: confirm),
        ],
      ),
    );
  }
}

/// `1e`'s list card: one row per file up to [_kNamedFiles], then a rule and a
/// footer carrying what was left unnamed and the total size.
///
/// A single file gets the taller row with its type and size under the name —
/// there is room for it, and one file is the case where the user most wants
/// to be sure it is *that* one.
class _FileListCard extends StatelessWidget {
  const _FileListCard({required this.files});

  final List<BrowserFile> files;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bool single = files.length == 1;
    final int hidden = files.length - _kNamedFiles;
    final int bytes = files.fold<int>(0, (int sum, BrowserFile f) => sum + f.size);

    final BoxDecoration decoration = BoxDecoration(
      color: scheme.surfaceContainerLow,
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(AppRadius.control),
    );

    if (single) {
      final BrowserFile file = files.first;
      final String type = p.extension(file.name).replaceFirst('.', '').toUpperCase();
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            TransferThumb(path: file.path),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.name,
                    style: textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    type.isEmpty
                        ? AppConstants.formatFileSize(file.size)
                        : '$type · ${AppConstants.formatFileSize(file.size)}',
                    style: textTheme.bodySmall!.mono.copyWith(color: scheme.outline),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: decoration,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final BrowserFile file in files.take(_kNamedFiles))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 3),
              child: Row(
                children: [
                  TransferThumb(path: file.path, size: AppSize.compact),
                  const SizedBox(width: AppSpace.s10),
                  Expanded(
                    child: Text(
                      file.name,
                      style: textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Text(
                    AppConstants.formatFileSize(file.size),
                    style: textTheme.bodySmall!.mono.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
            child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s10, 0, AppSpace.s10, 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hidden > 0 ? l10n.deleteMoreFiles(hidden) : '',
                    style: textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                  ),
                ),
                Text(
                  l10n.deleteTotalSize(AppConstants.formatFileSize(bytes)),
                  style: textTheme.bodySmall!.mono.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
