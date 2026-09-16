import 'dart:convert';

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

/// The first reasoning field of a `message` / `delta` that carries text, with
/// the field's name, or null when none does.
///
/// ① has no standard spelling (DeepSeek `reasoning_content`, OpenRouter
/// `reasoning`), so the known candidates are probed in order — and "carries
/// text" is the test, not "present": `reasoning_content ?? reasoning` picked
/// a relay's empty `reasoning_content: ""` over a non-empty `reasoning`,
/// dropping the thought and remembering the wrong key for the echo.
({String text, String field})? pickReasoningField(
  Map<String, dynamic> source,
) {
  for (final field in const ['reasoning_content', 'reasoning']) {
    final value = source[field];
    if (value is String && value.isNotEmpty) return (text: value, field: field);
  }
  return null;
}

/// A ① `usage` block in the shape `LLMService` reads, or null when [raw] is
/// not one.
///
/// DeepSeek reports cache hits as top-level `prompt_cache_hit_tokens` rather
/// than `prompt_tokens_details.cached_tokens`, the one spelling the usage
/// recorder reads for ① — so every hit was recorded as full-price input. Its
/// `prompt_tokens` already includes the hits, so the count is republished
/// under the OpenAI spelling when the host did not send one; the raw fields
/// ride along untouched.
Map<String, dynamic>? normalizeOpenAIUsage(Object? raw) {
  if (raw is! Map) return null;
  final usage = raw.cast<String, dynamic>();
  final hits = usage['prompt_cache_hit_tokens'];
  final details = usage['prompt_tokens_details'];
  final hasCached = details is Map && details['cached_tokens'] != null;
  if (hits is! num || hasCached) return usage;
  return {
    ...usage,
    'prompt_tokens_details': {
      if (details is Map) ...details.cast<String, dynamic>(),
      'cached_tokens': hits,
    },
  };
}
