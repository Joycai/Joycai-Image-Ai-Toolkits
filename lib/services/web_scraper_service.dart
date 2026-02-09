import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import 'llm/llm_models.dart';
import 'llm/llm_service.dart';

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
    final dataDir = await AppPaths.getDataDirectory();
    final dir = Directory(p.join(dataDir, 'cache', 'downloader'));
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

    // Prepare prompt for LLM
    final prompt = '''
Identify images from the following list that match this requirement: "$requirement"
URL of the page: $url

List of candidate images (JSON format):
${jsonEncode(imagesMetadata)}

Return only a JSON array of the "url" strings of the images that match. No explanation.
Example output: ["https://example.com/img1.jpg", "https://example.com/img2.png"]
''';

    final llmResponse = await LLMService().request(
      modelIdentifier: modelIdentifier,
      messages: [LLMMessage(role: LLMRole.user, content: prompt)],
      useStream: false,
    );

    onLog?.call('LLM analysis complete. Filtering results...');
    
    try {
      final String jsonStr = _extractJsonArray(llmResponse.text);
      final List<dynamic> matchedUrls = jsonDecode(jsonStr);
      final List<String> matchedUrlStrings = matchedUrls.cast<String>();

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
    } catch (e) {
      onLog?.call('Error parsing LLM response: $e');
      throw Exception('Failed to parse LLM analysis results.');
    }
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

  String _extractJsonArray(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return '[]';
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
