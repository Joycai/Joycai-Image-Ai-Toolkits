import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
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

  // Controllers
  final TextEditingController _outputDirController = TextEditingController();
  final TextEditingController _prefixController = TextEditingController();

  // Channel Step Controllers
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  String _channelType = 'openai-api-rest';

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
    _updateDefaultEndpoint();
    setState(() {});
  }

  void _updateDefaultEndpoint() {
    if (_channelType == 'openai-api-rest') {
      _endpointController.text = 'https://api.openai.com/v1';
    } else if (_channelType == 'official-google-genai-api' || _channelType == 'google-genai-rest') {
      _endpointController.text = 'https://generativelanguage.googleapis.com';
    }
  }

  void _nextStep() {
    if (_currentStep < 3) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentStep++);
    } else {
      _finishSetup();
    }
  }

  Future<void> _finishSetup() async {
    final appState = Provider.of<AppState>(context, listen: false);

    // Save Channel if API Key is provided
    if (_apiKeyController.text.isNotEmpty) {
      await _db.addChannel({
        'display_name': _channelNameController.text,
        'endpoint': _endpointController.text,
        'api_key': _apiKeyController.text,
        'type': _channelType,
        'enable_discovery': 1,
        'tag': _channelNameController.text.split(' ').first,
        'tag_color': Colors.blue.toARGB32(),
      });
    }

    await appState.completeSetup();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setupWizardTitle),
        automaticallyImplyLeading: false, // Prevent back button if mandatory
        actions: [
          TextButton(
            onPressed: () {
              // Only allow skipping if not mandatory/first run check logic allows it
              // For now, let's allow closing which just pops. 
              // Real first-run logic in main.dart handles re-showing if needed.
              Navigator.of(context).pop();
            }, 
            child: Text(l10n.skip)
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_currentStep + 1) / 4),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildWelcomeStep(context, l10n),
                _buildStorageStep(context, l10n),
                _buildApiStep(context, l10n),
                _buildFinishStep(context, l10n),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_currentStep > 0)
                  TextButton(
                    onPressed: () {
                      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                      setState(() => _currentStep--);
                    },
                    child: const Text("Back"),
                  ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _currentStep == 1 && _outputDirController.text.isEmpty 
                      ? null // Storage is mandatory-ish
                      : _nextStep,
                  child: Text(_currentStep == 3 ? l10n.getStarted : "Next"),
                ),
              ],
            ),
          ),
        ],
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
          const Text("Select where generated images will be saved."),
          const SizedBox(height: 24),
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

  Widget _buildApiStep(BuildContext context, AppLocalizations l10n) {
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
          Text(l10n.stepApi, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text("Add your first AI provider channel (Optional)."),
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
              DropdownMenuItem(value: 'openai-api-rest', child: Text('OpenAI API REST')),
              DropdownMenuItem(value: 'google-genai-rest', child: Text('Google GenAI REST')),
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
            onChanged: (v) {},
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
