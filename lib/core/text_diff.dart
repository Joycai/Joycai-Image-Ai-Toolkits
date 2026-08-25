/// A line diff, for showing what an agent's proposed knowledge-base edit
/// actually changes.
///
/// `A2 10h` draws a staged edit as a unified diff — a `@@` hunk header over
/// context, removed and added lines. Before this the app showed the whole
/// proposed file and left the user to spot the difference by eye, which on a
/// two-line change inside a 200-line document is not an approval gate at all:
/// the one failure mode that matters here is the model quietly rewriting a
/// paragraph it was not asked to touch, and a wall of "new content" hides
/// exactly that.
///
/// Lines, not characters. These are Markdown documents whose meaningful unit
/// is the line, and a character diff of prose produces a shredded rendering
/// nobody reads.
library;

enum DiffLineKind { context, added, removed }

class DiffLine {
  final DiffLineKind kind;
  final String text;

  const DiffLine(this.kind, this.text);
}

/// One changed region plus the context around it. [oldStart] and [newStart]
/// are 1-based line numbers, as a unified diff writes them.
class DiffHunk {
  final int oldStart;
  final int newStart;
  final List<DiffLine> lines;

  const DiffHunk({required this.oldStart, required this.newStart, required this.lines});
}

class TextDiff {
  const TextDiff._();

  /// Lines of unchanged text kept on each side of a change.
  static const int _contextLines = 2;

  /// Past this many lines on either side the diff is not attempted.
  ///
  /// The algorithm below is O(ND) in the number of differences, which is fast
  /// for the edits an agent actually proposes and slow for the pathological
  /// case of two unrelated documents. A knowledge file this long being
  /// *replaced wholesale* is the one case where the diff would cost real time
  /// and tell the user nothing they could not see from the counts, so it is
  /// reported as a full replacement instead.
  static const int _maxLines = 4000;

  /// Added and removed line counts — the `+12 −3` a card's header carries.
  static (int added, int removed) counts(String oldText, String newText) {
    int added = 0;
    int removed = 0;
    for (final hunk in unified(oldText, newText)) {
      for (final line in hunk.lines) {
        if (line.kind == DiffLineKind.added) added++;
        if (line.kind == DiffLineKind.removed) removed++;
      }
    }
    return (added, removed);
  }

  /// The changed regions of [oldText] → [newText], with [_contextLines] of
  /// unchanged text around each. An empty list means the two are identical.
  static List<DiffHunk> unified(String oldText, String newText) {
    final oldLines = _split(oldText);
    final newLines = _split(newText);

    if (oldLines.length > _maxLines || newLines.length > _maxLines) {
      // One hunk covering everything: honest about being a replacement rather
      // than pretending to have found the edit inside it.
      return [
        DiffHunk(
          oldStart: 1,
          newStart: 1,
          lines: [
            for (final l in oldLines) DiffLine(DiffLineKind.removed, l),
            for (final l in newLines) DiffLine(DiffLineKind.added, l),
          ],
        ),
      ];
    }

    final script = _diff(oldLines, newLines);
    return _toHunks(script);
  }

  /// Splits on either line ending, and drops the empty final element a
  /// trailing newline produces — a file that ends in a newline has not got an
  /// extra blank line at the end of it, and rendering one made every diff
  /// against a well-formed file claim a change it had not made.
  static List<String> _split(String text) {
    if (text.isEmpty) return const [];
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  /// One entry of the edit script, carrying the line numbers a hunk header
  /// needs.
  static List<_Op> _diff(List<String> a, List<String> b) {
    // Common head and tail are stripped first. They are the bulk of any real
    // edit, they cost nothing to find, and taking them out is what keeps the
    // search below working on the handful of lines that actually differ.
    int head = 0;
    while (head < a.length && head < b.length && a[head] == b[head]) {
      head++;
    }
    int tail = 0;
    while (tail < a.length - head && tail < b.length - head &&
        a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
      tail++;
    }

    final midA = a.sublist(head, a.length - tail);
    final midB = b.sublist(head, b.length - tail);

    final ops = <_Op>[
      for (int i = 0; i < head; i++) _Op(DiffLineKind.context, a[i], i + 1, i + 1),
    ];
    ops.addAll(_myers(midA, midB, head));
    for (int i = 0; i < tail; i++) {
      final oldIndex = a.length - tail + i;
      final newIndex = b.length - tail + i;
      ops.add(_Op(DiffLineKind.context, a[oldIndex], oldIndex + 1, newIndex + 1));
    }
    return ops;
  }

  /// Myers' O(ND) diff, walking the furthest-reaching path per edit distance
  /// and keeping one trace per `d` so the path can be walked back afterwards.
  static List<_Op> _myers(List<String> a, List<String> b, int offset) {
    final n = a.length;
    final m = b.length;
    if (n == 0 && m == 0) return const [];

    final max = n + m;
    final v = List<int>.filled(2 * max + 1, 0);
    final trace = <List<int>>[];

    for (int d = 0; d <= max; d++) {
      trace.add(List<int>.from(v));
      for (int k = -d; k <= d; k += 2) {
        int x;
        if (k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max])) {
          x = v[k + 1 + max];
        } else {
          x = v[k - 1 + max] + 1;
        }
        int y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++;
          y++;
        }
        v[k + max] = x;
        if (x >= n && y >= m) return _backtrack(trace, a, b, offset, max);
      }
    }
    return const [];
  }

  static List<_Op> _backtrack(
    List<List<int>> trace,
    List<String> a,
    List<String> b,
    int offset,
    int max,
  ) {
    final ops = <_Op>[];
    int x = a.length;
    int y = b.length;

    for (int d = trace.length - 1; d >= 0 && (x > 0 || y > 0); d--) {
      final v = trace[d];
      final k = x - y;
      final int prevK;
      if (k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max])) {
        prevK = k + 1;
      } else {
        prevK = k - 1;
      }
      final prevX = v[prevK + max];
      final prevY = prevX - prevK;

      while (x > prevX && y > prevY) {
        x--;
        y--;
        ops.add(_Op(DiffLineKind.context, a[x], offset + x + 1, offset + y + 1));
      }
      if (d == 0) break;
      if (x > prevX) {
        x--;
        ops.add(_Op(DiffLineKind.removed, a[x], offset + x + 1, offset + y + 1));
      } else if (y > prevY) {
        y--;
        ops.add(_Op(DiffLineKind.added, b[y], offset + x + 1, offset + y + 1));
      }
    }

    return ops.reversed.toList();
  }

  /// Groups the edit script into hunks, keeping [_contextLines] either side of
  /// each change and dropping the untouched stretches between them.
  static List<DiffHunk> _toHunks(List<_Op> ops) {
    final changed = <int>[
      for (int i = 0; i < ops.length; i++)
        if (ops[i].kind != DiffLineKind.context) i,
    ];
    if (changed.isEmpty) return const [];

    final hunks = <DiffHunk>[];
    int start = (changed.first - _contextLines).clamp(0, ops.length);
    int end = (changed.first + _contextLines).clamp(0, ops.length - 1);

    for (final index in changed.skip(1)) {
      // Merge into the open hunk when their context windows touch; a one-line
      // gap between two changes is not worth two headers.
      if (index - _contextLines <= end + 1) {
        end = (index + _contextLines).clamp(0, ops.length - 1);
        continue;
      }
      hunks.add(_hunk(ops, start, end));
      start = (index - _contextLines).clamp(0, ops.length);
      end = (index + _contextLines).clamp(0, ops.length - 1);
    }
    hunks.add(_hunk(ops, start, end));
    return hunks;
  }

  static DiffHunk _hunk(List<_Op> ops, int start, int end) {
    final slice = ops.sublist(start, end + 1);
    return DiffHunk(
      oldStart: slice.first.oldLine,
      newStart: slice.first.newLine,
      lines: [for (final op in slice) DiffLine(op.kind, op.text)],
    );
  }
}

class _Op {
  final DiffLineKind kind;
  final String text;
  final int oldLine;
  final int newLine;

  const _Op(this.kind, this.text, this.oldLine, this.newLine);
}
