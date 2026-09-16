import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm_debug_logger.dart';
import '../llm_types.dart';
import '../vendors/vendor_profile.dart';
import 'anthropic_payload.dart';
import 'anthropic_response.dart';
import 'anthropic_stream.dart';
import 'anthropic_thinking.dart';
import 'anthropic_wire.dart';
import 'protocol.dart';

/// Anthropic `POST /messages` — JSON request, JSON or typed-SSE response.
///
/// Served by Anthropic's own host and by the relays that expose the format
/// natively (New API, MiniMax). Everything vendor-specific about them is
/// authentication, which comes from the vendor profile; there is no branch on
/// a vendor id here.
class AnthropicChatProtocol implements ChatProtocol {
  /// Whether a failed first attempt is worth one more with the other thinking
  /// spelling: the API refused the thinking *shape*, and the request actually
  /// carried one (a request without a thinking field has nothing to respell).
  /// On success the learned dialect is remembered for this endpoint + model.
  ThinkingDialect? _retryDialectFor(
    LLMTarget target,
    ThinkingDialect sent,
    Object error,
    Map<String, dynamic>? options,
    LLMLogger? logger,
  ) {
    if (!isAnthropicThinkingRejection(error)) return null;
    final carried = anthropicThinkingRequest(
      sent,
      effort: target.config.effectiveReasoningEffort,
      maxTokens: anthropicMaxTokens(options),
    );
    if (carried == null) return null;
    final alternate = learnAnthropicThinkingDialect(target, sent);
    if (alternate == null) return null;
    logger?.call(
      'The endpoint rejected the ${sent.name} thinking spelling for '
      '${target.config.modelId}; retrying once with ${alternate.name} and '
      'remembering it for this channel.',
      level: 'WARN',
    );
    return alternate;
  }

  @override
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async {
    final dialect = resolveAnthropicThinkingDialect(target);
    try {
      return await _generateOnce(
        target,
        history,
        options: options,
        tools: tools,
        logger: logger,
        dialect: dialect,
      );
    } catch (e) {
      final retry = _retryDialectFor(target, dialect, e, options, logger);
      if (retry == null) rethrow;
      return _generateOnce(
        target,
        history,
        options: options,
        tools: tools,
        logger: logger,
        dialect: retry,
      );
    }
  }

  Future<LLMResponse> _generateOnce(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
    required ThinkingDialect dialect,
  }) async {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/messages');
    logger?.call('Preparing Anthropic request to: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareAnthropicPayload(
      target,
      history,
      options: options,
      tools: tools,
      isStreaming: false,
      dialect: dialect,
    );

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(
          config.modelId,
          'Anthropic (Standard)',
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

      logger?.call('Response received, parsing data...', level: 'DEBUG');
      // Status → JSON → shape → envelope, in that order (decodeJsonBody). ④
      // delivers errors as `{"type":"error","error":{…}}`, which the shared
      // envelope check recognizes by its `error` field — and a relay can
      // serve one behind a 200.
      final data = decodeJsonBody(response, apiName: 'Anthropic API');

      final rawContent = data['content'];
      if (rawContent is! List || rawContent.isEmpty) {
        // Same rule the other two families now follow: a body carrying no
        // content is a failed request, not a model that chose to say nothing.
        final body = response.body;
        throw Exception(
          'Anthropic API returned no content: '
          '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
        );
      }

      final content = parseAnthropicContent(rawContent);
      if (content.toolCalls.isNotEmpty) {
        logger?.call(
          'Model requested ${content.toolCalls.length} tool call(s).',
          level: 'DEBUG',
        );
      }
      for (final run in content.serverToolRuns) {
        logAnthropicServerToolRun(run, logger);
      }
      if (content.turnIncomplete) {
        logger?.call(
          'The turn ended on a search result with no answer after it — the '
          'host did not call the model back. The request will be continued.',
          level: 'WARN',
        );
      }
      logger?.call(
        'Parse complete. Text length: ${content.text.length}, Tool calls: ${content.toolCalls.length}',
        level: 'DEBUG',
      );

      return LLMResponse(
        text: content.text,
        metadata: anthropicUsageMetadata(
          (data['usage'] as Map?)?.cast<String, dynamic>(),
          stopReason: data['stop_reason']?.toString(),
          serverToolRuns: content.serverToolRuns,
          turnIncomplete: content.turnIncomplete,
        ),
        rawContentBlocks: content.rawContentBlocks.isEmpty
            ? null
            : content.rawContentBlocks,
        reasoningContent: content.thinking,
        // Deliberately no field *name*: ④'s echo-back obligation is not a
        // field on the message but the whole thinking block, verified by its
        // signature (see [LLMMessage.reasoningSignature]). Leaving the name
        // null is what keeps the ① payload builder from inventing a key for
        // it if this history is ever replayed against an ① endpoint.
        reasoningSignature: content.thinkingSignature,
        rawThinkingBlocks: content.rawThinkingBlocks.isEmpty
            ? null
            : content.rawThinkingBlocks,
        rawThinkingModelId:
            content.rawThinkingBlocks.isEmpty &&
                content.rawContentBlocks.isEmpty
            ? null
            : config.modelId,
        toolCalls: content.toolCalls,
      );
    } finally {
      client.close();
    }
  }

  /// ④ is the family whose streamed tool calls are cheapest to assemble: the
  /// id and name arrive whole on `content_block_start`, and only the
  /// arguments are fragmented, keyed by a content-block index that is
  /// explicit in every event.
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
    final dialect = resolveAnthropicThinkingDialect(target);
    ThinkingDialect? retry;
    try {
      yield* _streamOnce(
        target,
        history,
        options: options,
        tools: tools,
        logger: logger,
        dialect: dialect,
      );
      return;
    } catch (e) {
      // Only a 400 on the opening response qualifies (see
      // [isAnthropicThinkingRejection]), and that arrives before any chunk
      // has been yielded — so retrying cannot duplicate delivered output.
      retry = _retryDialectFor(target, dialect, e, options, logger);
      if (retry == null) rethrow;
    }
    yield* _streamOnce(
      target,
      history,
      options: options,
      tools: tools,
      logger: logger,
      dialect: retry,
    );
  }

  Stream<LLMResponseChunk> _streamOnce(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
    required ThinkingDialect dialect,
  }) async* {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/messages');
    logger?.call('Starting Anthropic stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareAnthropicPayload(
      target,
      history,
      options: options,
      tools: tools,
      isStreaming: true,
      dialect: dialect,
    );

    final request = buildJsonRequest('POST', url,
        headers: headers, body: jsonEncode(payload), options: options);

    final client = config.createClient();
    LLMDebugLog? debugFile;
    if (LLMDebugLogger.enabled) {
      debugFile = await LLMDebugLogger.startLog(
        config.modelId,
        'Anthropic (Stream)',
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
      throw LLMApiException(
        'Anthropic API Stream Request failed: ${response.statusCode} - $body',
        statusCode: response.statusCode,
        retryAfter: parseRetryAfter(response.headers),
      );
    }

    logger?.call(
      'Stream connection established, waiting for chunks...',
      level: 'DEBUG',
    );
    if (debugFile != null) {
      await LLMDebugLogger.appendLine(
        debugFile,
        'Status: ${response.statusCode}',
      );
    }

    final assembler = AnthropicStreamAssembler(logger: logger);

    try {
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (debugFile != null && line.isNotEmpty) {
          await LLMDebugLogger.appendStreamLine(debugFile, line);
        }
        // ④ is a *named*-event stream: every payload line is preceded by an
        // `event:` line naming the same type the JSON repeats in its `type`
        // field. The name is redundant here — but it is not JSON, so it has
        // to be stepped over rather than handed to the decoder.
        if (line.startsWith('event:') ||
            line.startsWith('id:') ||
            line.startsWith('retry:')) {
          continue;
        }
        final dataLine = sseDataPayload(line);
        if (dataLine == null) continue;

        Map<String, dynamic>? event;
        try {
          final decoded = jsonDecode(dataLine);
          if (decoded is Map<String, dynamic>) event = decoded;
        } catch (_) {
          continue; // Non-JSON SSE noise.
        }
        if (event == null) continue;

        // An `error` event mid-stream (overloaded_error, rate limits) must
        // fail the request rather than end it early with a partial answer.
        throwIfEnvelopeError(event);

        // Iterable, not Stream: the assembler is synchronous, so its
        // output is re-yielded one at a time rather than with yield*.
        for (final chunk in assembler.accept(event)) {
          yield chunk;
        }
      }
    } finally {
      client.close();
      // In the finally so a stream that failed mid-flight still records how
      // long it ran before it did.
      await LLMDebugLogger.finish(debugFile);
    }

    if (!assembler.sawMessage) {
      throw LLMApiException(
        'Anthropic API stream ended without a message — the base URL may '
        'point at something that is not this API, or the relay answered '
        'with an empty stream.',
        isNonJsonBody: true,
      );
    }

    final closing = assembler.finish();
    if (closing != null) yield closing;

    yield LLMResponseChunk(isDone: true);
  }
}

/// Anthropic `GET /models` discovery listing.
class AnthropicDiscoveryProtocol implements DiscoveryProtocol {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMTarget target) async {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/models');
    final headers = target.headers();

    final client = config.createClient();
    try {
      final response = await client.get(url, headers: headers);
      final data = decodeJsonBody(response, apiName: 'Anthropic models');
      final rawModels = data['data'];
      final List<dynamic> modelsJson = rawModels is List ? rawModels : const [];

      return modelsJson.whereType<Map>().map((m) {
        final id = m['id']?.toString().trim() ?? '';
        if (id.isEmpty) return null;
        return DiscoveredModel(
          modelId: id,
          displayName: m['display_name']?.toString() ?? id,
          description: m['created_at']?.toString() ?? '',
          rawData: m.cast<String, dynamic>(),
        );
      }).whereType<DiscoveredModel>().toList();
    } finally {
      client.close();
    }
  }
}
