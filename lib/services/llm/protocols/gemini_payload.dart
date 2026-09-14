import 'dart:convert';
import 'dart:io';

import '../../../core/safety_settings.dart';
import '../image_compression.dart';
import '../llm_types.dart';

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
  final userMsg = history.lastWhere(
    (m) => m.role == LLMRole.user,
    orElse: () => history.last,
  );

  final parameters = <String, dynamic>{
    'sampleCount': 1,
    'personGeneration': 'allow_all',
  };
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
    "instances": [
      {"prompt": userMsg.content}
    ],
    "parameters": parameters,
  };
}

/// Veo `:predictLongRunning` request body, including first/last frame and asset
/// reference images.
Map<String, dynamic> prepareVeoPayload(List<LLMMessage> history, Map<String, dynamic>? options) {
  final userMsg = history.lastWhere((m) => m.role == LLMRole.user);

  final instance = <String, dynamic>{
    "prompt": userMsg.content,
  };

  final referenceImages = <Map<String, dynamic>>[];

  for (var attachment in userMsg.attachments) {
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
      final mediaDataLegacy = {
          "mimeType": attachment.mimeType,
          "bytesBase64Encoded": b64Data
      };

      switch (attachment.referenceType) {
        case LLMReferenceType.firstFrame:
          instance['image'] = mediaDataLegacy;
          break;
        case LLMReferenceType.lastFrame:
          instance['lastFrame'] = mediaDataLegacy;
          break;
        case LLMReferenceType.asset:
          referenceImages.add({
            "image": mediaDataLegacy,
            "referenceType": "asset"
          });
          break;
        default:
          referenceImages.add({
            "image": mediaDataLegacy,
            "referenceType": "asset"
          });
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
    "instances": [instance],
    if (parameters.isNotEmpty) "parameters": parameters,
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
      return 'content_filter';
    default:
      // FINISH_REASON_UNSPECIFIED, OTHER, LANGUAGE, and the protocol ones
      // above: the turn ended and nothing in ①'s ladder describes why. The
      // raw value rides along as `finish_reason_raw`.
      return 'stop';
  }
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
      : _nonce = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
            '${(_instances++).toRadixString(36)}';

  /// The next unused id of this response.
  String next() => 'gtc_${_nonce}_${_next++}';
}

/// Parses one `generateContent`/stream chunk into [LLMResponseChunk]s, handling
/// prompt blocking, finish reasons and safety ratings via [logger].
///
/// `metadata` carries `usageMetadata` verbatim plus, on the chunk that ends
/// the candidate, `finish_reason` (①'s vocabulary) and `finish_reason_raw`
/// (③'s). Text parts flagged `thought: true` go out as reasoning, never as
/// text.
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
  Map<String, dynamic>? metadata = chunkData['usageMetadata'];

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

  for (var candidate in candidates) {
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
          for (var r in ratings) {
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
      // The protocol reasons still fail here when nothing was said: a turn
      // that stopped for a missing signature is a failed request, not an
      // empty reply. With content, the content is kept.
      if (protocol && (parts == null || parts.isEmpty)) {
        throw Exception('Google GenAI ended the generation: $finishReason');
      }
    }

    if (parts == null || parts.isEmpty) {
      // Nothing to say, but the finish reason (and usage) still has to reach
      // the consumer — a MAX_TOKENS with an empty candidate is how a request
      // whose budget went entirely to thinking looks.
      if (metadata != null) yield LLMResponseChunk(metadata: metadata);
      continue;
    }

    {
      for (var part in parts) {
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
            thoughtSignature:
                (part['thoughtSignature'] ?? part['thought_signature'])?.toString(),
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
/// works. `test/image_relay_compat_test.dart` walks the payload for any key
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
}) {
  final systemMessages = history.where((m) => m.role == LLMRole.system).toList();
  final conversationMessages = history.where((m) => m.role != LLMRole.system).toList();

  Map<String, dynamic>? systemInstruction;
  if (systemMessages.isNotEmpty) {
    systemInstruction = {
      "parts": systemMessages.map((m) => {"text": m.content}).toList()
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
        responsePayload = decoded is Map<String, dynamic> ? decoded : {"result": decoded};
      } catch (_) {
        responsePayload = {"result": msg.content};
      }
      final toolName = msg.toolName;
      final part = <String, dynamic>{
        "functionResponse": {
          "name": (toolName != null && toolName.isNotEmpty)
              ? toolName
              : (callNames[msg.toolCallId] ?? ''),
          "response": responsePayload,
        }
      };
      if (lastIsResults) {
        (contents.last['parts'] as List).add(part);
      } else {
        contents.add({
          "role": "user",
          "parts": [part],
        });
        lastIsResults = true;
      }
      continue;
    }

    final parts = <Map<String, dynamic>>[];

    if (msg.content.isNotEmpty) {
      parts.add({"text": msg.content});
    }

    // Assistant tool calls echoed back into history → functionCall parts.
    // Gemini requires the thoughtSignature captured from the original response
    // to be replayed verbatim on the same part.
    for (final tc in msg.toolCalls) {
      parts.add({
        "functionCall": {
          "name": tc.name,
          "args": tc.arguments,
        },
        // Only to the model that produced it: another model has no use for
        // the signature and it still travels as input.
        if (tc.thoughtSignature != null &&
            (msg.rawThinkingModelId == null ||
                modelId == null ||
                msg.rawThinkingModelId == modelId))
          "thoughtSignature": tc.thoughtSignature,
      });
    }

    for (var attachment in msg.attachments) {
      if (attachment.path == null && attachment.bytes == null) continue;
      final resolved = ImageCompressor.readForApi(attachment);
      // camelCase, never snake_case. Google's own host accepts both (proto3
      // JSON), but the relays that front this wire (New API's Gemini face)
      // document only the camelCase spelling and *ignore* unrecognized keys
      // rather than rejecting them — so `inline_data` used to mean the model
      // never saw the picture, with a 200 and a perfectly normal answer.
      parts.add({
        "inlineData": {
          "mimeType": resolved.mimeType,
          "data": base64Encode(resolved.bytes)
        }
      });
    }

    // An empty `parts` array is rejected. A turn that produced nothing — an
    // assistant message with neither text nor calls — is simply not sent.
    if (parts.isEmpty) continue;
    contents.add({
      "role": msg.role == LLMRole.user ? "user" : "model",
      "parts": parts
    });
    lastIsResults = false;
  }

  final generationConfig = <String, dynamic>{};
  if (emitsImages) {
    generationConfig['responseModalities'] = ['TEXT', 'IMAGE'];
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

  return {
    // camelCase for the same reason as `inlineData` above: a relay that reads
    // only `systemInstruction` silently drops a snake_case system prompt.
    "systemInstruction": ?systemInstruction,
    "contents": contents,
    if (tools != null && tools.isNotEmpty)
      "tools": [
        {
          "functionDeclarations": tools.map((t) => {
            "name": t.name,
            "description": t.description,
            "parameters": t.parameters,
          }).toList(),
        }
      ],
    "generationConfig": generationConfig,
    "safetySettings":
        SafetySettings.toApiList(options?[SafetySettings.paramKey]),
  };
}
