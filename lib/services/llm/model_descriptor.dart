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
  bool get isNijiVariant => ModelFamilyClassifier.isNijiVariant(modelId);

  /// Whether the model accepts image *input* (multimodal understanding), as
  /// opposed to the generation-side capabilities in [capabilities].
  ///
  /// Drives whether image-viewing tools are offered to agent loops: sending
  /// an `image_url` part to a text-only endpoint either 400s or — worse —
  /// gets silently dropped, so the model answers as if it saw the image.
  ///
  /// Default is true (the historical behavior); only families/ids known to be
  /// text-only opt out — the rule itself lives in the classifier's table.
  bool get acceptsImageInput => !ModelFamilyClassifier.isTextOnlyChat(modelId);

  /// Whether DashScope's *native* chat surface serves this model on its
  /// multimodal endpoint rather than its text one.
  ///
  /// Read by the native chat protocol to pick between the two paths. A fact
  /// about the model, not about the vendor — which is why it is answered
  /// here rather than by a branch inside the protocol.
  bool get needsMultimodalChatSurface =>
      ModelFamilyClassifier.isDashScopeMultimodalChat(modelId);

  /// Whether this is a Claude of the generation (4.5 and earlier) that knows
  /// only the manual thinking form and rejects the adaptive one.
  ///
  /// Read by the ④ protocol to override the vendor's default
  /// `ThinkingDialect`: both generations live on one host under one key, so
  /// the vendor can only say what the *current* spelling is, and this is the
  /// per-model exception. False for anything not recognizably a Claude id.
  bool get usesLegacyAnthropicThinking =>
      ModelFamilyClassifier.isLegacyClaudeThinking(modelId);

  /// True for the `mock-*` ids the simulated long-running-operation path
  /// accepts. Here rather than in the dispatcher because model-id sniffing is
  /// this layer's monopoly.
  bool get isMockModel => ModelFamilyClassifier.isMockModel(modelId);
}
