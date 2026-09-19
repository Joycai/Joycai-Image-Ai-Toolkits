import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/safety_settings.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'chat_image_extraction.dart';
import 'inline_think.dart';
import 'openai_chat_parsing.dart';
import 'openai_chat_payload.dart';
import 'protocol.dart';
import 'streaming_tool_calls.dart';

/// OpenAI `POST /chat/completions` — JSON request, JSON or SSE response.
///
/// The base envelope is identical for every model. Gemini-family models
/// reached through an OpenAI-shaped vendor additionally receive the
/// Gemini-via-OpenAI compatibility extensions (`modalities`, `image_config`,
/// `safety_settings`) — flagged by [ModelDescriptor.isGeminiFamily], never
/// sniffed here. Native OpenAI models must never receive them (400).
class OpenAIChatProtocol implements ChatProtocol {
  @override
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    // Trimmed like every sibling protocol's base URL. [LLMModelConfig.endpoint]
    // already guarantees no trailing slash; this keeps the call sites uniform
    // so the next one copied from here cannot reintroduce `//chat/completions`.
    final url = Uri.parse(openaiChatUrl(config.endpoint));
    logger?.call('Preparing OpenAI request to: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareOpenAIChatPayload(
      target,
      history,
      options,
      isStreaming: false,
      tools: tools,
    );
    if (payload.containsKey('safety_settings')) {
      logger?.call(
        'Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}',
        level: 'DEBUG',
      );
    }

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (LLMDebugLogger.enabled) {
        debugFile = await LLMDebugLogger.startLog(
          config.modelId,
          'OpenAI (Standard)',
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
      // Status → JSON → shape → envelope, in that order (decodeJsonBody).
      final data = decodeJsonBody(response, apiName: 'OpenAI API');
      String text = '';
      final List<Uint8List> images = [];
      final List<LLMToolCall> toolCalls = [];
      String? reasoningContent;
      String? reasoningFieldName;

      final choice = firstChoice(data);
      final rawMessage = choice?['message'];
      final message = rawMessage is Map
          ? rawMessage.cast<String, dynamic>()
          : null;
      if (message == null) {
        // Previously this fell through to an empty LLMResponse, which callers
        // (the assistant loop above all) read as "the model chose to say
        // nothing" — an expired key looked like a silent no-op.
        final body = response.body;
        throw LLMApiException(
          'OpenAI API returned no choices: '
          '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
        );
      }
      {
        text = contentToText(message['content']);

        // ① family chain-of-thought: field-based (DeepSeek reasoning_content,
        // OpenRouter reasoning — no standard spelling exists, so probe the
        // known candidates and remember which one answered)...
        final picked = pickReasoningField(message);
        if (picked != null) {
          reasoningContent = picked.text;
          reasoningFieldName = picked.field;
        }
        // ...or inline <think> spans glued into content (MiniMax default).
        // Inline reasoning is display/accounting-only — it carries no echo
        // obligation, hence no field name. It is never merged into a native
        // field's text: that text is echoed back under the field's name, and
        // the inline span would ride along into a key the host reads as its
        // own (reasoning 03 §6 rule 3). With both present, the native one
        // is what the response carries.
        final inline = stripInlineThink(text);
        if (inline.reasoning != null) {
          text = inline.text;
          if (reasoningContent == null) {
            reasoningContent = inline.reasoning;
          } else {
            logger?.call(
              'Inline <think> reasoning (not echoed): ${inline.reasoning}',
              level: 'DEBUG',
            );
          }
        }

        // Native tool/function calls.
        final rawToolCalls = message['tool_calls'];
        if (rawToolCalls is List) {
          for (int i = 0; i < rawToolCalls.length; i++) {
            final tc = rawToolCalls[i];
            final fn = tc is Map ? tc['function'] : null;
            if (fn is! Map) continue;
            final args = decodeToolArguments(fn['arguments'], logger: logger);
            toolCalls.add(
              LLMToolCall(
                id: resolveToolCallId(tc['id'], i),
                name: fn['name']?.toString() ?? '',
                arguments: args,
              ),
            );
          }
          if (toolCalls.isNotEmpty) {
            logger?.call(
              'Model requested ${toolCalls.length} tool call(s).',
              level: 'DEBUG',
            );
          }
        }

        // Some OpenAI-compat relays expose images via a structured field —
        // sometimes the same picture in several of them at once, hence the
        // de-duplication across every source below.
        final dedupe = ImageDeduper();
        final structured = extractStructuredImages(message);
        images.addAll(dedupe.filter(structured.bytes));
        images.addAll(
          dedupe.filter(await _fetchImageUrls(structured.urls, config, logger,
              abortTrigger: abortTriggerOf(options))),
        );

        if (text.isNotEmpty) {
          logger?.call(
            'Extracting images from text response...',
            level: 'DEBUG',
          );
          final result = await _processTextAndExtractImages(
            text,
            config,
            imageReply: target.model.capabilities.isImageGenerator,
            logger: logger,
            abortTrigger: abortTriggerOf(options),
          );
          text = result.text;
          images.addAll(dedupe.filter(result.images));
        }
      }

      logger?.call(
        'Parse complete. Text length: ${text.length}, Images: ${images.length}',
        level: 'DEBUG',
      );

      final metadata = <String, dynamic>{
        ...?normalizeOpenAIUsage(data['usage']),
      };
      final finishReason = choice?['finish_reason'];
      if (finishReason != null) metadata['finish_reason'] = finishReason;

      // A message with nothing in it — no text, reasoning, tool calls or
      // images — is not "the model chose to say nothing" (pitfalls 11 §A6).
      // `length` and `content_filter` are real endings with their own
      // handling downstream, so they pass through — and so does the one
      // caller that declared an empty ending legitimate
      // ([emptyReplyEndsTurnKey]: an agent continuing after a tool result).
      if (text.isEmpty &&
          reasoningContent == null &&
          toolCalls.isEmpty &&
          images.isEmpty &&
          finishReason != 'length' &&
          finishReason != contentFilterFinishReason &&
          !_emptyReplyEndsTurn(options, logger)) {
        throw LLMApiException(
          'OpenAI API (${redactUrl(url)}) returned no content — no text, '
          'reasoning, tool calls or images '
          '(finish_reason: ${finishReason ?? 'none'}, '
          'usage: ${data['usage'] ?? 'none'}).',
        );
      }

      return LLMResponse(
        text: text,
        generatedImages: images,
        metadata: metadata,
        reasoningContent: reasoningContent,
        reasoningFieldName: reasoningFieldName,
        // The replay scope of the field — see the payload builder's echo rule.
        rawThinkingModelId: reasoningFieldName == null ? null : config.modelId,
        toolCalls: toolCalls,
      );
    } finally {
      client.close();
    }
  }

  /// True since [StreamingToolCallAccumulator] taught this surface to
  /// reassemble a call out of `delta.tool_calls[]` fragments, grouped by
  /// `index` rather than `id` (docs/api/tools.md §4).
  ///
  /// What it buys is not incremental display — an agent loop cannot act on
  /// half a batch — but the per-chunk idle guard: on the synchronous path
  /// nothing arrives until the last token, so the whole generation has to fit
  /// inside one deadline, and a 6–7 K-token answer did not
  /// (docs/plans/2026-08-assistant-timeout.md).
  @override
  bool get streamingDeclaresTools => true;

  /// Whether the caller declared an empty reply a legitimate end of turn
  /// (see [emptyReplyEndsTurnKey]). Logged, so a log that shows a 200 with
  /// nothing in it also shows why it was not failed.
  static bool _emptyReplyEndsTurn(
      Map<String, dynamic>? options, LLMLogger? logger) {
    if (options?[emptyReplyEndsTurnKey] != true) return false;
    logger?.call(
      'The reply carried no content; the caller declared that a legitimate '
      'end of turn, so it is delivered empty rather than failed.',
      level: 'DEBUG',
    );
    return true;
  }

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async* {
    final config = target.config;
    final url = Uri.parse(openaiChatUrl(config.endpoint));
    logger?.call('Starting OpenAI stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareOpenAIChatPayload(
      target,
      history,
      options,
      isStreaming: true,
      tools: tools,
    );
    if (payload.containsKey('safety_settings')) {
      logger?.call(
        'Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}',
        level: 'DEBUG',
      );
    }

    final request = buildJsonRequest('POST', url,
        headers: headers, body: jsonEncode(payload), options: options);

    final client = config.createClient();
    LLMDebugLog? debugFile;
    if (LLMDebugLogger.enabled) {
      debugFile = await LLMDebugLogger.startLog(
        config.modelId,
        'OpenAI (Stream)',
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
      // Read unconditionally, not just for the debug log: the body carries
      // the provider's actual complaint, and draining it also settles the
      // pooled client's transfer count the moment it happens rather than at
      // the handle's close.
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
          debugFile,
          'Error Status: ${response.statusCode}',
        );
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
        await LLMDebugLogger.finish(debugFile);
      }
      logger?.call(
        'Stream request failed with status: ${response.statusCode}',
        level: 'ERROR',
      );
      client.close();
      throw LLMApiException(
        'OpenAI API Stream Request failed: ${response.statusCode} '
        '(${redactUrl(url)}) - '
        '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
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

    final textGate = StreamedImageTextGate();
    // <think> tags arrive split across chunks; the filter reassembles them
    // and keeps the thinking out of the text channel.
    final thinkFilter = InlineThinkStreamFilter();
    // Usage and finish_reason arrive on different chunks (and, on some relays,
    // alongside content rather than on a choices-less tail chunk), so they are
    // collected here and emitted once at stream end — the consumer keeps the
    // last metadata it sees, so a single final chunk cannot be overwritten by
    // a later one carrying only half the picture.
    Map<String, dynamic>? usageMetadata;
    String? finishReason;
    // Fragments only become calls at stream end — ① has no per-call
    // terminator — so this holds them until the loop is over.
    final streamedToolCalls = StreamingToolCallAccumulator();
    // One copy of each picture, whichever field(s) it arrives in.
    final dedupe = ImageDeduper();
    // Whether a single protocol-shaped chunk arrived. A 200 whose body is an
    // HTML page, or a stream of nothing but keep-alives and `[DONE]`, decodes
    // to no chunk at all and used to end as a successful empty reply — the
    // synchronous path throws "returned no choices" for the same body.
    var sawChunk = false;
    // Whether any of those chunks carried something: text (base64 included),
    // reasoning, a tool-call fragment or an image. Separate from [sawChunk]
    // because a relay can stream well-formed chunks that hold nothing.
    var sawOutput = false;

    try {
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (debugFile != null && line.isNotEmpty) {
          await LLMDebugLogger.appendStreamLine(debugFile, line);
        }
        final dataLine = sseDataPayload(line);
        if (dataLine == null) continue;

        Map<String, dynamic>? chunkData;
        try {
          final decoded = jsonDecode(dataLine);
          if (decoded is Map<String, dynamic>) chunkData = decoded;
        } catch (_) {
          continue; // Non-JSON SSE noise.
        }
        if (chunkData == null) continue;
        sawChunk = true;

        // Deliberately outside the shape-tolerant try below: an in-body error
        // event must terminate the stream as a failure, not be swallowed as
        // a malformed chunk (streaming.md §3.1/§3.2).
        throwIfEnvelopeError(chunkData);

        // Same: usage is the whole point of the choices-less tail chunk, so it
        // is read before any parsing that is allowed to fail.
        final usage = chunkData['usage'];
        if (usage is Map) usageMetadata = normalizeOpenAIUsage(usage);

        final choice = firstChoice(chunkData);
        if (choice == null) continue;
        final rawFinish = choice['finish_reason'];
        if (rawFinish is String && rawFinish.isNotEmpty) {
          finishReason = rawFinish;
        }

        // Structured image fields, read outside the tolerant try for the same
        // reason as usage: on a relay that answers with `delta.images[]`
        // instead of a markdown data URI in the text, these *are* the reply.
        // Only `image_data` used to be read here, so those relays streamed
        // zero images and the task reported success with nothing in it.
        final rawDelta = choice['delta'];
        final delta = rawDelta is Map ? rawDelta.cast<String, dynamic>() : null;
        if (delta != null) {
          // Outside the tolerant try below for the same reason as usage: on a
          // tool-bearing request these fragments *are* the reply, and losing
          // one to a shape surprise elsewhere in the chunk would produce a
          // call with truncated arguments rather than a visible failure.
          final rawToolCalls = delta['tool_calls'];
          streamedToolCalls.feed(rawToolCalls);
          if (rawToolCalls is List && rawToolCalls.isNotEmpty) {
            sawOutput = true;
            // Keepalive. Fragments buffer silently until the flush after the
            // loop, but the consumer's idle guard resets only on chunks it
            // receives — a model answering with one long tool call and no
            // text would otherwise look like a dead connection at exactly
            // the moment it is delivering
            // (docs/plans/2026-08-assistant-timeout.md, the case streaming
            // tools exists to fix).
            yield LLMResponseChunk(
                toolArgumentChars: streamedToolCalls.argumentChars);
          }

          final structured = extractStructuredImages(delta);
          for (final img in dedupe.filter(structured.bytes)) {
            sawOutput = true;
            yield LLMResponseChunk(imagePart: img);
          }
          for (final img in dedupe.filter(
            await _fetchImageUrls(structured.urls, config, logger,
                abortTrigger: abortTriggerOf(options)),
          )) {
            sawOutput = true;
            yield LLMResponseChunk(imagePart: img);
          }
        }

        try {
          // Same shape tolerance as the sync path — a delta carrying a content
          // array would otherwise throw into the catch below and be dropped as
          // "parse noise", losing the reply one chunk at a time.
          final text = contentToText(delta?['content']);
          final picked = delta == null ? null : pickReasoningField(delta);

          if (picked != null) {
            sawOutput = true;
            // Dedicated channel: consumers that accumulate textPart into a
            // deliverable must never glue the thinking into it. The field
            // *name* rides along — same probe as the sync path — because a
            // tool-calling turn's replay must echo the reasoning under the
            // key it arrived with (reasoning.md §3), and the stream consumer
            // cannot recover the name from the text alone.
            yield LLMResponseChunk(
              reasoningPart: picked.text,
              reasoningFieldName: picked.field,
            );
          }

          if (text.isNotEmpty) {
            sawOutput = true;
            final split = thinkFilter.feed(text);
            if (split.reasoning.isNotEmpty) {
              yield LLMResponseChunk(reasoningPart: split.reasoning);
            }
            final shown = textGate.feed(split.text);
            if (shown.isNotEmpty) yield LLMResponseChunk(textPart: shown);
          }
        } catch (e) {
          // Ignore parse errors
        }
      }

      final tail = thinkFilter.flush();
      if (tail.reasoning.isNotEmpty) {
        yield LLMResponseChunk(reasoningPart: tail.reasoning);
      }
      final shownTail = textGate.feed(tail.text);
      if (shownTail.isNotEmpty) yield LLMResponseChunk(textPart: shownTail);

      if (textGate.text.isNotEmpty) {
        final result = await _processTextAndExtractImages(
          textGate.text,
          config,
          imageReply: target.model.capabilities.isImageGenerator,
          logger: logger,
          abortTrigger: abortTriggerOf(options),
        );
        final rest = textGate.finish(result.text);
        if (rest.isNotEmpty) yield LLMResponseChunk(textPart: rest);

        for (var img in dedupe.filter(result.images)) {
          yield LLMResponseChunk(imagePart: img);
        }
      }
    } finally {
      client.close();
      // In the finally so a stream that failed mid-flight still records how
      // long it ran before it did.
      await LLMDebugLogger.finish(debugFile);
    }

    if (!sawChunk) {
      throw LLMApiException(
        'OpenAI API stream ended without a single chunk — the base URL may '
        'point at something that is not this API, or the relay answered '
        'with an empty stream.',
        isNonJsonBody: true,
      );
    }

    // Chunks arrived, but nothing in them: no text, no reasoning, no tool
    // call, no image. A 200 like that used to end as a successful empty
    // reply (pitfalls 11 §A6). `length` and `content_filter` are exempt —
    // those are real endings with their own handling downstream (the
    // truncation warning, [contentBlockedFailure]).
    if (!sawOutput &&
        finishReason != 'length' &&
        finishReason != contentFilterFinishReason &&
        !_emptyReplyEndsTurn(options, logger)) {
      throw LLMApiException(
        'OpenAI API stream (${redactUrl(url)}) returned no content — no '
        'text, reasoning, tool calls or images '
        '(finish_reason: ${finishReason ?? 'none'}, '
        'usage: ${usageMetadata ?? 'none'}).',
      );
    }

    // A stream that closes cleanly without ever sending a finish_reason was
    // cut off: every ① host sends one on the last choice chunk. With tool
    // fragments pending that is a hard failure — [flush] would decode the
    // cut-off arguments to `{}` with a WARN and the agent loop would execute
    // the call. Text alone is delivered, marked `length` (the one truncation
    // signal every caller already honours) and flagged `stream_incomplete`.
    var streamIncomplete = false;
    if (finishReason == null) {
      if (!streamedToolCalls.isEmpty) {
        throw LLMApiException(
          'OpenAI API stream (${redactUrl(url)}) closed without a '
          'finish_reason while tool call arguments were still arriving — '
          'the stream was truncated, and a call with cut-off arguments must '
          'not be executed.',
        );
      }
      logger?.call(
        'The stream closed without a finish_reason — the reply was probably '
        'cut off in transit. Treating it as truncated.',
        level: 'WARN',
      );
      finishReason = 'length';
      streamIncomplete = true;
    }

    // After the loop, never inside it: a call is whole only once the last
    // fragment has arrived, and [LLMResponseChunk.toolCallPart] promises
    // consumers they can act on whatever reaches them. Deliberately outside
    // the `finally` too — a stream that died mid-arguments must fail, not
    // deliver a half-built call.
    final assembled = streamedToolCalls.flush(logger: logger);
    if (assembled.isNotEmpty) {
      logger?.call(
        'Model requested ${assembled.length} tool call(s).',
        level: 'DEBUG',
      );
    }
    for (final call in assembled) {
      yield LLMResponseChunk(toolCallPart: call);
    }

    // Last, so it wins over any metadata attached to an earlier chunk. Without
    // it a streamed request recorded no token usage at all — the sync path's
    // `usage` + `finish_reason` are reported here in the same shape.
    //
    // Unconditional: llama.cpp, LM Studio and many relays send no usage
    // block at all, and gating this chunk on usage meant `length` and
    // `content_filter` never reached the truncation warning or the
    // content-block check on exactly those hosts. A finish reason is always
    // known by now — a stream that sent none was resolved above.
    yield LLMResponseChunk(
      metadata: {
        ...?usageMetadata,
        'finish_reason': finishReason,
        if (streamIncomplete) 'stream_incomplete': true,
      },
    );

    yield LLMResponseChunk(isDone: true);
  }

  /// Downloads images a relay returned by reference rather than by value.
  ///
  /// Through the shared [resolveImageRefs]: the bytes must be an image (a
  /// relay's `200` + HTML page for an expired link used to be kept as a
  /// picture), a link gets one retry, and a partial result is warned about.
  /// A failed fetch is still skipped — one dead link must not lose the images
  /// that did arrive.
  Future<List<Uint8List>> _fetchImageUrls(
    List<String> urls,
    LLMModelConfig config,
    LLMLogger? logger, {
    Future<void>? abortTrigger,
  }) async {
    if (urls.isEmpty) return const [];
    final client = config.createClient();
    try {
      return await resolveImageRefs(urls, client, logger,
          source: 'OpenAI chat image links', abortTrigger: abortTrigger);
    } finally {
      client.close();
    }
  }

  Future<_TextProcessResult> _processTextAndExtractImages(
    String text,
    LLMModelConfig config, {
    required bool imageReply,
    LLMLogger? logger,
    Future<void>? abortTrigger,
  }) async {
    final client = config.createClient();
    try {
      final result = await extractTextImages(text, client,
          imageReply: imageReply,
          logger: logger,
          abortTrigger: abortTrigger);
      return _TextProcessResult(result.text, result.images);
    } finally {
      client.close();
    }
  }

  /// Images carried by a chat reply's *text*, and the text left over.
  ///
  /// Both link spellings — the whole reply being one link, and links inside
  /// markdown / Google storage URLs ([imageUrlsInText]) — are fetched through
  /// the shared [resolveImageRef] / [resolveImageRefs]: the bytes must be an
  /// image, a link gets one retry, and a failure is logged instead of the old
  /// silent `/* ignore */` (a text link answered with an HTML page used to be
  /// kept as a picture). Inline `data:` payloads are decoded as before.
  ///
  /// Static and handed its [client] so it can be pinned without a socket.
  @visibleForTesting
  static Future<({String text, List<Uint8List> images})> extractTextImages(
    String text,
    http.Client client, {
    required bool imageReply,
    LLMLogger? logger,
    Duration retryDelay = const Duration(seconds: 1),
    Future<void>? abortTrigger,
  }) async {
    final List<Uint8List> images = [];
    String cleanText = text;

    // 0. The whole reply *is* the image: bare base64, or (for an image
    //    model) a bare link. Both are relay shapes with no markdown and no
    //    `data:` prefix, which the two scans below cannot see.
    final whole = wholeContentImage(text, imageReply: imageReply);
    if (whole != null) {
      if (whole.bytes != null) {
        images.add(whole.bytes!);
      } else if (whole.url != null) {
        final bytes = await resolveImageRef(whole.url!, client, logger,
            retryDelay: retryDelay, abortTrigger: abortTrigger);
        if (bytes != null) images.add(bytes);
      }
      if (images.isNotEmpty) return (text: '', images: images);
    }

    // 1. Extract and remove Inline Base64
    final base64Regex = RegExp(r'data:image/[^;]+;base64,([a-zA-Z0-9+/=]+)');
    final b64Matches = base64Regex.allMatches(text);
    for (var match in b64Matches) {
      try {
        images.add(base64Decode(match.group(1)!));
        cleanText = cleanText.replaceFirst(match.group(0)!, '[Image Data]');
      } catch (e) {
        /* ignore */
      }
    }

    // 2. Fetch images the text points at rather than embeds.
    images.addAll(await resolveImageRefs(imageUrlsInText(text), client, logger,
        source: 'OpenAI chat reply links',
        retryDelay: retryDelay,
        abortTrigger: abortTrigger));

    return (text: cleanText.trim(), images: images);
  }

  /// Exposes the payload builder to tests — request-shape rules (reasoning
  /// echo-back, tool nesting, image parts) are pinned in
  /// `test/openai_chat_payload_test.dart`.
  @visibleForTesting
  Map<String, dynamic> buildChatPayloadForTest(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    required bool isStreaming,
    List<LLMTool>? tools,
  }) => prepareOpenAIChatPayload(
    target,
    history,
    options,
    isStreaming: isStreaming,
    tools: tools,
  );
}

/// Decides which streamed reply text reaches the consumer while an inline
/// image may be arriving as text (`data:image/…;base64,…`, or bare base64).
///
/// Text is shown as it arrives until something looks like image data; from
/// then on it is held back, and [finish] hands over only what the image
/// extraction left that was not already shown. The gate it replaces dropped
/// a suspicious chunk for good, and at stream end re-yielded the *whole*
/// cleaned text once it had flipped — so every character shown before the
/// flip appeared twice, and text after an inline image was lost whenever the
/// leftover was under a tenth of the raw length.
@visibleForTesting
class StreamedImageTextGate {
  final StringBuffer _all = StringBuffer();
  final StringBuffer _shown = StringBuffer();
  bool _holding = false;

  /// Everything fed so far — what image extraction runs over.
  String get text => _all.toString();

  /// Feeds one piece of reply text; returns the part to show now.
  String feed(String piece) {
    if (piece.isEmpty) return '';
    _all.write(piece);
    if (!_holding &&
        (looksLikeImageData(piece) ||
            (_all.length > 500 && looksLikeImageData(text)))) {
      _holding = true;
    }
    if (_holding) return '';
    _shown.write(piece);
    return piece;
  }

  /// Given the text left after image extraction, returns what still has to
  /// be shown: the part past what [feed] already showed. Nothing when the
  /// gate never held back, or when the remainder is itself image data.
  String finish(String cleaned) {
    if (!_holding) return '';
    final shown = _shown.toString().trimLeft();
    var common = 0;
    final limit = math.min(shown.length, cleaned.length);
    while (common < limit &&
        shown.codeUnitAt(common) == cleaned.codeUnitAt(common)) {
      common++;
    }
    final rest = cleaned.substring(common);
    if (rest.trim().isEmpty || looksLikeImageData(rest)) return '';
    return rest;
  }

  /// A `data:image/` payload, or a long run of base64 with no spaces.
  static bool looksLikeImageData(String text) {
    if (text.length < 64) return false;
    if (text.contains('data:image/')) return true;
    return text.length > 200 &&
        !text.contains(' ') &&
        RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(text.substring(0, 100));
  }
}

class _TextProcessResult {
  final String text;
  final List<Uint8List> images;
  _TextProcessResult(this.text, this.images);
}

/// OpenAI `GET /models` discovery listing.
class OpenAIDiscoveryProtocol implements DiscoveryProtocol {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMTarget target) async {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/models');
    final headers = target.headers();

    // Use the configured client so discovery honors the same proxy and
    // connection pool as generation.
    final client = config.createClient();
    try {
      final response = await client.get(url, headers: headers);
      final data = decodeJsonBody(response, apiName: 'OpenAI models');
      final rawModels = data['data'];
      final List<dynamic> modelsJson = rawModels is List ? rawModels : const [];

      return modelsJson.whereType<Map>().map((m) {
        final id = m['id']?.toString().trim() ?? '';
        if (id.isEmpty) return null;
        return DiscoveredModel(
          modelId: id,
          displayName: id,
          description: 'Owned by: ${m['owned_by'] ?? 'unknown'}',
          rawData: m.cast<String, dynamic>(),
        );
      }).whereType<DiscoveredModel>().toList();
    } finally {
      client.close();
    }
  }
}

/// The Chat Completions request address for base [base] — the one spelling
/// the requests above and the channel editor's address preview share.
String openaiChatUrl(String base) => '${trimBaseUrl(base)}/chat/completions';
