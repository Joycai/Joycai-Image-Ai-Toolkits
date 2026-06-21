import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../state/app_state.dart';

/// Import / export helpers for the Prompt Library.
///
/// These keep file-picking, JSON (de)serialization and user feedback out of the
/// screen widget. They show their own snackbars and dialogs via the given
/// [context]; callers should reload their lists after [importPrompts] succeeds.

/// Export tags + user/system prompts to a user-chosen JSON file.
Future<void> exportPrompts(
  BuildContext context,
  AppLocalizations l10n, {
  required List<PromptTag> tags,
  required List<Prompt> userPrompts,
  required List<SystemPrompt> systemPrompts,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final data = {
    'tags': tags.map((t) => t.toMap()).toList(),
    'user_prompts': userPrompts.map((p) => {
          ...p.toMap(),
          'tags': p.tags.map((t) => t.toMap()).toList(),
        }).toList(),
    'system_prompts': systemPrompts.map((p) => {
          ...p.toMap(),
          'tags': p.tags.map((t) => t.toMap()).toList(),
        }).toList(),
    'export_type': 'prompts_only',
    'version': 1,
  };

  final json = jsonEncode(data);
  final bytes = utf8.encode(json);

  String? path = await FilePicker.saveFile(
    fileName: 'joycai_prompts.json',
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: bytes,
  );

  if (path != null && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await File(path).writeAsString(json);
  }

  if (path != null && context.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsExported)));
  }
}

/// Pick a JSON file, prompt for merge/replace, and import the prompt data.
/// Returns `true` if data was imported (caller should reload).
Future<bool> importPrompts(BuildContext context, AppLocalizations l10n) async {
  final appState = Provider.of<AppState>(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final successMsg = l10n.settingsImported;
  final errorColor = Theme.of(context).colorScheme.error;

  FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
  if (!context.mounted || result == null) return false;

  final String? importMode = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.importMode),
      content: Text(l10n.importModeDesc),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'merge'),
          child: Text(l10n.merge),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, 'replace'),
          child: Text(l10n.replaceAll),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );

  if (importMode == null) return false;

  try {
    final file = File(result.files.single.path!);
    final String content = await file.readAsString();
    final Map<String, dynamic> data = jsonDecode(content);

    await appState.importPromptData(data, replace: importMode == 'replace');

    messenger.showSnackBar(SnackBar(content: Text(successMsg)));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.importFailed(e.toString())),
      backgroundColor: errorColor,
    ));
    return false;
  }
}
