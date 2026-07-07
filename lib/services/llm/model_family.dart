/// Single source of truth for classifying a model id into a "family".
///
/// A family determines two things across the app:
///  1. Which API *dialect* an OpenAI-compatible transport should speak
///     (native OpenAI vs. Gemini-via-OpenAI-compat extensions).
///  2. What kind of task a model performs (image / video / chat), used for
///     auto-tagging during model discovery.
///
/// This consolidates the ad-hoc `modelId.contains(...)` sniffing that was
/// previously duplicated inside the providers, the discovery dialog and the
/// setup wizard.
enum ModelFamily {
  /// Google Veo — long-running video generation.
  geminiVideo,

  /// Google Imagen — dedicated image generation via `:predict`.
  geminiImagen,

  /// "nanoBanana" style models, e.g. `gemini-2.5-flash-image` — image output
  /// via the standard `:generateContent` / chat surface.
  geminiImage,

  /// General Gemini multimodal / chat models.
  geminiChat,

  /// OpenAI dedicated image models, e.g. `gpt-image-1`.
  openaiImage,

  /// OpenAI chat / reasoning models, e.g. `gpt-4o`, `gpt-5`, `o3`.
  openaiChat,

  /// Midjourney / Niji image generation served through a midjourney-proxy
  /// (NewAPI, novicezk/midjourney-proxy, …). Async submit → poll → image URL.
  midjourney,

  /// OpenAI-compatible video generation served at `/v1/videos`
  /// (Sora 2, grok-imagine, Aliyun Wanxiang, Kling, Vidu, Jimeng, …). Async
  /// submit → poll → mp4 URL. Routed through the OpenAI transport, not Google.
  openaiVideo,

  /// xAI Grok Imagine image generation (`grok-imagine-image*`). On native
  /// xAI channels this uses xAI's JSON `/images/generations` + `/images/edits`
  /// surface (single `image` or up to 3 `images[]` references); on relays it
  /// falls back to the OpenAI-style Images API.
  xaiImage,

  /// Anything else routed through an OpenAI-compatible relay (Claude, etc.).
  /// Treated as a plain chat model with no provider-specific extensions.
  other,
}

class ModelFamilyClassifier {
  /// Classify a raw model id (case-insensitive).
  static ModelFamily classify(String modelId) {
    final id = modelId.toLowerCase();

    // --- Midjourney family (matches MJ / Niji ids served via proxy) ---
    if (id.startsWith('mj_') ||
        id == 'mj' ||
        id.contains('midjourney') ||
        id.contains('niji')) {
      return ModelFamily.midjourney;
    }

    // --- xAI Grok Imagine *image* models ---
    // Must precede the video block: `grok-imagine-image*` also matches the
    // `grok-imagine` video prefix below.
    if (id.contains('grok-imagine-image')) {
      return ModelFamily.xaiImage;
    }

    // --- OpenAI-compatible video (Sora-style /v1/videos) ---
    // Matches the catalog NewAPI exposes under the openai-video format:
    // sora-2, sora-2-pro, grok-imagine-*, wan2.5-{t2v,i2v}-*, kling-v*, viduq*,
    // jimeng_* — plus any id with the `t2v` / `i2v` suffix convention.
    if (id.startsWith('sora') ||
        id.startsWith('grok-imagine') ||
        id.startsWith('wan2.5') ||
        id.startsWith('wan-') ||
        id.startsWith('kling') ||
        id.startsWith('viduq') ||
        id.startsWith('vidu-') ||
        id.startsWith('jimeng') ||
        id.contains('-t2v') ||
        id.contains('-i2v')) {
      return ModelFamily.openaiVideo;
    }

    // --- Google families (order matters: most specific first) ---
    if (id.contains('veo')) return ModelFamily.geminiVideo;
    if (id.contains('imagen')) return ModelFamily.geminiImagen;
    // nanoBanana: a gemini model that also emits images.
    if (id.contains('gemini') && id.contains('image')) {
      return ModelFamily.geminiImage;
    }
    if (id.contains('gemini')) return ModelFamily.geminiChat;

    // --- OpenAI families ---
    // gpt-image-1 and friends. Must precede the generic gpt-* check.
    if (id.contains('gpt-image') || id.contains('gpt-image-1')) {
      return ModelFamily.openaiImage;
    }
    if (id.startsWith('gpt') ||
        id.contains('gpt-') ||
        _isOpenAIReasoning(id)) {
      return ModelFamily.openaiChat;
    }

    return ModelFamily.other;
  }

  /// `o1` / `o3` / `o4` reasoning models (optionally suffixed, e.g. `o3-mini`).
  static bool _isOpenAIReasoning(String id) {
    return RegExp(r'(^|[^a-z])o[1-9](-|$)').hasMatch(id);
  }

  /// True for any Gemini/Google-served family. These need the OpenAI-compat
  /// Gemini extensions when routed through an OpenAI-style relay.
  static bool isGemini(ModelFamily f) {
    return f == ModelFamily.geminiVideo ||
        f == ModelFamily.geminiImagen ||
        f == ModelFamily.geminiImage ||
        f == ModelFamily.geminiChat;
  }

  /// True for native OpenAI families.
  static bool isOpenAINative(ModelFamily f) {
    return f == ModelFamily.openaiImage || f == ModelFamily.openaiChat;
  }

  /// True when the model's primary job is to *generate* images
  /// (as opposed to chat models that may merely accept image input).
  static bool isImageGeneration(ModelFamily f) {
    return f == ModelFamily.geminiImage ||
        f == ModelFamily.geminiImagen ||
        f == ModelFamily.openaiImage ||
        f == ModelFamily.xaiImage ||
        f == ModelFamily.midjourney;
  }

  /// True for long-running video generation.
  static bool isVideo(ModelFamily f) =>
      f == ModelFamily.geminiVideo || f == ModelFamily.openaiVideo;

  /// Convenience id-level helper used by the discovery/tagging UI.
  static String inferTag(String modelId) {
    final family = classify(modelId);
    if (isVideo(family)) return 'video';
    if (family == ModelFamily.geminiImage ||
        family == ModelFamily.geminiImagen ||
        family == ModelFamily.openaiImage ||
        family == ModelFamily.xaiImage ||
        family == ModelFamily.midjourney) {
      return 'image';
    }
    if (family == ModelFamily.geminiChat) return 'multimodal';

    // Heuristics that don't map to a provider family but still inform tagging.
    final id = modelId.toLowerCase();
    if (id.contains('claude') &&
        (id.contains('opus') || id.contains('sonnet'))) {
      return 'multimodal';
    }
    if (id.contains('vision')) return 'multimodal';

    return 'chat';
  }
}
