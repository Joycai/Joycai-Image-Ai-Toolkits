part of '../prompt_optimizer_view.dart';

/// What the empty chat offers in task-preset mode (`A3d 4c`): the library's
/// presets, which one is loaded, and the ways to change that. Handed in whole
/// — the view stays presentational, and the parent owns the unsaved-edit
/// guard a preset switch has to pass.
class OptimizerPresetChoices {
  const OptimizerPresetChoices({
    required this.presets,
    required this.selectedId,
    required this.builtinSelected,
    this.selectedKind = PresetOutputKind.prompt,
    required this.onPick,
    this.onShowAll,
    this.onManage,
  });

  /// Every refiner preset, in library order.
  final List<SystemPrompt> presets;
  final int? selectedId;

  /// True when nothing is loaded and the built-in preset will run.
  final bool builtinSelected;

  /// What the loaded preset hands back (`A3e`) — of the text in the panel,
  /// so it still holds once that text's library row is gone.
  final PresetOutputKind selectedKind;

  /// Loads a preset; null loads the built-in one. Selects — never sends.
  final void Function(SystemPrompt? preset) onPick;
  final VoidCallback? onShowAll;
  final VoidCallback? onManage;
}

/// The three empty states (`A3d 4c`). One shared paragraph could only
/// describe the mode the user was not in two times out of three.
extension _EmptyState on _PromptOptimizerChatViewState {
  /// Tiles shown before "All N presets…" takes over.
  static const int _tileCount = 4;

  Widget _buildEmptyState(
    PromptOptimizerSession session,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    // `A3e 5d`: under an analysis preset the first sentence is not obvious
    // — least of all that the images are named by their number — so the
    // empty chat asks a different question and shows how to put it.
    final analysis = _analysisPresetLoaded(session);
    final (IconData icon, String title, String sub) = switch (session.mode) {
      AssistantMode.systemPrompt => (
          Icons.auto_awesome,
          analysis ? l10n.optEmptyAnalysisTitle : l10n.optEmptyPresetTitle,
          analysis ? l10n.optEmptyAnalysisSub : l10n.optEmptyPresetSub,
        ),
      AssistantMode.knowledgeBase => (
          Icons.menu_book_outlined,
          l10n.optEmptyKbTitle,
          l10n.optEmptyKbSub,
        ),
      AssistantMode.knowledgeEdit => (
          Icons.edit_note_outlined,
          l10n.optEmptyKbEditTitle,
          l10n.optEmptyKbEditSub,
        ),
    };
    final examples = switch (session.mode) {
      AssistantMode.systemPrompt => analysis
          ? [
              l10n.optEmptyAnalysisExample1,
              l10n.optEmptyAnalysisExample2,
              l10n.optEmptyAnalysisExample3,
            ]
          : const <String>[],
      AssistantMode.knowledgeBase => [
          l10n.optEmptyKbExample1,
          l10n.optEmptyKbExample2,
          l10n.optEmptyKbExample3,
        ],
      AssistantMode.knowledgeEdit => [
          l10n.optEmptyKbEditExample1,
          l10n.optEmptyKbEditExample2,
          l10n.optEmptyKbEditExample3,
        ],
    };
    final choices = widget.presetChoices;

    // Scrollable, not just centred: the input bar grows to six lines as the
    // user types, and the console below can be dragged up, so the space left
    // for this can fall below the artwork's own height. A bare Column cannot
    // shrink past its children and would overflow instead.
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: _gutter, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.accentTint,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(icon, size: 24, color: colorScheme.primary),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.looseHeight,
                ),
              ),
              if (session.mode == AssistantMode.systemPrompt && choices != null) ...[
                const SizedBox(height: AppSpace.s16),
                _buildPresetTiles(choices, l10n, colorScheme, textTheme),
              ],
              if (examples.isNotEmpty) ...[
                const SizedBox(height: AppSpace.s16),
                for (final (index, example) in examples.indexed) ...[
                  if (index > 0) const SizedBox(height: AppSpace.s6),
                  _buildExample(example, colorScheme, textTheme),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Whether what is loaded answers in the chat rather than with a prompt.
  bool _analysisPresetLoaded(PromptOptimizerSession session) =>
      session.mode == AssistantMode.systemPrompt &&
      widget.presetChoices?.selectedKind == PresetOutputKind.analysis;

  /// 2×2 on a wide column, one column on a phone. Picking loads the preset;
  /// it never sends — the user has not said anything yet.
  Widget _buildPresetTiles(
    OptimizerPresetChoices choices,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final shown = choices.presets.take(_tileCount).toList();
    final tiles = <Widget>[
      // With no library presets the built-in is the only thing to show, and
      // showing it says what will run.
      if (shown.isEmpty)
        _PresetTile(
          title: l10n.optPresetBuiltinName,
          summary: l10n.optPresetBuiltinDesc,
          selected: choices.builtinSelected,
          onTap: () => choices.onPick(null),
        ),
      for (final preset in shown)
        _PresetTile(
          title: preset.title,
          summary: presetSummaryOf(preset.content),
          dotColor: preset.tags.isEmpty ? null : Color(preset.tags.first.color),
          marker: preset.outputKind == PresetOutputKind.analysis
              ? l10n.presetOutputAnalysisShort
              : null,
          selected: preset.id == choices.selectedId,
          onTap: () => choices.onPick(preset),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = _phone || tiles.length == 1 ? 1 : 2;
            const gap = AppSpace.s10;
            final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
            );
          },
        ),
        const SizedBox(height: AppSpace.s10),
        if (choices.presets.isEmpty)
          AppButton(
            label: l10n.optEmptyPresetCreate,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: choices.onManage,
          )
        else
          // Always, not only past four: it is also the way to the built-in.
          AppButton(
            label: l10n.optEmptyPresetAll(choices.presets.length),
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: choices.onShowAll,
          ),
      ],
    );
  }

  /// An example request. Tapping fills the composer and stops there: most end
  /// on a colon, waiting for the part only the user knows.
  Widget _buildExample(String example, ColorScheme colorScheme, TextTheme textTheme) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Ahead of a draft, never over it: the empty state stays up while
          // the user types, and most examples end on a colon precisely so
          // that their text can follow.
          final draft = widget.inputCtrl.text;
          final joint = draft.isEmpty || example.endsWith(' ') || example.endsWith('：') ? '' : '\n';
          final text = '$example$joint$draft';
          widget.inputCtrl.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  example,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    height: AppType.proseHeight,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              Icon(Icons.north_west, size: AppSize.iconSm, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.title,
    required this.summary,
    required this.selected,
    required this.onTap,
    this.dotColor,
    this.marker,
  });

  final String title;
  final String summary;
  final Color? dotColor;

  /// `A3e 5d`: the 「分析」 marker, ahead of the selection tick.
  final String? marker;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colorScheme.accentTint : colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: selected ? colorScheme.primary : colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (dotColor != null) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: AppSpace.s6),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelLarge?.copyWith(
                          color: selected ? colorScheme.onAccentTint : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (marker != null) ...[
                      const SizedBox(width: AppSpace.s6),
                      AppNeutralMarker(icon: Icons.subject, label: marker!),
                    ],
                    if (selected) ...[
                      const SizedBox(width: AppSpace.s6),
                      Icon(Icons.check_circle, size: AppSize.iconMd, color: colorScheme.primary),
                    ],
                  ],
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.s4),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                      height: AppType.proseHeight,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
