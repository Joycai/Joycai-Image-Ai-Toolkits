import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../state/app_state.dart';
import '../image_compression.dart';
import '../llm_debug_logger.dart';
import '../llm_types.dart';
import '../vendors/vendor_profile.dart';
import 'protocol.dart';

/// Fallback for Anthropic's mandatory `max_tokens`.
///
/// ④ is the only family whose output cap has no server-side default — omit it
/// and the request is rejected outright — so an adapter must carry a constant.
/// 8192 is the largest value every Claude model still in service accepts;
/// going higher would 400 on the older ones, and the current generation caps
/// far above it, so nothing is lost that the caller cannot raise per request
/// via `options['maxTokens']`.
const int anthropicDefaultMaxTokens = 8192;

/// The four image media types Anthropic accepts. Anything else is re-encoded
/// on the way out — see [ImageCompressor.coerceMediaType].
const Set<String> anthropicImageMediaTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
};

/// The versioned type identifier of the server-side web search tool.
///
/// A **server** tool is declared like a client tool but never handed back to
/// the caller to run: the host executes it mid-turn and returns both the call
/// and its results as content blocks. MiniMax adopted Anthropic's identifier
/// verbatim, dated release and all, so one constant covers both.
const String anthropicWebSearchToolType = 'web_search_20250305';

/// Cap on searches per request. Billing is per search *and* every result is
/// re-billed as input on each later iteration and turn, and this field is the
/// only brake the API offers; without it a curious model can run a dozen
/// searches for one question.
const int anthropicWebSearchMaxUses = 5;

/// ①-vocabulary `finish_reason` published for ④'s `pause_turn`: the host
/// suspended a long server-tool turn and wants the assistant message sent
/// back unchanged so the model can continue it. Not `stop` — a turn that
/// ends here has a search in it and no answer after it.
const String anthropicPauseFinishReason = 'pause';

/// Metadata key set when a turn ended on a server-tool result with no text
/// after it while claiming `end_turn` — MiniMax's ④ face does this (it runs
/// the search, hands the results back and does not call the model again).
/// No field says anything was cut short; the shape is the only signal.
const String anthropicTurnIncompleteKey = 'turn_incomplete';

/// Floor Anthropic puts under `thinking.budget_tokens`. Below it the request
/// is rejected rather than clamped.
const int anthropicMinThinkingBudget = 1024;

/// The `system` prompt and `messages[]` of an Anthropic request, separated.
class AnthropicHistory {
  /// Hoisted out of [messages]: ④ has no system *role*, only a top-level
  /// field. Null when the conversation carries no system prompt.
  final String? system;
  final List<Map<String, dynamic>> messages;

  const AnthropicHistory(this.system, this.messages);
}

/// Converts the app's flat message list into ④'s shape.
///
/// Three rewrites happen here, each of which is a 400 from the API if skipped:
///
///  * **system is hoisted.** `{"role": "system"}` is not a thing in ④.
///    Several system turns are joined rather than dropped.
///  * **tool results become user turns.** ④ has no tool role; a result is a
///    `tool_result` block inside a normal user message.
///  * **consecutive same-role turns are merged.** ④ requires the roles to
///    alternate. This matters most for an agent loop: a batch of parallel
///    tool calls arrives as N tool messages, and all N results have to travel
///    in *one* user message immediately after the assistant turn that asked
///    for them.
AnthropicHistory buildAnthropicHistory(List<LLMMessage> history,
    {String? modelId}) {
  final systemParts = <String>[];
  final messages = <Map<String, dynamic>>[];

  void append(String role, List<Map<String, dynamic>> blocks) {
    // An empty content array is rejected too, so a turn that produced no
    // blocks (an assistant message with neither text nor tool calls) is
    // simply not sent.
    if (blocks.isEmpty) return;
    if (messages.isNotEmpty && messages.last['role'] == role) {
      (messages.last['content'] as List).addAll(blocks);
      return;
    }
    messages.add({'role': role, 'content': blocks});
  }

  for (final msg in history) {
    if (msg.role == LLMRole.system) {
      if (msg.content.isNotEmpty) systemParts.add(msg.content);
      continue;
    }

    if (msg.role == LLMRole.tool) {
      append('user', [
        {
          'type': 'tool_result',
          'tool_use_id': msg.toolCallId ?? '',
          // A text block may not be empty, and a tool legitimately returning
          // nothing is not an error — say so instead of sending "".
          'content': msg.content.isEmpty ? '(no output)' : msg.content,
        }
      ]);
      continue;
    }

    if (msg.role == LLMRole.assistant) {
      // A server-tool turn is replayed whole, exactly as it arrived: the
      // result blocks carry an `encrypted_content` the API decrypts to
      // recover what the model read (modified or missing → 400), and a
      // `pause_turn` continuation is defined as "send the assistant message
      // back unchanged". Rebuilding from text + tool calls, as below, would
      // drop the search blocks and with them the search. Model-scoped like
      // the thinking blocks: another model ignores them and bills them.
      final rawContent = msg.rawContentBlocks;
      if (rawContent != null &&
          rawContent.isNotEmpty &&
          (modelId == null || msg.rawThinkingModelId == modelId)) {
        // Shallow copies, so a cache breakpoint stamped on the last block
        // later does not write into the persisted history.
        append('assistant', [
          for (final block in rawContent) Map<String, dynamic>.of(block),
        ]);
        continue;
      }

      final blocks = <Map<String, dynamic>>[];
      // Thinking goes back first, verbatim when the raw blocks were captured
      // (thinking + redacted_thinking, original order and content — the only
      // history ④ accepts as complete). Replay is model-scoped: blocks from
      // a different model are not rejected upstream, they are silently
      // ignored and still billed as input, so a mismatch drops the group.
      final rawBlocks = msg.rawThinkingBlocks;
      if (rawBlocks != null && rawBlocks.isNotEmpty) {
        if (modelId == null || msg.rawThinkingModelId == modelId) {
          blocks.addAll(rawBlocks);
        }
      } else if (msg.reasoningContent != null &&
          msg.reasoningSignature != null) {
        // Legacy path (histories persisted before raw-block capture): a
        // sealed thinking block reconstructed from the display fields. With
        // thinking on, ④ rejects a replayed tool-calling turn whose thinking
        // block is missing or unsigned — and it must precede the text and
        // tool_use blocks it led to. An unsigned one is dropped rather than
        // sent: the API would refuse it anyway, and a refused request is
        // worse than a turn the model has to re-derive.
        blocks.add({
          'type': 'thinking',
          'thinking': msg.reasoningContent,
          'signature': msg.reasoningSignature,
        });
      }
      if (msg.content.isNotEmpty) {
        blocks.add({'type': 'text', 'text': msg.content});
      }
      for (final call in msg.toolCalls) {
        blocks.add({
          'type': 'tool_use',
          'id': call.id,
          'name': call.name,
          'input': call.arguments,
        });
      }
      append('assistant', blocks);
      continue;
    }

    append('user', anthropicUserBlocks(msg));
  }

  return AnthropicHistory(
    systemParts.isEmpty ? null : systemParts.join('\n\n'),
    messages,
  );
}

/// Text + image blocks of one user turn.
List<Map<String, dynamic>> anthropicUserBlocks(LLMMessage msg) {
  final blocks = <Map<String, dynamic>>[];
  if (msg.content.isNotEmpty) {
    blocks.add({'type': 'text', 'text': msg.content});
  }
  for (final attachment in msg.attachments) {
    if (attachment.path == null && attachment.bytes == null) continue;
    final read = ImageCompressor.readForApi(attachment);
    final resolved = ImageCompressor.coerceMediaType(
        read.bytes, read.mimeType, anthropicImageMediaTypes);
    blocks.add({
      'type': 'image',
      'source': {
        'type': 'base64',
        'media_type': resolved.mimeType,
        'data': base64Encode(resolved.bytes),
      },
    });
  }
  return blocks;
}

/// The output cap for a request: the caller's `maxTokens` when it set one,
/// [anthropicDefaultMaxTokens] otherwise.
int anthropicMaxTokens(Map<String, dynamic>? options) =>
    requestedMaxTokens(options) ?? anthropicDefaultMaxTokens;

/// The `thinking` payload for [dialect], or null when there is nothing to
/// send — either the model has it switched off, or the vendor has no such
/// control to switch.
///
/// [maxTokens] matters only to the budget spelling, where the budget is
/// carved out of the output cap and must leave room for the answer itself.
/// The intensity level itself travels separately on the adaptive spelling —
/// see [anthropicOutputConfig] — because ④ puts it in a different top-level
/// field.
Map<String, dynamic>? anthropicThinkingRequest(
  ThinkingDialect dialect, {
  required ReasoningEffort? effort,
  required int maxTokens,
}) {
  // Off and default both mean the field is not sent. Not `disabled`: the
  // newest models reject `{type: "disabled"}` outright (and Opus 5 does at
  // high effort), and on 4.6–4.8 an absent field *is* off. The cost is that
  // "off" on a model that thinks by default (Claude 5) is not honoured — a
  // model that cannot be switched off anyway.
  if (effort == null || effort == ReasoningEffort.off) return null;
  switch (dialect) {
    case ThinkingDialect.none:
    // A ① dialect has no meaning on this wire; a vendor declaring it cannot
    // be a ④ vendor, so this is unreachable in practice and null by rule.
    case ThinkingDialect.openaiThinkingObject:
      return null;
    case ThinkingDialect.adaptive:
      return {'type': 'adaptive'};
    case ThinkingDialect.anthropicAdaptive:
      // `display` is explicit because the newest models default it to
      // `omitted`: the thinking is billed in full, the text just never
      // arrives — and this app shows the thinking in its console.
      return {'type': 'adaptive', 'display': 'summarized'};
    case ThinkingDialect.anthropicBudget:
      // Half the cap, floored at the 1024 the API demands. When the cap is
      // itself below the floor there is no legal budget at all — asking for
      // one anyway is a 400, so the request simply goes out without thinking.
      final half = maxTokens ~/ 2;
      final budget = half < anthropicMinThinkingBudget
          ? anthropicMinThinkingBudget
          : half;
      if (budget >= maxTokens) return null;
      return {'type': 'enabled', 'budget_tokens': budget};
  }
}

/// The top-level `output_config` for [dialect], or null when the dialect has
/// no intensity knob. Only the adaptive spelling carries one; the budget
/// spelling expresses intensity as `budget_tokens`, and MiniMax's has none.
Map<String, dynamic>? anthropicOutputConfig(
  ThinkingDialect dialect, {
  required ReasoningEffort? effort,
}) {
  if (dialect != ThinkingDialect.anthropicAdaptive) return null;
  final wire = anthropicEffortWire(effort);
  return wire == null ? null : {'effort': wire};
}

/// ④'s spelling of the app's reasoning vocabulary for `output_config.effort`,
/// or null for "send nothing". Off is handled upstream — the whole `thinking`
/// field is withheld — so it never reaches here as a value.
///
/// ④'s ladder is `low / medium / high / xhigh / max`. The app has no `xhigh`,
/// and `max` is accepted only by the newest models; an unsupported value is a
/// 400 that names the field, which the on-400 retry deliberately does *not*
/// treat as a dialect problem (see [isAnthropicThinkingRejection]).
String? anthropicEffortWire(ReasoningEffort? effort) => switch (effort) {
      null || ReasoningEffort.off => null,
      ReasoningEffort.low => 'low',
      ReasoningEffort.medium => 'medium',
      ReasoningEffort.high => 'high',
      ReasoningEffort.max => 'max',
    };

/// The two Anthropic spellings are each other's fallback; MiniMax's has none
/// to fall to (a rejected `adaptive` there is a real error), and `none` stays
/// `none`.
ThinkingDialect? alternateAnthropicThinkingDialect(ThinkingDialect dialect) =>
    switch (dialect) {
      ThinkingDialect.anthropicAdaptive => ThinkingDialect.anthropicBudget,
      ThinkingDialect.anthropicBudget => ThinkingDialect.anthropicAdaptive,
      ThinkingDialect.adaptive ||
      ThinkingDialect.none ||
      ThinkingDialect.openaiThinkingObject =>
        null,
    };

/// Dialects learned from a 400, keyed by endpoint and model, for the life of
/// the process.
///
/// The first request on a (host, model) that guessed wrong costs one round
/// trip; every later one goes out right. In-process rather than persisted:
/// relays re-point model names, and a stale memo would be exactly the wrong
/// kind of memory.
final Map<String, ThinkingDialect> _learnedThinkingDialects = {};

String _thinkingMemoKey(LLMTarget target) =>
    '${target.config.endpoint}|${target.config.modelId}';

/// The thinking spelling this request goes out with.
///
/// Resolution order, most specific first:
///  1. what a previous 400 taught us about this endpoint + model;
///  2. the model's generation (layer 3): a Claude of 4.5 or earlier takes the
///     manual form whatever the vendor's default, because both generations
///     are served on one host under one key and the vendor can only name the
///     current one. Applies only where the vendor speaks an Anthropic
///     spelling at all — it must not turn thinking *on* for a vendor that
///     declared `none`, nor rewrite MiniMax's own dialect;
///  3. the vendor's default.
ThinkingDialect resolveAnthropicThinkingDialect(LLMTarget target) {
  final learned = _learnedThinkingDialects[_thinkingMemoKey(target)];
  if (learned != null) return learned;
  final declared = target.vendor.thinking;
  final isAnthropicSpelling = declared == ThinkingDialect.anthropicAdaptive ||
      declared == ThinkingDialect.anthropicBudget;
  if (isAnthropicSpelling && target.model.usesLegacyAnthropicThinking) {
    return ThinkingDialect.anthropicBudget;
  }
  return declared;
}

/// Records that [rejected] was refused for this endpoint + model and returns
/// the spelling to retry with, or null when there is none.
ThinkingDialect? learnAnthropicThinkingDialect(
    LLMTarget target, ThinkingDialect rejected) {
  final alternate = alternateAnthropicThinkingDialect(rejected);
  if (alternate != null) {
    _learnedThinkingDialects[_thinkingMemoKey(target)] = alternate;
  }
  return alternate;
}

/// Forgets every learned dialect. Tests only.
@visibleForTesting
void resetAnthropicThinkingDialectsForTest() => _learnedThinkingDialects.clear();

/// Whether [error] is the API refusing the *shape* of the thinking request —
/// the one 400 worth answering with the other dialect.
///
/// Deliberately narrow. A 400 about `output_config.effort` being unsupported
/// on this model is a level the user can lower, and switching to the budget
/// spelling would only produce a second, unrelated 400; a 400 about
/// `budget_tokens` being too small is the cap, not the dialect. What flips
/// the dialect is the API not knowing the field at all: `thinking.type` with
/// an unexpected value, or an `output_config` it has never heard of.
bool isAnthropicThinkingRejection(Object error) {
  if (error is! LLMApiException || error.statusCode != 400) return false;
  final text = error.message.toLowerCase();
  if (!text.contains('thinking') && !text.contains('output_config')) {
    return false;
  }
  // A complaint about the *value* of effort is not a dialect problem.
  if (text.contains('effort')) return false;
  return true;
}

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
  final converted =
      buildAnthropicHistory(history, modelId: target.config.modelId);
  final maxTokens = anthropicMaxTokens(options);
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
    if (target.config.enableWebSearch)
      {
        'type': anthropicWebSearchToolType,
        'name': 'web_search',
        'max_uses': anthropicWebSearchMaxUses,
      },
  ];

  if (declared.isNotEmpty) {
    payload['tools'] = declared;
    // `auto` only. The forcing modes (`any` / `tool`) are the first thing ④
    // compat layers drop — MiniMax's endpoint has neither — and nothing here
    // needs them.
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

/// One search the host ran on its own, with what it found.
class ServerToolRun {
  final String name;

  /// The tool's input rendered for a log line — `web_search` puts the query
  /// here, and there is only ever one field worth reading.
  final String query;

  /// `title → url` of each result, in the order returned.
  final List<({String title, String url})> results;

  /// The host's `error_code` when the search itself failed
  /// (`too_many_requests`, `max_uses_exceeded`, `unavailable`, …). Delivered
  /// as a 200 with an error *block*, not an HTTP error, so it has to be read
  /// off the result. Zero results is not an error — that is an empty list
  /// with a null here.
  final String? error;

  const ServerToolRun(this.name, this.query, this.results, {this.error});
}

/// What one response's `content` block array carried.
class AnthropicContent {
  final String text;
  final String? thinking;

  /// ④'s seal over [thinking]. Without it the turn cannot be replayed into a
  /// tool-calling conversation — see [LLMMessage.reasoningSignature].
  final String? thinkingSignature;

  final List<LLMToolCall> toolCalls;

  /// Searches the *host* ran during this turn. Never surfaced as
  /// [toolCalls]: they are already executed and already answered, so handing
  /// one to an agent loop would make it run a tool nobody asked it to and
  /// reply to a call the model never made.
  final List<ServerToolRun> serverToolRuns;

  /// The turn's thinking-class blocks **verbatim, in original order**: sealed
  /// `thinking` blocks and opaque `redacted_thinking` blocks. This is the
  /// replay carrier — reconstructing a thinking block from [thinking] +
  /// [thinkingSignature] loses exactly the blocks that have no text to
  /// reconstruct from, and ④'s reaction to an incomplete thinking history is
  /// not a 400 but *silently disabling thinking for the turn* (while still
  /// billing it). [thinking]/[thinkingSignature] remain the display/legacy
  /// carriers.
  final List<Map<String, dynamic>> rawThinkingBlocks;

  /// The **whole** content array, verbatim, when the turn ran a server tool;
  /// empty otherwise. See [LLMMessage.rawContentBlocks].
  final List<Map<String, dynamic>> rawContentBlocks;

  /// True when the turn stopped on a server-tool result with no text after
  /// it: the host ran the search and never called the model back. Official
  /// ④ announces this as `stop_reason: pause_turn`; MiniMax's face reports
  /// `end_turn` and leaves this shape as the only evidence.
  final bool turnIncomplete;

  const AnthropicContent(
    this.text,
    this.thinking,
    this.thinkingSignature,
    this.toolCalls,
    this.serverToolRuns, {
    this.rawThinkingBlocks = const [],
    this.rawContentBlocks = const [],
    this.turnIncomplete = false,
  });
}

/// Reads a `content` block array. Unknown block types contribute nothing —
/// ④ adds them over time (citations, code execution) and an unrecognized one
/// must not cost the blocks around it.
AnthropicContent parseAnthropicContent(Object? rawContent) {
  final text = StringBuffer();
  final thinking = StringBuffer();
  String? signature;
  final rawThinkingBlocks = <Map<String, dynamic>>[];
  final toolCalls = <LLMToolCall>[];
  final serverToolRuns = <ServerToolRun>[];
  // `server_tool_use` and its result are separate blocks tied by an id, and
  // the call always precedes the result.
  final runsByCallId = <String, int>{};
  var hasServerTool = false;
  // The type of the last block that is not thinking — what the turn ended
  // on, for the incomplete-turn test.
  String? lastVisibleType;

  if (rawContent is List) {
    for (final block in rawContent) {
      if (block is! Map) continue;
      final type = block['type'];
      if (type != 'thinking' && type != 'redacted_thinking') {
        lastVisibleType = type?.toString();
      }
      if (type == 'text') {
        final value = block['text'];
        if (value is String && value.isNotEmpty) {
          // A blank line between blocks, not a bare join: with a server tool
          // in the turn the model writes one paragraph before the search and
          // another after it, and gluing them together runs two thoughts into
          // one sentence.
          if (text.isNotEmpty) text.write('\n\n');
          text.write(value);
        }
      } else if (type == 'thinking') {
        final value = block['thinking'];
        if (value is String) thinking.write(value);
        final seal = block['signature'];
        if (seal is String && seal.isNotEmpty) {
          signature = seal;
          // Only sealed blocks are kept for replay — the API refuses an
          // unsigned one, and refusing the whole request is worse than the
          // model re-deriving a thought.
          rawThinkingBlocks.add(block.cast<String, dynamic>());
        }
      } else if (type == 'redacted_thinking') {
        // Opaque encrypted blob: nothing to show, nothing to count — but it
        // MUST survive for replay. A tool-calling turn replayed without its
        // redacted_thinking block is an incomplete thinking history, which ④
        // silently strips (thinking stops, billing continues) rather than
        // rejects.
        rawThinkingBlocks.add(block.cast<String, dynamic>());
      } else if (type == 'tool_use') {
        final input = block['input'];
        toolCalls.add(LLMToolCall(
          id: block['id']?.toString() ?? 'toolu_${toolCalls.length}',
          name: block['name']?.toString() ?? '',
          arguments: input is Map ? input.cast<String, dynamic>() : {},
        ));
      } else if (type == 'server_tool_use') {
        hasServerTool = true;
        final input = block['input'];
        final query = input is Map ? (input['query']?.toString() ?? '') : '';
        runsByCallId[block['id']?.toString() ?? ''] = serverToolRuns.length;
        serverToolRuns.add(ServerToolRun(
          block['name']?.toString() ?? '',
          query,
          const [],
        ));
      } else if (type == 'web_search_tool_result') {
        hasServerTool = true;
        final parsed = _parseWebSearchResult(block['content']);
        final index = runsByCallId[block['tool_use_id']?.toString() ?? ''];
        if (index != null) {
          final run = serverToolRuns[index];
          serverToolRuns[index] = ServerToolRun(run.name, run.query,
              parsed.results,
              error: parsed.error);
        } else {
          // A result with no call in front of it: keep the sources anyway
          // rather than lose them to a bookkeeping mismatch.
          serverToolRuns.add(ServerToolRun('web_search', '', parsed.results,
              error: parsed.error));
        }
      }
      // `redacted_thinking` is an opaque encrypted blob — there is nothing to
      // show and nothing to count.
    }
  }

  final thought = thinking.toString();
  return AnthropicContent(
    text.toString(),
    thought.isEmpty ? null : thought,
    signature,
    toolCalls,
    serverToolRuns,
    rawThinkingBlocks: rawThinkingBlocks,
    rawContentBlocks: hasServerTool && rawContent is List
        ? [
            for (final block in rawContent)
              if (block is Map) block.cast<String, dynamic>(),
          ]
        : const [],
    turnIncomplete: hasServerTool && lastVisibleType == 'web_search_tool_result',
  );
}

/// The `content` of a `web_search_tool_result` block, which is either a list
/// of results or — when the search itself failed — a single error object
/// (`{type: web_search_tool_result_error, error_code}`) in the same field.
({List<({String title, String url})> results, String? error})
    _parseWebSearchResult(Object? content) {
  final results = <({String title, String url})>[];
  if (content is Map) {
    final code = content['error_code']?.toString();
    return (results: results, error: code ?? content['type']?.toString());
  }
  if (content is List) {
    for (final entry in content) {
      if (entry is! Map) continue;
      final url = entry['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      results.add((title: entry['title']?.toString() ?? url, url: url));
    }
  }
  return (results: results, error: null);
}

/// Response metadata in the shape the billing/accounting layer reads.
///
/// ④'s three input buckets **do not overlap**: `input_tokens` is only the
/// part that missed the cache, with `cache_read_input_tokens` and
/// `cache_creation_input_tokens` alongside it. Every other family reports a
/// prompt total that *contains* its cached part, and `LLMService._recordUsage`
/// subtracts the cached part back out of it — so handing it ④'s
/// `input_tokens` under-reports the input by an order of magnitude on a long
/// cached prompt. The sum is published as `prompt_tokens`, which that method
/// prefers over `input_tokens`; the raw buckets ride along untouched so the
/// debug log still shows what the API actually said.
///
/// Cache *creation* stays in the uncached remainder on purpose: it is billed
/// above the base input rate, not below it like a cache hit, and the app has
/// only the two rates.
Map<String, dynamic> anthropicUsageMetadata(
  Map<String, dynamic>? usage, {
  String? stopReason,
  List<ServerToolRun> serverToolRuns = const [],
  bool turnIncomplete = false,
}) {
  int count(Object? value) => value is num ? value.toInt() : 0;
  final input = count(usage?['input_tokens']);
  final cacheRead = count(usage?['cache_read_input_tokens']);
  final cacheWrite = count(usage?['cache_creation_input_tokens']);

  return {
    ...?usage,
    if (usage != null) 'prompt_tokens': input + cacheRead + cacheWrite,
    // Where the answer came from, when it did not come from the model alone.
    if (serverToolRuns.isNotEmpty)
      'server_tool_runs': [
        for (final run in serverToolRuns)
          {
            'name': run.name,
            'query': run.query,
            'sources': [
              for (final r in run.results) {'title': r.title, 'url': r.url}
            ],
            if (run.error != null) 'error': run.error,
          }
      ],
    // The MiniMax-shaped half-turn: `end_turn` on a search result with no
    // answer after it. `finish_reason` still says `stop` — the field is
    // honest about what the host said — and this flag says what the shape
    // said. `LLMService` continues the turn on either signal.
    if (turnIncomplete) anthropicTurnIncompleteKey: true,
    'stop_reason': ?stopReason,
    // The truncation checks in the assistant loop and the web scraper both
    // key off ①'s vocabulary, so the stop reason is also published under the
    // name and value they look for.
    'finish_reason': ?anthropicFinishReason(stopReason),
  };
}

/// ④'s `stop_reason` in ①'s `finish_reason` vocabulary.
String? anthropicFinishReason(String? stopReason) {
  switch (stopReason) {
    case null:
      return null;
    case 'max_tokens':
      return 'length';
    case 'tool_use':
      return 'tool_calls';
    case 'refusal':
      return 'content_filter';
    case 'pause_turn':
      // Not finished: the host suspended a server-tool turn and wants the
      // assistant message sent back unchanged. Mapping this to `stop` read
      // "the search ran, the model wrote one line, then nothing" as a
      // complete answer — and there is no other field that says otherwise.
      return anthropicPauseFinishReason;
    default:
      // end_turn, stop_sequence — the model finished its turn.
      return 'stop';
  }
}

/// The state machine behind [AnthropicChatProtocol.generateStream].
///
/// Extracted from the transport loop so it can be pinned without a socket,
/// the way `geminiChunksFromSseLine` is on ③. Everything here is about one
/// problem: ④ sends a turn as *content blocks* that arrive interleaved and
/// incomplete, while [LLMResponseChunk] promises whole values.
///
/// Feed it decoded `data:` events in arrival order with [accept], then call
/// [finish] once. It is single-use and not reentrant.
class AnthropicStreamAssembler {
  final LLMLogger? logger;

  AnthropicStreamAssembler({this.logger});

  /// Usage arrives in two instalments: the input side on `message_start`,
  /// the output side on `message_delta` — the latter cumulative, so a later
  /// value replaces an earlier one rather than adding to it. Both are held
  /// and reported once at stream end, so no consumer sees half the picture.
  final Map<String, dynamic> _usage = {};
  String? _stopReason;

  /// A turn can hold several text blocks with a server tool's work between
  /// them; the paragraph break belongs at the seam, and only there.
  bool _emittedText = false;

  /// Tool calls under construction, keyed by the content-block index every
  /// event carries. Finalized on `content_block_stop` rather than at stream
  /// end: indices are reused across blocks, and a call whose arguments are
  /// still a JSON fragment must never escape (see
  /// [LLMResponseChunk.toolCallPart]).
  final Map<int, ({String id, String name, StringBuffer json})> _pendingCalls = {};

  /// Server-tool calls under construction — same shape, but these are never
  /// emitted as calls: the host runs them itself.
  final Map<int, ({String id, String name, StringBuffer json})> _pendingServerCalls = {};

  /// Every block of the turn, verbatim as far as a stream allows, keyed by
  /// index and in arrival order. This is the replay carrier for a
  /// server-tool turn ([LLMMessage.rawContentBlocks]): the result blocks
  /// arrive whole (with their `encrypted_content`), the text blocks are
  /// re-assembled from their deltas, and the thinking entries are the *same*
  /// map objects [_pendingThinking] fills in — so both views stay in step.
  final Map<int, Map<String, dynamic>> _blocks = {};
  final List<int> _order = [];
  final Map<int, Map<String, dynamic>> _pendingThinking = {};

  /// Verbatim, in arrival order — the only history ④ accepts as complete.
  final List<Map<String, dynamic>> _rawThinkingBlocks = [];
  String? _thinkingSignature;

  final List<ServerToolRun> _serverToolRuns = [];
  final Map<String, int> _runsByCallId = {};
  bool _hasServerTool = false;
  String? _lastVisibleType;

  /// Whether any event of substance arrived — a `message_start`, a block, a
  /// `message_delta`. `ping` alone does not count. A stream that ends with
  /// this false delivered nothing and is reported as a failure, the way the
  /// synchronous path reports a body with no `content`.
  bool get sawMessage => _sawMessage;
  bool _sawMessage = false;

  static int _indexOf(Map<String, dynamic> event) {
    final raw = event['index'];
    return raw is num ? raw.toInt() : -1;
  }

  /// Consume one event, emitting whatever became complete because of it.
  ///
  /// Unknown event types yield nothing by design: ④ adds them without a
  /// version bump, and an unrecognized one must not cost the blocks around
  /// it.
  Iterable<LLMResponseChunk> accept(Map<String, dynamic> event) sync* {
    if (event['type'] != 'ping') _sawMessage = true;
    switch (event['type']) {
      case 'message_start':
        final message = event['message'];
        if (message is Map) {
          final started = message['usage'];
          if (started is Map) _usage.addAll(started.cast<String, dynamic>());
        }

      case 'content_block_start':
        final block = event['content_block'];
        if (block is! Map) return;
        final index = _indexOf(event);
        final type = block['type']?.toString();
        // The verbatim copy this block will grow into. Shallow: the fields
        // that arrive whole (`content`, `encrypted_content`, `id`) are kept
        // by reference, the ones that stream (`text`, `input`, `thinking`)
        // are rewritten below as they complete.
        final raw = Map<String, dynamic>.of(block.cast<String, dynamic>());
        _blocks[index] = raw;
        _order.add(index);
        if (type != 'thinking' && type != 'redacted_thinking') {
          _lastVisibleType = type;
        }
        switch (type) {
          case 'tool_use':
            // id and name arrive whole here; only `input` is fragmented.
            _pendingCalls[index] = (
              id: block['id']?.toString() ?? 'toolu_${_pendingCalls.length}',
              name: block['name']?.toString() ?? '',
              json: StringBuffer(),
            );
          case 'thinking':
            raw['thinking'] = block['thinking']?.toString() ?? '';
            raw['signature'] = block['signature']?.toString() ?? '';
            _pendingThinking[index] = raw;
          case 'redacted_thinking':
            // Opaque and delta-free: complete the moment it starts, but
            // still finalized at stop so it keeps its place in the order.
            _pendingThinking[index] = raw;
          case 'text':
            raw['text'] = block['text']?.toString() ?? '';
            if (_emittedText) yield LLMResponseChunk(textPart: '\n\n');
          case 'server_tool_use':
            _hasServerTool = true;
            // The host is about to run this itself. Its `input` streams as
            // JSON fragments like a client tool's; the run is recorded once
            // it is whole. Announced now rather than silent: the user is
            // paying for it, and with web search the answer will rest on
            // pages nobody here chose.
            _pendingServerCalls[index] = (
              id: block['id']?.toString() ?? '',
              name: block['name']?.toString() ?? '',
              json: StringBuffer(),
            );
            final startInput = block['input'];
            final startQuery =
                startInput is Map ? startInput['query']?.toString() : null;
            logger?.call(
              'Host running ${block['name']}'
              '${startQuery == null || startQuery.isEmpty ? '' : '("$startQuery")'}…',
              level: 'INFO',
            );
          case 'web_search_tool_result':
            _hasServerTool = true;
            final parsed = _parseWebSearchResult(block['content']);
            final at = _runsByCallId[block['tool_use_id']?.toString() ?? ''];
            if (at != null) {
              final run = _serverToolRuns[at];
              _serverToolRuns[at] = ServerToolRun(run.name, run.query,
                  parsed.results,
                  error: parsed.error);
            } else {
              _serverToolRuns.add(ServerToolRun('web_search', '',
                  parsed.results,
                  error: parsed.error));
            }
        }

      case 'content_block_delta':
        final delta = event['delta'];
        if (delta is! Map) return;
        final index = _indexOf(event);
        switch (delta['type']) {
          case 'text_delta':
            final text = delta['text'];
            if (text is String && text.isNotEmpty) {
              _emittedText = true;
              yield LLMResponseChunk(textPart: text);
              final block = _blocks[index];
              if (block != null) {
                block['text'] = '${block['text'] ?? ''}$text';
              }
            }
          case 'thinking_delta':
            final thinking = delta['thinking'];
            if (thinking is String && thinking.isNotEmpty) {
              // Its own channel, never glued into the deliverable — and also
              // accumulated into the block, because the replay carrier has
              // to be the whole thing, not the display text.
              yield LLMResponseChunk(reasoningPart: thinking);
              final block = _pendingThinking[index];
              if (block != null) {
                block['thinking'] = '${block['thinking'] ?? ''}$thinking';
              }
            }
          case 'input_json_delta':
            // Tool arguments, as a string fragment that is not valid JSON
            // until the last one lands — for the caller's tools and the
            // host's alike.
            final partial = delta['partial_json'];
            if (partial is String) {
              _pendingCalls[index]?.json.write(partial);
              _pendingServerCalls[index]?.json.write(partial);
            }
          case 'signature_delta':
            final seal = delta['signature'];
            if (seal is String && seal.isNotEmpty) {
              final block = _pendingThinking[index];
              if (block != null) block['signature'] = seal;
            }
          case 'citations_delta':
            // Attached to a text block after a search. Kept on the replay
            // copy so the block goes back as it came.
            final citation = delta['citation'];
            final block = _blocks[index];
            if (citation is Map && block != null) {
              final existing = block['citations'];
              block['citations'] = [
                if (existing is List) ...existing,
                citation,
              ];
            }
        }

      case 'content_block_stop':
        final index = _indexOf(event);
        final call = _pendingCalls.remove(index);
        if (call != null) {
          final completed = _completeCall(call, startedWith: _blocks[index]?['input']);
          _blocks[index]?['input'] = completed.arguments;
          yield LLMResponseChunk(toolCallPart: completed);
        }
        final serverCall = _pendingServerCalls.remove(index);
        if (serverCall != null) {
          final input =
              _completeCall(serverCall, startedWith: _blocks[index]?['input']).arguments;
          _blocks[index]?['input'] = input;
          _runsByCallId[serverCall.id] = _serverToolRuns.length;
          _serverToolRuns.add(ServerToolRun(
            serverCall.name,
            input['query']?.toString() ?? '',
            const [],
          ));
        }
        final thought = _pendingThinking.remove(index);
        if (thought != null) _keepForReplay(thought);

      case 'message_delta':
        final delta = event['delta'];
        if (delta is Map && delta['stop_reason'] != null) {
          _stopReason = delta['stop_reason'].toString();
        }
        final finalUsage = event['usage'];
        if (finalUsage is Map) _usage.addAll(finalUsage.cast<String, dynamic>());

      // message_stop / ping carry nothing this consumer needs.
    }
  }

  /// [startedWith] is the `input` the opening `content_block_start` carried.
  /// The spec sends `{}` there and streams the real arguments as fragments,
  /// but a relay re-assembling the stream may hand the whole object over at
  /// the start and send no fragments at all — so an empty buffer falls back
  /// to it rather than to nothing.
  LLMToolCall _completeCall(({String id, String name, StringBuffer json}) call,
      {Object? startedWith}) {
    // A tool taking no arguments sends no input_json_delta at all, so an
    // empty buffer is `{}` and not a parse failure. A buffer that is present
    // but unparseable means the stream was cut mid-arguments: dropping the
    // call would read to an agent loop as "the model chose to answer
    // directly" — the one failure mode it cannot detect — so it goes out
    // with empty arguments and the tool reports the mismatch itself.
    final raw = call.json.toString();
    var arguments = const <String, dynamic>{};
    if (raw.trim().isEmpty && startedWith is Map && startedWith.isNotEmpty) {
      arguments = startedWith.cast<String, dynamic>();
    } else if (raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) arguments = decoded;
      } catch (_) {
        logger?.call(
            'Tool call ${call.name} arrived with unparseable arguments — the '
            'stream was cut mid-JSON.',
            level: 'WARN');
      }
    }
    return LLMToolCall(id: call.id, name: call.name, arguments: arguments);
  }

  /// The same rule [parseAnthropicContent] follows: only *sealed* thinking
  /// blocks are kept (④ refuses an unsigned one, and refusing the whole
  /// request is worse than the model re-deriving a thought), while
  /// `redacted_thinking` is always kept — it has no text to reconstruct
  /// from, and a replay missing it is an incomplete thinking history, which
  /// ④ silently strips rather than rejects.
  void _keepForReplay(Map<String, dynamic> thought) {
    if (thought['type'] == 'redacted_thinking') {
      _rawThinkingBlocks.add(thought);
      return;
    }
    final seal = thought['signature'];
    if (seal is String && seal.isNotEmpty) {
      _rawThinkingBlocks.add(thought);
      _thinkingSignature = seal;
    }
  }

  /// Whether the turn stopped on a search result with no text after it — the
  /// MiniMax-shaped half-turn (see [AnthropicContent.turnIncomplete]).
  bool get turnIncomplete =>
      _hasServerTool && _lastVisibleType == 'web_search_tool_result';

  /// The closing chunk: usage, stop reason, and the replay carriers.
  ///
  /// One chunk rather than three, and only at the end, because the thinking
  /// blocks only become replayable once their last `signature_delta` has
  /// landed and the consumer needs the whole ordered group or none of it —
  /// and the same holds for a server-tool turn's whole content array.
  /// Null when the stream carried none of them.
  LLMResponseChunk? finish() {
    for (final run in _serverToolRuns) {
      AnthropicChatProtocol._logServerToolRun(run, logger);
    }
    if (turnIncomplete) {
      logger?.call(
        'The turn ended on a search result with no answer after it — the '
        'host did not call the model back. The request will be continued.',
        level: 'WARN',
      );
    }
    final rawContent = _hasServerTool
        ? [for (final index in _order) _blocks[index]!]
        : const <Map<String, dynamic>>[];
    if (_usage.isEmpty &&
        _stopReason == null &&
        _rawThinkingBlocks.isEmpty &&
        rawContent.isEmpty) {
      return null;
    }
    return LLMResponseChunk(
      metadata: (_usage.isEmpty && _stopReason == null && !turnIncomplete)
          ? null
          : anthropicUsageMetadata(
              _usage.isEmpty ? null : _usage,
              stopReason: _stopReason,
              serverToolRuns: _serverToolRuns,
              turnIncomplete: turnIncomplete,
            ),
      rawThinkingBlocks:
          _rawThinkingBlocks.isEmpty ? null : List.of(_rawThinkingBlocks),
      reasoningSignature: _thinkingSignature,
      rawContentBlocks: rawContent.isEmpty ? null : rawContent,
    );
  }
}

/// Anthropic `POST /messages` — JSON request, JSON or typed-SSE response.
///
/// Served by Anthropic's own host and by the relays that expose the format
/// natively (New API, MiniMax). Everything vendor-specific about them is
/// authentication, which comes from the vendor profile; there is no branch on
/// a vendor id here.
class AnthropicChatProtocol implements ChatProtocol {
  /// Whether a failed first attempt is worth one more with the other thinking
  /// spelling: the API refused the thinking *shape*, and the request actually
  /// carried one (a request without a thinking field has nothing to respell).
  /// On success the learned dialect is remembered for this endpoint + model.
  ThinkingDialect? _retryDialectFor(
    LLMTarget target,
    ThinkingDialect sent,
    Object error,
    Map<String, dynamic>? options,
    LLMLogger? logger,
  ) {
    if (!isAnthropicThinkingRejection(error)) return null;
    final carried = anthropicThinkingRequest(
      sent,
      effort: target.config.effectiveReasoningEffort,
      maxTokens: anthropicMaxTokens(options),
    );
    if (carried == null) return null;
    final alternate = learnAnthropicThinkingDialect(target, sent);
    if (alternate == null) return null;
    logger?.call(
      'The endpoint rejected the ${sent.name} thinking spelling for '
      '${target.config.modelId}; retrying once with ${alternate.name} and '
      'remembering it for this channel.',
      level: 'WARN',
    );
    return alternate;
  }

  @override
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async {
    final dialect = resolveAnthropicThinkingDialect(target);
    try {
      return await _generateOnce(target, history,
          options: options, tools: tools, logger: logger, dialect: dialect);
    } catch (e) {
      final retry = _retryDialectFor(target, dialect, e, options, logger);
      if (retry == null) rethrow;
      return _generateOnce(target, history,
          options: options, tools: tools, logger: logger, dialect: retry);
    }
  }

  Future<LLMResponse> _generateOnce(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
    required ThinkingDialect dialect,
  }) async {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/messages');
    logger?.call('Preparing Anthropic request to: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareAnthropicPayload(target, history,
        options: options, tools: tools, isStreaming: false, dialect: dialect);

    logger?.call('Sending POST request...', level: 'DEBUG');
    final client = config.createClient();
    try {
      final appState = AppState();
      LLMDebugLog? debugFile;
      if (appState.enableApiDebug) {
        debugFile = await LLMDebugLogger.startLog(config.modelId, 'Anthropic (Standard)', {
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
      // Status → JSON → shape → envelope, in that order (decodeJsonBody). ④
      // delivers errors as `{"type":"error","error":{…}}`, which the shared
      // envelope check recognizes by its `error` field — and a relay can
      // serve one behind a 200.
      final data = decodeJsonBody(response, apiName: 'Anthropic API');

      final rawContent = data['content'];
      if (rawContent is! List || rawContent.isEmpty) {
        // Same rule the other two families now follow: a body carrying no
        // content is a failed request, not a model that chose to say nothing.
        final body = response.body;
        throw Exception('Anthropic API returned no content: '
            '${body.length > 500 ? '${body.substring(0, 500)}…' : body}');
      }

      final content = parseAnthropicContent(rawContent);
      if (content.toolCalls.isNotEmpty) {
        logger?.call('Model requested ${content.toolCalls.length} tool call(s).', level: 'DEBUG');
      }
      for (final run in content.serverToolRuns) {
        _logServerToolRun(run, logger);
      }
      if (content.turnIncomplete) {
        logger?.call(
          'The turn ended on a search result with no answer after it — the '
          'host did not call the model back. The request will be continued.',
          level: 'WARN',
        );
      }
      logger?.call(
        'Parse complete. Text length: ${content.text.length}, Tool calls: ${content.toolCalls.length}',
        level: 'DEBUG',
      );

      return LLMResponse(
        text: content.text,
        metadata: anthropicUsageMetadata(
          (data['usage'] as Map?)?.cast<String, dynamic>(),
          stopReason: data['stop_reason']?.toString(),
          serverToolRuns: content.serverToolRuns,
          turnIncomplete: content.turnIncomplete,
        ),
        rawContentBlocks:
            content.rawContentBlocks.isEmpty ? null : content.rawContentBlocks,
        reasoningContent: content.thinking,
        // Deliberately no field *name*: ④'s echo-back obligation is not a
        // field on the message but the whole thinking block, verified by its
        // signature (see [LLMMessage.reasoningSignature]). Leaving the name
        // null is what keeps the ① payload builder from inventing a key for
        // it if this history is ever replayed against an ① endpoint.
        reasoningSignature: content.thinkingSignature,
        rawThinkingBlocks: content.rawThinkingBlocks.isEmpty
            ? null
            : content.rawThinkingBlocks,
        rawThinkingModelId:
            content.rawThinkingBlocks.isEmpty && content.rawContentBlocks.isEmpty
                ? null
                : config.modelId,
        toolCalls: content.toolCalls,
      );
    } finally {
      client.close();
    }
  }

  /// The host already ran this. Logged rather than silent because the user
  /// is paying for it and, with web search, the answer rests on pages nobody
  /// in this app chose. A failed search is a WARN, not an error: the request
  /// itself succeeded, and `max_uses_exceeded` is the brake doing its job.
  static void _logServerToolRun(ServerToolRun run, LLMLogger? logger) {
    if (run.error != null) {
      logger?.call(
        'Host ran ${run.name}("${run.query}") and it failed: ${run.error}',
        level: 'WARN',
      );
      return;
    }
    logger?.call(
      'Host ran ${run.name}("${run.query}") → ${run.results.length} result(s)'
      '${run.results.isEmpty ? '' : ': ${run.results.map((r) => r.url).join(', ')}'}',
      level: 'INFO',
    );
  }

  /// ④ is the family whose streamed tool calls are cheapest to assemble: the
  /// id and name arrive whole on `content_block_start`, and only the
  /// arguments are fragmented, keyed by a content-block index that is
  /// explicit in every event.
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
    final dialect = resolveAnthropicThinkingDialect(target);
    ThinkingDialect? retry;
    try {
      yield* _streamOnce(target, history,
          options: options, tools: tools, logger: logger, dialect: dialect);
      return;
    } catch (e) {
      // Only a 400 on the opening response qualifies (see
      // [isAnthropicThinkingRejection]), and that arrives before any chunk
      // has been yielded — so retrying cannot duplicate delivered output.
      retry = _retryDialectFor(target, dialect, e, options, logger);
      if (retry == null) rethrow;
    }
    yield* _streamOnce(target, history,
        options: options, tools: tools, logger: logger, dialect: retry);
  }

  Stream<LLMResponseChunk> _streamOnce(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
    required ThinkingDialect dialect,
  }) async* {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/messages');
    logger?.call('Starting Anthropic stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareAnthropicPayload(target, history,
        options: options, tools: tools, isStreaming: true, dialect: dialect);

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(payload);

    final client = config.createClient();
    final appState = AppState();
    LLMDebugLog? debugFile;
    if (appState.enableApiDebug) {
      debugFile = await LLMDebugLogger.startLog(config.modelId, 'Anthropic (Stream)', {
        'url': redactUrl(url),
        'headers': headers,
        'body': payload,
      });
    }

    final response = await client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (debugFile != null) {
        await LLMDebugLogger.appendLine(debugFile, 'Error Status: ${response.statusCode}');
        await LLMDebugLogger.appendLine(debugFile, 'Error Body: $body');
        await LLMDebugLogger.finish(debugFile);
      }
      client.close();
      logger?.call('Stream request failed with status: ${response.statusCode}', level: 'ERROR');
      throw LLMApiException(
          'Anthropic API Stream Request failed: ${response.statusCode} - $body',
          statusCode: response.statusCode);
    }

    logger?.call('Stream connection established, waiting for chunks...', level: 'DEBUG');
    if (debugFile != null) {
      await LLMDebugLogger.appendLine(debugFile, 'Status: ${response.statusCode}');
    }

    final assembler = AnthropicStreamAssembler(logger: logger);

    try {
      await for (final line
          in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (debugFile != null && line.isNotEmpty) {
          await LLMDebugLogger.appendStreamLine(debugFile, line);
        }
        // ④ is a *named*-event stream: every payload line is preceded by an
        // `event:` line naming the same type the JSON repeats in its `type`
        // field. The name is redundant here — but it is not JSON, so it has
        // to be stepped over rather than handed to the decoder.
        if (line.startsWith('event:') ||
            line.startsWith('id:') ||
            line.startsWith('retry:')) {
          continue;
        }
        final dataLine = sseDataPayload(line);
        if (dataLine == null) continue;

        Map<String, dynamic>? event;
        try {
          final decoded = jsonDecode(dataLine);
          if (decoded is Map<String, dynamic>) event = decoded;
        } catch (_) {
          continue; // Non-JSON SSE noise.
        }
        if (event == null) continue;

        // An `error` event mid-stream (overloaded_error, rate limits) must
        // fail the request rather than end it early with a partial answer.
        throwIfEnvelopeError(event);

        // Iterable, not Stream: the assembler is synchronous, so its
        // output is re-yielded one at a time rather than with yield*.
        for (final chunk in assembler.accept(event)) {
          yield chunk;
        }
      }
    } finally {
      client.close();
      // In the finally so a stream that failed mid-flight still records how
      // long it ran before it did.
      await LLMDebugLogger.finish(debugFile);
    }

    if (!assembler.sawMessage) {
      throw LLMApiException(
          'Anthropic API stream ended without a message — the base URL may '
          'point at something that is not this API, or the relay answered '
          'with an empty stream.',
          isNonJsonBody: true);
    }

    final closing = assembler.finish();
    if (closing != null) yield closing;

    yield LLMResponseChunk(isDone: true);
  }
}

/// Anthropic `GET /models` discovery listing.
class AnthropicDiscoveryProtocol implements DiscoveryProtocol {
  @override
  Future<List<DiscoveredModel>> fetchModels(LLMTarget target) async {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/models');
    final headers = target.headers();

    final response = await http.get(url, headers: headers);

    final data = decodeJsonBody(response, apiName: 'Anthropic models');
    final rawModels = data['data'];
    final List<dynamic> modelsJson = rawModels is List ? rawModels : const [];

    return modelsJson.whereType<Map>().map((m) {
      final id = m['id']?.toString() ?? '';
      return DiscoveredModel(
        modelId: id,
        displayName: m['display_name']?.toString() ?? id,
        description: m['created_at']?.toString() ?? '',
        rawData: m.cast<String, dynamic>(),
      );
    }).toList();
  }
}
