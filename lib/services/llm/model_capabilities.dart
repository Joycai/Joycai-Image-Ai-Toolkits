import 'image_size_rules.dart';
import 'image_size_vocabulary.dart';
import 'model_family.dart';
import 'param_spec.dart';
import 'vendors/vendor_profile.dart' show WireProtocol;

export 'param_spec.dart';

part 'model_capability_tables.dart';

/// Which request body an image model's endpoint expects, when the family
/// default (one shape per protocol) is not enough.
///
/// DashScope is the reason this exists: its two generations of image models
/// are served by the same host under the same auth and the same
/// `input.messages` envelope, but disagree about the order of the content
/// parts (and, in layer 3, about sizes and defaults) — `qwen-image*` leads
/// with the images, `wan2.7-*` with the text. A top-level `messages` for wan
/// was a docs-mirror error; the endpoint 400s on it (verified 2026-09-19).
/// Declaring the shape here keeps the protocol free
/// of the model-id branch that would otherwise decide it (layer-1 code may
/// not sniff ids; this file may).
enum ImageRequestShape {
  /// Not a DashScope-native model — the protocol's own default shape.
  none,

  /// `{model, input: {messages: [...]}, parameters: {...}}`, images first.
  dashscopeQwen,

  /// The same envelope, text first.
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

  /// The exact pixels each (resolution tier, aspect ratio) pair maps to, for
  /// a model whose `size` takes *either* a tier (`2K`) *or* pixels
  /// (`2848x1600`) but not both — Seedream's. Keyed tier → ratio → `WxH`.
  ///
  /// The workbench offers a tier and an aspect ratio as two controls; the
  /// protocol sends the tier alone when no ratio is chosen (the model then
  /// reads the ratio off the prompt) and looks the pair up here otherwise.
  /// The values are each model's own documented mapping, so the pixels sent
  /// are the ones the model would have picked for that ratio anyway. Empty
  /// for every family that sizes some other way.
  final Map<String, Map<String, String>> tierPixelSizes;

  /// True when the model's image surface can stream — push each image the
  /// moment it is drawn rather than answer once the whole group exists.
  /// Seedream 5.0 lite / 4.5 / 4.0 (`stream: true`, docs/api/volcengine-ark.md
  /// §5); 5.0 pro rejects the field with a 400. Whether a request actually
  /// streams is the dispatcher's call — the route has to serve it too.
  final bool streamsImages;

  const ModelCapabilities({
    this.isImageGenerator = false,
    this.isVideoGenerator = false,
    this.imageParams = const [],
    this.videoParams = const [],
    this.maxReferenceImages,
    this.longRunning = false,
    this.imageRequestShape = ImageRequestShape.none,
    this.supportsAsyncImageTask = false,
    this.tierPixelSizes = const {},
    this.streamsImages = false,
  });

  /// The tables [forModel] reaches by id alone — a version or variant whose
  /// family default ([forFamily]) differs from it. Together with [forFamily]
  /// over every family and [forProtocol] over every protocol this is every
  /// table there is, which is what the spec-billing picker needs: its
  /// condition values are the union of every table's vocabulary, and a tier
  /// only one version offers (Seedream 5.0 pro's `1.5K`, lite's `3K`) would
  /// otherwise be missing from it.
  static const List<ModelCapabilities> idRoutedTables = [
    _openaiImage2,
    _openaiImage25,
    _geminiImageV2,
    _geminiImagePro,
    _geminiImageLegacy,
    _grokImagineVideo,
    _dashscopeWanVideo,
    _minimaxVideo,
    _minimaxH3Base,
    _dashscopeWanImage,
    _dashscopeWanImagePro,
    _dashscopeQwenImageFixed,
    _dashscopeQwenImageEditMaxPlus,
    _dashscopeQwenImageEdit,
    _dashscopeQwenImage,
    _seedream50Pro,
    _seedream50Lite,
    _seedream45,
    _seedream40,
    _seedream30,
  ];

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
    // reference-image ceiling and size vocabulary, so they are separate
    // tables: wan and wan-pro (pro's area ceiling is 4096², not 2048²); the
    // first-generation qwen text-to-image models, which take five fixed
    // sizes; the basic `qwen-image-edit`, which alone in its family takes no
    // `size` at all (docs/api/qianwen-bailian.md §4.1: "不支持 size", 400 on
    // receiving one); `qwen-image-edit-max` / `-plus` and their dated builds,
    // whose range is per edge (512–2048); and everything else —
    // `qwen-image-2.0*` / `-3.0*` — on the area-bounded free-size table.
    if (family == ModelFamily.dashscopeImage) {
      if (id.startsWith('wan')) {
        return id.contains('-pro') ? _dashscopeWanImagePro : _dashscopeWanImage;
      }
      // First-generation text-to-image: five fixed sizes, no free `WxH`.
      if (id == 'qwen-image' ||
          id.startsWith('qwen-image-plus') ||
          id.startsWith('qwen-image-max')) {
        return _dashscopeQwenImageFixed;
      }
      if (id.startsWith('qwen-image-edit')) {
        return id.contains('-max') || id.contains('-plus')
            ? _dashscopeQwenImageEditMaxPlus
            : _dashscopeQwenImageEdit;
      }
      return _dashscopeQwenImage;
    }

    // Seedream's generations differ in almost every parameter — tiers,
    // group generation, output format, prompt-optimization modes, web search,
    // 5.0 pro's task modes — so the version picks the table. The version is
    // read by the classifier (`5-0` and `5.0` spell the same generation);
    // anything it cannot place keeps the family's generic table.
    if (family == ModelFamily.seedreamImage) {
      return _seedreamTableFor(modelId);
    }

    return forFamily(family);
  }

  static ModelCapabilities _seedreamTableFor(String modelId) {
    final version = ModelFamilyClassifier.seedreamVersion(modelId);
    switch (version) {
      case (5, 0):
        return ModelFamilyClassifier.isSeedreamPro(modelId)
            ? _seedream50Pro
            : _seedream50Lite;
      case (4, 5):
        return _seedream45;
      case (4, 0):
        return _seedream40;
      case (3, _):
        return _seedream30;
      default:
        return _seedreamGeneric;
    }
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
  /// DashScope's is a table of its own whose size box is the intersection of
  /// the free-size families (`kDashscopeCommonSizeRules`) and whose reference
  /// ceiling is qwen's, the smaller — so a guess errs toward a request
  /// upstream accepts.
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
        return _dashscopeImageFallback;
      case WireProtocol.minimaxImages:
        return _minimaxImage;
      case WireProtocol.arkImages:
        return _seedreamGeneric;
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
      case ModelFamily.seedreamImage:
        return _seedreamGeneric;
      case ModelFamily.dashscopeImage:
        // Reached only for an id that classified into the family but missed
        // every table in [forModel]: the fallback's size box is the
        // intersection of the free-size families, and its reference ceiling
        // is qwen's, the smaller.
        return _dashscopeImageFallback;
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
