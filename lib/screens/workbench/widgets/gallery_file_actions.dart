import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../state/app_state.dart';

/// File-system side effects for gallery items (save / share / delete).
///
/// Kept separate from the card and context-menu UI so the widgets stay
/// presentation-only. Each function shows its own user feedback via the given
/// [context] and triggers a gallery refresh where appropriate.

/// Save a single file: a save-dialog on desktop, the system gallery on mobile.
Future<void> saveImageFile(
  BuildContext context,
  String sourcePath,
  String fileName,
  AppLocalizations l10n,
) async {
  try {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final extension = sourcePath.split('.').last;
      final bytes = await File(sourcePath).readAsBytes();
      final outputFile = await FilePicker.saveFile(
        dialogTitle: l10n.save,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );

      if (outputFile != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsExported), backgroundColor: Colors.green),
        );
      }
    } else {
      if (AppConstants.isVideoFile(sourcePath)) {
        await Gal.putVideo(sourcePath);
      } else {
        await Gal.putImage(sourcePath);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.savedToPhotos), backgroundColor: Colors.green),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.saveFailed(e.toString())), backgroundColor: Colors.red),
      );
    }
  }
}

/// Share one or more files via the platform share sheet.
Future<void> shareImageFiles(
  BuildContext context,
  List<AppImage> filesToShare,
  AppLocalizations l10n, {
  required Offset position,
}) async {
  try {
    final xFiles = filesToShare.map((f) => XFile(
          f.path,
          name: f.name,
          mimeType: AppConstants.getMimeType(f.path),
        )).toList();

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      xFiles,
      subject: filesToShare.length == 1 ? filesToShare.first.name : l10n.appTitle,
      sharePositionOrigin: Rect.fromLTWH(position.dx, position.dy, 1, 1),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.shareFailed(e.toString()))),
      );
    }
  }
}

/// Confirm then delete a file (recycle bin on Windows, hard delete elsewhere).
Future<void> confirmAndDeleteImageFile(
  BuildContext context,
  AppImage imageFile,
  AppLocalizations l10n,
) async {
  final filename = imageFile.name;
  final isWindows = Platform.isWindows;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deleteFileConfirmTitle),
      content: Text(l10n.deleteFileConfirmMessage(filename)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: Text(isWindows ? l10n.moveToTrash : l10n.permanentlyDelete),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await _deleteImageFile(context, imageFile, l10n);
  }
}

Future<void> _deleteImageFile(
  BuildContext context,
  AppImage imageFile,
  AppLocalizations l10n,
) async {
  final appState = Provider.of<AppState>(context, listen: false);

  try {
    if (Platform.isWindows) {
      final path = imageFile.path
          .replaceAll("'", "''")
          .replaceAll('`', '``')
          .replaceAll(r'$', r'`$');
      final result = await Process.run(
        'powershell',
        [
          '-Command',
          "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('$path', 'OnlyErrorDialogs', 'SendToRecycleBin')"
        ],
      );

      if (result.exitCode != 0) {
        throw Exception('PowerShell Error: ${result.stderr}');
      }
    } else {
      await File(imageFile.path).delete();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deleteSuccess), backgroundColor: Colors.green),
      );
      appState.galleryState.refreshImages();
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deleteFailed(e.toString())), backgroundColor: Colors.red),
      );
    }
  }
}
