import 'dart:convert';
import 'dart:io';

import '../../../core/safety_settings.dart';
import '../image_compression.dart';
import '../llm_types.dart';
import '../model_descriptor.dart' show GeminiThinkingGeneration;
import 'protocol.dart' show upstreamUsage;

/// ③'s `thinkingBudget` for each rung on a [GeminiThinkingGeneration.budget]
/// model (Gemini 2.5). Off is `0`; High is 24576, the Flash / Flash-Lite
/// ceiling and inside Pro's; Max has nowhere further to go on every 2.5
/// model at once and is sent as High. No clamp against `maxOutputTokens`:
/// this wire never sends one.
const Map<ReasoningEffort, int> geminiThinkingBudgets = {
  ReasoningEffort.off: 0,
  ReasoningEffort.low: 1024,
  ReasoningEffort.medium: 8192,
  ReasoningEffort.high: 24576,
  ReasoningEffort.max: 24576,
};

/// `generationConfig.thinkingConfig` for [effort] on a model of
/// [generation], or null for "send nothing" (reasoning 03 §2).
///
/// * Default (null) and [GeminiThinkingGeneration.none] send nothing — the
///   request stays byte-identical to one built before this existed.
/// * [GeminiThinkingGeneration.level] (Gemini 3+): the UPPERCASE enum.
///   Off is `MINIMAL` — ③ cannot turn thinking off, and the models without
///   `MINIMAL` (Gemini 3.1 Pro) answer it with an error, which is the
///   endpoint's own statement and stays audible. Max is `HIGH`, the top of
///   the enum.
/// * [GeminiThinkingGeneration.budget] (Gemini 2.5): [geminiThinkingBudgets].
///   Off is `0`, which 2.5 Pro (it cannot stop thinking) rejects audibly.
///
/// Only one generation's field is ever present, and it always travels with
/// `includeThoughts: true`: the thinking runs and bills either way, and
/// without it official Gemini returns no thought parts at all.
Map<String, dynamic>? geminiThinkingConfig(
  GeminiThinkingGeneration generation,
  ReasoningEffort? effort,
) {
  if (effort == null) return null;
  switch (generation) {
    case GeminiThinkingGeneration.none:
      return null;
    case GeminiThinkingGeneration.level:
      return {
        'thinkingLevel': switch (effort) {
          ReasoningEffort.off => 'MINIMAL',
          ReasoningEffort.low => 'LOW',
          ReasoningEffort.medium => 'MEDIUM',
          ReasoningEffort.high || ReasoningEffort.max => 'HIGH',
        },
        'includeThoughts': true,
      };
    case GeminiThinkingGeneration.budget:
      return {'thinkingBudget': geminiThinkingBudgets[effort], 'includeThoughts': true};
  }
}

/// Pure request-payload builders and response parsing for the Gemini wire
/// format (layer 1). Isolated from network orchestration so the logic can be
/// unit-tested directly.

/// Recursively strips large base64 `data` fields so payloads are safe to log.
Map<String, dynamic> getSafePayload(Map<String, dynamic> payload) {
  final Map<String, dynamic> safe = {};
  payload.forEach((key, value) {
    if ((key == 'data' || key == 'bytesBase64Encoded') && value is String && value.length > 100) {
      safe[key] = '<BASE64_DATA (${value.length} chars)>';
    } else if (value is Map<String, dynamic>) {
      safe[key] = getSafePayload(value);
    } else if (value is List) {
      safe[key] = value.map((e) => e is Map<String, dynamic> ? getSafePayload(e) : e).toList();
    } else {
      safe[key] = value;
    }
  });
  return safe;
}

/// Imagen `:predict` request body (text-to-image only).
Map<String, dynamic> prepareImagenPayload(List<LLMMessage> history, Map<String, dynamic>? options) {
  final userMsg = history.lastWhere((m) => m.role == LLMRole.user, orElse: () => history.last);

  final parameters = <String, dynamic>{'sampleCount': 1, 'personGeneration': 'allow_all'};
  if (options != null) {
    if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
      parameters['aspectRatio'] = options['aspectRatio'];
    }
    final size = options['imageSize'];
    if (size is String && size.isNotEmpty && size != 'not_set') {
      parameters['sampleImageSize'] = size;
    }
  }

  return {
    'instances': [
      {'prompt': userMsg.content},
    ],
    'parameters': parameters,
  };
}

/// Veo `:predictLongRunning` request body, including first/last frame and asset
/// reference images.
/// How many images a Veo payload from [prepareVeoPayload] carries: the
/// first frame (`image`), the last frame (`lastFrame`) and every entry of
/// `referenceImages` — what the submit publishes as its input count.
int veoInputImages(Map<String, dynamic> payload) {
  final instances = payload['instances'];
  if (instances is! List || instances.isEmpty) return 0;
  final instance = instances.first;
  if (instance is! Map) return 0;
  final references = instance['referenceImages'];
  return (instance['image'] is Map ? 1 : 0) +
      (instance['lastFrame'] is Map ? 1 : 0) +
      (references is List ? references.length : 0);
}

Map<String, dynamic> prepareVeoPayload(List<LLMMessage> history, Map<String, dynamic>? options) {
  final userMsg = history.lastWhere((m) => m.role == LLMRole.user);

  final instance = <String, dynamic>{'prompt': userMsg.content};

  final referenceImages = <Map<String, dynamic>>[];

  for (final attachment in userMsg.attachments) {
    String? b64Data;
    if (attachment.path != null) {
      b64Data = base64Encode(File(attachment.path!).readAsBytesSync());
    } else if (attachment.bytes != null) {
      b64Data = base64Encode(attachment.bytes!);
    }

    if (b64Data != null) {
      // // Some Google REST APIs (like Veo in Google AI Studio) expect fields directly,
      // // without the 'inline_data' or 'inlineData' wrapper.
      // // We'll use snake_case for mime_type as it's common in generativelanguage REST.
      // final mediaData = {
      //   "inlineData": {
      //     "mimeType": attachment.mimeType,
      //     "data": b64Data
      //   }
      // };

      // Google Gen API doc is wrong, this code is get from ai studio, fuck google
      final mediaDataLegacy = {'mimeType': attachment.mimeType, 'bytesBase64Encoded': b64Data};

      switch (attachment.referenceType) {
        case LLMReferenceType.firstFrame:
          instance['image'] = mediaDataLegacy;
        case LLMReferenceType.lastFrame:
          instance['lastFrame'] = mediaDataLegacy;
        case LLMReferenceType.asset:
          referenceImages.add({'image': mediaDataLegacy, 'referenceType': 'asset'});
        default:
          referenceImages.add({'image': mediaDataLegacy, 'referenceType': 'asset'});
      }
    }
  }

  if (referenceImages.isNotEmpty) {
    instance['referenceImages'] = referenceImages;
  }

  final parameters = <String, dynamic>{};
  if (options != null) {
    // Keep parameters as camelCase for now as per LRO standard,
    // but switch if errors persist.
    if (options.containsKey('resolution')) parameters['resolution'] = options['resolution'];
    if (options.containsKey('aspectRatio')) parameters['aspectRatio'] = options['aspectRatio'];
  }

  return {
    'instances': [instance],
    if (parameters.isNotEmpty) 'parameters': parameters,
  };
}

/// Finish reasons that mean the model was stopped by a policy rather than by
/// running out of things to say.
///
/// `IMAGE_SAFETY` and `PROHIBITED_CONTENT` are the two the image models
/// actually return; both used to fall through the `SAFETY`/`RECITATION`
/// comparison and be logged at INFO, which is the level a successful request
/// uses. `MAX_TOKENS` is deliberately absent — a truncated answer is still an
/// answer.
const Set<String> blockingFinishReasons = {
  'SAFETY',
  'IMAGE_SAFETY',
  'RECITATION',
  'BLOCKLIST',
  'PROHIBITED_CONTENT',
  'SPII',
  // The image models' own spellings of the same two blocks.
  'IMAGE_PROHIBITED_CONTENT',
  'IMAGE_RECITATION',
};

/// Finish reasons that mean the model's *thinking* protocol was broken by the
/// request rather than by content: a replayed turn missing its
/// `thoughtSignature`, a tool called that was never declared, too many tool
/// calls in a row. None of them is a policy block and none is a normal end,
/// and all three used to be logged at INFO and read as a short, complete
/// answer. The signature one is the ③-shaped replay failure: not a 400, not a
/// silent downgrade, but a third form — a successful response that stopped
/// for this reason.
const Set<String> protocolFinishReasons = {
  'MISSING_THOUGHT_SIGNATURE',
  'UNEXPECTED_TOOL_CALL',
  'TOO_MANY_TOOL_CALLS',
  'MALFORMED_FUNCTION_CALL',
  'MALFORMED_RESPONSE',
};

/// ③'s `finishReason` in ①'s `finish_reason` vocabulary, the one every
/// consumer of `metadata['finish_reason']` speaks: the assistant loop and the
/// web scraper both check `== 'length'` for truncation, and until this
/// existed ③ never published anything there — a truncated Gemini answer was
/// indistinguishable from a complete one. The ④ twin is
/// `anthropicFinishReason`.
String? geminiFinishReason(String? finishReason) {
  switch (finishReason) {
    case null:
      return null;
    case 'STOP':
      return 'stop';
    case 'MAX_TOKENS':
      return 'length';
    case 'SAFETY':
    case 'IMAGE_SAFETY':
    case 'RECITATION':
    case 'BLOCKLIST':
    case 'PROHIBITED_CONTENT':
    case 'SPII':
    case 'IMAGE_PROHIBITED_CONTENT':
    case 'IMAGE_RECITATION':
      return 'content_filter';
    default:
      // FINISH_REASON_UNSPECIFIED, OTHER, LANGUAGE, and the protocol ones
      // above: the turn ended and nothing in ①'s ladder describes why. The
      // raw value rides along as `finish_reason_raw`.
      return 'stop';
  }
}

/// The failure a finished Gemini response stands for when it carried no
/// output at all (no text, thinking, image or call) and ended for a reason
/// other than `STOP` / `MAX_TOKENS` — or null.
///
/// `OTHER`, `LANGUAGE`, `NO_IMAGE`, `IMAGE_OTHER`, `MALFORMED_RESPONSE`, a
/// missing thought signature: [geminiFinishReason] has no ① word for these
/// and publishes `stop`, so an empty candidate that ended this way used to
/// reach the caller as a successful empty reply — an image task with no
/// image, a refine that returned nothing. Typed and non-retryable (no status
/// code): the same request meets the same end, and every attempt is billed.
/// A content-filter end is left to LLMService's single check.
LLMApiException? geminiEmptyEndFailure(Map<String, dynamic>? metadata, {required bool sawOutput}) {
  if (sawOutput || metadata == null) return null;
  final raw = metadata['finish_reason_raw'];
  if (raw is! String || raw == 'STOP' || raw == 'MAX_TOKENS') return null;
  // Any content block — a candidate's own reason, or a prompt-level block
  // whose `blockReason` (OTHER, BLOCK_REASON_UNSPECIFIED…) rides as the raw
  // value — is LLMService's to fail, after it records the usage.
  if (blockingFinishReasons.contains(raw) ||
      metadata['finish_reason'] == contentFilterFinishReason) {
    return null;
  }
  return LLMApiException(
    'Google GenAI ended the generation with finishReason $raw and no content'
    '${raw == 'MISSING_THOUGHT_SIGNATURE' ? ' — a replayed tool-calling turn lacked its thoughtSignature' : ''}.',
  );
}

/// Call ids for the `functionCall`s of one response.
///
/// ③ supplies no call id, and the agent loop pairs every result with its call
/// by id — so a synthesized id has to be unique across the conversation, not
/// just within one candidate. The old `call_<name>_<index>` restarted its
/// index per candidate per chunk: a streamed turn could name two different
/// calls `call_read_0`, and the next turn reused the same id for a third
/// (protocol 02 §3.2, tools 05 §3).
///
/// One instance per response — a stream holds it across its chunks — built
/// from a per-instance nonce (clock plus a process-wide counter, so two
/// instances created in the same microsecond still differ) and a monotonic
/// counter within it: `gtc_<nonce>_<n>`.
class GeminiToolCallIds {
  static int _instances = 0;
  final String _nonce;
  int _next = 0;

  GeminiToolCallIds()
    : _nonce =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '${(_instances++).toRadixString(36)}';

  /// The next unused id of this response.
  String next() => 'gtc_${_nonce}_${_next++}';
}

/// Collects a ③ model turn's `parts` verbatim — the carrier behind
/// [LLMMessage.rawModelParts].
///
/// Fed every decoded chunk of a stream in order (or the single body of a
/// synchronous response). Each ③ chunk is a complete JSON object carrying
/// whole parts, so collecting them in arrival order *is* the turn: a text
/// part split across chunks stays as several text parts, and a
/// `thoughtSignature` that arrives on an empty trailing text part is kept
/// where it came. Only the first candidate is read — the one every consumer
/// of this wire uses.
///
/// [toolTurnParts] answers only for a turn that called a function: a turn
/// without calls carries no replay obligation, and keeping its parts would
/// re-send them as input for nothing (reasoning 03 §5 rule 1).
class GeminiModelPartsCollector {
  final List<Map<String, dynamic>> _parts = [];
  bool _sawCall = false;

  void feed(Map<String, dynamic> chunkData) {
    final candidates = chunkData['candidates'];
    if (candidates is! List || candidates.isEmpty) return;
    final first = candidates.first;
    if (first is! Map) return;
    final content = first['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) return;
    for (final part in parts) {
      if (part is! Map) continue;
      final copy = Map<String, dynamic>.from(part);
      if (copy.containsKey('functionCall') || copy.containsKey('function_call')) {
        _sawCall = true;
      }
      _parts.add(copy);
    }
  }

  /// The turn's parts when it called a tool, else null.
  List<Map<String, dynamic>>? get toolTurnParts =>
      _sawCall && _parts.isNotEmpty ? List.of(_parts) : null;
}

/// Parses one `generateContent`/stream chunk into [LLMResponseChunk]s, handling
/// prompt blocking, finish reasons and safety ratings via [logger].
///
/// `metadata` carries `usageMetadata` through [upstreamUsage] (the app's two
/// reserved keys removed, the rest as sent) plus, on the chunk that ends the
/// candidate, `finish_reason` (①'s vocabulary) and `finish_reason_raw` (③'s).
/// Text parts flagged `thought: true` go out as reasoning, never as text.
///
/// [callIds] synthesizes the ids of any `functionCall` parts. A stream passes
/// one instance for all of its chunks; left null, the chunk gets a fresh one,
/// which is right for a synchronous response — that is one chunk.
Iterable<LLMResponseChunk> parseGoogleChunks(
  Map<String, dynamic> chunkData, {
  Function(String, {String level})? logger,
  GeminiToolCallIds? callIds,
}) sync* {
  final ids = callIds ?? GeminiToolCallIds();
  final rawUsage = chunkData['usageMetadata'];
  Map<String, dynamic>? metadata = rawUsage is Map ? upstreamUsage(rawUsage) : null;

  // Prompt-level block (e.g. prohibited content). Published, not thrown:
  // the one content-filter check lives in LLMService
  // ([contentBlockedFailure]), after the usage this request was billed for
  // has been recorded — a throw from here reached the caller before that.
  final feedback = chunkData['promptFeedback'];
  if (feedback is Map && feedback['blockReason'] != null) {
    final blockReason = feedback['blockReason'].toString();
    logger?.call('Google GenAI Blocked: $blockReason', level: 'ERROR');
    yield LLMResponseChunk(
      metadata: {
        ...?metadata,
        'finish_reason_raw': blockReason,
        'finish_reason': contentFilterFinishReason,
      },
    );
    return;
  }

  final candidates = chunkData['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) {
    if (metadata != null) {
      yield LLMResponseChunk(metadata: metadata);
    }
    return;
  }

  for (final candidate in candidates) {
    final finishReason = candidate['finishReason'] as String?;
    final parts = candidate['content']?['parts'] as List?;

    // The finish reason travels with the usage so a consumer that keeps the
    // last metadata it sees ends up with both — on a stream that is the
    // final chunk, which is also where the usage totals settle.
    if (finishReason != null) {
      metadata = {
        ...?metadata,
        'finish_reason_raw': finishReason,
        'finish_reason': ?geminiFinishReason(finishReason),
      };
    }

    // Handle Safety and other non-STOP reasons (Section 3.3)
    if (finishReason != null && finishReason != 'STOP') {
      final blocked = blockingFinishReasons.contains(finishReason);
      final protocol = protocolFinishReasons.contains(finishReason);
      String level = 'INFO';
      if (blocked || protocol) level = 'WARN';
      if (finishReason == 'OTHER') level = 'ERROR';

      logger?.call('Generation finished with reason: $finishReason', level: level);
      if (finishReason == 'MISSING_THOUGHT_SIGNATURE') {
        logger?.call(
          'A replayed turn lacked its thoughtSignature — multi-turn tool '
          'calling has stopped working for this conversation.',
          level: 'WARN',
        );
      }

      if (blocked) {
        logger?.call('Content was flagged by safety filters.', level: 'WARN');
        if (candidate['safetyRatings'] != null) {
          final ratings = candidate['safetyRatings'] as List;
          for (final r in ratings) {
            if (r['probability'] != 'NEGLIGIBLE') {
              logger?.call('Safety: ${r['category']} is ${r['probability']}', level: 'DEBUG');
            }
          }
        }
      }

      // A policy block is a failure whether or not text arrived first — it
      // used to throw only when the candidate was empty, so a block landing
      // after streamed text was kept as a successful short answer. It is
      // published as `finish_reason: content_filter` (above) and failed by
      // LLMService's single check, which records the billed usage first.
      //
      // Every other abnormal end fails only when the *whole* response said
      // nothing — judged once at its end by [geminiEmptyEndFailure], not per
      // chunk: on a stream the finish reason rides the last chunk, whose
      // parts are often empty after the text already arrived.
    }

    if (parts == null || parts.isEmpty) {
      // Nothing to say, but the finish reason (and usage) still has to reach
      // the consumer — a MAX_TOKENS with an empty candidate is how a request
      // whose budget went entirely to thinking looks.
      if (metadata != null) yield LLMResponseChunk(metadata: metadata);
      continue;
    }

    {
      for (final part in parts) {
        final rawText = part['text'] as String?;
        // A `thought: true` part is the model's reasoning summary
        // (`includeThoughts`), not its answer. Its own channel, like ①'s
        // reasoning_content and ④'s thinking block — glued into the text it
        // would reach the deliverable.
        final isThought = part['thought'] == true;
        final textPart = isThought ? null : rawText;
        final reasoningPart = isThought ? rawText : null;

        // Spec prioritizes inlineData (Section 2)
        final inlineData = part['inlineData'] ?? part['inline_data'];
        final imgData = inlineData?['data'];

        // Native function calling. Google supplies no call id — synthesize
        // one that is unique across the stream and the conversation
        // ([GeminiToolCallIds]).
        LLMToolCall? toolCall;
        final functionCall = part['functionCall'] ?? part['function_call'];
        if (functionCall is Map) {
          final args = functionCall['args'];
          toolCall = LLMToolCall(
            id: ids.next(),
            name: functionCall['name']?.toString() ?? '',
            arguments: args is Map<String, dynamic> ? args : {},
            thoughtSignature: (part['thoughtSignature'] ?? part['thought_signature'])?.toString(),
          );
          logger?.call('Model requested tool call: ${toolCall.name}', level: 'DEBUG');
        }

        yield LLMResponseChunk(
          textPart: textPart,
          reasoningPart: reasoningPart,
          imagePart: imgData != null ? base64Decode(imgData as String) : null,
          toolCallPart: toolCall,
          metadata: metadata,
        );
      }
    }
  }
}

/// Standard `:generateContent` request body: system instruction, multimodal
/// contents, image-generation config and per-request safety settings (from
/// `options['safetySettings']`, defaulting to BLOCK_NONE for all categories).
///
/// Every structural key is spelled **camelCase**. Google accepts snake_case
/// too, but the relays that host this wire do not — and an unknown key is
/// ignored, not rejected, so the snake_case spelling fails by making the
/// image or the system prompt vanish from the request while everything else
/// works. `test/services/llm/image_relay_compat_test.dart` walks the payload for any key
/// carrying an underscore.
///
/// [emitsImages] declares `responseModalities: ["TEXT","IMAGE"]`. It comes
/// from the model descriptor's capabilities, never from the model id — this
/// layer must not sniff. Nothing else supplies it: a relay only injects the
/// modalities when it is *translating* an OpenAI-shaped request, so on the
/// native surface the field is ours to send or the model answers in text
/// only — silently, for the models that need it declared.
///
/// [modelId] is the model the request goes to. A replayed call's
/// `thoughtSignature` is echoed only to the model that produced it, or when
/// no producer was recorded (reasoning 03 §5 rule 2).
Map<String, dynamic> prepareGooglePayload(
  List<LLMMessage> history,
  Map<String, dynamic>? options,
  String? endpoint, {
  List<LLMTool>? tools,
  bool emitsImages = false,
  String? modelId,
  GeminiThinkingGeneration thinking = GeminiThinkingGeneration.none,
  ReasoningEffort? reasoningEffort,

  /// The cap already ranked by `outputCapFor` — this builder has no target
  /// of its own. Falls back to the raw option so a caller without a target
  /// (the probe's test, the scraper) keeps its cap.
  int? outputCap,
}) {
  final systemMessages = history.where((m) => m.role == LLMRole.system).toList();
  final conversationMessages = history.where((m) => m.role != LLMRole.system).toList();

  Map<String, dynamic>? systemInstruction;
  if (systemMessages.isNotEmpty) {
    systemInstruction = {
      'parts': systemMessages.map((m) => {'text': m.content}).toList(),
    };
  }

  // The tool name behind each call id. ③ pairs a result with its call by
  // *name* — the protocol has no call id — so a result persisted without its
  // tool name takes the name of the call it answers rather than going out as
  // "" (protocol 02 §2.2).
  final callNames = <String, String>{
    for (final m in conversationMessages)
      for (final tc in m.toolCalls)
        if (tc.name.isNotEmpty) tc.id: tc.name,
  };

  final contents = <Map<String, dynamic>>[];
  // Whether the last content is a batch of function results that the next
  // result joins.
  var lastIsResults = false;

  for (final msg in conversationMessages) {
    // Tool result message → functionResponse part (role "user" per the
    // Gemini REST function-calling contract). Consecutive results share one
    // user content: a batch of parallel calls is answered by one turn, not N
    // user turns in a row. Anything else that follows — the assistant's
    // `[view_image result]` message with its picture — stays its own turn.
    if (msg.role == LLMRole.tool) {
      Map<String, dynamic> responsePayload;
      try {
        final decoded = jsonDecode(msg.content);
        responsePayload = decoded is Map<String, dynamic> ? decoded : {'result': decoded};
      } catch (_) {
        responsePayload = {'result': msg.content};
      }
      final toolName = msg.toolName;
      final part = <String, dynamic>{
        'functionResponse': {
          'name': (toolName != null && toolName.isNotEmpty)
              ? toolName
              : (callNames[msg.toolCallId] ?? ''),
          'response': responsePayload,
        },
      };
      if (lastIsResults) {
        (contents.last['parts'] as List).add(part);
      } else {
        contents.add({
          'role': 'user',
          'parts': [part],
        });
        lastIsResults = true;
      }
      continue;
    }

    final parts = <Map<String, dynamic>>[];

    // A tool-calling model turn goes back as the parts it arrived as, when
    // the model it goes to is the one that produced them (protocol 02 §2.2
    // rule 3, reasoning 03 §5): thought parts, every signature, the order.
    // "Understand and rebuild" keeps only the signatures on functionCall
    // parts, and ③ answers the gap with MISSING_THOUGHT_SIGNATURE. A copy, so
    // nothing downstream of the payload can write into stored history.
    final raw = msg.rawModelParts;
    final replayRaw =
        msg.role == LLMRole.assistant &&
        msg.toolCalls.isNotEmpty &&
        raw != null &&
        raw.isNotEmpty &&
        (modelId == null || msg.rawThinkingModelId == modelId);
    if (replayRaw) {
      for (final part in raw) {
        parts.add((jsonDecode(jsonEncode(part)) as Map).cast<String, dynamic>());
      }
    } else {
      if (msg.content.isNotEmpty) {
        parts.add({'text': msg.content});
      }

      // Rebuilt: assistant tool calls → functionCall parts. Gemini requires
      // the thoughtSignature captured from the original response to be
      // replayed verbatim on the same part.
      for (final tc in msg.toolCalls) {
        parts.add({
          'functionCall': {'name': tc.name, 'args': tc.arguments},
          // Only to the model that produced it: another model has no use
          // for the signature and it still travels as input.
          if (tc.thoughtSignature != null &&
              (msg.rawThinkingModelId == null ||
                  modelId == null ||
                  msg.rawThinkingModelId == modelId))
            'thoughtSignature': tc.thoughtSignature,
        });
      }
    }

    for (final attachment in msg.attachments) {
      if (attachment.path == null && attachment.bytes == null) continue;
      final resolved = ImageCompressor.readForApi(attachment);
      // camelCase, never snake_case. Google's own host accepts both (proto3
      // JSON), but the relays that front this wire (New API's Gemini face)
      // document only the camelCase spelling and *ignore* unrecognized keys
      // rather than rejecting them — so `inline_data` used to mean the model
      // never saw the picture, with a 200 and a perfectly normal answer.
      parts.add({
        'inlineData': {'mimeType': resolved.mimeType, 'data': base64Encode(resolved.bytes)},
      });
    }

    // An empty `parts` array is rejected. A turn that produced nothing — an
    // assistant message with neither text nor calls — is simply not sent.
    if (parts.isEmpty) continue;
    contents.add({'role': msg.role == LLMRole.user ? 'user' : 'model', 'parts': parts});
    lastIsResults = false;
  }

  final generationConfig = <String, dynamic>{};
  if (emitsImages) {
    generationConfig['responseModalities'] = ['TEXT', 'IMAGE'];
  }
  // Absent at the default effort and for a model that does not think, so
  // those requests are byte-identical to before (reasoning 03 §2). camelCase
  // like every other key here.
  final thinkingConfig = geminiThinkingConfig(thinking, reasoningEffort);
  if (thinkingConfig != null) {
    generationConfig['thinkingConfig'] = thinkingConfig;
  }
  if (options != null) {
    final imageConfig = <String, dynamic>{};
    // personGeneration is Only for Imagen model
    // Only add aspectRatio if it's not "not_set"
    // if (endpoint?.contains("aabao") == false) {
    //   imageConfig['personGeneration'] = "ALLOW_ALL";
    // }
    if (options.containsKey('aspectRatio') && options['aspectRatio'] != 'not_set') {
      imageConfig['aspectRatio'] = options['aspectRatio'];
    }
    // `not_set` means not sent, like the ratio above: the upstream default is
    // the 1K tier, and the models without an `imageSize` at all
    // (gemini-2.5-flash-image) accept only its absence.
    final size = options['imageSize'];
    if (size is String && size.isNotEmpty && size != 'not_set') {
      imageConfig['imageSize'] = size;
    }
    if (imageConfig.isNotEmpty) generationConfig['imageConfig'] = imageConfig;
  }
  // Only when something capped the output — the channel probe's one token or
  // the model's stored cap. Absent otherwise, so a model with no cap sends a
  // body byte-identical to before. On 2.5+ this bounds thinking *and* the
  // answer together (usage 04 §3), which the editor's caption says.
  final maxTokens = outputCap ?? requestedMaxTokens(options);
  if (maxTokens != null) generationConfig['maxOutputTokens'] = maxTokens;

  return {
    // camelCase for the same reason as `inlineData` above: a relay that reads
    // only `systemInstruction` silently drops a snake_case system prompt.
    'systemInstruction': ?systemInstruction,
    'contents': contents,
    if (tools != null && tools.isNotEmpty)
      'tools': [
        {
          'functionDeclarations': tools
              .map(
                (t) => {'name': t.name, 'description': t.description, 'parameters': t.parameters},
              )
              .toList(),
        },
      ],
    'generationConfig': generationConfig,
    'safetySettings': SafetySettings.toApiList(options?[SafetySettings.paramKey]),
  };
}
