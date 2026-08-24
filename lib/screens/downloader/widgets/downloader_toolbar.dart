import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../state/downloader_state.dart';
import '../../../widgets/api_key_field.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/chat_model_selector.dart';
import '../../../widgets/app_switch.dart';

/// Height of the toolbar's inputs and the controls that line up with them.
/// Taller than a bare button: these are fields you type a URL into.
const double _controlHeight = 44;

/// Top toolbar of the image downloader.
///
/// Two rows: the address on its own, then what to look for in it and the model
/// that will do the looking. The URL earns the full width — it is the longest
/// value on the screen and the one you paste rather than type, so a field that
/// scrolls its own text hides the end of the thing you just pasted.
class DownloaderToolbar extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController requirementController;
  final bool isAnalyzing;
  final VoidCallback onAnalyze;
  final VoidCallback onOpenAdvanced;

  const DownloaderToolbar({
    super.key,
    required this.urlController,
    required this.requirementController,
    required this.isAnalyzing,
    required this.onAnalyze,
    required this.onOpenAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = context.watch<DownloaderState>();
    final colorScheme = Theme.of(context).colorScheme;

    final urlField = SizedBox(
      height: _controlHeight,
      child: TextField(
        controller: urlController,
        // Monospace: this is an address, not prose. Fixed widths make a typo in
        // a long path something you can see rather than something you re-read.
        style: Theme.of(context).textTheme.bodyMedium?.mono,
        decoration: _fieldDecoration(context, colorScheme, l10n.websiteUrl, Icons.link),
      ),
    );

    final requirementField = SizedBox(
      height: _controlHeight,
      child: AppSearchField(
        controller: requirementController,
        hint: l10n.whatToFind,
        onSubmitted: (_) => isAnalyzing ? null : onAnalyze(),
      ),
    );

    final modelSelector = SizedBox(
      width: 250,
      child: ChatModelSelector(
        selectedModelId: state.selectedModelDbId,
        label: l10n.analysisModel,
        onChanged: (v) => state.setState(selectedModelDbId: v),
      ),
    );

    final findButton = SizedBox(
      height: _controlHeight,
      child: AppButton(
        label: isAnalyzing ? l10n.analyzing : l10n.findImages,
        icon: Icons.image_search,
        loading: isAnalyzing,
        onPressed: onAnalyze,
      ),
    );

    final advancedButton = AppIconButton(
      icon: Icons.tune,
      tooltip: l10n.advancedOptions,
      size: _controlHeight,
      onPressed: onOpenAdvanced,
    );

    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_download_outlined, size: 24, color: colorScheme.primary),
        const SizedBox(width: 10),
        Text(
          l10n.imageDownloader,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );

    // Header row of the downloader column: no fill of its own — the panel
    // surface shows through; the bottom border is the internal divider.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = [
            modelSelector,
            const SizedBox(width: 8),
            findButton,
            const SizedBox(width: 8),
            advancedButton,
          ];

          return Column(
            children: [
              Row(
                children: [
                  title,
                  const SizedBox(width: 16),
                  Expanded(child: urlField),
                ],
              ),
              const SizedBox(height: 10),
              // Below ~820 the requirement field is squeezed to a few
              // characters by the controls beside it, so it takes its own row.
              if (constraints.maxWidth >= 820)
                Row(children: [Expanded(child: requirementField), const SizedBox(width: 8), ...actions])
              else ...[
                requirementField,
                const SizedBox(height: 10),
                Row(children: [Expanded(child: modelSelector), const SizedBox(width: 8), findButton, const SizedBox(width: 8), advancedButton]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The address bar's own decoration.
///
/// Was shared with the requirement field beside it, which is now an
/// [AppSearchField]; this is the only caller left. It keeps its fill rather
/// than following the theme's outlined input because the URL bar is the one
/// field that spans the toolbar and reads as a surface of its own, not as a
/// control in a row of controls.
InputDecoration _fieldDecoration(
    BuildContext context, ColorScheme colorScheme, String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
    prefixIcon: Icon(icon, size: 18, color: colorScheme.outline),
    contentPadding: EdgeInsets.zero,
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(appButtonRadius),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(appButtonRadius),
      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
    ),
  );
}

/// Slim strip under the toolbar: manual-HTML mode, save-HTML shortcut, log
/// toggle on the left; discovery counters on the right.
class DownloaderOptionsStrip extends StatelessWidget {
  final bool isAnalyzing;
  final bool showLogs;
  final VoidCallback onToggleLogs;
  final VoidCallback onSaveHtml;
  final VoidCallback onPasteHtml;

  const DownloaderOptionsStrip({
    super.key,
    required this.isAnalyzing,
    required this.showLogs,
    required this.onToggleLogs,
    required this.onSaveHtml,
    required this.onPasteHtml,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = context.watch<DownloaderState>();
    final colorScheme = Theme.of(context).colorScheme;

    final discoveredCount = state.discoveredImages.length;
    final selectedCount =
        state.discoveredImages.where((i) => i.isSelected).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90)),
        ),
      ),
      child: Row(
        children: [
          AppSwitch(
            value: state.isManualHtml,
            onChanged: (v) => state.setState(isManualHtml: v),
          ),
          Text(l10n.manualHtmlMode,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
          if (state.isManualHtml) ...[
            const SizedBox(width: 4),
            AppButton(
              label: l10n.pasteFromClipboard,
              icon: Icons.paste,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: onPasteHtml,
            ),
            if (state.manualHtml.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${(state.manualHtml.length / 1024).toStringAsFixed(1)} KB',
                  style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                      color: colorScheme.onSurfaceVariant),
                ),
              ),
              IconButton(
                onPressed: () => state.setState(manualHtml: ''),
                icon: const Icon(Icons.clear, size: 14),
                tooltip: l10n.clear,
                visualDensity: VisualDensity.compact,
                color: colorScheme.error,
              ),
            ],
          ],
          const SizedBox(width: 8),
          Container(width: 1, height: 18, color: colorScheme.outlineVariant),
          const SizedBox(width: 4),
          AppButton(
            label: l10n.saveOriginHtml,
            icon: Icons.html,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: isAnalyzing ? null : onSaveHtml,
          ),
          const SizedBox(width: 4),
          // Always drawn, disabled until there is something to read. Appearing
          // only once logs exist made the strip re-flow under the pointer.
          AppIconButton(
            icon: Icons.terminal,
            tooltip: l10n.logs,
            size: 30,
            selected: showLogs,
            onPressed: state.logs.isEmpty ? null : onToggleLogs,
          ),
          const Spacer(),
          // Nothing found yet is not a result worth captioning: an empty strip
          // says it, where the bare word "Results" reads as a heading for a
          // section that is not there.
          if (discoveredCount > 0)
            Flexible(
              child: Text(
                l10n.downloaderFoundSelected(discoveredCount, selectedCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Advanced options (filename prefix + cookies) moved from the old left
/// panel's expansion tile into a compact dialog behind the toolbar's tune
/// button.
Future<void> showDownloaderAdvancedDialog(
  BuildContext context, {
  required TextEditingController prefixController,
  required TextEditingController cookieController,
  required VoidCallback onImportCookie,
}) {
  final l10n = AppLocalizations.of(context)!;
  final state = Provider.of<AppState>(context, listen: false).downloaderState;

  return AppDialog.show<void>(
    context,
    icon: Icons.tune,
    title: l10n.advancedOptions,
    maxWidth: 440,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: prefixController,
          decoration: InputDecoration(
            labelText: l10n.filenamePrefix,
            prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        ApiKeyField(
          controller: cookieController,
          label: l10n.cookiesHint,
          maxLines: 3,
          onChanged: (v) => state.setState(cookies: v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            AppButton(
              label: l10n.importCookieFile,
              icon: Icons.upload_file,
              variant: AppButtonVariant.text,
              onPressed: () {
                Navigator.pop(context);
                onImportCookie();
              },
            ),
            if (state.cookieHistory.isNotEmpty)
              AppButton(
                label: l10n.cookieHistory,
                icon: Icons.history,
                variant: AppButtonVariant.text,
                onPressed: () {
                  Navigator.pop(context);
                  _showCookieHistory(context, state, cookieController);
                },
              ),
          ],
        ),
      ],
    ),
    actions: [
      AppButton(
        label: l10n.finish,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}

void _showCookieHistory(
  BuildContext context,
  DownloaderState state,
  TextEditingController cookieController,
) {
  showModalBottomSheet(
    context: context,
    builder: (context) => ListView(
      shrinkWrap: true,
      children: state.cookieHistory
          .map<Widget>((h) => ListTile(
                leading: const Icon(Icons.history),
                title: Text(h['host']),
                onTap: () {
                  cookieController.text = h['cookies'];
                  state.setState(cookies: h['cookies']);
                  Navigator.pop(context);
                },
              ))
          .toList(),
    ),
  );
}
