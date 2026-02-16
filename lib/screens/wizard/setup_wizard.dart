import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_paths.dart';
import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/model_discovery_service.dart';
import '../../state/app_state.dart';
import '../../widgets/api_key_field.dart';
import '../../widgets/settings_widgets.dart';

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
  String _channelType = 'google-genai-rest';
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
    if (_channelType == 'openai-api-rest') {
      _endpointController.text = 'https://api.openai.com/v1';
    } else {
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
        'type': _channelType.contains('google') ? 'google-genai' : 'openai-api',
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

  Future<void> _importSettings(BuildContext context, AppLocalizations l10n) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final isMobile = MediaQuery.of(context).size.width < 600;

    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (!context.mounted || result == null) return;
    
    try {
      final file = File(result.files.single.path!);
      final fileContent = await file.readAsString();
      if (!context.mounted) return;
      final Map<String, dynamic> data = jsonDecode(fileContent);
      
      final bool hasDirs = data.containsKey('source_directories') || 
                          (data['settings'] as List?)?.any((s) => s['key'] == 'output_directory') == true;
      final bool hasPrompts = data.containsKey('user_prompts') || data.containsKey('prompts') || data.containsKey('tags');
      final bool hasUsage = data.containsKey('token_usage');

      bool includeDirs = hasDirs;
      bool includePrompts = hasPrompts;
      bool includeUsage = hasUsage;

      final bool? confirmed = await (isMobile 
        ? _showMobileImportOptions(context, l10n, hasDirs, hasPrompts, hasUsage, (d, p, u) {
            includeDirs = d; includePrompts = p; includeUsage = u;
          })
        : _showDesktopImportOptions(context, l10n, hasDirs, hasPrompts, hasUsage, (d, p, u) {
            includeDirs = d; includePrompts = p; includeUsage = u;
          }));

      if (confirmed != true || !context.mounted) return;

      await DatabaseService().restoreBackup(
        data, 
        includePrompts: includePrompts,
        includeUsage: includeUsage,
        includeDirectories: includeDirs,
      );

      if (!context.mounted) return;
      await appState.loadSettings();
      if (!context.mounted) return;
      await appState.completeSetup();
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import failed: $e"), backgroundColor: Colors.red));
    }
  }

  Future<bool?> _showMobileImportOptions(
    BuildContext context, 
    AppLocalizations l10n, 
    bool hasDirs, bool hasPrompts, bool hasUsage,
    Function(bool, bool, bool) onUpdate
  ) async {
    bool d = hasDirs;
    bool p = hasPrompts;
    bool u = hasUsage;

    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.importOptions, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(l10n.importSettingsConfirm, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 24),
              _buildImportOption(l10n.includeDirectories, l10n.includeDirectoriesDesc, d, hasDirs, l10n, (v) => setState(() => d = v)),
              const Divider(height: 32),
              _buildImportOption(l10n.includePrompts, l10n.includePromptsDesc, p, hasPrompts, l10n, (v) => setState(() => p = v)),
              const Divider(height: 32),
              _buildImportOption(l10n.includeUsage, l10n.includeUsageDesc, u, hasUsage, l10n, (v) => setState(() => u = v)),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: () {
                  onUpdate(d, p, u);
                  Navigator.pop(context, true);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
                child: Text(l10n.importNow),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showDesktopImportOptions(
    BuildContext context, 
    AppLocalizations l10n, 
    bool hasDirs, bool hasPrompts, bool hasUsage,
    Function(bool, bool, bool) onUpdate
  ) async {
    bool d = hasDirs;
    bool p = hasPrompts;
    bool u = hasUsage;

    return await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.importOptions),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.importSettingsConfirm, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 20),
                _buildImportOption(l10n.includeDirectories, l10n.includeDirectoriesDesc, d, hasDirs, l10n, (v) => setState(() => d = v)),
                const SizedBox(height: 12),
                _buildImportOption(l10n.includePrompts, l10n.includePromptsDesc, p, hasPrompts, l10n, (v) => setState(() => p = v)),
                const SizedBox(height: 12),
                _buildImportOption(l10n.includeUsage, l10n.includeUsageDesc, u, hasUsage, l10n, (v) => setState(() => u = v)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            FilledButton(
              onPressed: () {
                onUpdate(d, p, u);
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: Text(l10n.importNow),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportOption(String title, String desc, bool value, bool enabled, AppLocalizations l10n, Function(bool) onChanged) {
    return SwitchListTile(
      value: value && enabled,
      onChanged: enabled ? onChanged : null,
      title: Text(title, style: TextStyle(
        fontWeight: FontWeight.bold, 
        fontSize: 14,
        color: enabled ? null : Colors.grey,
      )),
      subtitle: Text(
        enabled ? desc : l10n.notInBackup, 
        style: TextStyle(fontSize: 12, color: enabled ? null : Colors.grey[400]),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setupWizardTitle),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(), 
            child: Text(l10n.skip)
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
                    TextButton(
                      onPressed: () {
                        int prev = _currentStep - 1;
                        if (_currentStep == 4 && _createdChannelId == null) {
                          prev = 2; // Go back to channel if model was skipped
                        }
                        _pageController.animateToPage(prev, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                        setState(() => _currentStep = prev);
                      },
                      child: Text(l10n.back),
                    ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: _currentStep == 1 && _outputDirController.text.isEmpty 
                        ? null 
                        : _nextStep,
                    child: Text(_currentStep == _totalSteps - 1 ? l10n.getStarted : (_currentStep == 2 && _apiKeyController.text.isEmpty ? l10n.skip : l10n.next)),
                  ),
                ],
              ),
            ),
          ],
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
            onPressed: () => _importSettings(context, l10n),
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
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.folder_open),
            ),
            onTap: () async {
              String? path = await FilePicker.platform.getDirectoryPath();
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
              border: const OutlineInputBorder(),
              helperText: "e.g. 'result' -> result_001.png",
            ),
            onChanged: (v) => appState.setImagePrefix(v),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelStep(BuildContext context, AppLocalizations l10n) {
    String endpointHint = "";
    if (_channelType == 'openai-api-rest') {
      endpointHint = "Hint: OpenAI compatible endpoints usually end with '/v1'";
    } else if (_channelType.contains('google')) {
      endpointHint = "Hint: Google GenAI endpoints usually end with '/v1beta' (internal handling)";
    }

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
              border: const OutlineInputBorder(),
              hintText: "e.g. My OpenAI",
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _channelType,
            items: const [
              DropdownMenuItem(value: 'google-genai-rest', child: Text('Google GenAI REST')),
              DropdownMenuItem(value: 'openai-api-rest', child: Text('OpenAI API REST')),
              DropdownMenuItem(value: 'official-google-genai-api', child: Text('Official Google GenAI API')),
            ],
            onChanged: (v) {
              setState(() {
                _channelType = v!;
                _updateDefaultEndpoint();
              });
            },
            decoration: InputDecoration(
              labelText: l10n.channelType,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpointController,
            decoration: InputDecoration(
              labelText: l10n.endpointUrl,
              border: const OutlineInputBorder(),
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
                    border: const OutlineInputBorder(),
                    hintText: "e.g. gpt-4o",
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isFetchingModels ? null : _fetchModels,
                icon: _isFetchingModels 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
                label: Text(l10n.fetchModels),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelNameController,
            decoration: InputDecoration(
              labelText: l10n.displayName,
              border: const OutlineInputBorder(),
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
              border: const OutlineInputBorder(),
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
      final type = _channelType.contains('google') ? 'google-genai' : 'openai-api';
      final apiKey = _apiKeyController.text.trim();
      
      final config = LLMModelConfig(
        modelId: 'discovery',
        type: type,
        channelType: _channelType,
        endpoint: _endpointController.text.trim(),
        apiKey: apiKey,
      );

      final models = await ModelDiscoveryService().discoverModels(type, config);
      
      if (!mounted) return;
      
      final selected = await showDialog<DiscoveredModel>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.selectModelsToAdd),
          content: SizedBox(
            width: 400,
            height: 400,
            child: ListView.builder(
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
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isFetchingModels = false);
    }
  }

  void _showRestartDialog(AppLocalizations l10n) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.restartRequired),
        content: Text(l10n.restartMessage),
        actions: [
          FilledButton(
            onPressed: () => exit(0),
            child: Text(l10n.exit),
          ),
        ],
      ),
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
