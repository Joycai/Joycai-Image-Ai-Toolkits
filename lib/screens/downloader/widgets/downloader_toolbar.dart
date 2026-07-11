import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../state/downloader_state.dart';
import '../../../widgets/api_key_field.dart';
import '../../../widgets/chat_model_selector.dart';

/// Top toolbar of the image downloader: URL + requirement + analysis model +
/// primary action in a single row (two rows below 1000px), replacing the old
/// 350px left panel so the results grid gets the full width.
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
    final appState = Provider.of<AppState>(context);
    final state = appState.downloaderState;
    final colorScheme = Theme.of(context).colorScheme;

    final urlField = TextField(
      controller: urlController,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: l10n.websiteUrl,
        isDense: true,
        prefixIcon: const Icon(Icons.link, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );

    final requirementField = TextField(
      controller: requirementController,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: l10n.whatToFind,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onSubmitted: (_) => isAnalyzing ? null : onAnalyze(),
    );

    final modelSelector = SizedBox(
      width: 230,
      child: ChatModelSelector(
        selectedModelId: state.selectedModelDbId,
        label: l10n.analysisModel,
        prefixIcon: Icons.psychology,
        onChanged: (v) => state.setState(selectedModelDbId: v),
      ),
    );

    final findButton = SizedBox(
      height: 42,
      child: FilledButton.icon(
        onPressed: isAnalyzing ? null : onAnalyze,
        icon: isAnalyzing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.image_search, size: 18),
        label: Text(isAnalyzing ? l10n.analyzing : l10n.findImages),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );

    final advancedButton = SizedBox(
      width: 42,
      height: 42,
      child: IconButton.outlined(
        onPressed: onOpenAdvanced,
        icon: const Icon(Icons.tune, size: 18),
        tooltip: l10n.advancedOptions,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
    );

    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_download, size: 22, color: colorScheme.primary),
        const SizedBox(width: 10),
        Text(
          l10n.imageDownloader,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    );

    // Header row of the downloader card: no fill of its own — the PanelCard
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
          if (constraints.maxWidth >= 1000) {
            return Row(
              children: [
                title,
                const SizedBox(width: 16),
                Expanded(flex: 3, child: urlField),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: requirementField),
                const SizedBox(width: 8),
                modelSelector,
                const SizedBox(width: 8),
                findButton,
                const SizedBox(width: 6),
                advancedButton,
              ],
            );
          }
          return Column(
            children: [
              Row(
                children: [
                  title,
                  const SizedBox(width: 16),
                  Expanded(child: urlField),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: requirementField),
                  const SizedBox(width: 8),
                  modelSelector,
                  const SizedBox(width: 8),
                  findButton,
                  const SizedBox(width: 6),
                  advancedButton,
                ],
              ),
            ],
          );
        },
      ),
    );
  }
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
    final appState = Provider.of<AppState>(context);
    final state = appState.downloaderState;
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
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: state.isManualHtml,
              onChanged: (v) => state.setState(isManualHtml: v),
            ),
          ),
          Text(l10n.manualHtmlMode,
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant)),
          if (state.isManualHtml) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onPasteHtml,
              icon: const Icon(Icons.paste, size: 14),
              label: Text(l10n.pasteFromClipboard,
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact),
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
                  style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
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
          TextButton.icon(
            onPressed: isAnalyzing ? null : onSaveHtml,
            icon: const Icon(Icons.html, size: 16),
            label:
                Text(l10n.saveOriginHtml, style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
          ),
          if (state.logs.isNotEmpty)
            IconButton(
              onPressed: onToggleLogs,
              icon: Icon(
                showLogs ? Icons.terminal : Icons.terminal_outlined,
                size: 16,
              ),
              tooltip: l10n.logs,
              visualDensity: VisualDensity.compact,
              color: showLogs
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          const Spacer(),
          Flexible(
            child: Text(
              discoveredCount > 0
                  ? l10n.downloaderFoundSelected(discoveredCount, selectedCount)
                  : l10n.results,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
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

  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.tune, size: 20),
          const SizedBox(width: 10),
          Text(l10n.advancedOptions),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: prefixController,
              decoration: InputDecoration(
                labelText: l10n.filenamePrefix,
                isDense: true,
                border: const OutlineInputBorder(),
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
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onImportCookie();
                  },
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: Text(l10n.importCookieFile,
                      style: const TextStyle(fontSize: 12)),
                ),
                if (state.cookieHistory.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCookieHistory(context, state, cookieController);
                    },
                    icon: const Icon(Icons.history, size: 16),
                    label: Text(l10n.cookieHistory,
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.finish),
        ),
      ],
    ),
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
