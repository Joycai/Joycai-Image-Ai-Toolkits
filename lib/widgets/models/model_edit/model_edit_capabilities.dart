part of '../model_edit_dialog.dart';

/// Capabilities, the card preview, agent behaviour and the reasoning ladder.
extension _CapabilitySections on _ModelEditDialogState {
  Widget _capabilitiesSection(BuildContext context) {
    final l10n = widget.l10n;
    final ignoredBy = _streamIgnoredBy;
    final asyncPinned = _asyncImagePinned;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.capabilities, scope: _scope()),
        const SizedBox(height: AppSpace.s6),
        ModelEditCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // With a non-streaming route pinned the toggle is inert: the
              // value is preserved, not rewritten — switch back to auto and it
              // comes back untouched. The notice below says which route.
              ModelEditToggleRow(
                title: l10n.supportsStreaming,
                tooltip: l10n.supportsStreamingDesc,
                value: supportsStream,
                dimmed: ignoredBy != null,
                onChanged: ignoredBy != null ? null : (v) => _rebuild(() => supportsStream = v),
              ),
              const Divider(height: 1),
              ModelEditToggleRow(
                title: l10n.supportsStandardRequest,
                tooltip: l10n.supportsStandardRequestDesc,
                value: supportsStandard,
                onChanged: (v) => _rebuild(() => supportsStandard = v),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `1d`: a statement of fact, not an error.
              if (ignoredBy != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ModelEditNotice(
                    tone: ModelEditTone.info,
                    text: l10n.protocolStreamIgnored(wireProtocolLabel(l10n, ignoredBy)),
                  ),
                ),
              if (asyncPinned)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ModelEditNotice(tone: ModelEditTone.info, text: l10n.protocolAsyncQueueNote),
                ),
              const SizedBox(width: double.infinity),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewSection(BuildContext context) {
    final l10n = widget.l10n;
    final feeGroup = widget.appState.allPricingGroups
        .cast<PricingGroup?>()
        .firstWhere((g) => g?.id == feeGroupId, orElse: () => null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.cardPreview),
        const SizedBox(height: AppSpace.s6),
        ModelEditCardPreview(
          model: _draftModel,
          channel: _selectedChannel,
          feeGroup: feeGroup,
        ),
      ],
    );
  }

  /// The model as it would be saved right now, for the card preview. Carries
  /// the raw stored selection so the card can mark a stale one itself, and
  /// no context window while Specify holds nothing savable.
  LLMModel get _draftModel {
    final id = idCtrl.text.trim();
    final name = nameCtrl.text.trim();
    return LLMModel(
      id: widget.model?.id,
      modelId: id,
      modelName: name.isEmpty ? id : name,
      tag: tag,
      supportsStream: supportsStream,
      supportsStandard: supportsStandard,
      channelId: channelId,
      feeGroupId: feeGroupId,
      contextWindow: _contextValid ? ContextBudget.store(contextMode, _contextTokens ?? 0) : null,
      maxOutputTokens: _outputCapValid ? _storedOutputCap : null,
      forceViewAllImages: forceViewAllImages,
      enableThinking: reasoningEffort != null && reasoningEffort != 'off',
      reasoningEffort: reasoningEffort,
      enableWebSearch: enableWebSearch,
      wireProtocol: wireProtocol,
      activeRoute: activeRoute,
      routeParams: ModelRoutes.encodeParked(_parked),
    );
  }

  // --- Behaviour ------------------------------------------------------------

  Widget _agentSection(BuildContext context) {
    final l10n = widget.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.agentBehavior, scope: _scope()),
        const SizedBox(height: AppSpace.s6),
        ModelEditCard(
          child: ModelEditToggleRow(
            title: l10n.forceViewAllImages,
            description: l10n.forceViewAllImagesDesc,
            emphasized: true,
            value: forceViewAllImages,
            onChanged: (v) => _rebuild(() => forceViewAllImages = v),
          ),
        ),
      ],
    );
  }

  /// A rung's name. On a ladder with no intensity the one rung above Default
  /// is simply on, whatever level it is stored as.
  String _rungLabel(ReasoningEffort? rung, {required bool short, required bool onOff}) {
    final l10n = widget.l10n;
    return switch (rung) {
      null => short ? l10n.reasoningEffortDefaultShort : l10n.reasoningEffortDefault,
      ReasoningEffort.off => l10n.reasoningEffortOff,
      ReasoningEffort.low => l10n.reasoningEffortLow,
      ReasoningEffort.medium => onOff ? l10n.reasoningEffortOn : l10n.reasoningEffortMedium,
      ReasoningEffort.high => l10n.reasoningEffortHigh,
      ReasoningEffort.max => l10n.reasoningEffortMax,
    };
  }

  /// Where the stored level sits on [ladder]. A level this wire does not tell
  /// apart shows as the rung that sends the same request: Off where Off is
  /// withheld like Default, any intensity where thinking is only on or off.
  /// The stored value itself is left alone until the slider is moved.
  int _rungIndex(List<ReasoningEffort?> ladder) {
    final current = ReasoningEffort.tryParse(reasoningEffort);
    final exact = ladder.indexOf(current);
    if (exact >= 0) return exact;
    if (current == ReasoningEffort.off) return 0;
    final on = ladder.indexOf(ReasoningEffort.medium);
    return on >= 0 ? on : 0;
  }

  /// Always present (`1a`). The stops are the model's: only the rungs its
  /// wire tells apart. Where no rung reaches the request the slider greys out
  /// with its thumb held at Off, and lights up again when the channel or the
  /// kind changes to one that takes reasoning.
  Widget _reasoningSection(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final ladder = _reasoningLadder;
    final supported = ladder.isNotEmpty;
    final rungs = supported ? ladder : _allRungs;
    final onOff = supported && !ladder.contains(ReasoningEffort.low);
    final index = supported ? _rungIndex(ladder) : _allRungs.indexOf(ReasoningEffort.off);
    final current = _rungLabel(rungs[index], short: false, onOff: onOff);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _caption(
                l10n.reasoningEffort,
                tone: supported ? AppSectionTone.accent : AppSectionTone.neutral,
                scope: _scope(route: true),
              ),
            ),
            const SizedBox(width: AppSpace.s10),
            Text(
              supported ? current : l10n.reasoningEffortUnavailable,
              style: theme.textTheme.labelSmall?.mono.copyWith(
                color: supported ? theme.colorScheme.onSurface : theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditTrackSlider(
          stopCount: rungs.length,
          value: index.toDouble(),
          snap: true,
          highlight: supported ? index : null,
          labels: [for (final rung in rungs) _rungLabel(rung, short: true, onOff: onOff)],
          semanticLabel: l10n.reasoningEffort,
          semanticValueOf: (v) => supported
              ? _rungLabel(rungs[v.round()], short: false, onOff: onOff)
              : l10n.reasoningEffortUnavailable,
          onChanged: !supported
              ? null
              : (v) => _rebuild(() => reasoningEffort = ladder[v.round()]?.name),
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditHelperText(
          supported ? l10n.reasoningEffortDesc : l10n.reasoningEffortUnsupported,
          muted: !supported,
        ),
        // The Responses ladder is not trimmed per model, so the one known
        // guaranteed 400 is said here instead (reasoning 03 §7.1).
        if (supported && _onResponsesFace) ...[
          const SizedBox(height: AppSpace.s6),
          ModelEditHelperText(l10n.reasoningEffortResponsesHint),
        ],
      ],
    );
  }

  /// Whether a reasoning level would reach the request: the channel's chat
  /// wire consumes it (the dispatcher's answer, not a copy), and the kind
  /// sends the model down that chat wire at all.
  bool get _reasoningSupported => _reasoningLadder.isNotEmpty;

  /// Whether the model's requests take the Responses face — the dispatcher's
  /// resolution, not a copy of it.
  bool get _onResponsesFace {
    final routed = _routed;
    if (routed == null) return false;
    return LLMDispatcher.resolvedChatFace(
          channelType: routed.channelType,
          modelId: idCtrl.text.trim(),
          tag: tag,
          wireProtocol: _dispatchPin,
        ) ==
        WireProtocol.openaiResponses;
  }

  /// The rungs that each send a different request on this channel for this
  /// id and kind: the dispatcher's answer, empty where none reaches the wire.
  List<ReasoningEffort?> get _reasoningLadder {
    final routed = _routed;
    if (routed == null) return const [];
    return LLMDispatcher.reasoningLadder(
      channelType: routed.channelType,
      modelId: idCtrl.text.trim(),
      tag: tag,
      // The face the model rides decides the spelling, and so the rungs: a
      // Bailian model on its ④ route has two, on ① three, never six.
      wireProtocol: _dispatchPin,
    );
  }
}

/// Every rung, in the order a greyed slider shows them.
const List<ReasoningEffort?> _allRungs = [
  null,
  ReasoningEffort.off,
  ReasoningEffort.low,
  ReasoningEffort.medium,
  ReasoningEffort.high,
  ReasoningEffort.max,
];
