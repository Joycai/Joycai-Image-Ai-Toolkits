import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/channel_dialect.dart';
import '../../state/app_state.dart';
import '../api_key_field.dart';
import '../app_segmented_control.dart';
import 'channel_form_sections.dart';

/// A provider preset selectable on the wizard's first step. Merges the old
/// protocol + provider steps: picking a preset implies both the channel
/// dialect and (when known) the endpoint, so the flow is 3 steps instead
/// of 5: provider → connection → config.
class _ProviderPreset {
  final String id;
  final String channelType;

  /// Non-null for hosted providers with a well-known endpoint; null when the
  /// user must supply one (relays, proxies, custom).
  final String? fixedEndpoint;

  /// Version-path suffix auto-appended to New API hosts ('' = keep verbatim).
  final String endpointSuffix;
  final IconData icon;

  const _ProviderPreset({
    required this.id,
    required this.channelType,
    this.fixedEndpoint,
    this.endpointSuffix = '',
    required this.icon,
  });

  bool get needsEndpoint => fixedEndpoint == null;
}

const _presets = <_ProviderPreset>[
  _ProviderPreset(
    id: 'openai-official',
    channelType: ChannelDialect.openAIRest,
    fixedEndpoint: 'https://api.openai.com/v1',
    icon: Icons.api,
  ),
  _ProviderPreset(
    id: 'xai-official',
    channelType: ChannelDialect.xaiApi,
    fixedEndpoint: 'https://api.x.ai/v1',
    icon: Icons.rocket_launch_outlined,
  ),
  _ProviderPreset(
    id: 'google-compatible',
    channelType: ChannelDialect.openAIRest,
    fixedEndpoint: 'https://generativelanguage.googleapis.com/v1beta/openai',
    icon: Icons.swap_horiz,
  ),
  _ProviderPreset(
    id: 'newapi-openai',
    channelType: ChannelDialect.newApiOpenAI,
    endpointSuffix: '/v1',
    icon: Icons.hub_outlined,
  ),
  _ProviderPreset(
    id: 'google-official',
    channelType: ChannelDialect.googleRest,
    fixedEndpoint: 'https://generativelanguage.googleapis.com/v1beta',
    icon: Icons.auto_awesome,
  ),
  _ProviderPreset(
    id: 'newapi-gemini',
    channelType: ChannelDialect.newApiGemini,
    endpointSuffix: '/v1beta',
    icon: Icons.hub_outlined,
  ),
  _ProviderPreset(
    id: 'midjourney-proxy',
    channelType: ChannelDialect.midjourneyProxy,
    icon: Icons.brush_outlined,
  ),
  _ProviderPreset(
    id: 'custom',
    channelType: ChannelDialect.openAIRest, // resolved by _customProtocol
    icon: Icons.settings_input_component,
  ),
];

class ChannelWizardDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final AppState appState;

  const ChannelWizardDialog({
    super.key,
    required this.l10n,
    required this.appState,
  });

  @override
  State<ChannelWizardDialog> createState() => _ChannelWizardDialogState();
}

class _ChannelWizardDialogState extends State<ChannelWizardDialog> {
  int _currentStep = 0;
  static const int _totalSteps = 3;

  String _selectedProviderId = 'openai-official';

  /// Dialect for the `custom` preset (OpenAI- or Gemini-shaped REST).
  String _customProtocol = ChannelDialect.openAIRest;

  final TextEditingController _endpointCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _tagCtrl = TextEditingController();
  bool _enableDiscovery = true;
  int _tagColor = AppConstants.tagColors.first.toARGB32();

  _ProviderPreset get _preset =>
      _presets.firstWhere((p) => p.id == _selectedProviderId);

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _apiKeyCtrl.dispose();
    _nameCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  // --- Flow -----------------------------------------------------------------

  bool _isNextEnabled() {
    if (_currentStep == 1) {
      if (_preset.needsEndpoint && _endpointCtrl.text.trim().isEmpty) {
        return false;
      }
      if (_apiKeyCtrl.text.trim().isEmpty) return false;
    }
    return true;
  }

  void _next() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  /// Normalizes a New API base URL to the correct versioned path. If the user
  /// already typed a full path ending in `/v1` or `/v1beta`, it is respected;
  /// otherwise [suffix] is appended.
  String _resolveNewApiEndpoint(String input, String suffix) {
    var base = input.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/v1') || base.endsWith('/v1beta')) return base;
    return '$base$suffix';
  }

  String _resolvedEndpoint() {
    final preset = _preset;
    if (preset.fixedEndpoint != null) return preset.fixedEndpoint!;
    if (preset.endpointSuffix.isNotEmpty) {
      return _resolveNewApiEndpoint(_endpointCtrl.text, preset.endpointSuffix);
    }
    var raw = _endpointCtrl.text.trim();
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  String _resolvedChannelType() {
    if (_selectedProviderId == 'custom') return _customProtocol;
    return _preset.channelType;
  }

  Future<void> _finish() async {
    final data = {
      'display_name': _nameCtrl.text.trim().isEmpty
          ? _selectedProviderId
          : _nameCtrl.text.trim(),
      'endpoint': _resolvedEndpoint(),
      'api_key': _apiKeyCtrl.text.trim(),
      'type': _resolvedChannelType(),
      'enable_discovery': _enableDiscovery ? 1 : 0,
      'tag': _tagCtrl.text.trim().isEmpty
          ? _selectedProviderId.split('-').first
          : _tagCtrl.text.trim(),
      'tag_color': _tagColor,
    };

    await widget.appState.addChannel(data);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  // --- Labels ---------------------------------------------------------------

  String _providerTitle(AppLocalizations l10n, String id) {
    switch (id) {
      case 'openai-official':
        return l10n.providerOpenAIOfficial;
      case 'xai-official':
        return l10n.providerXaiOfficial;
      case 'google-compatible':
        return l10n.providerGoogleCompatible;
      case 'newapi-openai':
        return l10n.providerNewApiOpenAI;
      case 'google-official':
        return l10n.providerGoogleOfficial;
      case 'newapi-gemini':
        return l10n.providerNewApiGemini;
      case 'midjourney-proxy':
        return l10n.protocolMidjourney;
      default:
        return l10n.providerCustom;
    }
  }

  String _providerSubtitle(AppLocalizations l10n, _ProviderPreset p) {
    switch (p.id) {
      case 'openai-official':
        return 'api.openai.com';
      case 'xai-official':
        return l10n.providerXaiOfficialDesc;
      case 'google-compatible':
        return l10n.providerGoogleCompatibleDesc;
      case 'google-official':
        return 'generativelanguage.googleapis.com';
      case 'newapi-openai':
      case 'newapi-gemini':
        return l10n.providerNewApiDesc;
      case 'midjourney-proxy':
        return l10n.protocolMidjourneyDesc;
      default:
        return l10n.providerCustomDesc;
    }
  }

  String _stepSubtitle(AppLocalizations l10n) {
    switch (_currentStep) {
      case 0:
        return l10n.stepProvider;
      case 1:
        return l10n.stepConnection;
      default:
        return l10n.stepConfig;
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isMobile = Responsive.isMobile(context);

    final content = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: KeyedSubtree(
          key: ValueKey(_currentStep),
          child: switch (_currentStep) {
            0 => _buildProviderStep(l10n),
            1 => _buildConnectionStep(l10n),
            _ => _buildConfigStep(l10n),
          },
        ),
      ),
    );

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.addChannel),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildStepCaption(l10n),
              ),
            ),
            Expanded(child: content),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildStepDots(),
                    const Spacer(),
                    if (_currentStep > 0) ...[
                      OutlinedButton(onPressed: _back, child: Text(l10n.back)),
                      const SizedBox(width: 12),
                    ],
                    FilledButton(
                      onPressed: _isNextEnabled() ? _next : null,
                      child: Text(_currentStep == _totalSteps - 1
                          ? l10n.finish
                          : l10n.next),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(l10n.addChannel),
          const Spacer(),
          _buildStepCaption(l10n),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      // Fixed size so the dialog doesn't resize between steps; shorter steps
      // simply leave whitespace below (content is top-aligned and scrolls
      // when it exceeds the height).
      content: SizedBox(width: 560, height: 520, child: content),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actions: [
        Row(
          children: [
            _buildStepDots(),
            const Spacer(),
            if (_currentStep > 0)
              TextButton(onPressed: _back, child: Text(l10n.back))
            else
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isNextEnabled() ? _next : null,
              child: Text(
                  _currentStep == _totalSteps - 1 ? l10n.finish : l10n.next),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepCaption(AppLocalizations l10n) {
    return Text(
      '${_currentStep + 1}/$_totalSteps · ${_stepSubtitle(l10n)}',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.normal,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }

  Widget _buildStepDots() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < _totalSteps; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == _currentStep ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _currentStep
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (i < _totalSteps - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }

  // --- Step 1: provider selection -------------------------------------------

  Widget _buildProviderStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupLabel(l10n.protocolOpenAI),
        _buildProviderGrid(l10n, const [
          'openai-official',
          'xai-official',
          'google-compatible',
          'newapi-openai',
        ]),
        const SizedBox(height: 14),
        _buildGroupLabel(l10n.protocolGoogle),
        _buildProviderGrid(l10n, const ['google-official', 'newapi-gemini']),
        const SizedBox(height: 14),
        _buildGroupLabel(l10n.providerGroupOther),
        _buildProviderGrid(l10n, const ['midjourney-proxy', 'custom']),
      ],
    );
  }

  Widget _buildGroupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildProviderGrid(AppLocalizations l10n, List<String> ids) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 440;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: twoColumns ? 2 : 1,
            mainAxisExtent: 64,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: ids.length,
          itemBuilder: (context, index) {
            final preset = _presets.firstWhere((p) => p.id == ids[index]);
            return _buildProviderCard(l10n, preset);
          },
        );
      },
    );
  }

  Widget _buildProviderCard(AppLocalizations l10n, _ProviderPreset preset) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedProviderId == preset.id;

    return InkWell(
      onTap: () => setState(() => _selectedProviderId = preset.id),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withAlpha(100),
            width: isSelected ? 2 : 1,
          ),
          color:
              isSelected ? colorScheme.primaryContainer.withAlpha(40) : null,
        ),
        child: Row(
          children: [
            Icon(
              preset.icon,
              size: 20,
              color: isSelected ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _providerTitle(l10n, preset.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    _providerSubtitle(l10n, preset),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, color: colorScheme.primary, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  // --- Step 2: connection ----------------------------------------------------

  Widget _buildConnectionStep(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final preset = _preset;
    final isNewApi = preset.endpointSuffix.isNotEmpty;
    final isCustom = preset.id == 'custom';
    final isMidjourney = preset.id == 'midjourney-proxy';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected provider recap.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(preset.icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                _providerTitle(l10n, preset.id),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (preset.fixedEndpoint != null)
                Flexible(
                  child: Text(
                    preset.fixedEndpoint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (isCustom) ...[
          Text(l10n.channelType,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          AppSegmentedControl<String>(
            segments: [
              AppSegment(value: ChannelDialect.openAIRest, label: l10n.protocolOpenAI),
              AppSegment(value: ChannelDialect.googleRest, label: l10n.protocolGoogle),
            ],
            value: _customProtocol,
            onChanged: (v) => setState(() => _customProtocol = v),
            expand: true,
          ),
          const SizedBox(height: 20),
        ],

        if (preset.needsEndpoint) ...[
          TextField(
            controller: _endpointCtrl,
            decoration: InputDecoration(
              labelText: isNewApi ? l10n.newApiBaseUrl : l10n.endpointUrl,
              hintText: isNewApi || isMidjourney
                  ? 'https://your-newapi-host.com'
                  : 'https://your-api.com/v1',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
              helperText: isNewApi
                  ? l10n.newApiBaseHint
                  : isMidjourney
                      ? l10n.midjourneyEndpointHint
                      : (_customProtocol == ChannelDialect.googleRest
                          ? l10n.googleV1BetaHint
                          : l10n.openaiV1Hint),
              helperMaxLines: 3,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
        ],

        ApiKeyField(
          controller: _apiKeyCtrl,
          label: l10n.enterApiKey,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.apiKeyStorageNotice,
          style: TextStyle(fontSize: 12, color: colorScheme.outline),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: Text(l10n.enableDiscovery, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            l10n.enableDiscoveryDesc,
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
          value: _enableDiscovery,
          onChanged: (v) => setState(() => _enableDiscovery = v),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }

  // --- Step 3: config + summary ----------------------------------------------

  Widget _buildConfigStep(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChannelSectionLabel(l10n.sectionAppearance),
        ChannelAppearanceSection(
          l10n: l10n,
          nameCtrl: _nameCtrl,
          tagCtrl: _tagCtrl,
          tagColor: _tagColor,
          onColorChanged: (color) => setState(() => _tagColor = color),
        ),
        const SizedBox(height: 20),

        // Summary of what will be created.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: colorScheme.primaryContainer.withAlpha(100)),
          ),
          child: Column(
            children: [
              _buildSummaryRow(
                  l10n.name,
                  _nameCtrl.text.trim().isEmpty
                      ? _selectedProviderId
                      : _nameCtrl.text.trim()),
              _buildSummaryRow(
                  l10n.stepProvider, _providerTitle(l10n, _selectedProviderId)),
              _buildSummaryRow(l10n.endpointUrl, _resolvedEndpoint()),
              _buildSummaryRow(l10n.channelType, _resolvedChannelType()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: colorScheme.outline)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
