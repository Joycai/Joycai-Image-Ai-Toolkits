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

  /// Alibaba DashScope's *native* image surface — `qwen-image*` and
  /// `wan2.7-image*`. These models are not served by the OpenAI-compatible
  /// images API: the only endpoint that generates them speaks DashScope's
  /// own `input`/`parameters` body. On a channel that is not DashScope-native
  /// (a relay), the dispatcher deliberately keeps routing them through chat,
  /// where relays hand images back in the chat response.
  dashscopeImage,

  /// xAI Grok Imagine image generation (`grok-imagine-image*`). On native
  /// xAI channels this uses xAI's JSON `/images/generations` + `/images/edits`
  /// surface (single `image` or up to 3 `images[]` references); on relays it
  /// falls back to the OpenAI-style Images API.
  xaiImage,

  /// MiniMax's native image surface — `image-01` and `image-01-live`. Served
  /// only at `POST /v1/image_generation`, which despite the `/v1` prefix is
  /// not the OpenAI Images API: its own body, its own `data.image_urls`
  /// result and the `base_resp` envelope. Same arrangement as
  /// [dashscopeImage] — on a channel that is not MiniMax (a relay), the
  /// dispatcher keeps routing these through chat.
  minimaxImage,

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
        isNijiVariant(id)) {
      return ModelFamily.midjourney;
    }

    // --- xAI Grok Imagine *image* models ---
    // Must precede the video block: `grok-imagine-image*` also matches the
    // `grok-imagine` video prefix below.
    if (id.contains('grok-imagine-image')) {
      return ModelFamily.xaiImage;
    }

    // --- DashScope native image models ---
    // Must precede the video block, which claims `wan2.5*` wholesale. The
    // same trick for 2.7 (`startsWith('wan2.7')`) would swallow a future
    // `wan2.7-t2v`, so these rules name `-image` and claim nothing else.
    // wan2.6 has not surfaced in any official model enum yet
    // (docs/api/qianwen-bailian.md §7) — the rule is parked here so the id
    // routes correctly the day it appears.
    if (id.startsWith('qwen-image') ||
        id.startsWith('wan2.6-image') ||
        id.startsWith('wan2.7-image')) {
      return ModelFamily.dashscopeImage;
    }

    // --- MiniMax native image models ---
    // `image-01` / `image-01-live`. Matched by prefix rather than equality so
    // the `-live` variant and any future suffix land here; nothing else in
    // the catalog starts with `image-0`.
    if (id.startsWith('image-01')) {
      return ModelFamily.minimaxImage;
    }

    // --- MiniMax native video (H3, async-task only) ---
    // Spelled out in full because `MiniMax-M3` (chat) and `MiniMax-H3`
    // (video) differ by one letter, and a prefix rule loose enough to be
    // convenient here would route the chat model at the video surface.
    // Classifies into [ModelFamily.openaiVideo] ("this is an async video-task
    // model") on the same reasoning as wan3.x below: *which* video protocol
    // serves it is the vendor's declaration, so on a relay the same id keeps
    // the `/v1/videos` route.
    //
    // The second spelling is the HuggingFace repo path — what a self-hosted
    // SGLang H3-Base service loads and expects on the wire
    // (docs/api/minimax.md §8). It cannot be reached by the first prefix
    // (`minimaxai/…` diverges at the eighth character), and the same M3/H3
    // one-letter caution applies: `minimaxai/minimax-m3` (chat, also
    // self-hostable) must stay out of the video family.
    if (id.startsWith('minimax-h3') ||
        id.startsWith('minimaxai/minimax-h3')) {
      return ModelFamily.openaiVideo;
    }

    // --- DashScope native video (wan3.x, async-task only) ---
    // `wan3.0-video(-prime)` matches none of the rules below (`wan2.5*`,
    // `wan-*`, `-t2v`/`-i2v`), so it needs its own — placed with the video
    // block and spelled `wan3` + `-video` so a future `wan3.x-image` is not
    // swallowed. Classifies into [ModelFamily.openaiVideo] ("this is an
    // async video-task model"); *which* video protocol serves it is the
    // vendor's declaration (`videoProtocol`), so on a relay the same id
    // keeps the `/v1/videos` route.
    if (id.startsWith('wan3') && id.contains('-video')) {
      return ModelFamily.openaiVideo;
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

  /// True when this id is a Niji variant of Midjourney. A variant *within*
  /// the midjourney family (it drives the proxy's `botType`), which is why it
  /// is a named predicate here rather than another [ModelFamily] value. Lives
  /// in this rule table so the string rule exists exactly once.
  static bool isNijiVariant(String modelId) =>
      modelId.toLowerCase().contains('niji');

  /// Ids DashScope serves only on its **multimodal** native chat endpoint
  /// (`multimodal-generation/generation`) rather than the text one.
  ///
  /// Sending one of these to `text-generation/generation` is rejected, and
  /// the reverse — an image part on the text endpoint — is worse: the part
  /// is dropped and the model answers as though it had never seen it. Both
  /// halves of the rule therefore live here, in the one file allowed to
  /// recognize a model id.
  ///
  /// Named after the shapes DashScope publishes rather than a vendor prefix:
  /// `qwen-vl-*` / `qwen3-vl-*` (vision), `qwen-omni-*` (any-to-any) and
  /// `qwen-audio-*` (the one family with no compatible-mode route at all).
  static bool isDashScopeMultimodalChat(String modelId) {
    final id = modelId.toLowerCase();
    return id.contains('-vl-') ||
        id.endsWith('-vl') ||
        id.contains('-omni') ||
        id.contains('-audio');
  }

  /// Ids whose chat surface takes text only — image parts either 400 or,
  /// worse, get silently dropped. DeepSeek's chat/completions endpoint does
  /// not serve its multimodal models (as of 2026-08).
  static bool isTextOnlyChat(String modelId) =>
      modelId.toLowerCase().contains('deepseek');

  /// Mock ids used by the simulated long-running-operation path
  /// (`mock-*`). A Layer 3 fact so the dispatcher never sniffs a model id.
  static bool isMockModel(String modelId) => modelId.startsWith('mock-');

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
        f == ModelFamily.dashscopeImage ||
        f == ModelFamily.minimaxImage ||
        f == ModelFamily.midjourney;
  }

  /// True for long-running video generation.
  static bool isVideo(ModelFamily f) =>
      f == ModelFamily.geminiVideo || f == ModelFamily.openaiVideo;

  /// Convenience id-level helper used by the discovery/tagging UI.
  static String inferTag(String modelId) {
    final family = classify(modelId);
    if (isVideo(family)) return 'video';
    if (isImageGeneration(family)) return 'image';
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
