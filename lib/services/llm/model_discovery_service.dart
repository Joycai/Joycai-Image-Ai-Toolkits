import 'llm_dispatcher.dart';
import 'llm_types.dart';
import 'protocols/protocol.dart' show DiscoveredModel;

export 'protocols/protocol.dart' show DiscoveredModel;

/// Model listing facade. The discovery protocol is picked by the dispatcher
/// from the channel's vendor (layer 2), exactly like generation requests.
class ModelDiscoveryService {
  static final ModelDiscoveryService _instance = ModelDiscoveryService._internal();
  factory ModelDiscoveryService() => _instance;
  ModelDiscoveryService._internal();

  final LLMDispatcher _dispatcher = LLMDispatcher();

  Future<List<DiscoveredModel>> discoverModels(LLMModelConfig config) =>
      _dispatcher.discoverModels(config);
}

/// The two limits a listing may report about a model, in tokens; null when
/// the listing did not say.
class DiscoveredLimits {
  final int? contextWindow;
  final int? maxOutputTokens;

  const DiscoveredLimits({this.contextWindow, this.maxOutputTokens});

  static const none = DiscoveredLimits();
}

/// What a model listing says about a model's window and output cap.
///
/// No protocol tells a caller the window (usage 04 §4), but some listings
/// do, each under its own name: Anthropic's `GET /models` carries
/// `max_input_tokens` and `max_tokens` (since 2026-03), Gemini's
/// `inputTokenLimit` / `outputTokenLimit`, OpenRouter's `context_length` and
/// `top_provider.max_completion_tokens`, LM Studio's `max_context_length`.
/// Read by key shape, not by vendor: the keys do not collide, an absent key
/// is simply unknown, and a relay that forwards an upstream listing gets
/// read the same way as the upstream. Two guards: a bare `max_tokens` is
/// read only beside `max_input_tokens` (Anthropic's shape) — on its own the
/// name has meant a context length or a request default elsewhere; and
/// OpenRouter's window is the smaller of the model-level `context_length`
/// and the top provider's, which is what the routed request actually gets.
///
/// The discovery dialog seeds a **new** row's window with this; the output
/// cap it reports is a model's *maximum*, not a cap anyone chose to send —
/// stored, it would go out on every request, size the deadline and the ④
/// thinking budget, and exceed input + output on a long session — so the
/// cap stays unset for the user to pick (the editor names the maximum in
/// its captions). A stored row is the user's and is never rewritten.
DiscoveredLimits discoveredLimitsOf(DiscoveredModel model) {
  final raw = model.rawData;
  final topProvider = raw['top_provider'];
  final providerWindow = _positiveInt(topProvider is Map ? topProvider['context_length'] : null);
  final modelWindow = _positiveInt(raw['context_length']);
  final openRouterWindow = modelWindow == null || providerWindow == null
      ? (modelWindow ?? providerWindow)
      : (modelWindow < providerWindow ? modelWindow : providerWindow);
  final anthropicShape = raw['max_input_tokens'] != null;
  return DiscoveredLimits(
    contextWindow:
        _positiveInt(raw['max_input_tokens']) ??
        _positiveInt(raw['inputTokenLimit']) ??
        openRouterWindow ??
        _positiveInt(raw['max_context_length']) ??
        _positiveInt(raw['context_window']),
    maxOutputTokens:
        (anthropicShape ? _positiveInt(raw['max_tokens']) : null) ??
        _positiveInt(raw['outputTokenLimit']) ??
        _positiveInt(raw['max_output_tokens']) ??
        _positiveInt(raw['max_completion_tokens']) ??
        _positiveInt(topProvider is Map ? topProvider['max_completion_tokens'] : null),
  );
}

int? _positiveInt(Object? value) {
  final n = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  return n == null || n <= 0 ? null : n;
}
