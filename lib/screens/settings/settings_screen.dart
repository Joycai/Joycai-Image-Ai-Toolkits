import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_paths.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../services/llm/llm_debug_logger.dart';
import '../../state/app_state.dart';
import '../../widgets/api_key_field.dart';
import '../../widgets/app_section.dart';
import '../../widgets/settings_widgets.dart';
import '../wizard/setup_wizard.dart';

enum SettingsCategory { appearance, connectivity, application, data }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _db = DatabaseService();
  SettingsCategory _selectedCategory = SettingsCategory.appearance;
  
  // Controllers
  final TextEditingController _outputDirController = TextEditingController();
  
  // Proxy Settings
  bool _proxyEnabled = false;
  final TextEditingController _proxyUrlController = TextEditingController();
  final TextEditingController _proxyUsernameController = TextEditingController();
  final TextEditingController _proxyPasswordController = TextEditingController();
  
  // MCP Settings
  bool _mcpEnabled = false;
  final TextEditingController _mcpPortController = TextEditingController();

  bool _isPortable = false;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    _outputDirController.text = await _db.getSetting('output_directory') ?? '';
    
    _proxyEnabled = (await _db.getSetting('proxy_enabled')) == 'true';
    _proxyUrlController.text = await _db.getSetting('proxy_url') ?? '';
    _proxyUsernameController.text = await _db.getSetting('proxy_username') ?? '';
    _proxyPasswordController.text = await _db.getSetting('proxy_password') ?? '';

    _mcpEnabled = (await _db.getSetting('mcp_enabled')) == 'true';
    _mcpPortController.text = await _db.getSetting('mcp_port') ?? '3000';

    _isPortable = await AppPaths.isPortableMode();
    
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isNarrow = Responsive.isNarrow(context);

    if (isNarrow) {
      return _buildMobileLayout(l10n);
    } else {
      return _buildDesktopLayout(l10n);
    }
  }

  Widget _buildMobileLayout(AppLocalizations l10n) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildAppearanceSection(l10n),
            const SizedBox(height: 24),
            _buildConnectivitySection(l10n, true),
            const SizedBox(height: 24),
            _buildApplicationSection(l10n),
            const SizedBox(height: 24),
            _buildDataSection(l10n, true),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 250,
            color: colorScheme.surfaceContainerLow,
            child: ListView(
              children: [
                _buildCategoryTile(SettingsCategory.appearance, Icons.palette_outlined, l10n.appearance),
                _buildCategoryTile(SettingsCategory.connectivity, Icons.lan_outlined, l10n.connectivity),
                _buildCategoryTile(SettingsCategory.application, Icons.settings_applications_outlined, l10n.application),
                _buildCategoryTile(SettingsCategory.data, Icons.storage_outlined, l10n.dataManagement),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: _buildSelectedCategory(l10n),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(SettingsCategory category, IconData icon, String label) {
    final isSelected = _selectedCategory == category;
    return ListTile(
      selected: isSelected,
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: () => setState(() => _selectedCategory = category),
    );
  }

  Widget _buildSelectedCategory(AppLocalizations l10n) {
    switch (_selectedCategory) {
      case SettingsCategory.appearance:
        return _buildAppearanceSection(l10n);
      case SettingsCategory.connectivity:
        return _buildConnectivitySection(l10n, false);
      case SettingsCategory.application:
        return _buildApplicationSection(l10n);
      case SettingsCategory.data:
        return _buildDataSection(l10n, false);
    }
  }

  Widget _buildAppearanceSection(AppLocalizations l10n) {
    final appState = Provider.of<AppState>(context);
    return AppSection(
      title: l10n.appearance,
      children: [
        ThemeSelector(appState: appState, l10n: l10n),
        const SizedBox(height: 32),
        ThemeColorSelector(appState: appState, l10n: l10n),
        const SizedBox(height: 32),
        LanguageSelector(appState: appState, l10n: l10n),
      ],
    );
  }

  Widget _buildConnectivitySection(AppLocalizations l10n, bool isMobile) {
    return Column(
      children: [
        AppSection(
          title: l10n.proxySettings,
          children: [
            _buildProxySettings(l10n, isMobile),
          ],
        ),
        const SizedBox(height: 24),
        AppSection(
          title: l10n.mcpServerSettings,
          children: [
            _buildMcpSettings(l10n),
          ],
        ),
      ],
    );
  }

  Widget _buildApplicationSection(AppLocalizations l10n) {
    final appState = Provider.of<AppState>(context);
    return AppSection(
      title: l10n.application,
      children: [
        _buildNotificationTile(appState, l10n),
        const SizedBox(height: 8),
        _buildApiDebugTile(appState, l10n),
        const SizedBox(height: 8),
        _buildPortableModeTile(l10n),
        const SizedBox(height: 8),
        _buildOutputDirectoryTile(appState, l10n),
      ],
    );
  }

  Widget _buildDataSection(AppLocalizations l10n, bool isMobile) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSection(
      title: l10n.dataManagement,
      padding: const EdgeInsets.only(bottom: 64),
      children: [
        _buildAdaptiveDataActions(colorScheme, l10n, isMobile),
      ],
    );
  }

  Widget _buildProxySettings(AppLocalizations l10n, bool isMobile) {
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
                if (isMobile) ...[
                  TextField(
                    controller: _proxyUsernameController,
                    decoration: InputDecoration(
                      labelText: l10n.proxyUsername,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => _db.saveSetting('proxy_username', v),
                  ),
                  const SizedBox(height: 16),
                  ApiKeyField(
                    controller: _proxyPasswordController,
                    label: l10n.proxyPassword,
                    onChanged: (v) => _db.saveSetting('proxy_password', v),
                  ),
                ] else
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

  Widget _buildNotificationTile(AppState appState, AppLocalizations l10n) {
    return SwitchListTile(
      title: Text(l10n.enableNotifications),
      value: appState.notificationsEnabled,
      onChanged: (v) => appState.setNotificationsEnabled(v),
    );
  }

  Widget _buildApiDebugTile(AppState appState, AppLocalizations l10n) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(l10n.enableApiDebug),
          subtitle: Text(l10n.apiDebugDesc),
          value: appState.enableApiDebug,
          onChanged: (v) => appState.setEnableApiDebug(v),
        ),
        if (appState.enableApiDebug)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => LLMDebugLogger.openLogFolder(),
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: Text(l10n.openLogFolder),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPortableModeTile(AppLocalizations l10n) {
    return SwitchListTile(
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
    );
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
            child: Text(l10n.resetEverything),
          ),
        ],
      ),
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

  Widget _buildAdaptiveDataActions(ColorScheme colorScheme, AppLocalizations l10n, bool isMobile) {
    final actions = [
      (onPressed: () => _exportSettings(l10n), icon: Icons.download, label: l10n.exportSettings, color: null),
      (onPressed: () => _importSettings(l10n), icon: Icons.upload, label: l10n.importSettings, color: null),
      (onPressed: _openAppDataDir, icon: Icons.folder_shared, label: l10n.openAppDataDirectory, color: null),
      (onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupWizard())), icon: Icons.auto_fix_high, label: l10n.runSetupWizard, color: null),
      (
        onPressed: () async {
          final appState = Provider.of<AppState>(context, listen: false);
          await appState.clearDownloaderCache();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloader cache cleared.')));
        },
        icon: Icons.delete_sweep_outlined,
        label: l10n.clearDownloaderCache,
        color: null
      ),
      (onPressed: () => _resetSettings(l10n), icon: Icons.refresh, label: l10n.resetAllSettings, color: colorScheme.error),
    ];

    if (isMobile) {
      return Column(
        children: actions.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildActionBtn(a, true),
        )).toList(),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 4,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) => _buildActionBtn(actions[index], false),
    );
  }

  Widget _buildActionBtn(dynamic action, bool fullWidth) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isError = action.color != null;

    final btnContent = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(action.icon, size: 18),
        const SizedBox(width: 12),
        Text(action.label, style: const TextStyle(fontSize: 12)),
      ],
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 50,
      child: OutlinedButton(
        onPressed: action.onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: action.color,
          side: isError ? BorderSide(color: colorScheme.error.withAlpha(100)) : null,
          backgroundColor: isError ? colorScheme.errorContainer.withAlpha(20) : null,
        ),
        child: btnContent,
      ),
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
    final data = await _db.getAllDataRaw(includePrompts: true);
    final json = jsonEncode(data);
    
    String? path = await FilePicker.platform.saveFile(
      fileName: 'joycai_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    
    if (path != null) {
      await File(path).writeAsString(json);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsExported)));
      }
    }
  }

  Future<void> _importSettings(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final appState = Provider.of<AppState>(context, listen: false);
    final importedMsg = l10n.settingsImported;

    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (!mounted) return;
    
    if (result != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.importSettingsTitle),
          content: Text(l10n.importSettingsConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: Text(l10n.importAndReplace),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      try {
        final file = File(result.files.single.path!);
        final Map<String, dynamic> data = jsonDecode(await file.readAsString());
        
        await _db.restoreBackup(data);

        if (!mounted) return;
        // ignore: use_build_context_synchronously
        await _loadAllSettings();
        await appState.loadSettings();
        appState.refreshImages();
        messenger.showSnackBar(SnackBar(content: Text(importedMsg)));
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text("Import failed: $e"), backgroundColor: Colors.red));
      }
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