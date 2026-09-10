import 'model_capabilities.dart';
import 'model_family.dart';
import 'vendors/vendor_profile.dart' show WireProtocol;

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

  /// Descriptors re-described by a serving protocol, keyed by the pair.
  ///
  /// A separate map keyed by a record rather than a composed string: the
  /// pair is the identity, and no separator character can make two
  /// different pairs collide.
  static final Map<(String, WireProtocol), ModelDescriptor> _servedCache = {};

  /// Resolve the descriptor for [modelId]. Cached — classification is pure.
  ///
  /// Without [servedBy] this is the model as its id classifies. With it, it is
  /// the model as that protocol serves it, which differs only where the id
  /// could not have been routed there on its own:
  ///
  /// * **A protocol with a surface of its own** (the Images API, a video
  ///   task…) keeps the id's precise table when the id is one of the models
  ///   it serves, and otherwise describes the model by the protocol — its
  ///   family, and its default table ([ModelCapabilities.forProtocol]). A
  ///   relay's `nano-banana-pro` pinned to the Images API is, for every
  ///   purpose downstream, an unnamed `gpt-image`.
  /// * **A chat face, or images through chat**, demotes a model whose family
  ///   routes somewhere dedicated to the chat family of the same provider:
  ///   `gpt-image-1` sent through chat must stop being the family the Images
  ///   API branch looks for. Gemini's go to [ModelFamily.geminiChat], not
  ///   [ModelFamily.other], because the OpenAI-compatible chat wire adds its
  ///   Gemini extensions by family — and dropping them fails silently.
  ///
  /// Only the dispatcher passes [servedBy], and only when the route differs
  /// from the one the id alone takes, so a model routed as it always was gets
  /// the very same cached object as before.
  ///
  /// The protocol is part of the cache key. Two channels holding the same
  /// model id under different selections are two descriptors; keyed by the id
  /// alone, the second would silently read the first one's family and
  /// parameter table.
  factory ModelDescriptor.of(String modelId, {WireProtocol? servedBy}) {
    final byId = _cache.putIfAbsent(
        modelId,
        () => ModelDescriptor._(
              modelId,
              ModelFamilyClassifier.classify(modelId),
              ModelCapabilities.forModel(modelId),
            ));
    if (servedBy == null) return byId;
    final served = _familyServedBy(byId.family, servedBy);
    if (served == null) return byId;
    return _servedCache.putIfAbsent(
        (modelId, servedBy),
        () => ModelDescriptor._(
              modelId,
              served,
              ModelCapabilities.forProtocol(servedBy),
            ));
  }

  /// The family [protocol] makes of a model whose id classified as [id], or
  /// null when the id's own descriptor already describes it — the protocol
  /// serves that family, so the id's precise table stands.
  static ModelFamily? _familyServedBy(ModelFamily id, WireProtocol protocol) {
    ModelFamily? unlessServes(List<ModelFamily> serves, ModelFamily makes) =>
        serves.contains(id) ? null : makes;

    switch (protocol) {
      case WireProtocol.openaiImages:
        // xAI's image ids already fall back to this surface on relays.
        return unlessServes(
            const [ModelFamily.openaiImage, ModelFamily.xaiImage],
            ModelFamily.openaiImage);
      case WireProtocol.xaiImages:
        return unlessServes(const [ModelFamily.xaiImage], ModelFamily.xaiImage);
      case WireProtocol.geminiImagen:
        return unlessServes(
            const [ModelFamily.geminiImagen], ModelFamily.geminiImagen);
      case WireProtocol.dashscopeImagesSync:
      case WireProtocol.dashscopeImagesAsync:
        return unlessServes(
            const [ModelFamily.dashscopeImage], ModelFamily.dashscopeImage);
      case WireProtocol.minimaxImages:
        return unlessServes(
            const [ModelFamily.minimaxImage], ModelFamily.minimaxImage);
      case WireProtocol.openaiVideos:
      case WireProtocol.xaiVideos:
      case WireProtocol.dashscopeVideo:
      case WireProtocol.minimaxVideo:
      case WireProtocol.minimaxH3BaseVideo:
        return unlessServes(
            const [ModelFamily.openaiVideo], ModelFamily.openaiVideo);
      case WireProtocol.geminiVeo:
        return unlessServes(
            const [ModelFamily.geminiVideo], ModelFamily.geminiVideo);
      case WireProtocol.chatImage:
        // The image families that already draw through chat keep their
        // tables; anything else becomes an image generator with no
        // parameters of its own.
        return unlessServes(
            const [ModelFamily.geminiImage, ModelFamily.midjourney],
            _chatSibling(id));
      case WireProtocol.openaiChat:
      case WireProtocol.anthropicChat:
      case WireProtocol.geminiChat:
      case WireProtocol.dashscopeChat:
      case WireProtocol.midjourney:
        final sibling = _chatSibling(id);
        return sibling == id ? null : sibling;
    }
  }

  /// The chat family of the provider behind [family]: itself for every family
  /// that is already served by chat, and the demotion for the ones routed
  /// somewhere dedicated.
  static ModelFamily _chatSibling(ModelFamily family) {
    switch (family) {
      case ModelFamily.geminiImagen:
      case ModelFamily.geminiVideo:
        return ModelFamily.geminiChat;
      case ModelFamily.openaiImage:
      case ModelFamily.xaiImage:
      case ModelFamily.dashscopeImage:
      case ModelFamily.minimaxImage:
      case ModelFamily.openaiVideo:
        return ModelFamily.other;
      case ModelFamily.geminiImage:
      case ModelFamily.geminiChat:
      case ModelFamily.openaiChat:
      case ModelFamily.midjourney:
      case ModelFamily.other:
        return family;
    }
  }

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
