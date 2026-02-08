import 'dart:io';

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
  
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    final state = Provider.of<AppState>(context, listen: false).downloaderState;
    _urlController = TextEditingController(text: state.url);
    _requirementController = TextEditingController(text: state.requirement);
    _cookieController = TextEditingController(text: state.cookies);
    _prefixController = TextEditingController(text: state.prefix);
    
    // For manual HTML, we only show a preview if it's too large
    String initialPreview = state.manualHtml;
    if (state.manualHtml.length > 5000) {
      initialPreview = '${state.manualHtml.substring(0, 5000)}... (truncated for performance)';
    }
    _manualHtmlController = TextEditingController(text: initialPreview);

    // Sync back to state on change (except manualHtml which uses Paste button)
    _urlController.addListener(() => state.url = _urlController.text);
    _requirementController.addListener(() => state.requirement = _requirementController.text);
    _cookieController.addListener(() => state.cookies = _cookieController.text);
    _prefixController.addListener(() => state.prefix = _prefixController.text);
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
        preview = '${fullText.substring(0, 5000)}... (truncated for performance)';
      }
      _manualHtmlController.text = preview;
      state.addLog('Pasted HTML from clipboard (${fullText.length} chars)');
    }
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

  Future<void> _analyze() async {
    if (_urlController.text.isEmpty || _requirementController.text.isEmpty) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    final state = appState.downloaderState;
    
    if (state.selectedModelPk == null && appState.chatModels.isNotEmpty) {
       state.selectedModelPk = appState.chatModels.first['id'] as int;
    }
    if (state.selectedModelPk == null) return;

    setState(() {
      _isAnalyzing = true;
    });
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
      state.addLog('Analysis finished. Found ${results.length} matching images.');
      
      // Save to history if successful and has cookies
      if (results.isNotEmpty && _cookieController.text.isNotEmpty) {
        try {
          final host = Uri.parse(_urlController.text).host;
          if (host.isNotEmpty) {
            state.saveCookie(host, _cookieController.text);
          }
        } catch (_) {}
      }
    } catch (e) {
      state.addLog('Error: $e');
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _saveOriginHtml() async {
    if (_urlController.text.isEmpty) return;
    
    final appState = Provider.of<AppState>(context, listen: false);
    final state = appState.downloaderState;
    final outputDir = await appState.getSetting('output_directory');
    if (!mounted) return;
    if (outputDir == null || outputDir.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set output directory in settings first.')),
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
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.htmlSavedTo(filePath))),
        );
      }
    } catch (e) {
      state.addLog('Failed to save HTML: $e');
    }
  }

  void _addToQueue() {
    final state = Provider.of<AppState>(context, listen: false).downloaderState;
    final selected = state.discoveredImages.where((img) => img.isSelected).toList();
    if (selected.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${selected.length} images to download queue.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final state = appState.downloaderState;
    final colorScheme = Theme.of(context).colorScheme;

    if (state.selectedModelPk == null && appState.chatModels.isNotEmpty) {
      state.selectedModelPk = appState.chatModels.first['id'] as int;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Downloader'),
      ),
      body: Row(
        children: [
          // Control Panel
          Container(
            width: 350,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Website URL',
                      hintText: 'https://example.com',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _requirementController,
                    decoration: const InputDecoration(
                      labelText: 'What to find?',
                      hintText: 'e.g. all product gallery images',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: state.selectedModelPk,
                    decoration: const InputDecoration(
                      labelText: 'Analysis Model',
                      border: OutlineInputBorder(),
                    ),
                    items: appState.chatModels.map((m) {
                      return DropdownMenuItem<int>(
                        value: m['id'] as int,
                        child: Text(m['model_name']),
                      );
                    }).toList(),
                    onChanged: (v) => state.setState(selectedModelPk: v),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(l10n.manualHtmlMode, style: const TextStyle(fontSize: 14)),
                    value: state.isManualHtml,
                    onChanged: (v) => state.setState(isManualHtml: v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (state.isManualHtml) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualHtmlController,
                            decoration: InputDecoration(
                              labelText: l10n.manualHtmlHint,
                              border: const OutlineInputBorder(),
                            ),
                            maxLines: 5,
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.paste),
                              onPressed: _pasteHtml,
                              tooltip: l10n.pasteFromClipboard,
                            ),
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                state.setState(manualHtml: '');
                                _manualHtmlController.clear();
                              },
                              tooltip: l10n.clear,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('Advanced Options', style: TextStyle(fontSize: 14)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: TextField(
                          controller: _prefixController,
                          decoration: const InputDecoration(
                            labelText: 'Filename Prefix',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: ApiKeyField(
                                controller: _cookieController,
                                label: 'Cookies (Raw or Netscape format)',
                                maxLines: 5,
                                onChanged: (v) {},
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (state.cookieHistory.isNotEmpty)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.history),
                                tooltip: l10n.cookieHistory,
                                onSelected: (String value) {
                                  _cookieController.text = value;
                                  state.setState(cookies: value);
                                },
                                itemBuilder: (BuildContext context) {
                                  return state.cookieHistory.map((h) {
                                    return PopupMenuItem<String>(
                                      value: h['cookies'],
                                      child: Text(
                                        h['host'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed: _isAnalyzing ? null : _analyze,
                      icon: _isAnalyzing 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.analytics_outlined),
                      label: Text(_isAnalyzing ? 'Analyzing...' : 'Find Images'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: _isAnalyzing ? null : _saveOriginHtml,
                      icon: const Icon(Icons.html_outlined),
                      label: Text(l10n.saveOriginHtml),
                    ),
                  ),
                  if (state.logs.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    Container(
                      height: 150,
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: state.logs.length,
                        itemBuilder: (context, i) => Text(
                          state.logs[i],
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Results Area
          Expanded(
            child: Column(
              children: [
                if (state.discoveredImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          'Select images to download (${state.discoveredImages.where((i)=>i.isSelected).length} selected)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {
                            for (var img in state.discoveredImages) {
                              img.isSelected = true;
                            }
                          }),
                          child: const Text('Select All'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: state.discoveredImages.any((i) => i.isSelected) ? _addToQueue : null,
                          icon: const Icon(Icons.download),
                          label: const Text('Add to Queue'),
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
                            Icon(Icons.image_search, size: 64, color: colorScheme.outlineVariant),
                            const SizedBox(height: 16),
                            const Text('No images discovered yet.'),
                            const Text('Enter a URL and requirement to start.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                        itemCount: state.discoveredImages.length,
                        itemBuilder: (context, index) {
                          final img = state.discoveredImages[index];
                          return _ImageDiscoveryCard(
                            image: img,
                            onToggle: () => setState(() => img.isSelected = !img.isSelected),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageDiscoveryCard extends StatelessWidget {
  final DiscoveredImage image;
  final VoidCallback onToggle;

  const _ImageDiscoveryCard({required this.image, required this.onToggle});

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: image.isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: image.isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onToggle,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: image.localCachePath != null
                      ? Image.file(File(image.localCachePath!), fit: BoxFit.cover)
                      : const Center(child: Icon(Icons.image, color: Colors.grey)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      image.url,
                      style: const TextStyle(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (image.isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: colorScheme.primary,
                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}