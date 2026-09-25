import '../llm_types.dart';
import 'anthropic_wire.dart';
import 'protocol.dart';

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

/// The host already ran this. Logged rather than silent because the user
/// is paying for it and, with web search, the answer rests on pages nobody
/// in this app chose. A failed search is a WARN, not an error: the request
/// itself succeeded, and `max_uses_exceeded` is the brake doing its job.
void logAnthropicServerToolRun(ServerToolRun run, LLMLogger? logger) {
  if (run.error != null) {
    logger?.call('Host ran ${run.name}("${run.query}") and it failed: ${run.error}', level: 'WARN');
    return;
  }
  logger?.call(
    'Host ran ${run.name}("${run.query}") → ${run.results.length} result(s)'
    '${run.results.isEmpty ? '' : ': ${run.results.map((r) => r.url).join(', ')}'}',
    level: 'INFO',
  );
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
        toolCalls.add(
          LLMToolCall(
            id: block['id']?.toString() ?? 'toolu_${toolCalls.length}',
            name: block['name']?.toString() ?? '',
            arguments: input is Map ? input.cast<String, dynamic>() : {},
          ),
        );
      } else if (type == 'server_tool_use') {
        hasServerTool = true;
        final input = block['input'];
        final query = input is Map ? (input['query']?.toString() ?? '') : '';
        runsByCallId[block['id']?.toString() ?? ''] = serverToolRuns.length;
        serverToolRuns.add(ServerToolRun(block['name']?.toString() ?? '', query, const []));
      } else if (type == 'web_search_tool_result') {
        hasServerTool = true;
        final parsed = parseAnthropicWebSearchResult(block['content']);
        final index = runsByCallId[block['tool_use_id']?.toString() ?? ''];
        if (index != null) {
          final run = serverToolRuns[index];
          serverToolRuns[index] = ServerToolRun(
            run.name,
            run.query,
            parsed.results,
            error: parsed.error,
          );
        } else {
          // A result with no call in front of it: keep the sources anyway
          // rather than lose them to a bookkeeping mismatch.
          serverToolRuns.add(ServerToolRun('web_search', '', parsed.results, error: parsed.error));
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
({List<({String title, String url})> results, String? error}) parseAnthropicWebSearchResult(
  Object? content,
) {
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
    ...upstreamUsage(usage),
    if (usage != null) 'prompt_tokens': input + cacheRead + cacheWrite,
    // Where the answer came from, when it did not come from the model alone.
    if (serverToolRuns.isNotEmpty)
      'server_tool_runs': [
        for (final run in serverToolRuns)
          {
            'name': run.name,
            'query': run.query,
            'sources': [
              for (final r in run.results) {'title': r.title, 'url': r.url},
            ],
            if (run.error != null) 'error': run.error,
          },
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
