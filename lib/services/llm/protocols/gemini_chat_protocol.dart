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
    final payload = prepareGooglePayload(history, options, config.endpoint, tools: tools);
    logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      final appState = AppState();
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleGenAI (Standard)', {
          'url': url.toString(),
          'headers': headers,
          'body': payload,
        });
      }

      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
      }

      final data = jsonDecode(response.body);

      // Check for System-level errors (Section 3.3)
      if (data['error'] != null) {
        final err = data['error'];
        final msg = 'Google GenAI Error: [${err['code']}] ${err['message']} (${err['status']})';
        logger?.call(msg, level: 'ERROR');
        throw Exception(msg);
      }

      if (response.statusCode != 200) {
        logger?.call('Request failed with status: ${response.statusCode}', level: 'ERROR');
        throw Exception('Google GenAI Request failed: ${response.statusCode} - ${response.body}');
      }

      logger?.call('Response received, parsing data...', level: 'DEBUG');

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

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async* {
    final config = target.config;
    final url = target.decorateUrl(Uri.parse(
        '${config.endpoint}/models/${config.modelId}:streamGenerateContent?alt=sse'));
    logger?.call('Starting Google GenAI stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareGooglePayload(history, options, config.endpoint);
    logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'GoogleGenAI (Stream)', {
        'url': url.toString(),
        'headers': headers,
        'body': payload,
      });
    }

    final response = await client.send(request);

    if (response.statusCode != 200) {
      // Try to parse error from body if possible
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
      }
      client.close();
      try {
        final data = jsonDecode(body);
        if (data['error'] != null) {
          final err = data['error'];
          final msg = 'Google GenAI Stream Error: [${err['code']}] ${err['message']}';
          logger?.call(msg, level: 'ERROR');
          throw Exception(msg);
        }
      } catch (_) {}

      logger?.call('Stream request failed with status: ${response.statusCode}', level: 'ERROR');
      throw Exception('Google GenAI Stream Request failed: ${response.statusCode}');
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

        String dataLine = line;
        if (line.startsWith('data: ')) {
          dataLine = line.substring(6);
        }

        try {
          final chunkData = jsonDecode(dataLine);

          // Check for error in chunk
          if (chunkData['error'] != null) {
            final err = chunkData['error'];
            logger?.call('Stream Chunk Error: ${err['message']}', level: 'ERROR');
            throw Exception(err['message']);
          }

          yield* Stream.fromIterable(parseGoogleChunks(chunkData, logger: logger));
        } catch (e) {
          if (e is Exception) rethrow;
          // Ignore parse errors for empty/non-json lines
        }
      }
    } finally {
      client.close();
    }

    yield LLMResponseChunk(isDone: true);
  }
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

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch models: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> modelsJson = data['models'] ?? [];

    return modelsJson.map((m) => DiscoveredModel(
      modelId: m['name']?.toString().replaceFirst('models/', '') ?? '',
      displayName: m['displayName'] ?? m['name'] ?? '',
      description: m['description'] ?? '',
      rawData: m as Map<String, dynamic>,
    )).toList();
  }
}
