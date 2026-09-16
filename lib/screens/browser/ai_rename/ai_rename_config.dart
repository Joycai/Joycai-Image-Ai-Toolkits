part of '../ai_rename_dialog.dart';

/// The left column (`1e` 左列): model, template and instructions — and, below
/// the narrow breakpoint, the summary row and the sheet that stand in for it.
extension _ConfigColumn on _AiRenameDialogState {
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
    if (mounted) _rebuild(() {});
  }

  // ------------------------------------------------------------ result panel
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
