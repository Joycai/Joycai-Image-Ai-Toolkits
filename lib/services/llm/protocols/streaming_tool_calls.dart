import '../llm_types.dart';
import 'openai_chat_parsing.dart';
import 'protocol.dart';

/// Assembles the `tool_calls` fragments of a stream into whole calls.
///
/// ① splits one call across chunks and groups the pieces by
/// `delta.tool_calls[].index` — not by `id`, which is fragmented too
/// (docs/api/tools.md §4) — and gives no per-call terminator the way ④'s
/// `content_block_stop` does. Nothing can therefore be emitted before the
/// stream ends, which is why [LLMResponseChunk.toolCallPart] promises whole
/// calls and this class hands them over only from [flush].
///
/// Fragments are *merged* rather than appended blindly, because one wire
/// shape serves two dialects: ① streams deltas, while DashScope's native face
/// streams deltas only where `incremental_output` was honoured and otherwise
/// repeats the whole call on every frame. Appending a cumulative frame builds
/// `{"a":1}{"a":1}` — which parses as nothing and reaches the model as a
/// malformed argument set.
class StreamingToolCallAccumulator {
  final Map<int, _PendingToolCall> _calls = {};

  /// The slot the last index-less frame resolved to. A bare continuation
  /// fragment (no `index`, no `id`) joins it rather than array position 0 —
  /// see [_slotForIndexless].
  int? _lastIndexlessSlot;

  /// Whether any fragment has arrived. False on a stream that answered with
  /// text alone, which is the common case.
  bool get isEmpty => _calls.isEmpty;

  /// Argument characters assembled so far, across every call — measured on
  /// the merged text, so a cumulative dialect's restated frames count once.
  int get argumentChars =>
      _calls.values.fold(0, (sum, call) => sum + call.arguments.length);

  /// Consume one chunk's `tool_calls` array. Anything else is ignored — the
  /// field is absent from most chunks of a tool-bearing stream.
  void feed(Object? rawToolCalls) {
    if (rawToolCalls is! List) return;
    for (var position = 0; position < rawToolCalls.length; position++) {
      final tc = rawToolCalls[position];
      if (tc is! Map) continue;
      // `index` is the grouping key the spec guarantees. For relays that omit
      // the field, the fallback is resolved from the call's own identity —
      // see [_slotForIndexless] for why bare array position is not enough.
      final rawIndex = tc['index'];
      final index = rawIndex is num
          ? rawIndex.toInt()
          : _slotForIndexless(tc, position);
      final pending = _calls.putIfAbsent(index, _PendingToolCall.new);
      pending.id = _merge(pending.id, tc['id']);
      final fn = tc['function'];
      if (fn is! Map) continue;
      final rawName = fn['name'];
      // Dialect telltale, read before the merges fold this frame in. A bare ①
      // continuation delta carries only `index` + `arguments` once the call
      // is open — no id, no name — while a cumulative frame restates the whole
      // call object (id + name + the full arguments so far) every time. So a
      // frame that drops BOTH id and name on an already-named call is a delta,
      // and its arguments append unconditionally: this closes the gap the
      // prefix heuristic in [_merge] leaves open — a delta that opens by
      // repeating the accumulation (`{"a":` + `{"a":1}}`), which the heuristic
      // alone would swallow as a cumulative repeat. Requiring the id to be
      // absent too is what keeps a cumulative dialect that restates its id but
      // not its name (arguments still restated in full) OUT of the delta path,
      // where appending would double its arguments; it routes to [_merge]
      // instead, whose prefix test replaces the restated frame.
      final rawId = tc['id'];
      final frameHasId = rawId is String && rawId.isNotEmpty;
      final isNamelessDelta =
          pending.name.isNotEmpty &&
          !frameHasId &&
          (rawName is! String || rawName.isEmpty);
      pending.name = _merge(pending.name, rawName);
      final rawArgs = fn['arguments'];
      if (rawArgs is Map<String, dynamic>) {
        // Already whole — no wire sends an object in pieces — so it replaces
        // rather than merges.
        pending.decodedArguments = rawArgs;
      } else if (isNamelessDelta && rawArgs is String) {
        pending.arguments = pending.arguments + rawArgs;
      } else {
        pending.arguments = _merge(pending.arguments, rawArgs);
      }
    }
  }

  /// Grouping slot for a fragment whose frame omitted `index`.
  ///
  /// Array position is the spec-shaped fallback — it is what the field would
  /// have said for calls sharing one frame. But a relay that omits `index`
  /// and streams *multiple* calls in separate single-element frames puts every
  /// call at position 0, and merging them builds one blended call — the
  /// silent loss an agent loop cannot detect. The call's `id` disambiguates:
  /// a fragment carrying a known id joins that call, one carrying a new id
  /// opens a fresh slot.
  ///
  /// A fragment with NO id is a bare continuation. Array position 0 sends
  /// every such fragment to the first call, so a second call arriving in its
  /// own single-element frame (id + name on the opener, bare `arguments`
  /// afterwards) has its argument tail merged onto call A. Routing a bare
  /// fragment to the most recently opened index-less slot instead follows the
  /// call that is actually streaming — the only reading that holds when calls
  /// arrive one-after-another rather than interleaved (a relay that interleaves
  /// keeps `index`, which never reaches here).
  int _slotForIndexless(Map<dynamic, dynamic> tc, int position) {
    final rawId = tc['id'];
    final int slot;
    if (rawId is String && rawId.isNotEmpty) {
      int? matched;
      for (final entry in _calls.entries) {
        if (entry.value.id == rawId) {
          matched = entry.key;
          break;
        }
      }
      if (matched != null) {
        slot = matched;
      } else if (_calls.containsKey(position) &&
          _calls[position]!.id.isNotEmpty &&
          _calls[position]!.id != rawId) {
        slot = _calls.keys.reduce((a, b) => a > b ? a : b) + 1;
      } else {
        slot = position;
      }
    } else {
      slot = _lastIndexlessSlot ?? position;
    }
    _lastIndexlessSlot = slot;
    return slot;
  }

  /// Everything assembled so far, in `index` order, and the accumulator
  /// emptied so a reused instance cannot replay a previous turn's calls.
  List<LLMToolCall> flush({LLMLogger? logger}) {
    if (_calls.isEmpty) return const [];
    final calls = <LLMToolCall>[];
    for (final index in _calls.keys.toList()..sort()) {
      final pending = _calls[index]!;
      calls.add(
        LLMToolCall(
          id: resolveToolCallId(pending.id, index),
          name: pending.name,
          arguments:
              pending.decodedArguments ??
              decodeToolArguments(pending.arguments, logger: logger),
        ),
      );
    }
    _calls.clear();
    _lastIndexlessSlot = null;
    return calls;
  }

  /// [raw] folded into what has already arrived on the same field.
  ///
  /// A frame that has the accumulation as its own prefix is a cumulative
  /// repeat and replaces it — which also covers the identical repeat a name
  /// makes on every cumulative frame, and the very first fragment, where the
  /// accumulation is empty. Anything else is a delta and is appended.
  ///
  /// The one shape this cannot tell apart is a delta that opens by repeating
  /// the entire accumulation. For arguments, [feed] resolves that ambiguity
  /// before it reaches here — a nameless frame on a named call is a delta by
  /// construction and appends unconditionally — so this heuristic only
  /// decides frames that restate the name, which is the cumulative dialect's
  /// signature. `DashScopeStreamChannel` faces the same ambiguity for text,
  /// where no such telltale exists.
  static String _merge(String seen, Object? raw) {
    if (raw is! String || raw.isEmpty) return seen;
    if (raw.startsWith(seen)) return raw;
    return seen + raw;
  }
}

/// One call under construction. Mutable and private: only
/// [StreamingToolCallAccumulator] may hold a half-built call.
class _PendingToolCall {
  String id = '';
  String name = '';
  String arguments = '';

  /// Set only where a relay answered with the arguments object itself, in
  /// which case [arguments] stays empty and this wins.
  Map<String, dynamic>? decodedArguments;
}
