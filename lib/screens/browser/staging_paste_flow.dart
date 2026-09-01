import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/file_transfer_service.dart';
import '../../state/app_state.dart';
import '../../state/file_staging_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';

/// Runs a staging-area paste end to end: plan, resolve conflicts, execute with
/// progress, then reconcile the staging list and the browser listing.
///
/// One entry point for both of the ways a paste starts — the panel's footer
/// buttons and a folder's context menu — because everything after the first
/// click is identical and the conflict pass is not something either caller
/// should be reimplementing.
///
/// [destination] overrides the staging area's current destination, which is
/// what the folder menu passes: right-clicking a folder both names the
/// destination and commits to it in one gesture.
Future<void> runStagingPaste(
  BuildContext context, {
  required FileTransferMode mode,
  String? destination,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final appState = Provider.of<AppState>(context, listen: false);
  final staging = Provider.of<FileStagingState>(context, listen: false);

  if (destination != null) staging.setDestination(destination);
  final target = destination ?? staging.destination;

  if (target == null) {
    AppSnackBar.warning(context, l10n.pasteNoDestination);
    return;
  }
  if (staging.isEmpty) return;

  final plan = await FileTransferService.plan(
    sourcePaths: staging.items.map((f) => f.path),
    destination: target,
    mode: mode,
  );

  if (!context.mounted) return;
  if (!plan.destinationExists) {
    AppSnackBar.error(context, l10n.pasteDestinationGone);
    return;
  }

  var resolutions = const <String, FileConflictResolution>{};
  if (plan.hasConflicts) {
    final decided = await _askConflicts(context, plan);
    // Dismissed rather than decided — the whole paste is off. Resolving
    // nothing and transferring the clean entries anyway would be a partial
    // action the user never asked for.
    if (decided == null) return;
    resolutions = decided;
  }

  // Everything is either skipped or has nowhere to go. Saying so beats a
  // progress dialog that flashes and reports nothing done.
  final willTransfer = plan.entries.where((e) {
    final r = resolutions[e.sourcePath];
    if (e.conflict == FileTransferConflict.sourceMissing) return false;
    if (e.hasConflict) return r != null && r != FileConflictResolution.skip;
    return true;
  }).length;
  if (willTransfer == 0) {
    if (context.mounted) AppSnackBar.info(context, l10n.pasteNothingToDo);
    return;
  }

  if (!context.mounted) return;
  final outcome = await _runWithProgress(context, plan, resolutions);

  // A move empties what it moved: those files are no longer where the marks
  // point. A copy leaves the sources in place, so the marks stay valid and the
  // list is still good for a second destination — which is a real thing to
  // want and the reason this is not symmetrical.
  if (mode == FileTransferMode.move && outcome.succeeded.isNotEmpty) {
    final moved = <String>[];
    for (final entry in plan.entries) {
      if (outcome.skipped.contains(entry.sourcePath)) continue;
      if (outcome.failed.any((f) => f.sourcePath == entry.sourcePath)) continue;
      moved.add(entry.sourcePath);
    }
    staging.removeAll(moved);
  }

  await staging.revalidate();
  await appState.fileBrowserState.refresh();

  if (!context.mounted) return;
  _reportOutcome(context, outcome);
}

/// The conflict pass — one decision per clashing file, plus a way to make the
/// same call for everything left.
///
/// Returns null when the user backs out, which is different from returning an
/// empty map: an empty map means "decided, and every decision was skip".
Future<Map<String, FileConflictResolution>?> _askConflicts(
  BuildContext context,
  FileTransferPlan plan,
) {
  final l10n = AppLocalizations.of(context)!;
  final conflicts = plan.conflicts
      .where((e) => e.conflict != FileTransferConflict.sourceMissing)
      .toList();

  // Only unreachable sources clashed; there is nothing to decide about them.
  if (conflicts.isEmpty) return Future.value(const {});

  final resolutions = <String, FileConflictResolution>{};

  return AppDialog.show<Map<String, FileConflictResolution>>(
    context,
    title: l10n.conflictsTitle,
    subtitle: l10n.stagingItemsCount(conflicts.length),
    icon: Icons.rule_folder_outlined,
    maxWidth: 640,
    maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    scrollable: true,
    content: StatefulBuilder(
      builder: (context, setState) {
        void applyToRest(FileConflictResolution choice) {
          setState(() {
            for (final entry in conflicts) {
              resolutions[entry.sourcePath] = choice;
            }
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  l10n.conflictApplyToRest,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 10),
                for (final choice in FileConflictResolution.values) ...[
                  AppButton(
                    label: _choiceLabel(l10n, choice),
                    variant: AppButtonVariant.text,
                    onPressed: () => applyToRest(choice),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in conflicts)
              _ConflictRow(
                entry: entry,
                choice: resolutions[entry.sourcePath],
                onChanged: (c) => setState(() => resolutions[entry.sourcePath] = c),
              ),
          ],
        );
      },
    ),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context),
      ),
      AppButton(
        label: l10n.confirm,
        onPressed: () => Navigator.pop(context, resolutions),
      ),
    ],
  );
}

String _choiceLabel(AppLocalizations l10n, FileConflictResolution choice) {
  switch (choice) {
    case FileConflictResolution.skip:
      return l10n.conflictSkip;
    case FileConflictResolution.overwrite:
      return l10n.conflictOverwrite;
    case FileConflictResolution.rename:
      return l10n.conflictRename;
  }
}

class _ConflictRow extends StatelessWidget {
  final FileTransferEntry entry;
  final FileConflictResolution? choice;
  final ValueChanged<FileConflictResolution> onChanged;

  const _ConflictRow({
    required this.entry,
    required this.choice,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final reason = switch (entry.conflict) {
      FileTransferConflict.targetExists => l10n.conflictReasonExists,
      FileTransferConflict.duplicateInBatch => l10n.conflictReasonDuplicate,
      FileTransferConflict.sameLocation => l10n.conflictReasonSameLocation,
      FileTransferConflict.sourceMissing => l10n.conflictReasonMissing,
      FileTransferConflict.none => '',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Three plain choices rather than a dropdown: the decision is the
          // point of this dialog, and burying it one click deep per row is
          // what makes a twelve-row conflict list unusable.
          for (final option in FileConflictResolution.values) ...[
            _ChoiceChip(
              label: _choiceLabel(l10n, option),
              selected: choice == option,
              destructive: option == FileConflictResolution.overwrite,
              onTap: () => onChanged(option),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool destructive;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.destructive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Overwrite is the one choice that destroys something, so when it is the
    // active one it says so in the error colour rather than the accent.
    final accent = destructive ? colorScheme.error : colorScheme.primary;

    return Material(
      color: selected ? accent.withValues(alpha: AppAlpha.tint) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: AppSize.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: AppAlpha.ring)
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected
                      ? (destructive ? colorScheme.error : colorScheme.onAccentTint)
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

/// Runs the transfer behind a modal that reports where it has got to and can
/// stop it.
///
/// Modal on purpose: the paste is moving the very files the grid behind it is
/// listing, and letting the user re-sort or re-select mid-run would be showing
/// them a listing that is wrong while it changes.
Future<FileTransferOutcome> _runWithProgress(
  BuildContext context,
  FileTransferPlan plan,
  Map<String, FileConflictResolution> resolutions,
) async {
  final progress = ValueNotifier<FileTransferProgress?>(null);
  var cancelled = false;

  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ProgressDialog(
      plan: plan,
      progress: progress,
      onCancel: () => cancelled = true,
    ),
  );

  final outcome = await FileTransferService.execute(
    plan,
    resolutions: resolutions,
    onProgress: (p) => progress.value = p,
    isCancelled: () => cancelled,
  );

  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await dialog;
  progress.dispose();
  return outcome;
}

class _ProgressDialog extends StatelessWidget {
  final FileTransferPlan plan;
  final ValueNotifier<FileTransferProgress?> progress;
  final VoidCallback onCancel;

  const _ProgressDialog({
    required this.plan,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMove = plan.mode == FileTransferMode.move;

    return PopScope(
      // Escape would leave the transfer running with nothing on screen
      // reporting it. Cancel is the way out.
      canPop: false,
      child: AppDialog(
        icon: isMove ? Icons.drive_file_move_outlined : Icons.file_copy_outlined,
        title: isMove ? l10n.pasteRunningMove : l10n.pasteRunningCopy,
        subtitle: _shortFolder(plan.destination),
        maxWidth: 460,
        content: ValueListenableBuilder<FileTransferProgress?>(
          valueListenable: progress,
          builder: (context, value, _) {
            final done = value?.index ?? 0;
            final total = value?.total ?? plan.entries.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (plan.crossVolume) ...[
                  _CrossVolumeNote(text: l10n.pasteCrossVolumeWarning),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value?.name ?? '',
                        style: textTheme.labelMedium?.mono
                            .copyWith(color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.pasteProgressCount(done, total),
                      style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: total == 0 ? null : done / total,
                    minHeight: 4,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _CrossVolumeNote extends StatelessWidget {
  final String text;

  const _CrossVolumeNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: AppSize.iconSm, color: semantic.onWarningContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: semantic.onWarningContainer, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The closing summary. A toast when it all worked, a dialog when it did not —
/// a failure list has per-file detail the user has to be able to read at their
/// own pace, and a toast takes that away after four seconds.
void _reportOutcome(BuildContext context, FileTransferOutcome outcome) {
  final l10n = AppLocalizations.of(context)!;

  final parts = <String>[
    l10n.pasteSucceededCount(outcome.succeeded.length),
    if (outcome.skipped.isNotEmpty) l10n.pasteSkippedCount(outcome.skipped.length),
    if (outcome.failed.isNotEmpty) l10n.pasteFailedCount(outcome.failed.length),
  ];
  final summary = parts.join(' · ');

  if (outcome.failed.isEmpty) {
    if (outcome.cancelled) {
      AppSnackBar.warning(context, '${l10n.pasteCancelledTitle} · $summary');
    } else {
      AppSnackBar.success(context, summary);
    }
    return;
  }

  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  AppDialog.show<void>(
    context,
    title: outcome.cancelled ? l10n.pasteCancelledTitle : l10n.pasteDoneTitle,
    subtitle: summary,
    icon: Icons.error_outline,
    iconColor: colorScheme.error,
    maxWidth: 560,
    maxHeight: MediaQuery.sizeOf(context).height * 0.6,
    scrollable: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final failure in outcome.failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(failure.sourcePath),
                  style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  failure.message,
                  style: textTheme.labelSmall?.copyWith(color: colorScheme.error),
                ),
              ],
            ),
          ),
      ],
    ),
    actions: [
      AppButton(
        label: l10n.close,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}

/// Last two segments of a path — a dialog subtitle has no room for the rest.
String _shortFolder(String path) {
  final parts = p.split(path).where((s) => s.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return parts.sublist(parts.length - 2).join(' / ');
}
