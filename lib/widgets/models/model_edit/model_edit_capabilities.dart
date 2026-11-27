part of '../model_edit_dialog.dart';

/// Behavior toggles, collapsible transport options and the reasoning ladder.
extension _CapabilitySections on _ModelEditDialogState {
  /// Low-frequency streaming and standard request compatibility toggles,
  /// collapsed by default to keep the form focused.
  Widget _transportSection(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ignoredBy = _streamIgnoredBy;
    final asyncPinned = _asyncImagePinned;
    final streamState = ignoredBy != null
        ? l10n.transportStreamIgnoredShort
        : (supportsStream ? l10n.reasoningEffortOn : l10n.reasoningEffortOff);
    final standardState = supportsStandard ? l10n.reasoningEffortOn : l10n.reasoningEffortOff;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ModelEditCard(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                expanded: _transportExpanded,
                label: l10n.transportCompatibility,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    onTap: () => _rebuild(() => _transportExpanded = !_transportExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.s10,
                        vertical: AppSpace.s10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.transportCompatibility,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.s6),
                          Flexible(
                            child: Text(
                              l10n.transportSummary(streamState, standardState),
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.mono.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpace.s6),
                          AppDisclosureChevron(
                            open: _transportExpanded,
                            size: AppSize.iconMd,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: AppMotion.durationOf(context, AppMotion.reveal),
                curve: AppMotion.enter,
                alignment: Alignment.topCenter,
                child: !_transportExpanded
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.s10,
                              vertical: AppSpace.s4,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // With a non-streaming route pinned the toggle
                                // is inert: the value is preserved, not
                                // rewritten — switch back to auto and it comes
                                // back untouched.
                                ModelEditToggleRow(
                                  title: l10n.supportsStreaming,
                                  tooltip: l10n.supportsStreamingDesc,
                                  value: supportsStream,
                                  dimmed: ignoredBy != null,
                                  onChanged: ignoredBy != null
                                      ? null
                                      : (v) => _rebuild(() => supportsStream = v),
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
                        ],
                      ),
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
                  padding: const EdgeInsets.only(top: AppSpace.s6),
                  child: ModelEditNotice(
                    tone: ModelEditTone.info,
                    text: l10n.protocolStreamIgnored(wireProtocolLabel(l10n, ignoredBy)),
                  ),
                ),
              if (asyncPinned)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s6),
                  child: ModelEditNotice(
                    tone: ModelEditTone.info,
                    text: l10n.protocolAsyncQueueNote,
                  ),
                ),
              const SizedBox(width: double.infinity),
            ],
          ),
        ),
      ],
    );
  }

  /// The model as it would be saved right now, for route/protocol queries.
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
      contextWindow: _isChatGroup
          ? (_contextValid ? ContextBudget.store(contextMode, _contextTokens ?? 0) : null)
          : widget.model?.contextWindow,
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

  // --- Behavior & Extensions ------------------------------------------------

  Widget _behaviorSection(BuildContext context) {
    final l10n = widget.l10n;
    final scheme = Theme.of(context).colorScheme;
    final showThinking = _isAnthropicChannel;
    final search = _webSearch;
    final showSearch = search != ServerWebSearch.unsupported || (_routeMode && _anyRouteSearches);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.behaviorAndExtensions),
        const SizedBox(height: AppSpace.s6),
        ModelEditCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ModelEditToggleRow(
                title: l10n.supportsMultimodalInput,
                description: l10n.supportsMultimodalInputDesc,
                value: _isMultimodal,
                onChanged: _setMultimodal,
              ),
              AnimatedSize(
                duration: AppMotion.durationOf(context, AppMotion.reveal),
                curve: AppMotion.enter,
                alignment: Alignment.topCenter,
                child: !_isMultimodal
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: AppSpace.s4,
                          top: AppSpace.s10,
                        ),
                        child: Container(
                          padding: const EdgeInsetsDirectional.only(start: 10),
                          decoration: BoxDecoration(
                            border: BorderDirectional(
                              start: BorderSide(color: scheme.accentRule, width: 2),
                            ),
                          ),
                          child: ModelEditToggleRow(
                            title: l10n.forceViewAllImages,
                            description: l10n.forceViewAllImagesDesc,
                            value: forceViewAllImages,
                            onChanged: (v) => _rebuild(() => forceViewAllImages = v),
                          ),
                        ),
                      ),
              ),
              if (showThinking) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.s6),
                  child: Divider(height: 1),
                ),
                ModelEditToggleRow(
                  title: l10n.enableThinking,
                  description: l10n.enableThinkingDesc,
                  value: reasoningEffort != null && reasoningEffort != 'off',
                  dimmed: !_reasoningSupported,
                  onChanged: !_reasoningSupported
                      ? null
                      : (v) => _rebuild(
                          () => reasoningEffort = v
                              ? ((reasoningEffort != null && reasoningEffort != 'off')
                                    ? reasoningEffort
                                    : 'medium')
                              : null,
                        ),
                ),
              ],
              if (showSearch) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.s6),
                  child: Divider(height: 1),
                ),
                ModelEditToggleRow(
                  title: l10n.enableWebSearch,
                  // A traceless switch says so where it is turned on: the reply
                  // carries no sources, and nothing shows whether it searched.
                  description: search == ServerWebSearch.traceless
                      ? '${l10n.enableWebSearchDesc} ${l10n.enableWebSearchTracelessHint}'
                      : l10n.enableWebSearchDesc,
                  value: enableWebSearch,
                  onChanged: (v) => _rebuild(() => enableWebSearch = v),
                ),
                if (_routeMode) ...[const SizedBox(height: AppSpace.s6), _webSearchMatrix(context)],
              ],
            ],
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

  /// Reasoning effort slider when supported; collapses to a quiet 1-line row
  /// when the current model/protocol does not accept reasoning parameters.
  Widget _reasoningSection(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ladder = _reasoningLadder;
    final supported = ladder.isNotEmpty;

    if (!supported) {
      return ModelEditCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 9),
        child: Row(
          children: [
            Text(
              l10n.reasoningEffort,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Text(
                l10n.reasoningEffortNotSupportedShort,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
              ),
            ),
          ],
        ),
      );
    }

    final onOff = !ladder.contains(ReasoningEffort.low);
    final index = _rungIndex(ladder);
    final current = _rungLabel(ladder[index], short: false, onOff: onOff);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _caption(l10n.reasoningEffort, scope: _scope(route: true))),
            const SizedBox(width: AppSpace.s10),
            Text(
              current,
              style: theme.textTheme.labelSmall?.mono.copyWith(color: scheme.onSurface),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ModelEditTrackSlider(
                stopCount: ladder.length,
                value: index.toDouble(),
                snap: true,
                highlight: index,
                labels: [for (final rung in ladder) _rungLabel(rung, short: true, onOff: onOff)],
                semanticLabel: l10n.reasoningEffort,
                semanticValueOf: (v) => _rungLabel(ladder[v.round()], short: false, onOff: onOff),
                onChanged: (v) => _rebuild(() => reasoningEffort = ladder[v.round()]?.name),
              ),
              const SizedBox(height: AppSpace.s6),
              ModelEditHelperText(l10n.reasoningEffortDesc),
              // The Responses ladder is not trimmed per model, so the one
              // known guaranteed 400 is said here instead (reasoning 03 §7.1).
              if (_onResponsesFace) ...[
                const SizedBox(height: AppSpace.s6),
                ModelEditHelperText(l10n.reasoningEffortResponsesHint),
              ],
            ],
          ),
        ),
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
