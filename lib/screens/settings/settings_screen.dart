import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Appearance'),
                  _buildThemeSelector(appState),
                  const SizedBox(height: 32),

                  _buildSectionHeader('Google GenAI REST Settings'),
                  _buildRestConfigGroup(
                    'Free Model', 
                    _googleFreeEndpoint, 
                    _googleFreeApiKey, 
                    'google_free',
                    _showGoogleFreeKey,
                    (v) => setState(() => _showGoogleFreeKey = v),
                  ),
                  const SizedBox(height: 16),
                  _buildRestConfigGroup(
                    'Paid Model', 
                    _googlePaidEndpoint, 
                    _googlePaidApiKey, 
                    'google_paid',
                    _showGooglePaidKey,
                    (v) => setState(() => _showGooglePaidKey = v),
                  ),
                  const SizedBox(height: 32),

                  _buildSectionHeader('OpenAI API REST Settings'),
                  _buildRestConfigGroup(
                    'Standard Config', 
                    _openaiEndpoint, 
                    _openaiApiKey, 
                    'openai',
                    _showOpenAIKey,
                    (v) => setState(() => _showOpenAIKey = v),
                  ),
                  const SizedBox(height: 32),

                  _buildSectionHeader('Application Settings'),
                  _buildOutputDirectoryTile(appState),
                  const SizedBox(height: 32),

                  _buildSectionHeader('Data Management'),
                  _buildDataActions(colorScheme),
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

  Widget _buildThemeSelector(AppState appState) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto)),
        ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
        ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
      ],
      selected: {appState.themeMode},
      onSelectionChanged: (Set<ThemeMode> newSelection) {
        appState.setThemeMode(newSelection.first);
      },
    );
  }

  Widget _buildRestConfigGroup(
    String label, 
    TextEditingController ep, 
    TextEditingController key, 
    String prefix,
    bool showKey,
    Function(bool) onToggleVisibility,
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
                decoration: const InputDecoration(labelText: 'Endpoint URL', border: OutlineInputBorder()),
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
                  labelText: 'API Key', 
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

  Widget _buildOutputDirectoryTile(AppState appState) {
    return ListTile(
      title: const Text('Output Directory'),
      subtitle: Text(_outputDirController.text.isEmpty ? 'Not set' : _outputDirController.text),
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

  Widget _buildDataActions(ColorScheme colorScheme) {
    return Wrap(
      spacing: 16,
      children: [
        OutlinedButton.icon(
          onPressed: _exportSettings,
          icon: const Icon(Icons.download),
          label: const Text('Export Settings'),
        ),
        OutlinedButton.icon(
          onPressed: _importSettings,
          icon: const Icon(Icons.upload),
          label: const Text('Import Settings'),
        ),
        ElevatedButton.icon(
          onPressed: _resetSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.errorContainer,
            foregroundColor: colorScheme.error,
          ),
          icon: const Icon(Icons.refresh),
          label: const Text('Reset All Settings'),
        ),
      ],
    );
  }

  Future<void> _exportSettings() async {
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings exported successfully')));
    }
  }

  Future<void> _importSettings() async {
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings imported successfully')));
    }
  }

  void _resetSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Settings?'),
        content: const Text('This will delete all configurations, models, and added folders. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.resetAllSettings();
              Navigator.pop(context);
              _loadAllSettings();
              if (mounted) Provider.of<AppState>(context, listen: false).addLog('All settings reset to default.');
            },
            child: const Text('Reset Everything', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
