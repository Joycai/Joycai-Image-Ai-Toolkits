import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/browser_file.dart';
import '../../models/prompt.dart';
import '../../services/ai_rename_agent.dart';
import '../../services/database_service.dart';
import '../../services/file_transfer_service.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/chat_model_selector.dart';

/// Below this the two-column shell stops working and the dialog folds into
/// `13e`: the config column becomes a summary row, and the old and new names
/// stack instead of sitting in two columns.
const double _kNarrowBreakpoint = 700;

/// Which rows the result list is showing.
enum _RowFilter { all, conflicts, skipped }

/// How a row's target name clashes.
enum _RowConflict {
  none,

  /// Another file already carries this name on disk.
  targetExists,

  /// Two rows in this run propose the same name.
  duplicate,
}

/// What the user decided about a clashing row.
enum _ConflictChoice { rename, skip, overwrite }

/// One line of the review list.
///
/// Mutable on purpose: the whole point of the redraw is that a row is a thing
/// the user edits — accepted, skipped, renamed in place — rather than a cell
/// in a take-it-or-leave-it table.
class _RenameRow {
  _RenameRow(this.proposal) : newName = proposal.newName;

  final RenameProposal proposal;

  String newName;
  bool skipped = false;
  bool autoRenamed = false;
  _RowConflict conflict = _RowConflict.none;
  _ConflictChoice? choice;

  String get path => proposal.path;
  String get oldName => proposal.oldName;
  String get directory => p.dirname(proposal.path);

  bool get hasConflict => conflict != _RowConflict.none;

  /// A conflict the user has not answered. These are subtracted from the apply
  /// count one by one — the old dialog disabled the whole button for any
  /// conflict at all, which made one bad name block thirty-five good ones.
  bool get unresolved => hasConflict && choice == null;

  bool get willApply => !skipped && !unresolved && newName.isNotEmpty && newName != oldName;
}

/// AI batch rename — `B4 13a`–`13f`.
///
/// Config on the left, results on the right, each scrolling on its own. The
/// dialog this replaced ran both down one column, so finishing a generation
/// meant scrolling past a config panel that had already done its job to reach
/// the answers.
class AiRenameDialog extends StatefulWidget {
  const AiRenameDialog({super.key});

  @override
  State<AiRenameDialog> createState() => _AiRenameDialogState();
}

class _AiRenameDialogState extends State<AiRenameDialog> {
  final TextEditingController _instructionController = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  final ScrollController _resultScroll = ScrollController();
  final DatabaseService _db = DatabaseService();

  List<SystemPrompt> _templates = [];
  int? _selectedModelDbId;
  SystemPrompt? _selectedTemplate;

  bool _isGenerating = false;
  bool _cancelRequested = false;
  bool _isSubmitting = false;

  int _batchIndex = 0;
  int _batchTotal = 0;

  List<_RenameRow> _rows = [];
  _RowFilter _filter = _RowFilter.all;

  /// Row being renamed in place, by path. One at a time: an editor open on
  /// every row would be a form, and this list is meant to be read.
  String? _editingPath;

  /// The last batch that failed, kept as a banner rather than an error that
  /// wipes the run — `13f`'s whole point is that the rows already produced
  /// survive it.
  String? _failedReason;
  int _failedBatch = 0;
  List<String> _failedPaths = const [];

  List<BrowserFile> get _files =>
      Provider.of<AppState>(context, listen: false).fileBrowserState.selectedFiles.toList();

  @override
  void initState() {
    super.initState();
    _loadLastSettings();
  }

  @override
  void dispose() {
    _instructionController.dispose();
    _editController.dispose();
    _resultScroll.dispose();
    super.dispose();
  }

  Future<void> _loadLastSettings() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final lastModelId = await appState.getSetting('last_ai_rename_model_id');
    final lastTemplateId = await appState.getSetting('last_ai_rename_system_prompt_id');
    final lastInstructions = await appState.getSetting('last_ai_rename_instructions');

    final templates = await _db.getSystemPrompts(type: 'rename');
    SystemPrompt? initial;
    if (lastTemplateId != null) {
      final id = int.tryParse(lastTemplateId);
      initial = templates.cast<SystemPrompt?>().firstWhere((e) => e?.id == id, orElse: () => null);
    }
    initial ??= templates.isNotEmpty ? templates.first : null;

    if (!mounted) return;
    setState(() {
      _templates = templates;
      _selectedTemplate = initial;
      _selectedModelDbId =
          int.tryParse(lastModelId ?? '') ?? int.tryParse(appState.lastSelectedModelId ?? '');
      if (lastInstructions != null) _instructionController.text = lastInstructions;
    });
  }

  // ---------------------------------------------------------------- generate

  Future<void> _generate({List<String>? onlyPaths}) async {
    final l10n = AppLocalizations.of(context)!;
    if (_selectedModelDbId == null || _selectedTemplate == null) {
      AppSnackBar.warning(context, l10n.selectTemplateFirst);
      return;
    }

    final all = _files;
    final targets = onlyPaths == null
        ? all
        : all.where((f) => onlyPaths.contains(f.path)).toList();
    if (targets.isEmpty) return;

    _db.saveSetting('last_ai_rename_model_id', _selectedModelDbId.toString());
    _db.saveSetting('last_ai_rename_system_prompt_id', _selectedTemplate?.id?.toString() ?? '');
    _db.saveSetting('last_ai_rename_instructions', _instructionController.text);

    setState(() {
      _isGenerating = true;
      _cancelRequested = false;
      _failedReason = null;
      _failedPaths = const [];
      _batchIndex = 0;
      _batchTotal = (targets.length / AiRenameAgent.defaultBatchSize).ceil();
      // A retry keeps what the earlier batches produced; a fresh run does not.
      if (onlyPaths == null) _rows = [];
    });

    try {
      final filesData = targets
          .map((f) => {
                'original_name': f.name,
                'path': f.path,
                'category': f.category.name,
              })
          .toList();

      await AiRenameAgent.collectProposals(
        modelIdentifier: _selectedModelDbId,
        filesData: filesData,
        systemPrompt: _selectedTemplate!.content,
        instructions: _instructionController.text.trim(),
        onBatchProgress: (current, total) {
          if (mounted) setState(() => _batchIndex = current);
        },
        // Rows land as each batch comes back, so a 4-batch run is reviewable
        // from the first one rather than after the last.
        onProposals: (collected) {
          if (!mounted) return;
          _mergeProposals(collected);
        },
        onBatchFailed: (batch, total, error, paths) {
          if (!mounted) return;
          setState(() {
            _failedBatch = batch;
            _failedReason = error.toString();
            _failedPaths = paths.where((path) => path.isNotEmpty).toList();
          });
        },
        isCancelled: () => _cancelRequested || !mounted,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _failedBatch = 1;
          _failedReason = e.toString();
          _failedPaths = targets.map((f) => f.path).toList();
        });
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// Folds a batch's output into the rows, keeping any decision the user has
  /// already made about a row that came back again.
  void _mergeProposals(List<RenameProposal> collected) {
    final existing = {for (final row in _rows) row.path: row};
    final merged = <_RenameRow>[];
    for (final proposal in collected) {
      final prior = existing[proposal.path];
      if (prior != null) {
        merged.add(prior);
      } else {
        merged.add(_RenameRow(proposal));
      }
    }
    setState(() => _rows = merged);
    _recomputeConflicts();
  }

  // --------------------------------------------------------------- conflicts

  /// Recomputed from scratch on every edit rather than patched.
  ///
  /// A rename can resolve one clash and create another in the same keystroke,
  /// and an incremental update has to get both halves right; this is O(n) over
  /// a list that is at most a few hundred rows long.
  Future<void> _recomputeConflicts() async {
    final taken = <String, int>{};
    for (final row in _rows) {
      if (row.skipped) continue;
      final key = p.join(row.directory, row.newName).toLowerCase();
      taken[key] = (taken[key] ?? 0) + 1;
    }

    for (final row in _rows) {
      if (row.skipped) {
        row.conflict = _RowConflict.none;
        continue;
      }
      final targetPath = p.join(row.directory, row.newName);
      if ((taken[targetPath.toLowerCase()] ?? 0) > 1) {
        row.conflict = _RowConflict.duplicate;
        continue;
      }
      // A name that only "exists" because it is this row's own file is not a
      // clash — that is the no-op case, filtered out by [_RenameRow.willApply].
      final exists = await File(targetPath).exists();
      row.conflict = (exists && !p.equals(targetPath, row.path))
          ? _RowConflict.targetExists
          : _RowConflict.none;
      if (row.conflict == _RowConflict.none && row.choice != _ConflictChoice.skip) {
        row.choice = null;
      }
    }
    if (mounted) setState(() {});
  }

  void _resolve(_RenameRow row, _ConflictChoice choice) {
    setState(() {
      row.choice = choice;
      switch (choice) {
        case _ConflictChoice.rename:
          final unique = FileTransferService.uniqueTargetPath(row.directory, row.newName);
          row.newName = p.basename(unique);
          row.autoRenamed = true;
          break;
        case _ConflictChoice.skip:
          row.skipped = true;
          break;
        case _ConflictChoice.overwrite:
          break;
      }
    });
    _recomputeConflicts();
  }

  void _jumpToNextConflict() {
    final index = _visibleRows.indexWhere((row) => row.unresolved);
    if (index < 0 || !_resultScroll.hasClients) return;
    _resultScroll.animateTo(
      (index * 52.0).clamp(0.0, _resultScroll.position.maxScrollExtent),
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.enter,
    );
  }

  // ------------------------------------------------------------------- apply

  Future<void> _apply() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context, listen: false);
    final applying = _rows.where((row) => row.willApply).toList();
    if (applying.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      await taskService.addTask(
        applying.map((row) => row.path).toList(),
        _selectedModelDbId,
        {
          // Exactly what was previewed, with the conflict answers folded in —
          // the executor applies these without another model round-trip.
          'proposals': [
            for (final row in applying)
              {
                'path': row.path,
                'old_name': row.oldName,
                'new_name': row.newName,
                'overwrite': row.choice == _ConflictChoice.overwrite,
              }
          ],
        },
        type: TaskType.aiRename,
        useStream: false,
        id: const Uuid().v4(),
      );

      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.info(context, l10n.taskSubmitted);
        appState.fileBrowserState.refresh();
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Failed to start task: $e');
        setState(() => _isSubmitting = false);
      }
    }
  }

  // -------------------------------------------------------------------- view

  List<_RenameRow> get _visibleRows {
    switch (_filter) {
      case _RowFilter.all:
        return _rows;
      case _RowFilter.conflicts:
        return _rows.where((row) => row.hasConflict).toList();
      case _RowFilter.skipped:
        return _rows.where((row) => row.skipped).toList();
    }
  }

  int get _conflictCount => _rows.where((row) => row.hasConflict).length;
  int get _unresolvedCount => _rows.where((row) => row.unresolved).length;
  int get _skippedCount => _rows.where((row) => row.skipped).length;
  int get _applyCount => _rows.where((row) => row.willApply).length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = context.watch<AppState>();
    // Watched separately: AppState stopped forwarding its sub-states, so the
    // count would otherwise freeze at whatever it was when the dialog opened.
    final files = context.watch<FileBrowserState>().selectedFiles;
    final isNarrow = MediaQuery.sizeOf(context).width < _kNarrowBreakpoint;

    final dirCount = files.map((f) => p.dirname(f.path)).toSet().length;
    final hasModels = appState.chatModels.isNotEmpty;

    return AppDialog(
      icon: Icons.auto_fix_high,
      title: l10n.aiBatchRename,
      subtitle: l10n.renameSubtitleFiles(files.length, dirCount),
      maxWidth: isNarrow ? 640 : 920,
      onClose: () => Navigator.pop(context),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: 470,
        child: isNarrow
            ? Column(
                children: [
                  _NarrowConfigSummary(
                    modelId: _selectedModelDbId,
                    template: _selectedTemplate,
                    generating: _isGenerating,
                    onEdit: _showNarrowConfigSheet,
                    onGenerate: hasModels ? () => _generate() : null,
                    onStop: () => setState(() => _cancelRequested = true),
                  ),
                  Expanded(child: _buildResults(l10n, hasModels, isNarrow)),
                ],
              )
            : Row(
                children: [
                  _buildConfigColumn(l10n, hasModels),
                  Expanded(child: _buildResults(l10n, hasModels, isNarrow)),
                ],
              ),
      ),
      actionsOverride: _buildFooter(l10n),
    );
  }

  // ------------------------------------------------------------ config panel

  Widget _buildConfigColumn(AppLocalizations l10n, bool hasModels) {
    final colorScheme = Theme.of(context).colorScheme;
    final fileCount = _files.length;
    final batches = (fileCount / AiRenameAgent.defaultBatchSize).ceil();

    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No section label above this one: [ChatModelSelector] always draws
          // its own, so the heading `13a` puts here is already on the field.
          // One combined picker rather than the frame's separate channel and
          // model boxes: this is the app's shared chat-model control and it
          // already names both, so splitting it here would make this the one
          // screen that picks a model differently.
          ChatModelSelector(
            selectedModelId: _selectedModelDbId,
            onChanged: (v) => setState(() => _selectedModelDbId = v),
          ),
          const SizedBox(height: 14),
          _SectionLabel(l10n.renameSectionTemplate),
          const SizedBox(height: 8),
          Expanded(
            child: _templates.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      l10n.noPromptsSaved,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: colorScheme.outline),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _templates.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) => _TemplateCard(
                      template: _templates[index],
                      selected: _templates[index].id == _selectedTemplate?.id,
                      onTap: () => setState(() => _selectedTemplate = _templates[index]),
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          _SectionLabel(l10n.renameSectionInstructions),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: TextField(
              controller: _instructionController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: l10n.aiRenameInstructionsHint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: _isGenerating
                ? OutlinedButton.icon(
                    onPressed: () => setState(() => _cancelRequested = true),
                    icon: const Icon(Icons.stop_circle_outlined, size: AppSize.iconMd),
                    label: Text(l10n.renameStopGenerating),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: hasModels ? () => _generate() : null,
                    icon: const Icon(Icons.bolt, size: AppSize.iconMd),
                    label: Text(_rows.isEmpty ? l10n.generateSuggestions : l10n.renameRegenerate),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.renameBatchEstimate(fileCount, AiRenameAgent.defaultBatchSize, batches),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.mono
                .copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _showNarrowConfigSheet() async {
    final l10n = AppLocalizations.of(context)!;
    await AppDialog.show<void>(
      context,
      title: l10n.renameEditConfig,
      maxWidth: 460,
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      content: SizedBox(height: 420, child: _buildConfigColumn(l10n, true)),
      actions: [
        AppButton(label: l10n.close, onPressed: () => Navigator.pop(context)),
      ],
    );
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ result panel

  Widget _buildResults(AppLocalizations l10n, bool hasModels, bool isNarrow) {
    if (!hasModels) return _buildNoModels(l10n);

    // The brighter column tone, so the config panel beside it reads as a panel
    // rather than as more of the same surface. `13a` draws the shell near-white
    // with the config column a step down; the app's ramp expresses that
    // relationship the same way round with `surfaceContainerLow` over
    // `surface`.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          _buildResultToolbar(l10n),
          if (_failedReason != null) _buildFailureBanner(l10n),
          Expanded(
            child: _rows.isEmpty
                ? (_isGenerating ? const _SkeletonList() : _buildEmptyState(l10n))
                : _buildRowList(isNarrow),
          ),
        ],
      ),
    );
  }

  Widget _buildResultToolbar(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: _isGenerating
          // The toolbar becomes the progress readout while a run is going: a
          // real position in the run, not a spinner in a placeholder box.
          ? Row(
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 12),
                Text(l10n.renameGenerating, style: textTheme.titleSmall),
                const SizedBox(width: 12),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: _batchTotal == 0 ? null : _batchIndex / _batchTotal,
                        minHeight: 4,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.renameBatchProgress(_batchIndex, _batchTotal, _rows.length, _files.length),
                  style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _cancelRequested = true),
                  style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                  child: Text(l10n.renameStop, style: textTheme.bodySmall),
                ),
              ],
            )
          : Row(
              children: [
                _FilterChip(
                  label: l10n.renameFilterAll,
                  count: _rows.length,
                  selected: _filter == _RowFilter.all,
                  onTap: () => setState(() => _filter = _RowFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l10n.renameFilterConflicts,
                  count: _conflictCount,
                  selected: _filter == _RowFilter.conflicts,
                  onTap: () => setState(() => _filter = _RowFilter.conflicts),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: l10n.renameFilterSkipped,
                  count: _skippedCount,
                  selected: _filter == _RowFilter.skipped,
                  onTap: () => setState(() => _filter = _RowFilter.skipped),
                ),
                const Spacer(),
                if (_unresolvedCount > 0)
                  OutlinedButton.icon(
                    onPressed: _jumpToNextConflict,
                    icon: const Icon(Icons.arrow_downward, size: 14),
                    label: Text(l10n.renameNextConflict, style: textTheme.bodySmall),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error.withValues(alpha: AppAlpha.ring)),
                      minimumSize: const Size(0, AppSize.compact),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildFailureBanner(AppLocalizations l10n) {
    final semantic = AppSemanticColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final missing = _failedPaths.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: semantic.warningContainer,
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: AppSize.iconMd, color: semantic.onWarningContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.renameBatchFailed(_failedBatch, _shortReason(_failedReason!)),
                  style: textTheme.labelMedium?.copyWith(
                    color: semantic.onWarningContainer,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.renameBatchFailedDesc(_rows.length, missing),
                  style: textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _isGenerating ? null : () => _generate(onlyPaths: _failedPaths),
            style: OutlinedButton.styleFrom(
              foregroundColor: semantic.onWarningContainer,
              side: BorderSide(color: semantic.onWarningContainer.withValues(alpha: AppAlpha.ring)),
              minimumSize: const Size(0, AppSize.compact),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(l10n.renameRetryBatch, style: textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fileCount = _files.length;
    final batches = (fileCount / AiRenameAgent.defaultBatchSize).ceil();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: colorScheme.surface, shape: BoxShape.circle),
              child: Icon(Icons.drive_file_rename_outline,
                  size: 26, color: colorScheme.outlineVariant),
            ),
            const SizedBox(height: 12),
            Text(l10n.renameEmptyTitle, style: textTheme.titleSmall),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                l10n.renameEmptyDesc(fileCount, batches, AiRenameAgent.defaultBatchSize),
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.outline, height: 1.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoModels(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology_alt_outlined, size: 40, color: colorScheme.outlineVariant),
            const SizedBox(height: 14),
            Text(l10n.renameNoModelsTitle, style: textTheme.titleSmall),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                l10n.renameNoModelsDesc,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.outline, height: 1.7),
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              label: l10n.renameGoToSettings,
              icon: Icons.tune,
              onPressed: () {
                Navigator.pop(context);
                Provider.of<AppState>(context, listen: false).navigateToScreen(6);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowList(bool isNarrow) {
    final rows = _visibleRows;
    return ListView.builder(
      controller: _resultScroll,
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return _ResultRow(
          row: row,
          narrow: isNarrow,
          editing: _editingPath == row.path,
          editController: _editController,
          onAccept: () => setState(() {
            row.skipped = false;
            if (row.choice == _ConflictChoice.skip) row.choice = null;
            _recomputeConflicts();
          }),
          onSkip: () => setState(() {
            row.skipped = true;
            _recomputeConflicts();
          }),
          onEdit: () => setState(() {
            _editingPath = row.path;
            _editController.text = row.newName;
          }),
          onCommitEdit: (value) {
            setState(() {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) {
                row.newName = trimmed;
                row.autoRenamed = false;
                row.choice = null;
              }
              _editingPath = null;
            });
            _recomputeConflicts();
          },
          onResolve: (choice) => _resolve(row, choice),
        );
      },
    );
  }

  // ------------------------------------------------------------------ footer

  Widget _buildFooter(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isNarrow = MediaQuery.sizeOf(context).width < _kNarrowBreakpoint;

    final summary = <String>[
      if (_isGenerating)
        l10n.renameProducedHint(_rows.length)
      else
        l10n.renameSuggestionsCount(_rows.length),
      if (!_isGenerating && _skippedCount > 0) l10n.renameSkippedCount(_skippedCount),
      if (!_isGenerating && _unresolvedCount > 0) l10n.renameConflictsPending(_unresolvedCount),
    ].join(' · ');

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              summary,
              style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.outline),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 14),
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          AppButton(
            // Counts only the rows that will actually move. An unresolved
            // conflict subtracts itself and nothing else — the old dialog
            // disabled the button outright, so one bad name held the other
            // thirty-five hostage.
            label: isNarrow ? l10n.renameApplyShort(_applyCount) : l10n.renameApplyCount(_applyCount),
            loading: _isSubmitting,
            onPressed: (_applyCount == 0 || _isGenerating || _isSubmitting) ? null : _apply,
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

String _shortReason(String raw) {
  final oneLine = raw.replaceAll('\n', ' ').trim();
  return oneLine.length <= 80 ? oneLine : '${oneLine.substring(0, 80)}…';
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final SystemPrompt template;
  final bool selected;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? colorScheme.accentTint : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? colorScheme.primary : colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.title,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? colorScheme.onAccentTint : colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check, size: 14, color: colorScheme.onAccentTint),
                ],
              ),
              const SizedBox(height: 3),
              // The frame shows an example output filename here. Templates
              // carry no example field, so this is the rule itself, in mono —
              // the nearest true thing the data actually holds.
              Text(
                template.content.replaceAll('\n', ' '),
                style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = selected ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant;

    return Material(
      color: selected ? colorScheme.accentTint : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? Colors.transparent : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text('$count', style: textTheme.labelSmall?.mono.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows still on their way. Grey blocks in the shape of the real thing, not a
/// spinner in a box — the list is already the right length in the user's head
/// by the time the first batch lands.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(120))),
        ),
        child: Row(
          children: [
            _bar(colorScheme, 36, 36, AppRadius.xs),
            const SizedBox(width: 12),
            Expanded(child: _bar(colorScheme, double.infinity, 10, AppRadius.xs)),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: _bar(colorScheme, double.infinity, 10, AppRadius.xs)),
          ],
        ),
      ),
    );
  }

  Widget _bar(ColorScheme colorScheme, double width, double height, double radius) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(140),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _ResultRow extends StatelessWidget {
  final _RenameRow row;
  final bool narrow;
  final bool editing;
  final TextEditingController editController;
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  final VoidCallback onEdit;
  final ValueChanged<String> onCommitEdit;
  final ValueChanged<_ConflictChoice> onResolve;

  const _ResultRow({
    required this.row,
    required this.narrow,
    required this.editing,
    required this.editController,
    required this.onAccept,
    required this.onSkip,
    required this.onEdit,
    required this.onCommitEdit,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final oldName = Text(
      row.oldName,
      style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.outline),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final newName = editing
        ? SizedBox(
            height: 28,
            child: TextField(
              controller: editController,
              autofocus: true,
              style: textTheme.labelMedium?.mono,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
              ),
              onSubmitted: onCommitEdit,
              onTapOutside: (_) => onCommitEdit(editController.text),
            ),
          )
        : Row(
            children: [
              Flexible(
                child: Text(
                  row.newName,
                  style: textTheme.labelMedium?.mono.copyWith(
                    color: row.unresolved ? colorScheme.error : colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (row.unresolved) ...[
                const SizedBox(width: 7),
                _Badge(label: l10n.renameDuplicateBadge, color: colorScheme.error),
              ] else if (row.autoRenamed) ...[
                const SizedBox(width: 7),
                _Badge(label: l10n.renameRenamedBadge, color: colorScheme.onSurfaceVariant),
              ],
            ],
          );

    return Opacity(
      // A skipped row stays legible but stops competing: it is still there to
      // be undone, and dropping it out of the list would lose that.
      opacity: row.skipped ? 0.5 : 1,
      child: Container(
        height: narrow ? 64 : 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(120))),
        ),
        child: Row(
          children: [
            _Thumb(path: row.path),
            const SizedBox(width: 12),
            if (narrow)
              // Two lines instead of two columns: at 640 the columns are too
              // narrow for either name to survive its own ellipsis.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    oldName,
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.subdirectory_arrow_right, size: 12, color: colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(child: newName),
                    ]),
                  ],
                ),
              )
            else ...[
              // 1 : 1.15 — the new name is the one being judged, so it gets the
              // extra room, and the two columns stay aligned down the list.
              Expanded(flex: 100, child: oldName),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 13, color: colorScheme.outlineVariant),
              const SizedBox(width: 8),
              Expanded(flex: 115, child: newName),
            ],
            if (row.skipped) ...[
              const SizedBox(width: 8),
              _Badge(label: l10n.renameSkippedBadge, color: colorScheme.onSurfaceVariant),
            ] else if (row.unresolved) ...[
              const SizedBox(width: 8),
              _ConflictSegments(onResolve: onResolve),
            ],
            const SizedBox(width: 8),
            _RowAction(
              icon: Icons.check,
              tooltip: row.skipped ? l10n.renameActionUndo : l10n.renameActionAccept,
              active: !row.skipped,
              onTap: onAccept,
            ),
            _RowAction(
              icon: Icons.block,
              tooltip: l10n.renameActionSkip,
              active: false,
              onTap: onSkip,
            ),
            _RowAction(
              icon: Icons.edit_outlined,
              tooltip: l10n.renameActionEdit,
              active: editing,
              onTap: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String path;

  const _Thumb({required this.path});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = BrowserFile.categoryOf(path);

    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 36,
        height: 36,
        color: colorScheme.surfaceContainerHighest,
        child: category == FileCategory.image
            ? Image(
                image: ResizeImage(FileImage(File(path)), width: 72),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    Icon(category.icon, size: 16, color: colorScheme.outline),
              )
            : Icon(category.icon, size: 16, color: category.color.withAlpha(180)),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// The three answers to a clash, inline on the row that has it.
///
/// Inline rather than in a dialog of its own: `13d` resolves conflicts without
/// leaving the list, so the user can see what else is affected while deciding.
class _ConflictSegments extends StatelessWidget {
  final ValueChanged<_ConflictChoice> onResolve;

  const _ConflictSegments({required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, l10n.renameConflictAutoRename, _ConflictChoice.rename, false),
          _segment(context, l10n.renameActionSkip, _ConflictChoice.skip, false),
          // Overwrite is the only one that destroys a file, so it is the only
          // one that carries the error colour.
          _segment(context, l10n.conflictOverwrite, _ConflictChoice.overwrite, true),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, _ConflictChoice choice, bool destructive) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onResolve(choice),
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: destructive ? colorScheme.error : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? colorScheme.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(
              icon,
              size: 14,
              color: active ? colorScheme.onAccentTint : colorScheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

/// `13e`'s collapsed config: the four controls become one summary row with a
/// way back to them, so the narrow dialog spends its width on the results.
class _NarrowConfigSummary extends StatelessWidget {
  final int? modelId;
  final SystemPrompt? template;
  final bool generating;
  final VoidCallback onEdit;
  final VoidCallback? onGenerate;
  final VoidCallback onStop;

  const _NarrowConfigSummary({
    required this.modelId,
    required this.template,
    required this.generating,
    required this.onEdit,
    required this.onGenerate,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appState = context.watch<AppState>();
    final model = appState.chatModels.where((m) => m.id == modelId).firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model?.modelName ?? l10n.noModelsConfigured,
                  style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${l10n.renameTemplateLabel} · ${template?.title ?? l10n.noTemplateSelected}',
                  style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppButton(
            label: l10n.renameEditConfig,
            variant: AppButtonVariant.text,
            onPressed: onEdit,
          ),
          const SizedBox(width: 6),
          generating
              ? AppButton(
                  label: l10n.renameStop,
                  variant: AppButtonVariant.destructiveText,
                  onPressed: onStop,
                )
              : AppButton(
                  label: l10n.generateSuggestions,
                  icon: Icons.bolt,
                  onPressed: onGenerate,
                ),
        ],
      ),
    );
  }
}
