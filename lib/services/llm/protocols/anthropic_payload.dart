import '../llm_types.dart';
import '../vendors/vendor_profile.dart';
import 'anthropic_history.dart';
import 'anthropic_thinking.dart';
import 'anthropic_wire.dart';
import 'protocol.dart';

/// Builds a `POST /messages` body.
///
/// Deliberately sends no `temperature` / `top_p` / `top_k`: Anthropic's
/// current generation rejects a non-default value for any of the three
/// unconditionally (and with thinking on, rejects them outright), and the app
/// has no UI that asks for one — so the only thing sending them could do is
/// turn working requests into 400s.
///
/// [dialect] overrides the resolved thinking spelling — the retry path uses
/// it; every other caller leaves it to [resolveAnthropicThinkingDialect].
Map<String, dynamic> prepareAnthropicPayload(
  LLMTarget target,
  List<LLMMessage> history, {
  Map<String, dynamic>? options,
  List<LLMTool>? tools,
  required bool isStreaming,
  ThinkingDialect? dialect,
}) {
  final converted = buildAnthropicHistory(
    history,
    modelId: target.config.modelId,
  );
  final maxTokens = anthropicMaxTokens(target, options);
  final thinkingDialect = dialect ?? resolveAnthropicThinkingDialect(target);
  final effort = target.config.effectiveReasoningEffort;
  final payload = <String, dynamic>{
    'model': target.config.modelId,
    'max_tokens': maxTokens,
    'system': ?converted.system,
    'messages': converted.messages,
    'stream': isStreaming,
    'thinking': ?anthropicThinkingRequest(
      thinkingDialect,
      effort: effort,
      maxTokens: maxTokens,
    ),
    'output_config': ?anthropicOutputConfig(thinkingDialect, effort: effort),
  };

  // Client tools and the host's own tools share one array. A server tool is
  // declared by `type` alone — it has no schema, because the caller never
  // sees the call and never answers it.
  final declared = <Map<String, dynamic>>[
    for (final t in tools ?? const <LLMTool>[])
      {
        'name': t.name,
        'description': t.description,
        // Flat and named `input_schema`, where ① nests the same JSON Schema
        // under `function.parameters`.
        'input_schema': t.parameters,
      },
    // Only where the vendor declares it (`VendorProfile.webSearchOn`): a
    // switch stored on a model that now reaches a non-Anthropic ④ face
    // (Bailian's) is hidden in the editor and must not be sent either.
    if (target.config.enableWebSearch &&
        target.vendor.sendsWebSearchOn(WireProtocol.anthropicChat))
      {
        'type': anthropicWebSearchToolType,
        'name': 'web_search',
        'max_uses': anthropicWebSearchMaxUses,
      },
  ];

  if (declared.isNotEmpty) {
    payload['tools'] = declared;
  }
  // Only when the caller declared tools of its own (tools 05 §2): with server
  // tools alone, `auto` is this app voicing an opinion on the host's internal
  // decision. `auto` only, even then — the forcing modes (`any` / `tool`) are
  // the first thing ④ compat layers drop (MiniMax's endpoint has neither),
  // and nothing here needs them.
  if (tools != null && tools.isNotEmpty) {
    payload['tool_choice'] = {'type': 'auto'};
  }

  if (target.vendor.promptCaching) {
    applyAnthropicCacheBreakpoints(payload);
  }

  return payload;
}

/// One `cache_control` breakpoint, ④'s only flavour.
const Map<String, dynamic> _ephemeral = {'type': 'ephemeral'};

/// Marks the reusable prefix of [payload] so ④ can cache it, in place.
///
/// Three of the four breakpoints ④ allows:
///
///  * **End of `system`.** A breakpoint caches everything before it and the
///    prefix is ordered tools → system → messages, so this one covers the
///    tool schemas too. It requires rewriting `system` from a plain string
///    into a block array, which is the reason this is opt-in per vendor
///    ([VendorProfile.promptCaching]).
///  * **End of each of the last two messages.** The rolling window that makes
///    a multi-turn conversation cache incrementally: the older breakpoint
///    keeps the previous prefix alive while the newer one extends it over the
///    turn just added. One alone would either never cover the newest turn or
///    never survive to the next request.
///
/// Without any of this every request re-reads the whole conversation at full
/// price. The relay this was diagnosed against caches implicitly, which is
/// why the omission was invisible in the logs — against Anthropic's own
/// endpoint the Prompt Assistant was re-billing ~69 K input tokens per turn.
void applyAnthropicCacheBreakpoints(Map<String, dynamic> payload) {
  final system = payload['system'];
  if (system is String && system.isNotEmpty) {
    payload['system'] = [
      {'type': 'text', 'text': system, 'cache_control': _ephemeral},
    ];
  }

  final messages = payload['messages'];
  if (messages is! List || messages.isEmpty) return;
  // The last two, or the only one when that is all there is.
  final from = messages.length >= 2 ? messages.length - 2 : 0;
  for (var i = from; i < messages.length; i++) {
    final message = messages[i];
    if (message is! Map) continue;
    final blocks = message['content'];
    // Only the block array shape is marked. A message whose content is a bare
    // string has nowhere to hang the field, and inventing a block for it
    // would change what is sent for the sake of a cache hint.
    if (blocks is! List || blocks.isEmpty) continue;
    final last = blocks.last;
    if (last is Map<String, dynamic>) last['cache_control'] = _ephemeral;
  }
}
