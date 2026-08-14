import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_paths.dart';
import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/model_discovery_service.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../../widgets/api_key_field.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/settings_widgets.dart';
import 'wizard_import.dart';

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  final PageController _pageController = PageController();
  final DatabaseService _db = DatabaseService();
  int _currentStep = 0;
  final int _totalSteps = 5;

  // Controllers
  final TextEditingController _outputDirController = TextEditingController();
  final TextEditingController _prefixController = TextEditingController();

  // Channel Step Controllers
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  String _channelType = Vendors.googleRest;
  int? _createdChannelId;

  // Model Step Controllers
  final TextEditingController _modelIdController = TextEditingController();
  final TextEditingController _modelNameController = TextEditingController();
  String _modelTag = 'multimodal';
  bool _isFetchingModels = false;
  bool _isPortable = false;

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  Future<void> _loadInitialValues() async {
    final appState = Provider.of<AppState>(context, listen: false);
    _outputDirController.text = appState.outputDirectory ?? '';
    _prefixController.text = appState.imagePrefix;
    _channelNameController.text = 'My First Channel';
    _isPortable = await AppPaths.isPortableMode();
    _updateDefaultEndpoint();
    setState(() {});
  }

  void _updateDefaultEndpoint() {
    switch (_channelType) {
      case Vendors.openAIRest:
        _endpointController.text = 'https://api.openai.com/v1';
        break;
      case Vendors.newApiOpenAI:
        // New API is a self-hosted relay; only the path suffix is known.
        _endpointController.text = 'https://your-newapi-host.com/v1';
        break;
      case Vendors.newApiGemini:
        _endpointController.text = 'https://your-newapi-host.com/v1beta';
        break;
      case Vendors.xaiApi:
        _endpointController.text = 'https://api.x.ai/v1';
        break;
      case Vendors.deepseek:
        _endpointController.text = 'https://api.deepseek.com';
        break;
      case Vendors.minimax:
        _endpointController.text = 'https://api.minimaxi.com/v1';
        break;
      case Vendors.anthropicRest:
        _endpointController.text = 'https://api.anthropic.com/v1';
        break;
      case Vendors.newApiAnthropic:
        _endpointController.text = 'https://your-newapi-host.com/v1';
        break;
      case Vendors.minimaxAnthropic:
        // Not `/v1`: MiniMax puts its ④-format endpoint beside the ① one.
        _endpointController.text = 'https://api.minimaxi.com/anthropic/v1';
        break;
      default:
        _endpointController.text = 'https://generativelanguage.googleapis.com/v1beta';
    }
  }

  void _nextStep() {
    if (_currentStep == 2) {
      _saveChannelAndContinue();
      return;
    }
    
    if (_currentStep == 3) {
      _saveModelAndContinue();
      return;
    }

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentStep++);
    } else {
      _finishSetup();
    }
  }

  Future<void> _saveChannelAndContinue() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isNotEmpty) {
      final id = await _db.addChannel({
        'display_name': _channelNameController.text.trim(),
        'endpoint': _endpointController.text.trim(),
        'api_key': apiKey,
        'type': _channelType,
        'enable_discovery': 1,
        'tag': _channelNameController.text.trim().split(' ').first,
        'tag_color': Colors.blue.toARGB32(),
      });
      setState(() {
        _createdChannelId = id;
        _currentStep++;
      });
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      // Skip model step if no channel added
      setState(() {
        _currentStep = 4; // Jump to finish
      });
      _pageController.animateToPage(4, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<void> _saveModelAndContinue() async {
    if (_modelIdController.text.isNotEmpty && _createdChannelId != null) {
      await _db.addModel({
        'model_id': _modelIdController.text,
        'model_name': _modelNameController.text.isEmpty ? _modelIdController.text : _modelNameController.text,
        'tag': _modelTag,
        'is_paid': 1,
        'sort_order': 0,
        'channel_id': _createdChannelId,
      });
    }
    
    setState(() => _currentStep++);
    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _finishSetup() async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.completeSetup();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      child: Scaffold(
      appBar: AppBar(
        title: Text(l10n.setupWizardTitle),
        automaticallyImplyLeading: false,
        actions: [
          AppButton(
            label: l10n.skip,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_currentStep + 1) / _totalSteps),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildWelcomeStep(context, l10n),
                  _buildStorageStep(context, l10n),
                  _buildChannelStep(context, l10n),
                  _buildModelStep(context, l10n),
                  _buildFinishStep(context, l10n),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentStep > 0 && _currentStep != 4)
                    AppButton(
                      label: l10n.back,
                      variant: AppButtonVariant.text,
                      onPressed: () {
                        int prev = _currentStep - 1;
                        if (_currentStep == 4 && _createdChannelId == null) {
                          prev = 2; // Go back to channel if model was skipped
                        }
                        _pageController.animateToPage(prev, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                        setState(() => _currentStep = prev);
                      },
                    ),
                  const SizedBox(width: 16),
                  AppButton(
                    label: _currentStep == _totalSteps - 1 ? l10n.getStarted : (_currentStep == 2 && _apiKeyController.text.isEmpty ? l10n.skip : l10n.next),
                    onPressed: _currentStep == 1 && _outputDirController.text.isEmpty
                        ? null
                        : _nextStep,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildWelcomeStep(BuildContext context, AppLocalizations l10n) {
    final appState = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, size: 64, color: Colors.blue),
          const SizedBox(height: 24),
          Text(l10n.welcomeMessage, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 48),
          ThemeSelector(appState: appState, l10n: l10n),
          const SizedBox(height: 24),
          LanguageSelector(appState: appState, l10n: l10n),
          const SizedBox(height: 48),
          OutlinedButton.icon(
            onPressed: () => importBackupSettings(context, l10n),
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(l10n.importSettings),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(200, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageStep(BuildContext context, AppLocalizations l10n) {
    final appState = Provider.of<AppState>(context);
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.stepStorage, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.storageLocationDesc),
          const SizedBox(height: 24),
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            SwitchListTile(
              title: Text(l10n.portableMode),
              subtitle: Text(l10n.portableModeDesc),
              value: _isPortable,
              onChanged: (v) async {
                await AppPaths.setPortableMode(v);
                setState(() => _isPortable = v);
                if (mounted) {
                  _showRestartDialog(l10n);
                }
              },
              contentPadding: EdgeInsets.zero,
            ),
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            const SizedBox(height: 16),
          TextField(
            controller: _outputDirController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: l10n.outputDirectory,
              suffixIcon: const Icon(Icons.folder_open),
            ),
            onTap: () async {
              String? path = await FilePicker.getDirectoryPath();
              if (path != null) {
                setState(() => _outputDirController.text = path);
                appState.updateOutputDirectory(path);
              }
            },
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _prefixController,
            decoration: InputDecoration(
              labelText: l10n.filenamePrefix,
              helperText: "e.g. 'result' -> result_001.png",
            ),
            onChanged: (v) => appState.setImagePrefix(v),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelStep(BuildContext context, AppLocalizations l10n) {
    final String endpointHint = switch (Vendors.byId(_channelType).family) {
      ProtocolFamily.gemini =>
        "Hint: Google GenAI endpoints usually end with '/v1beta' (internal handling)",
      ProtocolFamily.anthropic =>
        "Hint: Anthropic endpoints usually end with '/v1'",
      ProtocolFamily.openai || ProtocolFamily.midjourney =>
        "Hint: OpenAI compatible endpoints usually end with '/v1'",
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.addChannel, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.addChannelOptional),
          const SizedBox(height: 24),
          TextField(
            controller: _channelNameController,
            decoration: InputDecoration(
              labelText: l10n.displayName,
              hintText: "e.g. My OpenAI",
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _channelType,
            items: const [
              DropdownMenuItem(value: Vendors.googleRest, child: Text('Google GenAI REST')),
              DropdownMenuItem(value: Vendors.openAIRest, child: Text('OpenAI API REST')),
              DropdownMenuItem(value: Vendors.officialGoogle, child: Text('Official Google GenAI API')),
              DropdownMenuItem(value: Vendors.newApiOpenAI, child: Text('New API (OpenAI format)')),
              DropdownMenuItem(value: Vendors.newApiGemini, child: Text('New API (Gemini format)')),
              DropdownMenuItem(value: Vendors.xaiApi, child: Text('xAI (Grok) API')),
              DropdownMenuItem(value: Vendors.deepseek, child: Text('DeepSeek')),
              DropdownMenuItem(value: Vendors.minimax, child: Text('MiniMax')),
              DropdownMenuItem(value: Vendors.anthropicRest, child: Text('Anthropic API')),
              DropdownMenuItem(value: Vendors.newApiAnthropic, child: Text('New API (Anthropic format)')),
              DropdownMenuItem(value: Vendors.minimaxAnthropic, child: Text('MiniMax (Anthropic format)')),
            ],
            onChanged: (v) {
              setState(() {
                _channelType = v!;
                _updateDefaultEndpoint();
              });
            },
            decoration: InputDecoration(
              labelText: l10n.channelType,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpointController,
            decoration: InputDecoration(
              labelText: l10n.endpointUrl,
              helperText: endpointHint,
              helperStyle: const TextStyle(color: Colors.blueGrey),
            ),
          ),
          const SizedBox(height: 16),
          ApiKeyField(
            controller: _apiKeyController,
            label: l10n.apiKey,
            onChanged: (v) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildModelStep(BuildContext context, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.addModel, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.configureModelOptional),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _modelIdController,
                  decoration: InputDecoration(
                    labelText: l10n.modelIdLabel,
                    hintText: "e.g. gpt-4o",
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.fetchModels,
                icon: Icons.refresh,
                variant: AppButtonVariant.secondary,
                loading: _isFetchingModels,
                onPressed: _fetchModels,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelNameController,
            decoration: InputDecoration(
              labelText: l10n.displayName,
              hintText: "e.g. My Model",
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _modelTag,
            items: const [
              DropdownMenuItem(value: 'chat', child: Text('Chat')),
              DropdownMenuItem(value: 'multimodal', child: Text('Multimodal')),
              DropdownMenuItem(value: 'image', child: Text('Image')),
            ],
            onChanged: (v) => setState(() => _modelTag = v!),
            decoration: InputDecoration(
              labelText: l10n.tag,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchModels() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isFetchingModels = true);
    
    try {
      final apiKey = _apiKeyController.text.trim();

      final config = LLMModelConfig(
        modelId: 'discovery',
        channelType: _channelType,
        endpoint: _endpointController.text.trim(),
        apiKey: apiKey,
      );

      final models = await ModelDiscoveryService().discoverModels(config);
      
      if (!mounted) return;
      
      final selected = await AppDialog.show<DiscoveredModel>(
        context,
        title: l10n.selectModelsToAdd,
        maxWidth: 400,
        maxHeight: 400,
        content: ListView.builder(
          itemCount: models.length,
          itemBuilder: (context, index) {
            final m = models[index];
            return ListTile(
              title: Text(m.displayName),
              subtitle: Text(m.modelId),
              onTap: () => Navigator.pop(context, m),
            );
          },
        ),
      );

      if (selected != null) {
        setState(() {
          _modelIdController.text = selected.modelId;
          _modelNameController.text = selected.displayName;
          // Infer tag
          final id = selected.modelId.toLowerCase();
          if (id.contains('vision') || id.contains('image')) {
            _modelTag = 'multimodal';
          } else if (id.contains('gemini')) {
            _modelTag = 'multimodal';
          } else {
            _modelTag = 'chat';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }

  void _showRestartDialog(AppLocalizations l10n) {
    AppDialog.show<void>(
      context,
      barrierDismissible: false,
      title: l10n.restartRequired,
      content: Text(l10n.restartMessage),
      actions: [
        AppButton(
          label: l10n.exit,
          onPressed: () => exit(0),
        ),
      ],
    );
  }

  Widget _buildFinishStep(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          Text(l10n.setupCompleteMessage, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
