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

/// Moves or copies the folder at [source] into [destination] — `B1b 1c`.
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

  // Everything shown from here on is shown from the root navigator, not from
  // the row this was called on: the menu's "Move to…" arrives on the *source*
  // row, and a move rebuilds the tree without it — so the row's own context
  // is unmounted exactly when there is a summary or a snackbar to show.
  final host = Navigator.of(context, rootNavigator: true).context;

  final rejection = FolderOperationsService.canTransfer(
    source,
    destination,
    roots: appState.fileBrowserState.sourceDirectories.toSet(),
    mode: mode,
  );
  if (rejection != null) {
    final text = _rejectionText(l10n, rejection);
    // A move into itself or onto an existing name is refused outright (`1a`
    // lists it as an error); a root or a no-op move only needs a nudge.
    switch (rejection) {
      case FolderMoveRejection.intoSelf:
      case FolderMoveRejection.intoDescendant:
      case FolderMoveRejection.targetExists:
        AppSnackBar.error(host, text);
      case FolderMoveRejection.isRoot:
      case FolderMoveRejection.sameParent:
        AppSnackBar.warning(host, text);
    }
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
      context: host,
      animationStyle: appDialogAnimation(host),
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
        if (!dialogShown && host.mounted) showProgress();
      },
      isCancelled: () => cancelled,
    );
  } on FileSystemException catch (e) {
    if (dialogShown && host.mounted) Navigator.of(host).pop();
    progress.dispose();
    if (host.mounted) AppSnackBar.error(host, l10n.folderOpFailed(e.message));
    return;
  }

  if (dialogShown && host.mounted) Navigator.of(host).pop();
  // After the pop, never before — the dialog listens to this until its route
  // is gone.
  progress.dispose();
  if (!host.mounted) return;

  if (isMove && outcome.isClean) {
    await applyFolderPathChange(appState, staging, source, outcome.targetPath);
  } else {
    await appState.fileBrowserState.refresh();
  }
  await staging.revalidate();
  if (!host.mounted) return;

  if (outcome.cancelled) {
    await _showCancelled(host, source, outcome, mode);
    return;
  }
  if (outcome.failure != null) {
    AppSnackBar.error(host, l10n.folderOpFailed(outcome.failure!));
    return;
  }

  appState.fileBrowserState.flash(outcome.targetPath);
  final target = p.basename(destination);
  AppSnackBar.success(host, isMove ? l10n.folderMoved(name, target) : l10n.folderCopied(name, target));
}

String _rejectionText(AppLocalizations l10n, FolderMoveRejection rejection) => switch (rejection) {
      FolderMoveRejection.isRoot => l10n.rootCannotMove,
      FolderMoveRejection.intoSelf || FolderMoveRejection.intoDescendant => l10n.moveFolderIntoSelf,
      FolderMoveRejection.sameParent => l10n.moveFolderSameParent,
      FolderMoveRejection.targetExists => l10n.moveFolderTargetExists,
    };

// ---------------------------------------------------------------- 1c dialogs

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
    final textTheme = Theme.of(context).textTheme;
    final isMove = mode == FolderTransferMode.move;
    final mono11 = textTheme.labelSmall!.mono.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );

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
            titleWidget: TransferDialogHeading(
              icon: isMove ? Icons.drive_file_move_outlined : Icons.content_copy_outlined,
              tone: TransferTone.accent,
              title: isMove ? l10n.folderMovingTitle(name) : l10n.folderCopyingTitle(name),
              subtitle: <String>[
                l10n.pasteRoute(transferShortPath(source), transferShortPath(target)),
                l10n.folderTransferItems(total),
              ].join(' · '),
              subtitleTooltip: l10n.pasteRoute(source, target),
              badge: crossVolume
                  ? TransferBadge(label: l10n.pasteCrossVolumeTag, tone: TransferTone.warn)
                  : null,
            ),
            maxWidth: 460,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (crossVolume) ...[
                  TransferNote(
                    text: l10n.folderMoveCrossVolumeNote,
                    tone: TransferTone.warn,
                    icon: Icons.info_outline,
                  ),
                  const SizedBox(height: 14),
                ],
                TransferProgressBar(fraction: fraction),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(l10n.pasteProgressCount(done, total), style: mono11),
                    const SizedBox(width: AppSpace.s10),
                    Expanded(
                      child: Text(
                        '${AppConstants.formatFileSize(bytesDone)} / ${AppConstants.formatFileSize(bytesTotal)}',
                        style: mono11,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.s4),
                Text(
                  value == null || value.name.isEmpty ? '' : l10n.pasteCurrentFile(value.name),
                  style: mono11,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actionsOverride: Row(
              children: [
                const Spacer(),
                AppButton(
                  label: l10n.cancel,
                  variant: AppButtonVariant.secondary,
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

/// `1c` 取消（文件夹移动）: what a cancelled copy left behind.
///
/// Neutral, not red — nothing was lost. The source is whole; the destination
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
  final semantic = context.semantic;
  final textTheme = Theme.of(context).textTheme;
  final pending = outcome.filesTotal - outcome.filesDone;

  return AppDialog.show<void>(
    context,
    titleWidget: TransferDialogHeading(
      icon: Icons.cancel_outlined,
      tone: TransferTone.neutral,
      title: mode == FolderTransferMode.move ? l10n.folderMoveCancelledTitle : l10n.folderCopyCancelledTitle,
      subtitle: l10n.folderTransferStoppedAt(outcome.filesDone, outcome.filesTotal),
      subtitleTooltip: l10n.pasteRoute(source, outcome.targetPath),
    ),
    maxWidth: 460,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Column(
            children: [
              _StatusRow(
                icon: Icons.check_circle,
                color: semantic.success,
                label: l10n.folderMoveStatCopied,
                value: outcome.filesDone,
              ),
              _StatusRow(
                icon: Icons.remove_circle_outline,
                color: colorScheme.outline,
                label: l10n.folderMoveStatPending,
                value: pending,
              ),
              _StatusRow(
                icon: Icons.folder,
                color: semantic.info,
                label: l10n.folderMoveStatSourceKept,
                value: outcome.filesTotal,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.folderMoveCancelledDesc,
          style: textTheme.bodySmall!.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: AppType.proseHeight,
          ),
        ),
      ],
    ),
    actionsOverride: Row(
      children: [
        Flexible(
          child: AppButton(
            label: l10n.showDestinationInSystem,
            icon: Icons.folder_open,
            variant: AppButtonVariant.text,
            onPressed: () => FileUtils.openPath(outcome.targetPath),
          ),
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

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;

  const _StatusRow({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: AppSize.iconMd, color: color),
          const SizedBox(width: AppSpace.s10),
          Expanded(
            child: Text(label, style: textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpace.s10),
          Text(
            '$value',
            style: textTheme.bodySmall!.mono.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
