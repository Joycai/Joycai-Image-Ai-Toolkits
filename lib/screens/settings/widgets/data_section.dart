import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/backup_error_text.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../services/temp_storage_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/dialogs/import_options_dialog.dart';
import '../../wizard/setup_wizard.dart';
import 'settings_layout.dart';

/// `E1 · 1d` 「数据管理」: one group of action rows — export, import, open the
/// data folder, clear scratch files, run the wizard, reset — each row the
/// target, ending in its action's glyph; reset in the error colour.
class DataSection extends StatelessWidget {
  final bool isMobile;
  const DataSection({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // No title — the pane header already says 「数据管理」.
    return SettingsSections(
      children: [
        SettingsGroup(
          children: [
            _DataActionRow(
              title: l10n.exportSettings,
              note: l10n.exportSettingsNote,
              verb: l10n.actionExport,
              icon: Icons.upload_outlined,
              onPressed: () => _exportSettings(context, l10n),
            ),
            _DataActionRow(
              title: l10n.importSettings,
              verb: l10n.actionImport,
              icon: Icons.download_outlined,
              onPressed: () => _importSettings(context, l10n),
            ),
            _DataActionRow(
              title: l10n.openAppDataDirectory,
              verb: l10n.actionOpen,
              icon: Icons.folder_open_outlined,
              onPressed: () => _openAppDataDir(context),
            ),
            // Its own widget: it carries a measured size, which means state and
            // a reload after the clear. Second to last, so the two actions that
            // throw something away stay together at the end.
            const _TempFilesRow(),
            _DataActionRow(
              title: l10n.runSetupWizard,
              verb: l10n.actionRun,
              icon: Icons.play_arrow_outlined,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupWizard())),
            ),
            _DataActionRow(
              title: l10n.resetAllSettings,
              note: l10n.resetAllSettingsNote,
              verb: l10n.reset,
              icon: Icons.restart_alt,
              danger: true,
              onPressed: () => _resetSettings(context, l10n),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openAppDataDir(BuildContext context) async {
    try {
      final path = await DatabaseService().getDatabasePath();
      await FileUtils.openPath(path);
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _exportSettings(BuildContext context, AppLocalizations l10n) async {
    bool includeDirs = true;
    bool includePrompts = true;
    bool includeUsage = false;

    final bool? confirmed = await _showExportOptions(context, l10n, (d, p, u) {
      includeDirs = d;
      includePrompts = p;
      includeUsage = u;
    });

    if (confirmed != true || !context.mounted) return;

    final data = await DatabaseService().getAllDataRaw(
      includePrompts: includePrompts,
      includeUsage: includeUsage,
      includeDirectories: includeDirs,
    );
    final json = jsonEncode(data);
    final bytes = utf8.encode(json);

    // file_picker >= 12 writes `bytes` itself on every platform and returns the
    // destination as a Uri, so no follow-up write is needed here.
    final Uri? saved = await FilePicker.saveFile(
      fileName: 'joycai_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (!context.mounted) return;

    if (saved != null) {
      AppSnackBar.success(context, l10n.settingsExported);
    }
  }

  /// The export question, in the same checkbox rows the import dialog uses: a
  /// dialog on desktop, a sheet on a phone.
  Future<bool?> _showExportOptions(
    BuildContext context,
    AppLocalizations l10n,
    void Function(bool, bool, bool) onUpdate,
  ) {
    bool d = true;
    bool p = true;
    bool u = false;

    Widget options(StateSetter setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ImportOptionRow(
              title: l10n.includeDirectories,
              description: l10n.includeDirectoriesDesc,
              value: d,
              onChanged: (v) => setState(() => d = v),
            ),
            ImportOptionRow(
              title: l10n.includePrompts,
              description: l10n.includePromptsDesc,
              value: p,
              onChanged: (v) => setState(() => p = v),
            ),
            ImportOptionRow(
              title: l10n.includeUsage,
              description: l10n.includeUsageDesc,
              value: u,
              onChanged: (v) => setState(() => u = v),
            ),
          ],
        );

    if (isMobile) {
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setState) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.s22, AppSpace.s22, AppSpace.s22, AppSpace.s28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.exportOptions, style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: AppSpace.s16),
                options(setState),
                const SizedBox(height: AppSpace.s22),
                AppButton(
                  label: l10n.exportNow,
                  size: AppButtonSize.large,
                  fullWidth: true,
                  onPressed: () {
                    onUpdate(d, p, u);
                    Navigator.pop(sheetContext, true);
                  },
                ),
                const SizedBox(height: AppSpace.s6),
                AppButton(
                  label: l10n.cancel,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.large,
                  fullWidth: true,
                  onPressed: () => Navigator.pop(sheetContext, false),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AppDialog.show<bool>(
      context,
      icon: Icons.upload_outlined,
      title: l10n.exportOptions,
      maxWidth: 440,
      content: StatefulBuilder(builder: (context, setState) => options(setState)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.exportNow,
          onPressed: () {
            onUpdate(d, p, u);
            Navigator.pop(context, true);
          },
        ),
      ],
    );
  }

  Future<void> _importSettings(BuildContext context, AppLocalizations l10n) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final importedMsg = l10n.settingsImported;

    final PlatformFile? picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (!context.mounted || picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      final String fileContent = utf8.decode(bytes);
      if (!context.mounted) return;
      final Map<String, dynamic> data = jsonDecode(fileContent);

      // Pre-check what's available in the file
      final bool hasDirs = data.containsKey('source_directories') ||
          (data['settings'] as List?)?.any((s) => s['key'] == 'output_directory') == true;
      final bool hasPrompts = data.containsKey('user_prompts') || data.containsKey('prompts') || data.containsKey('tags');
      final bool hasUsage = data.containsKey('token_usage');

      bool includeDirs = hasDirs;
      bool includePrompts = hasPrompts;
      bool includeUsage = hasUsage;

      final bool? confirmed = await showImportOptionsDialog(
        context,
        l10n: l10n,
        hasDirs: hasDirs,
        hasPrompts: hasPrompts,
        hasUsage: hasUsage,
        isMobile: isMobile,
        fileName: picked.name,
        onUpdate: (d, p, u) {
          includeDirs = d;
          includePrompts = p;
          includeUsage = u;
        },
      );

      if (confirmed != true || !context.mounted) return;

      await DatabaseService().restoreBackup(
        data,
        includePrompts: includePrompts,
        includeUsage: includeUsage,
        includeDirectories: includeDirs,
      );

      if (!context.mounted) return;
      await appState.loadSettings();
      await appState.galleryState.reloadSettings();
      await appState.fileBrowserState.reloadSettings();
      if (!context.mounted) return;
      AppSnackBar.success(context, importedMsg);
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.error(context, backupImportErrorText(l10n, e));
    }
  }

  void _resetSettings(BuildContext context, AppLocalizations l10n) {
    AppDialog.show<void>(
      context,
      icon: Icons.restart_alt,
      iconColor: Theme.of(context).colorScheme.error,
      title: l10n.confirmReset,
      subtitle: l10n.resetIrreversible,
      content: Text(l10n.resetWarning),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          // Enter must never be the key that resets.
          autofocus: true,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.resetEverything,
          variant: AppButtonVariant.destructive,
          onPressed: () async {
            final appState = Provider.of<AppState>(context, listen: false);
            await DatabaseService().resetAllSettings();
            if (!context.mounted) return;
            Navigator.pop(context);
            appState.addLog('All settings reset to default.');
            await appState.loadSettings();
            await appState.galleryState.reloadSettings();
            await appState.fileBrowserState.reloadSettings();
          },
        ),
      ],
    );
  }
}

/// One action row of the data group: the title (and an optional note),
/// ending in the action's glyph and verb in `1d`'s compact button skin.
///
/// The whole row is the button — an [OutlinedButton] with its outline taken
/// off, so it keeps the button's focus, hover and disabled behaviour and a
/// screen reader announces it as one. A disabled row greys to the muted ink.
class _DataActionRow extends StatelessWidget {
  const _DataActionRow({
    required this.title,
    required this.verb,
    required this.icon,
    required this.onPressed,
    this.note,
    this.danger = false,
  });

  final String title;

  /// The short verb on the trailing pill — 「导出」, 「清理」.
  final String verb;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? note;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bool enabled = onPressed != null;

    final Color titleInk = !enabled
        ? colorScheme.outline
        : danger
            ? colorScheme.error
            : colorScheme.onSurface;
    final Color actionInk = !enabled
        ? colorScheme.outline
        : danger
            ? colorScheme.error
            : colorScheme.accentText;
    final Color actionEdge = danger && enabled
        ? colorScheme.error.withValues(alpha: AppAlpha.edge)
        : colorScheme.outlineVariant;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide.none,
        backgroundColor: Colors.transparent,
        foregroundColor: titleInk,
        disabledForegroundColor: colorScheme.outline,
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(double.infinity, 48),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: titleInk),
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      note!,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurfaceVariant,
                        height: AppType.proseHeight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: AppSize.compact,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: actionEdge),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppSize.iconSm, color: actionInk),
                const SizedBox(width: AppSpace.s6),
                Text(
                  verb,
                  style: textTheme.labelMedium?.copyWith(color: actionInk),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Clear Temporary Files", with what they currently cost under the title.
///
/// The size is the point: without it this is an action whose effect the user
/// cannot see either before or after taking it, and there is no other place
/// in the app that says how much scratch space is in use. It reloads after a
/// clear, so the number is the answer as well as the prompt.
class _TempFilesRow extends StatefulWidget {
  const _TempFilesRow();

  @override
  State<_TempFilesRow> createState() => _TempFilesRowState();
}

class _TempFilesRowState extends State<_TempFilesRow> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final bytes = await TempStorageService.instance.measure();
    if (mounted) setState(() => _bytes = bytes);
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context)!;
    final bytes = _bytes ?? 0;
    final size = AppConstants.formatFileSize(bytes);

    // The size goes in the question, not just on the row: this is the one
    // action here that can take a mask or a crop the workspace is still
    // pointing at, so what it costs and what it touches are both spelled out.
    final confirmed = await AppDialog.show<bool>(
      context,
      icon: Icons.cleaning_services_outlined,
      title: l10n.clearTempFilesConfirmTitle,
      subtitle: size,
      content: Text(l10n.clearTempFilesConfirmMessage(size)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.clearTempFiles,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final freed = await TempStorageService.instance.clear();
    // The workspace may have been holding a mask or a crop that just went; the
    // refresh is what drops those entries rather than leaving them pointing at
    // nothing.
    await appState.galleryState.refreshImages();
    if (!mounted) return;

    setState(() => _bytes = 0);
    AppSnackBar.success(context, l10n.tempFilesCleared(AppConstants.formatFileSize(freed)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bytes = _bytes;
    final bool empty = bytes == null || bytes == 0;

    // No size until the walk finishes, and none once there is nothing to
    // clear -- "0 B" is noise, and the greyed row already says it.
    return _DataActionRow(
      title: l10n.clearTempFiles,
      verb: l10n.actionClear,
      icon: Icons.cleaning_services_outlined,
      note: empty
          ? l10n.clearTempFilesNote
          : '${AppConstants.formatFileSize(bytes)} · ${l10n.clearTempFilesNote}',
      onPressed: empty ? null : _clear,
    );
  }
}
