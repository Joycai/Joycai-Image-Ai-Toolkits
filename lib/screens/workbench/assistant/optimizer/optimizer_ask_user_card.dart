part of '../prompt_optimizer_view.dart';

/// Structured-question card for a pending `ask_user` tool call.
///
/// Stateful so the draft selections and "other" text live here (keyed by call
/// id in the parent) instead of bloating the chat view's state. Once the
/// entry's state flips to answered/dismissed the card renders collapsed and
/// the draft state is simply never read again.
class _AskUserCard extends StatefulWidget {
  final OptimizerChatEntry entry;

  /// False while an agent turn is queued or running — answering then would
  /// race the self-healing guard, which cancels a still-pending question.
  final bool enabled;
  final void Function(List<AskUserAnswer> answers) onSubmit;

  const _AskUserCard({
    super.key,
    required this.entry,
    required this.enabled,
    required this.onSubmit,
  });

  @override
  State<_AskUserCard> createState() => _AskUserCardState();
}

class _AskUserCardState extends State<_AskUserCard> {
  /// Selected option indices per question index.
  final Map<int, Set<int>> _selections = {};
  late final List<TextEditingController> _otherCtrls;

  List<AskUserQuestion> get _questions => widget.entry.askQuestions ?? const [];

  @override
  void initState() {
    super.initState();
    _otherCtrls = [for (final _ in _questions) TextEditingController()];
  }

  @override
  void dispose() {
    for (final c in _otherCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isAnswered(int qIndex) =>
      (_selections[qIndex]?.isNotEmpty ?? false) || _otherCtrls[qIndex].text.trim().isNotEmpty;

  bool get _allAnswered {
    for (int i = 0; i < _questions.length; i++) {
      if (!_isAnswered(i)) return false;
    }
    return _questions.isNotEmpty;
  }

  List<AskUserAnswer> _collectAnswers() => [
    for (int i = 0; i < _questions.length; i++)
      AskUserAnswer(
        header: _questions[i].header,
        selected: [
          for (final o in (_selections[i] ?? const <int>{}).toList()..sort())
            _questions[i].options[o].label,
        ],
        otherText: _otherCtrls[i].text.trim().isEmpty ? null : _otherCtrls[i].text.trim(),
      ),
  ];

  void _toggleOption(int qIndex, int oIndex, bool multiSelect) {
    setState(() {
      final current = _selections[qIndex] ?? <int>{};
      if (current.contains(oIndex)) {
        _selections[qIndex] = {...current}..remove(oIndex);
      } else {
        _selections[qIndex] = multiSelect ? {...current, oIndex} : {oIndex};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final state = widget.entry.askState ?? AskUserState.pending;
    if (state != AskUserState.pending) {
      return _buildResolved(state, l10n, colorScheme);
    }
    final canSubmit = widget.enabled && _allAnswered;
    final phone = Responsive.isMobile(context);

    // The 12% wash form: the one card in the transcript that is waiting on
    // the user, so the one that wears the accent.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.accentRing),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: AppSize.iconMd, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.optAskUserTitle,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.accentText,
                    ),
                  ),
                ),
              ],
            ),
            for (int i = 0; i < _questions.length; i++)
              _buildQuestion(i, l10n, colorScheme, textTheme),
            const SizedBox(height: 12),
            if (phone)
              SizedBox(
                height: _PromptOptimizerChatViewState._phoneActionHeight,
                child: AppButton(
                  label: l10n.optAskUserConfirm,
                  fullWidth: true,
                  onPressed: canSubmit ? () => widget.onSubmit(_collectAnswers()) : null,
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: l10n.optAskUserConfirm,
                  size: AppButtonSize.compact,
                  onPressed: canSubmit ? () => widget.onSubmit(_collectAnswers()) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(
    int qIndex,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final question = _questions[qIndex];
    final selected = _selections[qIndex] ?? const <int>{};
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  question.header,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: AppType.trackedLabelSpacing,
                  ),
                ),
              ),
              if (question.multiSelect) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.optAskUserMultiHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            question.question,
            style: textTheme.bodyMedium?.copyWith(
              height: AppType.proseHeight,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          for (int o = 0; o < question.options.length; o++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildOption(
                qIndex,
                o,
                question,
                selected.contains(o),
                colorScheme,
                textTheme,
              ),
            ),
          _buildOtherField(qIndex, l10n, colorScheme, textTheme),
        ],
      ),
    );
  }

  /// A 32px option row on the panel: hairline at rest, the accent edge and a
  /// filled mark when chosen.
  Widget _buildOption(
    int qIndex,
    int oIndex,
    AskUserQuestion question,
    bool isSelected,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final option = question.options[oIndex];
    final row = Material(
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: isSelected ? colorScheme.primary : colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: widget.enabled ? () => _toggleOption(qIndex, oIndex, question.multiSelect) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                _choiceMark(
                  selected: isSelected,
                  multi: question.multiSelect,
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.label,
                    style: textTheme.bodySmall?.copyWith(
                      color: widget.enabled ? colorScheme.onSurface : colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final description = option.description;
    return (description == null || description.isEmpty)
        ? row
        : Tooltip(message: description, child: row);
  }

  /// A checkbox for a multi-select question, a radio for a single one.
  Widget _choiceMark({
    required bool selected,
    required bool multi,
    required ColorScheme colorScheme,
  }) {
    final fill = widget.enabled ? colorScheme.primary : colorScheme.outline;
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? fill : null,
        shape: multi ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: multi ? BorderRadius.circular(AppRadius.xs) : null,
        border: selected ? null : Border.all(color: colorScheme.outline, width: 1.5),
      ),
      child: !selected
          ? null
          : multi
          ? Icon(Icons.check_rounded, size: 12, color: colorScheme.onPrimary)
          : Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: colorScheme.onPrimary, shape: BoxShape.circle),
            ),
    );
  }

  /// "Other / add details..." — a free-text row behind a dashed hairline, so
  /// it reads as an optional slot rather than one more option.
  Widget _buildOtherField(
    int qIndex,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return CustomPaint(
      foregroundPainter: _DashedOutlinePainter(
        color: colorScheme.outlineVariant,
        radius: AppRadius.control,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(Icons.edit_outlined, size: AppSize.iconSm, color: colorScheme.outline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _otherCtrls[qIndex],
                  enabled: widget.enabled,
                  minLines: 1,
                  maxLines: 3,
                  style: textTheme.bodySmall?.copyWith(
                    height: AppType.proseHeight,
                    color: colorScheme.onSurface,
                  ),
                  // setState so the confirm button re-evaluates _allAnswered.
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: l10n.optAskUserOtherHint,
                    hintStyle: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Collapsed rendering once the question is no longer actionable.
  Widget _buildResolved(AskUserState state, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final answered = state == AskUserState.answered;
    final answers = widget.entry.askAnswers ?? const <AskUserAnswer>[];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                answered ? Icons.check_circle_outline : Icons.remove_circle_outline,
                size: AppSize.iconSm,
                color: answered ? semantic.success : colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  answered ? l10n.optAskUserAnswered : l10n.optAskUserDismissed,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          for (final answer in answers)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 20),
              child: Text(
                '${answer.header}: '
                '${[...answer.selected, if (answer.otherText != null) answer.otherText!].join(', ')}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A 1px dashed rounded-rect edge drawn *over* the field.
///
/// Not [DashedBorder]: that paints behind its child, and here the child is the
/// field's own opaque fill. The dash rhythm is [drawDashedRRect]'s, like every
/// other dashed edge in the app; the half-pixel inset keeps a 1px stroke on
/// whole pixels, as `app_reorder_gap.dart` does.
class _DashedOutlinePainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedOutlinePainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    drawDashedRRect(canvas, rrect, paint);
  }

  @override
  bool shouldRepaint(_DashedOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
