part of '../model_edit_dialog.dart';

/// The output cap: Auto / Specify, the typed figure and a six-stop track.
///
/// The same anatomy as the context section right above it — caption with a
/// status figure, a choice grid, a mono field with `tokens` after the
/// number, a track, helper text — so the two read as one pair of limits:
/// what the model may be sent, what it may say back. The differences are
/// what the value is: two states rather than three (there is no "unlimited"
/// cap to declare — on the wires where a cap is optional, Auto *is* no cap),
/// six stops in one rank rather than nine in two (`OutputCapScale`), and a
/// snapping track rather than the magnet, because output caps are almost
/// always a power of two.
extension _OutputCapSection on _ModelEditDialogState {
  Widget _outputCapSection(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final tokens = _outputCapTokens;
    final specified = outputCapSpecified;
    final hasValue = tokens != null && tokens > 0;
    final invalid = _outputCapTouched && !_outputCapValid;
    final window = _contextTokens;
    // The cap only means anything below the window: a hosted endpoint
    // refuses the request past it, a local runtime truncates on its own.
    // Said here rather than clamped in the request, where a rewrite would be
    // a third behaviour nobody can see.
    final exceedsWindow = specified &&
        hasValue &&
        contextMode == ContextWindowMode.specified &&
        window != null &&
        window > 0 &&
        tokens >= window;

    final String status;
    if (specified && hasValue) {
      final exact = OutputCapScale.stopIndexOf(tokens);
      status = exact != null
          ? l10n.contextStatusPreset(OutputCapScale.label(OutputCapScale.stops[exact]))
          : formatGroupedTokens(tokens);
    } else if (!specified && _isAnthropicChannel) {
      // ④'s field is mandatory, so Auto is a number the user should see.
      status = l10n.outputCapDefault(formatGroupedTokens(anthropicDefaultMaxTokens));
    } else {
      status = '';
    }

    final description = specified
        ? l10n.outputCapSpecifyDesc
        : _isAnthropicChannel
            ? l10n.outputCapAutoAnthropicDesc
            : l10n.outputCapAutoDesc;
    // Reasoning is set on this model and the cap is a number: the two share
    // it on every wire (usage 04 §3), and a cap sized for the answer alone
    // is spent on the thinking first.
    final thinkingShares = specified && reasoningEffort != null && reasoningEffort != 'off';
    // ④'s budget dialect carves half the cap for thinking with a 1024 floor
    // and sends no thinking at all when that floor does not fit — silently,
    // the request just goes out without it. Below twice the floor is where
    // that happens; said here, since nothing on the wire says it.
    final capStarvesThinking =
        thinkingShares && _isAnthropicChannel && hasValue && tokens < 2 * anthropicMinThinkingBudget;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: _caption(l10n.outputCap, scope: _scope(route: true))),
            if (status.isNotEmpty) ...[
              const SizedBox(width: AppSpace.s10),
              Text(
                status,
                style: theme.textTheme.labelSmall?.mono.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditChoiceGrid<bool>(
          choices: [
            ModelEditChoice(value: false, label: l10n.outputCapAuto),
            ModelEditChoice(value: true, label: l10n.outputCapSpecify),
          ],
          value: specified,
          onChanged: (v) => _rebuild(() => outputCapSpecified = v),
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
                      ModelEditTextField(
                        controller: outputCapCtrl,
                        focusNode: _outputCapFocus,
                        mono: true,
                        hint: '${OutputCapScale.stops[4]}',
                        keyboardType: TextInputType.text,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9kKmM ,.]'))],
                        suffixText: l10n.contextTokensUnit,
                        error: invalid,
                        onChanged: (_) => _rebuild(() => _outputCapTouched = true),
                      ),
                      const SizedBox(height: AppSpace.s6),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.s6),
                        child: ModelEditTrackSlider(
                          stopCount: OutputCapScale.stops.length,
                          value: hasValue ? OutputCapScale.positionOf(tokens) : 0,
                          snap: true,
                          highlight: hasValue ? OutputCapScale.stopIndexOf(tokens) : null,
                          labels: [for (final stop in OutputCapScale.stops) OutputCapScale.label(stop)],
                          semanticLabel: l10n.outputCap,
                          semanticValueOf: (p) => l10n.contextTokens(
                              formatGroupedTokens(OutputCapScale.tokensAt(p))),
                          onChanged: (p) => _setOutputCapTokens(OutputCapScale.tokensAt(p)),
                        ),
                      ),
                      const SizedBox(height: AppSpace.s4),
                      ModelEditHelperText(l10n.outputCapSliderHint),
                      if (!_outputCapValid)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.s6),
                          child: ModelEditValidationNote(title: l10n.outputCapSpecifyInvalid),
                        ),
                      if (exceedsWindow)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.s6),
                          child: ModelEditValidationNote(
                            title: l10n.outputCapExceedsWindow(formatGroupedTokens(window)),
                          ),
                        ),
                      if (capStarvesThinking)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.s6),
                          child: ModelEditValidationNote(
                            title: l10n.outputCapStarvesThinking(
                                formatGroupedTokens(2 * anthropicMinThinkingBudget)),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditHelperText(description),
        if (thinkingShares) ...[
          const SizedBox(height: AppSpace.s6),
          ModelEditHelperText(l10n.outputCapThinkingHint),
        ],
      ],
    );
  }

  void _setOutputCapTokens(int tokens) {
    if (tokens == _outputCapTokens && outputCapCtrl.text == '$tokens') return;
    _rebuild(() {
      outputCapCtrl.value = TextEditingValue(
        text: '$tokens',
        selection: TextSelection.collapsed(offset: '$tokens'.length),
      );
      _outputCapTouched = true;
    });
  }
}
