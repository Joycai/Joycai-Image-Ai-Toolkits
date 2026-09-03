import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/browser_file.dart';
import '../../services/file_transfer_service.dart';
import '../../state/app_state.dart';
import '../../state/file_staging_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';
import 'widgets/transfer_dialog_parts.dart';

/// Runs a staging-area paste end to end: plan, resolve conflicts, execute with
/// progress, then reconcile the staging list and the browser listing.
///
/// One entry point for all three ways a paste starts — the panel's footer
/// buttons, a folder's context menu, and a drop onto a folder — because
/// everything after the first gesture is identical and the conflict pass is
/// not something any of them should be reimplementing.
///
/// [destination] overrides the staging area's current destination, which is
/// what the folder menu and the drop target pass: pointing at a folder both
/// names the destination and commits to it in one gesture.
Future<void> runStagingPaste(
  BuildContext context, {
  required FileTransferMode mode,
  String? destination,

  /// Files to transfer instead of the staging list.
  ///
  /// What a drop onto a folder passes: `12d`'s second entry point moves the
  /// *selection*, not the staging area, and routing it through here anyway is
  /// what keeps one conflict pass and one progress surface for both gestures.
  List<BrowserFile>? files,
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

  final sources = files ?? staging.items;
  if (sources.isEmpty) return;

  final plan = await FileTransferService.plan(
    sourcePaths: sources.map((f) => f.path),
    destination: target,
    mode: mode,
  );

  if (!context.mounted) return;
  if (!plan.destinationExists) {
    AppSnackBar.error(context, l10n.pasteDestinationGone);
    return;
  }

  var resolutions = const <String, FileConflictResolution>{};
  if (plan.entries.any(_isNameClash)) {
    final decided = await _askConflicts(context, plan);
    // Dismissed rather than decided — the whole paste is off. Transferring the
    // clean entries anyway would be a partial action nobody asked for.
    if (decided == null) return;
    resolutions = decided;
  }

  final willTransfer = plan.entries.where((e) {
    if (e.conflict == FileTransferConflict.sourceMissing) return false;
    if (e.conflict == FileTransferConflict.sameLocation) return false;
    final r = resolutions[e.sourcePath];
    if (e.hasConflict) return r != null && r != FileConflictResolution.skip;
    return true;
  }).length;
  if (willTransfer == 0) {
    if (context.mounted) AppSnackBar.info(context, l10n.pasteNothingToDo);
    return;
  }

  if (!context.mounted) return;
  await _runAndReport(context, appState, staging, plan, resolutions);
}

/// A clash the user has to answer. A missing source, or a file already sitting
/// in the destination, is not one — nothing is at risk and nothing is decided.
bool _isNameClash(FileTransferEntry e) =>
    e.conflict == FileTransferConflict.targetExists ||
    e.conflict == FileTransferConflict.duplicateInBatch;

/// Executes [plan], keeping the progress dialog and the staging list in step,
/// and reports the outcome — as `12f`'s summary card if the dialog is still
/// up, or as a toast if the user sent it to the background.
Future<void> _runAndReport(
  BuildContext context,
  AppState appState,
  FileStagingState staging,
  FileTransferPlan plan,
  Map<String, FileConflictResolution> resolutions,
) async {
  final progress = ValueNotifier<FileTransferProgress?>(null);
  final started = DateTime.now();
  var cancelled = false;
  var backgrounded = false;

  // Not awaited: the run owns its own lifetime, so "run in background" can
  // dismiss this dialog without taking the transfer down with it.
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ProgressDialog(
      plan: plan,
      progress: progress,
      onCancel: () => cancelled = true,
      onBackground: () {
        backgrounded = true;
        Navigator.pop(dialogContext);
      },
    ),
  ));

  final outcome = await FileTransferService.execute(
    plan,
    resolutions: resolutions,
    onProgress: (value) => progress.value = value,
    isCancelled: () => cancelled,
  );

  final elapsed = DateTime.now().difference(started);

  // A move empties what it moved: those marks point at files that are no
  // longer there. A copy leaves the sources in place, so the marks stay valid
  // and the list is still good for a second destination — which is a real
  // thing to want, and the reason this is not symmetrical.
  if (plan.mode == FileTransferMode.move && outcome.succeeded.isNotEmpty) {
    final moved = <String>[
      for (final entry in plan.entries)
        if (!File(entry.sourcePath).existsSync()) entry.sourcePath,
    ];
    staging.removeAll(moved);
  }

  await staging.revalidate();
  await appState.fileBrowserState.refresh();

  if (context.mounted) {
    if (backgrounded) {
      AppSnackBar.info(context, _summaryLine(AppLocalizations.of(context)!, outcome));
    } else {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // After the pop, never before: the progress dialog is still listening to
  // this until its route is gone, and disposing underneath it makes the
  // route's own teardown remove a listener from a disposed notifier.
  progress.dispose();

  if (!context.mounted || backgrounded) return;
  await _showSummary(context, plan, outcome, elapsed);
}

String _summaryLine(AppLocalizations l10n, FileTransferOutcome outcome) => <String>[
      l10n.pasteSucceededCount(outcome.succeeded.length),
      if (outcome.skipped.isNotEmpty) l10n.pasteSkippedCount(outcome.skipped.length),
      if (outcome.failed.isNotEmpty) l10n.pasteFailedCount(outcome.failed.length),
    ].join(' · ');

// --------------------------------------------------------------- 12e dialog

/// The conflict pass — one decision per clashing file, plus a checkbox that
/// hands the same answer to everything left.
///
/// Returns null when the user backs out, which is different from an empty map:
/// empty means "decided, and every decision was skip".
Future<Map<String, FileConflictResolution>?> _askConflicts(
  BuildContext context,
  FileTransferPlan plan,
) async {
  final conflicts = plan.entries.where(_isNameClash).toList();
  if (conflicts.isEmpty) return const {};

  // Read once, before the dialog opens. `12e` compares the file about to be
  // written with the one already there — which is the whole basis for choosing
  // between them — and doing that stat per build would hit the disk on every
  // rebuild of the list.
  final existing = <String, FileStat?>{};
  final incoming = <String, FileStat?>{};
  for (final entry in conflicts) {
    existing[entry.sourcePath] = await _statOrNull(entry.targetPath);
    incoming[entry.sourcePath] = await _statOrNull(entry.sourcePath);
  }

  if (!context.mounted) return null;
  return showDialog<Map<String, FileConflictResolution>>(
    context: context,
    builder: (_) => _ConflictDialog(
      plan: plan,
      conflicts: conflicts,
      existing: existing,
      incoming: incoming,
    ),
  );
}

class _ConflictDialog extends StatefulWidget {
  final FileTransferPlan plan;
  final List<FileTransferEntry> conflicts;

  /// Stats of the file already at the target, and of the one about to be
  /// written, keyed by source path. Either can be null — the disk is allowed
  /// to have changed since the plan was made.
  final Map<String, FileStat?> existing;
  final Map<String, FileStat?> incoming;

  const _ConflictDialog({
    required this.plan,
    required this.conflicts,
    required this.existing,
    required this.incoming,
  });

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  final Map<String, FileConflictResolution> _choices = {};
  bool _applyToRest = false;

  int get _undecided => widget.conflicts.length - _choices.length;

  /// What the first answered row would hand to the rest.
  FileConflictResolution? get _leadChoice {
    for (final entry in widget.conflicts) {
      final choice = _choices[entry.sourcePath];
      if (choice != null) return choice;
    }
    return null;
  }

  Map<String, FileConflictResolution> get _result {
    final out = Map<String, FileConflictResolution>.from(_choices);
    final lead = _leadChoice;
    if (_applyToRest && lead != null) {
      for (final entry in widget.conflicts) {
        out.putIfAbsent(entry.sourcePath, () => lead);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    // Every row answered, or the checkbox is about to answer the rest.
    final canContinue = _undecided == 0 || (_applyToRest && _leadChoice != null);

    return AppDialog(
      icon: Icons.rule_folder_outlined,
      iconColor: semantic.warning,
      title: l10n.conflictsTitle,
      subtitle: l10n.conflictsSubtitle(
        widget.conflicts.length,
        widget.plan.entries.length,
        _shortFolder(widget.plan.destination),
      ),
      maxWidth: 560,
      maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      scrollable: true,
      contentPadding: EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
            child: Text(
              l10n.conflictsIntro,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
          for (final entry in widget.conflicts)
            _ConflictRow(
              entry: entry,
              existing: widget.existing[entry.sourcePath],
              incoming: widget.incoming[entry.sourcePath],
              choice: _choices[entry.sourcePath],
              onChanged: (choice) => setState(() => _choices[entry.sourcePath] = choice),
            ),
        ],
      ),
      // No Padding around this row: AppDialog pads the footer band itself, and
      // a second one turns the strip above the buttons into dead space.
      actionsOverride: Row(
        children: [
          if (_undecided > 0 && _leadChoice != null) ...[
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _applyToRest,
                onChanged: (v) => setState(() => _applyToRest = v ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                l10n.conflictApplyRestCount(_undecided),
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: l10n.conflictApplyAndContinue,
            onPressed: canContinue ? () => Navigator.pop(context, _result) : null,
          ),
        ],
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  final FileTransferEntry entry;
  final FileStat? existing;
  final FileStat? incoming;
  final FileConflictResolution? choice;
  final ValueChanged<FileConflictResolution> onChanged;

  const _ConflictRow({
    required this.entry,
    required this.existing,
    required this.incoming,
    required this.choice,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(120))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Thumb(path: entry.sourcePath, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.name,
                  style: textTheme.bodySmall?.mono.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              _ChoiceTrack(choice: choice, onChanged: onChanged),
              if (choice == null) ...[
                const SizedBox(width: 8),
                _Pill(
                  label: l10n.conflictPending,
                  color: semantic.onWarningContainer,
                  background: semantic.warningContainer,
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          // Which file is bigger and which is newer is the whole basis for
          // choosing between them, and the flow this replaced made the user
          // guess from a filename.
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Wrap(
              spacing: 18,
              runSpacing: 2,
              children: [
                Text(
                  l10n.conflictWriteInfo(
                    AppConstants.formatFileSize(entry.size),
                    _shortDate(incoming?.modified),
                  ),
                  style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
                ),
                if (existing != null)
                  Text(
                    l10n.conflictExistingInfo(
                      AppConstants.formatFileSize(existing!.size),
                      _shortDate(existing!.modified),
                    ),
                    style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
                  ),
              ],
            ),
          ),
          if (choice == FileConflictResolution.rename)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 5),
              child: Text(
                // Resolved live, so the row shows the name it will actually
                // land on rather than promising "a different one".
                '→ ${p.basename(FileTransferService.uniqueTargetPath(p.dirname(entry.targetPath), entry.name))}',
                style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.onAccentTint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (choice == FileConflictResolution.overwrite)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 5),
              child: Text(
                l10n.conflictOverwriteWarning,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Skip / overwrite / rename as one raised track, the way `12e` draws it.
class _ChoiceTrack extends StatelessWidget {
  final FileConflictResolution? choice;
  final ValueChanged<FileConflictResolution> onChanged;

  const _ChoiceTrack({required this.choice, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, l10n.conflictSkip, FileConflictResolution.skip),
          _segment(context, l10n.conflictOverwrite, FileConflictResolution.overwrite),
          _segment(context, l10n.conflictRename, FileConflictResolution.rename),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, FileConflictResolution value) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = choice == value;
    final destructive = value == FileConflictResolution.overwrite;

    return Material(
      // The chosen answer lifts out of the track rather than tinting: three
      // answers to one question is navigation, and the accent in this dialog
      // belongs to the button that commits.
      color: selected ? colorScheme.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      elevation: selected ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected
                      ? (destructive ? colorScheme.error : colorScheme.onSurface)
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- 12f dialogs

class _ProgressDialog extends StatelessWidget {
  final FileTransferPlan plan;
  final ValueNotifier<FileTransferProgress?> progress;
  final VoidCallback onCancel;
  final VoidCallback onBackground;

  const _ProgressDialog({
    required this.plan,
    required this.progress,
    required this.onCancel,
    required this.onBackground,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isMove = plan.mode == FileTransferMode.move;
    final sourceDir = plan.entries.isEmpty ? '' : p.dirname(plan.entries.first.sourcePath);

    return PopScope(
      // Escape would leave the transfer running with nothing reporting it.
      // "Run in background" is the deliberate version of that.
      canPop: false,
      child: AppDialog(
        icon: isMove ? Icons.drive_file_move_outlined : Icons.file_copy_outlined,
        iconColor: semantic.info,
        title: isMove
            ? l10n.pasteMovingCount(plan.entries.length)
            : l10n.pasteCopyingCount(plan.entries.length),
        subtitle: <String>[
          l10n.pasteRoute(_shortFolder(sourceDir), _shortFolder(plan.destination)),
          if (plan.crossVolume) l10n.pasteCrossVolumeTag,
        ].join(' · '),
        maxWidth: 460,
        content: ValueListenableBuilder<FileTransferProgress?>(
          valueListenable: progress,
          builder: (context, value, _) {
            final done = value?.index ?? 0;
            final total = value?.total ?? plan.entries.length;
            final fraction = total == 0 ? 0.0 : done / total;
            return Column(
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
                          AppConstants.formatFileSize(value?.bytesDone ?? 0),
                          AppConstants.formatFileSize(plan.totalBytes),
                        ),
                        style: textTheme.labelMedium?.mono
                            .copyWith(color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${(fraction * 100).round()}%',
                      style: textTheme.labelMedium?.mono
                          .copyWith(color: colorScheme.onSurfaceVariant),
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
                if (plan.crossVolume) ...[
                  const SizedBox(height: 12),
                  TransferInfoNote(text: l10n.pasteRollbackNote),
                ],
              ],
            );
          },
        ),
        actionsOverride: Row(
          children: [
            AppButton(
              label: l10n.pasteRunInBackground,
              variant: AppButtonVariant.text,
              onPressed: onBackground,
            ),
            const Spacer(),
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.destructiveOutline,
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// The closing card — `12f`'s right half.
///
/// Three counts rather than a sentence: succeeded, skipped and failed answer
/// three different questions, and a toast that runs them together makes the
/// one that matters easiest to miss.
Future<void> _showSummary(
  BuildContext context,
  FileTransferPlan plan,
  FileTransferOutcome outcome,
  Duration elapsed,
) {
  final l10n = AppLocalizations.of(context)!;
  final colorScheme = Theme.of(context).colorScheme;
  final semantic = AppSemanticColors.of(context);
  final textTheme = Theme.of(context).textTheme;
  final isMove = plan.mode == FileTransferMode.move;

  return AppDialog.show<void>(
    context,
    icon: outcome.failed.isEmpty ? Icons.check_circle_outline : Icons.error_outline,
    iconColor: outcome.failed.isEmpty ? semantic.success : colorScheme.error,
    title: outcome.cancelled
        ? l10n.pasteCancelledTitle
        : (isMove ? l10n.pasteMoveDone : l10n.pasteCopyDone),
    subtitle: l10n.pasteElapsed(plan.entries.length, _formatDuration(elapsed)),
    maxWidth: 460,
    maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    scrollable: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TransferStatCell(
                value: outcome.succeeded.length,
                label: l10n.pasteStatSucceeded,
                color: semantic.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TransferStatCell(
                value: outcome.skipped.length,
                label: l10n.pasteStatSkipped,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TransferStatCell(
                value: outcome.failed.length,
                label: l10n.pasteStatFailed,
                color: colorScheme.error,
              ),
            ),
          ],
        ),
        for (final failure in outcome.failed) ...[
          const SizedBox(height: 10),
          _FailureRow(
            failure: failure,
            onRetry: () async {
              Navigator.pop(context);
              await runStagingPaste(
                context,
                mode: plan.mode,
                destination: plan.destination,
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        Text(
          l10n.pasteKeptInStaging(
            outcome.skipped.length + outcome.failed.length,
            outcome.succeeded.length,
          ),
          style: textTheme.labelSmall?.copyWith(color: colorScheme.outline, height: 1.5),
        ),
      ],
    ),
    actionsOverride: Row(
      children: [
        AppButton(
          label: l10n.pasteExportLog,
          variant: AppButtonVariant.text,
          onPressed: () => _exportLog(context, plan, outcome, elapsed),
        ),
        const Spacer(),
        AppButton(
          label: l10n.finish,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}

class _FailureRow extends StatelessWidget {
  final FileTransferFailure failure;
  final VoidCallback onRetry;

  const _FailureRow({required this.failure, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: AppSize.iconSm, color: colorScheme.error),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(failure.sourcePath),
                  style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  failure.message,
                  style: textTheme.labelSmall?.copyWith(color: colorScheme.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 9),
            ),
            child: Text(l10n.pasteRetry, style: textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Writes what happened to a file the user picks.
///
/// A real export rather than a clipboard copy: the thing worth keeping after a
/// failed 200-file move is a list you can read next to the folder, and the
/// dialog it came from is about to close.
Future<void> _exportLog(
  BuildContext context,
  FileTransferPlan plan,
  FileTransferOutcome outcome,
  Duration elapsed,
) async {
  final l10n = AppLocalizations.of(context)!;
  final buffer = StringBuffer()
    ..writeln('destination: ${plan.destination}')
    ..writeln('mode: ${plan.mode.name}')
    ..writeln('elapsed: ${_formatDuration(elapsed)}')
    ..writeln('succeeded: ${outcome.succeeded.length}')
    ..writeln('skipped: ${outcome.skipped.length}')
    ..writeln('failed: ${outcome.failed.length}')
    ..writeln();
  for (final path in outcome.succeeded) {
    buffer.writeln('OK      $path');
  }
  for (final path in outcome.skipped) {
    buffer.writeln('SKIP    $path');
  }
  for (final failure in outcome.failed) {
    buffer.writeln('FAIL    ${failure.sourcePath}  —  ${failure.message}');
  }

  try {
    // `saveFile` writes the bytes itself and hands back where they landed — on
    // macOS that is the only way the sandbox lets the app write outside its own
    // container, so the write is not done separately here.
    final saved = await FilePicker.saveFile(
      fileName: 'transfer-log.txt',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
      mimeType: 'text/plain',
    );
    if (saved == null) return;
    if (context.mounted) {
      AppSnackBar.success(context, l10n.pasteLogSaved(p.basename(saved.toFilePath())));
    }
  } catch (e) {
    if (context.mounted) AppSnackBar.error(context, '$e');
  }
}

// ------------------------------------------------------------------ helpers

class _Thumb extends StatelessWidget {
  final String path;
  final double size;

  const _Thumb({required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = BrowserFile.categoryOf(path);

    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: size,
        height: size,
        color: colorScheme.surfaceContainerHighest,
        child: category == FileCategory.image
            ? Image(
                image: ResizeImage(FileImage(File(path)), width: (size * 2).round()),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    Icon(category.icon, size: 14, color: colorScheme.outline),
              )
            : Icon(category.icon, size: 14, color: category.color.withAlpha(180)),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;

  const _Pill({required this.label, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Last two segments of a path — a dialog subtitle has no room for the rest.
String _shortFolder(String path) {
  final parts = p.split(path).where((s) => s.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return parts.sublist(parts.length - 2).join(' / ');
}

String _shortDate(DateTime? when) {
  if (when == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(when.month)}-${two(when.day)} ${two(when.hour)}:${two(when.minute)}';
}

Future<FileStat?> _statOrNull(String path) async {
  try {
    final stat = await File(path).stat();
    return stat.type == FileSystemEntityType.notFound ? null : stat;
  } on FileSystemException {
    return null;
  }
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
  return '${d.inMinutes}:${two(d.inSeconds % 60)}';
}
