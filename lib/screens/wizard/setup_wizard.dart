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
  final TextEditingController _googleFreeEndpoint = TextEditingController();
  final TextEditingController _googleFreeApiKey = TextEditingController();
  final TextEditingController _googlePaidEndpoint = TextEditingController();
  final TextEditingController _googlePaidApiKey = TextEditingController();
  final TextEditingController _openaiEndpoint = TextEditingController();
  final TextEditingController _openaiApiKey = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  Future<void> _loadInitialValues() async {
    // Load existing values just in case
    final appState = Provider.of<AppState>(context, listen: false);
    _outputDirController.text = appState.outputDirectory ?? '';
    _prefixController.text = appState.imagePrefix;
    
    // API keys might be in DB
    _googleFreeEndpoint.text = await _db.getSetting('google_free_endpoint') ?? '';
    _googleFreeApiKey.text = await _db.getSetting('google_free_apikey') ?? '';
    _googlePaidEndpoint.text = await _db.getSetting('google_paid_endpoint') ?? '';
    _googlePaidApiKey.text = await _db.getSetting('google_paid_apikey') ?? '';
    _openaiEndpoint.text = await _db.getSetting('openai_endpoint') ?? '';
    _openaiApiKey.text = await _db.getSetting('openai_apikey') ?? '';
    setState(() {});
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.stepApi, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text("Configure AI models (Optional). You can do this later in Settings."),
          const SizedBox(height: 24),
          _buildApiGroup(l10n.googleGenAiFree, _googleFreeEndpoint, _googleFreeApiKey, 'google_free', l10n),
          const SizedBox(height: 16),
          _buildApiGroup(l10n.openaiApi, _openaiEndpoint, _openaiApiKey, 'openai', l10n),
        ],
      ),
    );
  }

  Widget _buildApiGroup(String label, TextEditingController ep, TextEditingController key, String prefix, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: ep,
          decoration: InputDecoration(labelText: l10n.endpointUrl, border: const OutlineInputBorder()),
          onChanged: (v) => _db.saveSetting('${prefix}_endpoint', v),
        ),
        const SizedBox(height: 8),
        ApiKeyField(
          controller: key,
          label: l10n.apiKey,
          onChanged: (v) => _db.saveSetting('${prefix}_apikey', v),
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
