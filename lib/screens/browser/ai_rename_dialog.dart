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
import '../../services/tasks/ai_rename_agent.dart';
import '../../services/tasks/ai_rename_review.dart';
import '../../services/db/database_service.dart';
import '../../services/tasks/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_dialog.dart';
import '../../widgets/ui/app_dropdown.dart';
import '../../widgets/ui/app_field_size.dart';
import '../../widgets/ui/app_segmented_control.dart';
import '../../widgets/ui/app_snackbar.dart';
import '../../widgets/models/chat_model_selector.dart';
import '../../widgets/glass/glass_controls.dart';
import '../../widgets/files/transfer_dialog_parts.dart';

part 'ai_rename/ai_rename_config.dart';
part 'ai_rename/ai_rename_results.dart';
part 'ai_rename/ai_rename_rows.dart';

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

/// AI batch rename — `B1b 1e` / `1f`.
///
/// The one large dialog on this screen: 920 wide, config on the left and the
/// review list on the right, each scrolling on its own. Suggestions land a
/// batch at a time and are reviewable as they arrive; they are applied only
/// once generation has finished.
class AiRenameDialog extends StatefulWidget {
  const AiRenameDialog({super.key, @visibleForTesting this.debugInitialRows});

  /// Review rows to open with, as if a run had produced them. Lets a test reach
  /// the review list — the clash actions above all — without a model call.
  final List<RenameReviewRow>? debugInitialRows;

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

  List<RenameReviewRow> _rows = [];
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

  /// [setState] for the builders in the parts. They are extensions on this
  /// class, and an extension may not call a protected member itself.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    final seeded = widget.debugInitialRows;
    if (seeded != null) _rows = List.of(seeded);
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
    final merged = <RenameReviewRow>[
      for (final proposal in collected) existing[proposal.path] ?? RenameReviewRow(proposal),
    ];
    _update(() => _rows = merged);
    _recomputeConflicts();
  }

  // --------------------------------------------------------------- conflicts

  /// See [recomputeRenameConflicts]: every edit recomputes every row.
  Future<void> _recomputeConflicts() async {
    await recomputeRenameConflicts(_rows);
    if (mounted) _update(() {});
  }

  void _resolve(RenameReviewRow row, RenameConflictChoice choice) {
    _update(() => resolveRenameConflict(row, choice, among: _rows));
    _recomputeConflicts();
  }

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
                'overwrite': row.choice == RenameConflictChoice.overwrite,
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

  List<RenameReviewRow> get _visibleRows {
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
