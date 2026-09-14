import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../image_compression.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'openai_chat_protocol.dart' show decodeToolArguments, resolveToolCallId;
import 'protocol.dart';

/// The `include` value that asks a Responses host for the encrypted
/// reasoning on each reasoning item — sent only where the vendor declares it
/// needs asking (`VendorProfile.responsesIncludeEncryptedReasoning`).
const String responsesEncryptedReasoningInclude = 'reasoning.encrypted_content';

/// The Responses API's spelling of the app's reasoning vocabulary, or null
/// for "send nothing" (reasoning 03 §7.1).
///
/// Default sends no `reasoning` object at all — each model's default differs
/// (GPT-5.4 `none`, 5.5/5.6 `medium`, Grok 4.5/4.6 `high`), and "unset" must
/// not be spelled as any of them. Off is `{effort: "none"}` with no summary.
/// Every other level carries `summary: "auto"`: without it the host streams
/// no summary events at all, and the thinking is billed but never seen.
///
/// The menu is not trimmed per model: GPT-5.4 rejects `max`, Grok 4.5/4.6
/// reject `none` and every Grok rejects `max`, each with a 400 that names
/// the value — the endpoint's own statement beats a guess from a model id
/// that a relay may have renamed.
Map<String, dynamic>? responsesReasoningField(ReasoningEffort? effort) =>
    switch (effort) {
      null => null,
      ReasoningEffort.off => {'effort': 'none'},
      ReasoningEffort.low => {'effort': 'low', 'summary': 'auto'},
      ReasoningEffort.medium => {'effort': 'medium', 'summary': 'auto'},
      ReasoningEffort.high => {'effort': 'high', 'summary': 'auto'},
      ReasoningEffort.max => {'effort': 'max', 'summary': 'auto'},
    };

/// The `tool_choice` for a request that declares function tools.
///
/// `auto` / `none` / `required` pass through; anything else names one
/// function, spelled **without** ①'s `function` wrapper:
/// `{type: "function", name}` (protocol 02 §7.1 rule 4). Never sent on a
/// request without function tools.
Object responsesToolChoice(Object? requested) {
  if (requested is String && requested.isNotEmpty) {
    if (const {'auto', 'none', 'required'}.contains(requested)) {
      return requested;
    }
    return {'type': 'function', 'name': requested};
  }
  return 'auto';
}

/// Every system message of [history], hoisted and joined by a blank line —
/// `""` when there is none.
///
/// Always sent, even empty (protocol 02 §7.1 rule 2): a New API relay that
/// finds `instructions` missing injects its own multi-thousand-token Codex
/// prompt, and nothing but the bill says so (provider layering 01 §9.2).
String responsesInstructions(List<LLMMessage> history) => history
    .where((m) => m.role == LLMRole.system)
    .map((m) => m.content)
    .where((c) => c.isNotEmpty)
    .join('\n\n');

/// [history] as Responses `input` items, for a request to [modelId].
///
/// * system → left out (it is [responsesInstructions]);
/// * user → `{role: user, content: [input_text, input_image…]}`, the image a
///   data URL in `image_url` — a string beside the part's other keys, never
///   an object the way ① nests it;
/// * a tool-calling assistant turn → its [LLMMessage.rawResponseItems]
///   verbatim when [modelId] produced them, **instead of** the rebuilt calls;
///   otherwise any text as an assistant message and one bare `function_call`
///   per call. Never both: the verbatim items already contain the calls, and
///   sending them twice duplicates every call id;
/// * plain assistant text → `{role: assistant, content: "…"}` — the easy
///   input message form, whose content may be a string;
/// * tool result → `{type: function_call_output, call_id, output}`.
List<Map<String, dynamic>> buildResponsesInput(
  List<LLMMessage> history, {
  required String modelId,
}) {
  final input = <Map<String, dynamic>>[];
  for (final msg in history) {
    switch (msg.role) {
      case LLMRole.system:
        continue;
      case LLMRole.tool:
        input.add({
          'type': 'function_call_output',
          'call_id': msg.toolCallId ?? '',
          'output': msg.content,
        });
      case LLMRole.assistant:
        final raw = msg.rawResponseItems;
        final replayRaw = msg.toolCalls.isNotEmpty &&
            raw != null &&
            raw.isNotEmpty &&
            msg.rawThinkingModelId == modelId;
        if (replayRaw) {
          // A deep copy, so nothing downstream of the payload can write into
          // stored history.
          for (final item in raw) {
            input.add(
                (jsonDecode(jsonEncode(item)) as Map).cast<String, dynamic>());
          }
          continue;
        }
        if (msg.content.isNotEmpty) {
          input.add({'role': 'assistant', 'content': msg.content});
        }
        for (final call in msg.toolCalls) {
          input.add({
            'type': 'function_call',
            'call_id': call.id,
            'name': call.name,
            'arguments': jsonEncode(call.arguments),
          });
        }
      case LLMRole.user:
        final parts = <Map<String, dynamic>>[
          if (msg.content.isNotEmpty || msg.attachments.isEmpty)
            {'type': 'input_text', 'text': msg.content},
        ];
        for (final attachment in msg.attachments) {
          if (attachment.path == null && attachment.bytes == null) continue;
          final resolved = ImageCompressor.readForApi(attachment);
          parts.add({
            'type': 'input_image',
            'image_url':
                'data:${resolved.mimeType};base64,${base64Encode(resolved.bytes)}',
          });
        }
        input.add({'role': 'user', 'content': parts});
    }
  }
  return input;
}

/// The `POST /responses` body for [target].
///
/// Rules that fail silently when broken (protocol 02 §7.1):
/// * `instructions` always, even `""`;
/// * `store: false` always — the app keeps its own history, zero-retention
///   organisations are refused without it, and it is what makes a host
///   attach `encrypted_content` to reasoning items;
/// * function tools flat with an explicit `strict: false` — omitted, the
///   official host promotes the tool to strict and rewrites every schema
///   with optional fields into an "all required or 400" contract;
/// * `tool_choice` only beside function tools;
/// * `max_output_tokens` only when the caller capped the output;
/// * `include: ["reasoning.encrypted_content"]` only where the vendor
///   declares it needs asking.
Map<String, dynamic> buildResponsesPayload(
  LLMTarget target,
  List<LLMMessage> history, {
  Map<String, dynamic>? options,
  required bool isStreaming,
  List<LLMTool>? tools,
}) {
  final config = target.config;
  final reasoning = responsesReasoningField(config.effectiveReasoningEffort);
  final maxTokens = requestedMaxTokens(options);
  return {
    'model': config.modelId,
    'instructions': responsesInstructions(history),
    'input': buildResponsesInput(history, modelId: config.modelId),
    'store': false,
    if (tools != null && tools.isNotEmpty) ...{
      'tools': [
        for (final t in tools)
          {
            'type': 'function',
            'name': t.name,
            'description': t.description,
            'parameters': t.parameters,
            'strict': false,
          },
      ],
      'tool_choice': responsesToolChoice(options?['toolChoice']),
    },
    'reasoning': ?reasoning,
    if (target.vendor.responsesIncludeEncryptedReasoning)
      'include': const [responsesEncryptedReasoningInclude],
    'max_output_tokens': ?maxTokens,
    if (isStreaming) 'stream': true,
  };
}

/// One function call under construction, keyed by `output_index`.
class _PendingResponsesCall {
  String callId = '';
  String name = '';
  final StringBuffer deltas = StringBuffer();

  /// The whole arguments string from `function_call_arguments.done` or the
  /// finished item. Wins over [deltas] whenever it arrived.
  String? whole;
}

/// Turns Responses stream events into chunks — pure, so every rule is
/// pinned without a socket (the `AnthropicStreamAssembler` pattern).
///
/// Reads (protocol 02 §7.2):
/// * text from `response.output_text.delta` (only `delta`: the
///   `obfuscation` padding beside it is noise), reasoning from
///   `response.reasoning_summary_text.delta` and
///   `response.reasoning_text.delta`;
/// * function calls grouped by **`output_index`** — some relays drop
///   `item_id` from the delta events — with the whole string from
///   `function_call_arguments.done` / `output_item.done` beating the
///   accumulated deltas; a host that sends only one of the two still yields
///   the whole call;
/// * the replay carrier straight from `output_item.done` (reasoning,
///   function_call, message — never a server tool's item), not rebuilt from
///   deltas;
/// * the terminal event: `response.completed`, `response.incomplete`
///   (`max_output_tokens` → `length`, `content_filter` → `content_filter`,
///   which `LLMService` turns into the failure), `response.failed` / `error`
///   / a bare `{error}` → [LLMApiException].
///
/// The synchronous path replays its body's `output[]` through the same class
/// ([responsesResponseFromBody]), so the two cannot disagree.
class ResponsesStreamAssembler {
  /// The `reasoning.effort` this request sent, for the echo comparison — or
  /// null when it sent none, in which case nothing is compared.
  final String? sentEffort;

  /// Names the request in thrown errors (already redacted).
  final String requestLabel;

  final LLMLogger? logger;

  ResponsesStreamAssembler({
    this.sentEffort,
    this.requestLabel = 'OpenAI Responses API',
    this.logger,
  });

  final Map<int, _PendingResponsesCall> _calls = {};
  final Map<int, Map<String, dynamic>> _items = {};
  final Set<int> _textStreamed = {};
  final Set<int> _reasoningStreamed = {};

  bool _sawEvent = false;
  bool _sawOutput = false;

  /// Whether a `refusal` content part arrived, by event or inside an item.
  bool _refused = false;
  final StringBuffer _refusal = StringBuffer();
  bool _terminal = false;
  String? _finishReason;
  String? _finishRaw;
  Map<String, dynamic>? _usage;
  List<Map<String, dynamic>>? _rewrites;

  /// Whether a single protocol event arrived.
  bool get sawEvent => _sawEvent;

  static int _index(Map<String, dynamic> event) {
    final raw = event['output_index'];
    return raw is num ? raw.toInt() : -1;
  }

  /// Consume one decoded `data:` payload; returns what became deliverable.
  List<LLMResponseChunk> feed(Map<String, dynamic> event) {
    final type = event['type'];
    if (type is! String) {
      // A bare `{error: …}` with no event type is a relay's failure
      // envelope inside the stream.
      if (event['error'] != null) {
        _sawEvent = true;
        throwIfEnvelopeError(event);
      }
      return const [];
    }
    _sawEvent = true;
    switch (type) {
      case 'response.output_text.delta':
        final delta = event['delta'];
        if (delta is! String || delta.isEmpty) return const [];
        _sawOutput = true;
        _textStreamed.add(_index(event));
        return [LLMResponseChunk(textPart: delta)];

      // A refusal is not reply text: it ends the turn as `content_filter`,
      // like ④'s `refusal`, and LLMService fails the request after recording
      // usage. The text is kept only for the log line.
      case 'response.refusal.delta':
        final delta = event['delta'];
        _refused = true;
        if (delta is String) _refusal.write(delta);
        return [LLMResponseChunk()];

      case 'response.refusal.done':
        final whole = event['refusal'];
        _refused = true;
        if (whole is String) {
          _refusal
            ..clear()
            ..write(whole);
        }
        return const [];

      case 'response.reasoning_summary_text.delta':
      case 'response.reasoning_text.delta':
        final delta = event['delta'];
        if (delta is! String || delta.isEmpty) return const [];
        _sawOutput = true;
        _reasoningStreamed.add(_index(event));
        return [LLMResponseChunk(reasoningPart: delta)];

      case 'response.output_item.added':
        final item = event['item'];
        if (item is Map && item['type'] == 'function_call') {
          final call = _calls.putIfAbsent(_index(event), _PendingResponsesCall.new);
          call.callId = item['call_id']?.toString() ?? call.callId;
          call.name = item['name']?.toString() ?? call.name;
          _sawOutput = true;
          // Keepalive: a call buffers until it is whole, and the consumer's
          // idle guard resets only on chunks it receives.
          return [LLMResponseChunk()];
        }
        return const [];

      case 'response.function_call_arguments.delta':
        final delta = event['delta'];
        final call = _calls.putIfAbsent(_index(event), _PendingResponsesCall.new);
        if (delta is String) call.deltas.write(delta);
        _sawOutput = true;
        return [LLMResponseChunk()];

      case 'response.function_call_arguments.done':
        final args = event['arguments'];
        final call = _calls.putIfAbsent(_index(event), _PendingResponsesCall.new);
        if (args is String) call.whole = args;
        _sawOutput = true;
        return const [];

      case 'response.output_item.done':
        final raw = event['item'];
        if (raw is! Map) return const [];
        return _itemDone(_index(event), raw.cast<String, dynamic>());

      case 'response.completed':
      case 'response.incomplete':
        _readTerminal(event['response'], type);
        return const [];

      case 'response.failed':
        _terminal = true;
        final response = event['response'];
        final error = response is Map ? response['error'] : null;
        final message = error is Map
            ? '${error['message'] ?? error}'
                '${error['code'] == null ? '' : ' (${error['code']})'}'
            : 'no error detail';
        throw LLMApiException(
            '$requestLabel reported the response as failed: $message',
            isEnvelope: true);

      case 'error':
        _terminal = true;
        final code = event['code'];
        throw LLMApiException(
            '$requestLabel stream error: ${event['message'] ?? event}'
            '${code == null ? '' : ' ($code)'}',
            isEnvelope: true);

      default:
        return const [];
    }
  }

  List<LLMResponseChunk> _itemDone(int index, Map<String, dynamic> item) {
    final chunks = <LLMResponseChunk>[];
    switch (item['type']) {
      case 'function_call':
        final call = _calls.putIfAbsent(index, _PendingResponsesCall.new);
        call.callId = item['call_id']?.toString() ?? call.callId;
        call.name = item['name']?.toString() ?? call.name;
        final args = item['arguments'];
        if (args is String) call.whole = args;
        _sawOutput = true;
        _items[index] = _copy(item);
      case 'message':
        _items[index] = _copy(item);
        final refusal = _refusalText(item);
        if (refusal != null) {
          _refused = true;
          if (_refusal.isEmpty) _refusal.write(refusal);
        }
        // A host that sent the item without its text deltas still delivers
        // the text.
        if (!_textStreamed.contains(index)) {
          final text = _messageText(item);
          if (text.isNotEmpty) {
            _sawOutput = true;
            chunks.add(LLMResponseChunk(textPart: text));
          }
        }
      case 'reasoning':
        _items[index] = _copy(item);
        if (!_reasoningStreamed.contains(index)) {
          final text = _reasoningText(item);
          if (text.isNotEmpty) {
            _sawOutput = true;
            chunks.add(LLMResponseChunk(reasoningPart: text));
          }
        }
      default:
        // Server tools (`web_search_call` …) ran upstream; they are not
        // replayed, and the answer they fed arrives as a message item.
        break;
    }
    return chunks;
  }

  void _readTerminal(Object? raw, String type) {
    _terminal = true;
    final response = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    final usage = response['usage'];
    if (usage is Map) _usage = responsesUsageMetadata(usage.cast<String, dynamic>());

    final details = response['incomplete_details'];
    final reason = details is Map ? details['reason']?.toString() : null;
    if (type == 'response.incomplete' || reason != null) {
      _finishRaw = reason ?? 'incomplete';
      _finishReason = reason == contentFilterFinishReason
          ? contentFilterFinishReason
          : 'length';
    } else {
      _finishReason = 'stop';
    }

    // Echo comparison (errors 06 §4.1): report, never retry; a missing echo
    // says nothing.
    final reasoning = response['reasoning'];
    final echoed = reasoning is Map ? reasoning['effort'] : null;
    if (sentEffort != null && echoed is String && echoed != sentEffort) {
      _rewrites = [
        {'field': 'reasoning.effort', 'sent': sentEffort, 'echoed': echoed},
      ];
      logger?.call(
        'The endpoint changed reasoning.effort from "$sentEffort" to '
        '"$echoed" — the request ran with a different reasoning level than '
        'configured.',
        level: 'WARN',
      );
    }
  }

  /// The closing chunks: whole calls, the replay carrier, metadata. Throws
  /// where the stream cannot be delivered as a turn.
  List<LLMResponseChunk> finish() {
    if (!_sawEvent) {
      throw LLMApiException(
        '$requestLabel stream ended without a single event — the base URL may '
        'point at something that is not this API, or the relay answered with '
        'an empty stream.',
        isNonJsonBody: true,
      );
    }

    var streamIncomplete = false;
    if (!_terminal) {
      // Ends without response.completed happen (protocol 02 §7.2). Text is
      // delivered, marked as truncated like ①'s cut stream; a turn with
      // calls is not — nothing proves the batch was whole.
      if (_calls.isNotEmpty) {
        throw LLMApiException(
          '$requestLabel stream closed without a terminal event while function '
          'calls were in flight — the stream was truncated, and a batch that '
          'may be missing calls must not be executed.',
        );
      }
      logger?.call(
        'The Responses stream closed without a terminal event — the reply was '
        'probably cut off in transit. Treating it as truncated.',
        level: 'WARN',
      );
      _finishReason = 'length';
      streamIncomplete = true;
    }

    if (_refused) {
      _finishReason = contentFilterFinishReason;
      _finishRaw = 'refusal';
      logger?.call(
        'The model refused (Responses refusal part): ${_refusal.toString()}',
        level: 'WARN',
      );
    }

    if (!_sawOutput &&
        _finishReason != 'length' &&
        _finishReason != contentFilterFinishReason) {
      throw LLMApiException(
        '$requestLabel returned no content — no text, reasoning or function '
        'calls (usage: ${_usage ?? 'none'}).',
      );
    }

    final chunks = <LLMResponseChunk>[];
    final indices = _calls.keys.toList()..sort();
    final calls = <LLMToolCall>[];
    for (final index in indices) {
      final pending = _calls[index]!;
      calls.add(LLMToolCall(
        id: resolveToolCallId(pending.callId, index < 0 ? calls.length : index),
        name: pending.name,
        arguments: decodeToolArguments(
            pending.whole ?? pending.deltas.toString(),
            logger: logger),
      ));
    }
    for (final call in calls) {
      chunks.add(LLMResponseChunk(toolCallPart: call));
    }

    // The carrier stands for the calls only if it contains every one of them;
    // a call assembled from deltas alone has no item to replay, and verbatim
    // reasoning without its call would break the pairing.
    if (calls.isNotEmpty) {
      final ordered = [for (final i in (_items.keys.toList()..sort())) _items[i]!];
      final itemCallIds = {
        for (final item in ordered)
          if (item['type'] == 'function_call') item['call_id']?.toString(),
      };
      if (calls.every((c) => itemCallIds.contains(c.id))) {
        chunks.add(LLMResponseChunk(rawResponseItems: ordered));
      }
    }

    chunks.add(LLMResponseChunk(metadata: {
      ...?_usage,
      'finish_reason': calls.isNotEmpty && _finishReason == 'stop'
          ? 'tool_calls'
          : _finishReason,
      'finish_reason_raw': ?_finishRaw,
      if (streamIncomplete) 'stream_incomplete': true,
      'wire_rewrites': ?_rewrites,
    }));
    return chunks;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> item) =>
      (jsonDecode(jsonEncode(item)) as Map).cast<String, dynamic>();

  static String _messageText(Map<String, dynamic> item) {
    final content = item['content'];
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map || part['type'] == 'refusal') continue;
      final text = part['text'];
      if (text is String) buffer.write(text);
    }
    return buffer.toString();
  }

  /// The text of the item's `{type: "refusal", refusal}` part, `''` for one
  /// without text, or null when the item holds no refusal.
  static String? _refusalText(Map<String, dynamic> item) {
    final content = item['content'];
    if (content is! List) return null;
    for (final part in content) {
      if (part is Map && part['type'] == 'refusal') {
        final text = part['refusal'];
        return text is String ? text : '';
      }
    }
    return null;
  }

  static String _reasoningText(Map<String, dynamic> item) {
    final texts = <String>[];
    for (final key in const ['summary', 'content']) {
      final list = item[key];
      if (list is! List) continue;
      for (final part in list) {
        final text = part is Map ? part['text'] : null;
        if (text is String && text.isNotEmpty) texts.add(text);
      }
      if (texts.isNotEmpty) break;
    }
    return texts.join('\n\n');
  }
}

/// A Responses `usage` block in the shape `LLMService` records: ①'s
/// spellings, so the recorder needs no branch of its own.
///
/// `input_tokens_details.cached_tokens` is a subset of `input_tokens`, as
/// ①'s `cached_tokens` is of `prompt_tokens`; `output_tokens` already counts
/// reasoning (`output_tokens_details.reasoning_tokens` is a breakdown).
Map<String, dynamic> responsesUsageMetadata(Map<String, dynamic> usage) {
  final input = usage['input_tokens'];
  final output = usage['output_tokens'];
  final inputDetails = usage['input_tokens_details'];
  final outputDetails = usage['output_tokens_details'];
  final cached = inputDetails is Map ? inputDetails['cached_tokens'] : null;
  final reasoning =
      outputDetails is Map ? outputDetails['reasoning_tokens'] : null;
  return {
    'prompt_tokens': ?input,
    'completion_tokens': ?output,
    'total_tokens': ?usage['total_tokens'],
    if (cached != null) 'prompt_tokens_details': {'cached_tokens': cached},
    if (reasoning != null)
      'completion_tokens_details': {'reasoning_tokens': reasoning},
  };
}

/// A synchronous Responses body as an [LLMResponse], through the stream
/// assembler: every output item is fed as its `output_item.done`, then the
/// body itself as the terminal event its `status` names.
LLMResponse responsesResponseFromBody(
  Map<String, dynamic> body, {
  required String modelId,
  String? sentEffort,
  String requestLabel = 'OpenAI Responses API',
  LLMLogger? logger,
}) {
  final assembler = ResponsesStreamAssembler(
      sentEffort: sentEffort, requestLabel: requestLabel, logger: logger);
  final chunks = <LLMResponseChunk>[];
  final output = body['output'];
  if (output is List) {
    for (var i = 0; i < output.length; i++) {
      final item = output[i];
      if (item is! Map) continue;
      chunks.addAll(assembler.feed({
        'type': 'response.output_item.done',
        'output_index': i,
        'item': item,
      }));
    }
  }
  final status = body['status'];
  chunks.addAll(assembler.feed({
    'type': switch (status) {
      'failed' => 'response.failed',
      'incomplete' => 'response.incomplete',
      _ => 'response.completed',
    },
    'response': body,
  }));
  chunks.addAll(assembler.finish());

  final text = StringBuffer();
  final reasoning = StringBuffer();
  final calls = <LLMToolCall>[];
  List<Map<String, dynamic>>? items;
  Map<String, dynamic> metadata = const {};
  for (final chunk in chunks) {
    if (chunk.textPart != null) text.write(chunk.textPart);
    if (chunk.reasoningPart != null) {
      if (reasoning.isNotEmpty) reasoning.write('\n\n');
      reasoning.write(chunk.reasoningPart);
    }
    if (chunk.toolCallPart != null) calls.add(chunk.toolCallPart!);
    if (chunk.rawResponseItems != null) items = chunk.rawResponseItems;
    if (chunk.metadata != null) metadata = chunk.metadata!;
  }
  return LLMResponse(
    text: text.toString(),
    metadata: metadata,
    reasoningContent: reasoning.isEmpty ? null : reasoning.toString(),
    rawResponseItems: items,
    // The producer of the items, which are replayed only to the same model.
    rawThinkingModelId: items == null ? null : modelId,
    toolCalls: calls,
  );
}

/// OpenAI `POST {base}/responses` — the ② chat wire, served by the same base
/// URL and bearer auth as ①.
class OpenAIResponsesProtocol implements ChatProtocol {
  static const String _apiName = 'OpenAI Responses API';

  @override
  bool get streamingDeclaresTools => true;

  @override
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/responses');
    logger?.call('Preparing OpenAI Responses request to: ${url.host}',
        level: 'DEBUG');
    final headers = target.headers();
    final payload = buildResponsesPayload(target, history,
        options: options, isStreaming: false, tools: tools);

    final client = config.createClient();
    try {
      LLMDebugLog? debugFile;
      if (AppState().enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(
          config.modelId,
          'OpenAI (Responses)',
          {'url': redactUrl(url), 'headers': headers, 'body': payload},
        );
      }
      final response = await sendJsonRequest(client, url,
          headers: headers, body: jsonEncode(payload), options: options);
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
            debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
        await LLMDebugLogger.finish(debugFile);
      }
      final data = decodeJsonBody(response, apiName: _apiName);
      return responsesResponseFromBody(
        data,
        modelId: config.modelId,
        sentEffort: (payload['reasoning'] as Map?)?['effort'] as String?,
        requestLabel: '$_apiName (${redactUrl(url)})',
        logger: logger,
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
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async* {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/responses');
    logger?.call('Starting OpenAI Responses stream: ${url.host}',
        level: 'DEBUG');
    final headers = target.headers();
    final payload = buildResponsesPayload(target, history,
        options: options, isStreaming: true, tools: tools);

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    LLMDebugLog? debugFile;
    if (AppState().enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(
        config.modelId,
        'OpenAI (Responses Stream)',
        {'url': redactUrl(url), 'headers': headers, 'body': payload},
      );
    }

    final http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (_) {
      client.close();
      await LLMDebugLogger.finish(debugFile);
      rethrow;
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(
            debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
        await LLMDebugLogger.finish(debugFile);
      }
      client.close();
      throw LLMApiException(
        '$_apiName Stream Request failed: ${response.statusCode} '
        '(${redactUrl(url)}) - '
        '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
        statusCode: response.statusCode,
        retryAfter: parseRetryAfter(response.headers),
      );
    }

    final assembler = ResponsesStreamAssembler(
      sentEffort: (payload['reasoning'] as Map?)?['effort'] as String?,
      requestLabel: '$_apiName (${redactUrl(url)})',
      logger: logger,
    );

    try {
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (debugFile != null && line.isNotEmpty) {
          await LLMDebugLogger.appendStreamLine(debugFile, line);
        }
        // The `event:` line repeats the payload's own `type`.
        if (line.startsWith('event:')) continue;
        final data = sseDataPayload(line);
        if (data == null) continue;
        Map<String, dynamic>? event;
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) event = decoded;
        } catch (_) {
          continue; // Non-JSON SSE noise.
        }
        if (event == null) continue;
        for (final chunk in assembler.feed(event)) {
          yield chunk;
        }
      }
    } finally {
      client.close();
      await LLMDebugLogger.finish(debugFile);
    }

    // Outside the finally: a stream that died mid-call must fail, not deliver.
    for (final chunk in assembler.finish()) {
      yield chunk;
    }
    yield LLMResponseChunk(isDone: true);
  }
}
