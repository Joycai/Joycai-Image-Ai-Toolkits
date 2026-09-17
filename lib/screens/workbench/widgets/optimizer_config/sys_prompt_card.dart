part of '../optimizer_config_panel.dart';

extension _SysPromptCard on _OptimizerConfigPanelState {
  /// `A3a 1a`'s system-prompt card: which template is loaded, its text, what
  /// the text costs, the two ways out of an edit, and why this mode makes no
  /// tool calls.
  ///
  /// The text is always on screen, a template is where it starts, and the edit
  /// is a state the card can report and undo.
  Widget _buildSysPromptSection(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final semantic = context.semantic;
    final template = _template;
    final text = widget.selectedSysPrompt ?? '';
    final dirty = template != null && text != template.content;

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(
          l10n.systemPrompt,
          // Amber, not the accent: this is a condition to act on — text that
          // will be lost when another template is loaded over it.
          trailing: dirty
              ? OptimizerTagBadge(
                  label: l10n.optSysPromptUnsaved,
                  background: semantic.warningContainer,
                  foreground: semantic.onWarningContainer,
                )
              : null,
        ),
        _buildTemplatePicker(l10n, colorScheme, template),
        _buildSysPromptEditor(l10n, colorScheme, textTheme),
        _buildSysPromptMeter(l10n, colorScheme, textTheme, text),
        if (template != null) _buildSysPromptActions(l10n, template, text, dirty),
        _hairlined(colorScheme, Text(l10n.optSysPromptNoTools, style: _noteStyle(colorScheme, textTheme))),
      ],
    );
  }

  /// The template row. A [SearchablePickerField]: the tag rides along as each
  /// row's badge and the picker matches on it, so filtering by tag is typing
  /// its name rather than setting a second control first.
  Widget _buildTemplatePicker(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    SystemPrompt? template,
  ) {
    return SearchablePickerField<int>(
      selected: template == null
          ? null
          : PickerOption<int>(
              value: template.id!,
              label: template.title,
              badge: template.tags.isEmpty ? null : template.tags.first.name,
              badgeColor: template.tags.isEmpty ? null : Color(template.tags.first.color),
            ),
      optionsBuilder: () => [
        for (final p in widget.sysPrompts)
          if (p.id != null)
            PickerOption<int>(
              value: p.id!,
              label: p.title,
              badge: p.tags.isEmpty ? null : p.tags.first.name,
              badgeColor: p.tags.isEmpty ? null : Color(p.tags.first.color),
            ),
      ],
      onChanged: (id) {
        final picked = widget.sysPrompts.firstWhere((p) => p.id == id);
        widget.onSysPromptTemplateChanged(picked.id, picked.content);
      },
      hint: l10n.optSysPromptNone,
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
