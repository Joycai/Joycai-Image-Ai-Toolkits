import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/safety_settings.dart';
import '../../../state/app_state.dart';
import '../image_compression.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import 'protocol.dart';

/// Recovers a `function.arguments` string that is several JSON objects
/// concatenated back-to-back (e.g. `{}{"id": 1}`), which some relays emit —
/// observed from a Claude-via-relay backend that prefixes real arguments
/// with a stray empty-object placeholder. Plain [jsonDecode] rejects the
/// trailing data, so this walks brace depth to split the string into
/// top-level objects and merges them left-to-right (a later object's keys
/// win). Returns null if the string isn't actually this shape.
Map<String, dynamic>? _recoverConcatenatedJsonObjects(String raw) {
  final objects = <Map<String, dynamic>>[];
  int depth = 0;
  int start = -1;
  bool inString = false;
  bool escapeNext = false;

  for (int i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (escapeNext) {
      escapeNext = false;
      continue;
    }
    if (inString) {
      if (ch == '\\') {
        escapeNext = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0 && start != -1) {
        try {
          final decoded = jsonDecode(raw.substring(start, i + 1));
          if (decoded is Map<String, dynamic>) objects.add(decoded);
        } catch (_) {
          // Not a valid standalone object — give up on recovery entirely
          // rather than silently dropping part of the arguments.
          return null;
        }
        start = -1;
      } else if (depth < 0) {
        return null;
      }
    }
  }

  if (objects.length < 2) return null;
  final merged = <String, dynamic>{};
  for (final obj in objects) {
    merged.addAll(obj);
  }
  return merged;
}

/// Normalizes a chat message's `content` field into text.
///
/// `content` is a plain string in the OpenAI spec, but compat layers fronting
/// a Responses- or Anthropic-shaped backend mirror the content-**array** form
/// onto `chat/completions` (`[{"type":"text","text":"…"}]`). A bare `String`
/// downcast throws a `TypeError` from inside the parser, which reaches the
/// caller as a request failure with nothing in it that points at the cause —
/// so both shapes are accepted and anything else (an image part carries no
/// text) contributes nothing.
String contentToText(Object? raw) {
  if (raw is String) return raw;
  if (raw is! List) return '';
  final buffer = StringBuffer();
  for (final part in raw) {
    if (part is String) {
      buffer.write(part);
    } else if (part is Map) {
      final text = part['text'];
      if (text is String) buffer.write(text);
    }
  }
  return buffer.toString();
}

/// Call id for the [index]-th tool call of a response.
///
/// Relays that do not assign ids mostly send `null`, but some send `""` —
/// which a plain `?? 'call_$index'` fallback keeps, so two calls in one batch
/// share an empty `tool_call_id` and the *next* request is rejected for a
/// duplicate id. Empty is treated as absent.
String resolveToolCallId(Object? rawId, int index) {
  final id = rawId?.toString();
  return (id == null || id.isEmpty) ? 'call_$index' : id;
}

/// One tool call's `arguments`, decoded.
///
/// Shared by the synchronous and streaming paths so the two cannot come to
/// disagree about what a payload means. The value is a JSON *string* on every
/// ①-shaped wire, but relays have been seen answering with the object itself,
/// and both spellings reach here.
///
/// An unparseable string yields empty arguments rather than dropping the
/// call: a missing call reads to an agent loop as "the model chose to answer
/// directly", which is the one failure mode it cannot detect, so the call
/// goes out and the tool reports the mismatch itself.
Map<String, dynamic> decodeToolArguments(Object? rawArgs, {LLMLogger? logger}) {
  if (rawArgs is Map<String, dynamic>) return rawArgs;
  if (rawArgs is! String || rawArgs.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(rawArgs);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (e) {
    final recovered = _recoverConcatenatedJsonObjects(rawArgs);
    if (recovered != null) {
      logger?.call(
        'Tool call arguments were concatenated JSON objects '
        '("$rawArgs") — recovered by merging them.',
        level: 'WARN',
      );
      return recovered;
    }
    logger?.call('Failed to decode tool call arguments: $e', level: 'WARN');
  }
  return const {};
}

/// Assembles the `tool_calls` fragments of a stream into whole calls.
///
/// ① splits one call across chunks and groups the pieces by
/// `delta.tool_calls[].index` — not by `id`, which is fragmented too
/// (docs/api/tools.md §4) — and gives no per-call terminator the way ④'s
/// `content_block_stop` does. Nothing can therefore be emitted before the
/// stream ends, which is why [LLMResponseChunk.toolCallPart] promises whole
/// calls and this class hands them over only from [flush].
///
/// Fragments are *merged* rather than appended blindly, because one wire
/// shape serves two dialects: ① streams deltas, while DashScope's native face
/// streams deltas only where `incremental_output` was honoured and otherwise
/// repeats the whole call on every frame. Appending a cumulative frame builds
/// `{"a":1}{"a":1}` — which parses as nothing and reaches the model as a
/// malformed argument set.
class StreamingToolCallAccumulator {
  final Map<int, _PendingToolCall> _calls = {};

  /// Whether any fragment has arrived. False on a stream that answered with
  /// text alone, which is the common case.
  bool get isEmpty => _calls.isEmpty;

  /// Consume one chunk's `tool_calls` array. Anything else is ignored — the
  /// field is absent from most chunks of a tool-bearing stream.
  void feed(Object? rawToolCalls) {
    if (rawToolCalls is! List) return;
    for (var position = 0; position < rawToolCalls.length; position++) {
      final tc = rawToolCalls[position];
      if (tc is! Map) continue;
      // `index` is the grouping key the spec guarantees. For relays that omit
      // the field, the fallback is resolved from the call's own identity —
      // see [_slotForIndexless] for why bare array position is not enough.
      final rawIndex = tc['index'];
      final index =
          rawIndex is num ? rawIndex.toInt() : _slotForIndexless(tc, position);
      final pending = _calls.putIfAbsent(index, _PendingToolCall.new);
      pending.id = _merge(pending.id, tc['id']);
      final fn = tc['function'];
      if (fn is! Map) continue;
      final rawName = fn['name'];
      // Dialect telltale, read before the merges fold this frame in: a
      // cumulative frame restates the whole call every time — name included —
      // while ① deltas carry only `index` + `arguments` once the call is
      // open. A nameless frame on an already-named call is therefore a delta,
      // and its arguments append unconditionally. This closes the one gap the
      // prefix heuristic in [_merge] leaves open: a delta that happens to
      // begin by repeating the entire accumulation (`{"a":` + `{"a":1}}`),
      // which the heuristic alone would swallow as a cumulative repeat.
      final isNamelessDelta =
          pending.name.isNotEmpty && (rawName is! String || rawName.isEmpty);
      pending.name = _merge(pending.name, rawName);
      final rawArgs = fn['arguments'];
      if (rawArgs is Map<String, dynamic>) {
        // Already whole — no wire sends an object in pieces — so it replaces
        // rather than merges.
        pending.decodedArguments = rawArgs;
      } else if (isNamelessDelta && rawArgs is String) {
        pending.arguments = pending.arguments + rawArgs;
      } else {
        pending.arguments = _merge(pending.arguments, rawArgs);
      }
    }
  }

  /// Grouping slot for a fragment whose frame omitted `index`.
  ///
  /// Array position is the spec-shaped fallback — it is what the field would
  /// have said for calls sharing one frame. But a relay that omits `index`
  /// and streams *multiple* calls in separate single-element frames puts every
  /// call at position 0, and merging them builds one blended call — the
  /// silent loss an agent loop cannot detect. The call's `id` disambiguates:
  /// a fragment carrying a known id joins that call, one carrying a new id
  /// opens a fresh slot. Fragments with no id keep the positional answer.
  int _slotForIndexless(Map<dynamic, dynamic> tc, int position) {
    final rawId = tc['id'];
    if (rawId is String && rawId.isNotEmpty) {
      for (final entry in _calls.entries) {
        if (entry.value.id == rawId) return entry.key;
      }
      if (_calls.containsKey(position) &&
          _calls[position]!.id.isNotEmpty &&
          _calls[position]!.id != rawId) {
        return _calls.keys.reduce((a, b) => a > b ? a : b) + 1;
      }
    }
    return position;
  }

  /// Everything assembled so far, in `index` order, and the accumulator
  /// emptied so a reused instance cannot replay a previous turn's calls.
  List<LLMToolCall> flush({LLMLogger? logger}) {
    if (_calls.isEmpty) return const [];
    final calls = <LLMToolCall>[];
    for (final index in _calls.keys.toList()..sort()) {
      final pending = _calls[index]!;
      calls.add(LLMToolCall(
        id: resolveToolCallId(pending.id, index),
        name: pending.name,
        arguments: pending.decodedArguments ??
            decodeToolArguments(pending.arguments, logger: logger),
      ));
    }
    _calls.clear();
    return calls;
  }

  /// [raw] folded into what has already arrived on the same field.
  ///
  /// A frame that has the accumulation as its own prefix is a cumulative
  /// repeat and replaces it — which also covers the identical repeat a name
  /// makes on every cumulative frame, and the very first fragment, where the
  /// accumulation is empty. Anything else is a delta and is appended.
  ///
  /// The one shape this cannot tell apart is a delta that opens by repeating
  /// the entire accumulation. For arguments, [feed] resolves that ambiguity
  /// before it reaches here — a nameless frame on a named call is a delta by
  /// construction and appends unconditionally — so this heuristic only
  /// decides frames that restate the name, which is the cumulative dialect's
  /// signature. `DashScopeStreamChannel` faces the same ambiguity for text,
  /// where no such telltale exists.
  static String _merge(String seen, Object? raw) {
    if (raw is! String || raw.isEmpty) return seen;
    if (raw.startsWith(seen)) return raw;
    return seen + raw;
  }
}

/// One call under construction. Mutable and private: only
/// [StreamingToolCallAccumulator] may hold a half-built call.
class _PendingToolCall {
  String id = '';
  String name = '';
  String arguments = '';

  /// Set only where a relay answered with the arguments object itself, in
  /// which case [arguments] stays empty and this wins.
  Map<String, dynamic>? decodedArguments;
}

/// The first `choices` entry of a response or stream chunk, or null when there
/// is none.
///
/// The usage-only chunk that `stream_options.include_usage` produces at stream
/// end carries `"choices": []`, and a null-aware `chunk['choices']?[0]` does
/// not guard an *empty* list — it throws a `RangeError` that the stream loop's
/// shape-tolerant catch swallowed as a malformed chunk. Every OpenAI-family
/// streaming request lost its token usage that way, silently.
Map<String, dynamic>? firstChoice(Map<String, dynamic> chunk) {
  final choices = chunk['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  return first is Map ? first.cast<String, dynamic>() : null;
}

/// Result of separating inline `<think>…</think>` chain-of-thought from
/// model text.
class InlineThinkResult {
  final String text;
  final String? reasoning;
  const InlineThinkResult(this.text, this.reasoning);
}

/// Separates inline `<think>…</think>` spans from [raw].
///
/// Some ①-family compat endpoints (MiniMax by default, various relays fronting
/// DeepSeek-style models) put the chain of thought straight into `content` as
/// `<think>…</think>\n\n<answer>`. Any consumer that treats `content` as the
/// answer collects the thinking with it — into the transcript, into history
/// re-sent every turn, into compaction summaries. A trailing unterminated
/// `<think>` (truncated response) swallows the rest of the string as
/// reasoning rather than leaking it as text.
InlineThinkResult stripInlineThink(String raw) {
  if (!raw.contains('<think>')) return InlineThinkResult(raw, null);
  final reasoning = StringBuffer();
  final text = StringBuffer();
  int cursor = 0;
  while (true) {
    final open = raw.indexOf('<think>', cursor);
    if (open == -1) {
      text.write(raw.substring(cursor));
      break;
    }
    text.write(raw.substring(cursor, open));
    final close = raw.indexOf('</think>', open + 7);
    if (close == -1) {
      reasoning.write(raw.substring(open + 7));
      break;
    }
    reasoning.write(raw.substring(open + 7, close));
    cursor = close + 8;
  }
  final cleaned = text.toString().trimLeft();
  final thought = reasoning.toString().trim();
  return InlineThinkResult(cleaned, thought.isEmpty ? null : thought);
}

/// Cross-chunk `<think>` separator for the streaming path.
///
/// Tags arrive split across SSE chunks (`<thi` + `nk>` is normal), so a
/// per-chunk regex cannot work. The filter holds back the longest trailing
/// fragment that could still become a tag and classifies everything else as
/// text or reasoning as soon as its side of the tag boundary is known.
class InlineThinkStreamFilter {
  final StringBuffer _pending = StringBuffer();
  bool _inThink = false;

  static const String _openTag = '<think>';
  static const String _closeTag = '</think>';

  /// Feeds one delta; returns what can be classified so far.
  ({String text, String reasoning}) feed(String delta) {
    _pending.write(delta);
    final text = StringBuffer();
    final reasoning = StringBuffer();
    var buf = _pending.toString();
    _pending.clear();

    while (buf.isNotEmpty) {
      final tag = _inThink ? _closeTag : _openTag;
      final idx = buf.indexOf(tag);
      if (idx != -1) {
        (_inThink ? reasoning : text).write(buf.substring(0, idx));
        buf = buf.substring(idx + tag.length);
        _inThink = !_inThink;
        continue;
      }
      // No full tag: hold back a trailing partial-tag fragment, flush the rest.
      final hold = _partialTagSuffix(buf, tag);
      final flush = buf.substring(0, buf.length - hold);
      (_inThink ? reasoning : text).write(flush);
      _pending.write(buf.substring(buf.length - hold));
      buf = '';
    }
    return (text: text.toString(), reasoning: reasoning.toString());
  }

  /// Flushes whatever is still held back at stream end. An unterminated think
  /// span counts as reasoning, mirroring [stripInlineThink].
  ({String text, String reasoning}) flush() {
    final rest = _pending.toString();
    _pending.clear();
    if (rest.isEmpty) return (text: '', reasoning: '');
    return _inThink ? (text: '', reasoning: rest) : (text: rest, reasoning: '');
  }

  /// Length of the longest suffix of [buf] that is a proper prefix of [tag].
  static int _partialTagSuffix(String buf, String tag) {
    final maxLen = buf.length < tag.length - 1 ? buf.length : tag.length - 1;
    for (int len = maxLen; len > 0; len--) {
      if (tag.startsWith(buf.substring(buf.length - len))) return len;
    }
    return 0;
  }
}

/// Images carried by a structured (non-text) response field.
///
/// Relays disagree on how a generated image comes back. New API's own Gemini
/// adapter writes markdown `![image](data:…)` into `content`, which the text
/// scan handles; others use `images: [{image_url: {url}}]` or a bare
/// `image_data` base64 string. [urls] holds `http(s)` entries the caller must
/// still fetch — a relay backed by object storage returns a link rather than
/// the bytes, and dropping those was indistinguishable from generating nothing.
class StructuredImages {
  final List<Uint8List> bytes;
  final List<String> urls;
  const StructuredImages(this.bytes, this.urls);

  bool get isEmpty => bytes.isEmpty && urls.isEmpty;
}

/// Reads the structured image fields of a `message` (sync) or `delta`
/// (streaming) object. Unknown shapes contribute nothing.
StructuredImages extractStructuredImages(Map<String, dynamic> source) {
  final bytes = <Uint8List>[];
  final urls = <String>[];

  void addUrl(String url) {
    if (url.startsWith('data:image/')) {
      final comma = url.indexOf(',');
      if (comma == -1) return;
      try {
        bytes.add(base64Decode(url.substring(comma + 1)));
      } catch (_) {/* not decodable — nothing to add */}
    } else if (url.startsWith('http://') || url.startsWith('https://')) {
      urls.add(url);
    }
  }

  final imageData = source['image_data'];
  if (imageData is String && imageData.isNotEmpty) {
    try {
      bytes.add(base64Decode(imageData));
    } catch (_) {/* ignore */}
  }

  // `images: [{ image_url: { url: "data:…"|"http…" } }]`
  final imageList = source['images'];
  if (imageList is List) {
    for (final entry in imageList) {
      if (entry is! Map) continue;
      final urlField = entry['image_url'] is Map
          ? entry['image_url']['url']
          : (entry['image_url'] ?? entry['url']);
      if (urlField is String && urlField.isNotEmpty) addUrl(urlField);
      final b64 = entry['b64_json'];
      if (b64 is String && b64.isNotEmpty) {
        try {
          bytes.add(base64Decode(b64));
        } catch (_) {/* ignore */}
      }
    }
  }

  return StructuredImages(bytes, urls);
}

/// Image URLs a reply's *text* points at, in declaration order, deduplicated.
///
/// Two forms count as "this is the image you asked for":
///  * a markdown image link — `![image](https://…)`. New API's Gemini adapter
///    writes exactly this shape with a `data:` URI, and relays backed by
///    object storage write it with an `http(s)` link instead; the second kind
///    used to be dropped, so those relays produced a caption and no picture.
///  * a bare `storage.googleapis.com` link, the historical Gemini case.
///
/// A bare link to any other host is deliberately *not* fetched: a chat reply
/// that merely cites a URL must not cause the app to go download it.
List<String> imageUrlsInText(String text) {
  final urls = <String>{};
  for (final m in RegExp(r'!\[[^\]]*\]\((https?://[^\s)]+)\)').allMatches(text)) {
    urls.add(m.group(1)!);
  }
  for (final m
      in RegExp(r'https?://storage\.googleapis\.com/[^\s"\]\)]+').allMatches(text)) {
    urls.add(m.group(0)!);
  }
  return urls.toList();
}

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
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/chat/completions');
    logger?.call('Preparing OpenAI request to: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = _prepareChatPayload(target, history, options, isStreaming: false, tools: tools);
    if (payload.containsKey('safety_settings')) {
      logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');
    }

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      final appState = AppState();
      LLMDebugLog? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Standard)', {
          'url': redactUrl(url),
          'headers': headers,
          'body': payload,
        });
      }

      final response = await client.post(url, headers: headers, body: jsonEncode(payload));

      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Body: ${response.body}');
        await LLMDebugLogger.finish(debugFile);
      }

      logger?.call('Response received, parsing data...', level: 'DEBUG');
      // Status → JSON → shape → envelope, in that order (decodeJsonBody).
      final data = decodeJsonBody(response, apiName: 'OpenAI API');
      String text = "";
      List<Uint8List> images = [];
      final List<LLMToolCall> toolCalls = [];
      String? reasoningContent;
      String? reasoningFieldName;

      final choice = firstChoice(data);
      final rawMessage = choice?['message'];
      final message =
          rawMessage is Map ? rawMessage.cast<String, dynamic>() : null;
      if (message == null) {
        // Previously this fell through to an empty LLMResponse, which callers
        // (the assistant loop above all) read as "the model chose to say
        // nothing" — an expired key looked like a silent no-op.
        final body = response.body;
        throw Exception('OpenAI API returned no choices: '
            '${body.length > 500 ? '${body.substring(0, 500)}…' : body}');
      }
      {
        text = contentToText(message['content']);

        // ① family chain-of-thought: field-based (DeepSeek reasoning_content,
        // OpenRouter reasoning — no standard spelling exists, so probe the
        // known candidates and remember which one answered)...
        final rawReasoning = message['reasoning_content'] ?? message['reasoning'];
        if (rawReasoning is String && rawReasoning.isNotEmpty) {
          reasoningContent = rawReasoning;
          reasoningFieldName =
              message['reasoning_content'] != null ? 'reasoning_content' : 'reasoning';
        }
        // ...or inline <think> spans glued into content (MiniMax default).
        // Inline reasoning is display/accounting-only — it carries no echo
        // obligation, hence no field name.
        final inline = stripInlineThink(text);
        if (inline.reasoning != null) {
          text = inline.text;
          reasoningContent = reasoningContent == null
              ? inline.reasoning
              : '$reasoningContent\n${inline.reasoning}';
        }

        // Native tool/function calls.
        final rawToolCalls = message['tool_calls'];
        if (rawToolCalls is List) {
          for (int i = 0; i < rawToolCalls.length; i++) {
            final tc = rawToolCalls[i];
            final fn = tc is Map ? tc['function'] : null;
            if (fn is! Map) continue;
            final args = decodeToolArguments(fn['arguments'], logger: logger);
            toolCalls.add(LLMToolCall(
              id: resolveToolCallId(tc['id'], i),
              name: fn['name']?.toString() ?? '',
              arguments: args,
            ));
          }
          if (toolCalls.isNotEmpty) {
            logger?.call('Model requested ${toolCalls.length} tool call(s).', level: 'DEBUG');
          }
        }

        // Some OpenAI-compat relays expose images via a structured field.
        final structured = extractStructuredImages(message);
        images.addAll(structured.bytes);
        images.addAll(await _fetchImageUrls(structured.urls, config, logger));

        if (text.isNotEmpty) {
          logger?.call('Extracting images from text response...', level: 'DEBUG');
          final result = await _processTextAndExtractImages(text, config);
          text = result.text;
          images.addAll(result.images);
        }
      }

      logger?.call('Parse complete. Text length: ${text.length}, Images: ${images.length}', level: 'DEBUG');

      final metadata = <String, dynamic>{
        ...?(data['usage'] as Map?)?.cast<String, dynamic>(),
      };
      final finishReason = choice?['finish_reason'];
      if (finishReason != null) metadata['finish_reason'] = finishReason;

      return LLMResponse(
        text: text,
        generatedImages: images,
        metadata: metadata,
        reasoningContent: reasoningContent,
        reasoningFieldName: reasoningFieldName,
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

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async* {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/chat/completions');
    logger?.call('Starting OpenAI stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload =
        _prepareChatPayload(target, history, options, isStreaming: true, tools: tools);
    if (payload.containsKey('safety_settings')) {
      logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');
    }

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    final appState = AppState();
    LLMDebugLog? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Stream)', {
        'url': redactUrl(url),
        'headers': headers,
        'body': payload,
      });
    }

    final response = await client.send(request);

    if (response.statusCode != 200) {
      // Read unconditionally, not just for the debug log: the body carries
      // the provider's actual complaint, and draining it also settles the
      // pooled client's transfer count the moment it happens rather than at
      // the handle's close.
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
        await LLMDebugLogger.finish(debugFile);
      }
      logger?.call('Stream request failed with status: ${response.statusCode}', level: 'ERROR');
      client.close();
      throw LLMApiException(
          'OpenAI API Stream Request failed: ${response.statusCode} - '
          '${body.length > 500 ? '${body.substring(0, 500)}…' : body}',
          statusCode: response.statusCode);
    }

    logger?.call('Stream connection established, waiting for chunks...', level: 'DEBUG');

    if (debugFile != null) {
      await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
    }

    String accumulatedText = "";
    bool isLikelyBase64Stream = false;
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

    try {
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
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

        // Deliberately outside the shape-tolerant try below: an in-body error
        // event must terminate the stream as a failure, not be swallowed as
        // a malformed chunk (streaming.md §3.1/§3.2).
        throwIfEnvelopeError(chunkData);

        // Same: usage is the whole point of the choices-less tail chunk, so it
        // is read before any parsing that is allowed to fail.
        final usage = chunkData['usage'];
        if (usage is Map) usageMetadata = usage.cast<String, dynamic>();

        final choice = firstChoice(chunkData);
        if (choice == null) continue;
        final rawFinish = choice['finish_reason'];
        if (rawFinish is String && rawFinish.isNotEmpty) finishReason = rawFinish;

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
            // Keepalive. Fragments buffer silently until the flush after the
            // loop, but the consumer's idle guard resets only on chunks it
            // receives — a model answering with one long tool call and no
            // text would otherwise look like a dead connection at exactly
            // the moment it is delivering
            // (docs/plans/2026-08-assistant-timeout.md, the case streaming
            // tools exists to fix).
            yield LLMResponseChunk();
          }

          final structured = extractStructuredImages(delta);
          for (final img in structured.bytes) {
            yield LLMResponseChunk(imagePart: img);
          }
          for (final img in await _fetchImageUrls(structured.urls, config, logger)) {
            yield LLMResponseChunk(imagePart: img);
          }
        }

        try {
          // Same shape tolerance as the sync path — a delta carrying a content
          // array would otherwise throw into the catch below and be dropped as
          // "parse noise", losing the reply one chunk at a time.
          final text = contentToText(delta?['content']);
          final rawReasoningContent = delta?['reasoning_content'];
          final reasoning = rawReasoningContent ?? delta?['reasoning'];

          if (reasoning is String && reasoning.isNotEmpty) {
            // Dedicated channel: consumers that accumulate textPart into a
            // deliverable must never glue the thinking into it. The field
            // *name* rides along — same probe as the sync path — because a
            // tool-calling turn's replay must echo the reasoning under the
            // key it arrived with (reasoning.md §3), and the stream consumer
            // cannot recover the name from the text alone.
            yield LLMResponseChunk(
              reasoningPart: reasoning,
              reasoningFieldName: rawReasoningContent != null
                  ? 'reasoning_content'
                  : 'reasoning',
            );
          }

          if (text.isNotEmpty) {
            final split = thinkFilter.feed(text);
            if (split.reasoning.isNotEmpty) {
              yield LLMResponseChunk(reasoningPart: split.reasoning);
            }
            final cleanText = split.text;
            if (cleanText.isNotEmpty) {
              accumulatedText += cleanText;

              // Check if we are currently receiving a massive base64 string
              if (!isLikelyBase64Stream && accumulatedText.length > 500 && _isBase64Heuristic(accumulatedText)) {
                isLikelyBase64Stream = true;
              }

              // Only yield text to console if it doesn't look like raw image data
              if (!isLikelyBase64Stream && !_isBase64Heuristic(cleanText)) {
                yield LLMResponseChunk(textPart: cleanText);
              }
            }
          }

        } catch (e) {
          // Ignore parse errors
        }
      }

      final tail = thinkFilter.flush();
      if (tail.reasoning.isNotEmpty) {
        yield LLMResponseChunk(reasoningPart: tail.reasoning);
      }
      if (tail.text.isNotEmpty && !_isBase64Heuristic(tail.text)) {
        accumulatedText += tail.text;
        yield LLMResponseChunk(textPart: tail.text);
      }

      if (accumulatedText.isNotEmpty) {
        final result = await _processTextAndExtractImages(accumulatedText, config);
        // If the text was mostly images, don't yield the messy leftover text
        if (result.text.length < accumulatedText.length * 0.1 || _isBase64Heuristic(result.text)) {
          // Skip yielding textPart
        } else if (isLikelyBase64Stream) {
          // If we suppressed it during streaming but it turned out to have valid text, yield it now
          yield LLMResponseChunk(textPart: result.text);
        }

        for (var img in result.images) {
          yield LLMResponseChunk(imagePart: img);
        }
      }
    } finally {
      client.close();
      // In the finally so a stream that failed mid-flight still records how
      // long it ran before it did.
      await LLMDebugLogger.finish(debugFile);
    }

    // After the loop, never inside it: a call is whole only once the last
    // fragment has arrived, and [LLMResponseChunk.toolCallPart] promises
    // consumers they can act on whatever reaches them. Deliberately outside
    // the `finally` too — a stream that died mid-arguments must fail, not
    // deliver a half-built call.
    final assembled = streamedToolCalls.flush(logger: logger);
    if (assembled.isNotEmpty) {
      logger?.call('Model requested ${assembled.length} tool call(s).',
          level: 'DEBUG');
    }
    for (final call in assembled) {
      yield LLMResponseChunk(toolCallPart: call);
    }

    // Last, so it wins over any metadata attached to an earlier chunk. Without
    // it a streamed request recorded no token usage at all — the sync path's
    // `usage` + `finish_reason` are reported here in the same shape.
    if (usageMetadata != null) {
      yield LLMResponseChunk(metadata: {
        ...usageMetadata,
        'finish_reason': ?finishReason,
      });
    }

    yield LLMResponseChunk(isDone: true);
  }

  /// Downloads images a relay returned by reference rather than by value.
  /// A failed fetch is logged and skipped — one dead link must not lose the
  /// images that did arrive.
  Future<List<Uint8List>> _fetchImageUrls(
    List<String> urls,
    LLMModelConfig config,
    LLMLogger? logger,
  ) async {
    if (urls.isEmpty) return const [];
    final images = <Uint8List>[];
    final client = config.createClient();
    try {
      for (final url in urls) {
        try {
          final resp = await client.get(Uri.parse(url));
          if (resp.statusCode == 200) {
            images.add(resp.bodyBytes);
          } else {
            logger?.call('Image URL returned ${resp.statusCode}: $url', level: 'WARN');
          }
        } catch (e) {
          logger?.call('Failed to fetch image URL $url: $e', level: 'WARN');
        }
      }
    } finally {
      client.close();
    }
    return images;
  }

  bool _isBase64Heuristic(String text) {
    if (text.length < 64) return false;
    // Check if it contains data URI prefix
    if (text.contains('data:image/')) return true;
    // Check if it's a long string of base64 characters with no spaces
    return text.length > 200 && !text.contains(' ') && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(text.substring(0, 100));
  }

  Future<_TextProcessResult> _processTextAndExtractImages(String text, LLMModelConfig config) async {
    final List<Uint8List> images = [];
    String cleanText = text;
    final client = config.createClient();

    try {
      // 1. Extract and remove Inline Base64
      final base64Regex = RegExp(r'data:image/[^;]+;base64,([a-zA-Z0-9+/=]+)');
      final b64Matches = base64Regex.allMatches(text);
      for (var match in b64Matches) {
        try {
          images.add(base64Decode(match.group(1)!));
          cleanText = cleanText.replaceFirst(match.group(0)!, '[Image Data]');
        } catch (e) { /* ignore */ }
      }

      // 2. Fetch images the text points at rather than embeds.
      for (final url in imageUrlsInText(text)) {
        try {
          final response = await client.get(Uri.parse(url));
          if (response.statusCode == 200) {
            images.add(response.bodyBytes);
          }
        } catch (e) { /* ignore */ }
      }
    } finally {
      client.close();
    }

    return _TextProcessResult(cleanText.trim(), images);
  }

  /// Build a chat/completions payload for [target].
  Map<String, dynamic> _prepareChatPayload(
    LLMTarget target,
    List<LLMMessage> history,
    Map<String, dynamic>? options,
    {required bool isStreaming, List<LLMTool>? tools}
  ) {
    final messages = history.map((msg) {
      // Tool result message.
      if (msg.role == LLMRole.tool) {
        return {
          "role": "tool",
          "tool_call_id": msg.toolCallId,
          "content": msg.content,
        };
      }

      // Assistant message carrying tool calls.
      if (msg.role == LLMRole.assistant && msg.toolCalls.isNotEmpty) {
        return {
          "role": "assistant",
          "content": msg.content.isEmpty ? null : msg.content,
          // ① family echo-back obligation (reasoning.md §3): DeepSeek returns
          // 400 when a tool-calling assistant turn's reasoning is not
          // replayed. Echo under the exact field name it arrived with —
          // vendors that don't require it simply ignore the field. Inline
          // (<think>) reasoning has no field name and no obligation.
          if (msg.reasoningContent != null && msg.reasoningFieldName != null)
            msg.reasoningFieldName!: msg.reasoningContent,
          "tool_calls": msg.toolCalls.map((tc) => {
            "id": tc.id,
            "type": "function",
            "function": {
              "name": tc.name,
              "arguments": jsonEncode(tc.arguments),
            },
          }).toList(),
        };
      }

      dynamic content;

      if (msg.attachments.isEmpty) {
        content = msg.content;
      } else {
        final parts = <Map<String, dynamic>>[];
        if (msg.content.isNotEmpty) {
          parts.add({"type": "text", "text": msg.content});
        }
        for (var attachment in msg.attachments) {
          if (attachment.path == null && attachment.bytes == null) continue;
          final resolved = ImageCompressor.readForApi(attachment);
          parts.add({
            "type": "image_url",
            "image_url": {
              "url": "data:${resolved.mimeType};base64,${base64Encode(resolved.bytes)}"
            }
          });
        }
        content = parts;
      }

      return {
        "role": msg.role.name,
        "content": content
      };
    }).toList();

    final payload = <String, dynamic>{
      "model": target.config.modelId,
      "messages": messages,
      "stream": isStreaming,
      // Only when the user picked a level — default sends nothing (the
      // minimal-common-denominator rule: every proactively sent field is one
      // some relay can 400 on). `off` goes out as "none": an endpoint that
      // predates the value rejects it audibly, which beats thinking anyway.
      "reasoning_effort":
          ?openaiReasoningEffortWire(target.config.effectiveReasoningEffort),
    };

    if (tools != null && tools.isNotEmpty) {
      payload["tools"] = tools.map((t) => {
        "type": "function",
        "function": {
          "name": t.name,
          "description": t.description,
          "parameters": t.parameters,
        },
      }).toList();
      payload["tool_choice"] = "auto";
    }

    if (isStreaming) {
      payload["stream_options"] = {"include_usage": true};
    }

    // Only Gemini-served models (e.g. via New API or Google's OpenAI-compat
    // layer) understand these extensions. Native OpenAI must never receive
    // them. The flag comes from the model descriptor (layer 3).
    if (target.model.isGeminiFamily) {
      _applyGeminiCompatExtensions(payload, options);
    }

    return payload;
  }

  /// ①'s spelling of the app's reasoning vocabulary, or null for "send
  /// nothing". One translation table per family (playbook 03) — the app's
  /// own words never reach the wire.
  static String? openaiReasoningEffortWire(ReasoningEffort? effort) =>
      switch (effort) {
        null => null,
        ReasoningEffort.off => 'none',
        ReasoningEffort.low => 'low',
        ReasoningEffort.medium => 'medium',
        ReasoningEffort.high => 'high',
        ReasoningEffort.max => 'max',
      };

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
  }) =>
      _prepareChatPayload(target, history, options, isStreaming: isStreaming, tools: tools);

  /// Gemini-via-OpenAI compatibility extensions used by relay services.
  ///
  /// The aspect ratio and 1K/2K/4K size go out **twice**, because the two
  /// hosts that serve Gemini through an OpenAI-shaped surface read them from
  /// different places and neither complains about the other's spelling:
  ///
  ///  * New API only reads `extra_body.google.image_config`, and only its
  ///    `aspect_ratio` / `image_size` keys — it rejects the camelCase
  ///    spellings outright and ignores everything else, so the top-level
  ///    `image_config` this used to send alone was silently dropped and the
  ///    workbench's ratio and resolution controls did nothing.
  ///  * The top-level form is what other relays (and our own history) use, so
  ///    it stays.
  ///
  /// `modalities` and `safety_settings` are likewise ignored by New API — it
  /// derives `responseModalities` from the model name and takes safety
  /// thresholds from its own server-side config — but they are what other
  /// OpenAI-shaped Gemini hosts read, and an unknown field costs nothing.
  void _applyGeminiCompatExtensions(Map<String, dynamic> payload, Map<String, dynamic>? options) {
    payload["modalities"] = ["image", "text"];

    payload["safety_settings"] =
        SafetySettings.toApiList(options?[SafetySettings.paramKey]);

    if (options == null) return;

    // Only these two keys are portable; `person_generation` /
    // `number_of_images` belong to the top-level dialect alone.
    final portable = <String, dynamic>{};
    if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
      portable['aspect_ratio'] = options['aspectRatio'];
    }
    if (options.containsKey('imageSize')) {
      portable['image_size'] = options['imageSize'];
    }
    if (portable.isEmpty) return;

    payload["image_config"] = {
      'person_generation': 'allow_all',
      ...portable,
      'number_of_images': 1,
    };

    final extraBody = (payload['extra_body'] as Map<String, dynamic>?) ?? {};
    final google = (extraBody['google'] as Map<String, dynamic>?) ?? {};
    payload['extra_body'] = {
      ...extraBody,
      'google': {...google, 'image_config': portable},
    };
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

    final response = await http.get(url, headers: headers);

    final data = decodeJsonBody(response, apiName: 'OpenAI models');
    final rawModels = data['data'];
    final List<dynamic> modelsJson = rawModels is List ? rawModels : const [];

    return modelsJson.map((m) => DiscoveredModel(
      modelId: m['id']?.toString() ?? '',
      displayName: m['id']?.toString() ?? '',
      description: 'Owned by: ${m['owned_by'] ?? 'unknown'}',
      rawData: m as Map<String, dynamic>,
    )).toList();
  }
}
