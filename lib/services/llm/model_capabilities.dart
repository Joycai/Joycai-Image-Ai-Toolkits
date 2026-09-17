import 'image_size_rules.dart';
import 'model_family.dart';
import 'param_spec.dart';
import 'vendors/vendor_profile.dart' show WireProtocol;

export 'param_spec.dart';

part 'model_capability_tables.dart';

/// Which request body an image model's endpoint expects, when the family
/// default (one shape per protocol) is not enough.
///
/// DashScope is the reason this exists: its two generations of image models
/// are served by the same host under the same auth, but disagree about where
/// the conversation goes — `qwen-image*` nests it under `input`, `wan2.7-*`
/// puts it at the top level. Declaring the shape here keeps the protocol free
/// of the model-id branch that would otherwise decide it (layer-1 code may
/// not sniff ids; this file may).
enum ImageRequestShape {
  /// Not a DashScope-native model — the protocol's own default shape.
  none,

  /// `{model, input: {messages: [...]}, parameters: {...}}`.
  dashscopeQwen,

  /// `{model, messages: [...], parameters: {...}}`.
  dashscopeWan,
}

/// What a model family can do, and which parameters apply to it.
class ModelCapabilities {
  /// True when the model's primary output is a generated image (and therefore
  /// the image parameter controls should be shown).
  final bool isImageGenerator;

  /// True when the model's primary output is a generated video (Veo, Sora,
  /// grok-imagine, Wanxiang, Kling, …). Drives whether the video panel renders
  /// per-model controls beyond the shared resolution/aspect dropdowns.
  final bool isVideoGenerator;

  /// The image-generation parameters this family understands. Empty for chat /
  /// multimodal / video models — which is what keeps the wrong controls from
  /// showing up for, say, a GPT-4o chat model or a `gemini-2.5-pro` text model.
  final List<ParamSpec> imageParams;

  /// The video-generation parameters this family understands beyond the shared
  /// resolution/aspect-ratio controls (e.g. Sora's `seconds`, `quality`).
  /// Rendered by the video panel via the same per-model dropdown pattern as
  /// `imageParams`. Empty for Veo (the existing fixed controls cover it).
  final List<ParamSpec> videoParams;

  /// True when a single request runs the whole generation upstream, so the
  /// caller's per-request timeout has to be lifted to generation timescales
  /// rather than API-response ones.
  ///
  /// DashScope's synchronous image endpoint is the case in point: it answers
  /// only once the image exists, which for a 2K `wan2.7-image` can outlast
  /// the 120 s that fits a chat completion — and the generation is billed
  /// before the client gives up, so the default guard turns a paid result
  /// into a timeout message. Read by `LLMDispatcher.generateTimeout`.
  final bool longRunning;

  /// Which request body this model's image endpoint expects. [
  /// ImageRequestShape.none] for every family whose protocol has only one
  /// shape.
  final ImageRequestShape imageRequestShape;

  /// True when this image model is also served by DashScope's async task
  /// surface (`image-generation/generation` + `X-DashScope-Async`), making
  /// sync/async a genuine per-model choice. `wan2.7-image*` documents both
  /// routes; `qwen-image*` documents only the synchronous one, so its menu
  /// collapses to a single entry and the protocol selector never renders.
  /// The dispatcher intersects the vendor's image menu with this.
  final bool supportsAsyncImageTask;

  /// How many reference (input) images this family accepts for generation:
  ///  * `null` — supported with no enforced limit (e.g. nanoBanana).
  ///  * `0` — not supported at all (e.g. Imagen text-to-image).
  ///  * `> 0` — supported up to this many (e.g. OpenAI `gpt-image-1`).
  final int? maxReferenceImages;

  const ModelCapabilities({
    this.isImageGenerator = false,
    this.isVideoGenerator = false,
    this.imageParams = const [],
    this.videoParams = const [],
    this.maxReferenceImages,
    this.longRunning = false,
    this.imageRequestShape = ImageRequestShape.none,
    this.supportsAsyncImageTask = false,
  });

  /// Whether the model accepts any reference images at all.
  bool get supportsReferenceImages => maxReferenceImages != 0;

  static ModelCapabilities forModel(String modelId) {
    final family = ModelFamilyClassifier.classify(modelId);
    final id = modelId.toLowerCase();

    // gpt-image-2 shares the OpenAI image transport with gpt-image-1 but accepts
    // a much larger size set (2K / 4K), so it resolves to its own table.
    // gpt-image-2.5 (flare / sunburst) keeps the 2 size rules and adds two
    // quality rungs — its id also contains `gpt-image-2`, so it must be
    // checked first.
    if (family == ModelFamily.openaiImage) {
      if (id.contains('gpt-image-2.5')) return _openaiImage25;
      if (id.contains('gpt-image-2')) return _openaiImage2;
    }

    // Nano Banana variants share the gemini-*-image transport but expose wider
    // aspect-ratio sets than the generic nanoBanana table.
    if (family == ModelFamily.geminiImage) {
      if (id.contains('gemini-3.1-flash-image')) return _geminiImageV2;
      if (id.contains('gemini-3.1-pro-image')) return _geminiImagePro;
      // The 2.5 generation has no resolution parameter at all.
      if (id.contains('gemini-2.5-flash-image')) return _geminiImageLegacy;
    }

    // grok-imagine-video-1.5 exposes a different parameter set (1:1 / 4:3 /
    // 3:2 aspect ratios, 480p–1080p resolution, a 1–15s duration slider) than
    // the generic Sora-style openaiVideo table.
    if (family == ModelFamily.openaiVideo && id.contains('grok-imagine-video')) {
      return _grokImagineVideo;
    }

    // wan3.x on DashScope's native video-synthesis surface: its own
    // resolution/ratio vocabulary, a 2–30 s duration range and an audio
    // toggle whose upstream default (on) is billed — so it is exposed rather
    // than silently inherited.
    if (family == ModelFamily.openaiVideo && id.startsWith('wan3')) {
      return _dashscopeWanVideo;
    }

    // MiniMax-H3 on the native `/v2/video_generation` task surface: two
    // resolution tiers rather than the usual three, and a 4–15 s window that
    // starts above the Sora-style table's floor.
    if (family == ModelFamily.openaiVideo && id.startsWith('minimax-h3')) {
      return _minimaxVideo;
    }

    // The same model behind the self-hosted SGLang H3-Base surface, which
    // spells its id as the HuggingFace repo path (`MiniMaxAI/MiniMax-H3`,
    // docs/api/minimax.md §8). The id difference is what lets the two
    // deployments carry different tables: the open checkpoints generate 768p
    // only, so the cloud table's 768P/2K resolution control would be a knob
    // whose upper half silently does nothing.
    if (family == ModelFamily.openaiVideo &&
        id.startsWith('minimaxai/minimax-h3')) {
      return _minimaxH3Base;
    }

    // DashScope's two shapes (see [ImageRequestShape]) also differ in their
    // reference-image ceiling and size vocabulary, so they are two tables —
    // three, counting the basic `qwen-image-edit`, which alone in its family
    // takes no `size` at all (docs/api/qianwen-bailian.md §4.1: "不支持
    // size", 400 on receiving one). `-max` / `-plus` and the dated builds of
    // those are ordinary qwen-image models and keep the shared table.
    if (family == ModelFamily.dashscopeImage) {
      if (id.startsWith('wan')) return _dashscopeWanImage;
      if (id.startsWith('qwen-image-edit') &&
          !id.contains('-max') &&
          !id.contains('-plus')) {
        return _dashscopeQwenImageEdit;
      }
      return _dashscopeQwenImage;
    }

    return forFamily(family);
  }

  /// The table a protocol implies for a model this layer cannot identify by
  /// its id — the fallback behind a protocol selection on a relay whose model
  /// names are free text.
  ///
  /// A relay's `nano-banana-pro` pinned to the Images API has, for every
  /// purpose the workbench cares about, the Images API's parameters: without
  /// this it resolved to the empty table its id classifies into, and the
  /// parameter panel came up blank for a model that has one. Only reached
  /// when the id is *not* one of the protocol's own models (see
  /// `ModelDescriptor.of`); a recognized id keeps its precise table from
  /// [forModel].
  ///
  /// Where a protocol serves several tables, the stricter one stands in:
  /// DashScope's defaults to qwen's (the smaller reference-image ceiling, the
  /// narrower size vocabulary), so a guess errs toward a request upstream
  /// accepts.
  static ModelCapabilities forProtocol(WireProtocol protocol) {
    switch (protocol) {
      case WireProtocol.openaiImages:
        return _openaiImage;
      case WireProtocol.xaiImages:
        return _xaiImage;
      case WireProtocol.geminiImagen:
        return _imagen;
      case WireProtocol.dashscopeImagesSync:
      case WireProtocol.dashscopeImagesAsync:
        return _dashscopeQwenImage;
      case WireProtocol.minimaxImages:
        return _minimaxImage;
      case WireProtocol.chatImage:
        // No parameters to offer, but an image generator all the same: both
        // chat wires key image *output* off this flag — Gemini declares
        // `responseModalities: IMAGE` by it, and the OpenAI-shaped wire only
        // takes a bare-link reply as an image when it is set.
        return const ModelCapabilities(isImageGenerator: true);
      case WireProtocol.openaiVideos:
        return _openaiVideo;
      case WireProtocol.xaiVideos:
        return _grokImagineVideo;
      case WireProtocol.geminiVeo:
        return const ModelCapabilities(isVideoGenerator: true);
      case WireProtocol.dashscopeVideo:
        return _dashscopeWanVideo;
      case WireProtocol.minimaxVideo:
        return _minimaxVideo;
      case WireProtocol.minimaxH3BaseVideo:
        return _minimaxH3Base;
      case WireProtocol.midjourney:
        return _midjourney;
      case WireProtocol.openaiChat:
      case WireProtocol.openaiResponses:
      case WireProtocol.anthropicChat:
      case WireProtocol.geminiChat:
      case WireProtocol.dashscopeChat:
        return const ModelCapabilities();
    }
  }

  static ModelCapabilities forFamily(ModelFamily family) {
    switch (family) {
      case ModelFamily.geminiImage:
        return _geminiImage;
      case ModelFamily.geminiImagen:
        return _imagen;
      case ModelFamily.openaiImage:
        return _openaiImage;
      case ModelFamily.xaiImage:
        return _xaiImage;
      case ModelFamily.minimaxImage:
        return _minimaxImage;
      case ModelFamily.dashscopeImage:
        // Reached only for an id that classified into the family but missed
        // both tables in [forModel]; qwen's is the safer default (the smaller
        // reference-image ceiling, the stricter size vocabulary).
        return _dashscopeQwenImage;
      case ModelFamily.midjourney:
        return _midjourney;
      case ModelFamily.openaiVideo:
        return _openaiVideo;
      case ModelFamily.geminiVideo:
        // Veo's panel uses fixed VeoResolution/VeoAspectRatio enums; no extra
        // capability-driven controls are needed (yet).
        return const ModelCapabilities(isVideoGenerator: true);
      case ModelFamily.geminiChat:
      case ModelFamily.openaiChat:
      case ModelFamily.other:
        return const ModelCapabilities();
    }
  }
}
