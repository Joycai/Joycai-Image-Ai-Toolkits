import 'package:flutter/material.dart';

import '../services/assistant_context_usage.dart';

/// Identity colours for the assistant's context bar.
///
/// The four slices are parts of a whole, not states: system prompt, tool
/// definitions, session history and what is left. Telling them apart is the
/// colour's entire job — none of them means *good* or *wrong* — which is why
/// they are their own palette rather than semantic roles, and why they do not
/// follow the seed. See `docs/architecture/design-tokens.md` §3.
///
/// They used to be `primary` / `semantic.info` / `semantic.warning`, and the
/// architecture doc said to split them out once a fourth slice appeared. A
/// fourth appeared, and then the restyle made the split urgent rather than
/// tidy: the default seed is now blue and `semantic.info` is *also* blue, so
/// the first two slices of the bar — the two that sit side by side, and the
/// two the user is most often comparing — came out the same colour.
///
/// The values are the spec's own, off `10d`'s bar. Its answer to the same
/// problem is worth copying: the tool slice is a *steel* blue, far enough from
/// the accent to survive next to it.
class ContextUsagePalette {
  const ContextUsagePalette._();

  /// The colour of [slice] in [brightness].
  static Color of(ContextUsageSlice slice, Brightness brightness) {
    final light = brightness == Brightness.light;
    switch (slice) {
      case ContextUsageSlice.systemPrompt:
        // The spec's #3355C4. Deliberately the accent's own deep tone: this
        // slice is the one the user cannot do anything about, so it reads as
        // the bar's baseline rather than as a warning.
        return light ? const Color(0xFF3355C4) : const Color(0xFF7C9BF5);
      case ContextUsageSlice.tools:
        // #3F8FBF, a steel blue. Next to the accent it has to be a different
        // blue rather than a lighter one, or the two slices merge.
        return light ? const Color(0xFF3F8FBF) : const Color(0xFF6FB6D9);
      case ContextUsageSlice.history:
        // #D9963A. The only slice compaction acts on, and the warm one — it is
        // what grows until something has to give.
        return light ? const Color(0xFFD9963A) : const Color(0xFFE8B063);
    }
  }

  /// What is left of the window: the bar's unfilled remainder.
  ///
  /// Not a [ContextUsageSlice] — it is the absence of the other three, and it
  /// carries no identity of its own. A plain ground, which is why the spec
  /// draws it at #DDE2F0 rather than giving it a hue.
  static Color remaining(Brightness brightness) =>
      brightness == Brightness.light ? const Color(0xFFDDE2F0) : const Color(0xFF33415C);
}
