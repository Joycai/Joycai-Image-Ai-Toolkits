part of '../ai_rename_dialog.dart';

/// The right column: the filter row, the failed-batch card, the empty and
/// no-model states, and the review list itself.
extension _ResultsArea on _AiRenameDialogState {
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
                  onChanged: (value) => _rebuild(() => _filter = value),
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
                  if (row.choice == RenameConflictChoice.skip) row.choice = null;
                });
                _recomputeConflicts();
              },
              onSkip: () {
                _update(() => row.skipped = true);
                _recomputeConflicts();
              },
              onEdit: () => _rebuild(() {
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
}
