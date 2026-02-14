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
import 'widgets/downloader_control_panel.dart';
import 'widgets/downloader_results_area.dart';

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
  late TextEditingController _manualHtmlController;
  
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    final state = Provider.of<AppState>(context, listen: false).downloaderState;
    _urlController = TextEditingController(text: state.url);
    _requirementController = TextEditingController(text: state.requirement);
    _cookieController = TextEditingController(text: state.cookies);
    _prefixController = TextEditingController(text: state.prefix);
    
    String initialPreview = state.manualHtml;
    if (state.manualHtml.length > 5000) {
      initialPreview = '${state.manualHtml.substring(0, 5000)}... (truncated)';
    }
    _manualHtmlController = TextEditingController(text: initialPreview);

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
    _manualHtmlController.dispose();
    super.dispose();
  }

  Future<void> _pasteHtml() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text != null) {
      final state = Provider.of<AppState>(context, listen: false).downloaderState;
      final fullText = data!.text!;
      state.setState(manualHtml: fullText);
      
      String preview = fullText;
      if (fullText.length > 5000) {
        preview = '${fullText.substring(0, 5000)}... (truncated)';
      }
      _manualHtmlController.text = preview;
      state.addLog('Pasted HTML (${fullText.length} chars)');
    }
  }

  Future<void> _analyze() async {
    if (_urlController.text.isEmpty || _requirementController.text.isEmpty) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    final state = appState.downloaderState;
    
    if (state.selectedModelPk == null && appState.chatModels.isNotEmpty) {
       state.selectedModelPk = appState.chatModels.first.id;
    }
    
    if (state.selectedModelPk == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.noModelsConfigured),
            action: SnackBarAction(
              label: l10n.settings,
              onPressed: () => appState.navigateToScreen(5),
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isAnalyzing = true);
    state.reset();

    try {
      final results = await WebScraperService().discoverImages(
        url: _urlController.text,
        requirement: _requirementController.text,
        modelIdentifier: state.selectedModelPk!,
        cookies: _cookieController.text,
        manualHtml: state.isManualHtml ? state.manualHtml : null,
        onLog: state.addLog,
      );
      state.setState(discoveredImages: results);
      
      if (results.isNotEmpty && _cookieController.text.isNotEmpty) {
        try {
          final host = Uri.parse(_urlController.text).host;
          if (host.isNotEmpty) state.saveCookie(host, _cookieController.text);
        } catch (_) {}
      }
    } catch (e) {
      state.addLog('Error: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _saveOriginHtml() async {
    if (_urlController.text.isEmpty) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    final state = appState.downloaderState;
    final outputDir = await appState.getSetting('output_directory');
    
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

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
      state.selectedModelPk,
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

    final result = await FilePicker.platform.pickFiles(
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
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 900;

    if (state.selectedModelPk == null && appState.chatModels.isNotEmpty) {
      state.selectedModelPk = appState.chatModels.first.id;
    }

    final controlPanel = DownloaderControlPanel(
      urlController: _urlController,
      requirementController: _requirementController,
      cookieController: _cookieController,
      prefixController: _prefixController,
      manualHtmlController: _manualHtmlController,
      isAnalyzing: _isAnalyzing,
      onAnalyze: _analyze,
      onSaveHtml: _saveOriginHtml,
      onPasteHtml: _pasteHtml,
      onImportCookie: _importCookieFile,
    );

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(l10n.imageDownloader),
        leading: isNarrow ? IconButton(
          icon: const Icon(Icons.tune),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ) : null,
      ),
      drawer: isNarrow ? Drawer(width: 350, child: SafeArea(child: controlPanel)) : null,
      body: Row(
        children: [
          if (!isNarrow) ...[
            SizedBox(width: 350, child: controlPanel),
            const VerticalDivider(width: 1, thickness: 1),
          ],
          Expanded(
            child: DownloaderResultsArea(
              onAddToQueue: _addToQueue,
            ),
          ),
        ],
      ),
    );
  }
}