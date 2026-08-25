import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/safety_settings.dart';
import '../../../state/app_state.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'gemini_payload.dart';
import 'protocol.dart';

/// Gemini `POST /models/{model}:generateContent` (sync) and
/// `:streamGenerateContent?alt=sse` (streaming) — text conversation,
/// multimodal input and nano-banana-style image output all ride this one
/// surface.
class GeminiChatProtocol implements ChatProtocol {
  @override
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final url = target.decorateUrl(
        Uri.parse('${config.endpoint}/models/${config.modelId}:generateContent'));
    logger?.call('Preparing Google GenAI request to: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareGooglePayload(history, options, config.endpoint,
        tools: tools, emitsImages: target.model.capabilities.isImageGenerator);
    logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleGenAI (Standard)', {
          'url': redactUrl(url),
          'headers': headers,
          'body': payload,
        });
      }

      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = decodeJsonBody(response, apiName: 'Google GenAI');

      logger?.call('Response received, parsing data...', level: 'DEBUG');

      // A body with no candidates and no promptFeedback reached the caller as
      // an empty success — the same silent no-op the OpenAI surface used to
      // have. Only the synchronous path can judge this: in a stream a chunk
      // carrying nothing but usageMetadata is perfectly normal, so
      // parseGoogleChunks must stay tolerant of it.
      final candidates = data['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        final body = response.body;
        throw Exception('Google GenAI returned no candidates: '
            '${body.length > 500 ? '${body.substring(0, 500)}…' : body}');
      }

      String text = "";
      List<Uint8List> images = [];
      List<LLMToolCall> toolCalls = [];
      Map<String, dynamic> metadata = {};

      for (final chunk in parseGoogleChunks(data, logger: logger)) {
        if (chunk.textPart != null) text += chunk.textPart!;
        if (chunk.imagePart != null) images.add(chunk.imagePart!);
        if (chunk.toolCallPart != null) toolCalls.add(chunk.toolCallPart!);
        if (chunk.metadata != null) metadata = chunk.metadata!;
      }

      logger?.call('Parse complete. Text length: ${text.length}, Images: ${images.length}, Tool calls: ${toolCalls.length}', level: 'DEBUG');

      return LLMResponse(
        text: text,
        generatedImages: images,
        metadata: metadata,
        toolCalls: toolCalls,
      );
    } finally {
      client.close();
    }
  }

  /// ③ delivers a `functionCall` part whole inside a streamed candidate, so
  /// this is a smaller job than ①'s — but nothing needs it yet, and claiming
  /// the capability without the accumulator would answer tool-bearing
  /// requests as though no tools existed.
  @override
  bool get streamingDeclaresTools => false;

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    // Ignored: streamingDeclaresTools is false here, so the dispatcher never
    // routes a tool-bearing request to this surface.
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async* {
    final config = target.config;
    final url = target.decorateUrl(Uri.parse(
        '${config.endpoint}/models/${config.modelId}:streamGenerateContent?alt=sse'));
    logger?.call('Starting Google GenAI stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareGooglePayload(history, options, config.endpoint,
        emitsImages: target.model.capabilities.isImageGenerator);
    logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleGenAI (Stream)', {
        'url': redactUrl(url),
        'headers': headers,
        'body': payload,
      });
    }

    final response = await client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
      }
      client.close();
      logger?.call('Stream request failed with status: ${response.statusCode}', level: 'ERROR');
      // The shared decoder owns the message shape (provider error text when
      // the body is JSON, excerpt otherwise) and always throws on non-2xx.
      decodeJsonBody(http.Response(body, response.statusCode),
          apiName: 'Google GenAI stream');
      throw LLMApiException(
          'Google GenAI stream request failed: ${response.statusCode}',
          statusCode: response.statusCode);
    }

    logger?.call('Stream connection established, waiting for chunks...', level: 'DEBUG');

    try {
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
      }
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) continue;

        if (debugFile != null) {
          await LLMDebugLogger.appendLine(debugFile, line);
        }

        yield* Stream.fromIterable(geminiChunksFromSseLine(line, logger: logger));
      }
    } finally {
      client.close();
    }

    yield LLMResponseChunk(isDone: true);
  }
}

/// The chunks carried by one SSE line of a Gemini stream — empty for lines
/// with no payload.
///
/// Line handling follows the shared SSE rules ([sseDataPayload]): the space
/// after `data:` is optional, `:` keep-alives and `[DONE]` carry nothing, and
/// named `event:` lines are skipped here (the helper passes unprefixed lines
/// through for relays that stream bare JSON). A line that then fails to parse
/// as JSON is relay noise and is *ignored* — the previous inline version
/// rethrew the `FormatException` (it implements `Exception`), so a single
/// `data:{…}` without a space or one keep-alive comment killed the whole
/// stream while the code's own comment claimed the line would be skipped.
///
/// An in-chunk error envelope still throws: that is the request failing, not
/// the line being noise, so it is checked *after* the tolerant decode.
@visibleForTesting
Iterable<LLMResponseChunk> geminiChunksFromSseLine(String line,
    {LLMLogger? logger}) {
  if (line.startsWith('event:')) return const [];
  final payload = sseDataPayload(line);
  if (payload == null) return const [];

  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map) return const [];
  final chunkData = decoded.cast<String, dynamic>();

  final err = chunkData['error'];
  if (err != null) {
    final msg = err is Map ? err['message'] : err;
    logger?.call('Stream Chunk Error: $msg', level: 'ERROR');
    throw LLMApiException('Google GenAI stream error: $msg', isEnvelope: true);
  }

  return parseGoogleChunks(chunkData, logger: logger);
}

/// Gemini `GET /models` discovery listing.
class GeminiDiscoveryProtocol implements DiscoveryProtocol {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMTarget target) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);

    final url = target.decorateUrl(Uri.parse('$baseUrl/models'));
    final headers = target.headers();

    final response = await http.get(url, headers: headers);

    final data = decodeJsonBody(response, apiName: 'Gemini models');
    final rawModels = data['models'];
    final List<dynamic> modelsJson = rawModels is List ? rawModels : const [];

    return modelsJson.map((m) => DiscoveredModel(
      modelId: m['name']?.toString().replaceFirst('models/', '') ?? '',
      displayName: m['displayName'] ?? m['name'] ?? '',
      description: m['description'] ?? '',
      rawData: m as Map<String, dynamic>,
    )).toList();
  }
}
