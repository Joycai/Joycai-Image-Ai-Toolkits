import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../state/app_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';

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

  // file_picker >= 12 writes `bytes` itself on every platform and returns the
  // destination as a Uri, so no follow-up write is needed here.
  final Uri? saved = await FilePicker.saveFile(
    fileName: 'joycai_prompts.json',
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: bytes,
  );

  if (saved != null && context.mounted) {
    AppSnackBar.success(context, l10n.settingsExported);
  }
}

/// Pick a JSON file, prompt for merge/replace, and import the prompt data.
/// Returns `true` if data was imported (caller should reload).
Future<bool> importPrompts(BuildContext context, AppLocalizations l10n) async {
  final appState = Provider.of<AppState>(context, listen: false);
  final successMsg = l10n.settingsImported;

  final PlatformFile? picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
  if (!context.mounted || picked == null) return false;

  final String? importMode = await AppDialog.show<String>(
    context,
    title: l10n.importMode,
    content: Text(l10n.importModeDesc),
    actions: [
      AppButton(
        label: l10n.merge,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context, 'merge'),
      ),
      AppButton(
        label: l10n.replaceAll,
        variant: AppButtonVariant.destructive,
        onPressed: () => Navigator.pop(context, 'replace'),
      ),
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );

  if (importMode == null) return false;

  try {
    final String content = utf8.decode(await picked.readAsBytes());
    final Map<String, dynamic> data = jsonDecode(content);

    await appState.importPromptData(data, replace: importMode == 'replace');

    if (!context.mounted) return true;
    AppSnackBar.success(context, successMsg);
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    AppSnackBar.error(context, l10n.importFailed(e.toString()));
    return false;
  }
}
