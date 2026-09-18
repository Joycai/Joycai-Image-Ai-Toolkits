part of '../channel_wizard_dialog.dart';

/// Choosing who to talk to: the provider list and, for a provider with
/// more than one way in, the variant cards.
extension _ProviderSteps on _ChannelWizardDialogState {
  // --- Step 1: provider ------------------------------------------------------

  /// Presets matching the search box, in declaration order. An empty query
  /// matches everything, which is what keeps every preset reachable — the
  /// picker has gone blind to whole vendors before, when it was driven by
  /// hand-written id lists instead of the catalogue itself.
  List<ChannelProviderPreset> _filteredPresets(AppLocalizations l10n) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return kListedChannelProviderPresets;
    return kListedChannelProviderPresets.where((p) {
      final haystack = [
        p.id,
        p.channelType,
        channelProviderTitle(l10n, p.id),
        channelProviderSubtitle(l10n, p),
        p.defaultEndpoint ?? '',
        // The names a provider is also known by. Folding the separate
        // "Qianwen Platform" row into DashScope only works because 千问 /
        // Qwen / 通义 still land on it.
        ...p.searchAliases,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Widget _buildProviderStep(AppLocalizations l10n) {
    final matches = _filteredPresets(l10n);

    final rows = <Widget>[];
    for (final group in ChannelProviderGroup.values) {
      final inGroup = matches.where((p) => p.group == group).toList();
      if (inGroup.isEmpty) continue;
      rows.add(ChannelProviderGroupCaption(
        l10n: l10n,
        group: group,
        count: inGroup.length,
        first: rows.isEmpty,
      ));
      for (final preset in inGroup) {
        rows.add(ChannelProviderRow(
          l10n: l10n,
          preset: preset,
          selected: preset.id == _selectedProviderId,
          onTap: () => _selectProvider(preset.id),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, AppSpace.s10),
          child: ChannelField(
            controller: _searchCtrl,
            hint: l10n.searchProvidersAlias,
            prefixIcon: Icons.search,
            onChanged: (_) => _rebuild(() {}),
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? ChannelProviderNoMatch(
                  l10n: l10n,
                  query: _searchCtrl.text.trim(),
                  onUseCustom: _useCustomProvider,
                )
              // Built eagerly: sixteen rows is nothing, and a lazy list leaves
              // the rows past the fold unbuilt — which is how a preset goes
              // missing from anything that looks for it without scrolling.
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
        ),
      ],
    );
  }

  // --- Step 2: way in (variant presets only) ---------------------------------

  Widget _buildVariantStep(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preset = _preset;
    final selected = _variant;
    if (selected == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelSectionLabel(channelProviderVariantTitle(l10n, preset.id)),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, variant) in preset.variants.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpace.s6 + 2),
                Expanded(
                  child: _buildVariantCard(
                    l10n,
                    variant,
                    selected: variant.id == selected.id,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        // What the choice resolves to: the stored protocol and the address
        // it will be sent to, before the next step asks for the key.
        Container(
          padding: const EdgeInsets.all(AppSpace.s10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.variantResultLabel,
                style: theme.textTheme.labelSmall?.mono
                    .copyWith(color: colorScheme.outline),
              ),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channelTypeLabel(l10n, _resolvedChannelType()),
                      style: theme.textTheme.labelSmall?.mono
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _endpointPreview(),
                      style: theme.textTheme.labelSmall?.mono
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The address the current face resolves to, or the version path a relay
  /// will append to a host not typed yet.
  String _endpointPreview() {
    if (_endpointCtrl.text.trim().isNotEmpty) return _resolvedEndpoint();
    final suffix = _endpointSuffix;
    return suffix.isEmpty ? '—' : 'https://…$suffix';
  }

  Widget _buildVariantCard(
    AppLocalizations l10n,
    ChannelProviderVariant variant, {
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preset = _preset;

    return Material(
      color: selected ? colorScheme.accentTint : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectVariant(variant.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.s10, vertical: AppSpace.s6 + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                channelProviderVariantLabel(l10n, preset.id, variant.id),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? colorScheme.onAccentTint
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                channelProviderVariantCaption(l10n, preset, variant),
                style: theme.textTheme.labelSmall?.mono.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
