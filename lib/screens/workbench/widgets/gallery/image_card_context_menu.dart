import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_shortcuts.dart';
import '../../../../core/constants.dart';
import '../../../../core/file_utils.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_image.dart';
import '../../../../services/db/repositories/image_layer_repository.dart';
import '../../../../state/app_state.dart';
import '../../../../state/gallery_state.dart';
import '../../../../state/workbench_ui_state.dart';
import '../../../../widgets/dialogs/file_rename_dialog.dart';
import '../../../../widgets/glass/app_glass_menu.dart';
import '../../../../widgets/ui/app_key_label.dart';
import '../../../../widgets/ui/app_snackbar.dart';
import '../layers/layer_canvas_page.dart';
import '../preview/media_preview_dialog.dart';
import 'gallery_file_actions.dart';

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
/// See `file_context_menu._keys`: the key a row really has, from the table.
String? _keys(String id) => AppKeyLabel.menuHint(AppShortcuts.byId(id));

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

  // Asked only of a file the layer index knows, so an ordinary picture's
  // menu opens without touching the database; null when nothing is left to
  // stack, and then the row is not offered (`A7 · 7b`).
  final layerSet = !multi &&
          ImageLayerRepository.layeredPaths.value.containsKey(imageFile.path)
      ? await ImageLayerRepository().setFor(imageFile.path)
      : null;
  if (!context.mounted) return;

  final bool inTempWorkspace =
      appState.galleryState.viewMode == GalleryViewMode.temp;

  final entries = <AppGlassMenuEntry>[
    if (isVideo)
      AppGlassMenuItem(
          icon: Icons.visibility_outlined,
          label: l10n.openInPreview,
          trailing: _keys(AppShortcutIds.preview),
          onSelected: openPreview)
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
    if (layerSet != null)
      AppGlassMenuItem(
        icon: Icons.layers_outlined,
        label: l10n.menuOpenLayers,
        trailing: l10n.menuLayerCount(layerSet.overlays.length),
        onSelected: () => showLayerCanvas(context, layerSet, imageFile.path),
      ),
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
          trailing: _keys(AppShortcutIds.rename),
          onSelected: () {
            if (!context.mounted) return;
            showFileRenameDialog(
              context: context,
              filePath: imageFile.path,
              onSuccess: appState.galleryState.refreshImages,
            );
          },
        ),
        AppGlassMenuItem(
          icon: Icons.content_copy_outlined,
          label: l10n.copyFilename,
          trailing: _keys(AppShortcutIds.copyFileName),
          // The whole selection, one name per line — what `⇧⌘C` does. A row
          // that carries a key's badge and then acts on one file while the
          // key acts on five is the drift this round exists to remove.
          onSelected: () {
            Clipboard.setData(
              ClipboardData(text: targets.map((i) => i.name).join('\n')),
            );
            if (!context.mounted) return;
            AppSnackBar.success(
              context,
              multi
                  ? l10n.copiedFilenames(targets.length)
                  : l10n.copiedToClipboard(imageFile.name),
            );
          },
        ),
        AppGlassMenuItem(
          icon: Icons.folder_open_outlined,
          label: l10n.openInFolder,
          trailing: _keys(AppShortcutIds.revealInFileManager),
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
    // `Delete` is the one key in this round that means two things (plan D2),
    // and this pair of rows is its only explanation: in the temporary
    // workspace the key takes the picture out of the basket, everywhere else
    // it deletes the file. Whichever meaning is in force carries the badge,
    // so the menu can be read instead of the rule being remembered.
    if (inTempWorkspace)
      AppGlassMenuItem(
        icon: Icons.remove_circle_outline,
        label: l10n.removeFromWorkspace,
        trailing: _keys(AppShortcutIds.delete),
        onSelected: () => appState.galleryState
            .removeDroppedImages(targets.map((i) => i.path).toList()),
      ),
    AppGlassMenuItem(
      icon: Icons.delete_outline,
      // The dialog says which it will be — trash where the platform has one,
      // a permanent delete only where it does not — so the row no longer has
      // to guess per platform.
      //
      // `targets`, like the share row above and like the key: the count is
      // in the label so a selection of five cannot be mistaken for the one
      // picture under the pointer.
      label: multi ? l10n.deleteFiles(targets.length) : l10n.delete,
      trailing: inTempWorkspace ? null : _keys(AppShortcutIds.delete),
      danger: true,
      onSelected: () {
        if (!context.mounted) return;
        // Copied: the run refreshes the gallery at the end, which rewrites
        // the live selection this list is.
        confirmAndDeleteImageFiles(context, List<AppImage>.of(targets));
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
