import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm_types.dart';
import 'openai_images_protocol.dart';
import 'protocol.dart';

/// Files + Batch transport. No retries of mutations: an ambiguous create must
/// be reconciled by its durable intent, never re-issued automatically.
class OpenAIImageBatchProtocol {
  Future<Map<String, dynamic>> payload(
    LLMTarget target,
    List<LLMMessage> history,
    Map<String, dynamic>? options,
  ) async {
    final message = history.lastWhere((m) => m.role == LLMRole.user);
    if (message.attachments.length > (target.model.capabilities.maxReferenceImages ?? 16)) {
      throw LLMApiException('Too many reference images for Batch.');
    }
    final images = <Map<String, String>>[];
    for (final attachment in message.attachments) {
      final bytes = await readAttachmentBytes(attachment);
      if (bytes == null) throw LLMApiException('Cannot read a Batch reference image.');
      final url = 'data:${attachment.mimeType};base64,${base64Encode(bytes)}';
      if (url.length > 20971520) {
        throw LLMApiException('A Batch reference image exceeds the JSON image limit.');
      }
      images.add({'image_url': url});
    }
    final size = OpenAIImagesProtocol.resolveImageSize(optionsWithCheckedSize(target, options));
    return {
      'model': target.config.modelId,
      'prompt': message.content,
      'n': 1,
      'size': ?size,
      if (options?['quality'] != null && options?['quality'] != 'auto')
        'quality': options!['quality'],
      ...OpenAIImagesProtocol.outputOptions(options),
      if (images.isNotEmpty) 'images': images,
    };
  }

  Future<Map<String, dynamic>> _send(
    LLMTarget target,
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final abort = Completer<void>();
    final timer = Timer(const Duration(minutes: 2), abort.complete);
    final client = target.config.createClient();
    try {
      final request = http.AbortableRequest(
        method,
        Uri.parse('${target.config.endpoint}$path'),
        abortTrigger: abort.future,
      );
      request.headers.addAll(target.headers());
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(await client.send(request));
      return decodeJsonBody(response, apiName: 'OpenAI Batch');
    } finally {
      timer.cancel();
      client.close();
    }
  }

  Future<String> upload(LLMTarget target, String customId, Map<String, dynamic> body) async {
    final endpoint = body.containsKey('images') ? '/v1/images/edits' : '/v1/images/generations';
    final bytes = utf8.encode(
      '${jsonEncode({'custom_id': customId, 'method': 'POST', 'url': endpoint, 'body': body})}\n',
    );
    if (bytes.length > 200000000) throw LLMApiException('Batch input exceeds 200 MB.');
    final abort = Completer<void>();
    final timer = Timer(const Duration(minutes: 5), abort.complete);
    final client = target.config.createClient();
    try {
      final request = http.AbortableMultipartRequest(
        'POST',
        Uri.parse('${target.config.endpoint}/files'),
        abortTrigger: abort.future,
      );
      request.headers.addAll(
        Map.of(target.headers())
          ..remove('Content-Type')
          ..remove('content-type'),
      );
      request.fields['purpose'] = 'batch';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: '$customId.jsonl'));
      final data = decodeJsonBody(
        await http.Response.fromStream(await client.send(request)),
        apiName: 'OpenAI Batch upload',
      );
      final id = data['id'];
      if (id is! String || id.isEmpty) throw LLMApiException('Missing uploaded file ID.');
      return id;
    } finally {
      timer.cancel();
      client.close();
    }
  }

  Future<Map<String, dynamic>> create(
    LLMTarget target,
    String inputFileId,
    String intent,
    bool edit,
  ) => _send(
    target,
    'POST',
    '/batches',
    body: {
      'input_file_id': inputFileId,
      'endpoint': edit ? '/v1/images/edits' : '/v1/images/generations',
      'completion_window': '24h',
      'metadata': {'joycai_intent': intent},
    },
  );

  Future<Map<String, dynamic>> inspect(LLMTarget target, String id) =>
      _send(target, 'GET', '/batches/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> cancel(LLMTarget target, String id) =>
      _send(target, 'POST', '/batches/${Uri.encodeComponent(id)}/cancel');

  Future<Map<String, dynamic>?> reconcile(LLMTarget target, String intent, String inputId) async {
    String? after;
    Map<String, dynamic>? match;
    // Bounded per refresh; never infer non-existence from a partial listing.
    for (var page = 0; page < 100; page++) {
      final list = await _send(
        target,
        'GET',
        '/batches?limit=100${after == null ? '' : '&after=${Uri.encodeComponent(after)}'}',
      );
      final rows = list['data'] as List? ?? [];
      for (final row in rows.whereType<Map>()) {
        if (row['metadata'] is Map &&
            row['metadata']['joycai_intent'] == intent &&
            row['input_file_id'] == inputId) {
          if (match != null) {
            throw LLMApiException(
              'Multiple batches match this submission; resolve before continuing.',
            );
          }
          match = Map<String, dynamic>.from(row);
        }
      }
      if (list['has_more'] != true) return match;
      if (rows.isEmpty || rows.last['id'] is! String) break;
      after = rows.last['id'] as String;
    }
    throw LLMApiException('Batch reconciliation incomplete; no new request was submitted.');
  }

  /// Stream JSONL lines instead of buffering a potentially large batch file.
  Future<Map<String, dynamic>?> resultLine(LLMTarget target, String fileId, String customId) async {
    final abort = Completer<void>();
    final timer = Timer(const Duration(minutes: 5), abort.complete);
    final client = target.config.createClient();
    try {
      final request = http.AbortableRequest(
        'GET',
        Uri.parse('${target.config.endpoint}/files/${Uri.encodeComponent(fileId)}/content'),
        abortTrigger: abort.future,
      )..headers.addAll(target.headers());
      final response = await client.send(request);
      if (response.statusCode != 200) {
        decodeJsonBody(await http.Response.fromStream(response), apiName: 'OpenAI Batch result');
      }
      Map<String, dynamic>? found;
      await for (final line
          in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final row = jsonDecode(line);
        if (row is Map && row['custom_id'] == customId) {
          if (found != null) throw LLMApiException('Duplicate Batch result identity.');
          found = Map<String, dynamic>.from(row);
        }
      }
      return found;
    } finally {
      timer.cancel();
      client.close();
    }
  }

  Future<LLMResponse> decodeResult(LLMTarget target, Map<String, dynamic> body, int inputs) async {
    final client = target.config.createClient();
    try {
      return await OpenAIImagesProtocol().decodeResult(
        http.Response(jsonEncode(body), 200),
        client,
        null,
        null,
        inputs,
        null,
      );
    } finally {
      client.close();
    }
  }
}
