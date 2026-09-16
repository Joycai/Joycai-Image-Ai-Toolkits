part of '../model_edit_dialog.dart';

/// The context window: Auto / Specify, the typed figure and its stepper.
extension _ContextSection on _ModelEditDialogState {
  /// `1a`'s Specify view. The typed figure is the value; the slider, the
  /// preset menu, the tick labels and the arrow keys are four ways of writing
  /// it. A status string on the caption's row says where the figure sits
  /// (`= 128k · preset`, `≈ 128k–256k`).
  Widget _contextSection(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final tokens = _contextTokens;
    final specified = contextMode == ContextWindowMode.specified;
    final hasValue = tokens != null && tokens > 0;
    final invalid = _contextTouched && !_contextValid;

    final description = switch (contextMode) {
      // An image or video model has no conversation to budget, so "unset" is
      // not a guess there but the right answer.
      ContextWindowMode.unset => switch (tag) {
          'image' => l10n.contextImageUnsetDesc,
          'video' => l10n.contextVideoUnsetDesc,
          _ => l10n.contextUnsetDesc,
        },
      ContextWindowMode.specified => l10n.contextWindowHint,
      ContextWindowMode.unlimited => l10n.contextUnlimitedDesc,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: _caption(l10n.contextWindow)),
            if (specified && hasValue) ...[
              const SizedBox(width: AppSpace.s10),
              Text(
                _contextStatus(tokens),
                style: theme.textTheme.labelSmall?.mono.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditChoiceGrid<ContextWindowMode>(
          choices: [
            ModelEditChoice(value: ContextWindowMode.unset, label: l10n.contextUnset),
            ModelEditChoice(value: ContextWindowMode.specified, label: l10n.contextSpecify),
            ModelEditChoice(value: ContextWindowMode.unlimited, label: l10n.contextUnlimited),
          ],
          value: contextMode,
          onChanged: (v) => _rebuild(() => contextMode = v),
        ),
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: !specified
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: _ModelEditDialogState._fieldGap),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _contextField(context, invalid: invalid),
                      const SizedBox(height: AppSpace.s6),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.s6),
                        child: ContextWindowSlider(
                          value: hasValue ? ContextWindowScale.positionOf(tokens) : 0,
                          semanticLabel: l10n.contextMax,
                          // The typed figure where the thumb rests on it; the
                          // track's own value anywhere else.
                          semanticValueOf: (p) => l10n.contextTokens(formatGroupedTokens(
                              hasValue && p == ContextWindowScale.positionOf(tokens)
                                  ? tokens
                                  : ContextWindowScale.tokensAt(p))),
                          onChanged: (position) => _setContextTokens(ContextWindowScale.tokensAt(position)),
                        ),
                      ),
                      const SizedBox(height: AppSpace.s4),
                      ModelEditHelperText(l10n.contextSliderHint),
                      // Shown whenever Specify holds nothing savable — the
                      // user chose Specify, and this is why Save is off. The
                      // stroke waits for typing.
                      if (!_contextValid)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.s6),
                          child: ModelEditValidationNote(title: l10n.contextSpecifyInvalid),
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditHelperText(description),
      ],
    );
  }

  /// The Specify field: mono, `tokens` after the figure, the 「档位」 preset
  /// menu at its end. Takes `128k` / `1m` as well as digits, and normalises
  /// what it holds to digits when focus leaves. ↑↓ walk the presets, ⇧↑↓
  /// only the major ones (`1a` path ③).
  Widget _contextField(BuildContext context, {required bool invalid}) {
    final l10n = widget.l10n;
    final tokens = _contextTokens;
    final metrics = ModelEditMetrics.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _stepContext(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _stepContext(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () => _stepContext(1, majorOnly: true),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () => _stepContext(-1, majorOnly: true),
      },
      child: ModelEditTextField(
        controller: contextCtrl,
        focusNode: _contextFocus,
        mono: true,
        hint: '${ContextBudget.defaultWindowTokens}',
        keyboardType: TextInputType.text,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9kKmM ,.]'))],
        suffixText: l10n.contextTokensUnit,
        suffix: ContextWindowPresetMenu(
          label: l10n.contextPresets,
          selected: tokens == null ? null : ContextWindowScale.stopIndexOf(tokens),
          onSelected: (i) => _setContextTokens(ContextWindowScale.stops[i]),
          height: metrics.fieldHeight,
        ),
        error: invalid,
        onChanged: (_) => _rebuild(() => _contextTouched = true),
      ),
    );
  }

  /// Where the figure sits on the scale, for the caption's row.
  String _contextStatus(int tokens) {
    final l10n = widget.l10n;
    final stops = ContextWindowScale.stops;
    final exact = ContextWindowScale.stopIndexOf(tokens);
    if (exact != null) return l10n.contextStatusPreset(ContextWindowScale.label(stops[exact]));
    if (tokens < stops.first) return l10n.contextStatusBelow(ContextWindowScale.label(stops.first));
    if (tokens > stops.last) return l10n.contextStatusAbove(ContextWindowScale.label(stops.last));
    final lo = ContextWindowScale.positionOf(tokens).floor();
    return l10n.contextStatusBetween(
      ContextWindowScale.label(stops[lo]),
      ContextWindowScale.label(stops[lo + 1]),
    );
  }

  void _setContextTokens(int tokens) {
    if (tokens == _contextTokens && contextCtrl.text == '$tokens') return;
    _rebuild(() {
      contextCtrl.value = TextEditingValue(
        text: '$tokens',
        selection: TextSelection.collapsed(offset: '$tokens'.length),
      );
      _contextTouched = true;
    });
  }

  /// An arrow in the field: the next preset in [direction]; from an empty
  /// field, the first one.
  void _stepContext(int direction, {bool majorOnly = false}) {
    final current = _contextTokens;
    final next = current == null || current <= 0
        ? ContextWindowScale.stops.first
        : ContextWindowScale.stepFrom(current, direction, majorOnly: majorOnly);
    if (next != null) _setContextTokens(next);
  }
}
