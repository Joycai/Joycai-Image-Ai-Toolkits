import 'package:flutter/foundation.dart';

import '../llm_types.dart';
import '../vendors/vendor_profile.dart';
import 'anthropic_wire.dart';
import 'protocol.dart';

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
    case ThinkingDialect.openaiEnableThinking:
    case ThinkingDialect.openaiAdaptiveObject:
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
      ThinkingDialect.openaiThinkingObject ||
      ThinkingDialect.openaiEnableThinking ||
      ThinkingDialect.openaiAdaptiveObject => null,
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
  return declaredAnthropicThinkingDialect(
    target.vendor.thinking,
    legacyModel: target.model.usesLegacyAnthropicThinking,
  );
}

/// The spelling a vendor's declared [dialect] takes for one model, before
/// anything has been learned from a rejection: a model whose generation knows
/// only the manual form gets the budget spelling on either Anthropic dialect.
///
/// Split out so the model editor's reasoning ladder
/// (`LLMDispatcher.reasoningLadder`) reads the same decision the request does.
ThinkingDialect declaredAnthropicThinkingDialect(
  ThinkingDialect dialect, {
  required bool legacyModel,
}) {
  final isAnthropicSpelling =
      dialect == ThinkingDialect.anthropicAdaptive ||
      dialect == ThinkingDialect.anthropicBudget;
  if (isAnthropicSpelling && legacyModel) {
    return ThinkingDialect.anthropicBudget;
  }
  return dialect;
}

/// Records that [rejected] was refused for this endpoint + model and returns
/// the spelling to retry with, or null when there is none.
ThinkingDialect? learnAnthropicThinkingDialect(
  LLMTarget target,
  ThinkingDialect rejected,
) {
  final alternate = alternateAnthropicThinkingDialect(rejected);
  if (alternate != null) {
    _learnedThinkingDialects[_thinkingMemoKey(target)] = alternate;
  }
  return alternate;
}

/// Forgets every learned dialect. Tests only.
@visibleForTesting
void resetAnthropicThinkingDialectsForTest() =>
    _learnedThinkingDialects.clear();

/// Whether [error] is the API refusing the *shape* of the thinking request —
/// the one 400 worth answering with the other dialect.
///
/// Deliberately narrow. A 400 about `output_config.effort` being unsupported
/// on this model is a level the user can lower, and switching to the budget
/// spelling would only produce a second, unrelated 400; a 400 about
/// `budget_tokens` being too small is the cap, not the dialect. What flips
/// the dialect is the API not knowing the field at all: `thinking.type` with
/// an unexpected value, or an `output_config` it has never heard of.
///
/// Anything else that merely *mentions* thinking is not it, and matters
/// because the answer is learned for the rest of the session: a replayed
/// turn missing its thinking block or signature (`messages.3.content.0…`,
/// "must start with a thinking block"), a `max_tokens` that does not clear
/// `thinking.budget_tokens`. Flipping the dialect on those used to swap a
/// working spelling for a broken one and keep it.
bool isAnthropicThinkingRejection(Object error) {
  if (error is! LLMApiException || error.statusCode != 400) return false;
  final text = error.message.toLowerCase();
  if (!text.contains('thinking') && !text.contains('output_config')) {
    return false;
  }
  // A complaint about the *value* of effort is not a dialect problem.
  if (text.contains('effort')) return false;
  if (_notADialectProblem.any(text.contains)) return false;
  if (text.contains('thinking.type') || text.contains('output_config')) {
    return true;
  }
  // The field-level spellings: `thinking: Input tag 'adaptive' found using
  // 'type' does not match…`, "adaptive thinking is not supported".
  return _thinkingShapeComplaint.hasMatch(text);
}

/// Phrases that put a thinking-related 400 on something other than the
/// request's thinking spelling — see [isAnthropicThinkingRejection].
const List<String> _notADialectProblem = [
  'budget_tokens',
  'max_tokens',
  'signature',
  'messages.',
  'thinking block',
  'redacted_thinking',
];

final RegExp _thinkingShapeComplaint = RegExp(
    r'thinking\W[^.]*\b(type|tag|adaptive|enabled|disabled)\b|'
    r'\b(adaptive|enabled) thinking\b');
