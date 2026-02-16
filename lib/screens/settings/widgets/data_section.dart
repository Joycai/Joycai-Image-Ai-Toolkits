import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_section.dart';
import '../../wizard/setup_wizard.dart';

class DataSection extends StatelessWidget {
  final bool isMobile;
  const DataSection({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    
    return AppSection(
      title: l10n.dataManagement,
      padding: const EdgeInsets.only(bottom: 64),
      children: [
        _buildAdaptiveDataActions(context, colorScheme, l10n),
      ],
    );
  }

  Widget _buildAdaptiveDataActions(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    final actions = [
      (onPressed: () => _exportSettings(context, l10n), icon: Icons.download, label: l10n.exportSettings, color: null),
      (onPressed: () => _importSettings(context, l10n), icon: Icons.upload, label: l10n.importSettings, color: null),
      (onPressed: () => _openAppDataDir(context), icon: Icons.folder_shared, label: l10n.openAppDataDirectory, color: null),
      (onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupWizard())), icon: Icons.auto_fix_high, label: l10n.runSetupWizard, color: null),
      (
        onPressed: () async {
          final appState = Provider.of<AppState>(context, listen: false);
          await appState.clearDownloaderCache();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.downloaderCacheCleared)));
        },
        icon: Icons.delete_sweep_outlined,
        label: l10n.clearDownloaderCache,
        color: null
      ),
      (onPressed: () => _resetSettings(context, l10n), icon: Icons.refresh, label: l10n.resetAllSettings, color: colorScheme.error),
    ];

    if (isMobile) {
      return Column(
        children: actions.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildActionBtn(context, a, true),
        )).toList(),
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: actions.map((a) => _buildActionBtn(context, a, false)).toList(),
    );
  }

  Widget _buildActionBtn(BuildContext context, dynamic action, bool fullWidth) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isError = action.color != null;

    return SizedBox(
      width: fullWidth ? double.infinity : 220,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: action.onPressed,
        icon: Icon(action.icon, size: 18),
        label: Text(action.label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: action.color,
          side: isError ? BorderSide(color: colorScheme.error.withAlpha(100)) : null,
          backgroundColor: isError ? colorScheme.errorContainer.withAlpha(20) : null,
        ),
      ),
    );
  }

  Future<void> _openAppDataDir(BuildContext context) async {
    try {
      final path = await DatabaseService().getDatabasePath();
      final uri = Uri.directory(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _exportSettings(BuildContext context, AppLocalizations l10n) async {
    bool includeDirs = true;
    bool includePrompts = true;
    bool includeUsage = false;

    final bool? confirmed = await (isMobile 
      ? _showMobileExportOptions(context, l10n, (d, p, u) {
          includeDirs = d; includePrompts = p; includeUsage = u;
        })
      : _showDesktopExportOptions(context, l10n, (d, p, u) {
          includeDirs = d; includePrompts = p; includeUsage = u;
        }));

    if (confirmed != true || !context.mounted) return;

    final data = await DatabaseService().getAllDataRaw(
      includePrompts: includePrompts, 
      includeUsage: includeUsage,
      includeDirectories: includeDirs,
    );
    final json = jsonEncode(data);
    final bytes = utf8.encode(json);
    
    String? path = await FilePicker.platform.saveFile(
      fileName: 'joycai_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    
    if (!context.mounted) return;

    if (path != null && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      await File(path).writeAsString(json);
    }
    
    if (!context.mounted) return;

    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsExported)));
    }
  }

  Future<bool?> _showMobileExportOptions(BuildContext context, AppLocalizations l10n, Function(bool, bool, bool) onUpdate) async {
    bool d = true;
    bool p = true;
    bool u = false;

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
              Text(l10n.exportOptions, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              _buildExportOption(l10n.includeDirectories, l10n.includeDirectoriesDesc, d, (v) => setState(() => d = v)),
              const Divider(height: 32),
              _buildExportOption(l10n.includePrompts, l10n.includePromptsDesc, p, (v) => setState(() => p = v)),
              const Divider(height: 32),
              _buildExportOption(l10n.includeUsage, l10n.includeUsageDesc, u, (v) => setState(() => u = v)),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: () {
                  onUpdate(d, p, u);
                  Navigator.pop(context, true);
                },
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text(l10n.exportNow),
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

  Future<bool?> _showDesktopExportOptions(BuildContext context, AppLocalizations l10n, Function(bool, bool, bool) onUpdate) async {
    bool d = true;
    bool p = true;
    bool u = false;

    return await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.exportOptions),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildExportOption(l10n.includeDirectories, l10n.includeDirectoriesDesc, d, (v) => setState(() => d = v)),
                const SizedBox(height: 12),
                _buildExportOption(l10n.includePrompts, l10n.includePromptsDesc, p, (v) => setState(() => p = v)),
                const SizedBox(height: 12),
                _buildExportOption(l10n.includeUsage, l10n.includeUsageDesc, u, (v) => setState(() => u = v)),
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
              child: Text(l10n.exportNow),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption(String title, String desc, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _importSettings(BuildContext context, AppLocalizations l10n) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final importedMsg = l10n.settingsImported;

    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (!context.mounted || result == null) return;
    
    try {
      final file = File(result.files.single.path!);
      final fileContent = await file.readAsString();
      if (!context.mounted) return;
      final Map<String, dynamic> data = jsonDecode(fileContent);
      
      // Pre-check what's available in the file
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
      appState.refreshImages();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(importedMsg)));
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

  void _resetSettings(BuildContext context, AppLocalizations l10n) {
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
              await DatabaseService().resetAllSettings();
              if (context.mounted) {
                Navigator.pop(context);
                Provider.of<AppState>(context, listen: false).addLog('All settings reset to default.');
                // Note: ideally we should reload settings here or restart app
              }
            },
            child: Text(l10n.resetEverything, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
