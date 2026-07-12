import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import 'database_service.dart';
import 'llm/llm_service.dart';
import 'llm/llm_types.dart';

class DiscoveredImage {
  final String url;
  final String? alt;
  final String? context;
  final String? localCachePath;
  bool isSelected;

  DiscoveredImage({
    required this.url,
    this.alt,
    this.context,
    this.localCachePath,
    this.isSelected = false,
  });

  Map<String, dynamic> toMap() => {
    'url': url,
    'alt': alt,
    'context': context,
    'localCachePath': localCachePath,
  };
}

class WebScraperService {
  static final WebScraperService _instance = WebScraperService._internal();
  factory WebScraperService() => _instance;
  WebScraperService._internal();

  /// Parses cookie input. Supports:
  /// 1. Netscape HTTP Cookie File format (tab-separated)
  /// 2. Standard header format (name=value; name2=value2)
  String parseCookies(String input) {
    if (input.isEmpty) return '';
    
    final lines = input.split(RegExp(r'\r?\n'));
    final List<String> cookiePairs = [];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final tabs = line.split('\t');
      if (tabs.length >= 7) {
        // Netscape format: domain, flag, path, secure, expiration, name, value
        final name = tabs[5];
        final value = tabs[6];
        cookiePairs.add('$name=$value');
      } else if (line.contains('=')) {
        // Fallback to name=value or already formatted string
        // If it's a single line with semicolons, it might be already formatted
        if (!line.contains('\t') && line.contains(';')) {
           return line; 
        }
        cookiePairs.add(line);
      }
    }

    return cookiePairs.join('; ');
  }

  Future<Directory> get _cacheDir async {
    final tempDir = await AppPaths.getTempDirectory();
    final dir = Directory(p.join(tempDir, 'joycai', 'cache', 'downloader'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> clearCache() async {
    final dir = await _cacheDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<int> getCacheSize() async {
    final dir = await _cacheDir;
    if (!await dir.exists()) return 0;
    int size = 0;
    await for (final file in dir.list(recursive: true)) {
      if (file is File) {
        size += await file.length();
      }
    }
    return size;
  }

  Future<String> fetchRawHtml({
    required String url,
    String? cookies,
  }) async {
    final formattedCookies = parseCookies(cookies ?? '');
    final client = HttpClient();
    // Add a realistic User-Agent
    client.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.add('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8');
      request.headers.add('Accept-Language', 'en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7');
      
      if (formattedCookies.isNotEmpty) {
        request.headers.add(HttpHeaders.cookieHeader, formattedCookies);
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch page: ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  Future<List<DiscoveredImage>> discoverImages({
    required String url,
    required String requirement,
    required dynamic modelIdentifier,
    String? cookies,
    String? manualHtml, // Added manualHtml support
    Function(String)? onLog,
  }) async {
    final formattedCookies = parseCookies(cookies ?? '');
    String html;
    if (manualHtml != null && manualHtml.isNotEmpty) {
      onLog?.call('Using manually provided HTML content...');
      html = manualHtml;
    } else {
      onLog?.call('Fetching page: $url');
      html = await fetchRawHtml(url: url, cookies: cookies);
    }

    onLog?.call('Parsing HTML and cleaning content in background...');
    final List<Map<String, String>> imagesMetadata = await compute(_extractImagesMetadataIsolate, {
      'html': html,
      'url': url,
    });

    if (imagesMetadata.isEmpty) {
      onLog?.call('No images found on page.');
      return [];
    }

    onLog?.call('Found ${imagesMetadata.length} candidate images. Analyzing with LLM...');

    final contextWindow = await _resolveContextWindow(modelIdentifier);
    final matchedUrlStrings = await _selectImagesWithLLM(
      modelIdentifier: modelIdentifier,
      requirement: requirement,
      pageUrl: url,
      imagesMetadata: imagesMetadata,
      contextWindow: contextWindow,
      onLog: onLog,
    );

    onLog?.call('LLM analysis complete. Filtering results...');

    final results = <DiscoveredImage>[];
    final cacheDir = await _cacheDir;

    for (var metadata in imagesMetadata) {
      final imageUrl = metadata['url']!;
      if (matchedUrlStrings.contains(imageUrl)) {
        // Pre-cache thumbnail if possible
        String? localPath;
        try {
          localPath = await _cacheThumbnail(imageUrl, cacheDir, formattedCookies);
        } catch (e) {
          onLog?.call('Failed to cache thumbnail for $imageUrl: $e');
        }

        results.add(DiscoveredImage(
          url: imageUrl,
          alt: metadata['alt'],
          context: metadata['context'],
          localCachePath: localPath,
        ));
      }
    }

    return results;
  }

  /// Asks the model to pick matching images via native tool calling.
  ///
  /// The model must submit its selection through the `select_images` tool;
  /// URLs are validated against the candidate set and invalid entries are
  /// reported back so the model can correct itself (up to [_maxSelectTurns]
  /// turns). This replaces the old free-text JSON parsing, which broke
  /// whenever the model added commentary around the array.
  static const int _maxSelectTurns = 3;

  /// Fallback batch size used when the model's context window is unknown. Large
  /// candidate lists overflow the context window of small local models
  /// (e.g. Ollama's default 4096-token window), so the model burns its whole
  /// generation budget before it can emit a tool call. Splitting the list into
  /// small batches keeps every request comfortably inside a modest context.
  static const int _defaultBatchSize = 10;

  /// Sentinel batch size meaning "no splitting" — used when a model is marked
  /// as having an unlimited context window.
  static const int _unlimitedBatchSize = 1 << 30;

  /// Reads the configured context window for [modelIdentifier] (a DB id), or
  /// null when it isn't a stored model or the field is unset.
  Future<int?> _resolveContextWindow(dynamic modelIdentifier) async {
    if (modelIdentifier is! int) return null;
    try {
      final models = await DatabaseService().getModels();
      for (final m in models) {
        if (m.id == modelIdentifier) return m.contextWindow;
      }
    } catch (_) {
      // Best effort — fall back to the default batch size.
    }
    return null;
  }

  /// Derives how many candidate images to show per request from the model's
  /// context window. Roughly one image per 512 tokens, leaving the rest of the
  /// window for the model's reasoning and the tool call, clamped to a sane range.
  ///
  /// `null` context window means "not configured" → conservative default.
  /// A value of `0` (or negative) means "unlimited" → everything in one batch.
  int _batchSizeFor(int? contextWindow) {
    if (contextWindow == null) return _defaultBatchSize;
    if (contextWindow <= 0) return _unlimitedBatchSize;
    return (contextWindow ~/ 512).clamp(4, 40);
  }

  Future<Set<String>> _selectImagesWithLLM({
    required dynamic modelIdentifier,
    required String requirement,
    required String pageUrl,
    required List<Map<String, String>> imagesMetadata,
    int? contextWindow,
    Function(String)? onLog,
  }) async {
    final Set<String> selected = {};
    final batchSize = _batchSizeFor(contextWindow);
    final totalBatches = (imagesMetadata.length / batchSize).ceil();

    int failures = 0;
    Object? lastError;
    for (int b = 0; b < totalBatches; b++) {
      final start = b * batchSize;
      final end = (start + batchSize).clamp(0, imagesMetadata.length);
      final batch = imagesMetadata.sublist(start, end);

      onLog?.call('Analyzing batch ${b + 1}/$totalBatches (${batch.length} images)...');
      try {
        final picked = await _selectImagesInBatch(
          modelIdentifier: modelIdentifier,
          requirement: requirement,
          pageUrl: pageUrl,
          batch: batch,
          onLog: onLog,
        );
        selected.addAll(picked);
      } catch (e) {
        failures++;
        lastError = e;
        // Keep processing the remaining batches rather than aborting everything.
        onLog?.call('Batch ${b + 1}/$totalBatches failed: $e');
      }
    }

    // Only surface an error when the model never produced a single selection.
    if (failures == totalBatches && lastError != null) {
      throw Exception('Image selection failed for every batch. Last error: $lastError');
    }

    onLog?.call('Model selected ${selected.length} image(s) across $totalBatches batch(es).');
    return selected;
  }

  /// Runs the tool-calling conversation for a single batch of candidates.
  ///
  /// Candidates are presented as a compact, numbered list and the model selects
  /// by integer id rather than echoing long URLs. This keeps the prompt small
  /// and removes the "URL not copied exactly" failure mode.
  Future<Set<String>> _selectImagesInBatch({
    required dynamic modelIdentifier,
    required String requirement,
    required String pageUrl,
    required List<Map<String, String>> batch,
    Function(String)? onLog,
  }) async {
    final buffer = StringBuffer();
    for (int i = 0; i < batch.length; i++) {
      final m = batch[i];
      final alt = (m['alt'] ?? '').trim();
      final ctx = (m['context'] ?? '')
          .replaceFirst('Element: img, Parent:', '')
          .trim();
      buffer.writeln('[$i] url: ${m['url'] ?? ''}');
      if (alt.isNotEmpty) buffer.writeln('    alt: $alt');
      if (ctx.isNotEmpty) buffer.writeln('    container: $ctx');
    }

    final tools = [
      LLMTool(
        name: 'select_images',
        description: 'Submit the id numbers of the candidate images that match the '
            'requirement. Submit an empty array if none match.',
        parameters: {
          'type': 'object',
          'properties': {
            'ids': {
              'type': 'array',
              'items': {'type': 'integer'},
              'description': 'The [id] numbers of matching images.',
            },
          },
          'required': ['ids'],
        },
      ),
    ];

    final messages = <LLMMessage>[
      LLMMessage(
        role: LLMRole.system,
        content: 'You are an image curation assistant. Review the candidate images and '
            'select the ones matching the user requirement by calling the select_images tool. '
            'Do not answer in plain text — always submit your selection via the tool.',
      ),
      LLMMessage(
        role: LLMRole.user,
        content: '''
Requirement: "$requirement"
Page: $pageUrl

Candidate images:
${buffer.toString().trim()}

Call select_images with the id numbers of the images that match the requirement.
''',
      ),
    ];

    final Set<String> selected = {};
    bool submitted = false;

    for (int turn = 0; turn < _maxSelectTurns; turn++) {
      final response = await LLMService().request(
        modelIdentifier: modelIdentifier,
        messages: messages,
        tools: tools,
        useStream: false,
      );

      if (response.toolCalls.isEmpty) {
        if (submitted) break; // Done: selection already received.
        // A "length" finish reason means the model ran out of tokens before it
        // could emit a tool call — nudging again only makes the prompt longer
        // and repeats the failure, so fail fast with an actionable message.
        if (response.metadata['finish_reason'] == 'length') {
          throw Exception('Model output was cut off before a tool call '
              '(context/length limit reached). Increase the model context window '
              '(e.g. Ollama num_ctx / OLLAMA_CONTEXT_LENGTH) or use a model that '
              'reasons less verbosely.');
        }
        // The model answered in text instead of calling the tool — nudge once.
        onLog?.call('Model replied without calling select_images; asking again...');
        messages.add(LLMMessage(role: LLMRole.assistant, content: response.text));
        messages.add(LLMMessage(
          role: LLMRole.user,
          content: 'Please submit your selection by calling the select_images tool with id numbers.',
        ));
        continue;
      }

      messages.add(LLMMessage(
        role: LLMRole.assistant,
        content: response.text,
        toolCalls: response.toolCalls,
      ));

      bool hadErrors = false;
      for (final call in response.toolCalls) {
        Map<String, dynamic> result;
        if (call.name != 'select_images') {
          result = {'status': 'error', 'message': 'Unknown tool. Use select_images.'};
          hadErrors = true;
        } else {
          final rawIds = call.arguments['ids'];
          final ids = rawIds is List
              ? rawIds.map((e) => int.tryParse(e.toString())).whereType<int>().toList()
              : <int>[];
          final invalid = ids.where((id) => id < 0 || id >= batch.length).toList();
          final valid = ids.where((id) => id >= 0 && id < batch.length).toList();

          for (final id in valid) {
            final url = batch[id]['url'];
            if (url != null) selected.add(url);
          }
          submitted = true;

          if (invalid.isEmpty) {
            result = {'status': 'ok', 'accepted': valid.length};
          } else {
            hadErrors = true;
            result = {
              'status': 'partial',
              'accepted': valid.length,
              'rejected': invalid,
              'message': 'Rejected ids are out of range. '
                  'Valid ids are 0..${batch.length - 1}.',
            };
            onLog?.call('Rejected ${invalid.length} out-of-range id(s).');
          }
        }

        messages.add(LLMMessage(
          role: LLMRole.tool,
          content: jsonEncode(result),
          toolCallId: call.id,
          toolName: call.name,
        ));
      }

      // Selection received cleanly — no need for another round-trip.
      if (submitted && !hadErrors) break;
    }

    if (!submitted) {
      throw Exception('The model did not submit a selection via the select_images tool.');
    }

    return selected;
  }

  static List<Map<String, String>> _extractImagesMetadataIsolate(Map<String, String> data) {
    final html = data['html']!;
    final baseUrl = data['url']!;
    final document = html_parser.parse(html);
    
    // Clean document
    document.querySelectorAll('script, style, head, iframe, noscript, svg').forEach((e) => e.remove());

    final List<Map<String, String>> metadata = [];
    final baseUri = Uri.parse(baseUrl);

    document.querySelectorAll('img').forEach((img) {
      // Check multiple possible sources for lazy loaders
      final src = img.attributes['src'] ?? 
                  img.attributes['data-src'] ?? 
                  img.attributes['data-original'] ??
                  img.attributes['lazy-src'] ??
                  img.attributes['data-lazy-src'];
      
      if (src == null || src.isEmpty) {
        // Try to parse srcset if src is missing
        final srcset = img.attributes['srcset'];
        if (srcset != null && srcset.isNotEmpty) {
          // Simplistic pick: take the last one (usually highest res)
          final parts = srcset.split(',');
          final last = parts.last.trim().split(' ').first;
          _addMetadataToList(metadata, baseUri, last, img.attributes['alt'] ?? '', img);
        }
        return;
      }

      _addMetadataToList(metadata, baseUri, src, img.attributes['alt'] ?? '', img);
    });

    // Also look for background images in inline styles if they look relevant
    document.querySelectorAll('[style*="background-image"]').forEach((el) {
      final style = el.attributes['style'];
      if (style != null) {
        final regExp = RegExp('url\\((["\']?)(.*?)\\1\\)');
        final match = regExp.firstMatch(style);
        if (match != null) {
          final src = match.group(2);
          if (src != null && src.isNotEmpty) {
            _addMetadataToList(metadata, baseUri, src, 'Background image', el);
          }
        }
      }
    });

    // Remove duplicates
    final seen = <String>{};
    metadata.retainWhere((m) => seen.add(m['url']!));

    return metadata.take(50).toList(); // Limit to 50 for token sanity
  }

  static void _addMetadataToList(List<Map<String, String>> list, Uri baseUri, String src, String alt, dom.Element el) {
    try {
      final absoluteUrl = baseUri.resolve(src).toString();
      final parentClass = el.parent?.attributes['class'] ?? '';
      final parentId = el.parent?.attributes['id'] ?? '';

      list.add({
        'url': absoluteUrl,
        'alt': alt,
        'context': 'Element: ${el.localName}, Parent: $parentClass $parentId',
      });
    } catch (_) {}
  }

  Future<String?> _cacheThumbnail(String url, Directory cacheDir, String? formattedCookies) async {
    final bytesToHash = utf8.encode(url);
    final hash = sha256.convert(bytesToHash).toString();
    final fileName = hash + p.extension(Uri.parse(url).path);
    final filePath = p.join(cacheDir.path, fileName);
    final file = File(filePath);

    if (await file.exists()) return filePath;

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (formattedCookies != null && formattedCookies.isNotEmpty) {
        request.headers.add(HttpHeaders.cookieHeader, formattedCookies);
      }
      final response = await request.close();
      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e));
        await file.writeAsBytes(bytes);
        return filePath;
      }
    } catch (e) {
      // Ignore download errors for thumbnails
    } finally {
      client.close();
    }
    return null;
  }
}
