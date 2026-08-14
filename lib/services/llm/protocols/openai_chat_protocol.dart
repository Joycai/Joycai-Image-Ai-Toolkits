import 'dart:convert';
import 'dart:io';

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

/// Throws when a 200 response body is actually an error envelope.
///
/// Compat layers deliver failures inside a successful HTTP response in at
/// least two spellings (streaming.md §3.1/§3.2): an `error` field (relays,
/// audits, quota), or MiniMax's `base_resp.status_code != 0` (auth 1004,
/// balance 1008, rate 1002, token limit 1039). A client that only checks the
/// HTTP status reads an expired key as a normal empty reply.
void throwIfEnvelopeError(Map<String, dynamic> data) {
  final err = data['error'];
  if (err != null) {
    final msg = err is Map ? (err['message'] ?? err.toString()) : err.toString();
    throw Exception('API error in response body: $msg');
  }
  final baseResp = data['base_resp'];
  if (baseResp is Map) {
    final code = baseResp['status_code'];
    if (code is num && code != 0) {
      throw Exception(
          'API error (base_resp $code): ${baseResp['status_msg'] ?? 'unknown'}');
    }
  }
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
    final url = Uri.parse('${config.endpoint}/chat/completions');
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
      File? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Standard)', {
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

      if (response.statusCode != 200) {
        logger?.call('Request failed with status: ${response.statusCode}', level: 'ERROR');
        throw Exception('OpenAI API Request failed: ${response.statusCode} - ${response.body}');
      }

      logger?.call('Response received, parsing data...', level: 'DEBUG');
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        // 200 does not mean success on compat layers — check both known
        // in-body error spellings before trusting the shape.
        throwIfEnvelopeError(data);
      }
      String text = "";
      List<Uint8List> images = [];
      final List<LLMToolCall> toolCalls = [];
      String? reasoningContent;
      String? reasoningFieldName;

      final choices = data['choices'];
      final choice = (choices is List && choices.isNotEmpty) ? choices[0] : null;
      final message = choice?['message'];
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
            Map<String, dynamic> args = {};
            final rawArgs = fn['arguments'];
            if (rawArgs is String && rawArgs.isNotEmpty) {
              try {
                final decoded = jsonDecode(rawArgs);
                if (decoded is Map<String, dynamic>) args = decoded;
              } catch (e) {
                final recovered = _recoverConcatenatedJsonObjects(rawArgs);
                if (recovered != null) {
                  args = recovered;
                  logger?.call(
                    'Tool call arguments were concatenated JSON objects '
                    '("$rawArgs") — recovered by merging them.',
                    level: 'WARN',
                  );
                } else {
                  logger?.call('Failed to decode tool call arguments: $e', level: 'WARN');
                }
              }
            } else if (rawArgs is Map<String, dynamic>) {
              args = rawArgs;
            }
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
        _extractStructuredImages(message, images);

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

  @override
  Stream<LLMResponseChunk> generateStream(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async* {
    final config = target.config;
    final url = Uri.parse('${config.endpoint}/chat/completions');
    logger?.call('Starting OpenAI stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = _prepareChatPayload(target, history, options, isStreaming: true);
    if (payload.containsKey('safety_settings')) {
      logger?.call('Safety settings: ${SafetySettings.describe(options?[SafetySettings.paramKey])}', level: 'DEBUG');
    }

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    final appState = AppState();
    File? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'OpenAI (Stream)', {
        'url': url.toString(),
        'headers': headers,
        'body': payload,
      });
    }

    final response = await client.send(request);

    if (response.statusCode != 200) {
      if (debugFile != null) {
        final body = await response.stream.bytesToString();
        await LLMDebugLogger.appendLine(debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
      }
      logger?.call('Stream request failed with status: ${response.statusCode}', level: 'ERROR');
      client.close();
      throw Exception('OpenAI API Stream Request failed: ${response.statusCode}');
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

    try {
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (debugFile != null && line.isNotEmpty) {
          await LLMDebugLogger.appendLine(debugFile, line);
        }
        if (line.isEmpty || line == 'data: [DONE]') continue;

        String dataLine = line;
        if (line.startsWith('data: ')) {
          dataLine = line.substring(6);
        }

        Map<String, dynamic>? chunkData;
        try {
          final decoded = jsonDecode(dataLine);
          if (decoded is Map<String, dynamic>) chunkData = decoded;
        } catch (_) {
          continue; // Non-JSON SSE noise (comments, keep-alives).
        }
        if (chunkData == null) continue;

        // Deliberately outside the shape-tolerant try below: an in-body error
        // event must terminate the stream as a failure, not be swallowed as
        // a malformed chunk (streaming.md §3.1/§3.2).
        throwIfEnvelopeError(chunkData);

        try {
          final choice = chunkData['choices']?[0];
          if (choice == null) {
            if (chunkData['usage'] != null) {
              yield LLMResponseChunk(metadata: chunkData['usage']);
            }
            continue;
          }

          final delta = choice['delta'];
          // Same shape tolerance as the sync path — a delta carrying a content
          // array would otherwise throw into the catch below and be dropped as
          // "parse noise", losing the reply one chunk at a time.
          final text = contentToText(delta?['content']);
          final reasoning = delta?['reasoning_content'] ?? delta?['reasoning'];
          final imageData = delta?['image_data'];

          if (reasoning is String && reasoning.isNotEmpty) {
            // Dedicated channel: consumers that accumulate textPart into a
            // deliverable must never glue the thinking into it.
            yield LLMResponseChunk(reasoningPart: reasoning);
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

          if (imageData != null) {
            yield LLMResponseChunk(
              imagePart: base64Decode(imageData),
              metadata: chunkData['usage'],
            );
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
    }

    yield LLMResponseChunk(isDone: true);
  }

  /// Pull images out of structured (non-text) response fields used by some
  /// OpenAI-compatible relays.
  void _extractStructuredImages(Map<String, dynamic> message, List<Uint8List> images) {
    final imageData = message['image_data'];
    if (imageData is String && imageData.isNotEmpty) {
      try {
        images.add(base64Decode(imageData));
      } catch (_) {/* ignore */}
    }

    // `images: [{ image_url: { url: "data:..."|"http..." } }]`
    final imageList = message['images'];
    if (imageList is List) {
      for (final entry in imageList) {
        final urlField = entry is Map ? (entry['image_url']?['url'] ?? entry['url']) : null;
        if (urlField is String && urlField.startsWith('data:image/')) {
          final comma = urlField.indexOf(',');
          if (comma != -1) {
            try {
              images.add(base64Decode(urlField.substring(comma + 1)));
            } catch (_) {/* ignore */}
          }
        }
      }
    }
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

      // 2. Extract Cloud URLs
      final urlRegex = RegExp(r'(https?://storage\.googleapis\.com/[^\s"\]\)]+)');
      final urlMatches = urlRegex.allMatches(text);
      for (var match in urlMatches) {
        try {
          final url = match.group(1)!;
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
  void _applyGeminiCompatExtensions(Map<String, dynamic> payload, Map<String, dynamic>? options) {
    payload["modalities"] = ["image", "text"];

    payload["safety_settings"] =
        SafetySettings.toApiList(options?[SafetySettings.paramKey]);

    if (options != null) {
      final imageConfig = <String, dynamic>{};
      imageConfig['person_generation'] = 'allow_all';
      if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
        imageConfig['aspect_ratio'] = options['aspectRatio'];
      }
      if (options.containsKey('imageSize')) {
        imageConfig['image_size'] = options['imageSize'];
      }
      if (imageConfig.isNotEmpty) {
        imageConfig['number_of_images'] = 1;
        payload["image_config"] = imageConfig;
      }
    }
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

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch OpenAI models: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> modelsJson = data['data'] ?? [];

    return modelsJson.map((m) => DiscoveredModel(
      modelId: m['id']?.toString() ?? '',
      displayName: m['id']?.toString() ?? '',
      description: 'Owned by: ${m['owned_by'] ?? 'unknown'}',
      rawData: m as Map<String, dynamic>,
    )).toList();
  }
}
