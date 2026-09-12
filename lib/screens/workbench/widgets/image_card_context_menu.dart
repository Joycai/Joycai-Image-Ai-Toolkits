import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../state/app_state.dart';
import '../../../state/gallery_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/dialogs/file_rename_dialog.dart';
import '../../../widgets/glass/app_glass_menu.dart';
import 'gallery_file_actions.dart';
import 'preview/media_preview_dialog.dart';

/// Builds and shows the right-click / long-press context menu for a gallery
/// [imageFile] — the same G2 glass menu the file browser opens, in groups of
/// open · edit | selection · comparator | video · assistant | rename · copy ·
/// reveal | save · share | remove · delete.
///
/// All side effects route through [AppState], [WorkbenchUIState] and
/// [gallery_file_actions], keeping this purely an action dispatcher. Every
/// [AppGlassMenuItem.onSelected] runs once the menu has been popped, so the
/// dialogs opened from here need no post-frame deferral.
void showImageCardContextMenu(
  BuildContext context, {
  required AppImage imageFile,
  required Offset position,
}) {
  final l10n = AppLocalizations.of(context)!;
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  final appState = Provider.of<AppState>(context, listen: false);

  final bool isPartOfSelection = appState.isImageSelected(imageFile.path);
  final List<AppImage> filesToShare = isPartOfSelection ? appState.selectedImages : [imageFile];
  final bool isVideo = AppConstants.isVideoFile(imageFile.path);

  showAppGlassMenu(
    context,
    position: position,
    entries: <AppGlassMenuEntry>[
      AppGlassMenuItem(
        icon: Icons.open_in_new,
        label: l10n.openInPreview,
        onSelected: () {
          if (!context.mounted) return;
          final images = appState.galleryState.currentViewImages;
          final idx = images.indexWhere((img) => img.path == imageFile.path);
          showMediaPreview(
            context,
            galleryImages: images,
            initialIndex: idx >= 0 ? idx : 0,
            heroScope: kWorkbenchPreviewHeroScope,
          );
        },
      ),
      if (!isVideo) ...[
        AppGlassMenuItem(
          icon: Icons.brush_outlined,
          label: l10n.drawMask,
          onSelected: () {
            workbenchUIState.setMaskEditorSourceImage(imageFile);
            appState.setWorkbenchTab(2); // Mask Editor
          },
        ),
        AppGlassMenuItem(
          icon: Icons.crop_outlined,
          label: l10n.cropAndResize,
          onSelected: () {
            workbenchUIState.setCropResizeSourceImage(imageFile);
            appState.setWorkbenchTab(3); // Crop & Resize Tab
          },
        ),
        const AppGlassMenuDivider(),
        AppGlassMenuItem(
          icon: isPartOfSelection ? Icons.remove_circle_outline : Icons.add_circle_outline,
          label: isPartOfSelection ? l10n.removeFromSelection : l10n.sendToSelection,
          onSelected: () => appState.galleryState.toggleImageSelection(imageFile),
        ),
        AppGlassMenuItem(
          icon: Icons.compare,
          label: l10n.sendToComparatorRaw,
          onSelected: () => workbenchUIState.sendToComparator(imageFile.path, isAfter: false),
        ),
        AppGlassMenuItem(
          icon: Icons.compare,
          label: l10n.sendToComparatorAfter,
          onSelected: () => workbenchUIState.sendToComparator(imageFile.path, isAfter: true),
        ),
        const AppGlassMenuDivider(),
        AppGlassMenuItem(
          icon: Icons.video_library_outlined,
          label: l10n.sendToFirstFrame,
          onSelected: () {
            workbenchUIState.setVideoFirstFrame(imageFile);
            appState.setWorkbenchTab(5); // Video Generation
          },
        ),
        AppGlassMenuItem(
          icon: Icons.video_library_outlined,
          label: l10n.sendToLastFrame,
          onSelected: () {
            workbenchUIState.setVideoLastFrame(imageFile);
            appState.setWorkbenchTab(5); // Video Generation
          },
        ),
        AppGlassMenuItem(
          icon: Icons.add_photo_alternate_outlined,
          label: l10n.sendToVideoReferences,
          onSelected: () {
            workbenchUIState.addVideoReferenceImage(imageFile);
            appState.setWorkbenchTab(5); // Video Generation
          },
        ),
        AppGlassMenuItem(
          icon: Icons.assistant_outlined,
          label: l10n.sendToOptimizer,
          onSelected: () {
            // With an active multi-selection send the whole set, mirroring the
            // share action's behavior.
            final toSend = isPartOfSelection ? appState.selectedImages : [imageFile];
            workbenchUIState.addAssistantImages(toSend);
            appState.setWorkbenchTab(4); // Prompt Assistant
          },
        ),
      ],
      const AppGlassMenuDivider(),
      AppGlassMenuItem(
        icon: Icons.edit_outlined,
        label: l10n.rename,
        onSelected: () {
          if (!context.mounted) return;
          showFileRenameDialog(
            context: context,
            filePath: imageFile.path,
            onSuccess: () => appState.galleryState.refreshImages(),
          );
        },
      ),
      AppGlassMenuItem(
        icon: Icons.content_copy_outlined,
        label: l10n.copyFilename,
        onSelected: () {
          final filename = imageFile.name;
          Clipboard.setData(ClipboardData(text: filename));
          if (!context.mounted) return;
          AppSnackBar.success(context, l10n.copiedToClipboard(filename));
        },
      ),
      AppGlassMenuItem(
        icon: Icons.folder_open_outlined,
        label: l10n.openInFolder,
        onSelected: () => FileUtils.openFolder(imageFile.path),
      ),
      const AppGlassMenuDivider(),
      AppGlassMenuItem(
        icon: Icons.save_alt,
        label: Platform.isIOS ? l10n.saveToPhotos : l10n.saveToGallery,
        onSelected: () {
          if (!context.mounted) return;
          saveImageFile(context, imageFile.path, imageFile.name, l10n);
        },
      ),
      AppGlassMenuItem(
        icon: Icons.ios_share,
        label: filesToShare.length > 1 ? l10n.shareFiles(filesToShare.length) : l10n.share,
        onSelected: () {
          if (!context.mounted) return;
          shareImageFiles(context, filesToShare, l10n, position: position);
        },
      ),
      const AppGlassMenuDivider(),
      // Only in the workspace view, where it is unambiguous what the picture
      // would be removed *from*. Elsewhere the same file may also sit in the
      // workspace, and an entry that quietly reached into another view to
      // change it would be acting on something not on screen. Sits above
      // Delete as the softer of the two: this drops a reference, Delete goes
      // to the file.
      if (appState.galleryState.viewMode == GalleryViewMode.temp)
        AppGlassMenuItem(
          icon: Icons.remove_circle_outline,
          label: l10n.removeFromWorkspace,
          onSelected: () => appState.galleryState.removeDroppedImage(imageFile.path),
        ),
      AppGlassMenuItem(
        icon: Icons.delete_outline,
        label: l10n.delete,
        danger: true,
        onSelected: () {
          if (!context.mounted) return;
          confirmAndDeleteImageFile(context, imageFile, l10n);
        },
      ),
    ],
  );
}
