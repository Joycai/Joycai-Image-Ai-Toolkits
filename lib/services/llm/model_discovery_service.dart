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
/// read the same way as the upstream. The discovery dialog seeds a **new**
/// row with these; a stored row is the user's and is never rewritten.
DiscoveredLimits discoveredLimitsOf(DiscoveredModel model) {
  final raw = model.rawData;
  final topProvider = raw['top_provider'];
  return DiscoveredLimits(
    contextWindow: _positiveInt(raw['max_input_tokens']) ??
        _positiveInt(raw['inputTokenLimit']) ??
        _positiveInt(raw['context_length']) ??
        _positiveInt(raw['max_context_length']) ??
        _positiveInt(raw['context_window']),
    maxOutputTokens: _positiveInt(raw['max_tokens']) ??
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
