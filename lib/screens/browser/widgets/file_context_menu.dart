import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_file.dart';
import '../../../models/browser_file.dart';
import '../../../state/app_state.dart';
import '../../../state/window_state.dart';
import '../../../widgets/dialogs/file_rename_dialog.dart';

void showFileContextMenu({
  required BuildContext context,
  required BrowserFile file,
  required Offset position,
  required WindowState windowState,
  required VoidCallback onRefresh,
}) {
  final l10n = AppLocalizations.of(context)!;
  final appState = Provider.of<AppState>(context, listen: false);
  
  final bool isImage = file.category == FileCategory.image;
  final bool isMediaOrText = [FileCategory.video, FileCategory.audio, FileCategory.text].contains(file.category);

  final bool isPartOfSelection = appState.browserState.selectedFiles.contains(file);
  final List<BrowserFile> filesToShare = isPartOfSelection 
      ? appState.browserState.selectedFiles.toList() 
      : [file];

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
            windowState.openPreview(file.path);
            appState.setSidebarMode(SidebarMode.preview);
            if (!appState.isSidebarExpanded) appState.setSidebarExpanded(true);
          },
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.brush_outlined, size: 18),
            title: Text(l10n.drawMask),
            dense: true,
          ),
          onTap: () {
            windowState.setMaskEditorSourceImage(AppFile(path: file.path, name: file.name));
            appState.setSidebarMode(SidebarMode.maskEditor);
            if (!appState.isSidebarExpanded) appState.setSidebarExpanded(true);
          },
        ),
        if (!windowState.isComparatorOpen)
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.compare, size: 18),
              title: Text(l10n.sendToComparator),
              dense: true,
            ),
            onTap: () {
              windowState.sendToComparator(file.path);
              appState.setSidebarMode(SidebarMode.comparator);
              if (!appState.isSidebarExpanded) appState.setSidebarExpanded(true);
            },
          )
        else ...[
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.compare, size: 18, color: Colors.blue),
              title: Text(l10n.sendToComparatorRaw),
              dense: true,
            ),
            onTap: () {
              windowState.sendToComparator(file.path, isAfter: false);
              appState.setSidebarMode(SidebarMode.comparator);
              if (!appState.isSidebarExpanded) appState.setSidebarExpanded(true);
            },
          ),
          PopupMenuItem(
            child: ListTile(
              leading: const Icon(Icons.compare, size: 18, color: Colors.orange),
              title: Text(l10n.sendToComparatorAfter),
              dense: true,
            ),
            onTap: () {
              windowState.sendToComparator(file.path, isAfter: true);
              appState.setSidebarMode(SidebarMode.comparator);
              if (!appState.isSidebarExpanded) appState.setSidebarExpanded(true);
            },
          ),
        ],
      ],
      PopupMenuItem(
        child: ListTile(
          leading: const Icon(Icons.share_outlined, size: 18),
          title: Text(filesToShare.length > 1 ? l10n.shareFiles(filesToShare.length) : l10n.share),
          dense: true,
        ),
        onTap: () async {
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
            );
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Share failed: $e')),
              );
            }
          }
        },
      ),
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
