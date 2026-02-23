import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../api_key_field.dart';
import '../color_picker_widget.dart';

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
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 5;

  // Step 1: Protocol
  String _selectedProtocol = 'openai-api-rest'; // 'openai-api-rest', 'google-genai-rest'

  // Step 2: Provider
  String _selectedProvider = 'openai-official'; 
  // OpenAI: 'openai-official', 'google-compatible', 'custom'
  // Google: 'google-official', 'custom'
  final TextEditingController _customEndpointCtrl = TextEditingController();

  // Step 3: API Key
  final TextEditingController _apiKeyCtrl = TextEditingController();

  // Step 4: Config
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _tagCtrl = TextEditingController();
  bool _enableDiscovery = true;
  int _tagColor = AppConstants.tagColors.first.toARGB32();

  @override
  void dispose() {
    _pageController.dispose();
    _customEndpointCtrl.dispose();
    _apiKeyCtrl.dispose();
    _nameCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentStep < _totalSteps - 1) {
      if (_currentStep == 0) {
        // Reset provider selection when protocol changes
        if (_selectedProtocol == 'openai-api-rest') {
          _selectedProvider = 'openai-official';
        } else {
          _selectedProvider = 'google-official';
        }
      }
      
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentStep++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_currentStep > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentStep--);
    }
  }

  Future<void> _finish() async {
    String finalEndpoint = "";
    if (_selectedProtocol == 'openai-api-rest') {
      if (_selectedProvider == 'openai-official') {
        finalEndpoint = 'https://api.openai.com/v1';
      } else if (_selectedProvider == 'google-compatible') {
        finalEndpoint = 'https://generativelanguage.googleapis.com/v1beta/openai';
      } else {
        finalEndpoint = _customEndpointCtrl.text.trim();
      }
    } else {
      if (_selectedProvider == 'google-official') {
        finalEndpoint = 'https://generativelanguage.googleapis.com/v1beta';
      } else {
        finalEndpoint = _customEndpointCtrl.text.trim();
      }
    }

    final data = {
      'display_name': _nameCtrl.text.trim().isEmpty ? _selectedProvider : _nameCtrl.text.trim(),
      'endpoint': finalEndpoint,
      'api_key': _apiKeyCtrl.text.trim(),
      'type': _selectedProtocol,
      'enable_discovery': _enableDiscovery ? 1 : 0,
      'tag': _tagCtrl.text.trim().isEmpty ? _selectedProvider.split('-').first : _tagCtrl.text.trim(),
      'tag_color': _tagColor,
    };

    await widget.appState.addChannel(data);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isMobile = Responsive.isMobile(context);
    
    final dialog = AlertDialog(
      title: _buildHeader(l10n),
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      content: SizedBox(
        width: isMobile ? double.maxFinite : 550,
        height: isMobile ? double.maxFinite : 500,
        child: Column(
          children: [
            LinearProgressIndicator(value: (_currentStep + 1) / _totalSteps),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildProtocolStep(l10n),
                  _buildProviderStep(l10n),
                  _buildApiKeyStep(l10n),
                  _buildConfigStep(l10n),
                  _buildPreviewStep(l10n),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_currentStep > 0)
          TextButton(onPressed: _back, child: Text(l10n.back))
        else
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        
        FilledButton(
          onPressed: _isNextEnabled() ? _next : null,
          child: Text(_currentStep == _totalSteps - 1 ? l10n.finish : l10n.next),
        ),
      ],
    );

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.addChannel),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ),
        body: Column(
          children: [
            LinearProgressIndicator(value: (_currentStep + 1) / _totalSteps),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildProtocolStep(l10n),
                  _buildProviderStep(l10n),
                  _buildApiKeyStep(l10n),
                  _buildConfigStep(l10n),
                  _buildPreviewStep(l10n),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(child: OutlinedButton(onPressed: _back, child: Text(l10n.back)))
                  else
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel))),
                  
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isNextEnabled() ? _next : null,
                      child: Text(_currentStep == _totalSteps - 1 ? l10n.finish : l10n.next),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return dialog;
  }

  bool _isNextEnabled() {
    if (_currentStep == 1 && _selectedProvider == 'custom' && _customEndpointCtrl.text.trim().isEmpty) return false;
    if (_currentStep == 2 && _apiKeyCtrl.text.trim().isEmpty) return false;
    return true;
  }

  Widget _buildHeader(AppLocalizations l10n) {
    String subtitle = "";
    switch (_currentStep) {
      case 0: subtitle = l10n.stepProtocol; break;
      case 1: subtitle = l10n.stepProvider; break;
      case 2: subtitle = l10n.stepApiKey; break;
      case 3: subtitle = l10n.stepConfig; break;
      case 4: subtitle = l10n.stepPreview; break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.addChannel),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline, fontWeight: FontWeight.normal)),
      ],
    );
  }

  Widget _buildProtocolStep(AppLocalizations l10n) {
    return _buildStepContainer(
      children: [
        _buildSelectionCard(
          title: l10n.protocolOpenAI,
          subtitle: l10n.protocolOpenAIDesc,
          icon: Icons.api,
          isSelected: _selectedProtocol == 'openai-api-rest',
          onTap: () => setState(() => _selectedProtocol = 'openai-api-rest'),
        ),
        const SizedBox(height: 16),
        _buildSelectionCard(
          title: l10n.protocolGoogle,
          subtitle: l10n.protocolGoogleDesc,
          icon: Icons.auto_awesome,
          isSelected: _selectedProtocol == 'google-genai-rest',
          onTap: () => setState(() => _selectedProtocol = 'google-genai-rest'),
        ),
      ],
    );
  }

  Widget _buildProviderStep(AppLocalizations l10n) {
    List<Widget> providers = [];
    if (_selectedProtocol == 'openai-api-rest') {
      providers = [
        _buildSelectionCard(
          title: l10n.providerOpenAIOfficial,
          subtitle: "api.openai.com",
          icon: Icons.cloud_outlined,
          isSelected: _selectedProvider == 'openai-official',
          onTap: () => setState(() => _selectedProvider = 'openai-official'),
        ),
        const SizedBox(height: 12),
        _buildSelectionCard(
          title: l10n.providerGoogleCompatible,
          subtitle: l10n.providerGoogleCompatibleDesc,
          icon: Icons.swap_horiz,
          isSelected: _selectedProvider == 'google-compatible',
          onTap: () => setState(() => _selectedProvider = 'google-compatible'),
        ),
      ];
    } else {
      providers = [
        _buildSelectionCard(
          title: l10n.providerGoogleOfficial,
          subtitle: "generativelanguage.googleapis.com",
          icon: Icons.auto_awesome_outlined,
          isSelected: _selectedProvider == 'google-official',
          onTap: () => setState(() => _selectedProvider = 'google-official'),
        ),
      ];
    }

    providers.addAll([
      const SizedBox(height: 12),
      _buildSelectionCard(
        title: l10n.providerCustom,
        subtitle: l10n.providerCustomDesc,
        icon: Icons.settings_input_component,
        isSelected: _selectedProvider == 'custom',
        onTap: () => setState(() => _selectedProvider = 'custom'),
      ),
      if (_selectedProvider == 'custom') ...[
        const SizedBox(height: 16),
        TextField(
          controller: _customEndpointCtrl,
          decoration: InputDecoration(
            labelText: l10n.endpointUrl,
            hintText: "https://your-api.com/v1",
            border: const OutlineInputBorder(),
            helperText: _selectedProtocol == 'openai-api-rest' ? l10n.openaiV1Hint : l10n.googleV1BetaHint,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ]
    ]);

    return _buildStepContainer(children: providers);
  }

  Widget _buildApiKeyStep(AppLocalizations l10n) {
    return _buildStepContainer(
      children: [
        const SizedBox(height: 20),
        Icon(Icons.vpn_key_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(l10n.apiKey, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ApiKeyField(
          controller: _apiKeyCtrl,
          label: l10n.enterApiKey,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.apiKeyStorageNotice,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildConfigStep(AppLocalizations l10n) {
    return _buildStepContainer(
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: l10n.displayName,
            hintText: l10n.nameHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: Text(l10n.enableDiscovery),
          subtitle: Text(l10n.enableDiscoveryDesc),
          value: _enableDiscovery,
          onChanged: (v) => setState(() => _enableDiscovery = v),
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(height: 32),
        Text(l10n.bindTag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        TextField(
          controller: _tagCtrl,
          decoration: InputDecoration(
            labelText: l10n.tag,
            hintText: l10n.tagHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ColorPickerWidget(
          selectedColor: _tagColor,
          onColorChanged: (color) {
            setState(() => _tagColor = color);
          },
          showHexInput: true,
          showColorWheel: true,
        ),
      ],
    );
  }

  Widget _buildPreviewStep(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildStepContainer(
      children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withAlpha(30),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.primaryContainer.withAlpha(100)),
          ),
          child: Column(
            children: [
              _buildPreviewRow(l10n.name, _nameCtrl.text.isEmpty ? _selectedProvider : _nameCtrl.text),
              _buildPreviewRow("Protocol", _selectedProtocol),
              _buildPreviewRow("Provider", _selectedProvider),
              _buildPreviewRow("Discovery", _enableDiscovery ? "Enabled" : "Disabled"),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.tag, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(_tagColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _tagCtrl.text.isEmpty ? _selectedProvider.split('-').first.toUpperCase() : _tagCtrl.text.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        Text(l10n.previewReady, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStepContainer({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: IntrinsicHeight(
              child: Column(
                children: children,
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildSelectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withAlpha(100),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? colorScheme.primaryContainer.withAlpha(30) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? colorScheme.primary : colorScheme.outline, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
