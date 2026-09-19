import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/safety_settings.dart';
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
      Uri.parse(geminiGenerateUrl(config.endpoint, config.modelId)),
    );
    logger?.call(
      'Preparing Google GenAI request to: ${url.host}',
      level: 'DEBUG',
    );
    final headers = target.headers();
    final payload = prepareGooglePayload(
      history,
      options,
      config.endpoint,
      tools: tools,
      emitsImages: target.model.capabilities.isImageGenerator,
      modelId: config.modelId,
      // Layer 3 says which field generation; the config says how hard.
      thinking: target.model.geminiThinking,
      reasoningEffort: config.effectiveReasoningEffort,
      outputCap: outputCapFor(target, options),
    );
    logger?.call(
      'Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}',
      level: 'DEBUG',
    );

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(
          config.modelId,
          'GoogleGenAI (Standard)',
          {'url': redactUrl(url), 'headers': headers, 'body': payload},
        );
      }

      // Abortable: LLMService cancels or times out a non-streaming request
      // through the options' trigger (sendJsonRequest).
      final response = await sendJsonRequest(
        client,
        url,
        headers: headers,
        body: jsonEncode(payload),
        options: options,
      );

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
          debugFile,
          'Status: ${response.statusCode}',
        );
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
        await LLMDebugLogger.finish(debugFile);
      }

      final data = decodeJsonBody(response, apiName: 'Google GenAI');

      logger?.call('Response received, parsing data...', level: 'DEBUG');

      // A body with no candidates and no promptFeedback reached the caller as
      // an empty success — the same silent no-op the OpenAI surface used to
      // have. Only the synchronous path can judge this: in a stream a chunk
      // carrying nothing but usageMetadata is perfectly normal, so
      // parseGoogleChunks must stay tolerant of it.
      final candidates = data['candidates'];
      // A prompt-level block also has no candidates, but it is not a malformed
      // body: parseGoogleChunks publishes it as `content_filter` and
      // LLMService fails the request after recording usage.
      final feedback = data['promptFeedback'];
      final promptBlocked = feedback is Map && feedback['blockReason'] != null;
      if (!promptBlocked && (candidates is! List || candidates.isEmpty)) {
        final body = response.body;
        throw LLMApiException(
          'Google GenAI returned no candidates: '
          '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
        );
      }

      String text = '';
      String reasoning = '';
      final List<Uint8List> images = [];
      final List<LLMToolCall> toolCalls = [];
      Map<String, dynamic> metadata = {};

      for (final chunk in parseGoogleChunks(data, logger: logger)) {
        if (chunk.textPart != null) text += chunk.textPart!;
        if (chunk.reasoningPart != null) reasoning += chunk.reasoningPart!;
        if (chunk.imagePart != null) images.add(chunk.imagePart!);
        if (chunk.toolCallPart != null) toolCalls.add(chunk.toolCallPart!);
        if (chunk.metadata != null) metadata = chunk.metadata!;
      }

      logger?.call(
        'Parse complete. Text length: ${text.length}, Images: ${images.length}, Tool calls: ${toolCalls.length}',
        level: 'DEBUG',
      );

      final emptyEnd = geminiEmptyEndFailure(
        metadata,
        sawOutput: text.isNotEmpty ||
            reasoning.isNotEmpty ||
            images.isNotEmpty ||
            toolCalls.isNotEmpty,
      );
      if (emptyEnd != null) throw emptyEnd;

      // ③'s replay carrier: the model turn's parts verbatim, only when it
      // called tools ([LLMMessage.rawModelParts]).
      final rawParts = (GeminiModelPartsCollector()..feed(data)).toolTurnParts;

      return LLMResponse(
        text: text,
        generatedImages: images,
        metadata: metadata,
        // ③'s thought summaries, kept off the deliverable. No field name: ③'s
        // replay obligation is the raw parts and their signatures, not this.
        reasoningContent: reasoning.isEmpty ? null : reasoning,
        rawModelParts: rawParts,
        // The producer of the raw parts and the calls' thought signatures,
        // which are replayed only to the same model (prepareGooglePayload).
        rawThinkingModelId: rawParts != null ||
                toolCalls.any((c) => c.thoughtSignature != null)
            ? config.modelId
            : null,
        toolCalls: toolCalls,
      );
    } finally {
      client.close();
    }
  }

  /// ③ needs no accumulator at all: a `functionCall` arrives whole inside a
  /// streamed candidate part, and [geminiChunksFromSseLine] — the *same*
  /// parser the synchronous path uses — already reads it, `thoughtSignature`
  /// included. Declaring tools on the stream was the only missing piece.
  ///
  /// `thoughtSignature` is ③'s entire replay obligation (③ answers a
  /// tool-calling turn replayed without it with `INVALID_ARGUMENT`), and it
  /// rides on the [LLMToolCall] itself rather than in a separate block group
  /// the way ④'s thinking does — so there is nothing here for the streaming
  /// path to drop.
  @override
  bool get streamingDeclaresTools => true;

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async* {
    final config = target.config;
    final url = target.decorateUrl(
      Uri.parse(
        '${config.endpoint}/models/${config.modelId}:streamGenerateContent?alt=sse',
      ),
    );
    logger?.call('Starting Google GenAI stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareGooglePayload(
      history,
      options,
      config.endpoint,
      tools: tools,
      emitsImages: target.model.capabilities.isImageGenerator,
      modelId: config.modelId,
      // Layer 3 says which field generation; the config says how hard.
      thinking: target.model.geminiThinking,
      reasoningEffort: config.effectiveReasoningEffort,
      outputCap: outputCapFor(target, options),
    );
    logger?.call(
      'Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}',
      level: 'DEBUG',
    );

    final request = buildJsonRequest('POST', url,
        headers: headers, body: jsonEncode(payload), options: options);

    final client = config.createClient();
    LLMDebugLog? debugFile;
    if (LLMDebugLogger.enabled) {
      debugFile = await LLMDebugLogger.startLog(
        config.modelId,
        'GoogleGenAI (Stream)',
        {'url': redactUrl(url), 'headers': headers, 'body': payload},
      );
    }

    final http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (_) {
      client.close();
      rethrow;
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
          debugFile,
          'Error Status: ${response.statusCode}',
        );
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
        await LLMDebugLogger.finish(debugFile);
      }
      client.close();
      logger?.call(
        'Stream request failed with status: ${response.statusCode}',
        level: 'ERROR',
      );
      // The shared decoder owns the message shape (provider error text when
      // the body is JSON, excerpt otherwise) and always throws on non-2xx.
      decodeJsonBody(
        // The request rides along so the message names the URL it failed on.
        // Headers too, so a 429's Retry-After reaches the retry loop.
        http.Response(body, response.statusCode,
            request: response.request, headers: response.headers),
        apiName: 'Google GenAI stream',
      );
      throw LLMApiException(
        'Google GenAI stream request failed: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    logger?.call(
      'Stream connection established, waiting for chunks...',
      level: 'DEBUG',
    );

    // Whether a single protocol-shaped chunk arrived — see the guard after
    // the loop.
    var sawChunk = false;
    // Whether any of them carried output, and the finish they ended on —
    // see [geminiEmptyEndFailure].
    var sawOutput = false;
    Map<String, dynamic>? lastMetadata;
    // One id generator for the whole stream: ③ sends each functionCall whole
    // in its own chunk, and ids restarted per chunk used to collide.
    final callIds = GeminiToolCallIds();
    // The turn's parts across every chunk, for verbatim replay.
    final modelParts = GeminiModelPartsCollector();

    try {
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
          debugFile,
          'Status: ${response.statusCode}',
        );
      }
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.isEmpty) continue;

        if (debugFile != null) {
          await LLMDebugLogger.appendStreamLine(debugFile, line);
        }

        for (final chunk in geminiChunksFromSseLine(
          line,
          logger: logger,
          callIds: callIds,
          modelParts: modelParts,
        )) {
          sawChunk = true;
          if (chunk.textPart != null ||
              chunk.reasoningPart != null ||
              chunk.imagePart != null ||
              chunk.toolCallPart != null) {
            sawOutput = true;
          }
          // Merged: a trailing usage-only chunk must not drop the finish.
          if (chunk.metadata != null) {
            lastMetadata = {...?lastMetadata, ...chunk.metadata!};
          }
          yield chunk;
        }
      }
    } finally {
      client.close();
      // In the finally so a stream that failed mid-flight still records how
      // long it ran before it did.
      await LLMDebugLogger.finish(debugFile);
    }

    // The guard ① (`sawChunk`), ④ (`sawMessage`) and DashScope (`sawFrame`)
    // already had: a 200 whose body is an HTML page, or nothing but
    // keep-alives, decodes to no chunk and used to end as a successful empty
    // reply (pitfalls 11 §A6).
    if (!sawChunk) {
      throw LLMApiException(
        'Google GenAI stream (${redactUrl(url)}) ended without a single '
        'chunk — the base URL may point at something that is not this API, '
        'or the relay answered with an empty stream.',
        isNonJsonBody: true,
      );
    }

    final emptyEnd = geminiEmptyEndFailure(lastMetadata, sawOutput: sawOutput);
    if (emptyEnd != null) throw emptyEnd;

    // Once, whole, at the end — the same arrangement as ④'s raw blocks.
    final rawParts = modelParts.toolTurnParts;
    if (rawParts != null) {
      yield LLMResponseChunk(rawModelParts: rawParts);
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
///
/// [callIds] is the stream's shared id generator — see [GeminiToolCallIds].
@visibleForTesting
Iterable<LLMResponseChunk> geminiChunksFromSseLine(
  String line, {
  LLMLogger? logger,
  GeminiToolCallIds? callIds,
  GeminiModelPartsCollector? modelParts,
}) {
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

  // Fed here, eagerly, rather than inside the lazy parser below: the stream's
  // parts are collected in arrival order whether or not a consumer drains
  // every chunk ([GeminiModelPartsCollector]).
  modelParts?.feed(chunkData);
  return parseGoogleChunks(chunkData, logger: logger, callIds: callIds);
}

/// Gemini `GET /models` discovery listing.
class GeminiDiscoveryProtocol implements DiscoveryProtocol {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMTarget target) async {
    final config = target.config;
    final baseUrl = trimBaseUrl(config.endpoint);

    final url = target.decorateUrl(Uri.parse('$baseUrl/models'));
    final headers = target.headers();

    final client = config.createClient();
    try {
      final response = await client.get(url, headers: headers);
      final data = decodeJsonBody(response, apiName: 'Gemini models');
      final rawModels = data['models'];
      final List<dynamic> modelsJson = rawModels is List ? rawModels : const [];

      return modelsJson.whereType<Map>().map((m) {
        final id =
            m['name']?.toString().replaceFirst('models/', '').trim() ?? '';
        if (id.isEmpty) return null;
        return DiscoveredModel(
          modelId: id,
          displayName: m['displayName']?.toString() ?? id,
          description: m['description']?.toString() ?? '',
          rawData: m.cast<String, dynamic>(),
        );
      }).whereType<DiscoveredModel>().toList();
    } finally {
      client.close();
    }
  }
}

/// The non-streaming generateContent address for [modelId] at base [base] —
/// shared with the channel editor's address preview.
String geminiGenerateUrl(String base, String modelId) =>
    '$base/models/$modelId:generateContent';
