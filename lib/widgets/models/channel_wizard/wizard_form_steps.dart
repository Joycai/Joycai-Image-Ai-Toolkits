part of '../channel_wizard_dialog.dart';

/// Filling the channel in: endpoint and key, then tag and appearance.
extension _FormSteps on _ChannelWizardDialogState {
  // --- Step 3: endpoint & key ------------------------------------------------

  Widget _buildConnectionStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEndpointField(l10n),
        const SizedBox(height: AppSpace.s16),
        ChannelLabelledField(
          // The field stays for the local runtimes rather than disappearing:
          // vanishing would leave someone who *has* put reverse-proxy auth in
          // front with nowhere to put the key.
          label: _keyOptional
              ? '${l10n.apiKey} · ${l10n.apiKeyOptional}'
              : l10n.apiKey,
          helper: _keyOptional ? l10n.apiKeyLocalNote : l10n.apiKeyStorageNotice,
          child: ChannelField(
            controller: _apiKeyCtrl,
            mono: true,
            obscurable: true,
            hint: _keyOptional ? l10n.apiKeyLocalPlaceholder : null,
            errorText: _apiKeyError(l10n),
            onChanged: (_) => _rebuild(_clearProbe),
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        Row(
          children: [
            AppButton(
              label: l10n.probeChannel,
              icon: Icons.network_check,
              variant: AppButtonVariant.secondary,
              accentLabel: true,
              loading: _probing,
              onPressed: _endpointMissing ? null : _runProbe,
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Text(
                l10n.probeSkippableNote,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
        if (_probe != null) ...[
          const SizedBox(height: AppSpace.s10),
          ChannelProbeResultCard(
            l10n: l10n,
            result: _probe!,
            onRetry: _probing ? null : _runProbe,
          ),
        ],
      ],
    );
  }

  Widget _buildEndpointField(AppLocalizations l10n) {
    final preset = _preset;
    final variant = _variant;
    // A relay is one whose *resolved* face appends a version path — which for
    // NewAPI is decided by the format, not by the preset.
    final isRelay = _endpointSuffix.isNotEmpty;
    final family = Vendors.byId(_resolvedChannelType()).family;
    final isMidjourney = family == ProtocolFamily.midjourney;
    final presetEndpoint = variant?.defaultEndpoint ?? preset.defaultEndpoint;
    final edited = presetEndpoint != null &&
        _endpointCtrl.text.trim() != presetEndpoint;

    final helper = isRelay
        ? l10n.newApiBaseHint
        : isMidjourney
            ? l10n.midjourneyEndpointHint
            : presetEndpoint != null
                ? l10n.endpointPresetValue(presetEndpoint)
                : switch (family) {
                    ProtocolFamily.gemini => l10n.googleV1BetaHint,
                    ProtocolFamily.anthropic => l10n.anthropicV1Hint,
                    ProtocolFamily.dashscope => l10n.dashscopeApiV1Hint,
                    _ => l10n.openaiV1Hint,
                  };

    return ChannelLabelledField(
      label: isRelay ? l10n.newApiBaseUrl : l10n.endpointUrl,
      badge: edited
          ? ChannelBadge(
              l10n.presetEndpointModified,
              tone: ChannelBadgeTone.warning,
            )
          : null,
      trailing: edited
          ? AppButton(
              label: l10n.restorePresetEndpoint,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: () => _rebuild(() {
                _applyPresetEndpoint();
                _clearProbe();
              }),
            )
          : null,
      helper: helper,
      child: ChannelField(
        controller: _endpointCtrl,
        mono: true,
        hint: isRelay || isMidjourney
            ? 'https://your-newapi-host.com'
            : 'https://your-api.com/v1',
        errorText: _endpointError(l10n),
        onChanged: (_) => _rebuild(_clearProbe),
      ),
    );
  }

  // --- Step 4: tag & appearance ----------------------------------------------

  Widget _buildAppearanceStep(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ChannelLabelledField(
                label: l10n.displayName,
                child: ChannelField(
                  controller: _nameCtrl,
                  hint: l10n.nameHint,
                  onChanged: (_) => _rebuild(() {}),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              flex: 2,
              child: ChannelLabelledField(
                label: l10n.tag,
                child: ChannelField(
                  controller: _tagCtrl,
                  mono: true,
                  hint: l10n.tagHint,
                  onChanged: (_) => _rebuild(() {}),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s16),
        ChannelFieldLabel(l10n.tagColor),
        const SizedBox(height: AppSpace.s4),
        ChannelTagColorPicker(
          l10n: l10n,
          selectedColor: _tagColor,
          onColorChanged: (color) => _rebuild(() {
            _tagColor = color;
            _tagColorChosen = true;
          }),
        ),
        const SizedBox(height: AppSpace.s16),
        ChannelFieldLabel(l10n.channelListPreview),
        const SizedBox(height: AppSpace.s4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          // What will actually be stored: an empty name or tag falls back to
          // the provider's, and the preview says so rather than going blank.
          child: ChannelListRowPreview(
            name: _resolvedName(),
            tag: _resolvedTag(),
            color: Color(_tagColor),
            subline: l10n.countModels(0),
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        ChannelToggleCard(
          title: l10n.enableDiscovery,
          description: l10n.enableDiscoveryDesc,
          value: _enableDiscovery,
          onChanged: (v) => _rebuild(() => _enableDiscovery = v),
        ),
      ],
    );
  }
}
