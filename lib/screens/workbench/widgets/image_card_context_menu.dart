import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/dialogs/file_rename_dialog.dart';
import 'gallery_file_actions.dart';
import 'preview/media_preview_dialog.dart';

/// Builds and shows the right-click / long-press context menu for a gallery
/// [imageFile]. All side effects route through [AppState], [WorkbenchUIState]
/// and [gallery_file_actions], keeping this purely an action dispatcher.
void showImageCardContextMenu(
  BuildContext context, {
  required AppImage imageFile,
  required Offset position,
}) {
  final l10n = AppLocalizations.of(context)!;
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  final appState = Provider.of<AppState>(context, listen: false);
  final colorScheme = Theme.of(context).colorScheme;

  final bool isPartOfSelection = appState.isImageSelected(imageFile.path);
  final List<AppImage> filesToShare = isPartOfSelection ? appState.selectedImages : [imageFile];
  final bool isVideo = AppConstants.isVideoFile(imageFile.path);

  final List<PopupMenuEntry<dynamic>> menuItems = [
    PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.open_in_new, size: 18),
        title: Text(l10n.openInPreview),
        dense: true,
      ),
      onTap: () {
        final images = appState.galleryState.currentViewImages;
        final idx = images.indexWhere((img) => img.path == imageFile.path);
        showMediaPreview(context, galleryImages: images, initialIndex: idx >= 0 ? idx : 0);
      },
    ),
  ];

  if (!isVideo) {
    menuItems.addAll([
      PopupMenuItem(
        child: ListTile(
          leading: const Icon(Icons.brush_outlined, size: 18),
          title: Text(l10n.drawMask),
          dense: true,
        ),
        onTap: () {
          workbenchUIState.setMaskEditorSourceImage(imageFile);
          appState.setWorkbenchTab(2); // Mask Editor
        },
      ),
      PopupMenuItem(
        child: ListTile(
          leading: const Icon(Icons.crop_outlined, size: 18),
          title: Text(l10n.cropAndResize),
          dense: true,
        ),
        onTap: () {
          workbenchUIState.setCropResizeSourceImage(imageFile);
          appState.setWorkbenchTab(3); // Crop & Resize Tab
        },
      ),
    ]);
  }

  menuItems.add(const PopupMenuDivider());

  if (!isVideo) {
    menuItems.add(
      PopupMenuItem(
        child: ListTile(
          leading: Icon(isPartOfSelection ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 18),
          title: Text(isPartOfSelection ? l10n.removeFromSelection : l10n.sendToSelection),
          dense: true,
        ),
        onTap: () => appState.galleryState.toggleImageSelection(imageFile),
      ),
    );
  }

  if (!isVideo) {
    menuItems.addAll([
      PopupMenuItem(
        child: ListTile(
          leading: Icon(Icons.compare, size: 18, color: colorScheme.primary),
          title: Text(l10n.sendToComparatorRaw),
          dense: true,
        ),
        onTap: () {
          workbenchUIState.sendToComparator(imageFile.path, isAfter: false);
        },
      ),
      PopupMenuItem(
        child: ListTile(
          leading: Icon(Icons.compare, size: 18, color: colorScheme.tertiary),
          title: Text(l10n.sendToComparatorAfter),
          dense: true,
        ),
        onTap: () {
          workbenchUIState.sendToComparator(imageFile.path, isAfter: true);
        },
      ),
    ]);
  }

  if (!isVideo) {
    menuItems.addAll([
      const PopupMenuDivider(),
      PopupMenuItem(
        child: ListTile(
          leading: Icon(Icons.video_library_outlined, size: 18, color: colorScheme.secondary),
          title: Text(l10n.sendToFirstFrame),
          dense: true,
        ),
        onTap: () {
          workbenchUIState.setVideoFirstFrame(imageFile);
          appState.setWorkbenchTab(5); // Video Generation
        },
      ),
      PopupMenuItem(
        child: ListTile(
          leading: Icon(Icons.video_library_outlined, size: 18, color: colorScheme.secondary),
          title: Text(l10n.sendToLastFrame),
          dense: true,
        ),
        onTap: () {
          workbenchUIState.setVideoLastFrame(imageFile);
          appState.setWorkbenchTab(5); // Video Generation
        },
      ),
      PopupMenuItem(
        child: ListTile(
          leading: Icon(Icons.add_photo_alternate_outlined, size: 18, color: colorScheme.secondary),
          title: Text(l10n.sendToVideoReferences),
          dense: true,
        ),
        onTap: () {
          workbenchUIState.addVideoReferenceImage(imageFile);
          appState.setWorkbenchTab(5); // Video Generation
        },
      ),
      PopupMenuItem(
        child: ListTile(
          leading: Icon(Icons.assistant_outlined, size: 18, color: colorScheme.primary),
          title: Text(l10n.sendToOptimizer),
          dense: true,
        ),
        onTap: () {
          // With an active multi-selection send the whole set, mirroring the
          // share action's behavior.
          final toSend = isPartOfSelection ? appState.selectedImages : [imageFile];
          workbenchUIState.addAssistantImages(toSend);
          appState.setWorkbenchTab(4); // Prompt Assistant
        },
      ),
    ]);
  }

  menuItems.addAll([
    const PopupMenuDivider(),
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
            filePath: imageFile.path,
            onSuccess: () => appState.galleryState.refreshImages(),
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
        final filename = imageFile.name;
        Clipboard.setData(ClipboardData(text: filename));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.copiedToClipboard(filename)), duration: const Duration(seconds: 1)),
        );
      },
    ),
    PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.folder_open, size: 18),
        title: Text(l10n.openInFolder),
        dense: true,
      ),
      onTap: () async {
        await FileUtils.openFolder(imageFile.path);
      },
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      child: ListTile(
        leading: Icon(Icons.save_alt, size: 18, color: colorScheme.primary),
        title: Text(Platform.isIOS ? l10n.saveToPhotos : l10n.saveToGallery),
        dense: true,
      ),
      onTap: () => saveImageFile(context, imageFile.path, imageFile.name, l10n),
    ),
    PopupMenuItem(
      child: ListTile(
        leading: const Icon(Icons.share_outlined, size: 18),
        title: Text(filesToShare.length > 1 ? l10n.shareFiles(filesToShare.length) : l10n.share),
        dense: true,
      ),
      onTap: () => shareImageFiles(context, filesToShare, l10n, position: position),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      child: ListTile(
        leading: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
        title: Text(l10n.delete, style: TextStyle(color: colorScheme.error)),
        dense: true,
      ),
      onTap: () {
        WidgetsBinding.instance.addPostFrameCallback((_) => confirmAndDeleteImageFile(context, imageFile, l10n));
      },
    ),
  ]);

  showMenu<dynamic>(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
    items: menuItems,
  );
}
