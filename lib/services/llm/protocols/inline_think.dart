



/// Result of separating inline `<think>…</think>` chain-of-thought from
/// model text.
class InlineThinkResult {
  final String text;
  final String? reasoning;
  const InlineThinkResult(this.text, this.reasoning);
}

const String _thinkOpenTag = '<think>';

const String _thinkCloseTag = '</think>';

/// Separates a leading inline `<think>…</think>` span from [raw].
///
/// Some ①-family compat endpoints (MiniMax by default, various relays fronting
/// DeepSeek-style models) put the chain of thought straight into `content` as
/// `<think>…</think>\n\n<answer>`. Any consumer that treats `content` as the
/// answer collects the thinking with it — into the transcript, into history
/// re-sent every turn, into compaction summaries.
///
/// **Only a tag at the very start counts** (leading whitespace allowed —
/// reasoning 03 §6 rule 1). A `<think>` anywhere later is the author's or the
/// model's own text: this app writes prompts, and a reply that explains the
/// tag used to have the explanation silently moved into reasoning. Missing a
/// split leaves a tag in the draft; a wrong split eats part of it, which is
/// the worse failure. An unterminated leading span (a truncated response)
/// swallows the rest as reasoning rather than leaking it as text.
InlineThinkResult stripInlineThink(String raw) {
  final body = raw.trimLeft();
  if (!body.startsWith(_thinkOpenTag)) return InlineThinkResult(raw, null);
  final close = body.indexOf(_thinkCloseTag, _thinkOpenTag.length);
  final thought = (close == -1
          ? body.substring(_thinkOpenTag.length)
          : body.substring(_thinkOpenTag.length, close))
      .trim();
  final text = close == -1
      ? ''
      : body.substring(close + _thinkCloseTag.length).trimLeft();
  return InlineThinkResult(text, thought.isEmpty ? null : thought);
}

/// Where an [InlineThinkStreamFilter] is in the reply.
enum _ThinkPhase {
  /// Nothing but whitespace (or a partial opening tag) seen so far.
  start,

  /// Inside the leading `<think>` span.
  thinking,

  /// The answer. Nothing is detected from here on.
  body,
}

/// Cross-chunk `<think>` separator for the streaming path — the same rule as
/// [stripInlineThink], as a start / thinking / body state machine.
///
/// Tags arrive split across SSE chunks (`<thi` + `nk>` is normal), so a
/// per-chunk regex cannot work. At the start the filter holds back leading
/// whitespace and any fragment that could still become the opening tag;
/// inside the span it holds back a fragment that could still become the
/// closing tag. Once the first non-whitespace answer text has been decided,
/// everything passes straight through: a tag in the body is text.
class InlineThinkStreamFilter {
  final StringBuffer _pending = StringBuffer();
  _ThinkPhase _phase = _ThinkPhase.start;

  /// True right after the closing tag: the blank line models put between
  /// thinking and answer is dropped, as the synchronous path trims it.
  bool _trimBodyStart = false;

  /// Feeds one delta; returns what can be classified so far.
  ({String text, String reasoning}) feed(String delta) {
    _pending.write(delta);
    final text = StringBuffer();
    final reasoning = StringBuffer();
    var buf = _pending.toString();
    _pending.clear();

    while (buf.isNotEmpty) {
      switch (_phase) {
        case _ThinkPhase.start:
          final lead = buf.trimLeft();
          if (lead.startsWith(_thinkOpenTag)) {
            _phase = _ThinkPhase.thinking;
            buf = lead.substring(_thinkOpenTag.length);
          } else if (lead.isEmpty || _thinkOpenTag.startsWith(lead)) {
            // Whitespace alone, or `<thi…`: undecided until more arrives.
            _pending.write(buf);
            buf = '';
          } else {
            // Not a thinking reply. The buffer, leading whitespace included,
            // is answer text.
            _phase = _ThinkPhase.body;
          }
        case _ThinkPhase.thinking:
          final idx = buf.indexOf(_thinkCloseTag);
          if (idx != -1) {
            reasoning.write(buf.substring(0, idx));
            buf = buf.substring(idx + _thinkCloseTag.length);
            _phase = _ThinkPhase.body;
            _trimBodyStart = true;
          } else {
            final hold = _partialTagSuffix(buf, _thinkCloseTag);
            reasoning.write(buf.substring(0, buf.length - hold));
            _pending.write(buf.substring(buf.length - hold));
            buf = '';
          }
        case _ThinkPhase.body:
          if (_trimBodyStart) {
            buf = buf.trimLeft();
            if (buf.isEmpty) break;
            _trimBodyStart = false;
          }
          text.write(buf);
          buf = '';
      }
    }
    return (text: text.toString(), reasoning: reasoning.toString());
  }

  /// Flushes whatever is still held back at stream end. An unterminated think
  /// span counts as reasoning, mirroring [stripInlineThink]; held-back
  /// whitespace or a lone `<thi` at the start is text.
  ({String text, String reasoning}) flush() {
    final rest = _pending.toString();
    _pending.clear();
    if (rest.isEmpty) return (text: '', reasoning: '');
    return _phase == _ThinkPhase.thinking
        ? (text: '', reasoning: rest)
        : (text: rest, reasoning: '');
  }

  /// Length of the longest suffix of [buf] that is a proper prefix of [tag].
  static int _partialTagSuffix(String buf, String tag) {
    final maxLen = buf.length < tag.length - 1 ? buf.length : tag.length - 1;
    for (int len = maxLen; len > 0; len--) {
      if (tag.startsWith(buf.substring(buf.length - len))) return len;
    }
    return 0;
  }
}
