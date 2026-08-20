import 'package:flutter/foundation.dart';

import 'llm/context_budget.dart';

/// One coloured slice of the context bar.
///
/// A *kind*, not a colour: the app ships eight seed colours and two
/// brightnesses, so the card resolves each of these against the ambient theme
/// rather than storing a hue.
enum ContextUsageSlice {
  /// Rebuilt and re-sent in full on every single request, knowledge-base file
  /// map and all. Compaction cannot touch it — which is exactly why it is worth
  /// showing separately from the history it crowds out.
  systemPrompt,

  /// The JSON schemas of the tools offered with the request. Fixed per turn,
  /// and it shrinks when a tool is withdrawn (`read_knowledge_file` once the
  /// window is exhausted).
  tools,

  /// Everything else in the request: the messages as they will actually be
  /// sent, i.e. *after* layer-1 eliding.
  history,
}

/// Where the number the bar is drawn against came from.
///
/// The window is a nullable int with three meanings (see [ContextBudget.modeOf])
/// and the card must not present all three as if they were a measurement.
enum ContextWindowBasis {
  /// Nothing measured yet — no request has gone out in this session.
  none,

  /// A window the user configured for this model.
  configured,

  /// No window configured. [ContextBudget.defaultWindowTokens] stands in — the
  /// same assumption the compaction budget makes, so the bar shows what the app
  /// actually does rather than an idealized unknown.
  assumed,

  /// The user asserts the model has no practical limit. There is no ceiling to
  /// draw a fraction against, so the bar shows the spend and no proportion.
  unlimited,
}

/// What the context bar draws, as a snapshot in characters.
///
/// Characters rather than tokens because that is the unit the assistant's
/// budgeting already works in — see [ContextBudget], which converts once, at
/// the edge, using the ratio it calibrates per model.
///
/// Built by `PromptOptimizerAgent.measureContext`; this class only carries the
/// numbers and the arithmetic that must not differ between the card and its
/// tests.
@immutable
class ContextUsageSnapshot {
  /// The model's context window, in characters. Zero means there is no ceiling
  /// to draw against — an unlimited model, or nothing measured yet.
  final int windowChars;

  /// Chars per slice. **An absent key is "not measured yet", which is not the
  /// same as zero** — a session restored from the database knows its history
  /// exactly and knows nothing about the system prompt until the next request
  /// builds one. The card draws the difference ('—' vs `0`) rather than
  /// claiming a free system prompt.
  final Map<ContextUsageSlice, int> slices;

  final ContextWindowBasis basis;

  const ContextUsageSnapshot({
    required this.windowChars,
    required this.slices,
    this.basis = ContextWindowBasis.configured,
  });

  /// An empty track with no numbers, for a session that has not run a turn yet.
  static const ContextUsageSnapshot placeholder = ContextUsageSnapshot(
    windowChars: 0,
    slices: <ContextUsageSlice, int>{},
    basis: ContextWindowBasis.none,
  );

  /// True while there is nothing measured to show. Distinct from a window of
  /// zero: an unlimited model has real figures and no ceiling.
  bool get isUnknown => basis == ContextWindowBasis.none;

  /// True when a proportion of the window can be drawn at all.
  bool get hasWindow => windowChars > 0;

  int get usedChars =>
      slices.values.fold<int>(0, (sum, value) => sum + (value < 0 ? 0 : value));

  int get remainingChars => (windowChars - usedChars).clamp(0, windowChars);

  /// Share of the window this slice claims, in 0–1, or 0 when there is no
  /// window to claim a share of.
  double fractionOf(ContextUsageSlice slice) {
    if (!hasWindow) return 0;
    final chars = slices[slice] ?? 0;
    if (chars <= 0) return 0;
    return (chars / windowChars).clamp(0.0, 1.0);
  }
}
