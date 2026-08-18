import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/backup_error_text.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/dialogs/import_options_dialog.dart';
import '../../../widgets/app_section.dart';
import '../../../widgets/app_snackbar.dart';
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
          if (context.mounted) AppSnackBar.success(context, AppLocalizations.of(context)!.downloaderCacheCleared);
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
    final bool isError = action.color != null;

    return SizedBox(
      width: fullWidth ? double.infinity : 220,
      height: 50,
      child: AppButton(
        label: action.label,
        icon: action.icon,
        variant: isError ? AppButtonVariant.destructiveOutline : AppButtonVariant.secondary,
        onPressed: action.onPressed,
      ),
    );
  }

  Future<void> _openAppDataDir(BuildContext context) async {
    try {
      final path = await DatabaseService().getDatabasePath();
      await FileUtils.openFolder(path);
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
    
    // file_picker >= 12 writes `bytes` itself on every platform and returns the
    // destination as a Uri, so no follow-up write is needed here.
    final Uri? saved = await FilePicker.saveFile(
      fileName: 'joycai_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (!context.mounted) return;

    if (saved != null) {
      AppSnackBar.success(context, l10n.settingsExported);
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
              _buildExportOption(context, l10n.includeDirectories, l10n.includeDirectoriesDesc, d, (v) => setState(() => d = v)),
              const Divider(height: 32),
              _buildExportOption(context, l10n.includePrompts, l10n.includePromptsDesc, p, (v) => setState(() => p = v)),
              const Divider(height: 32),
              _buildExportOption(context, l10n.includeUsage, l10n.includeUsageDesc, u, (v) => setState(() => u = v)),
              const SizedBox(height: 48),
              AppButton(
                label: l10n.exportNow,
                size: AppButtonSize.large,
                fullWidth: true,
                onPressed: () {
                  onUpdate(d, p, u);
                  Navigator.pop(context, true);
                },
              ),
              const SizedBox(height: 12),
              AppButton(
                label: l10n.cancel,
                variant: AppButtonVariant.text,
                size: AppButtonSize.large,
                fullWidth: true,
                onPressed: () => Navigator.pop(context, false),
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

    return await AppDialog.show<bool>(
      context,
      title: l10n.exportOptions,
      maxWidth: 450,
      content: StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildExportOption(context, l10n.includeDirectories, l10n.includeDirectoriesDesc, d, (v) => setState(() => d = v)),
            const SizedBox(height: 12),
            _buildExportOption(context, l10n.includePrompts, l10n.includePromptsDesc, p, (v) => setState(() => p = v)),
            const SizedBox(height: 12),
            _buildExportOption(context, l10n.includeUsage, l10n.includeUsageDesc, u, (v) => setState(() => u = v)),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.exportNow,
          onPressed: () {
            onUpdate(d, p, u);
            Navigator.pop(context, true);
          },
        ),
      ],
    );
  }

  Widget _buildExportOption(
      BuildContext context, String title, String desc, bool value, Function(bool) onChanged) {
    final textTheme = Theme.of(context).textTheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: textTheme.titleMedium),
      subtitle: Text(desc, style: textTheme.bodySmall),
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _importSettings(BuildContext context, AppLocalizations l10n) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final importedMsg = l10n.settingsImported;

    final PlatformFile? picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (!context.mounted || picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      final String fileContent = utf8.decode(bytes);
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

      final bool? confirmed = await showImportOptionsDialog(
        context,
        l10n: l10n,
        hasDirs: hasDirs,
        hasPrompts: hasPrompts,
        hasUsage: hasUsage,
        isMobile: isMobile,
        onUpdate: (d, p, u) {
          includeDirs = d; includePrompts = p; includeUsage = u;
        },
      );

      if (confirmed != true || !context.mounted) return;

      await DatabaseService().restoreBackup(
        data, 
        includePrompts: includePrompts,
        includeUsage: includeUsage,
        includeDirectories: includeDirs,
      );

      if (!context.mounted) return;
      await appState.loadSettings();
      await appState.galleryState.reloadSettings();
      await appState.fileBrowserState.reloadSettings();
      if (!context.mounted) return;
      AppSnackBar.success(context, importedMsg);
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.error(context, backupImportErrorText(l10n, e));
    }
  }

  void _resetSettings(BuildContext context, AppLocalizations l10n) {
    AppDialog.show<void>(
      context,
      title: l10n.confirmReset,
      content: Text(l10n.resetWarning),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.resetEverything,
          variant: AppButtonVariant.destructive,
          onPressed: () async {
            final appState = Provider.of<AppState>(context, listen: false);
            await DatabaseService().resetAllSettings();
            if (!context.mounted) return;
            Navigator.pop(context);
            appState.addLog('All settings reset to default.');
            await appState.loadSettings();
            await appState.galleryState.reloadSettings();
            await appState.fileBrowserState.reloadSettings();
          },
        ),
      ],
    );
  }
}
