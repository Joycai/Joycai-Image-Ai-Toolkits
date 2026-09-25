part of '../channel_wizard_dialog.dart';

/// The confirmation shown before anything is written.
extension _Preview on _ChannelWizardDialogState {
  // --- Preview ---------------------------------------------------------------

  /// `Ready to add this channel?` — every value that will be stored, as it
  /// will be stored, before anything is written.
  Future<bool?> _showPreview() {
    final l10n = widget.l10n;
    return showDialog<bool>(
      context: context,
      animationStyle: appDialogAnimation(context),
      builder: (dialogContext) => AppDialog(
        icon: Icons.fact_check_outlined,
        title: l10n.previewReady,
        subtitle: channelProviderTitle(l10n, _preset.id),
        maxWidth: 420,
        content: _buildPreviewSummary(dialogContext, l10n),
        actions: [
          AppButton(
            label: l10n.back,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          AppButton(
            label: l10n.addChannel,
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSummary(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyStyle = theme.textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant);
    final valueStyle = theme.textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurface,
    );
    final key = _apiKeyCtrl.text.trim();

    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: keyStyle),
          ),
          const SizedBox(width: AppSpace.s10),
          Expanded(child: value),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.s10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              row(l10n.displayName, Text(_resolvedName(), style: valueStyle)),
              row(l10n.tag, Text(_resolvedTag(), style: valueStyle)),
              if (_plannedRoutes.entries.length > 1)
                row(
                  l10n.routeSectionTitle,
                  Wrap(
                    spacing: AppSpace.s4,
                    runSpacing: AppSpace.s4,
                    children: [
                      for (final k in _plannedRoutes.kinds)
                        AppRouteBadge(
                          label: routeLabel(l10n, k, short: true),
                          state: k == _plannedRoutes.primary.kind
                              ? RouteBadgeState.current
                              : RouteBadgeState.configured,
                        ),
                    ],
                  ),
                )
              else
                row(
                  l10n.protocolField,
                  Text(channelTypeLabel(l10n, _resolvedChannelType()), style: valueStyle),
                ),
              row(l10n.endpointUrl, Text(_plannedRoutes.primaryAddress, style: valueStyle)),
              row(
                l10n.apiKey,
                Text(
                  key.isEmpty ? '—' : '••••••••',
                  style: valueStyle?.copyWith(
                    color: key.isEmpty ? colorScheme.outline : context.semantic.onSuccessContainer,
                  ),
                ),
              ),
              row(
                l10n.enableDiscovery,
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Icon(
                    _enableDiscovery ? Icons.check : Icons.remove,
                    size: AppSize.iconSm,
                    color: _enableDiscovery
                        ? context.semantic.onSuccessContainer
                        : colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (key.isEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          ChannelNoteStrip(l10n.previewEmptyKeyNote),
        ],
      ],
    );
  }
}
