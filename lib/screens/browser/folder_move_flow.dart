import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../core/file_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/file_transfer_service.dart';
import '../../services/folder_operations_service.dart';
import '../../state/app_state.dart';
import '../../state/file_staging_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';
import 'widgets/transfer_dialog_parts.dart';

/// Brings every list that named a folder at [from] into step with its new
/// address [to] — the browser's roots and active directories, the staging
/// marks, the workbench's registered sources and output directory.
///
/// One function, because the three states have to move together: fix the
/// browser but not the staging area and the next revalidate reports files
/// missing that are right there; fix both but not the workbench and it
/// reports its source unreachable. The browser is rescanned once at the end.
Future<void> applyFolderPathChange(
  AppState appState,
  FileStagingState staging,
  String from,
  String to,
) async {
  staging.rewritePathPrefix(from, to);
  await appState.galleryState.rewritePathPrefix(from, to);
  await appState.fileBrowserState.rewritePathPrefix(from, to);
  await appState.fileBrowserState.refresh();
}

/// Moves or copies the folder at [source] into [destination] — `B1b 13e/13f`.
///
/// Both entry points land here: a drop onto a tree row, and the menu's
/// "Move to…" through the system picker. A same-volume move is one rename and
/// finishes before any dialog could open; the progress dialog appears only
/// once the copy route reports its first file, which is what makes the
/// instant case feel instant.
Future<void> runFolderTransfer(
  BuildContext context, {
  required String source,
  required String destination,
  required FolderTransferMode mode,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final appState = Provider.of<AppState>(context, listen: false);
  final staging = Provider.of<FileStagingState>(context, listen: false);
  final name = p.basename(source);
  final isMove = mode == FolderTransferMode.move;

  final rejection = FolderOperationsService.canTransfer(
    source,
    destination,
    roots: appState.fileBrowserState.sourceDirectories.toSet(),
    mode: mode,
  );
  if (rejection != null) {
    AppSnackBar.warning(context, _rejectionText(l10n, rejection));
    return;
  }

  final progress = ValueNotifier<FileTransferProgress?>(null);
  final crossVolume = FolderOperationsService.isLikelyCrossVolume(source, destination);
  var cancelled = false;
  var dialogShown = false;

  void showProgress() {
    dialogShown = true;
    // Not awaited: the transfer owns its own lifetime and pops this itself.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FolderProgressDialog(
        name: name,
        source: source,
        target: p.join(destination, name),
        mode: mode,
        crossVolume: crossVolume,
        progress: progress,
        onCancel: () => cancelled = true,
      ),
    ));
  }

  FolderTransferOutcome outcome;
  try {
    outcome = await FolderOperationsService.transfer(
      source,
      destination,
      mode: mode,
      onProgress: (value) {
        progress.value = value;
        if (!dialogShown && context.mounted) showProgress();
      },
      isCancelled: () => cancelled,
    );
  } on FileSystemException catch (e) {
    if (dialogShown && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    if (context.mounted) AppSnackBar.error(context, l10n.folderOpFailed(e.message));
    return;
  }

  if (dialogShown && context.mounted) Navigator.of(context, rootNavigator: true).pop();
  // After the pop, never before — the dialog listens to this until its route
  // is gone.
  progress.dispose();
  if (!context.mounted) return;

  if (isMove && outcome.isClean) {
    await applyFolderPathChange(appState, staging, source, outcome.targetPath);
  } else {
    await appState.fileBrowserState.refresh();
  }
  await staging.revalidate();
  if (!context.mounted) return;

  if (outcome.cancelled) {
    await _showCancelled(context, source, outcome, mode);
    return;
  }
  if (outcome.failure != null) {
    AppSnackBar.error(context, l10n.folderOpFailed(outcome.failure!));
    return;
  }

  appState.fileBrowserState.flash(outcome.targetPath);
  final target = p.basename(destination);
  AppSnackBar.success(context, isMove ? l10n.folderMoved(name, target) : l10n.folderCopied(name, target));
}

String _rejectionText(AppLocalizations l10n, FolderMoveRejection rejection) => switch (rejection) {
      FolderMoveRejection.isRoot => l10n.rootCannotMove,
      FolderMoveRejection.intoSelf || FolderMoveRejection.intoDescendant => l10n.moveFolderIntoSelf,
      FolderMoveRejection.sameParent => l10n.moveFolderSameParent,
      FolderMoveRejection.targetExists => l10n.moveFolderTargetExists,
    };

// --------------------------------------------------------------- 13f dialogs

class _FolderProgressDialog extends StatelessWidget {
  final String name;
  final String source;
  final String target;
  final FolderTransferMode mode;
  final bool crossVolume;
  final ValueNotifier<FileTransferProgress?> progress;
  final VoidCallback onCancel;

  const _FolderProgressDialog({
    required this.name,
    required this.source,
    required this.target,
    required this.mode,
    required this.crossVolume,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isMove = mode == FolderTransferMode.move;

    return PopScope(
      // Escape would leave the copy running with nothing reporting it.
      canPop: false,
      child: ValueListenableBuilder<FileTransferProgress?>(
        valueListenable: progress,
        builder: (context, value, _) {
          final done = value?.index ?? 0;
          final total = value?.total ?? 0;
          final bytesDone = value?.bytesDone ?? 0;
          final bytesTotal = value?.bytesTotal ?? 0;
          // By bytes, not by count: a folder of one video and a hundred
          // thumbnails would otherwise sit at 1% for most of the wait.
          final fraction = bytesTotal == 0 ? (total == 0 ? 0.0 : done / total) : bytesDone / bytesTotal;

          return AppDialog(
            icon: isMove ? Icons.drive_file_move_outlined : Icons.file_copy_outlined,
            iconColor: semantic.info,
            title: isMove ? l10n.folderMovingTitle(name) : l10n.folderCopyingTitle(name),
            subtitle: <String>[
              l10n.pasteRoute(source, target),
              l10n.folderTransferItems(total),
              if (crossVolume) l10n.pasteCrossVolumeTag,
            ].join(' · '),
            maxWidth: 460,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.pasteProgressItems(
                          done,
                          total,
                          AppConstants.formatFileSize(bytesDone),
                          AppConstants.formatFileSize(bytesTotal),
                        ),
                        style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${(fraction * 100).round()}%',
                      style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  value == null || value.name.isEmpty ? '' : l10n.pasteCurrentFile(value.name),
                  style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (crossVolume) ...[
                  const SizedBox(height: 12),
                  TransferInfoNote(text: l10n.folderMoveCrossVolumeNote),
                ],
              ],
            ),
            actionsOverride: Row(
              children: [
                const Spacer(),
                AppButton(
                  label: l10n.cancel,
                  variant: AppButtonVariant.destructiveOutline,
                  onPressed: onCancel,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// `13f`'s right half: what a cancelled copy left behind.
///
/// Amber, not red — nothing was lost. The source is whole; the destination
/// holds a partial copy the user may well want to keep, so it is not tidied
/// away for them.
Future<void> _showCancelled(
  BuildContext context,
  String source,
  FolderTransferOutcome outcome,
  FolderTransferMode mode,
) {
  final l10n = AppLocalizations.of(context)!;
  final colorScheme = Theme.of(context).colorScheme;
  final semantic = AppSemanticColors.of(context);
  final textTheme = Theme.of(context).textTheme;
  final pending = outcome.filesTotal - outcome.filesDone;

  return AppDialog.show<void>(
    context,
    icon: Icons.warning_amber_rounded,
    iconColor: semantic.warning,
    title: mode == FolderTransferMode.move ? l10n.folderMoveCancelledTitle : l10n.folderCopyCancelledTitle,
    subtitle: '${l10n.pasteRoute(source, outcome.targetPath)} · '
        '${l10n.folderTransferStoppedAt(outcome.filesDone, outcome.filesTotal)}',
    maxWidth: 460,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TransferStatCell(
                value: outcome.filesDone,
                label: l10n.folderMoveStatCopied,
                color: semantic.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TransferStatCell(
                value: pending,
                label: l10n.folderMoveStatPending,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TransferStatCell(
                value: outcome.filesTotal,
                label: l10n.folderMoveStatSourceKept,
                color: semantic.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l10n.folderMoveCancelledDesc,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: AppType.proseHeight,
          ),
        ),
      ],
    ),
    actionsOverride: Row(
      children: [
        AppButton(
          label: l10n.showDestinationInSystem,
          variant: AppButtonVariant.text,
          onPressed: () => FileUtils.openPath(outcome.targetPath),
        ),
        const Spacer(),
        AppButton(
          label: l10n.gotIt,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}
