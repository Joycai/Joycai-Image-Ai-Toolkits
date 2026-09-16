import '../image_compression.dart';
import 'protocol.dart';

/// Fallback for Anthropic's mandatory `max_tokens`.
///
/// ④ is the only family whose output cap has no server-side default — omit it
/// and the request is rejected outright — so an adapter must carry a constant.
/// 8192 is the largest value every Claude model still in service accepts;
/// going higher would 400 on the older ones, and the current generation caps
/// far above it (128K), so nothing is lost that the user cannot raise in the
/// model editor (`llm_models.max_output_tokens`) or a caller per request via
/// `options['maxTokens']`. It is also the cap thinking shares — the Prompt
/// Assistant's 6–8K-token deliveries are why the editor exists.
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

/// Cap on searches per request. Billing is per search *and* every result is
/// re-billed as input on each later iteration and turn, and this field is the
/// only brake the API offers; without it a curious model can run a dozen
/// searches for one question.
const int anthropicWebSearchMaxUses = 5;

/// ①-vocabulary `finish_reason` published for ④'s `pause_turn`: the host
/// suspended a long server-tool turn and wants the assistant message sent
/// back unchanged so the model can continue it. Not `stop` — a turn that
/// ends here has a search in it and no answer after it.
const String anthropicPauseFinishReason = 'pause';

/// Metadata key set when a turn ended on a server-tool result with no text
/// after it while claiming `end_turn` — MiniMax's ④ face does this (it runs
/// the search, hands the results back and does not call the model again).
/// No field says anything was cut short; the shape is the only signal.
const String anthropicTurnIncompleteKey = 'turn_incomplete';

/// Floor Anthropic puts under `thinking.budget_tokens`. Below it the request
/// is rejected rather than clamped.
const int anthropicMinThinkingBudget = 1024;

/// The output cap for a request: what [outputCapFor] ranks (the caller's
/// `maxTokens`, then the model's stored cap), [anthropicDefaultMaxTokens]
/// otherwise — ④'s field is mandatory, so this is the one wire that never
/// answers null.
int anthropicMaxTokens(LLMTarget target, Map<String, dynamic>? options) =>
    outputCapFor(target, options) ?? anthropicDefaultMaxTokens;
