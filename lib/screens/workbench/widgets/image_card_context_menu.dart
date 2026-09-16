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
import '../../../widgets/ui/app_snackbar.dart';
import '../../../widgets/dialogs/file_rename_dialog.dart';
import '../../../widgets/glass/app_glass_menu.dart';
import 'gallery_file_actions.dart';
import 'preview/media_preview_dialog.dart';

/// The width of the gallery card's menu (`A1 · 2a`: 「240 宽」).
const double kImageCardMenuWidth = 240;

/// The right-click / long-press menu of a gallery [imageFile] — `A1 · 2a`.
///
/// The old menu was eighteen equal rows and five rules, some 550 tall, so a
/// right-click in the lower half of an 860 window flipped it. This one is 240
/// wide and eight rows: the four high-frequency actions (preview · mask ·
/// crop · assistant) are a block of four cells across the top; the four
/// mutually exclusive 「设为 ×」 assignments are a 2×2 grid under a 「设为」
/// heading; 「反馈给助手」 (`3a`) closes the selection group, greyed on a
/// picture without a run to judge;
/// rename · copy name · reveal fold into 「文件 ▸」 and save · share into
/// 「导出 ▸」; the destructive rows stay at the bottom, delete in the error ink.
///
/// With several cards selected the quick block stays and the 「设为」 grid goes
/// (an assignment takes one picture), and the share row carries the count.
/// A video keeps only what applies to it: preview as a row, the file and
/// export groups, and the destructive rows.
///
/// All side effects route through [AppState], [WorkbenchUIState] and
/// [gallery_file_actions], keeping this purely an action dispatcher. Every
/// action runs once the menu has been popped, so the dialogs opened from here
/// need no post-frame deferral. While the menu is up the gallery's selection
/// bar hides (`A1` 玻璃预算: 「菜单打开即隐操作条」).
Future<void> showImageCardContextMenu(
  BuildContext context, {
  required AppImage imageFile,
  required Offset position,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  final appState = Provider.of<AppState>(context, listen: false);

  final bool isPartOfSelection = appState.isImageSelected(imageFile.path);
  final List<AppImage> targets = isPartOfSelection ? appState.selectedImages : [imageFile];
  final bool multi = targets.length > 1;
  final bool isVideo = AppConstants.isVideoFile(imageFile.path);

  void openPreview() {
    if (!context.mounted) return;
    final images = appState.galleryState.currentViewImages;
    final idx = images.indexWhere((img) => img.path == imageFile.path);
    showMediaPreview(
      context,
      galleryImages: images,
      initialIndex: idx >= 0 ? idx : 0,
      heroScope: kWorkbenchPreviewHeroScope,
    );
  }

  final entries = <AppGlassMenuEntry>[
    if (isVideo)
      AppGlassMenuItem(icon: Icons.visibility_outlined, label: l10n.openInPreview, onSelected: openPreview)
    else
      AppGlassMenuQuickBlock([
        AppGlassMenuQuickCell(icon: Icons.visibility_outlined, label: l10n.preview, onSelected: openPreview),
        AppGlassMenuQuickCell(
          icon: Icons.brush_outlined,
          label: l10n.menuQuickMask,
          onSelected: () {
            workbenchUIState.setMaskEditorSourceImage(imageFile);
            appState.setWorkbenchTab(2); // Mask Editor
          },
        ),
        AppGlassMenuQuickCell(
          icon: Icons.crop_outlined,
          label: l10n.menuQuickCrop,
          onSelected: () {
            workbenchUIState.setCropResizeSourceImage(imageFile);
            appState.setWorkbenchTab(3); // Crop & Resize
          },
        ),
        AppGlassMenuQuickCell(
          icon: Icons.assistant_outlined,
          label: l10n.menuQuickAssistant,
          onSelected: () {
            // With an active multi-selection send the whole set, mirroring
            // the share action's behavior.
            workbenchUIState.addAssistantImages(targets);
            appState.setWorkbenchTab(4); // Prompt Assistant
          },
        ),
      ]),
    const AppGlassMenuDivider(),
    if (!isVideo && !multi) ...[
      AppGlassMenuHeading(l10n.menuSetAs),
      AppGlassMenuGrid([
        AppGlassMenuItem(
          icon: Icons.looks_one_outlined,
          label: l10n.menuSetAsRaw,
          onSelected: () => workbenchUIState.sendToComparator(imageFile.path, isAfter: false),
        ),
        AppGlassMenuItem(
          icon: Icons.looks_two_outlined,
          label: l10n.menuSetAsAfter,
          onSelected: () => workbenchUIState.sendToComparator(imageFile.path, isAfter: true),
        ),
        AppGlassMenuItem(
          icon: Icons.first_page,
          label: l10n.menuSetAsFirstFrame,
          onSelected: () {
            workbenchUIState.setVideoFirstFrame(imageFile);
            appState.setWorkbenchTab(5); // Video Generation
          },
        ),
        AppGlassMenuItem(
          icon: Icons.last_page,
          label: l10n.menuSetAsLastFrame,
          onSelected: () {
            workbenchUIState.setVideoLastFrame(imageFile);
            appState.setWorkbenchTab(5); // Video Generation
          },
        ),
      ]),
      const AppGlassMenuDivider(),
    ],
    if (!isVideo) ...[
      AppGlassMenuItem(
        icon: isPartOfSelection ? Icons.remove_circle_outline : Icons.add_circle_outline,
        label: isPartOfSelection ? l10n.removeFromSelection : l10n.sendToSelection,
        onSelected: () => appState.galleryState.toggleImageSelection(imageFile),
      ),
      AppGlassMenuItem(
        icon: Icons.add_photo_alternate_outlined,
        label: l10n.sendToVideoReferences,
        onSelected: () {
          workbenchUIState.addVideoReferenceImage(imageFile);
          appState.setWorkbenchTab(5); // Video Generation
        },
      ),
      // `3a`: the verdict on one run, distinct from the quick block's
      // 「助手」 (which hands the picture to the conversation). Greyed while
      // the conversation has staged no prompt — nothing to judge — and gone
      // under a multi-selection, since a verdict is about one picture.
      if (!multi)
        AppGlassMenuItem(
          icon: Icons.rate_review_outlined,
          label: l10n.optResultFeedbackAction,
          enabled: canSendResultFeedback(workbenchUIState, imageFile.path),
          onSelected: () {
            if (!context.mounted) return;
            sendResultFeedbackFromGallery(context, imageFile);
          },
        ),
      const AppGlassMenuDivider(),
    ],
    AppGlassMenuItem(
      icon: Icons.description_outlined,
      label: l10n.menuFileGroup,
      children: [
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
      ],
    ),
    AppGlassMenuItem(
      icon: Icons.ios_share,
      label: l10n.menuExportGroup,
      children: [
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
          label: multi ? l10n.shareFiles(targets.length) : l10n.share,
          onSelected: () {
            if (!context.mounted) return;
            shareImageFiles(context, targets, l10n, position: position);
          },
        ),
      ],
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
      // The row says what the confirm will do: Windows sends the file to the
      // recycle bin, the others delete it outright.
      label: Platform.isWindows ? l10n.moveToTrash : l10n.delete,
      danger: true,
      onSelected: () {
        if (!context.mounted) return;
        confirmAndDeleteImageFile(context, imageFile, l10n);
      },
    ),
  ];

  workbenchUIState.setGalleryMenuOpen(true);
  try {
    await showAppGlassMenu(context, position: position, entries: entries, width: kImageCardMenuWidth);
  } finally {
    workbenchUIState.setGalleryMenuOpen(false);
  }
}
