import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';

/// Backup-import flow for the setup wizard.
///
/// Self-contained: picks a JSON backup, lets the user choose what to restore
/// (responsive dialog vs. bottom sheet), applies it, then completes setup and
/// closes the wizard. Kept out of the wizard widget so the step UI stays lean.

/// Pick a backup file, confirm what to import, restore it and finish setup.
Future<void> importBackupSettings(BuildContext context, AppLocalizations l10n) async {
  final appState = Provider.of<AppState>(context, listen: false);
  final isMobile = MediaQuery.of(context).size.width < 600;

  FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
  if (!context.mounted || result == null) return;

  try {
    final file = File(result.files.single.path!);
    final fileContent = await file.readAsString();
    if (!context.mounted) return;
    final Map<String, dynamic> data = jsonDecode(fileContent);

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
    await appState.completeSetup();
    if (!context.mounted) return;
    Navigator.of(context).pop();
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
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
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
