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
    final data = await DatabaseService().getAllDataRaw(includePrompts: true);
    final json = jsonEncode(data);
    final bytes = utf8.encode(json);
    
    String? path = await FilePicker.platform.saveFile(
      fileName: 'joycai_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    
    if (path != null && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      await File(path).writeAsString(json);
    }
    
    if (path != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsExported)));
    }
  }

  Future<void> _importSettings(BuildContext context, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final appState = Provider.of<AppState>(context, listen: false);
    final importedMsg = l10n.settingsImported;

    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (!context.mounted) return;
    
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
        
        await DatabaseService().restoreBackup(data);

        if (!context.mounted) return;
        await appState.loadSettings();
        appState.refreshImages();
        messenger.showSnackBar(SnackBar(content: Text(importedMsg)));
      } catch (e) {
        if (!context.mounted) return;
        messenger.showSnackBar(SnackBar(content: Text("Import failed: $e"), backgroundColor: Colors.red));
      }
    }
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
