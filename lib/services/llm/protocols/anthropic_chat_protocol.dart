import 'dart:convert';

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
/// [maxTokens] matters only to Anthropic's spelling, where the budget is
/// carved out of the output cap and must leave room for the answer itself.
Map<String, dynamic>? anthropicThinkingRequest(
  ThinkingDialect dialect, {
  required ReasoningEffort? effort,
  required int maxTokens,
}) {
  // ④'s budget dialect has no intensity knob: any level means "thinking
  // on", off/default mean the field is not sent. The level vocabulary still
  // matters here because it is the app's single reasoning control — ① turns
  // the same value into `reasoning_effort`.
  if (effort == null || effort == ReasoningEffort.off) return null;
  switch (dialect) {
    case ThinkingDialect.none:
      return null;
    case ThinkingDialect.adaptive:
      return {'type': 'adaptive'};
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

/// Builds a `POST /messages` body.
///
/// Deliberately sends no `temperature` / `top_p` / `top_k`: Anthropic's
/// current generation rejects a non-default value for any of the three
/// unconditionally (and with thinking on, rejects them outright), and the app
/// has no UI that asks for one — so the only thing sending them could do is
/// turn working requests into 400s.
Map<String, dynamic> prepareAnthropicPayload(
  LLMTarget target,
  List<LLMMessage> history, {
  Map<String, dynamic>? options,
  List<LLMTool>? tools,
  required bool isStreaming,
}) {
  final converted =
      buildAnthropicHistory(history, modelId: target.config.modelId);
  final maxTokens = anthropicMaxTokens(options);
  final payload = <String, dynamic>{
    'model': target.config.modelId,
    'max_tokens': maxTokens,
    'system': ?converted.system,
    'messages': converted.messages,
    'stream': isStreaming,
    'thinking': ?anthropicThinkingRequest(
      target.vendor.thinking,
      effort: target.config.effectiveReasoningEffort,
      maxTokens: maxTokens,
    ),
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
      {'type': anthropicWebSearchToolType, 'name': 'web_search'},
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

  const ServerToolRun(this.name, this.query, this.results);
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

  const AnthropicContent(
    this.text,
    this.thinking,
    this.thinkingSignature,
    this.toolCalls,
    this.serverToolRuns, {
    this.rawThinkingBlocks = const [],
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

  if (rawContent is List) {
    for (final block in rawContent) {
      if (block is! Map) continue;
      final type = block['type'];
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
        final input = block['input'];
        final query = input is Map ? (input['query']?.toString() ?? '') : '';
        runsByCallId[block['id']?.toString() ?? ''] = serverToolRuns.length;
        serverToolRuns.add(ServerToolRun(
          block['name']?.toString() ?? '',
          query,
          const [],
        ));
      } else if (type == 'web_search_tool_result') {
        final results = <({String title, String url})>[];
        final entries = block['content'];
        if (entries is List) {
          for (final entry in entries) {
            if (entry is! Map) continue;
            final url = entry['url']?.toString() ?? '';
            if (url.isEmpty) continue;
            results.add((title: entry['title']?.toString() ?? url, url: url));
          }
        }
        final index = runsByCallId[block['tool_use_id']?.toString() ?? ''];
        if (index != null) {
          final run = serverToolRuns[index];
          serverToolRuns[index] = ServerToolRun(run.name, run.query, results);
        } else {
          // A result with no call in front of it: keep the sources anyway
          // rather than lose them to a bookkeeping mismatch.
          serverToolRuns.add(ServerToolRun('web_search', '', results));
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
  );
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
          }
      ],
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
    default:
      // end_turn, stop_sequence, pause_turn — the model finished its turn.
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

  /// Tool calls and thinking blocks under construction, keyed by the
  /// content-block index every event carries. Both are finalized on
  /// `content_block_stop` rather than at stream end: indices are reused
  /// across blocks, and a call whose arguments are still a JSON fragment
  /// must never escape (see [LLMResponseChunk.toolCallPart]).
  final Map<int, ({String id, String name, StringBuffer json})> _pendingCalls = {};
  final Map<int, Map<String, dynamic>> _pendingThinking = {};

  /// Verbatim, in arrival order — the only history ④ accepts as complete.
  final List<Map<String, dynamic>> _rawThinkingBlocks = [];
  String? _thinkingSignature;

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
        switch (block['type']) {
          case 'tool_use':
            // id and name arrive whole here; only `input` is fragmented.
            _pendingCalls[_indexOf(event)] = (
              id: block['id']?.toString() ?? 'toolu_${_pendingCalls.length}',
              name: block['name']?.toString() ?? '',
              json: StringBuffer(),
            );
          case 'thinking':
            _pendingThinking[_indexOf(event)] = {
              'type': 'thinking',
              'thinking': block['thinking']?.toString() ?? '',
              'signature': block['signature']?.toString() ?? '',
            };
          case 'redacted_thinking':
            // Opaque and delta-free: complete the moment it starts, but
            // still finalized at stop so it keeps its place in the order.
            _pendingThinking[_indexOf(event)] = block.cast<String, dynamic>();
          case 'text':
            if (_emittedText) yield LLMResponseChunk(textPart: '\n\n');
          case 'server_tool_use':
            final input = block['input'];
            final query = input is Map ? (input['query']?.toString() ?? '') : '';
            // The host is about to run this itself. Announced rather than
            // silent: the user is paying for it, and with web search the
            // answer will rest on pages nobody here chose.
            logger?.call(
              'Host running ${block['name']}${query.isEmpty ? '' : '("$query")'}…',
              level: 'INFO',
            );
        }

      case 'content_block_delta':
        final delta = event['delta'];
        if (delta is! Map) return;
        switch (delta['type']) {
          case 'text_delta':
            final text = delta['text'];
            if (text is String && text.isNotEmpty) {
              _emittedText = true;
              yield LLMResponseChunk(textPart: text);
            }
          case 'thinking_delta':
            final thinking = delta['thinking'];
            if (thinking is String && thinking.isNotEmpty) {
              // Its own channel, never glued into the deliverable — and also
              // accumulated into the block, because the replay carrier has
              // to be the whole thing, not the display text.
              yield LLMResponseChunk(reasoningPart: thinking);
              final block = _pendingThinking[_indexOf(event)];
              if (block != null) {
                block['thinking'] = '${block['thinking'] ?? ''}$thinking';
              }
            }
          case 'input_json_delta':
            // Tool arguments, as a string fragment that is not valid JSON
            // until the last one lands.
            final partial = delta['partial_json'];
            if (partial is String) {
              _pendingCalls[_indexOf(event)]?.json.write(partial);
            }
          case 'signature_delta':
            final seal = delta['signature'];
            if (seal is String && seal.isNotEmpty) {
              final block = _pendingThinking[_indexOf(event)];
              if (block != null) block['signature'] = seal;
            }
        }

      case 'content_block_stop':
        final index = _indexOf(event);
        final call = _pendingCalls.remove(index);
        if (call != null) {
          yield LLMResponseChunk(toolCallPart: _completeCall(call));
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

  LLMToolCall _completeCall(({String id, String name, StringBuffer json}) call) {
    // A tool taking no arguments sends no input_json_delta at all, so an
    // empty buffer is `{}` and not a parse failure. A buffer that is present
    // but unparseable means the stream was cut mid-arguments: dropping the
    // call would read to an agent loop as "the model chose to answer
    // directly" — the one failure mode it cannot detect — so it goes out
    // with empty arguments and the tool reports the mismatch itself.
    final raw = call.json.toString();
    var arguments = const <String, dynamic>{};
    if (raw.trim().isNotEmpty) {
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

  /// The closing chunk: usage, stop reason, and the replay carriers.
  ///
  /// One chunk rather than three, and only at the end, because the thinking
  /// blocks only become replayable once their last `signature_delta` has
  /// landed and the consumer needs the whole ordered group or none of it.
  /// Null when the stream carried none of the three.
  LLMResponseChunk? finish() {
    if (_usage.isEmpty && _stopReason == null && _rawThinkingBlocks.isEmpty) {
      return null;
    }
    return LLMResponseChunk(
      metadata: (_usage.isEmpty && _stopReason == null)
          ? null
          : anthropicUsageMetadata(
              _usage.isEmpty ? null : _usage,
              stopReason: _stopReason,
            ),
      rawThinkingBlocks:
          _rawThinkingBlocks.isEmpty ? null : List.of(_rawThinkingBlocks),
      reasoningSignature: _thinkingSignature,
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
  @override
  Future<LLMResponse> generate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async {
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/messages');
    logger?.call('Preparing Anthropic request to: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareAnthropicPayload(target, history,
        options: options, tools: tools, isStreaming: false);

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
        // The host already ran these. Logged rather than silent because the
        // user is paying for them and, with web search, the answer rests on
        // pages nobody in this app chose.
        logger?.call(
          'Host ran ${run.name}("${run.query}") → ${run.results.length} result(s)'
          '${run.results.isEmpty ? '' : ': ${run.results.map((r) => r.url).join(', ')}'}',
          level: 'INFO',
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
        ),
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
            content.rawThinkingBlocks.isEmpty ? null : config.modelId,
        toolCalls: content.toolCalls,
      );
    } finally {
      client.close();
    }
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
    final config = target.config;
    final url = Uri.parse('${trimBaseUrl(config.endpoint)}/messages');
    logger?.call('Starting Anthropic stream: ${url.host}', level: 'DEBUG');
    final headers = target.headers();
    final payload = prepareAnthropicPayload(target, history,
        options: options, tools: tools, isStreaming: true);

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
