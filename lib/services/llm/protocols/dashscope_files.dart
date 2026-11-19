import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

import '../llm_types.dart';
import 'protocol.dart';

// Serialize query/upload per credential scope within this app process. Keep only
// a digest of credentials; neither file URLs nor credentials form a disk cache.
final _uploadTurns = <String, Future<void>>{};

/// File-manager upload for Token Plan: unlike temporary oss:// resources, its
/// signed download URLs can be read by the plan's native video endpoint.
/// Remote files are retained for reuse; deleting them here could break jobs
/// still reading them. Every attempt refreshes metadata instead of caching URLs.
Future<String> uploadDashScopeFile({
  required http.Client client,
  required String base,
  required String apiKey,
  required File file,
  required String mime,
  required void Function() checkCancelled,
  Map<String, dynamic>? options,
}) async {
  final scope = sha256.convert(utf8.encode('$base\u0000$apiKey')).toString();
  final previous = _uploadTurns[scope];
  final turn = Completer<void>();
  _uploadTurns[scope] = turn.future;
  try {
    if (previous != null) await previous;
    checkCancelled();
    final size = await file.length();
    final digest = await md5.bind(file.openRead()).first;
    final hexDigest = digest.toString();
    final base64Digest = base64Encode(digest.bytes);
    checkCancelled();
    final headers = {'Authorization': 'Bearer $apiKey', 'Accept': 'application/json'};

    Future<Map<String, dynamic>?> get(Uri uri, {bool allowMissing = false}) async {
      for (var attempt = 0; ; attempt++) {
        checkCancelled();
        final request = buildJsonRequest('GET', uri, headers: headers, body: '', options: options);
        request.followRedirects = false;
        final response = await http.Response.fromStream(await client.send(request));
        checkCancelled();
        if (response.statusCode == 429 && attempt < 2) {
          final delay = parseRetryAfter(response.headers) ?? Duration(seconds: 2 << attempt);
          if (delay <= const Duration(seconds: 30)) {
            await cancellableSleep(delay, () {
              checkCancelled();
              return false;
            });
            continue;
          }
        }
        if (allowMissing && response.statusCode == 404) return null;
        return _fileData(response);
      }
    }

    bool matches(Map entry) {
      final remote = entry['md5']?.toString().trim();
      return entry['size'] == size &&
          (remote?.toLowerCase() == hexDigest || remote == base64Digest);
    }

    Future<String?> resolve(String id) async {
      final data = await get(
        Uri.parse('$base/files/${Uri.encodeComponent(id)}'),
        allowMissing: true,
      );
      if (data == null || !matches(data)) return null;
      final raw = data['url'];
      final uri = raw is String ? Uri.tryParse(raw) : null;
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment) {
        throw LLMApiException('DashScope file metadata returned an invalid download URL.');
      }
      // Use exactly the signed URL from the API: rewriting can invalidate a
      // gateway signature. It is passed to inference, never fetched with a key.
      return raw as String;
    }

    var seen = 0;
    for (var page = 1; page <= 100; page++) {
      final data = (await get(
        Uri.parse('$base/files').replace(queryParameters: {'page_no': '$page', 'page_size': '100'}),
      ))!;
      final entries = data['files'];
      final total = data['total'];
      if (entries is! List ||
          entries.any((entry) => entry is! Map) ||
          total is! int ||
          total < 0 ||
          (entries.isEmpty && seen < total)) {
        throw LLMApiException('DashScope returned an invalid file listing.');
      }
      for (final entry in entries.whereType<Map>()) {
        final id = entry['file_id'];
        if (matches(entry) && id is String && id.isNotEmpty) {
          final url = await resolve(id);
          if (url != null) return url;
        }
      }
      seen += entries.length;
      if (seen >= total) break;
      if (page == 100) throw LLMApiException('DashScope file listing exceeds the supported quota.');
    }

    checkCancelled();
    final extension = switch (mime) {
      'video/mp4' => 'mp4',
      'video/quicktime' => 'mov',
      'audio/wav' => 'wav',
      'audio/mpeg' => 'mp3',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/bmp' => 'bmp',
      'image/webp' => 'webp',
      _ => throw LLMApiException('Unsupported upload media format.'),
    };
    final request =
        http.AbortableMultipartRequest(
            'POST',
            Uri.parse('$base/files'),
            abortTrigger: abortTriggerOf(options),
          )
          ..followRedirects = false
          ..headers.addAll(headers)
          ..fields['purpose'] = 'file-extract'
          ..files.add(
            await http.MultipartFile.fromPath(
              'files',
              file.path,
              filename: '${const Uuid().v4()}.$extension',
              contentType: MediaType.parse(mime),
            ),
          );
    // Deliberately bypass sendJsonRequest: uploads never fire the paid-submit hook.
    final data = _fileData(await http.Response.fromStream(await client.send(request)));
    checkCancelled();
    final uploaded = data['uploaded_files'];
    final failed = data['failed_uploads'];
    if (uploaded is! List ||
        uploaded.length != 1 ||
        (failed != null && (failed is! List || failed.isNotEmpty))) {
      throw LLMApiException('DashScope file upload did not return one successful file.');
    }
    final entry = uploaded.single;
    final id = entry is Map ? entry['file_id'] : null;
    if (id is! String || id.isEmpty) {
      throw LLMApiException('DashScope file upload returned no file ID.');
    }
    final url = await resolve(id);
    if (url == null) throw LLMApiException('DashScope uploaded file failed content verification.');
    return url;
  } finally {
    turn.complete();
    if (identical(_uploadTurns[scope], turn.future)) unawaited(_uploadTurns.remove(scope));
  }
}

Map<String, dynamic> _fileData(http.Response response) {
  // Never echo API bodies: metadata includes signed URLs and credential IDs.
  if (response.statusCode != 200) {
    throw LLMApiException('DashScope file request failed (HTTP ${response.statusCode}).');
  }
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['code'] == null && decoded['data'] is Map) {
      return (decoded['data'] as Map).cast<String, dynamic>();
    }
  } catch (_) {
    // Fall through to a fixed diagnostic.
  }
  throw LLMApiException('DashScope returned an invalid file response.');
}
