import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/app_file.dart';
import '../../../models/browser_file.dart';
import '../../../state/window_state.dart';
import '../../../widgets/dialogs/file_rename_dialog.dart';
import '../../../widgets/dialogs/mask_editor_dialog.dart';

void showFileContextMenu({
  required BuildContext context,
  required BrowserFile file,
  required Offset position,
  required WindowState windowState,
  required VoidCallback onRefresh,
}) {
  final l10n = AppLocalizations.of(context)!;
  final bool isImage = file.category == FileCategory.image;
  final bool isMediaOrText = [FileCategory.video, FileCategory.audio, FileCategory.text].contains(file.category);

  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
    items: [
      if (isImage) ...[
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.open_in_new, size: 18),
            title: Text(l10n.openInPreview),
            dense: true,
          ),
          onTap: () {
            windowState.openFloatingPreview(file.path);
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.brush_outlined, size: 18),
            title: Text(l10n.drawMask),
            dense: true,
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showDialog(
                context: context,
                builder: (context) => MaskEditorDialog(
                  sourceImage: AppFile(path: file.path, name: file.name),
                ),
              );
            });
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.compare, size: 18),
            title: Text(l10n.sendToComparator),
            dense: true,
          ),
          onTap: () {
            windowState.sendToComparator(file.path);
          },
        ),
      ],
      if (isMediaOrText)
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.launch, size: 18),
            title: Text(l10n.openWithSystemDefault),
            dense: true,
          ),
          onTap: () async {
            final uri = Uri.file(file.path);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          },
        ),
      PopupMenuItem(
        child: ListTile(
          leading: const Icon(Icons.edit_outlined, size: 18),
          title: Text(l10n.rename),
          dense: true,
        ),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showFileRenameDialog(
              context: context,
              filePath: file.path,
              onSuccess: onRefresh,
            );
          });
        },
      ),
      PopupMenuItem(
        child: ListTile(
          leading: const Icon(Icons.copy, size: 18),
          title: Text(l10n.copyFilename),
          dense: true,
        ),
        onTap: () {
          Clipboard.setData(ClipboardData(text: file.name));
        },
      ),
      PopupMenuItem(
        child: ListTile(
          leading: const Icon(Icons.folder_open, size: 18),
          title: Text(l10n.openInFolder),
          dense: true,
        ),
        onTap: () async {
          final uri = Uri.directory(File(file.path).parent.path);
          if (await canLaunchUrl(uri)) await launchUrl(uri);
        },
      ),
    ],
  );
}
