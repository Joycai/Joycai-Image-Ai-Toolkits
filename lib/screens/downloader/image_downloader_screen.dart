import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../services/web_scraper_service.dart';
import '../../state/app_state.dart';
import '../../state/downloader_state.dart';
import '../../widgets/app_run_console.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_window_frame.dart';
import '../../widgets/shell/app_destinations.dart';
import 'widgets/downloader_inputs.dart';
import 'widgets/downloader_log_panel.dart';
import 'widgets/downloader_results_area.dart';
import 'widgets/downloader_toolbar.dart';

/// Image downloader (`B3`).
///
/// One column, top to bottom: the input toolbar, the iOS output-folder note,
/// the options strip, the log panel (animated open), the results, and the
/// execution console. The strips are opaque; the grid is transparent over the
/// window's backdrop.
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

  void _openSettings() {
    Provider.of<AppState>(context, listen: false).navigateToScreen(AppDestination.settings.index);
  }

  /// An address the scraper can fetch: an http(s) scheme and a host.
  static bool _isFetchableUrl(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
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

    if (!_isFetchableUrl(_urlController.text)) {
      AppSnackBar.error(context, l10n.urlRequired);
      return;
    }

    if (_requirementController.text.isEmpty) {
      AppSnackBar.warning(context, l10n.requirementRequired);
      return;
    }

    if (state.isManualHtml && state.manualHtml.trim().isEmpty) {
      AppSnackBar.warning(context, l10n.manualHtmlRequired);
      return;
    }

    if (state.selectedModelDbId == null && appState.chatModels.isNotEmpty) {
      state.selectedModelDbId = appState.chatModels.first.id;
    }

    if (state.selectedModelDbId == null) {
      if (mounted) {
        AppSnackBar.warning(
          context,
          l10n.noModelsConfigured,
          action: AppSnackBarAction(label: l10n.goToSettings, onPressed: _openSettings),
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
        // Collapse the log panel once results land so the grid gets space.
        setState(() => _showLogs = false);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, "Analysis failed: $e");
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
      AppSnackBar.warning(
        context,
        l10n.setOutputDirFirst,
        action: AppSnackBarAction(label: l10n.goToSettings, onPressed: _openSettings),
      );
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
        AppSnackBar.info(context, l10n.htmlSavedTo(filePath));
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

    AppSnackBar.success(context, l10n.addedToQueue(selected.length));
  }

  Future<void> _importCookieFile() async {
    final l10n = AppLocalizations.of(context)!;
    final state = Provider.of<AppState>(context, listen: false).downloaderState;

    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['txt', 'cookie', 'cookies'],
    );

    if (picked == null) return;

    try {
      final content = utf8.decode(await picked.readAsBytes());

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
          AppSnackBar.warning(context, l10n.cookieFileInvalid);
        }
        return;
      }

      _cookieController.text = parsedCookies;
      state.setState(cookies: parsedCookies);

      if (mounted) {
        AppSnackBar.success(context, l10n.cookieImportSuccess(count));
      }
    } catch (e) {
      state.addLog('Failed to import cookies: $e');
    }
  }

  Future<void> _openAdvancedOptions() async {
    final state = Provider.of<AppState>(context, listen: false).downloaderState;
    await showDownloaderAdvancedDialog(
      context,
      prefixController: _prefixController,
      cookieController: _cookieController,
      onImportCookie: _importCookieFile,
    );
    // The prefix field writes through without notifying, and the status row
    // shows it.
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    // Two subscriptions, deliberately: the downloader's own data comes from
    // DownloaderState, the model list from AppState. AppState no longer
    // forwards its sub-states' notifications, so watching it alone would leave
    // this screen frozen while an analysis runs.
    final state = context.watch<DownloaderState>();
    final appState = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    if (state.selectedModelDbId == null && appState.chatModels.isNotEmpty) {
      state.selectedModelDbId = appState.chatModels.first.id;
    }

    final logsOpen = _showLogs && state.logs.isNotEmpty;

    return Scaffold(
      // Transparent over the window's backdrop: the strips paint their own
      // column ground and the grid between them does not. The canvas colour
      // where there is no custom window frame to show through to.
      backgroundColor: usesCustomWindowChrome ? Colors.transparent : colorScheme.surfaceContainer,
      bottomNavigationBar: const AppRunConsole(),
      body: Column(
        children: [
          DownloaderToolbar(
            urlController: _urlController,
            requirementController: _requirementController,
            isAnalyzing: state.isAnalyzing,
            onAnalyze: _analyze,
            onOpenAdvanced: _openAdvancedOptions,
          ),
          if (Platform.isIOS) _IosOutputNote(onOpenSettings: _openSettings),
          DownloaderOptionsStrip(
            isAnalyzing: state.isAnalyzing,
            showLogs: _showLogs,
            onToggleLogs: () => setState(() => _showLogs = !_showLogs),
            onSaveHtml: _saveOriginHtml,
            onPasteHtml: _pasteHtml,
          ),
          // Laid out at its full height and revealed by the clip, so closing
          // slides the panel away rather than emptying it first.
          AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.reveal),
            curve: AppMotion.enter,
            height: logsOpen ? DownloaderLogPanel.height : 0,
            child: state.logs.isEmpty
                ? null
                : ClipRect(
                    child: OverflowBox(
                      minHeight: DownloaderLogPanel.height,
                      maxHeight: DownloaderLogPanel.height,
                      alignment: Alignment.topCenter,
                      child: DownloaderLogPanel(
                        logs: state.logs,
                        isAnalyzing: state.isAnalyzing,
                        onClose: () => setState(() => _showLogs = false),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: DownloaderResultsArea(onAddToQueue: _addToQueue),
          ),
        ],
      ),
    );
  }
}

/// The iOS output-folder note (`B3 · 1c`): full width on the warning ground
/// with a way to settings.
class _IosOutputNote extends StatelessWidget {
  const _IosOutputNote({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final semantic = context.semantic;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: semantic.warningContainer,
      padding: const EdgeInsets.symmetric(horizontal: kDownloaderGutter, vertical: AppSpace.s10),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: AppSize.iconMd, color: semantic.warning),
          const SizedBox(width: AppSpace.s10),
          Expanded(
            child: Text(
              l10n.iosOutputRecommend,
              style: textTheme.bodySmall!.copyWith(color: semantic.onWarningContainer),
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          InkWell(
            onTap: onOpenSettings,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: AppSpace.s4),
              child: Text(
                l10n.goToSettings,
                style: textTheme.bodySmall!.copyWith(
                  color: semantic.onWarningContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
