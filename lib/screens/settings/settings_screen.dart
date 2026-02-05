import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/api_key_field.dart';
import '../../widgets/app_section.dart';
import '../../widgets/settings_widgets.dart';
import '../wizard/setup_wizard.dart';

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
  
  // Proxy Settings
  bool _proxyEnabled = false;
  final TextEditingController _proxyUrlController = TextEditingController();
  final TextEditingController _proxyUsernameController = TextEditingController();
  final TextEditingController _proxyPasswordController = TextEditingController();
  
  // MCP Settings
  bool _mcpEnabled = false;
  final TextEditingController _mcpPortController = TextEditingController();

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
    
    _proxyEnabled = (await _db.getSetting('proxy_enabled')) == 'true';
    _proxyUrlController.text = await _db.getSetting('proxy_url') ?? '';
    _proxyUsernameController.text = await _db.getSetting('proxy_username') ?? '';
    _proxyPasswordController.text = await _db.getSetting('proxy_password') ?? '';

    _mcpEnabled = (await _db.getSetting('mcp_enabled')) == 'true';
    _mcpPortController.text = await _db.getSetting('mcp_port') ?? '3000';
    
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
                  AppSection(
                    title: l10n.appearance,
                    children: [
                      ThemeSelector(appState: appState, l10n: l10n),
                      const SizedBox(height: 16),
                      LanguageSelector(appState: appState, l10n: l10n),
                    ],
                  ),
                  const SizedBox(height: 32),

                  AppSection(
                    title: l10n.proxySettings,
                    children: [
                      _buildProxySettings(l10n),
                    ],
                  ),

                  AppSection(
                    title: l10n.mcpServerSettings,
                    children: [
                      _buildMcpSettings(l10n),
                    ],
                  ),

                  AppSection(
                    title: l10n.googleGenAiSettings,
                    children: [
                      _buildRestConfigGroup(
                        l10n.freeModel, 
                        _googleFreeEndpoint, 
                        _googleFreeApiKey, 
                        'google_free',
                        l10n,
                      ),
                      const SizedBox(height: 16),
                      _buildRestConfigGroup(
                        l10n.paidModel, 
                        _googlePaidEndpoint, 
                        _googlePaidApiKey, 
                        'google_paid',
                        l10n,
                      ),
                    ],
                  ),

                  AppSection(
                    title: l10n.openAiApiSettings,
                    children: [
                      _buildRestConfigGroup(
                        l10n.standardConfig, 
                        _openaiEndpoint, 
                        _openaiApiKey, 
                        'openai',
                        l10n,
                      ),
                    ],
                  ),

                  AppSection(
                    title: l10n.settings,
                    children: [
                      _buildOutputDirectoryTile(appState, l10n),
                    ],
                  ),

                  AppSection(
                    title: l10n.dataManagement,
                    padding: const EdgeInsets.only(bottom: 64),
                    children: [
                      _buildDataActions(colorScheme, l10n),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProxySettings(AppLocalizations l10n) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(l10n.enableProxy),
          value: _proxyEnabled,
          onChanged: (v) {
            setState(() => _proxyEnabled = v);
            _db.saveSetting('proxy_enabled', v.toString());
          },
        ),
        if (_proxyEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                TextField(
                  controller: _proxyUrlController,
                  decoration: InputDecoration(
                    labelText: l10n.proxyUrl,
                    hintText: '127.0.0.1:7890',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => _db.saveSetting('proxy_url', v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _proxyUsernameController,
                        decoration: InputDecoration(
                          labelText: l10n.proxyUsername,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => _db.saveSetting('proxy_username', v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ApiKeyField(
                        controller: _proxyPasswordController,
                        label: l10n.proxyPassword,
                        onChanged: (v) => _db.saveSetting('proxy_password', v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMcpSettings(AppLocalizations l10n) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(l10n.enableMcpServer),
          value: _mcpEnabled,
          onChanged: (v) {
            setState(() => _mcpEnabled = v);
            _db.saveSetting('mcp_enabled', v.toString());
          },
        ),
        if (_mcpEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _mcpPortController,
              decoration: InputDecoration(
                labelText: l10n.port,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => _db.saveSetting('mcp_port', v),
            ),
          ),
      ],
    );
  }

  Widget _buildRestConfigGroup(
    String label, 
    TextEditingController ep, 
    TextEditingController key, 
    String prefix,
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
              child: ApiKeyField(
                controller: key,
                label: l10n.apiKey,
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
        OutlinedButton.icon(
          onPressed: _openAppDataDir,
          icon: const Icon(Icons.folder_shared),
          label: Text(l10n.openAppDataDirectory),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupWizard())),
          icon: const Icon(Icons.auto_fix_high),
          label: Text(l10n.runSetupWizard),
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

  Future<void> _openAppDataDir() async {
    try {
      final path = await _db.getDatabasePath();
      final uri = Uri.directory(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _exportSettings(AppLocalizations l10n) async {
    final settings = await _db.database.then((db) => db.query('settings'));
    final models = await _db.getModels();
    final prompts = await _db.getPrompts();
    final data = jsonEncode({'settings': settings, 'models': models, 'prompts': prompts});
    
    String? path = await FilePicker.platform.saveFile(
      fileName: 'joycai_settings.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    
    if (path != null) {
      await File(path).writeAsString(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsExported)));
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
      if (data['prompts'] != null) {
        for (var p in data['prompts']) {
          Map<String, dynamic> prompt = Map.from(p);
          prompt.remove('id');
          await _db.addPrompt(prompt);
        }
      }

      _loadAllSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsImported)));
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
              if (context.mounted) {
                Navigator.pop(context);
                _loadAllSettings();
                Provider.of<AppState>(context, listen: false).addLog('All settings reset to default.');
              }
            },
            child: Text(l10n.resetEverything, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
