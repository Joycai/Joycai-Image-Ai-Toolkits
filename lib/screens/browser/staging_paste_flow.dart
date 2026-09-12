import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

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
  /// What a drop onto a folder passes: the drop moves the *selection*, not
  /// the staging area, and routing it through here anyway is what keeps one
  /// conflict pass and one progress surface for both gestures.
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
/// and reports the outcome — as the finished dialog if the progress dialog is
/// still up, or as a toast if the user sent it to the background.
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
    animationStyle: appDialogAnimation(context),
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

// ------------------------------------------------------------ 1b conflicts

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

  // Read once, before the dialog opens. The dialog compares the file about to
  // be written with the one already there — which is the whole basis for
  // choosing between them — and doing that stat per build would hit the disk
  // on every rebuild of the list.
  final existing = <String, FileStat?>{};
  final incoming = <String, FileStat?>{};
  for (final entry in conflicts) {
    existing[entry.sourcePath] = await _statOrNull(entry.targetPath);
    incoming[entry.sourcePath] = await _statOrNull(entry.sourcePath);
  }

  if (!context.mounted) return null;
  return showDialog<Map<String, FileConflictResolution>>(
    context: context,
    animationStyle: appDialogAnimation(context),
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
    final textTheme = Theme.of(context).textTheme;

    // Every row answered, or the checkbox is about to answer the rest.
    final canContinue = _undecided == 0 || (_applyToRest && _leadChoice != null);
    final showApplyRest = _undecided > 0 && _leadChoice != null;

    return AppDialog(
      titleWidget: TransferDialogHeading(
        icon: Icons.file_copy_outlined,
        tone: TransferTone.warn,
        title: l10n.conflictsTitle,
        subtitle: l10n.conflictsSubtitle(
          widget.conflicts.length,
          widget.plan.entries.length,
          transferShortPath(widget.plan.destination),
        ),
        subtitleMono: false,
        subtitleTooltip: widget.plan.destination,
      ),
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.conflictsIntro,
            style: textTheme.bodySmall!.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: AppType.proseHeight,
            ),
          ),
          const SizedBox(height: AppSpace.s10),
          for (final (index, entry) in widget.conflicts.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            _ConflictCard(
              entry: entry,
              existing: widget.existing[entry.sourcePath],
              incoming: widget.incoming[entry.sourcePath],
              choice: _choices[entry.sourcePath],
              onChanged: (choice) => setState(() => _choices[entry.sourcePath] = choice),
            ),
          ],
          if (showApplyRest) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _applyToRest = !_applyToRest),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: _applyToRest,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) => setState(() => _applyToRest = v ?? false),
                      ),
                    ),
                    const SizedBox(width: AppSpace.s10),
                    Expanded(
                      child: Text(
                        l10n.conflictApplyRestCount(_undecided),
                        style: textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      // No Padding around this row: AppDialog pads the footer band itself.
      actionsOverride: Row(
        children: [
          if (_undecided > 0)
            Flexible(
              child: Text(
                l10n.conflictUndecidedCount(_undecided),
                style: textTheme.labelSmall!.mono.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Spacer(),
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: AppSpace.s6),
          AppButton(
            label: l10n.conflictApplyAndContinue,
            onPressed: canContinue ? () => Navigator.pop(context, _result) : null,
          ),
        ],
      ),
    );
  }
}

/// `1b` 冲突卡: the name and why it clashes, the incoming file beside the one
/// already there, and the three answers.
class _ConflictCard extends StatelessWidget {
  final FileTransferEntry entry;
  final FileStat? existing;
  final FileStat? incoming;
  final FileConflictResolution? choice;
  final ValueChanged<FileConflictResolution> onChanged;

  const _ConflictCard({
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
    final textTheme = Theme.of(context).textTheme;

    final Widget outcome;
    switch (choice) {
      case null:
        outcome = TransferBadge(label: l10n.conflictPending, tone: TransferTone.track);
      case FileConflictResolution.overwrite:
        outcome = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: AppSize.iconSm, color: colorScheme.error),
            const SizedBox(width: AppSpace.s4),
            Flexible(
              child: Text(
                l10n.conflictOverwriteWarning,
                style: textTheme.labelSmall!.copyWith(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        );
      case FileConflictResolution.rename:
        // Resolved live, so the card shows the name it will actually land on
        // rather than promising "a different one".
        outcome = Text(
          '→ ${p.basename(FileTransferService.uniqueTargetPath(p.dirname(entry.targetPath), entry.name))}',
          style: textTheme.labelSmall!.mono.copyWith(color: colorScheme.onAccentTint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case FileConflictResolution.skip:
        outcome = const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  style: textTheme.bodySmall!.mono.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _reasonBadge(l10n, entry.conflict),
            ],
          ),
          const SizedBox(height: 8),
          // Which file is bigger and which is newer is the whole basis for
          // choosing between them.
          Row(
            children: [
              Expanded(
                child: _Side(
                  path: entry.sourcePath,
                  caption: l10n.conflictIncoming,
                  meta: '${AppConstants.formatFileSize(entry.size)} · ${_shortDate(incoming?.modified)}',
                  accent: true,
                ),
              ),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: existing == null
                    ? const SizedBox.shrink()
                    : _Side(
                        path: entry.targetPath,
                        caption: l10n.conflictAlreadyThere,
                        meta: '${AppConstants.formatFileSize(existing!.size)} · ${_shortDate(existing!.modified)}',
                        accent: false,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: AppSpace.s6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ChoiceTrack(choice: choice, onChanged: onChanged),
              outcome,
            ],
          ),
        ],
      ),
    );
  }

  /// The four reasons a planned entry can clash, each in its own tone.
  static Widget _reasonBadge(AppLocalizations l10n, FileTransferConflict conflict) => switch (conflict) {
        FileTransferConflict.targetExists =>
          TransferBadge(label: l10n.conflictReasonExists, tone: TransferTone.warn),
        FileTransferConflict.duplicateInBatch =>
          TransferBadge(label: l10n.conflictReasonDuplicate, tone: TransferTone.info),
        FileTransferConflict.sameLocation =>
          TransferBadge(label: l10n.conflictReasonSameLocation, tone: TransferTone.track),
        FileTransferConflict.sourceMissing =>
          TransferBadge(label: l10n.conflictReasonMissing, tone: TransferTone.err),
        FileTransferConflict.none => const SizedBox.shrink(),
      };
}

/// One side of the comparison: a thumbnail, its caption (`Incoming` /
/// `Already there`) and a mono `size · date` line under it.
class _Side extends StatelessWidget {
  final String path;
  final String caption;
  final String meta;

  /// The incoming caption speaks in the deep accent; the existing one in ink2.
  final bool accent;

  const _Side({required this.path, required this.caption, required this.meta, required this.accent});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        TransferThumb(path: path, size: 32),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                style: textTheme.labelSmall!.copyWith(
                  color: accent ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                meta,
                style: textTheme.labelSmall!.mono.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Skip / Overwrite / Keep both on a track: the chosen answer takes the 12%
/// wash under the deep ink — except Overwrite, the only answer that destroys
/// a file, which takes the error container.
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
        color: colorScheme.surfaceContainerHighest,
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

    final Color fill = !selected
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0)
        : (destructive ? colorScheme.errorContainer : colorScheme.accentTint);
    final Color ink = !selected
        ? colorScheme.onSurfaceVariant
        : (destructive ? colorScheme.onErrorContainer : colorScheme.onAccentTint);

    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.hover),
        curve: AppMotion.quick,
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: ink,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------- 1c progress/finish

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
    final textTheme = Theme.of(context).textTheme;
    final isMove = plan.mode == FileTransferMode.move;
    final sourceDir = plan.entries.isEmpty ? '' : p.dirname(plan.entries.first.sourcePath);
    final mono11 = textTheme.labelSmall!.mono.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );

    return PopScope(
      // Escape would leave the transfer running with nothing reporting it.
      // "Run in background" is the deliberate version of that.
      canPop: false,
      child: AppDialog(
        titleWidget: TransferDialogHeading(
          icon: isMove ? Icons.drive_file_move_outlined : Icons.content_copy_outlined,
          tone: TransferTone.accent,
          title: isMove
              ? l10n.pasteMovingCount(plan.entries.length)
              : l10n.pasteCopyingCount(plan.entries.length),
          subtitle: l10n.pasteRoute(transferShortPath(sourceDir), transferShortPath(plan.destination)),
          subtitleTooltip: l10n.pasteRoute(sourceDir, plan.destination),
          badge: plan.crossVolume
              ? TransferBadge(label: l10n.pasteCrossVolumeTag, tone: TransferTone.warn)
              : null,
        ),
        maxWidth: 460,
        content: ValueListenableBuilder<FileTransferProgress?>(
          valueListenable: progress,
          builder: (context, value, _) {
            final done = value?.index ?? 0;
            final total = value?.total ?? plan.entries.length;
            final fraction = total == 0 ? 0.0 : done / total;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (plan.crossVolume) ...[
                  TransferNote(
                    text: l10n.pasteRollbackNote,
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
                        '${AppConstants.formatFileSize(value?.bytesDone ?? 0)} / '
                        '${AppConstants.formatFileSize(plan.totalBytes)}',
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
            );
          },
        ),
        actionsOverride: Row(
          children: [
            Flexible(
              child: AppButton(
                label: l10n.pasteRunInBackground,
                icon: Icons.minimize,
                variant: AppButtonVariant.text,
                onPressed: onBackground,
              ),
            ),
            const Spacer(),
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.secondary,
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// The closing dialog — `1c` 完成 / 取消.
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
  final textTheme = Theme.of(context).textTheme;
  final isMove = plan.mode == FileTransferMode.move;

  final (IconData icon, TransferTone tone) = outcome.cancelled
      ? (Icons.cancel_outlined, TransferTone.neutral)
      : outcome.failed.isEmpty
          ? (Icons.check_circle_outline, TransferTone.ok)
          : (Icons.error_outline, TransferTone.err);

  Future<void> retry() async {
    Navigator.pop(context);
    await runStagingPaste(context, mode: plan.mode, destination: plan.destination);
  }

  return AppDialog.show<void>(
    context,
    titleWidget: TransferDialogHeading(
      icon: icon,
      tone: tone,
      title: outcome.cancelled
          ? l10n.pasteCancelledTitle
          : (isMove ? l10n.pasteMoveDone : l10n.pasteCopyDone),
      subtitle: l10n.pasteElapsed(plan.entries.length, _formatDuration(elapsed)),
    ),
    maxWidth: 460,
    maxHeight: MediaQuery.sizeOf(context).height * 0.75,
    scrollable: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TransferStatTiles(
          transferred: outcome.succeeded.length,
          skipped: outcome.skipped.length,
          failed: outcome.failed.length,
        ),
        if (outcome.failed.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          for (final failure in outcome.failed) _FailureRow(failure: failure),
        ],
        // A copy leaves every mark where it was (see `_runAndReport`), so the
        // sentence about the successes being taken out is only said of a move.
        if (isMove) ...[
          const SizedBox(height: 12),
          Text(
            l10n.pasteKeptInStaging(
              outcome.skipped.length + outcome.failed.length,
              outcome.succeeded.length,
            ),
            style: textTheme.bodySmall!.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: AppType.proseHeight,
            ),
          ),
        ],
      ],
    ),
    actionsOverride: Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: AppSpace.s4,
            runSpacing: AppSpace.s4,
            children: [
              if (outcome.failed.isNotEmpty)
                AppButton(
                  label: l10n.pasteRetry,
                  icon: Icons.refresh,
                  variant: AppButtonVariant.text,
                  onPressed: retry,
                ),
              AppButton(
                label: l10n.pasteExportLog,
                icon: Icons.download_outlined,
                variant: AppButtonVariant.text,
                onPressed: () => _exportLog(context, plan, outcome, elapsed),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.s6),
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

  const _FailureRow({required this.failure});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: AppSize.iconSm, color: colorScheme.error),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(failure.sourcePath),
                  style: textTheme.bodySmall!.mono,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  failure.message,
                  style: textTheme.labelSmall!.copyWith(color: colorScheme.onErrorContainer),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}
