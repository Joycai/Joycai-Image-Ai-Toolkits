import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../models/browser_file.dart';
import '../../../state/app_state.dart';
import '../../../state/file_staging_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/dialogs/file_rename_dialog.dart';
import '../../workbench/widgets/preview/media_preview_dialog.dart';
import '../../../widgets/glass/app_glass_menu.dart';

/// The file context menu — `B1a · 1b`: G2 glass, 230 wide, four groups.
///
/// Open (preview · system default) | selection · staging | rename · copy name
/// | reveal · share. Staging and sharing act on the same set: right-clicking
/// inside the selection means the selection, outside it means that one file,
/// and the count on the right of those rows says which.
void showFileContextMenu({
  required BuildContext context,
  required BrowserFile file,
  required Offset position,
  required WorkbenchUIState workbenchUIState,
  required VoidCallback onRefresh,
}) {
  final l10n = AppLocalizations.of(context)!;
  final appState = Provider.of<AppState>(context, listen: false);
  final staging = Provider.of<FileStagingState>(context, listen: false);
  final browser = appState.fileBrowserState;

  final bool isImage = file.category == FileCategory.image;
  // `other` stays out: it is whatever the scan could not classify, and
  // handing an unknown file to the shell from a menu is not an open.
  final bool canOpenWithSystem = file.category != FileCategory.other;

  final bool isPartOfSelection = browser.selectedFiles.contains(file);
  final List<BrowserFile> targets = isPartOfSelection ? browser.selectedFiles.toList() : [file];
  final bool allStaged = targets.every((f) => staging.contains(f.path));
  final String? countHint = targets.length > 1 ? '${targets.length}' : null;

  showAppGlassMenu(
    context,
    position: position,
    entries: [
      if (isImage)
        AppGlassMenuItem(
          icon: Icons.visibility_outlined,
          label: l10n.openInPreview,
          trailing: 'Enter',
          onSelected: () {
            if (!context.mounted) return;
            final imageFiles = browser.filteredFiles
                .where((f) => f.category == FileCategory.image)
                .map((f) => AppImage(path: f.path, name: f.name))
                .toList();
            final initialIdx = imageFiles.indexWhere((img) => img.path == file.path);
            showMediaPreview(
              context,
              galleryImages: imageFiles,
              initialIndex: initialIdx >= 0 ? initialIdx : 0,
              heroScope: kBrowserPreviewHeroScope,
            );
          },
        ),
      if (canOpenWithSystem)
        AppGlassMenuItem(
          icon: Icons.open_in_new,
          label: l10n.openWithSystemDefault,
          onSelected: () => FileUtils.openPath(file.path),
        ),
      if (isImage || canOpenWithSystem) const AppGlassMenuDivider(),
      AppGlassMenuItem(
        icon: isPartOfSelection ? Icons.remove_circle_outline : Icons.add_circle_outline,
        label: isPartOfSelection ? l10n.removeFromSelection : l10n.addToSelection,
        onSelected: () => browser.toggleSelection(file),
      ),
      // The second way into staging, beside the floating bar's: the bar only
      // exists once something is selected, and one right-click is the faster
      // path for one file.
      AppGlassMenuItem(
        icon: allStaged ? Icons.unarchive_outlined : Icons.inbox_outlined,
        label: allStaged ? l10n.removeFromStaging : l10n.addToStaging,
        trailing: countHint,
        onSelected: () {
          if (allStaged) {
            staging.removeAll(targets.map((f) => f.path));
          } else {
            staging.addAll(targets);
          }
        },
      ),
      const AppGlassMenuDivider(),
      AppGlassMenuItem(
        icon: Icons.edit_outlined,
        label: l10n.rename,
        trailing: 'F2',
        onSelected: () {
          if (!context.mounted) return;
          showFileRenameDialog(
            context: context,
            filePath: file.path,
            onSuccess: onRefresh,
          );
        },
      ),
      AppGlassMenuItem(
        icon: Icons.content_copy_outlined,
        label: l10n.copyFilename,
        onSelected: () => Clipboard.setData(ClipboardData(text: file.name)),
      ),
      const AppGlassMenuDivider(),
      AppGlassMenuItem(
        icon: Icons.folder_open_outlined,
        label: l10n.openInFolder,
        onSelected: () => FileUtils.openFolder(file.path),
      ),
      AppGlassMenuItem(
        icon: Icons.ios_share,
        label: targets.length > 1 ? l10n.shareFiles(targets.length) : l10n.share,
        onSelected: () async {
          try {
            final xFiles = targets
                .map((f) => XFile(
                      f.path,
                      name: f.name,
                      mimeType: AppConstants.getMimeType(f.path),
                    ))
                .toList();

            // ignore: deprecated_member_use
            await Share.shareXFiles(
              xFiles,
              subject: targets.length == 1 ? targets.first.name : l10n.appTitle,
              sharePositionOrigin: Rect.fromLTWH(position.dx, position.dy, 1, 1),
            );
          } catch (e) {
            if (context.mounted) {
              AppSnackBar.error(context, l10n.shareFailed('$e'));
            }
          }
        },
      ),
    ],
  );
}
