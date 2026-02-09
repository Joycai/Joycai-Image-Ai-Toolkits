import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../services/web_scraper_service.dart';
import '../../state/app_state.dart';
import '../../widgets/api_key_field.dart';

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
    if (state.selectedModelPk == null) return;

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

    final controlPanel = _ControlPanel(
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
            child: _ResultsArea(
              onAddToQueue: _addToQueue,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController requirementController;
  final TextEditingController cookieController;
  final TextEditingController prefixController;
  final TextEditingController manualHtmlController;
  final bool isAnalyzing;
  final VoidCallback onAnalyze;
  final VoidCallback onSaveHtml;
  final VoidCallback onPasteHtml;
  final VoidCallback onImportCookie;

  const _ControlPanel({
    required this.urlController,
    required this.requirementController,
    required this.cookieController,
    required this.prefixController,
    required this.manualHtmlController,
    required this.isAnalyzing,
    required this.onAnalyze,
    required this.onSaveHtml,
    required this.onPasteHtml,
    required this.onImportCookie,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final state = appState.downloaderState;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            colorScheme,
            child: Column(
              children: [
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: l10n.websiteUrl,
                    hintText: l10n.websiteUrlHint,
                    prefixIcon: const Icon(Icons.link),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: requirementController,
                  decoration: InputDecoration(
                    labelText: l10n.whatToFind,
                    hintText: l10n.whatToFindHint,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: state.selectedModelPk,
                  decoration: InputDecoration(
                    labelText: l10n.analysisModel,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.psychology),
                  ),
                  items: appState.chatModels.map((m) => DropdownMenuItem(value: m.id, child: Text(m.modelName))).toList(),
                  onChanged: (v) => state.setState(selectedModelPk: v),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          _buildCard(
            colorScheme,
            title: l10n.manualHtmlMode,
            trailing: Switch(
              value: state.isManualHtml,
              onChanged: (v) => state.setState(isManualHtml: v),
            ),
            child: state.isManualHtml ? Column(
              children: [
                TextField(
                  controller: manualHtmlController,
                  decoration: InputDecoration(
                    labelText: l10n.manualHtmlHint,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 4,
                  readOnly: true,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(onPressed: onPasteHtml, icon: const Icon(Icons.paste, size: 18), label: Text(l10n.pasteFromClipboard)),
                    TextButton.icon(
                      onPressed: () { state.setState(manualHtml: ''); manualHtmlController.clear(); }, 
                      icon: const Icon(Icons.clear, size: 18), 
                      label: Text(l10n.clear),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ) : const SizedBox.shrink(),
          ),

          const SizedBox(height: 20),

          ExpansionTile(
            title: Text(l10n.advancedOptions, style: const TextStyle(fontWeight: FontWeight.bold)),
            leading: const Icon(Icons.settings_suggest),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: prefixController,
                      decoration: InputDecoration(labelText: l10n.filenamePrefix, border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ApiKeyField(
                            controller: cookieController,
                            label: l10n.cookiesHint,
                            maxLines: 3,
                            onChanged: (v) {},
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (val) {
                            if (val == 'import') onImportCookie();
                            if (val == 'history') _showCookieHistory(context, state, l10n);
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'import',
                              child: ListTile(
                                leading: const Icon(Icons.upload_file),
                                title: Text(l10n.importCookieFile),
                                dense: true,
                              ),
                            ),
                            if (state.cookieHistory.isNotEmpty)
                              PopupMenuItem(
                                value: 'history',
                                child: ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text(l10n.cookieHistory),
                                  dense: true,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
          
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: isAnalyzing ? null : onAnalyze,
              icon: isAnalyzing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.analytics),
              label: Text(isAnalyzing ? l10n.analyzing : l10n.findImages),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isAnalyzing ? null : onSaveHtml,
              icon: const Icon(Icons.html),
              label: Text(l10n.saveOriginHtml),
            ),
          ),

          if (state.logs.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(l10n.logs, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 150,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: state.logs.length,
                itemBuilder: (context, i) => Text(state.logs[i], style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(ColorScheme colorScheme, {Widget? child, String? title, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (title case final String t) Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (trailing case final Widget w) w,
                ],
              ),
            ),
          if (child case final Widget c) c,
        ],
      ),
    );
  }

  void _showCookieHistory(BuildContext context, dynamic state, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: state.cookieHistory.map<Widget>((h) => ListTile(
          leading: const Icon(Icons.history),
          title: Text(h['host']),
          onTap: () {
            cookieController.text = h['cookies'];
            state.setState(cookies: h['cookies']);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }
}

class _ResultsArea extends StatelessWidget {
  final VoidCallback onAddToQueue;

  const _ResultsArea({required this.onAddToQueue});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final state = appState.downloaderState;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedCount = state.discoveredImages.where((i) => i.isSelected).length;

    return Column(
      children: [
        if (state.discoveredImages case [_, ...]) Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surface,
            child: Row(
              children: [
                Text(
                  l10n.selectImagesToDownload,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text('(${l10n.imagesSelected(selectedCount)})', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    for (var img in state.discoveredImages) {
                      img.isSelected = true;
                    }
                    state.notify();
                  },
                  child: Text(l10n.selectAll),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: selectedCount > 0 ? onAddToQueue : null,
                  icon: const Icon(Icons.download_for_offline),
                  label: Text(l10n.addToQueue),
                ),
              ],
            ),
          ),
        Expanded(
          child: state.discoveredImages.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_search, size: 80, color: colorScheme.outlineVariant),
                    const SizedBox(height: 24),
                    Text(l10n.noImagesDiscovered, style: Theme.of(context).textTheme.titleMedium),
                    Text(l10n.enterUrlToStart, style: TextStyle(color: colorScheme.outline)),
                  ],
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 0.85,
                ),
                itemCount: state.discoveredImages.length,
                itemBuilder: (context, index) {
                  final img = state.discoveredImages[index];
                  return _ImageDiscoveryCard(
                    image: img,
                    onToggle: () {
                      img.isSelected = !img.isSelected;
                      state.notify();
                    },
                  );
                },
              ),
        ),
      ],
    );
  }
}

class _ImageDiscoveryCard extends StatelessWidget {
  final dynamic image;
  final VoidCallback onToggle;

  const _ImageDiscoveryCard({required this.image, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: image.isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: image.isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: image.isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onToggle,
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: image.localCachePath != null
                      ? Image.file(File(image.localCachePath!), fit: BoxFit.cover)
                      : const Center(child: Icon(Icons.image, color: Colors.grey)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    image.url,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (image.isSelected)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.open_in_browser, size: 18),
            title: Text(l10n.openRawImage),
            dense: true,
          ),
          onTap: () async {
            final uri = Uri.parse(image.url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          },
        ),
      ],
    );
  }
}