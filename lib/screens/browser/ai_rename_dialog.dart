import 'dart:io';
import 'dart:math' as math;

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
import '../../widgets/app_dropdown.dart';
import '../../widgets/app_field_size.dart';
import '../../widgets/app_segmented_control.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/chat_model_selector.dart';
import '../../widgets/glass/glass_controls.dart';
import 'widgets/transfer_dialog_parts.dart';

/// Below this window width the two-column shell stops working and the dialog
/// folds: the config column becomes a summary row with a sheet behind it, and
/// the old and new names stack instead of sitting in two columns. A layout
/// form switch, not a text fit — text fits are measured below.
const double _kNarrowBreakpoint = 700;

/// The config column's width (`1e` 左列 300).
const double _kConfigWidth = 300;

/// The old name's column on a wide row (`1e` 150 宽).
const double _kOldNameWidth = 150;

/// The narrowest the new name may get before the row actions fold to glyphs.
const double _kMinNewNameWidth = 120;

/// The narrowest the footer summary may get before Apply takes its short label.
const double _kMinFooterSummaryWidth = 160;

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
/// Mutable on purpose: the whole point of the review list is that a row is a
/// thing the user edits — skipped, renamed in place, a clash answered — rather
/// than a cell in a take-it-or-leave-it table.
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
  /// count one by one — one bad name must not block thirty-five good ones.
  bool get unresolved => hasConflict && choice == null;

  bool get willApply => !skipped && !unresolved && newName.isNotEmpty && newName != oldName;
}

/// AI batch rename — `B1b 1e` / `1f`.
///
/// The one large dialog on this screen: 920 wide, config on the left and the
/// review list on the right, each scrolling on its own. Suggestions land a
/// batch at a time and are reviewable as they arrive; they are applied only
/// once generation has finished.
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

  /// The last batch that failed, kept as a card rather than an error that
  /// wipes the run — the rows already produced survive it.
  String? _failedReason;
  int _failedBatch = 0;
  List<String> _failedPaths = const [];

  /// Rebuilds the narrow-window config sheet while it is open. The sheet is
  /// its own route, so this state's `setState` does not reach it.
  StateSetter? _sheetSetState;

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

  /// `setState`, plus the config sheet when one is open.
  void _update(VoidCallback fn) {
    setState(fn);
    _sheetSetState?.call(() {});
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
    _update(() {
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

    _update(() {
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
          if (mounted) _update(() => _batchIndex = current);
        },
        // Rows land as each batch comes back, so a 4-batch run is reviewable
        // from the first one rather than after the last.
        onProposals: (collected) {
          if (!mounted) return;
          _mergeProposals(collected);
        },
        onBatchFailed: (batch, total, error, paths) {
          if (!mounted) return;
          _update(() {
            _failedBatch = batch;
            _failedReason = error.toString();
            _failedPaths = paths.where((path) => path.isNotEmpty).toList();
          });
        },
        isCancelled: () => _cancelRequested || !mounted,
      );
    } catch (e) {
      if (mounted) {
        _update(() {
          _failedBatch = 1;
          _failedReason = e.toString();
          _failedPaths = targets.map((f) => f.path).toList();
        });
      }
    } finally {
      if (mounted) _update(() => _isGenerating = false);
    }
  }

  void _stop() => _update(() => _cancelRequested = true);

  /// Folds a batch's output into the rows, keeping any decision the user has
  /// already made about a row that came back again.
  void _mergeProposals(List<RenameProposal> collected) {
    final existing = {for (final row in _rows) row.path: row};
    final merged = <_RenameRow>[
      for (final proposal in collected) existing[proposal.path] ?? _RenameRow(proposal),
    ];
    _update(() => _rows = merged);
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
    if (mounted) _update(() {});
  }

  void _resolve(_RenameRow row, _ConflictChoice choice) {
    _update(() {
      row.choice = choice;
      switch (choice) {
        case _ConflictChoice.rename:
          final unique = FileTransferService.uniqueTargetPath(row.directory, row.newName);
          row.newName = p.basename(unique);
          row.autoRenamed = true;
        case _ConflictChoice.skip:
          row.skipped = true;
        case _ConflictChoice.overwrite:
          break;
      }
    });
    _recomputeConflicts();
  }

  double _rowHeight(bool narrow) => narrow ? 64 : 52;

  void _jumpToNextConflict() {
    final index = _visibleRows.indexWhere((row) => row.unresolved);
    if (index < 0 || !_resultScroll.hasClients) return;
    final narrow = MediaQuery.sizeOf(context).width < _kNarrowBreakpoint;
    _resultScroll.animateTo(
      (index * _rowHeight(narrow)).clamp(0.0, _resultScroll.position.maxScrollExtent),
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.move,
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
    final screen = MediaQuery.sizeOf(context);
    final isNarrow = screen.width < _kNarrowBreakpoint;

    final dirCount = files.map((f) => p.dirname(f.path)).toSet().length;
    final hasModels = appState.chatModels.isNotEmpty;
    // What the window leaves once the heading, footer and dialog insets are
    // taken, up to the height the review list is drawn at.
    final bodyHeight = math.max(240.0, math.min(520.0, screen.height - 220));

    return AppDialog(
      titleWidget: TransferDialogHeading(
        icon: Icons.auto_awesome,
        tone: TransferTone.accent,
        title: l10n.aiBatchRename,
        subtitle: l10n.renameSubtitleFiles(files.length, dirCount),
        trailing: TransferDialogCloseButton(onPressed: () => Navigator.pop(context)),
      ),
      maxWidth: isNarrow ? 640 : 920,
      contentPadding: EdgeInsets.zero,
      dividedHeading: true,
      content: SizedBox(
        height: bodyHeight,
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NarrowConfigSummary(
                    modelId: _selectedModelDbId,
                    template: _selectedTemplate,
                    generating: _isGenerating,
                    onEdit: _showNarrowConfigSheet,
                    onGenerate: hasModels ? () => _generate() : null,
                    onStop: _stop,
                  ),
                  Expanded(child: _buildResults(l10n, hasModels, isNarrow)),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildConfigColumn(l10n, hasModels, width: _kConfigWidth),
                  Expanded(child: _buildResults(l10n, hasModels, isNarrow)),
                ],
              ),
      ),
      actionsOverride: _buildFooter(l10n, isNarrow),
    );
  }

  // ------------------------------------------------------------ config panel

  /// `1e` 左列: model, naming template, extra instructions, the batch card,
  /// and Generate / Stop pinned to the bottom of whatever height it is given.
  Widget _buildConfigColumn(AppLocalizations l10n, bool hasModels, {double? width}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fileCount = _files.length;
    final batches = (fileCount / AiRenameAgent.defaultBatchSize).ceil();
    final mono11 = textTheme.labelSmall!.mono.copyWith(fontWeight: FontWeight.w400);

    final top = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Caption(l10n.renameSectionModel),
        const SizedBox(height: AppSpace.s6),
        // The app's shared chat-model control: it already names channel and
        // model, and this should not be the one screen that picks differently.
        ChatModelSelector(
          selectedModelId: _selectedModelDbId,
          onChanged: (v) => _update(() => _selectedModelDbId = v),
          size: AppFieldSize.regular,
        ),
        const SizedBox(height: 12),
        _Caption(l10n.renameSectionTemplate),
        const SizedBox(height: AppSpace.s6),
        AppDropdown<int>(
          value: _selectedTemplate?.id,
          items: [
            for (final template in _templates)
              if (template.id != null)
                AppDropdownItem<int>(
                  value: template.id!,
                  label: template.title,
                  description: _oneLine(template.content),
                ),
          ],
          onChanged: _templates.isEmpty
              ? null
              : (id) => _update(() {
                    for (final template in _templates) {
                      if (template.id == id) _selectedTemplate = template;
                    }
                  }),
          hint: _templates.isEmpty ? l10n.noPromptsSaved : l10n.noTemplateSelected,
          size: AppFieldSize.regular,
          enabled: _templates.isNotEmpty,
        ),
        const SizedBox(height: 12),
        _Caption(l10n.renameSectionInstructions),
        const SizedBox(height: AppSpace.s6),
        SizedBox(
          height: 88,
          child: TextField(
            controller: _instructionController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: textTheme.bodySmall,
            decoration: InputDecoration(
              hintText: l10n.aiRenameInstructionsHint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(AppSpace.s10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.renameBatchEstimate(fileCount, AiRenameAgent.defaultBatchSize, batches),
                style: mono11.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              if (_isGenerating) ...[
                const SizedBox(height: AppSpace.s4),
                Text(
                  l10n.renameBatchProgress(_batchIndex, _batchTotal, _rows.length, fileCount),
                  style: mono11.copyWith(color: colorScheme.onAccentTint, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final bottom = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        _isGenerating
            ? AppButton(
                label: l10n.renameStopGenerating,
                icon: Icons.stop_circle_outlined,
                variant: AppButtonVariant.destructiveOutline,
                size: AppButtonSize.large,
                fullWidth: true,
                onPressed: _stop,
              )
            : AppButton(
                label: _rows.isEmpty ? l10n.generateSuggestions : l10n.renameRegenerate,
                icon: Icons.auto_awesome,
                size: AppButtonSize.large,
                fullWidth: true,
                onPressed: hasModels ? () => _generate() : null,
              ),
        if (_isGenerating) ...[
          const SizedBox(height: AppSpace.s6),
          Text(
            l10n.renameProducedHint(_rows.length),
            textAlign: TextAlign.center,
            style: textTheme.labelSmall!.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: width == null ? null : Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        // Top group up, the button down, and a scroll only when the height
        // runs out — no Spacer, so nothing here needs intrinsic sizing.
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 28)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [top, bottom],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showNarrowConfigSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final hasModels = context.read<AppState>().chatModels.isNotEmpty;
    await AppDialog.show<void>(
      context,
      title: l10n.renameEditConfig,
      maxWidth: 460,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: 480,
        child: StatefulBuilder(
          builder: (sheetContext, setSheet) {
            _sheetSetState = setSheet;
            return _buildConfigColumn(l10n, hasModels);
          },
        ),
      ),
      actions: [
        AppButton(label: l10n.close, onPressed: () => Navigator.pop(context)),
      ],
    );
    _sheetSetState = null;
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ result panel

  Widget _buildResults(AppLocalizations l10n, bool hasModels, bool isNarrow) {
    if (!hasModels) return _buildNoModels(l10n);

    final showEmpty = _rows.isEmpty && !_isGenerating && _failedReason == null;
    final showFilters = _rows.isNotEmpty || _isGenerating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showFilters) _buildFilterRow(l10n),
        if (_failedReason != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, AppSpace.s10, 14, AppSpace.s4),
            child: _buildFailureCard(l10n),
          ),
        Expanded(child: showEmpty ? _buildEmptyState(l10n, hasModels) : _buildRowList(isNarrow)),
      ],
    );
  }

  /// `1e` 过滤行 48: All / Conflicts / Skipped with counts, and Next conflict.
  Widget _buildFilterRow(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: AppSegmentedControl<_RowFilter>(
                  compact: true,
                  value: _filter,
                  onChanged: (value) => setState(() => _filter = value),
                  segments: [
                    AppSegment(value: _RowFilter.all, label: '${l10n.renameFilterAll} ${_rows.length}'),
                    AppSegment(
                      value: _RowFilter.conflicts,
                      label: '${l10n.renameFilterConflicts} $_conflictCount',
                    ),
                    AppSegment(
                      value: _RowFilter.skipped,
                      label: '${l10n.renameFilterSkipped} $_skippedCount',
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_unresolvedCount > 0) ...[
            const SizedBox(width: 8),
            AppButton(
              label: l10n.renameNextConflict,
              icon: Icons.keyboard_arrow_down,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.compact,
              onPressed: _jumpToNextConflict,
            ),
          ],
        ],
      ),
    );
  }

  /// `1f` 批次失败卡: the batch that gave up, what the rest kept, and a retry
  /// over only the files that batch covered.
  Widget _buildFailureCard(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reason = _failedReason!;

    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        border: Border.all(color: colorScheme.error.withValues(alpha: AppAlpha.edge)),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: AppSize.iconMd, color: colorScheme.error),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.renameBatchFailedTitle(_failedBatch),
                  style: textTheme.titleSmall!.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // The raw reason in mono, shortened to a line or two; the
                // whole thing is a hover away.
                Tooltip(
                  message: reason,
                  child: Text(
                    _shortReason(reason),
                    style: textTheme.labelSmall!.mono.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: AppSpace.s4),
                Text(
                  l10n.renameBatchFailedDesc(_rows.length, _failedPaths.length),
                  style: textTheme.bodySmall!.copyWith(color: colorScheme.onErrorContainer),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          AppButton(
            label: l10n.renameRetryBatch,
            icon: Icons.refresh,
            variant: AppButtonVariant.destructive,
            size: AppButtonSize.compact,
            onPressed: _isGenerating ? null : () => _generate(onlyPaths: _failedPaths),
          ),
        ],
      ),
    );
  }

  /// `1f` 空态.
  Widget _buildEmptyState(AppLocalizations l10n, bool hasModels) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fileCount = _files.length;
    final batches = (fileCount / AiRenameAgent.defaultBatchSize).ceil();

    return _CenteredScroll(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 28, color: colorScheme.outline),
            const SizedBox(height: AppSpace.s10),
            Text(l10n.renameEmptyTitle, style: textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.s6),
            Text(
              l10n.renameEmptyDesc(fileCount, batches, AiRenameAgent.defaultBatchSize),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall!.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: AppType.proseHeight,
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            AppButton(
              label: l10n.generateSuggestions,
              icon: Icons.auto_awesome,
              onPressed: hasModels ? () => _generate() : null,
            ),
          ],
        ),
      ),
    );
  }

  /// `1f` 无模型卡.
  Widget _buildNoModels(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return _CenteredScroll(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.s16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: AppSize.iconLg, color: context.semantic.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.renameNoModelsTitle,
                      style: textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.renameNoModelsDesc,
                style: textTheme.bodySmall!.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: l10n.renameGoToSettings,
                  icon: Icons.tune,
                  onPressed: () {
                    Navigator.pop(context);
                    Provider.of<AppState>(context, listen: false).navigateToScreen(6);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRowList(bool isNarrow) {
    final l10n = AppLocalizations.of(context)!;
    final rows = _visibleRows;
    final trailing = _isGenerating ? 1 : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final iconOnly = _actionsMustFold(context, l10n, constraints.maxWidth, isNarrow);
        return ListView.builder(
          controller: _resultScroll,
          padding: EdgeInsets.zero,
          itemExtent: _rowHeight(isNarrow),
          itemCount: rows.length + trailing,
          itemBuilder: (context, index) {
            if (index >= rows.length) return _GeneratingRow(label: l10n.renameGenerating);
            final row = rows[index];
            return _ResultRow(
              row: row,
              narrow: isNarrow,
              iconOnly: iconOnly,
              editing: _editingPath == row.path,
              editController: _editController,
              onUndoSkip: () {
                _update(() {
                  row.skipped = false;
                  if (row.choice == _ConflictChoice.skip) row.choice = null;
                });
                _recomputeConflicts();
              },
              onSkip: () {
                _update(() => row.skipped = true);
                _recomputeConflicts();
              },
              onEdit: () => setState(() {
                _editingPath = row.path;
                _editController.text = row.newName;
              }),
              onCommitEdit: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty && !AiRenameAgent.isSafeFileName(trimmed)) {
                  AppSnackBar.warning(
                    context,
                    l10n.folderNameIllegalChars(r'/ \\ ..'),
                  );
                  return;
                }
                _update(() {
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
      },
    );
  }

  /// Whether the row actions have to drop their labels, measured against the
  /// widest action set any row can carry and the badge beside it.
  bool _actionsMustFold(BuildContext context, AppLocalizations l10n, double width, bool narrow) {
    final textTheme = Theme.of(context).textTheme;
    double action(String label) => measureGlassText(context, label, textTheme.labelMedium!) + _RowAction.chrome;
    double badge(String label) => measureGlassText(context, label, textTheme.labelSmall!) + 16;

    final actions = [
      action(l10n.renameConflictAutoRename) + action(l10n.conflictOverwrite) + AppSize.compact,
      action(l10n.renameActionEdit) + action(l10n.renameActionSkip),
      action(l10n.renameActionUndo),
    ].reduce(math.max);
    final badges = [
      badge(l10n.renameDuplicateBadge),
      badge(l10n.renameSkippedBadge),
      badge(l10n.renameRenamedBadge),
      badge(l10n.conflictOverwrite),
    ].reduce(math.max);

    final fixed = 28 + 32 + AppSpace.s10 + (narrow ? 0 : _kOldNameWidth + 8 + AppSize.iconSm + 8) + 8 + badges + 8 + actions;
    return width - fixed < _kMinNewNameWidth;
  }

  // ------------------------------------------------------------------ footer

  Widget _buildFooter(AppLocalizations l10n, bool isNarrow) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mono11 = textTheme.labelSmall!.mono.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );

    // The produced-so-far hint lives under Stop in the config column; with
    // that column folded away, the footer carries it.
    final lead = <String>[
      if (_isGenerating && isNarrow)
        l10n.renameProducedHint(_rows.length)
      else
        l10n.renameSuggestionsCount(_rows.length),
      if (_skippedCount > 0) l10n.renameSkippedCount(_skippedCount),
    ].join(' · ');
    final unresolved = _unresolvedCount > 0 ? l10n.renameConflictsPending(_unresolvedCount) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Buttons draw their labels at 13/600 inside 14px of padding a side
        // (text buttons 10): measured, so the short label is chosen only when
        // the long one would squeeze the summary out.
        final buttonText = textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600);
        final cancelWidth = measureGlassText(context, l10n.cancel, buttonText) + 20;
        final applyWidth = measureGlassText(context, l10n.renameApplyCount(_applyCount), buttonText) + 28;
        final useShort =
            constraints.maxWidth - cancelWidth - applyWidth - AppSpace.s6 - 12 < _kMinFooterSummaryWidth;

        return Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: lead),
                    if (unresolved != null) ...[
                      const TextSpan(text: ' · '),
                      TextSpan(text: unresolved, style: TextStyle(color: colorScheme.onErrorContainer)),
                    ],
                  ],
                ),
                style: mono11,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: AppSpace.s6),
            AppButton(
              // Counts only the rows that will actually move. An unresolved
              // conflict subtracts itself and nothing else.
              label: useShort ? l10n.renameApplyShort(_applyCount) : l10n.renameApplyCount(_applyCount),
              loading: _isSubmitting,
              onPressed: (_applyCount == 0 || _isGenerating || _isSubmitting) ? null : _apply,
            ),
          ],
        );
      },
    );
  }
}

String _shortReason(String raw) {
  final oneLine = raw.replaceAll('\n', ' ').trim();
  return oneLine.length <= 80 ? oneLine : '${oneLine.substring(0, 80)}…';
}

/// A template's rule on one line, for the dropdown's second line.
String _oneLine(String content) {
  final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 60 ? flat : '${flat.substring(0, 60)}…';
}

/// The 11/500 tracked caption in the deep accent that heads a config group.
class _Caption extends StatelessWidget {
  final String text;

  const _Caption(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: Theme.of(context).colorScheme.onAccentTint,
            letterSpacing: AppType.trackedLabelSpacing,
          ),
    );
  }
}

/// Centres [child] in the space given, scrolling when the space is shorter.
class _CenteredScroll extends StatelessWidget {
  final Widget child;

  const _CenteredScroll({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(padding: const EdgeInsets.all(AppSpace.s22), child: child),
          ),
        ),
      ),
    );
  }
}

/// `1e` 列表末: the list is still growing.
class _GeneratingRow extends StatelessWidget {
  final String label;

  const _GeneratingRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// `1e` 行 52: thumbnail · old name → new name · badge · inline actions.
class _ResultRow extends StatelessWidget {
  final _RenameRow row;
  final bool narrow;

  /// Actions as glyphs with tooltips, for a list too narrow for their labels.
  final bool iconOnly;

  final bool editing;
  final TextEditingController editController;
  final VoidCallback onUndoSkip;
  final VoidCallback onSkip;
  final VoidCallback onEdit;
  final ValueChanged<String> onCommitEdit;
  final ValueChanged<_ConflictChoice> onResolve;

  const _ResultRow({
    required this.row,
    required this.narrow,
    required this.iconOnly,
    required this.editing,
    required this.editController,
    required this.onUndoSkip,
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
    final mono12 = textTheme.bodySmall!.mono;
    final unresolved = row.unresolved;

    final Color ground = unresolved
        ? colorScheme.errorContainer
        : (row.skipped ? colorScheme.surfaceContainer : colorScheme.surface);
    final Color newInk = unresolved
        ? colorScheme.onErrorContainer
        : (row.skipped ? colorScheme.outline : colorScheme.onSurface);

    final oldName = Tooltip(
      message: row.path,
      waitDuration: const Duration(milliseconds: 500),
      child: Text(
        row.oldName,
        style: mono12.copyWith(color: colorScheme.onSurfaceVariant),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final Widget newName = editing
        ? SizedBox(
            height: AppSize.compact,
            child: TextField(
              controller: editController,
              autofocus: true,
              style: mono12,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colorScheme.surface,
                // 28, not the 32 control: an editor inside a table row.
                constraints: const BoxConstraints.tightFor(height: AppSize.compact),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: pinnedFieldInset(context, mono12, AppSize.compact),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
              ),
              onSubmitted: onCommitEdit,
              onTapOutside: (_) => onCommitEdit(editController.text),
            ),
          )
        : Text(
            row.newName,
            style: mono12.copyWith(color: newInk, fontWeight: FontWeight.w500),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );

    final Widget? badge;
    if (row.skipped) {
      badge = TransferBadge(label: l10n.renameSkippedBadge, tone: TransferTone.track);
    } else if (unresolved) {
      badge = TransferBadge(label: l10n.renameDuplicateBadge, tone: TransferTone.err, outlined: true);
    } else if (row.choice == _ConflictChoice.overwrite) {
      badge = TransferBadge(label: l10n.conflictOverwrite, tone: TransferTone.err);
    } else if (row.autoRenamed) {
      badge = TransferBadge(label: l10n.renameRenamedBadge, tone: TransferTone.ok);
    } else {
      badge = null;
    }

    final List<Widget> actions;
    if (row.skipped) {
      actions = [
        _RowAction(
          icon: Icons.undo,
          label: l10n.renameActionUndo,
          color: colorScheme.onAccentTint,
          iconOnly: iconOnly,
          onTap: onUndoSkip,
        ),
      ];
    } else if (unresolved) {
      actions = [
        _RowAction(
          icon: Icons.auto_fix_high,
          label: l10n.renameConflictAutoRename,
          color: colorScheme.onAccentTint,
          iconOnly: iconOnly,
          onTap: () => onResolve(_ConflictChoice.rename),
        ),
        // Overwrite is the only answer that destroys a file, so it is the
        // only one in the error colour.
        _RowAction(
          icon: Icons.swap_horiz,
          label: l10n.conflictOverwrite,
          color: colorScheme.error,
          iconOnly: iconOnly,
          onTap: () => onResolve(_ConflictChoice.overwrite),
        ),
        _RowAction(
          icon: Icons.block,
          label: l10n.renameActionSkip,
          color: colorScheme.onSurfaceVariant,
          iconOnly: true,
          onTap: () => onResolve(_ConflictChoice.skip),
        ),
      ];
    } else {
      actions = [
        _RowAction(
          icon: Icons.edit_outlined,
          label: l10n.renameActionEdit,
          color: colorScheme.onSurfaceVariant,
          iconOnly: iconOnly,
          active: editing,
          onTap: onEdit,
        ),
        _RowAction(
          icon: Icons.block,
          label: l10n.renameActionSkip,
          color: colorScheme.onSurfaceVariant,
          iconOnly: iconOnly,
          onTap: onSkip,
        ),
      ];
    }

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ground,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          TransferThumb(path: row.path, size: 32),
          const SizedBox(width: AppSpace.s10),
          if (narrow)
            // Two lines instead of two columns: at this width the columns are
            // too narrow for either name to survive its own ellipsis.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  oldName,
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right, size: 12, color: colorScheme.outline),
                      const SizedBox(width: AppSpace.s4),
                      Expanded(child: newName),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            SizedBox(width: _kOldNameWidth, child: oldName),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward, size: AppSize.iconSm, color: colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(child: newName),
          ],
          if (badge != null) ...[const SizedBox(width: 8), badge],
          const SizedBox(width: 8),
          for (final (index, action) in actions.indexed) ...[
            if (index > 0) const SizedBox(width: 2),
            action,
          ],
        ],
      ),
    );
  }
}

/// A 28px inline row action: a text button with its glyph, or the glyph alone
/// with the label as its tooltip.
class _RowAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool iconOnly;
  final bool active;
  final VoidCallback onTap;

  const _RowAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconOnly,
    required this.onTap,
    this.active = false,
  });

  /// Everything a labelled action takes besides its label: 8px of padding a
  /// side, the glyph, and Material's gap after it.
  static const double chrome = 16 + AppSize.iconSm + 8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm));

    if (iconOnly) {
      return IconButton(
        icon: Icon(icon, size: AppSize.iconSm),
        tooltip: label,
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: AppSize.compact, height: AppSize.compact),
        style: IconButton.styleFrom(
          foregroundColor: color,
          backgroundColor: active ? colorScheme.accentTint : null,
          shape: shape,
        ),
      );
    }

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: AppSize.iconSm),
      label: Text(label, maxLines: 1),
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: active ? colorScheme.accentTint : null,
        minimumSize: const Size(0, AppSize.compact),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: Theme.of(context).textTheme.labelMedium,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: shape,
      ),
    );
  }
}

/// The folded config: one summary row with a way back to the controls, so the
/// narrow dialog spends its width on the results.
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

    final action = generating
        ? AppButton(
            label: l10n.renameStop,
            icon: Icons.stop_circle_outlined,
            variant: AppButtonVariant.destructiveText,
            size: AppButtonSize.compact,
            onPressed: onStop,
          )
        : AppButton(
            label: l10n.generateSuggestions,
            icon: Icons.auto_awesome,
            size: AppButtonSize.compact,
            onPressed: onGenerate,
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Edit config folds to its glyph when both labelled buttons would
          // leave the summary less room than a model name needs.
          final label = textTheme.labelMedium!;
          double buttonWidth(String text) => measureGlassText(context, text, label) + 20 + AppSize.iconSm + 8;
          final actionWidth = buttonWidth(generating ? l10n.renameStop : l10n.generateSuggestions);
          final editWidth = measureGlassText(context, l10n.renameEditConfig, label) + 20;
          final foldEdit = constraints.maxWidth - actionWidth - editWidth - 20 < 96;

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model?.modelName ?? l10n.noModelsConfigured,
                      style: textTheme.bodySmall!.mono.copyWith(color: colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${l10n.renameTemplateLabel} · ${template?.title ?? l10n.noTemplateSelected}',
                      style: textTheme.labelSmall!.copyWith(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (foldEdit)
                IconButton(
                  icon: const Icon(Icons.tune, size: AppSize.iconMd),
                  tooltip: l10n.renameEditConfig,
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: AppSize.compact, height: AppSize.compact),
                  style: IconButton.styleFrom(foregroundColor: colorScheme.onAccentTint),
                )
              else
                AppButton(
                  label: l10n.renameEditConfig,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.compact,
                  onPressed: onEdit,
                ),
              const SizedBox(width: AppSpace.s4),
              action,
            ],
          );
        },
      ),
    );
  }
}
