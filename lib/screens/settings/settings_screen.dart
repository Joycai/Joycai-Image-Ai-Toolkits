import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _db = DatabaseService();
  
  // Controllers for REST settings
  final TextEditingController _googleFreeEndpoint = TextEditingController();
  final TextEditingController _googleFreeApiKey = TextEditingController();
  final TextEditingController _googlePaidEndpoint = TextEditingController();
  final TextEditingController _googlePaidApiKey = TextEditingController();
  final TextEditingController _openaiEndpoint = TextEditingController();
  final TextEditingController _openaiApiKey = TextEditingController();
  final TextEditingController _outputDirController = TextEditingController();

  // Visibility states for API keys
  bool _showGoogleFreeKey = false;
  bool _showGooglePaidKey = false;
  bool _showOpenAIKey = false;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    _googleFreeEndpoint.text = await _db.getSetting('google_free_endpoint') ?? '';
    _googleFreeApiKey.text = await _db.getSetting('google_free_apikey') ?? '';
    _googlePaidEndpoint.text = await _db.getSetting('google_paid_endpoint') ?? '';
    _googlePaidApiKey.text = await _db.getSetting('google_paid_apikey') ?? '';
    _openaiEndpoint.text = await _db.getSetting('openai_endpoint') ?? '';
    _openaiApiKey.text = await _db.getSetting('openai_apikey') ?? '';
    _outputDirController.text = await _db.getSetting('output_directory') ?? '';
    setState(() {});
  }

  Future<void> _saveRestSetting(String key, String value) async {
    await _db.saveSetting(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(l10n.appearance),
                  _buildThemeSelector(appState, l10n),
                  const SizedBox(height: 16),
                  _buildLanguageSelector(appState, l10n),
                  const SizedBox(height: 32),

                  _buildSectionHeader(l10n.googleGenAiSettings),
                  _buildRestConfigGroup(
                    l10n.freeModel, 
                    _googleFreeEndpoint, 
                    _googleFreeApiKey, 
                    'google_free',
                    _showGoogleFreeKey,
                    (v) => setState(() => _showGoogleFreeKey = v),
                    l10n,
                  ),
                  const SizedBox(height: 16),
                  _buildRestConfigGroup(
                    l10n.paidModel, 
                    _googlePaidEndpoint, 
                    _googlePaidApiKey, 
                    'google_paid',
                    _showGooglePaidKey,
                    (v) => setState(() => _showGooglePaidKey = v),
                    l10n,
                  ),
                  const SizedBox(height: 32),

                  _buildSectionHeader(l10n.openAiApiSettings),
                  _buildRestConfigGroup(
                    l10n.standardConfig, 
                    _openaiEndpoint, 
                    _openaiApiKey, 
                    'openai',
                    _showOpenAIKey,
                    (v) => setState(() => _showOpenAIKey = v),
                    l10n,
                  ),
                  const SizedBox(height: 32),

                  _buildSectionHeader(l10n.settings),
                  _buildOutputDirectoryTile(appState, l10n),
                  const SizedBox(height: 32),

                  _buildSectionHeader(l10n.dataManagement),
                  _buildDataActions(colorScheme, l10n),
                  const SizedBox(height: 64),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildThemeSelector(AppState appState, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.appearance, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeAuto), icon: const Icon(Icons.brightness_auto)),
            ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight), icon: const Icon(Icons.light_mode)),
            ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark), icon: const Icon(Icons.dark_mode)),
          ],
          selected: {appState.themeMode},
          onSelectionChanged: (Set<ThemeMode> newSelection) {
            appState.setThemeMode(newSelection.first);
          },
        ),
      ],
    );
  }

  Widget _buildLanguageSelector(AppState appState, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.language, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 8),
        SegmentedButton<String?>(
          segments: const [
            ButtonSegment(value: null, label: Text('Default')),
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'zh', label: Text('中文')),
          ],
          selected: {appState.locale?.languageCode},
          onSelectionChanged: (Set<String?> newSelection) {
            final code = newSelection.first;
            appState.setLocale(code == null ? null : Locale(code));
          },
        ),
      ],
    );
  }

  Widget _buildRestConfigGroup(
    String label, 
    TextEditingController ep, 
    TextEditingController key, 
    String prefix,
    bool showKey,
    Function(bool) onToggleVisibility,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: ep,
                decoration: InputDecoration(labelText: l10n.endpointUrl, border: const OutlineInputBorder()),
                onChanged: (v) => _saveRestSetting('${prefix}_endpoint', v),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: TextField(
                controller: key,
                obscureText: !showKey,
                decoration: InputDecoration(
                  labelText: l10n.apiKey, 
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => onToggleVisibility(!showKey),
                  ),
                ),
                onChanged: (v) => _saveRestSetting('${prefix}_apikey', v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutputDirectoryTile(AppState appState, AppLocalizations l10n) {
    return ListTile(
      title: Text(l10n.outputDirectory),
      subtitle: Text(_outputDirController.text.isEmpty ? l10n.notSet : _outputDirController.text),
      trailing: const Icon(Icons.folder_open),
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      onTap: () async {
        String? path = await FilePicker.platform.getDirectoryPath();
        if (path != null) {
          setState(() => _outputDirController.text = path);
          await appState.updateOutputDirectory(path);
        }
      },
    );
  }

  Widget _buildDataActions(ColorScheme colorScheme, AppLocalizations l10n) {
    return Wrap(
      spacing: 16,
      children: [
        OutlinedButton.icon(
          onPressed: () => _exportSettings(l10n),
          icon: const Icon(Icons.download),
          label: Text(l10n.exportSettings),
        ),
        OutlinedButton.icon(
          onPressed: () => _importSettings(l10n),
          icon: const Icon(Icons.upload),
          label: Text(l10n.importSettings),
        ),
        ElevatedButton.icon(
          onPressed: () => _resetSettings(l10n),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.errorContainer,
            foregroundColor: colorScheme.error,
          ),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.resetAllSettings),
        ),
      ],
    );
  }

  Future<void> _exportSettings(AppLocalizations l10n) async {
    final settings = await _db.database.then((db) => db.query('settings'));
    final models = await _db.getModels();
    final data = jsonEncode({'settings': settings, 'models': models});
    
    String? path = await FilePicker.platform.saveFile(
      fileName: 'joycai_settings.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    
    if (path != null) {
      await File(path).writeAsString(data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsExported)));
    }
  }

  Future<void> _importSettings(AppLocalizations l10n) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result != null) {
      final file = File(result.files.single.path!);
      final data = jsonDecode(await file.readAsString());
      
      for (var s in data['settings']) {
        await _db.saveSetting(s['key'], s['value']);
      }
      for (var m in data['models']) {
        Map<String, dynamic> model = Map.from(m);
        model.remove('id');
        await _db.addModel(model);
      }
      _loadAllSettings();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsImported)));
    }
  }

  void _resetSettings(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmReset),
        content: Text(l10n.resetWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.resetAllSettings();
              Navigator.pop(context);
              _loadAllSettings();
              if (mounted) Provider.of<AppState>(context, listen: false).addLog('All settings reset to default.');
            },
            child: Text(l10n.resetEverything, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
