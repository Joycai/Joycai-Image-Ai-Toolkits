import 'model_capabilities.dart';
import 'model_family.dart';

/// **Layer 3 — the model.**
///
/// A [ModelDescriptor] is everything the rest of the LLM stack is allowed to
/// know about a concrete model id: its [family] classification, its
/// [capabilities] (parameter specs, reference-image limits, generator flags)
/// and a handful of derived routing hints.
///
/// This is the *only* place model-id string sniffing is permitted.
/// [ModelFamilyClassifier] and [ModelCapabilities] are implementation details
/// of this layer — protocols (layer 1) and vendors (layer 2) must never call
/// them directly; they receive a resolved descriptor instead.
class ModelDescriptor {
  final String modelId;
  final ModelFamily family;
  final ModelCapabilities capabilities;

  ModelDescriptor._(this.modelId, this.family, this.capabilities);

  static final Map<String, ModelDescriptor> _cache = {};

  /// Resolve the descriptor for [modelId]. Cached — classification is pure.
  factory ModelDescriptor.of(String modelId) =>
      _cache.putIfAbsent(
          modelId,
          () => ModelDescriptor._(
                modelId,
                ModelFamilyClassifier.classify(modelId),
                ModelCapabilities.forModel(modelId),
              ));

  /// True for any Gemini/Google-served family. When such a model is reached
  /// through an OpenAI-shaped vendor (relay or Google's own OpenAI-compat
  /// endpoint), the chat protocol adds the Gemini compatibility extensions
  /// (`modalities`, `image_config`, `safety_settings`).
  bool get isGeminiFamily => ModelFamilyClassifier.isGemini(family);

  /// True when this id is a Niji variant of Midjourney (drives the proxy's
  /// `botType` field).
  bool get isNijiVariant => modelId.toLowerCase().contains('niji');
}
