import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../image_compression.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'dashscope_payload.dart';
import 'openai_chat_protocol.dart'
    show
        StreamingToolCallAccumulator,
        contentToText,
        decodeToolArguments,
        resolveToolCallId;
import 'protocol.dart';

/// The header that turns a DashScope-native request into an SSE stream.
///
/// Header-only on the HTTP surface: `parameters.stream` is an SDK-level
/// concept and is deliberately not sent. Omitting this header is the failure
/// mode worth knowing about — the request succeeds and answers as one
/// ordinary JSON body, so a client that assumed it was streaming waits for a
/// stream that never arrives instead of seeing an error.
const String _dashscopeSseHeader = 'X-DashScope-SSE';

/// Alibaba DashScope's **native** chat surface (protocol C2 in
/// `docs/api/qianwen-bailian.md`):
///
///  * `POST /api/v1/services/aigc/text-generation/generation` — text models;
///  * `POST /api/v1/services/aigc/multimodal-generation/generation` — VL /
///    omni / audio models, and any request carrying an attachment.
///
/// Not the OpenAI-compatible face, and not reachable through one. Three
/// things differ on the wire and every one of them is silent when got wrong:
/// the body is DashScope's three-section `{model, input, parameters}` rather
/// than a flat one; the reply is nested under `output` rather than at the top
/// level; and `parameters.result_format` defaults to `"text"`, which answers
/// with a bare string and no `choices` at all — no error, just a response
/// this parser would read as empty. `"message"` is therefore always sent.
///
/// Why a channel would choose this face over the compatible one: `qwen-audio`
/// is served here and nowhere else, and the native surface is where DashScope
/// ships parameters first. It is not a superset, though — `Qwen-Omni`'s audio
/// *output* runs on the compatible face alone — which is why the face stays a
/// per-model choice rather than a channel-wide one.
class DashScopeChatProtocol implements ChatProtocol {
  @override
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final multimodal = dashscopeChatIsMultimodal(target);
    _warnIfAttachmentsDropped(target, history, multimodal, logger);
    final url = Uri.parse(dashscopeChatUrl(config.endpoint, multimodal));
    logger?.call('Preparing DashScope native chat request to: ${url.host}',
        level: 'DEBUG');

    final headers = target.headers();
    final payload = buildDashScopeChatPayload(
      target,
      history,
      tools: tools,
      multimodal: multimodal,
      isStreaming: false,
    );

    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (AppState().enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(
            config.modelId, 'DashScope (Native Chat)', {
          'url': redactUrl(url),
          'headers': headers,
          'body': dashscopePayloadForLog(
              payload, dashscopeAttachmentCount(history)),
        });
      }

      final response =
          await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
            debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
        await LLMDebugLogger.finish(debugFile);
      }

      // Status → JSON → shape, then DashScope's own envelope: the shared
      // check knows OpenAI's `{"error": …}` and MiniMax's `base_resp`, and
      // DashScope uses neither — its failures are a top-level non-empty
      // `code` (dashscope_payload.dart).
      final data =
          decodeJsonBody(response, apiName: 'DashScope Chat API');
      throwIfDashScopeError(data);

      final message = dashscopeChatMessage(data);
      if (message == null) {
        // An empty LLMResponse here reads to every caller as "the model chose
        // to say nothing", which is how a `result_format` mistake or an
        // expired key would look like a silent no-op.
        final body = response.body;
        throw Exception('DashScope Chat API returned no choices: '
            '${body.length > 500 ? '${body.substring(0, 500)}…' : body}');
      }

      final text = contentToText(message['content']);
      final rawReasoning = message['reasoning_content'];
      final reasoning =
          rawReasoning is String && rawReasoning.isNotEmpty ? rawReasoning : null;

      final toolCalls = dashscopeToolCalls(message, logger);
      if (toolCalls.isNotEmpty) {
        logger?.call('Model requested ${toolCalls.length} tool call(s).',
            level: 'DEBUG');
      }

      logger?.call('DashScope parse complete. Text length: ${text.length}',
          level: 'DEBUG');

      return LLMResponse(
        text: text,
        metadata: dashscopeChatMetadata(data),
        reasoningContent: reasoning,
        // Echoed back under the name it arrived with, exactly as on the ①
        // face — the native surface uses the same `reasoning_content`
        // spelling and the same replay obligation for tool-calling turns.
        reasoningFieldName: reasoning == null ? null : 'reasoning_content',
        toolCalls: toolCalls,
      );
    } finally {
      client.close();
    }
  }

  /// True on the same [StreamingToolCallAccumulator] that taught the ① face
  /// to reassemble a call out of fragments — C2 carries `tool_calls` in the
  /// ①-shaped spelling, so one accumulator serves both.
  ///
  /// The wrinkle this face adds is that its frames are deltas only where
  /// `incremental_output` was honoured; refused, or re-assembled by an
  /// intermediary, they repeat the whole call every time. The accumulator
  /// merges rather than appends for exactly that reason — the same trade
  /// [DashScopeStreamChannel] already makes for text.
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
    final multimodal = dashscopeChatIsMultimodal(target);
    _warnIfAttachmentsDropped(target, history, multimodal, logger);
    final url = Uri.parse(dashscopeChatUrl(config.endpoint, multimodal));
    logger?.call('Starting DashScope native chat stream: ${url.host}',
        level: 'DEBUG');

    final headers = {
      ...target.headers(),
      _dashscopeSseHeader: 'enable',
    };
    final payload = buildDashScopeChatPayload(
      target,
      history,
      tools: tools,
      multimodal: multimodal,
      isStreaming: true,
    );

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    LLMDebugLog? debugFile;
    if (AppState().enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(
          config.modelId, 'DashScope (Native Chat Stream)', {
        'url': redactUrl(url),
        'headers': headers,
        'body':
            dashscopePayloadForLog(payload, dashscopeAttachmentCount(history)),
      });
    }

    final response = await client.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
            debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
        await LLMDebugLogger.finish(debugFile);
      }
      logger?.call('Stream request failed with status: ${response.statusCode}',
          level: 'ERROR');
      client.close();
      throw LLMApiException(
          'DashScope Chat API stream request failed: ${response.statusCode} - '
          '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
          statusCode: response.statusCode);
    }

    if (debugFile != null) {
      await LLMDebugLogger.appendLine(
          debugFile, 'Status: ${response.statusCode}');
    }

    // Everything emitted so far on each channel. `incremental_output: true`
    // is requested, so frames should already be deltas — but the parameter
    // can be refused, and an intermediary can re-assemble frames, and a
    // cumulative stream fed to a consumer that appends replays the whole
    // answer on every frame. [_emit] tells the two apart against these.
    final text = DashScopeStreamChannel();
    final reasoning = DashScopeStreamChannel();
    // The third channel, and the one that cannot emit as it goes: a call is
    // whole only once its last fragment has arrived.
    final streamedToolCalls = StreamingToolCallAccumulator();
    Map<String, dynamic>? usageMetadata;
    String? finishReason;

    try {
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (debugFile != null && line.isNotEmpty) {
          await LLMDebugLogger.appendStreamLine(debugFile, line);
        }
        // DashScope frames carry `id:` and `event:` lines beside the payload.
        // They are not JSON and the shared helper passes unprefixed lines
        // through untouched, so they are dropped here rather than left to
        // fail a decode.
        if (line.startsWith('id:') || line.startsWith('event:')) continue;
        final dataLine = sseDataPayload(line);
        if (dataLine == null) continue;

        Map<String, dynamic>? frame;
        try {
          final decoded = jsonDecode(dataLine);
          if (decoded is Map<String, dynamic>) frame = decoded;
        } catch (_) {
          continue; // Non-JSON SSE noise.
        }
        if (frame == null) continue;

        // Outside the tolerant parsing below: an error frame must end the
        // stream as a failure, not be swallowed as a malformed one.
        throwIfDashScopeError(frame);

        final usage = frame['usage'];
        if (usage is Map) usageMetadata = usage.cast<String, dynamic>();
        final reason = dashscopeFinishReason(frame);
        if (reason != null) finishReason = reason;

        final message = dashscopeChatMessage(frame);
        if (message == null) continue;

        final rawToolCalls = message['tool_calls'];
        streamedToolCalls.feed(rawToolCalls);
        if (rawToolCalls is List && rawToolCalls.isNotEmpty) {
          // Keepalive, same as ①: fragments buffer silently until the flush
          // after the loop, but the consumer's idle guard resets only on
          // chunks it receives — a long tool-call-only answer would
          // otherwise time out mid-delivery and be re-sent.
          yield LLMResponseChunk();
        }

        final rawReasoning = message['reasoning_content'];
        if (rawReasoning is String && rawReasoning.isNotEmpty) {
          // Its own channel: a consumer that accumulates textPart into a
          // deliverable must never get the thinking glued into it. The field
          // name rides along for the replay obligation, matching the sync
          // path — the native face uses the same `reasoning_content` key as
          // the ① compatible face.
          final delta = reasoning.feed(rawReasoning);
          if (delta.isNotEmpty) {
            yield LLMResponseChunk(
              reasoningPart: delta,
              reasoningFieldName: 'reasoning_content',
            );
          }
        }

        final rawText = contentToText(message['content']);
        if (rawText.isNotEmpty) {
          final delta = text.feed(rawText);
          if (delta.isNotEmpty) yield LLMResponseChunk(textPart: delta);
        }
      }
    } finally {
      client.close();
      await LLMDebugLogger.finish(debugFile);
    }

    // Outside the `finally`: a stream that died mid-arguments must fail
    // rather than hand over a half-built call.
    final assembled = streamedToolCalls.flush(logger: logger);
    if (assembled.isNotEmpty) {
      logger?.call('Model requested ${assembled.length} tool call(s).',
          level: 'DEBUG');
    }
    for (final call in assembled) {
      yield LLMResponseChunk(toolCallPart: call);
    }

    if (usageMetadata != null || finishReason != null) {
      yield LLMResponseChunk(metadata: {
        ...?usageMetadata,
        'finish_reason': ?finishReason,
      });
    }
    yield LLMResponseChunk(isDone: true);
  }

}

/// One output channel of a stream (text or reasoning), turning whatever the
/// frames carry into deltas.
///
/// The frames are supposed to be deltas already (`incremental_output: true`),
/// but that is a request, not a guarantee: the parameter can be refused and
/// an intermediary can re-assemble frames, and a cumulative stream handed to
/// a consumer that appends replays the whole answer on every frame — which
/// looks like the model stuttering, not like a protocol bug.
///
/// The test is against **everything emitted so far**, not against the last
/// frame: a cumulative frame always has the accumulation as its prefix,
/// while a delta almost never does — it would have to repeat the entire
/// answer so far as its own opening. "Almost" is real, though: repetitive
/// content (markdown rules, ellipses, repeated CJK) makes a delta that opens
/// by restating the whole accumulation reachable at any point in the stream,
/// not just in the first frame, and the prefix test alone would silently
/// swallow the repeated span.
///
/// So the dialect is *latched*: a cumulative stream can only ever extend the
/// accumulation, which means the first frame that fails to do so proves the
/// stream speaks deltas, and every later frame is appended without another
/// look. Ordinary prose trips the latch on the second frame; only a stream
/// whose every frame so far kept extending the accumulation — which is what
/// cumulative *is* — still faces the heuristic, where the ambiguity costs at
/// most the repeated span. (A frame exactly equal to the accumulation stays
/// ambiguous — a cumulative frame with no new tokens reads the same as a
/// delta repeating everything — and is appended without latching, matching
/// the delta assumption the append path always made.)
///
/// Public only so `test/dashscope_chat_payload_test.dart` can reach it; the
/// stream path is the sole caller.
class DashScopeStreamChannel {
  final StringBuffer _emitted = StringBuffer();
  bool _deltaConfirmed = false;

  /// The new span in [frame], and the accumulation advanced past it.
  String feed(String frame) {
    final seen = _emitted.toString();
    if (seen.isEmpty || _deltaConfirmed) {
      _emitted.write(frame);
      return frame;
    }
    if (frame.length > seen.length && frame.startsWith(seen)) {
      final delta = frame.substring(seen.length);
      _emitted.write(delta);
      return delta;
    }
    // A cumulative frame restates everything emitted so far; this one did
    // not, so the stream speaks deltas — permanently. The one exception is a
    // frame *equal* to the accumulation, which either dialect can produce.
    if (frame != seen) _deltaConfirmed = true;
    _emitted.write(frame);
    return frame;
  }
}

/// Says out loud what the text endpoint will do silently: drop every image.
///
/// Reaching here with attachments and a text model is a conversation that
/// includes a reference image on a model that cannot see one — the request
/// still answers (the multimodal endpoint would reject the model outright),
/// but the user should learn why the model ignores the picture.
void _warnIfAttachmentsDropped(LLMTarget target, List<LLMMessage> history,
    bool multimodal, LLMLogger? logger) {
  if (multimodal) return;
  final count = dashscopeAttachmentCount(history);
  if (count == 0) return;
  logger?.call(
    '${target.config.modelId} is served by the text endpoint, which cannot '
    'carry images — $count attachment(s) will not reach the model. Use a '
    'vision model (qwen-vl / qwen-omni) for image turns.',
    level: 'WARN',
  );
}

// ---------------------------------------------------------------------------
// Pure request/response helpers — no IO, so the wire rules can be pinned by
// tests (the repo has no HTTP mock setup; `dashscope_payload.dart` and
// `gemini_payload.dart` are the same arrangement).
// ---------------------------------------------------------------------------

/// Which of the two native chat endpoints this request belongs to.
///
/// The model's own declaration (layer 3) decides it, alone — `qwen-vl`,
/// `qwen-omni` and `qwen-audio` are served only by the multimodal path, and
/// text models only by the text path. The split is by *model*, not by request
/// content (docs/api/qianwen-bailian.md §2, pitfall #10): an attachment used
/// to force the multimodal endpoint regardless, which sent every image-bearing
/// turn of a text model (`qwen-max`, `qwen3`) to an endpoint that does not
/// list it — an upstream "model not supported" error on the whole request,
/// where the text endpoint merely drops the image part. Neither direction is
/// good; only one of them answers at all, so the callers log the drop instead.
bool dashscopeChatIsMultimodal(LLMTarget target) =>
    target.model.needsMultimodalChatSurface;

/// The native chat URL implied by a channel's stored endpoint.
String dashscopeChatUrl(String endpoint, bool multimodal) =>
    '${dashscopeNativeBase(endpoint)}/services/aigc/'
    '${multimodal ? 'multimodal' : 'text'}-generation/generation';

/// Total attachments across [history], for the debug-log redaction.
int dashscopeAttachmentCount(List<LLMMessage> history) =>
    history.fold(0, (sum, m) => sum + m.attachments.length);

/// Builds a DashScope-native chat body.
///
/// The three sections are not interchangeable with the flat OpenAI one:
/// `input` carries the conversation, `parameters` carries everything that
/// shapes the generation, and a key in the wrong section is ignored rather
/// than rejected.
Map<String, dynamic> buildDashScopeChatPayload(
  LLMTarget target,
  List<LLMMessage> history, {
  List<LLMTool>? tools,
  required bool multimodal,
  required bool isStreaming,
}) {
  final messages = [
    for (final msg in history) _dashscopeMessage(msg, multimodal: multimodal),
  ];

  final parameters = <String, dynamic>{
    // Never omitted. The default (`"text"`) answers with a bare string and
    // no `choices`, which carries no tool calls, no finish reason and no
    // role — and looks like an empty reply rather than a wrong request.
    'result_format': 'message',
    // Frames carry only the new span. Without it every frame repeats the
    // whole answer so far, which a consumer that appends turns into
    // quadratic garbage.
    if (isStreaming) 'incremental_output': true,
  };

  final thinking = dashscopeThinkingRequest(
      target.config.effectiveReasoningEffort);
  if (thinking != null) parameters['enable_thinking'] = thinking;

  if (tools != null && tools.isNotEmpty) {
    parameters['tools'] = [
      for (final t in tools)
        {
          'type': 'function',
          'function': {
            'name': t.name,
            'description': t.description,
            'parameters': t.parameters,
          },
        }
    ];
    parameters['tool_choice'] = 'auto';
  }

  return {
    'model': target.config.modelId,
    'input': {'messages': messages},
    'parameters': parameters,
  };
}

/// DashScope's spelling of the app's reasoning control, or null for "send
/// nothing".
///
/// One translation table per family: the native surface has a plain on/off
/// switch rather than ①'s effort ladder or ④'s token budget, so every level
/// above `off` means the same thing here. `off` is sent explicitly — a model
/// whose thinking is on by default (the Qwen 3 generation) needs to be told,
/// and one that predates the field rejects it audibly.
bool? dashscopeThinkingRequest(ReasoningEffort? effort) => switch (effort) {
      null => null,
      ReasoningEffort.off => false,
      _ => true,
    };

/// Text content in whichever shape the endpoint being addressed accepts.
///
/// The multimodal endpoint rejects a bare string even for a turn that carries
/// no image at all, and [dashscopeChatIsMultimodal] is a property of the
/// *model*: a VL/omni/audio model puts every message of the conversation
/// on that endpoint. Which is why this is not something only the branches
/// that build image parts have to think about — a tool result and a
/// tool-calling assistant turn carry no image and still have to be lists,
/// and getting that wrong rejects the first round-trip of any agent turn
/// that happened to include a reference image.
Object _dashscopeContent(String text, {required bool multimodal}) =>
    multimodal ? [<String, dynamic>{'text': text}] : text;

Map<String, dynamic> _dashscopeMessage(LLMMessage msg,
    {required bool multimodal}) {
  // Tool result. `tool_call_id` is the current pairing key and `name` the
  // one older Qwen builds read; both go out because they cost nothing and a
  // mis-paired result is answered as if the tool had returned nothing.
  if (msg.role == LLMRole.tool) {
    return {
      'role': 'tool',
      'content': _dashscopeContent(msg.content, multimodal: multimodal),
      if (msg.toolCallId != null) 'tool_call_id': msg.toolCallId,
      if (msg.toolName != null) 'name': msg.toolName,
    };
  }

  if (msg.role == LLMRole.assistant && msg.toolCalls.isNotEmpty) {
    return {
      'role': 'assistant',
      // Empty string rather than null: the native surface validates the
      // field's type where the compatible face tolerates a null.
      'content': _dashscopeContent(msg.content, multimodal: multimodal),
      if (msg.reasoningContent != null && msg.reasoningFieldName != null)
        msg.reasoningFieldName!: msg.reasoningContent,
      'tool_calls': [
        for (final tc in msg.toolCalls)
          {
            'id': tc.id,
            'type': 'function',
            'function': {
              'name': tc.name,
              'arguments': jsonEncode(tc.arguments),
            },
          }
      ],
    };
  }

  if (!multimodal) {
    return {'role': msg.role.name, 'content': msg.content};
  }

  // Multimodal content is always a list, even for a text-only turn — the
  // endpoint rejects a bare string. Images lead, as they do on the native
  // image surface: the instruction then reads as "…do this to them".
  final parts = <Map<String, dynamic>>[];
  for (final attachment in msg.attachments) {
    if (attachment.path == null && attachment.bytes == null) continue;
    final resolved = ImageCompressor.readForApi(attachment);
    parts.add({
      'image': 'data:${resolved.mimeType};base64,'
          '${base64Encode(resolved.bytes)}',
    });
  }
  parts.add({'text': msg.content});
  return {'role': msg.role.name, 'content': parts};
}

/// The assistant message of a response or stream frame, or null when there is
/// none (an error body, or a `result_format` that produced no `choices`).
Map<String, dynamic>? dashscopeChatMessage(Map<String, dynamic> data) {
  final output = data['output'];
  if (output is! Map) return null;
  final choices = output['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  if (first is! Map) return null;
  final message = first['message'];
  return message is Map ? message.cast<String, dynamic>() : null;
}

/// The finish reason of a response or frame, from either place it can sit.
///
/// `result_format: "message"` puts it on the choice; the `"text"` shape puts
/// it on `output` itself. Both are read because an intermediary that
/// normalizes one shape into the other must not cost the reason.
String? dashscopeFinishReason(Map<String, dynamic> data) {
  final output = data['output'];
  if (output is! Map) return null;
  final choices = output['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map) {
      final reason = first['finish_reason'];
      // `"null"` as a *string* is what DashScope sends for "still going".
      if (reason is String && reason.isNotEmpty && reason != 'null') {
        return reason;
      }
    }
  }
  final reason = output['finish_reason'];
  if (reason is String && reason.isNotEmpty && reason != 'null') return reason;
  return null;
}

/// Usage and finish reason in the shape the rest of the app reads.
///
/// DashScope names its counters `input_tokens` / `output_tokens`, which is
/// the OpenAI *Images* API spelling `LLMService._recordUsage` already falls
/// back to — so they are published verbatim rather than renamed, and a
/// change to that fallback chain would break both surfaces together instead
/// of leaving this one silently recording zeros.
Map<String, dynamic> dashscopeChatMetadata(Map<String, dynamic> data) {
  final usage = data['usage'];
  return {
    if (usage is Map) ...usage.cast<String, dynamic>(),
    'finish_reason': ?dashscopeFinishReason(data),
    'request_id': ?_stringOrNull(data['request_id']),
  };
}

String? _stringOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// The tool calls carried by an assistant message, in declaration order.
List<LLMToolCall> dashscopeToolCalls(
    Map<String, dynamic> message, LLMLogger? logger) {
  final raw = message['tool_calls'];
  if (raw is! List) return const [];
  final calls = <LLMToolCall>[];
  for (var i = 0; i < raw.length; i++) {
    final tc = raw[i];
    final fn = tc is Map ? tc['function'] : null;
    if (fn is! Map) continue;
    // Shared with the ① face and with the streaming accumulator, so the three
    // cannot come to disagree about what a payload means.
    final args = decodeToolArguments(fn['arguments'], logger: logger);
    calls.add(LLMToolCall(
      id: resolveToolCallId(tc is Map ? tc['id'] : null, i),
      name: fn['name']?.toString() ?? '',
      arguments: args,
    ));
  }
  return calls;
}
