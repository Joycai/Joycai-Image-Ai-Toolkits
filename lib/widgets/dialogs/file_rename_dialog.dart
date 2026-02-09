import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';

Future<void> showFileRenameDialog({
  required BuildContext context,
  required String filePath,
  required VoidCallback onSuccess,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final file = File(filePath);
  final dir = p.dirname(file.path);
  final extension = p.extension(file.path);
  final nameStem = p.basenameWithoutExtension(file.path);

  final controller = TextEditingController(text: nameStem);

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.renameFile),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.newFilename,
              suffixText: extension,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (val) => Navigator.pop(context, true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.rename),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    final newName = controller.text.trim();
    if (newName.isEmpty || newName == nameStem) {
      return;
    }

    final newFilename = '$newName$extension';
    final newPath = p.join(dir, newFilename);

    if (File(newPath).existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.fileAlreadyExists), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    try {
      await file.rename(newPath);
      onSuccess();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.renameSuccess), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.renameFailed(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }
}
