part of '../video_config_panel.dart';

/// The model card: the picker and, expanded, the model's declared settings.
extension _ModelSection on _VideoConfigPanelState {
  Widget _buildModelSection({
    required AppLocalizations l10n,
    required List<LLMModel> videoModels,
    required List<LLMChannel> videoChannels,
    required LLMChannel? selectedChannel,
    required LLMModel? selectedModel,
    required LLMModel? modelInChannel,
    required ModelCapabilities caps,
    required AppState appState,
    required TextStyle? captionStyle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final selectedChannelId = selectedChannel?.id;
    final collapsedModelName = _isModelSettingsExpanded ? null : selectedModel?.modelName;

    // Some families (e.g. grok-imagine-video-1.5) declare their own
    // aspectRatio/resolution videoParams with a different option set than
    // the shared Veo dropdowns below — hide the shared control for whichever
    // key that family overrides so the panel doesn't show two conflicting
    // resolution/aspect-ratio pickers.
    final overridesResolution = caps.videoParams.any((p) => p.key == 'resolution');
    final overridesAspectRatio = caps.videoParams.any((p) => p.key == 'aspectRatio');

    // `A2 · 1a`: one two-column grid for every parameter — the shared Veo
    // pair first, then whatever the model declares (duration, quality…).
    final cells = <_ParamCell>[
      if (!overridesResolution)
        _ParamCell(
          label: l10n.videoResolution,
          control: AppDropdown<VeoResolution>(
            size: AppFieldSize.regular,
            height: _kParamControlHeight,
            value: appState.lastVideoResolution,
            items: [
              for (final v in VeoResolution.values) AppDropdownItem(value: v, label: v.value),
            ],
            onChanged: (v) => appState.updateVideoConfig(resolution: v),
          ),
        ),
      if (!overridesAspectRatio)
        _ParamCell(
          label: l10n.videoAspectRatio,
          control: AppDropdown<VeoAspectRatio>(
            size: AppFieldSize.regular,
            height: _kParamControlHeight,
            value: appState.lastVideoAspectRatio,
            items: [
              for (final v in VeoAspectRatio.values) AppDropdownItem(value: v, label: v.value),
            ],
            onChanged: (v) => appState.updateVideoConfig(aspectRatio: v),
          ),
        ),
      // Per-model extras (seconds / quality for openaiVideo; aspectRatio /
      // resolution / seconds slider for grok-imagine-video-1.5; nothing for
      // Veo). `customSize` is not used by any video family and draws nothing.
      if (modelInChannel != null)
        for (final spec in caps.videoParams)
          if (spec.control != ParamControl.customSize)
            _ParamCell(
              label: _videoParamLabel(l10n, spec.labelKey),
              control: _buildVideoParamControl(spec, modelInChannel, appState, l10n),
              spansRow: spec.control == ParamControl.slider ||
                  (spec.control == ParamControl.segmented && spec.options.length > 2),
            ),
    ];

    // `A2 · 1a`: the 11/500 caption and the chevron that folds the card.
    // Collapsed, the header still names the model.
    final header = Semantics(
      expanded: _isModelSettingsExpanded,
      child: InkWell(
        onTap: () => _rebuild(() => _isModelSettingsExpanded = !_isModelSettingsExpanded),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          height: AppSize.iconLg,
          child: Row(
            children: [
              Text(l10n.modelSelection, style: captionStyle),
              const SizedBox(width: AppSpace.s6),
              Expanded(
                child: collapsedModelName == null
                    ? const SizedBox.shrink()
                    : Text(
                        collapsedModelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
              ),
              const SizedBox(width: AppSpace.s4),
              Icon(
                _isModelSettingsExpanded ? Icons.expand_less : Icons.expand_more,
                size: AppSize.iconMd,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );

    final body = Theme(
      // A field inside a card takes the column's ground as its fill, under
      // the theme's own hairline (颜色角色 「输入填充 = col」).
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colorScheme.surfaceContainerLow,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stacked full width and uncaptioned, as `1a` draws them: the
          // channel's dot and the model's name say which is which. The caption
          // is kept for screen readers.
          MergeSemantics(
            child: Semantics(
              label: l10n.channel,
              child: SearchablePickerField<int>(
                size: AppFieldSize.regular,
                selected: selectedChannel == null ? null : channelPickerOption(selectedChannel),
                optionsBuilder: () => videoChannels.map(channelPickerOption).toList(),
                onChanged: (val) {
                  final firstVideoInChannel = videoModels.where((m) => m.channelId == val).firstOrNull;
                  if (firstVideoInChannel != null) {
                    appState.updateVideoConfig(modelId: firstVideoInChannel.id.toString());
                  }
                },
                hint: l10n.selectAChannel,
                searchHint: l10n.searchChannels,
                dialogIcon: Icons.hub_outlined,
                enabled: videoChannels.isNotEmpty,
                badgeStyle: PickerBadge.dot,
              ),
            ),
          ),
          const SizedBox(height: _kCardInnerGap),
          MergeSemantics(
            child: Semantics(
              label: l10n.model,
              child: SearchablePickerField<int>(
                size: AppFieldSize.regular,
                selected: modelInChannel == null ? null : modelPickerOption(modelInChannel),
                // Built on open, not on build: a relay's worth of video models
                // used to be mounted on every frame to render one line.
                optionsBuilder: () => [
                  for (final m in videoModels)
                    if (m.channelId == selectedChannelId && m.id != null) modelPickerOption(m),
                ],
                onChanged: (val) => appState.updateVideoConfig(modelId: val.toString()),
                hint: l10n.selectAModel,
                searchHint: l10n.searchModels,
                dialogIcon: Icons.memory_outlined,
                enabled: videoModels.any((m) => m.channelId == selectedChannelId),
              ),
            ),
          ),
          if (cells.isNotEmpty) ...[
            const SizedBox(height: _kCardInnerGap),
            _paramGrid(cells),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: AlignmentDirectional.topStart,
          child: _isModelSettingsExpanded
              ? Padding(padding: const EdgeInsets.only(top: _kCardInnerGap), child: body)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
