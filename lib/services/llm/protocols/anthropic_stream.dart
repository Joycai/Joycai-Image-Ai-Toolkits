import 'dart:convert';

import '../llm_types.dart';
import 'anthropic_response.dart';
import 'protocol.dart';

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
  /// Argument characters received for the caller's tools, for
  /// [LLMResponseChunk.toolArgumentChars]. The host's own tools are left out:
  /// they are not something this app is waiting on.
  int _toolArgumentChars = 0;

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
            final startQuery = startInput is Map ? startInput['query']?.toString() : null;
            logger?.call(
              'Host running ${block['name']}'
              '${startQuery == null || startQuery.isEmpty ? '' : '("$startQuery")'}…',
              level: 'INFO',
            );
          case 'web_search_tool_result':
            _hasServerTool = true;
            final parsed = parseAnthropicWebSearchResult(block['content']);
            final at = _runsByCallId[block['tool_use_id']?.toString() ?? ''];
            if (at != null) {
              final run = _serverToolRuns[at];
              _serverToolRuns[at] = ServerToolRun(
                run.name,
                run.query,
                parsed.results,
                error: parsed.error,
              );
            } else {
              _serverToolRuns.add(
                ServerToolRun('web_search', '', parsed.results, error: parsed.error),
              );
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
              // Also the only chunk such a fragment produces — without it a
              // long call streamed nothing the consumer could see.
              if (_pendingCalls[index] != null && partial.isNotEmpty) {
                _toolArgumentChars += partial.length;
                yield LLMResponseChunk(toolArgumentChars: _toolArgumentChars);
              }
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
              block['citations'] = [if (existing is List) ...existing, citation];
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
          final input = _completeCall(serverCall, startedWith: _blocks[index]?['input']).arguments;
          _blocks[index]?['input'] = input;
          _runsByCallId[serverCall.id] = _serverToolRuns.length;
          _serverToolRuns.add(
            ServerToolRun(serverCall.name, input['query']?.toString() ?? '', const []),
          );
        }
        final thought = _pendingThinking.remove(index);
        if (thought != null) _keepForReplay(thought);

      case 'message_delta':
        final delta = event['delta'];
        if (delta is Map && delta['stop_reason'] != null) {
          _stopReason = delta['stop_reason'].toString();
        }
        final finalUsage = event['usage'];
        if (finalUsage is Map) {
          _usage.addAll(finalUsage.cast<String, dynamic>());
        }

      // message_stop / ping carry nothing this consumer needs.
    }
  }

  /// [startedWith] is the `input` the opening `content_block_start` carried.
  /// The spec sends `{}` there and streams the real arguments as fragments,
  /// but a relay re-assembling the stream may hand the whole object over at
  /// the start and send no fragments at all — so an empty buffer falls back
  /// to it rather than to nothing.
  LLMToolCall _completeCall(
    ({String id, String name, StringBuffer json}) call, {
    Object? startedWith,
  }) {
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
          level: 'WARN',
        );
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
  bool get turnIncomplete => _hasServerTool && _lastVisibleType == 'web_search_tool_result';

  /// The closing chunk: usage, stop reason, and the replay carriers.
  ///
  /// One chunk rather than three, and only at the end, because the thinking
  /// blocks only become replayable once their last `signature_delta` has
  /// landed and the consumer needs the whole ordered group or none of it —
  /// and the same holds for a server-tool turn's whole content array.
  /// Null when the stream carried none of them.
  ///
  /// Throws when a client `tool_use` block opened and never closed: the call
  /// can only be emitted on its `content_block_stop`, so a stream cut before
  /// it used to leave the call in [_pendingCalls] and end normally — the
  /// agent loop then read the turn as "answered without calling a tool",
  /// the one failure it cannot detect (tools 05 §3).
  LLMResponseChunk? finish() {
    if (_pendingCalls.isNotEmpty) {
      final names = _pendingCalls.values.map((c) => c.name).join(', ');
      throw LLMApiException(
        'Anthropic API stream ended in the middle of tool call(s) ($names) — '
        'content_block_stop never arrived, so the arguments are incomplete. '
        'The stream was truncated.',
      );
    }
    for (final run in _serverToolRuns) {
      logAnthropicServerToolRun(run, logger);
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
    if (_usage.isEmpty && _stopReason == null && _rawThinkingBlocks.isEmpty && rawContent.isEmpty) {
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
      rawThinkingBlocks: _rawThinkingBlocks.isEmpty ? null : List.of(_rawThinkingBlocks),
      reasoningSignature: _thinkingSignature,
      rawContentBlocks: rawContent.isEmpty ? null : rawContent,
    );
  }
}
