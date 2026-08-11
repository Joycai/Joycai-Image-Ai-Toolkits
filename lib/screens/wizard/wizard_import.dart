import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/backup_error_text.dart';
import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/dialogs/import_options_dialog.dart';

/// Backup-import flow for the setup wizard.
///
/// Self-contained: picks a JSON backup, lets the user choose what to restore
/// (responsive dialog vs. bottom sheet), applies it, then completes setup and
/// closes the wizard. Kept out of the wizard widget so the step UI stays lean.

/// Pick a backup file, confirm what to import, restore it and finish setup.
Future<void> importBackupSettings(BuildContext context, AppLocalizations l10n) async {
  final appState = Provider.of<AppState>(context, listen: false);

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

    final bool? confirmed = await showImportOptionsDialog(
      context,
      l10n: l10n,
      hasDirs: hasDirs,
      hasPrompts: hasPrompts,
      hasUsage: hasUsage,
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
    if (!context.mounted) return;
    await appState.completeSetup();
    if (!context.mounted) return;
    Navigator.of(context).pop();
  } catch (e) {
    if (!context.mounted) return;
    AppSnackBar.error(context, backupImportErrorText(l10n, e));
  }
}
