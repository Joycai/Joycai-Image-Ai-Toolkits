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

  /// ByteDance Seedream on Volcengine Ark (`doubao-seedream-*`). Served at
  /// `POST {base}/images/generations` — the OpenAI Images path, but Ark's own
  /// body: references travel as a JSON `image` field rather than an
  /// `/images/edits` multipart, sizes are resolution tiers (`2K`) or pixels,
  /// and group generation, watermark and 5.0 pro's layer decomposition have
  /// no OpenAI equivalent (docs/api/volcengine-ark.md). Because the path is
  /// the Images API's, a relay that passes the body through serves it too —
  /// unlike [dashscopeImage] / [minimaxImage], whose native paths mean
  /// nothing on a relay host.
  seedreamImage,

  /// Anything else routed through an OpenAI-compatible relay (Claude, etc.).
  /// Treated as a plain chat model with no provider-specific extensions.
  other,
}

/// Which generation of ③'s `generationConfig.thinkingConfig` a Gemini model
/// takes. The two fields sit side by side in one object and are told apart
/// only by the error the wrong model returns (docs/api/reasoning.md §1.5), so
/// exactly one is ever sent.
enum GeminiThinkingGeneration {
  /// No `thinkingConfig` at all: a model that does not think. The API
  /// reference: "An error will be returned if this field is set for models
  /// that don't support thinking."
  none,

  /// `thinkingBudget` (Gemini 2.5).
  budget,

  /// `thinkingLevel` (Gemini 3 and later) — "Use with earlier models results
  /// in an error."
  level,
}

class ModelFamilyClassifier {
  /// The `thinkingConfig` generation for [modelId].
  ///
  /// Reads the first version after `gemini-`: 3+ → [GeminiThinkingGeneration
  /// .level], 2.5 → [GeminiThinkingGeneration.budget], anything older (2.0,
  /// 1.5, 1.0) → [GeminiThinkingGeneration.none].
  ///
  /// An id with no readable Gemini version — a relay's free-text name, an
  /// alias like `gemini-flash-latest` — gets [GeminiThinkingGeneration.level],
  /// the current generation. The guess is optimistic on purpose (reasoning 03
  /// §3): every way it can be wrong is loud (a 2.5 model or a non-thinking
  /// model answers the field with an error naming it), while guessing "none"
  /// would silently make the reasoning control do nothing. It also costs
  /// nothing at the default effort, which sends no field at all.
  static GeminiThinkingGeneration geminiThinkingGeneration(String modelId) {
    final m = RegExp(r'gemini-(\d+)(?:\.(\d+))?').firstMatch(modelId.toLowerCase());
    if (m == null) return GeminiThinkingGeneration.level;
    final major = int.parse(m.group(1)!);
    final minor = int.tryParse(m.group(2) ?? '') ?? 0;
    if (major >= 3) return GeminiThinkingGeneration.level;
    if (major == 2 && minor >= 5) return GeminiThinkingGeneration.budget;
    return GeminiThinkingGeneration.none;
  }

  /// Classify a raw model id (case-insensitive).
  static ModelFamily classify(String modelId) {
    final id = modelId.toLowerCase();

    // --- Midjourney family (matches MJ / Niji ids served via proxy) ---
    if (id.startsWith('mj_') || id == 'mj' || id.contains('midjourney') || isNijiVariant(id)) {
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

    // --- Volcengine Ark Seedream ---
    // `doubao-seedream-4-0-250828`, `doubao-seedream-5-0-pro-260628`, and the
    // subscription plan's undated `doubao-seedream-5.0-lite` — matched on the
    // product name alone, since the vendor prefix, the version separator
    // (`-` or `.`) and the date suffix all vary. Which *version* an id is
    // decides its parameter table; that reading is [seedreamVersion]. Nothing
    // else in any catalog contains `seedream` — ByteDance's video line is
    // `seedance`, a different word.
    if (id.contains('seedream')) {
      return ModelFamily.seedreamImage;
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
    if (id.startsWith('minimax-h3') || id.startsWith('minimaxai/minimax-h3')) {
      return ModelFamily.openaiVideo;
    }

    // --- MiniMax cloud video, Hailuo generation ---
    // `MiniMax-Hailuo-2.3(-Fast)` / `MiniMax-Hailuo-02`, and the older
    // `video-01` / `T2V-01(-Director)` / `I2V-01(-Director|-live)` / `S2V-01`
    // ids (platform.minimax.io video-generation reference). Without these
    // rules every one of them classified as chat and the video workbench
    // could not list them on any channel — the generic `-t2v`/`-i2v` rule
    // below misses `T2V-01`, whose marker sits at the start of the id.
    //
    // Classifies into [ModelFamily.openaiVideo] ("this is an async
    // video-task model") on the same reasoning as H3 above: *which* video
    // protocol serves it is the vendor's declaration, so on a relay these
    // ids ride the `/v1/videos` route (NewAPI exposes Hailuo under its
    // unified video format). Note MiniMax's *own* current `/v2` task surface
    // documents only `MiniMax-H3` — the Hailuo generation lives on the
    // legacy `/v1/video_generation` wire this app does not implement — so on
    // an official MiniMax channel these ids submit to `/v2` and stand or
    // fall with what that surface still accepts. The `minimax-hailuo` prefix
    // cannot collide with the chat ids (`MiniMax-M3`, `abab*`), and the
    // spelled-out `?2v-01` prefixes keep the same caution as H3 vs M3 above.
    if (id.startsWith('minimax-hailuo') ||
        id.startsWith('video-01') ||
        id.startsWith('t2v-01') ||
        id.startsWith('i2v-01') ||
        id.startsWith('s2v-01')) {
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
    if (id.startsWith('gpt') || id.contains('gpt-') || _isOpenAIReasoning(id)) {
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
  static bool isNijiVariant(String modelId) => modelId.toLowerCase().contains('niji');

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
  /// worse, get silently dropped.
  ///
  /// DeepSeek is the one vendor here, and no longer wholesale: image
  /// understanding arrived on `chat/completions` with DeepSeek-V4.1-Flash, so
  /// the rule is a *subtraction* from the deepseek name rather than the whole
  /// name. Sees images: `deepseek-flash`, the still-callable legacy names
  /// `deepseek-v4-flash` / `deepseek-v4-flash-vision-exp` (both now served by
  /// V4.1-Flash), and the open-source `deepseek-vl*` weights relays host.
  /// Text only: `deepseek-v4-pro`, and the V3-era `deepseek-chat` /
  /// `deepseek-reasoner`.
  ///
  /// Subtraction, not a `flash` allow-list, because `acceptsImageInput`
  /// defaults to *true*: a DeepSeek id this rule has never heard of is likelier
  /// to be another vision generation than another `-pro`. `flash` cannot
  /// collide with another vendor's id here — the name must already contain
  /// `deepseek` to be tested at all.
  static bool isTextOnlyChat(String modelId) {
    final id = modelId.toLowerCase();
    if (!id.contains('deepseek')) return false;
    return !id.contains('flash') && !id.contains('-vl') && !id.contains('vision');
  }

  /// Claude ids whose generation knows only the **manual** thinking form
  /// (`{type: "enabled", budget_tokens}`): 4.5 and everything before it.
  ///
  /// Adaptive thinking and `output_config` arrived with 4.6; 4.7 rejects the
  /// manual form outright. The two generations are served on the same host
  /// under the same key, so the vendor profile can only carry a default and
  /// this rule is what points the older models back. Anything that is not
  /// recognizably a Claude id answers false — the vendor default then
  /// applies, and the ④ protocol's on-400 retry covers relays that rename
  /// their models.
  ///
  /// Reads the first version number after `claude` (and an optional tier
  /// word): `claude-sonnet-4-5-20250929` → 4.5, `claude-3-7-sonnet-…` → 3.7,
  /// `claude-sonnet-4-20250514` → 4.0 (a date is not a minor version),
  /// `claude-opus-4.6` → 4.6, `claude-opus-5` → 5.0.
  static bool isLegacyClaudeThinking(String modelId) {
    final id = modelId.toLowerCase();
    if (!id.contains('claude')) return false;
    final m = RegExp(
      r'claude(?:[-_](?:opus|sonnet|haiku))?[-_](\d+)(?:[-_.](\d+))?',
    ).firstMatch(id);
    if (m == null) return false;
    final major = int.parse(m.group(1)!);
    final minorRaw = m.group(2);
    // A trailing 8-digit date (`-20250514`) is not a minor version.
    final minor = (minorRaw == null || minorRaw.length >= 4) ? 0 : int.parse(minorRaw);
    if (major < 4) return true;
    return major == 4 && minor <= 5;
  }

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

  /// True when the model's primary job is to *generate* images
  /// (as opposed to chat models that may merely accept image input).
  static bool isImageGeneration(ModelFamily f) {
    return f == ModelFamily.geminiImage ||
        f == ModelFamily.geminiImagen ||
        f == ModelFamily.openaiImage ||
        f == ModelFamily.xaiImage ||
        f == ModelFamily.dashscopeImage ||
        f == ModelFamily.minimaxImage ||
        f == ModelFamily.seedreamImage ||
        f == ModelFamily.midjourney;
  }

  /// The Seedream generation an id names, as `(major, minor)` — `(5, 0)` for
  /// `doubao-seedream-5-0-pro-260628` and for `doubao-seedream-5.0-lite`
  /// alike — or null when the id carries no readable version.
  ///
  /// The separator is `-` in the dated ids and `.` in the plan's aliases; the
  /// six-digit date after the version (`-250828`) is never read as a minor.
  static (int, int)? seedreamVersion(String modelId) {
    final m = RegExp(
      r'seedream[-_]?(\d+)(?:[-_.](\d{1,2}))?(?!\d)',
    ).firstMatch(modelId.toLowerCase());
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.tryParse(m.group(2) ?? '') ?? 0);
  }

  /// Whether a Seedream id is the **pro** tier of its generation
  /// (`doubao-seedream-5-0-pro-260628`, `doubao-seedream-5.0-pro`). Lite is
  /// spelled three ways — `-lite-260128`, `.0-lite`, and the bare dated
  /// `5-0-260128` — so pro is the one worth naming.
  static bool isSeedreamPro(String modelId) =>
      RegExp(r'seedream.*[-_.]pro(?:[-_.]|$)').hasMatch(modelId.toLowerCase());

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
    if (id.contains('claude') && (id.contains('opus') || id.contains('sonnet'))) {
      return 'multimodal';
    }
    if (id.contains('vision')) return 'multimodal';

    return 'chat';
  }
}
