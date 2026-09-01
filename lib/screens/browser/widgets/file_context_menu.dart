import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
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

/// One row of the file context menu — `11e`.
///
/// Hand-built rather than a [ListTile]: the frame draws a 32px row with the
/// shortcut hint set right-aligned in the mono face, and `ListTile` cannot be
/// squeezed to 32 without its own dense metrics fighting the padding.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Right-aligned keyboard hint, in mono. Only for actions that genuinely
  /// have a key — an invented one is worse than none.
  final String? shortcut;

  const _MenuRow({required this.icon, required this.label, this.shortcut});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (shortcut != null) ...[
            const SizedBox(width: 10),
            Text(
              shortcut!,
              style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

PopupMenuItem<dynamic> _item({
  required IconData icon,
  required String label,
  String? shortcut,
  required VoidCallback onTap,
}) {
  return PopupMenuItem<dynamic>(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    onTap: onTap,
    child: _MenuRow(icon: icon, label: label, shortcut: shortcut),
  );
}

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
  final colorScheme = Theme.of(context).colorScheme;

  final bool isImage = file.category == FileCategory.image;
  final bool isMediaOrText = [FileCategory.video, FileCategory.audio, FileCategory.text].contains(file.category);

  final bool isPartOfSelection = appState.fileBrowserState.selectedFiles.contains(file);
  final List<BrowserFile> filesToShare = isPartOfSelection
      ? appState.fileBrowserState.selectedFiles.toList()
      : [file];

  // Staging acts on the same set as sharing does: right-clicking inside a
  // selection means the selection, right-clicking outside it means that one
  // file. Anything else makes the count in the label a lie.
  final List<BrowserFile> stagingTargets = filesToShare;
  final bool allStaged = stagingTargets.every((f) => staging.contains(f.path));

  showMenu<dynamic>(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
    constraints: const BoxConstraints(minWidth: 230, maxWidth: 230),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    color: colorScheme.surface,
    items: <PopupMenuEntry<dynamic>>[
      // Primary Actions
      if (isImage)
        _item(
          icon: Icons.open_in_new,
          label: l10n.openInPreview,
          shortcut: 'Enter',
          onTap: () {
            final imageFiles = appState.fileBrowserState.filteredFiles
                .where((f) => f.category == FileCategory.image)
                .map((f) => AppImage(path: f.path, name: f.name))
                .toList();
            final initialIdx = imageFiles.indexWhere((img) => img.path == file.path);
            showMediaPreview(context, galleryImages: imageFiles, initialIndex: initialIdx >= 0 ? initialIdx : 0, heroScope: kBrowserPreviewHeroScope);
          },
        ),

      if (isMediaOrText)
        _item(
          icon: Icons.launch,
          label: l10n.openWithSystemDefault,
          onTap: () async {
            await FileUtils.openPath(file.path);
          },
        ),

      if (isImage || isMediaOrText) const PopupMenuDivider(),

      _item(
        icon: isPartOfSelection ? Icons.remove_circle_outline : Icons.add_circle_outline,
        label: isPartOfSelection ? l10n.removeFromSelection : l10n.addToSelection,
        onTap: () => appState.fileBrowserState.toggleSelection(file),
      ),

      // The second entry point into staging, beside the floating bar's. Both
      // exist because the bar only appears once something is selected, and
      // right-clicking one file is the faster path for one file.
      _item(
        icon: allStaged ? Icons.unarchive_outlined : Icons.inbox_outlined,
        label: allStaged
            ? l10n.removeFromStaging
            : (stagingTargets.length > 1
                ? l10n.addToStagingCount(stagingTargets.length)
                : l10n.addToStaging),
        onTap: () {
          if (allStaged) {
            staging.removeAll(stagingTargets.map((f) => f.path));
          } else {
            staging.addAll(stagingTargets);
          }
        },
      ),

      const PopupMenuDivider(),

      // Management Actions
      _item(
        icon: Icons.edit_outlined,
        label: l10n.rename,
        shortcut: 'F2',
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
      _item(
        icon: Icons.copy,
        label: l10n.copyFilename,
        onTap: () {
          Clipboard.setData(ClipboardData(text: file.name));
        },
      ),

      const PopupMenuDivider(),

      _item(
        icon: Icons.folder_open,
        label: l10n.openInFolder,
        onTap: () async {
          await FileUtils.openFolder(file.path);
        },
      ),
      _item(
        icon: Icons.share_outlined,
        label: filesToShare.length > 1 ? l10n.shareFiles(filesToShare.length) : l10n.share,
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
              sharePositionOrigin: Rect.fromLTWH(position.dx, position.dy, 1, 1),
            );
          } catch (e) {
            if (context.mounted) {
              AppSnackBar.error(context, 'Share failed: $e');
            }
          }
        },
      ),
    ],
  );
}
