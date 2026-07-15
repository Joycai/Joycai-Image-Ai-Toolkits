import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../services/web_scraper_service.dart';
import '../../state/app_state.dart';
import '../../widgets/panel_resizer.dart';
import 'widgets/downloader_results_area.dart';
import 'widgets/downloader_toolbar.dart';

/// Image downloader. Toolbar layout: URL / requirement / model / action in a
/// top bar, a slim options strip below it, and the full-width results grid —
/// replacing the old fixed 350px left panel.
class ImageDownloaderScreen extends StatefulWidget {
  const ImageDownloaderScreen({super.key});

  @override
  State<ImageDownloaderScreen> createState() => _ImageDownloaderScreenState();
}

class _ImageDownloaderScreenState extends State<ImageDownloaderScreen> {
  late TextEditingController _urlController;
  late TextEditingController _requirementController;
  late TextEditingController _cookieController;
  late TextEditingController _prefixController;

  bool _showLogs = false;

  @override
  void initState() {
    super.initState();
    final state = Provider.of<AppState>(context, listen: false).downloaderState;
    // Returning mid-analysis: reopen the live log panel.
    _showLogs = state.isAnalyzing;
    _urlController = TextEditingController(text: state.url);
    _requirementController = TextEditingController(text: state.requirement);
    _cookieController = TextEditingController(text: state.cookies);
    _prefixController = TextEditingController(text: state.prefix);

    _urlController.addListener(() => state.url = _urlController.text);
    _requirementController.addListener(() => state.requirement = _requirementController.text);
    _cookieController.addListener(() => state.cookies = _cookieController.text);
    _prefixController.addListener(() => state.prefix = _prefixController.text);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _requirementController.dispose();
    _cookieController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  Future<void> _pasteHtml() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text != null) {
      final state = Provider.of<AppState>(context, listen: false).downloaderState;
      final fullText = data!.text!;
      state.setState(manualHtml: fullText);
      state.addLog('Pasted HTML (${fullText.length} chars)');
    }
  }

  Future<void> _analyze() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context, listen: false);
    final state = appState.downloaderState;

    if (_urlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.urlRequired), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_requirementController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.requirementRequired), backgroundColor: Colors.orange),
      );
      return;
    }

    if (state.isManualHtml && state.manualHtml.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.manualHtmlRequired), backgroundColor: Colors.orange),
      );
      return;
    }

    if (state.selectedModelDbId == null && appState.chatModels.isNotEmpty) {
      state.selectedModelDbId = appState.chatModels.first.id;
    }

    if (state.selectedModelDbId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.noModelsConfigured),
            action: SnackBarAction(
              label: l10n.settings,
              onPressed: () => appState.navigateToScreen(6),
            ),
          ),
        );
      }
      return;
    }

    setState(() => _showLogs = true);

    // The analysis itself runs on DownloaderState so it survives screen
    // switches; this State only reacts to the outcome if still mounted.
    try {
      await state.analyze();
      if (mounted && state.discoveredImages.isNotEmpty) {
        // Collapse the log strip once results land so the grid gets space.
        setState(() => _showLogs = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Analysis failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveOriginHtml() async {
    if (_urlController.text.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final state = appState.downloaderState;
    final l10n = AppLocalizations.of(context)!;

    // On iOS we use the app's safe output directory (Result Cache)
    String? outputDir = await appState.getSetting('output_directory');
    if (Platform.isIOS && (outputDir == null || outputDir.isEmpty)) {
      outputDir = appState.galleryState.outputDirectory;
    }

    if (!mounted) return;

    if (outputDir == null || outputDir.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.setOutputDirFirst)));
      return;
    }

    try {
      state.addLog('Fetching raw HTML...');
      final html = await WebScraperService().fetchRawHtml(
        url: _urlController.text,
        cookies: _cookieController.text,
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'origin_$timestamp.html';
      final filePath = p.join(outputDir, fileName);

      await File(filePath).writeAsString(html);
      state.addLog('HTML saved to: $filePath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.htmlSavedTo(filePath))));
      }
    } catch (e) {
      state.addLog('Failed to save HTML: $e');
    }
  }

  void _addToQueue() {
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final state = appState.downloaderState;
    final selected = state.discoveredImages.where((img) => img.isSelected).toList();
    if (selected.isEmpty) return;

    final urls = selected.map((img) => img.url).toList();
    appState.taskQueue.addTask(
      urls,
      state.selectedModelDbId,
      {
        'url': _urlController.text,
        'prefix': _prefixController.text,
        'cookies': _cookieController.text,
      },
      type: TaskType.imageDownload,
    );

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.addedToQueue(selected.length))));
  }

  Future<void> _importCookieFile() async {
    final l10n = AppLocalizations.of(context)!;
    final state = Provider.of<AppState>(context, listen: false).downloaderState;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'cookie', 'cookies'],
    );

    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();

      String parsedCookies = "";
      int count = 0;

      if (content.contains('# Netscape HTTP Cookie File')) {
        // Parse Netscape format
        final lines = content.split('\n');
        final List<String> pairs = [];
        for (var line in lines) {
          if (line.trim().isEmpty || line.startsWith('#')) continue;
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 7) {
            final name = parts[5];
            final value = parts[6];
            pairs.add('$name=$value');
            count++;
          }
        }
        parsedCookies = pairs.join('; ');
      } else if (content.contains('; ') || content.contains('=')) {
        // Assume raw text format
        parsedCookies = content.trim();
        count = parsedCookies.split(';').length;
      }

      if (parsedCookies.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.cookieFileInvalid), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      _cookieController.text = parsedCookies;
      state.setState(cookies: parsedCookies);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.cookieImportSuccess(count)), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      state.addLog('Failed to import cookies: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final state = appState.downloaderState;
    final colorScheme = Theme.of(context).colorScheme;

    if (state.selectedModelDbId == null && appState.chatModels.isNotEmpty) {
      state.selectedModelDbId = appState.chatModels.first.id;
    }

    // Inset-panel canvas: the whole screen is a single rounded card (header
    // toolbar, options strip, log console, results grid) floating on the
    // tinted surfaceContainer background.
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: PanelCard(
          child: Column(
            children: [
              DownloaderToolbar(
                urlController: _urlController,
                requirementController: _requirementController,
                isAnalyzing: state.isAnalyzing,
                onAnalyze: _analyze,
                onOpenAdvanced: () => showDownloaderAdvancedDialog(
                  context,
                  prefixController: _prefixController,
                  cookieController: _cookieController,
                  onImportCookie: _importCookieFile,
                ),
              ),
              if (Platform.isIOS)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: colorScheme.primaryContainer.withAlpha(100),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.iosOutputRecommend,
                          style: TextStyle(fontSize: 11, color: colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                height: 40,
                child: DownloaderOptionsStrip(
                  isAnalyzing: state.isAnalyzing,
                  showLogs: _showLogs,
                  onToggleLogs: () => setState(() => _showLogs = !_showLogs),
                  onSaveHtml: _saveOriginHtml,
                  onPasteHtml: _pasteHtml,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: _showLogs && state.logs.isNotEmpty ? 196 : 0,
                child: _showLogs && state.logs.isNotEmpty
                    ? _DownloaderLogPanel(
                        logs: state.logs,
                        isAnalyzing: state.isAnalyzing,
                        onClose: () => setState(() => _showLogs = false),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: DownloaderResultsArea(onAddToQueue: _addToQueue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Console-style log card: timestamps and messages split into muted / normal
/// colors, error lines highlighted, a thin progress bar while analyzing, and
/// copy / close actions in the header.
class _DownloaderLogPanel extends StatelessWidget {
  final List<String> logs;
  final bool isAnalyzing;
  final VoidCallback onClose;

  const _DownloaderLogPanel({
    required this.logs,
    required this.isAnalyzing,
    required this.onClose,
  });

  static final _lineRegex = RegExp(r'^\[(.+?)\]\s*(.*)$');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withAlpha(150),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(120)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(Icons.terminal, size: 15, color: colorScheme.primary),
                ),
                const SizedBox(width: 9),
                Text(
                  l10n.logs,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${logs.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (isAnalyzing) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ],
                const Spacer(),
                IconButton(
                  onPressed: () => Clipboard.setData(ClipboardData(text: logs.join('\n'))),
                  icon: const Icon(Icons.copy, size: 14),
                  tooltip: l10n.copyLogs,
                  visualDensity: VisualDensity.compact,
                  color: colorScheme.onSurfaceVariant,
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 15),
                  tooltip: l10n.close,
                  visualDensity: VisualDensity.compact,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (isAnalyzing)
            const LinearProgressIndicator(minHeight: 2)
          else
            Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(120)),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final line = logs[logs.length - 1 - i];
                final isNewest = i == 0;
                final match = _lineRegex.firstMatch(line);
                final time = match?.group(1);
                final message = match?.group(2) ?? line;
                final isError = message.startsWith('Error') ||
                    message.startsWith('Failed') ||
                    message.contains('failed:');

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (time != null) ...[
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: isNewest ? FontWeight.w600 : FontWeight.normal,
                            color: isError
                                ? colorScheme.error
                                : isNewest
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
