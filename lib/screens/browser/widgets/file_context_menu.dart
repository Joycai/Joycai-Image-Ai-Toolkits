import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../state/window_state.dart';

void showFileContextMenu({
  required BuildContext context,
  required BrowserFile file,
  required Offset position,
  required WindowState windowState,
}) {
  final l10n = AppLocalizations.of(context)!;

  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
    items: [
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
          leading: const Icon(Icons.compare, size: 18),
          title: Text(l10n.sendToComparator),
          dense: true,
        ),
        onTap: () {
          windowState.sendToComparator(file.path);
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
