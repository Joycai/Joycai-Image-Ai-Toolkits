part of '../optimizer_config_panel.dart';

/// The built-in preset's place in the picker. Library ids start at 1.
const int _builtinPresetId = -1;

extension _SysPromptCard on _OptimizerConfigPanelState {
  /// `A3d 4b`'s task-preset card: which preset, a line saying what it is for,
  /// and — folded away until asked for — its instructions, what they cost and
  /// the two ways out of an edit. Then that this mode leaves the knowledge
  /// base alone, and where presets are kept.
  ///
  /// Task first, text second: the card used to open on eight lines of editor,
  /// which pushed the timeline and the context card off a 1440 screen to show
  /// text most sessions never touch.
  Widget _buildSysPromptSection(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final semantic = context.semantic;
    final template = _template;
    final text = widget.selectedSysPrompt ?? '';
    final builtin = _isBuiltinPreset;
    final dirty = template != null && text != template.content;
    final shown = builtin ? PromptOptimizerAgent.builtinPresetInstructions : text;
    final summary = builtin ? l10n.optPresetBuiltinDesc : presetSummaryOf(text);

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(
          l10n.optModeSystemPrompt,
          // Amber, not the accent: this is a condition to act on — text that
          // will be lost when another preset is loaded over it. On the caption
          // so that folding the editor away does not fold the warning with it.
          trailing: dirty
              ? OptimizerTagBadge(
                  label: l10n.optSysPromptUnsaved,
                  background: semantic.warningContainer,
                  foreground: semantic.onWarningContainer,
                )
              : null,
        ),
        _buildTemplatePicker(l10n, colorScheme, template, dirty: dirty),
        if (summary.isNotEmpty)
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _noteStyle(colorScheme, textTheme),
          ),
        _buildPresetDisclosure(l10n, colorScheme, textTheme, shown, builtin: builtin),
        if (_presetExpanded) ...[
          if (builtin)
            _buildBuiltinInstructions(l10n, colorScheme, textTheme)
          else ...[
            _buildSysPromptEditor(l10n, colorScheme, textTheme),
            _buildSysPromptMeter(l10n, colorScheme, textTheme, text),
            if (template != null)
              _buildSysPromptActions(l10n, template, text, dirty)
            else
              // Text with no preset behind it — its library row is gone. The
              // only way to keep it is to file it as a new one.
              _buildSaveAsRow(l10n, text),
          ],
        ],
        _hairlined(
          colorScheme,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.optSysPromptNoKb, style: _noteStyle(colorScheme, textTheme)),
              if (widget.onManagePresets != null) ...[
                const SizedBox(height: AppSpace.s6),
                _TextLink(label: l10n.optPresetManage, onTap: widget.onManagePresets),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The preset row. A [SearchablePickerField]: the tag rides along as each
  /// row's badge and the picker matches on it, so filtering by tag is typing
  /// its name rather than setting a second control first.
  ///
  /// The built-in preset is always the first row. It was always what ran when
  /// nothing was picked; listing it is what makes that a choice.
  Widget _buildTemplatePicker(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    SystemPrompt? template, {
    required bool dirty,
  }) {
    final builtinOption = PickerOption<int>(
      value: _builtinPresetId,
      label: l10n.optPresetBuiltinName,
      badge: l10n.optPresetBuiltinBadge,
      badgeColor: colorScheme.outline,
    );
    PickerOption<int> optionOf(SystemPrompt p) => PickerOption<int>(
          value: p.id!,
          label: p.title,
          badge: p.tags.isEmpty ? null : p.tags.first.name,
          badgeColor: p.tags.isEmpty ? null : Color(p.tags.first.color),
        );

    return SearchablePickerField<int>(
      selected: template != null
          ? optionOf(template)
          : _isBuiltinPreset
              ? builtinOption
              // Orphaned text: named for what it is, and not an option —
              // there is nothing in the list to go back to it from.
              : PickerOption<int>(value: 0, label: l10n.optPresetCustom),
      optionsBuilder: () => [
        builtinOption,
        for (final p in widget.sysPrompts)
          if (p.id != null) optionOf(p),
      ],
      onChanged: (id) async {
        if (id == (template?.id ?? (_isBuiltinPreset ? _builtinPresetId : 0))) return;
        if (dirty && !await _confirmDiscardPresetEdit(l10n, template!.title)) return;
        if (id == _builtinPresetId) {
          // Empty, not null: null is "never chosen", which the first load
          // answers by picking the library's first preset.
          widget.onSysPromptTemplateChanged(null, '');
          return;
        }
        final picked = widget.sysPrompts.firstWhere((p) => p.id == id);
        widget.onSysPromptTemplateChanged(picked.id, picked.content);
      },
      // Never shown — something is always selected — but the field requires one.
      hint: l10n.optModeSystemPrompt,
      searchHint: l10n.optSysPromptSearch,
      dialogTitle: l10n.optSysPromptPick,
      dialogIcon: Icons.notes_outlined,
      size: _fieldSize,
      decoration: _fieldDecoration(colorScheme),
      // A dot: the column narrows to 250px and a spelled-out tag there is a
      // coloured box with no letters left in it.
      badgeStyle: PickerBadge.dot,
    );
  }

  /// Asked once, at the moment the edit would be lost — loading a preset
  /// replaces the editor's text, and an unsaved edit lives nowhere else.
  Future<bool> _confirmDiscardPresetEdit(AppLocalizations l10n, String name) async {
    final discard = await AppDialog.show<bool>(
      context,
      title: l10n.optPresetDiscardTitle,
      content: Text(l10n.optPresetDiscardBody(name)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.optPresetDiscardAction,
          variant: AppButtonVariant.destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    return discard == true && mounted;
  }

  /// The fold: a chevron, what opening it gets you, and what the text costs
  /// either way — the one figure about it worth seeing while it is shut.
  Widget _buildPresetDisclosure(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
    String shown, {
    required bool builtin,
  }) {
    final tokens = (shown.length / ContextBudget.charsPerToken).round();
    return Semantics(
      button: true,
      expanded: _presetExpanded,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => _setPresetExpanded(!_presetExpanded),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: _touch ? AppSpace.s10 : AppSpace.s4),
          child: Row(
            children: [
              Icon(
                _presetExpanded ? Icons.expand_more : Icons.chevron_right,
                size: AppSize.iconMd,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpace.s4),
              Expanded(
                child: Text(
                  builtin ? l10n.optPresetViewInstructions : l10n.optPresetEditInstructions,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              Text(
                l10n.optSysPromptTokens(_formatCount(tokens)),
                style: _monoStyle(textTheme, colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The built-in instructions, read-only, and the way to make them one's own.
  Widget _buildBuiltinInstructions(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.s10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: SelectableText(
            PromptOptimizerAgent.builtinPresetInstructions,
            style: textTheme.bodySmall?.copyWith(
              height: AppType.proseHeight,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: OptimizerPanelCard.gap),
        Row(
          children: [
            Icon(Icons.lock_outline, size: AppSize.iconSm, color: colorScheme.outline),
            const SizedBox(width: AppSpace.s4),
            Expanded(
              child: Text(
                l10n.optPresetBuiltinLocked,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _noteStyle(colorScheme, textTheme),
              ),
            ),
          ],
        ),
        const SizedBox(height: OptimizerPanelCard.gap),
        _buildSaveAsRow(l10n, PromptOptimizerAgent.builtinPresetInstructions),
      ],
    );
  }

  Widget _buildSaveAsRow(AppLocalizations l10n, String content) {
    final onSaveAs = widget.onSaveAsPreset;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: AppButton(
        label: l10n.optPresetSaveAs,
        variant: AppButtonVariant.secondary,
        size: _touch ? AppButtonSize.normal : AppButtonSize.compact,
        onPressed: onSaveAs == null || content.trim().isEmpty ? null : () => onSaveAs(content),
      ),
    );
  }

  /// The instructions themselves.
  ///
  /// `A3a` gives this the remaining height of the column. Here it is a
  /// minimum-height box inside the column's scroll view instead: the column
  /// scrolls — it has to, since the cards below cannot be pushed off — and a
  /// child that claims the leftover space cannot live in a viewport that has
  /// none to give.
  Widget _buildSysPromptEditor(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final style = textTheme.bodySmall?.copyWith(
      height: AppType.proseHeight,
      color: colorScheme.onSurface,
    );
    return TextField(
      controller: _sysPromptCtrl,
      minLines: 8,
      maxLines: null,
      onChanged: widget.onSysPromptChanged,
      style: style,
      decoration: InputDecoration(
        hintText: l10n.optSysPromptHint,
        hintStyle: style?.copyWith(color: colorScheme.outline),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.all(AppSpace.s10),
      ),
    );
  }

  /// What the text costs, in the two units the user thinks in.
  ///
  /// The token figure is an estimate and says so with `~`: it is the same
  /// [ContextBudget.charsPerToken] ratio the context card measures against, so
  /// the two numbers on this column cannot disagree about the same prompt.
  Widget _buildSysPromptMeter(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
    String text,
  ) {
    final tokens = (text.length / ContextBudget.charsPerToken).round();
    return Text(
      '${l10n.optSysPromptChars(text.length)} · ${l10n.optSysPromptTokens(_formatCount(tokens))}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _monoStyle(textTheme, colorScheme.onSurfaceVariant),
    );
  }

  /// Commit the edit to the library, or throw it away.
  ///
  /// Both are off unless there is an edit to act on, so the pair is inert
  /// rather than absent while the text still matches its template — the row
  /// keeps its height and the card does not jump the first time a character is
  /// typed.
  Widget _buildSysPromptActions(
    AppLocalizations l10n,
    SystemPrompt template,
    String text,
    bool dirty,
  ) {
    final size = _touch ? AppButtonSize.normal : AppButtonSize.compact;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(
          label: l10n.optSysPromptReset,
          variant: AppButtonVariant.text,
          size: size,
          onPressed: dirty
              ? () => widget.onSysPromptTemplateChanged(template.id, template.content)
              : null,
        ),
        const SizedBox(width: AppSpace.s6),
        AppButton(
          label: l10n.optSysPromptSave,
          size: size,
          loading: _savingTemplate,
          onPressed: dirty ? () => _handleSaveTemplate(template, text) : null,
        ),
      ],
    );
  }
}

/// `18.2K` past a thousand — the same shape [OptimizerContextCard] uses, so
/// the two figures on this column are read off the same scale.
String _formatCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '${(value / 1000000).toStringAsFixed(1)}M';
}
