import 'dart:convert';
import 'dart:io';

import '../../../core/safety_settings.dart';
import '../llm_types.dart';

/// Pure request-payload builders and response parsing for the Google GenAI
/// dialect. Extracted from the provider so the wire-format logic is isolated
/// from network orchestration and can be unit-tested directly.

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
    if (options.containsKey('imageSize')) {
      parameters['sampleImageSize'] = options['imageSize'];
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

/// Parses one `generateContent`/stream chunk into [LLMResponseChunk]s, handling
/// prompt blocking, finish reasons and safety ratings via [logger].
Iterable<LLMResponseChunk> parseGoogleChunks(Map<String, dynamic> chunkData, {Function(String, {String level})? logger}) sync* {
  Map<String, dynamic>? metadata = chunkData['usageMetadata'];

  // Check for prompt blocking (e.g. prohibited content)
  if (chunkData['promptFeedback'] != null) {
    final feedback = chunkData['promptFeedback'] as Map<String, dynamic>;
    final blockReason = feedback['blockReason'];
    if (blockReason != null) {
      final msg = 'Google GenAI Blocked: $blockReason';
      logger?.call(msg, level: 'ERROR');

      // If we have metadata, yield it before throwing so tokens can be recorded if needed
      if (metadata != null) {
        yield LLMResponseChunk(metadata: metadata);
      }
      throw Exception(msg);
    }
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

    // Handle Safety and other non-STOP reasons (Section 3.3)
    if (finishReason != null && finishReason != 'STOP') {
      String level = 'INFO';
      if (finishReason == 'SAFETY') level = 'WARN';
      if (finishReason == 'RECITATION') level = 'WARN';
      if (finishReason == 'OTHER') level = 'ERROR';

      logger?.call('Generation finished with reason: $finishReason', level: level);

      if (finishReason == 'SAFETY') {
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
    }

    final parts = candidate['content']?['parts'] as List?;
    if (parts != null) {
      int callIndex = 0;
      for (var part in parts) {
        final textPart = part['text'] as String?;

        // Spec prioritizes inlineData (Section 2)
        final inlineData = part['inlineData'] ?? part['inline_data'];
        final imgData = inlineData?['data'];

        // Native function calling. Google supplies no call id — synthesize one.
        LLMToolCall? toolCall;
        final functionCall = part['functionCall'] ?? part['function_call'];
        if (functionCall is Map) {
          final args = functionCall['args'];
          toolCall = LLMToolCall(
            id: 'call_${functionCall['name']}_${callIndex++}',
            name: functionCall['name']?.toString() ?? '',
            arguments: args is Map<String, dynamic> ? args : {},
          );
          logger?.call('Model requested tool call: ${toolCall.name}', level: 'DEBUG');
        }

        yield LLMResponseChunk(
          textPart: textPart,
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
Map<String, dynamic> prepareGooglePayload(List<LLMMessage> history, Map<String, dynamic>? options, String? endpoint, {List<LLMTool>? tools}) {
  final systemMessages = history.where((m) => m.role == LLMRole.system).toList();
  final conversationMessages = history.where((m) => m.role != LLMRole.system).toList();

  Map<String, dynamic>? systemInstruction;
  if (systemMessages.isNotEmpty) {
    systemInstruction = {
      "parts": systemMessages.map((m) => {"text": m.content}).toList()
    };
  }

  final contents = conversationMessages.map((msg) {
    // Tool result message → functionResponse part (role "user" per the
    // Gemini REST function-calling contract).
    if (msg.role == LLMRole.tool) {
      Map<String, dynamic> responsePayload;
      try {
        final decoded = jsonDecode(msg.content);
        responsePayload = decoded is Map<String, dynamic> ? decoded : {"result": decoded};
      } catch (_) {
        responsePayload = {"result": msg.content};
      }
      return {
        "role": "user",
        "parts": [
          {
            "functionResponse": {
              "name": msg.toolName ?? '',
              "response": responsePayload,
            }
          }
        ],
      };
    }

    final parts = <Map<String, dynamic>>[];

    if (msg.content.isNotEmpty) {
      parts.add({"text": msg.content});
    }

    // Assistant tool calls echoed back into history → functionCall parts.
    for (final tc in msg.toolCalls) {
      parts.add({
        "functionCall": {
          "name": tc.name,
          "args": tc.arguments,
        }
      });
    }

    for (var attachment in msg.attachments) {
      String? b64Data;
      if (attachment.path != null) {
        b64Data = base64Encode(File(attachment.path!).readAsBytesSync());
      } else if (attachment.bytes != null) {
        b64Data = base64Encode(attachment.bytes!);
      }

      if (b64Data != null) {
        parts.add({
          "inline_data": {
            "mime_type": attachment.mimeType,
            "data": b64Data
          }
        });
      }
    }

    return {
      "role": msg.role == LLMRole.user ? "user" : "model",
      "parts": parts
    };
  }).toList();

  final generationConfig = <String, dynamic>{};
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
    if (options.containsKey('imageSize')) imageConfig['imageSize'] = options['imageSize'];
    if (imageConfig.isNotEmpty) generationConfig['imageConfig'] = imageConfig;
  }

  return {
    // ignore: use_null_aware_elements
    if (systemInstruction != null) "system_instruction": systemInstruction,
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
