import 'dart:convert';

import '../../../core/safety_settings.dart';
import '../image_compression.dart';
import '../llm_types.dart';
import '../vendors/vendor_profile.dart' show ThinkingDialect, WireProtocol;
import 'protocol.dart';

/// The system line the ① chat wire sends when the conversation has none.
///
/// Deliberately neutral and short: its only job is to be *present*. A New API
/// relay that receives a chat request without a system message injects its
/// own multi-thousand-token Codex prompt instead (provider layering 01 §9.2).
const String openaiDefaultSystemPrompt = 'You are a helpful assistant.';

/// Build a chat/completions payload for [target].
Map<String, dynamic> prepareOpenAIChatPayload(
  LLMTarget target,
  List<LLMMessage> history,
  Map<String, dynamic>? options, {
  required bool isStreaming,
  List<LLMTool>? tools,
}) {
  final messages = history.map((msg) {
    // Tool result message.
    if (msg.role == LLMRole.tool) {
      return {
        'role': 'tool',
        'tool_call_id': msg.toolCallId,
        'content': msg.content,
      };
    }

    // Assistant message carrying tool calls.
    if (msg.role == LLMRole.assistant && msg.toolCalls.isNotEmpty) {
      return {
        'role': 'assistant',
        'content': msg.content.isEmpty ? null : msg.content,
        // ① family echo-back obligation (reasoning.md §3): DeepSeek returns
        // 400 when a tool-calling assistant turn's reasoning is not
        // replayed. Echo under the exact field name it arrived with —
        // vendors that don't require it simply ignore the field. Inline
        // (<think>) reasoning has no field name and no obligation.
        //
        // Model-scoped (reasoning 03 §5 rule 2): only to the model that
        // produced it. Another model's official host 400s the unknown
        // field and a relay bills it. A turn with no recorded producer —
        // persisted before one was recorded — is still echoed.
        if (msg.reasoningContent != null &&
            msg.reasoningFieldName != null &&
            (msg.rawThinkingModelId == null ||
                msg.rawThinkingModelId == target.config.modelId))
          msg.reasoningFieldName!: msg.reasoningContent,
        'tool_calls': msg.toolCalls
            .map(
              (tc) => {
                'id': tc.id,
                'type': 'function',
                'function': {
                  'name': tc.name,
                  'arguments': jsonEncode(tc.arguments),
                },
              },
            )
            .toList(),
      };
    }

    dynamic content;

    if (msg.attachments.isEmpty) {
      // An image model on the chat route always gets a part array, even
      // for text alone. A relay translating this chat call into an images
      // request has 400ed the string form (`images[0] must be an http/https
      // URL or image data URI`) while accepting a one-element array with
      // the same text — and there is no other way around it. Chat models
      // keep the string: it is the shape every host accepts.
      content =
          (msg.role == LLMRole.user &&
              target.model.capabilities.isImageGenerator)
          ? [
              {'type': 'text', 'text': msg.content},
            ]
          : msg.content;
    } else {
      final parts = <Map<String, dynamic>>[];
      if (msg.content.isNotEmpty) {
        parts.add({'type': 'text', 'text': msg.content});
      }
      for (var attachment in msg.attachments) {
        if (attachment.path == null && attachment.bytes == null) continue;
        final resolved = ImageCompressor.readForApi(attachment);
        parts.add({
          'type': 'image_url',
          'image_url': {
            'url':
                'data:${resolved.mimeType};base64,${base64Encode(resolved.bytes)}',
          },
        });
      }
      content = parts;
    }

    return {'role': msg.role.name, 'content': content};
  }).toList();

  // Never without a system message (provider layering 01 §9.2, pitfalls 11
  // §62). A New API relay that receives a chat request with none injects
  // its own Codex system prompt — 4–9 K input tokens on every request, and
  // nothing anywhere says so but the bill. One short neutral line is the
  // whole cure. Vendor-blind on purpose: the relays that do it are not
  // identifiable from the channel, and a system line costs the rest
  // nothing. An image generator on the chat route is exempt — the relay is
  // translating that call into an images request.
  if (!history.any((m) => m.role == LLMRole.system) &&
      !target.model.capabilities.isImageGenerator) {
    messages.insert(0, {
      'role': 'system',
      'content': openaiDefaultSystemPrompt,
    });
  }

  final effort = target.config.effectiveReasoningEffort;
  final payload = <String, dynamic>{
    'model': target.config.modelId,
    'messages': messages,
    'stream': isStreaming,
    // Only when the user picked a level — default sends nothing (the
    // minimal-common-denominator rule: every proactively sent field is one
    // some relay can 400 on). `off` goes out as "none": an endpoint that
    // predates the value rejects it audibly, which beats thinking anyway.
    //
    // Except where the vendor says its off switch is somewhere else. On
    // DeepSeek `none` is not in the ladder and is *ignored* — the model
    // thinks and bills as usual with nothing in the reply to say so — and
    // the switch is the top-level `thinking` object below. The level itself
    // still travels as `reasoning_effort` there (DeepSeek reads it); only
    // "off" changes spelling, and the field is withheld so a value the host
    // does not know is not sent alongside the one it does.
    //
    // Read per face: a multi-face vendor can spell thinking differently
    // on ① than on its other faces (Bailian's ① switch).
    ...openaiThinkingFields(
      target.vendor.thinkingFor(WireProtocol.openaiChat),
      effort,
    ),
  };

  if (tools != null && tools.isNotEmpty) {
    payload['tools'] = tools
        .map(
          (t) => {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            },
          },
        )
        .toList();
    // Always auto, never a forced tool. That is also what keeps a declared
    // `enable_thinking: true` valid: Qwen accepts only auto|none as
    // tool_choice while thinking is on (pitfalls 11 §A13).
    payload['tool_choice'] = 'auto';
  }

  // The host's own web search, as a top-level flag — only on a vendor that
  // declares it for this face (tools 05 §5). A stored switch that has
  // travelled to any other ① host must not reach it: official OpenAI 400s
  // an unknown top-level field. The search is traceless on this wire (no
  // sources come back), so nothing is parsed or logged for it (pitfalls 11
  // §A10).
  if (target.config.enableWebSearch &&
      target.vendor.sendsWebSearchOn(WireProtocol.openaiChat)) {
    payload['enable_search'] = true;
  }

  if (isStreaming) {
    payload['stream_options'] = {'include_usage': true};
  }

  // Only when something capped the output — the channel probe's one token,
  // or the model's stored cap. Absent otherwise: a model with no cap set
  // sends a body byte-identical to before the field existed. The key is the
  // vendor's answer ([VendorProfile.outputCapFieldFor]): OpenAI's own host
  // 400s on the old name for its reasoning models, older relays and Ollama
  // know only it.
  final maxTokens = outputCapFor(target, options);
  if (maxTokens != null) {
    payload[target.vendor.outputCapFieldFor(target.config.endpoint).wireName] = maxTokens;
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
String? openaiReasoningEffortWire(ReasoningEffort? effort) =>
    switch (effort) {
      null => null,
      ReasoningEffort.off => 'none',
      ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'medium',
      ReasoningEffort.high => 'high',
      ReasoningEffort.max => 'max',
    };

/// The reasoning fields for [dialect] at [effort]: `reasoning_effort` on
/// the generic ① wire, plus — or instead, for "off" — the top-level
/// `thinking` object on a vendor that declares
/// [ThinkingDialect.openaiThinkingObject], or the top-level
/// `enable_thinking` switch **instead of** `reasoning_effort` on a face
/// that declares [ThinkingDialect.openaiEnableThinking]. Empty for the
/// default level on every dialect.
Map<String, dynamic> openaiThinkingFields(
  ThinkingDialect dialect,
  ReasoningEffort? effort,
) {
  if (effort == null) return const {};
  if (dialect == ThinkingDialect.openaiEnableThinking) {
    // 03 §3 switch dialect, ① spelling: a boolean, and no reasoning_effort
    // beside it (Qwen documents the two controls as exclusive).
    return {'enable_thinking': effort != ReasoningEffort.off};
  }
  if (dialect != ThinkingDialect.openaiThinkingObject) {
    return {'reasoning_effort': ?openaiReasoningEffortWire(effort)};
  }
  if (effort == ReasoningEffort.off) {
    return {
      'thinking': {'type': 'disabled'},
    };
  }
  return {
    'thinking': {'type': 'enabled'},
    'reasoning_effort': ?openaiReasoningEffortWire(effort),
  };
}

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
void _applyGeminiCompatExtensions(
  Map<String, dynamic> payload,
  Map<String, dynamic>? options,
) {
  payload['modalities'] = ['image', 'text'];

  payload['safety_settings'] = SafetySettings.toApiList(
    options?[SafetySettings.paramKey],
  );

  if (options == null) return;

  // Only these two keys are portable; `person_generation` /
  // `number_of_images` belong to the top-level dialect alone.
  final portable = <String, dynamic>{};
  if (options.containsKey('aspectRatio') &&
      options['aspectRatio'] != 'not_set') {
    portable['aspect_ratio'] = options['aspectRatio'];
  }
  final size = options['imageSize'];
  if (size is String && size.isNotEmpty && size != 'not_set') {
    portable['image_size'] = size;
  }
  if (portable.isEmpty) return;

  payload['image_config'] = {
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
