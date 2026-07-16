import '../database_service.dart';

/// How a model's context window is configured.
///
/// The `llm_models.context_window` column encodes this tri-state in one
/// nullable int, and more than one caller has to agree on the encoding — this
/// enum and [ContextBudget.modeOf] / [ContextBudget.store] are the only place
/// that spells it out.
enum ContextWindowMode {
  /// The user has not told us the model's limit. Callers assume a conservative
  /// default rather than guessing generously.
  unset,

  /// An explicit token count the user picked.
  specified,

  /// The user asserts the model has no practical limit. This is a claim, not a
  /// fact, so callers still keep a sane ceiling.
  unlimited,
}

/// What a model's configured context window means, in one place.
///
/// The window drives two unrelated consumers — image batching in
/// [WebScraperService] and the Prompt Assistant's compaction/knowledge-read
/// budget — and they must not drift on what `null` or `0` mean.
class ContextBudget {
  const ContextBudget._();

  /// Characters assumed to fit in one token, converting a token window into the
  /// character budget the agent actually measures.
  ///
  /// Note which way this cuts: budget = tokens * ratio * charsPerToken, so a
  /// *larger* value is more permissive, not safer. English runs ~4 chars/token
  /// and Chinese ~1–1.3; the old hardcoded threshold assumed 4, which for a
  /// Chinese knowledge base let the budget run several times past the real
  /// window — the request blew up before compaction ever triggered.
  ///
  /// 1.5 leans to the CJK end (this app's knowledge bases are Chinese) while
  /// staying conservative for the markdown, code and English terms mixed into
  /// them. It is a heuristic, and it does not need to be better than one: the
  /// window it converts is a 9-notch preset picked off a slider.
  ///
  /// Reading real token counts from the provider was considered and rejected:
  /// `usage` is optional in the OpenAI-compatible response and some servers
  /// omit it, which would read as *zero* occupancy on exactly the small local
  /// models that overflow first.
  static const double charsPerToken = 1.5;

  /// Bounds on a [calibrate] result. A ratio outside this is not a language
  /// mix, it is a bug or a provider reporting something other than what we
  /// think — clamping keeps one bad response from unbounding the budget.
  static const double _minObservedCharsPerToken = 0.5;
  static const double _maxObservedCharsPerToken = 6.0;

  /// The real chars-per-token of the last request, from the tokens the provider
  /// billed for it, or null when it reported none.
  ///
  /// [charsSent] must be measured the same way occupancy is, or the ratio maps
  /// between two different quantities. The conversion is then self-consistent
  /// by construction: budget_chars / observed == the token budget, whatever the
  /// mix of language, markdown and images happens to cost.
  static double? calibrate({required int charsSent, required int? promptTokens}) {
    if (promptTokens == null || promptTokens <= 0 || charsSent <= 0) return null;
    final observed = charsSent / promptTokens;
    if (observed < _minObservedCharsPerToken) return _minObservedCharsPerToken;
    if (observed > _maxObservedCharsPerToken) return _maxObservedCharsPerToken;
    return observed;
  }

  /// Assumed window when the model does not declare one.
  static const int defaultWindowTokens = 32768;

  /// Budget for an unlimited model. This is the threshold the agent hardcoded
  /// before windows were wired up, kept so "unlimited" behaves exactly as it
  /// does today. It must not be derived from the window: `0 * ratio` is 0, so
  /// a ratio trigger would fire on every single turn.
  static const int unlimitedBudgetChars = 192000;

  /// Ceiling on a single knowledge read for an unlimited model.
  ///
  /// Not infinity. "Unlimited" is the user's claim, and progressive disclosure
  /// also protects output quality — feeding 200KB of mostly irrelevant rules
  /// dilutes the model's attention even when it technically fits.
  static const int unlimitedReadCapChars = 64000;

  /// Ceiling on what is held back from a knowledge read for the model's own
  /// reply and the tool calls that follow it in the same turn.
  ///
  /// A ceiling rather than a flat amount: see [reserveFor].
  static const int maxReplyReserveChars = 16000;

  /// Share of a small window held back for the reply, when [maxReplyReserveChars]
  /// would not fit.
  static const double _reserveShare = 0.25;

  /// Chars held back for the reply out of a [totalChars] window.
  ///
  /// Flat reserves do not survive small windows: 16000 chars is ~8K tokens, so
  /// a 4K-token model (8192 chars all in) would have a negative budget and
  /// could never read a knowledge file at all. Scale down instead of pricing
  /// small models out.
  static int reserveFor(int totalChars) {
    final share = (totalChars * _reserveShare).round();
    return share < maxReplyReserveChars ? share : maxReplyReserveChars;
  }

  static ContextWindowMode modeOf(int? stored) => stored == null
      ? ContextWindowMode.unset
      : (stored <= 0 ? ContextWindowMode.unlimited : ContextWindowMode.specified);

  /// Encodes [mode] back into the column. [tokens] is ignored unless [mode] is
  /// [ContextWindowMode.specified].
  static int? store(ContextWindowMode mode, int tokens) => switch (mode) {
        ContextWindowMode.unset => null,
        ContextWindowMode.unlimited => 0,
        ContextWindowMode.specified => tokens,
      };

  /// The configured window for [modelIdentifier], or null when it is unset,
  /// unknown, or unreadable. Accepts both a DB primary key and a legacy string
  /// model id, matching [LLMConfigResolver].
  static Future<int?> resolveWindow(dynamic modelIdentifier) async {
    try {
      final models = await DatabaseService().getModels();
      for (final m in models) {
        if (modelIdentifier is int ? m.id == modelIdentifier : m.modelId == modelIdentifier) {
          return m.contextWindow;
        }
      }
    } catch (_) {
      // Best effort — every caller has a conservative fallback for null.
    }
    return null;
  }

  /// Character budget at which the assistant should summarize, given [window]
  /// and the user's hard-summary [ratio] (0–1).
  ///
  /// [observedCharsPerToken] is a [calibrate] result for this session; without
  /// one the conservative [charsPerToken] default applies.
  static int budgetChars(int? window, double ratio, {double? observedCharsPerToken}) {
    final perToken = observedCharsPerToken ?? charsPerToken;
    switch (modeOf(window)) {
      case ContextWindowMode.unlimited:
        return unlimitedBudgetChars;
      case ContextWindowMode.unset:
        return (defaultWindowTokens * ratio * perToken).round();
      case ContextWindowMode.specified:
        return (window! * ratio * perToken).round();
    }
  }

  /// Characters a single knowledge read may return, given what the context
  /// already holds.
  ///
  /// Uses the *whole* window rather than the summary ratio on purpose: the
  /// headroom above the ratio is exactly what funds reading a file in one
  /// piece, and compaction reclaims it at the next turn boundary. Never
  /// negative.
  static int readCapChars(int? window, int occupiedChars, {double? observedCharsPerToken}) {
    if (modeOf(window) == ContextWindowMode.unlimited) return unlimitedReadCapChars;
    final perToken = observedCharsPerToken ?? charsPerToken;
    final total = ((modeOf(window) == ContextWindowMode.unset
                ? defaultWindowTokens
                : window!) *
            perToken)
        .round();
    final cap = total - occupiedChars - reserveFor(total);
    return cap < 0 ? 0 : cap;
  }

  /// Images per request for LLM-assisted image selection.
  ///
  /// A long list burns the model's generation budget before it can emit a tool
  /// call, so batches keep each request inside a modest context.
  static int imageBatchSize(int? window, {required int defaultSize, required int unlimitedSize}) {
    switch (modeOf(window)) {
      case ContextWindowMode.unset:
        return defaultSize;
      case ContextWindowMode.unlimited:
        return unlimitedSize;
      case ContextWindowMode.specified:
        return (window! ~/ 512).clamp(4, 40);
    }
  }
}
