import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/backup_error_text.dart';
import '../../../core/constants.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../services/temp_storage_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/dialogs/import_options_dialog.dart';
import '../../../widgets/app_section.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/app_snackbar.dart';
import '../../wizard/setup_wizard.dart';

class DataSection extends StatelessWidget {
  final bool isMobile;
  const DataSection({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    
    // No title — the pane header already says 「数据管理」.
    return AppSection(
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
    ];
    final reset = (onPressed: () => _resetSettings(context, l10n), icon: Icons.refresh, label: l10n.resetAllSettings, color: colorScheme.error);

    // The scratch-file control is its own widget rather than another record:
    // it carries a measured size in its label, which means state and a reload
    // after the clear. It goes second to last, so the two actions that throw
    // something away stay together at the end.
    final buttons = <Widget>[
      ...actions.map((a) => _buildActionBtn(context, a, isMobile)),
      _TempFilesButton(fullWidth: isMobile),
      _buildActionBtn(context, reset, isMobile),
    ];

    if (isMobile) {
      return Column(
        children: buttons
            .map((b) => Padding(padding: const EdgeInsets.only(bottom: 12), child: b))
            .toList(),
      );
    }

    return Wrap(spacing: 16, runSpacing: 16, children: buttons);
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
              Text(l10n.exportOptions, style: Theme.of(context).textTheme.headlineSmall),
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
    // A dialog option, not a settings row, so it takes no box — but it takes
    // the app's switch. [SwitchListTile] cannot be given one: the control is
    // built inside it, at Material's 52×32.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: textTheme.titleSmall),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
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

/// "Clear Temporary Files", with what they currently cost on the label.
///
/// The size is the point: without it this is a button whose effect the user
/// cannot see either before or after pressing it, and there is no other place
/// in the app that says how much scratch space is in use. It reloads after a
/// clear, so the number is the answer as well as the prompt.
class _TempFilesButton extends StatefulWidget {
  final bool fullWidth;

  const _TempFilesButton({required this.fullWidth});

  @override
  State<_TempFilesButton> createState() => _TempFilesButtonState();
}

class _TempFilesButtonState extends State<_TempFilesButton> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final bytes = await TempStorageService.instance.measure();
    if (mounted) setState(() => _bytes = bytes);
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context)!;
    final bytes = _bytes ?? 0;

    // The size goes in the question, not just on the button: this is the one
    // action here that can take a mask or a crop the workspace is still
    // pointing at, so what it costs and what it touches are both spelled out.
    final confirmed = await AppDialog.show<bool>(
      context,
      title: l10n.clearTempFilesConfirmTitle,
      content: Text(l10n.clearTempFilesConfirmMessage(AppConstants.formatFileSize(bytes))),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.clearTempFiles,
          variant: AppButtonVariant.destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final freed = await TempStorageService.instance.clear();
    // The workspace may have been holding a mask or a crop that just went; the
    // refresh is what drops those entries rather than leaving them pointing at
    // nothing.
    await appState.galleryState.refreshImages();
    if (!mounted) return;

    setState(() => _bytes = 0);
    AppSnackBar.success(context, l10n.tempFilesCleared(AppConstants.formatFileSize(freed)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bytes = _bytes;
    // Bare label until the walk finishes, and again once there is nothing to
    // clear -- "(0 B)" is noise, and the disabled button already says it.
    final label = (bytes == null || bytes == 0)
        ? l10n.clearTempFiles
        : '${l10n.clearTempFiles} (${AppConstants.formatFileSize(bytes)})';

    return SizedBox(
      width: widget.fullWidth ? double.infinity : 220,
      height: 50,
      child: AppButton(
        label: label,
        icon: Icons.delete_sweep_outlined,
        variant: AppButtonVariant.secondary,
        onPressed: (bytes == null || bytes == 0) ? null : _clear,
      ),
    );
  }
}
