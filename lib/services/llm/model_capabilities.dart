import 'model_family.dart';

/// How a parameter should be rendered in the workbench config UI.
///
/// `customSize` is a specialised control for image-size parameters whose set
/// of legal values isn't enumerable — the spec lists popular presets, but the
/// dialog also lets the user type any WxH that satisfies the param's
/// [ParamSpec.customValidator]. Used by gpt-image-2, where OpenAI accepts any
/// pixel dimensions meeting four numeric constraints.
///
/// `slider` is a continuous-range integer control bounded by [ParamSpec.min]
/// / [ParamSpec.max] rather than a discrete [ParamSpec.options] list. Used by
/// grok-imagine-video's duration parameter (1–15s).
enum ParamControl { dropdown, segmented, customSize, slider }

/// A single selectable option for a parameter.
///
/// [value] is what gets sent to the provider; the human-readable label is
/// resolved in the UI layer (so localization stays out of this pure-data file).
class ParamOption {
  final String value;
  const ParamOption(this.value);
}

/// Declarative spec for one configurable generation parameter.
///
/// [key] is the option key handed to the provider (e.g. `aspectRatio`,
/// `imageSize`, `quality`) and must match what the providers read from the
/// task `options` map. [labelKey] is a stable token the UI maps to a localized
/// label.
class ParamSpec {
  final String key;
  final String labelKey;
  final ParamControl control;
  final List<ParamOption> options;
  final String defaultValue;

  /// Optional predicate that accepts user-typed values outside the discrete
  /// [options] list (e.g. arbitrary WxH for gpt-image-2). When set,
  /// [isValid] returns true if the value is either a known option *or* the
  /// validator accepts it.
  ///
  /// Must be a pure / `const`-compatible top-level function so this class
  /// stays `const`-constructible.
  final bool Function(String value)? customValidator;

  /// Inclusive bounds for [ParamControl.slider]. Unused by every other
  /// control.
  final int? min;
  final int? max;

  const ParamSpec({
    required this.key,
    required this.labelKey,
    required this.control,
    required this.options,
    required this.defaultValue,
    this.customValidator,
    this.min,
    this.max,
  });

  bool isValid(String? value) {
    if (value == null) return false;
    if (options.any((o) => o.value == value)) return true;
    // A slider has no discrete [options] — its valid set is the range it
    // already declares. Without this branch every slider value failed both
    // checks below, so [normalize] handed back [defaultValue] forever: the
    // control snapped back on the next rebuild and the request carried the
    // default no matter what the user chose. The one slider that worked did
    // so only because it carried a hand-written validator restating its own
    // min/max.
    //
    // The bounds fall back to the same 1/15 the panel clamps with, so a value
    // this accepts is always one the control can actually render — the two
    // must not be able to disagree about what is in range.
    if (control == ParamControl.slider) {
      final n = int.tryParse(value);
      if (n == null) return false;
      return n >= (min ?? 1) && n <= (max ?? 15);
    }
    final validator = customValidator;
    return validator != null && validator(value);
  }

  /// Returns [value] when it is a valid option for this spec, otherwise the
  /// default. Guarantees the UI never tries to render an out-of-range value
  /// and the provider never receives one (important when switching families).
  String normalize(String? value) => isValid(value) ? value! : defaultValue;
}

// ---------------------------------------------------------------------------
// gpt-image-2 size constraints
// ---------------------------------------------------------------------------

/// Validates a `WxH` size string against OpenAI's gpt-image-2 rules. Used by
/// both the capability spec's [ParamSpec.customValidator] and the picker
/// dialog's per-edge breakdown.
///
/// Rules (per OpenAI's published gpt-image-2 spec):
///   * Both edges must be multiples of 16.
///   * Max edge ≤ 3840 px.
///   * Long-edge / short-edge ratio ≤ 3:1.
///   * Total pixels in [655_360, 8_294_400] — equivalent to ~0.66 MP–~8.29 MP.
bool isValidOpenAIImage2Size(String value) {
  // Accept the `auto` sentinel separately (used by `_openaiImage2.defaultValue`).
  if (value == 'auto') return true;
  final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
  if (match == null) return false;
  final w = int.tryParse(match.group(1)!);
  final h = int.tryParse(match.group(2)!);
  if (w == null || h == null || w <= 0 || h <= 0) return false;
  return checkOpenAIImage2SizeRules(w, h).every((r) => r.passes);
}

// ---------------------------------------------------------------------------
// Aspect-ratio → size calculator
// ---------------------------------------------------------------------------

/// The edge grid every gpt-image-2 size sits on.
const int kImage2EdgeStep = 16;

/// The largest edge gpt-image-2 accepts.
const int kImage2MaxEdge = 3840;

/// A parsed aspect ratio, kept as *ratio plus orientation* rather than a bare
/// number: `16:9` and `9:16` are the same shape turned on its side, and which
/// one the user typed is the only thing that says whether the long edge is the
/// width or the height. Nothing else in the dialog asks them.
class AspectRatioSpec {
  /// Long edge divided by short edge — always ≥ 1.
  final double longOverShort;

  /// True when the *height* is the long edge (`9:16`, or a decimal below 1).
  final bool portrait;

  const AspectRatioSpec(this.longOverShort, this.portrait);
}

/// Parses `16:9`, `16x9`, `16/9` or a bare decimal (`1.78`, `0.5625`).
///
/// Returns null for anything that isn't two positive numbers or one positive
/// decimal — the caller disables its button on null rather than guessing.
AspectRatioSpec? parseAspectRatio(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final pair = RegExp(r'^(\d+(?:\.\d+)?)\s*[:x×/]\s*(\d+(?:\.\d+)?)$', caseSensitive: false)
      .firstMatch(text);
  if (pair != null) {
    final a = double.parse(pair.group(1)!);
    final b = double.parse(pair.group(2)!);
    if (a <= 0 || b <= 0) return null;
    return AspectRatioSpec(a >= b ? a / b : b / a, b > a);
  }

  final single = double.tryParse(text);
  if (single == null || single <= 0) return null;
  return AspectRatioSpec(single >= 1 ? single : 1 / single, single < 1);
}

/// Writes [w]×[h] back as the shortest exact ratio it can — `3840×2160` reads
/// as `16:9`, not `1.778`. Falls back to a decimal when the reduced terms are
/// too big to be worth reading (`1000×1234` → `0.81`).
String formatAspectRatio(int w, int h) {
  if (w <= 0 || h <= 0) return '';
  int a = w, b = h;
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  final rw = w ~/ a;
  final rh = h ~/ a;
  if (rw <= 64 && rh <= 64) return '$rw:$rh';
  return (w / h).toStringAsFixed(2);
}

/// Turns "this ratio, this long edge" into a legal WxH.
///
/// The long edge is what the user typed, so it leads: it snaps to the nearest
/// multiple of 16 and the short edge is then the multiple of 16 that lands
/// closest to [spec]. Where that pair breaks one of the other three rules —
/// 1:1 at 3840 is 14.7 MP, well over the cap — the long edge steps outward
/// along the grid (nearest first) until a legal pair appears.
///
/// Always returns a size. When the ratio itself is out of bounds (past 3:1,
/// where no pair of edges can ever be legal) it returns the straight
/// computation, so the dialog's rule list can say which rule the request fell
/// foul of rather than the button appearing to do nothing.
(int, int) sizeForAspectRatio(AspectRatioSpec spec, int longEdge) {
  (int, int) orient(int long, int short) => spec.portrait ? (short, long) : (long, short);

  final requested = _snapEdge(longEdge);

  // Nearest legal long edge wins, so the whole grid is fair game: a 1:1 at
  // 3840 is 14.7 MP and has to come down to 2880 before it fits under the
  // cap, while a 16:9 at 200 has to come *up* to clear the 0.66 MP floor.
  // Both corrections are shown back to the user in the long-edge field.
  for (int delta = 0; delta <= kImage2MaxEdge; delta += kImage2EdgeStep) {
    for (final long in delta == 0 ? [requested] : [requested - delta, requested + delta]) {
      if (long < kImage2EdgeStep || long > kImage2MaxEdge) continue;
      for (final short in _shortEdgeCandidates(long, spec.longOverShort)) {
        final (w, h) = orient(long, short);
        if (checkOpenAIImage2SizeRules(w, h).every((r) => r.passes)) return (w, h);
      }
    }
  }

  final fallbackShort = _shortEdgeCandidates(requested, spec.longOverShort).firstOrNull ??
      kImage2EdgeStep;
  return orient(requested, fallbackShort);
}

/// The multiples of 16 bracketing `long / ratio`, nearest ratio first.
List<int> _shortEdgeCandidates(int long, double longOverShort) {
  final exact = long / longOverShort;
  final lower = (exact / kImage2EdgeStep).floor() * kImage2EdgeStep;
  final candidates = <int>[lower, lower + kImage2EdgeStep]
      .where((s) => s >= kImage2EdgeStep && s <= long)
      .toList();
  double error(int s) => ((long / s) - longOverShort).abs();
  candidates.sort((a, b) => error(a).compareTo(error(b)));
  return candidates;
}

/// Nearest multiple of 16, clamped to the legal edge range.
int _snapEdge(int raw) {
  final clamped = raw.clamp(kImage2EdgeStep, kImage2MaxEdge);
  final snapped =
      ((clamped + kImage2EdgeStep ~/ 2) ~/ kImage2EdgeStep) * kImage2EdgeStep;
  return snapped.clamp(kImage2EdgeStep, kImage2MaxEdge);
}

/// Per-rule breakdown for live feedback in the picker dialog. Each entry maps
/// to a localized message key consumed by the UI layer.
class SizeRuleResult {
  final String labelKey;
  final bool passes;
  const SizeRuleResult(this.labelKey, this.passes);
}

List<SizeRuleResult> checkOpenAIImage2SizeRules(int w, int h) {
  final long = w > h ? w : h;
  final short = w > h ? h : w;
  final pixels = w * h;
  return [
    SizeRuleResult('sizeRuleMultiple16', w % 16 == 0 && h % 16 == 0),
    SizeRuleResult('sizeRuleMaxEdge', long <= 3840),
    SizeRuleResult('sizeRuleAspect', short > 0 && (long / short) <= 3.0),
    SizeRuleResult(
        'sizeRulePixels', pixels >= 655360 && pixels <= 8294400),
  ];
}

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
    if (family == ModelFamily.openaiImage && id.contains('gpt-image-2')) {
      return _openaiImage2;
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

  // --- Family parameter tables ---------------------------------------------

  /// 1K / 2K / 4K resolution control shared by the nanoBanana image families
  /// that have one.
  ///
  /// `not_set` is the default and means the field is not sent — the upstream
  /// default is the 1K tier, so nothing is lost, and "not sent" is the one
  /// spelling every host accepts. The value must be uppercase `K` on the
  /// wire; the options carry it that way so nothing has to translate.
  static const _geminiSizeParam = ParamSpec(
    key: 'imageSize',
    labelKey: 'resolution',
    control: ParamControl.segmented,
    defaultValue: 'not_set',
    options: [
      ParamOption('not_set'),
      ParamOption('1K'),
      ParamOption('2K'),
      ParamOption('4K'),
    ],
  );

  /// The ten-ratio aspect control every nanoBanana generation shares.
  static const _geminiAspectParam = ParamSpec(
    key: 'aspectRatio',
    labelKey: 'aspectRatio',
    control: ParamControl.dropdown,
    defaultValue: 'not_set',
    options: [
      ParamOption('not_set'),
      ParamOption('1:1'),
      ParamOption('2:3'),
      ParamOption('3:2'),
      ParamOption('3:4'),
      ParamOption('4:3'),
      ParamOption('4:5'),
      ParamOption('5:4'),
      ParamOption('9:16'),
      ParamOption('16:9'),
    ],
  );

  /// nanoBanana — `gemini-*-image`. Full Gemini aspect-ratio set + 1K/2K/4K.
  /// Accepts multiple reference images (no hard limit enforced here).
  static const _geminiImage = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: null,
    imageParams: [_geminiAspectParam, _geminiSizeParam],
  );

  /// The first nanoBanana, `gemini-2.5-flash-image`: the same ratios, but
  /// **no resolution control** — the model has a single 1024px tier and no
  /// `imageSize` field. Its own table so the control is never rendered and
  /// the field never sent; the shared table used to send `imageSize: 1K` to
  /// it on every request by default.
  static const _geminiImageLegacy = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: null,
    imageParams: [_geminiAspectParam],
  );

  /// Nano Banana Pro — `gemini-3.1-pro-image`. The standard nanoBanana set plus
  /// the 21:9 ultrawide ratio.
  static const _geminiImagePro = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: null,
    imageParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('1:1'),
          ParamOption('2:3'),
          ParamOption('3:2'),
          ParamOption('3:4'),
          ParamOption('4:3'),
          ParamOption('4:5'),
          ParamOption('5:4'),
          ParamOption('9:16'),
          ParamOption('16:9'),
          ParamOption('21:9'),
        ],
      ),
      _geminiSizeParam,
    ],
  );

  /// Nano Banana 2 — `gemini-3.1-flash-image`. The Pro set plus the extreme
  /// panoramic / strip ratios (1:4, 4:1, 1:8, 8:1).
  static const _geminiImageV2 = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: null,
    imageParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('1:1'),
          ParamOption('2:3'),
          ParamOption('3:2'),
          ParamOption('3:4'),
          ParamOption('4:3'),
          ParamOption('4:5'),
          ParamOption('5:4'),
          ParamOption('9:16'),
          ParamOption('16:9'),
          ParamOption('21:9'),
          ParamOption('1:4'),
          ParamOption('4:1'),
          ParamOption('1:8'),
          ParamOption('8:1'),
        ],
      ),
      _geminiSizeParam,
    ],
  );

  /// Imagen — `:predict`. Text-to-image only; reference images are not
  /// supported. Restricted aspect-ratio set, no 4K.
  static const _imagen = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 0,
    imageParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: '1:1',
        options: [
          ParamOption('1:1'),
          ParamOption('3:4'),
          ParamOption('4:3'),
          ParamOption('9:16'),
          ParamOption('16:9'),
        ],
      ),
      ParamSpec(
        key: 'imageSize',
        labelKey: 'resolution',
        control: ParamControl.segmented,
        defaultValue: '1K',
        options: [ParamOption('1K'), ParamOption('2K')],
      ),
    ],
  );

  /// Quality control shared by every native OpenAI image model.
  static const _openaiQualityParam = ParamSpec(
    key: 'quality',
    labelKey: 'quality',
    control: ParamControl.segmented,
    defaultValue: 'auto',
    options: [
      ParamOption('auto'),
      ParamOption('low'),
      ParamOption('medium'),
      ParamOption('high'),
    ],
  );

  /// Native OpenAI image (`gpt-image-1`). Pixel sizes + quality, no separate
  /// aspect-ratio control (size encodes the ratio). Accepts up to 16 reference
  /// images via the images/edits endpoint.
  static const _openaiImage = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 16,
    imageParams: [
      ParamSpec(
        key: 'imageSize',
        labelKey: 'resolution',
        control: ParamControl.dropdown,
        defaultValue: 'auto',
        options: [
          ParamOption('auto'),
          ParamOption('1024x1024'),
          ParamOption('1536x1024'),
          ParamOption('1024x1536'),
        ],
      ),
      _openaiQualityParam,
    ],
  );

  /// Sora 2 / grok-imagine / Wanxiang / Kling / Vidu / Jimeng served via
  /// NewAPI's OpenAI-compatible `/v1/videos` surface. Submit → poll → mp4 URL.
  ///
  /// Accepts up to one `input_reference` image (mapped from `firstFramePath`)
  /// and up to 7 reference images (mapped to `images[]`). The shared
  /// aspectRatio + resolution dropdowns in the video panel still drive the
  /// upstream `size` field; the parameters below are the openaiVideo-only
  /// extensions that wouldn't make sense for Veo.
  static const _openaiVideo = ModelCapabilities(
    isVideoGenerator: true,
    maxReferenceImages: 7,
    videoParams: [
      ParamSpec(
        key: 'seconds',
        labelKey: 'videoSeconds',
        control: ParamControl.segmented,
        defaultValue: '5',
        options: [
          ParamOption('4'),
          ParamOption('5'),
          ParamOption('8'),
          ParamOption('10'),
          ParamOption('12'),
        ],
      ),
      ParamSpec(
        key: 'videoQuality',
        labelKey: 'quality',
        control: ParamControl.segmented,
        defaultValue: 'standard',
        options: [
          ParamOption('standard'),
          ParamOption('high'),
        ],
      ),
    ],
  );

  /// grok-imagine-video-1.5 — xAI's native async video surface
  /// (`/videos/generations`, see `_submitXaiVideo`) on xAI channels, or the
  /// NewAPI `/v1/videos` relay otherwise. Overrides the shared Veo
  /// resolution/aspect-ratio dropdowns (the video panel hides those and
  /// renders these instead) since xAI's option set is different:
  ///  * `aspectRatio` — 1:1, 16:9/9:16, 4:3/3:4, 3:2/2:3, or unset (skips the
  ///    `aspect_ratio` field entirely and lets the model choose).
  ///  * `resolution` — 480p / 720p / 1080p.
  ///  * `seconds` — a 1–15s duration slider (xAI's `duration` field).
  static const _grokImagineVideo = ModelCapabilities(
    isVideoGenerator: true,
    maxReferenceImages: 7,
    videoParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('1:1'),
          ParamOption('16:9'),
          ParamOption('9:16'),
          ParamOption('4:3'),
          ParamOption('3:4'),
          ParamOption('3:2'),
          ParamOption('2:3'),
        ],
      ),
      ParamSpec(
        key: 'resolution',
        labelKey: 'resolution',
        control: ParamControl.segmented,
        defaultValue: '720p',
        options: [
          ParamOption('480p'),
          ParamOption('720p'),
          ParamOption('1080p'),
        ],
      ),
      ParamSpec(
        key: 'seconds',
        labelKey: 'videoSeconds',
        control: ParamControl.slider,
        defaultValue: '6',
        options: [],
        min: 1,
        max: 15,
      ),
    ],
  );

  /// `wan3.0-video(-prime)` — DashScope's native async video-synthesis
  /// surface (docs/api/qianwen-bailian.md §6). Overrides the shared Veo
  /// resolution/aspect dropdowns with DashScope's own vocabulary:
  ///  * `resolution` — 480P / 720P / 1080P (upstream default 1080P; the
  ///    protocol uppercases whatever the shared spelling delivers).
  ///  * `aspectRatio` — `adaptive` (default) or a fixed ratio.
  ///  * `seconds` — 2–30 s (`-1` smart mode is not exposed; upstream
  ///    default 5).
  ///  * `videoAudio` — whether the model also generates audio. Upstream
  ///    defaults to **on** and bills for it, which is why it is a visible
  ///    control instead of an inherited server-side default; the protocol
  ///    always sends the field explicitly.
  static const _dashscopeWanVideo = ModelCapabilities(
    isVideoGenerator: true,
    maxReferenceImages: 9,
    videoParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'adaptive',
        options: [
          ParamOption('adaptive'),
          ParamOption('16:9'),
          ParamOption('4:3'),
          ParamOption('1:1'),
          ParamOption('3:4'),
          ParamOption('9:16'),
        ],
      ),
      ParamSpec(
        key: 'resolution',
        labelKey: 'resolution',
        control: ParamControl.segmented,
        defaultValue: '1080p',
        options: [
          ParamOption('480p'),
          ParamOption('720p'),
          ParamOption('1080p'),
        ],
      ),
      ParamSpec(
        key: 'seconds',
        labelKey: 'videoSeconds',
        control: ParamControl.slider,
        defaultValue: '5',
        options: [],
        min: 2,
        max: 30,
      ),
      ParamSpec(
        key: 'videoAudio',
        labelKey: 'videoAudio',
        control: ParamControl.segmented,
        defaultValue: 'on',
        options: [ParamOption('on'), ParamOption('off')],
      ),
      _dashscopePromptExtend,
    ],
  );

  /// xAI Grok Imagine image (`grok-imagine-image*`). JSON
  /// `/images/generations` + `/images/edits`; accepts one source `image` or
  /// up to 3 `images[]` references (reference them as `<IMAGE_0>`… in the
  /// prompt). `auto` lets the model pick the best ratio; for single-image
  /// edits the output follows the input's ratio.
  static const _xaiImage = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 3,
    imageParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('auto'),
          ParamOption('1:1'),
          ParamOption('2:3'),
          ParamOption('3:2'),
          ParamOption('3:4'),
          ParamOption('4:3'),
          ParamOption('9:16'),
          ParamOption('16:9'),
          ParamOption('1:2'),
          ParamOption('2:1'),
          ParamOption('9:19.5'),
          ParamOption('19.5:9'),
          ParamOption('9:20'),
          ParamOption('20:9'),
        ],
      ),
      ParamSpec(
        key: 'imageSize',
        labelKey: 'resolution',
        control: ParamControl.segmented,
        defaultValue: '1k',
        options: [ParamOption('1k'), ParamOption('2k')],
      ),
    ],
  );

  /// Shared "let DashScope rewrite my prompt" control.
  ///
  /// Upstream defaults this to **on**: the endpoint rewrites the prompt
  /// before generating. For an app whose users hand-tune prompts that is a
  /// surprise worth surfacing, but flipping the default would be a surprise
  /// of its own — so `not_set` sends nothing and keeps upstream behavior,
  /// and the explicit values are how the author opts in or out.
  static const _dashscopePromptExtend = ParamSpec(
    key: 'promptExtend',
    labelKey: 'promptExtend',
    control: ParamControl.segmented,
    defaultValue: 'not_set',
    options: [ParamOption('not_set'), ParamOption('on'), ParamOption('off')],
  );

  /// `qwen-image*` on DashScope's native surface — the `input.messages`
  /// shape. Up to 3 reference images (10 MB each); sizes are `WxH` with the
  /// total area in 512²–2048², normalized to DashScope's `W*H` spelling on
  /// the wire.
  ///
  /// `not_set` here does **not** mean "send nothing": this endpoint renders an
  /// unsized request at 2048² and bills it at the 2K tier — twice the 1K
  /// price — so the dialect always sends a size, and `not_set` means "the
  /// dialect's default": a 1K square for text-to-image, the input's own
  /// proportions fitted into the 1K area for an edit (`dashscopeQwenDefaultSize`).
  /// The three presets are the 1K-area sizes an author picks explicitly.
  ///
  /// `n` is deliberately not exposed — every request sends 1. The ceiling
  /// differs *within* the family (6, but `qwen-image-edit` takes only 1) and
  /// sending the wrong one is a 400, so the control waits until there is a
  /// reason to produce more than one image per task.
  static const _dashscopeQwenImage = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 3,
    longRunning: true,
    imageRequestShape: ImageRequestShape.dashscopeQwen,
    imageParams: [
      ParamSpec(
        key: 'imageSize',
        labelKey: 'resolution',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('1024x1024'),
          ParamOption('1024x1536'),
          ParamOption('1536x1024'),
        ],
      ),
      _dashscopePromptExtend,
    ],
  );

  /// The basic `qwen-image-edit` (not `-max` / `-plus`): same shape and
  /// reference ceiling as [_dashscopeQwenImage], but **no size control** —
  /// the endpoint has no `size` for this one model and 400s on receiving it,
  /// and `n` is a hard 1 (docs/api/qianwen-bailian.md §4.1). The absence of
  /// the `imageSize` spec is what the protocol reads to leave `size` off
  /// (`dashscopeModelTakesSize`), so this table is the *only* place that fact
  /// lives.
  static const _dashscopeQwenImageEdit = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 3,
    longRunning: true,
    imageRequestShape: ImageRequestShape.dashscopeQwen,
    imageParams: [_dashscopePromptExtend],
  );

  /// `wan2.7-image*` on DashScope's native surface — the top-level
  /// `messages` shape. Up to 9 reference images (20 MB each) and a `1K`/`2K`
  /// size vocabulary on top of `W*H`.
  ///
  /// `not_set` sends `1K`, not nothing: wan's own omitted default is the 2K
  /// tier at twice the price, the same trap as qwen's. `n` is always sent as
  /// 1 — wan2.7's upstream default is **four** images, each billed.
  static const _dashscopeWanImage = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 9,
    longRunning: true,
    supportsAsyncImageTask: true,
    imageRequestShape: ImageRequestShape.dashscopeWan,
    imageParams: [
      ParamSpec(
        key: 'imageSize',
        labelKey: 'resolution',
        control: ParamControl.segmented,
        defaultValue: 'not_set',
        options: [ParamOption('not_set'), ParamOption('1K'), ParamOption('2K')],
      ),
      _dashscopePromptExtend,
    ],
  );

  /// Midjourney via midjourney-proxy / NewAPI. MJ-specific parameters are
  /// expressed as `--flag value` tokens appended to the prompt before submit
  /// (the provider does the rewriting). The dropdown values mirror what the
  /// upstream MJ bot accepts; `not_set` / `auto` skip the flag entirely so the
  /// MJ default is used.
  ///
  /// Reference images are supported via the `blend` / `--iw` path (the proxy
  /// auto-routes to `/mj/submit/blend` when multiple base64 images are
  /// supplied); 5 is MJ's hard ceiling for blend.
  static const _midjourney = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 5,
    imageParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('1:1'),
          ParamOption('2:3'),
          ParamOption('3:2'),
          ParamOption('3:4'),
          ParamOption('4:3'),
          ParamOption('9:16'),
          ParamOption('16:9'),
          ParamOption('21:9'),
        ],
      ),
      ParamSpec(
        key: 'mjVersion',
        labelKey: 'mjVersion',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('7'),
          ParamOption('6.1'),
          ParamOption('6'),
          ParamOption('5.2'),
          ParamOption('niji 6'),
        ],
      ),
      ParamSpec(
        key: 'mjMode',
        labelKey: 'mjMode',
        control: ParamControl.segmented,
        defaultValue: 'FAST',
        options: [
          ParamOption('RELAX'),
          ParamOption('FAST'),
          ParamOption('TURBO'),
        ],
      ),
      ParamSpec(
        key: 'mjQuality',
        labelKey: 'quality',
        control: ParamControl.segmented,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('0.25'),
          ParamOption('0.5'),
          ParamOption('1'),
          ParamOption('2'),
        ],
      ),
      ParamSpec(
        key: 'mjStylize',
        labelKey: 'mjStylize',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('0'),
          ParamOption('50'),
          ParamOption('100'),
          ParamOption('250'),
          ParamOption('500'),
          ParamOption('750'),
          ParamOption('1000'),
        ],
      ),
      ParamSpec(
        key: 'mjChaos',
        labelKey: 'mjChaos',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('0'),
          ParamOption('25'),
          ParamOption('50'),
          ParamOption('100'),
        ],
      ),
    ],
  );

  /// Native OpenAI image v2 (`gpt-image-2`). The size param renders as a
  /// custom picker (preset chips + free WxH input). OpenAI accepts any
  /// dimensions meeting four rules — see [isValidOpenAIImage2Size] — so the
  /// preset list below is only quick-pick scaffolding; the dialog enforces
  /// the actual constraints.
  static const _openaiImage2 = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 16,
    imageParams: [
      ParamSpec(
        key: 'imageSize',
        labelKey: 'resolution',
        control: ParamControl.customSize,
        defaultValue: 'auto',
        options: [
          ParamOption('auto'),
          ParamOption('1024x1024'),
          ParamOption('1536x1024'),
          ParamOption('1024x1536'),
          ParamOption('2048x2048'),
          ParamOption('2048x1152'),
          ParamOption('3840x2160'),
          ParamOption('2160x3840'),
        ],
        customValidator: isValidOpenAIImage2Size,
      ),
      _openaiQualityParam,
    ],
  );

  /// `image-01` / `image-01-live` — MiniMax's native `/v1/image_generation`
  /// (docs/api/minimax.md §4). What the app exposes and why:
  ///
  ///  * `aspectRatio` — the eight documented ratios. `width`/`height` are the
  ///    alternative spelling upstream (512–2048, multiples of 8, `image-01`
  ///    only); one control is enough and the ratio is the one both variants
  ///    accept.
  ///  * `promptExtend` — MiniMax's `prompt_optimizer`. Shared option key with
  ///    DashScope's `prompt_extend`: two wire spellings, one idea, one label.
  ///
  /// `maxReferenceImages: 1` because the reference is a **subject**, not a
  /// canvas: `subject_reference` takes `type: character` and nothing else, so
  /// a second portrait has no documented meaning. This is also why the model
  /// is not an image *editor* despite accepting an input image — the protocol
  /// warns about the mismatch on every reference request.
  ///
  /// `longRunning` for the same reason DashScope's sync surface has it: one
  /// request runs the whole generation upstream, and the generation is billed
  /// before a chat-sized guard would give up on it.
  static const _minimaxImage = ModelCapabilities(
    isImageGenerator: true,
    maxReferenceImages: 1,
    longRunning: true,
    imageParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'not_set',
        options: [
          ParamOption('not_set'),
          ParamOption('1:1'),
          ParamOption('16:9'),
          ParamOption('4:3'),
          ParamOption('3:2'),
          ParamOption('2:3'),
          ParamOption('3:4'),
          ParamOption('9:16'),
          ParamOption('21:9'),
        ],
      ),
      _minimaxPromptOptimizer,
    ],
  );

  /// MiniMax's `prompt_optimizer`. Same three-state shape as DashScope's
  /// prompt extension so `not_set` can leave the field off entirely rather
  /// than picking a default the vendor may change.
  static const _minimaxPromptOptimizer = ParamSpec(
    key: 'promptExtend',
    labelKey: 'promptExtend',
    control: ParamControl.segmented,
    defaultValue: 'not_set',
    options: [ParamOption('not_set'), ParamOption('on'), ParamOption('off')],
  );

  /// `MiniMax-H3` — the native `/v2/video_generation` task surface
  /// (docs/api/minimax.md §5). Overrides the shared Veo dropdowns because
  /// MiniMax's vocabulary matches neither:
  ///
  ///  * `resolution` — **two** tiers, `768P` and `2K`. Not the 480/720/1080
  ///    ladder every other family uses, so the options carry MiniMax's own
  ///    spelling rather than being bent into the shared one; the payload
  ///    builder normalizes case and falls back to the cheaper tier for
  ///    anything it does not recognize.
  ///  * `aspectRatio` — `adaptive` (upstream's default, meaning "follow the
  ///    input media") plus six fixed ratios. A text-only request has nothing
  ///    to adapt to and upstream demands an explicit value; the payload
  ///    builder substitutes 16:9 in that case.
  ///  * `seconds` — 4–15 s. Both `resolution` and `duration` are **required**
  ///    upstream with no server-side default, which is why neither can be
  ///    left unset the way an optional knob would be.
  ///
  /// `maxReferenceImages: 3` is a client-side ceiling, not a documented one:
  /// MiniMax states no count for `reference_image`, only a 64 MB cap on the
  /// whole request against a 30 MB cap per image. Three base64 images is the
  /// most that reliably fits.
  static const _minimaxVideo = ModelCapabilities(
    isVideoGenerator: true,
    maxReferenceImages: 3,
    videoParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'adaptive',
        options: [
          ParamOption('adaptive'),
          ParamOption('21:9'),
          ParamOption('16:9'),
          ParamOption('4:3'),
          ParamOption('1:1'),
          ParamOption('3:4'),
          ParamOption('9:16'),
        ],
      ),
      ParamSpec(
        key: 'resolution',
        labelKey: 'resolution',
        control: ParamControl.segmented,
        defaultValue: '768P',
        options: [
          ParamOption('768P'),
          ParamOption('2K'),
        ],
      ),
      ParamSpec(
        key: 'seconds',
        labelKey: 'videoSeconds',
        control: ParamControl.slider,
        defaultValue: '5',
        options: [],
        min: 4,
        max: 15,
      ),
    ],
  );

  /// `MiniMaxAI/MiniMax-H3` — the self-hosted SGLang H3-Base surface
  /// (docs/api/minimax.md §8). Diverges from [_minimaxVideo] in exactly the
  /// ways the local wire diverges from the cloud one:
  ///
  ///  * no `resolution` control — the released checkpoints have one verified
  ///    recipe (`short_edge: 768`) and the payload builder always sends it;
  ///    the 2K tier is a cloud-platform component the open weights lack.
  ///  * `aspectRatio` keeps the shared `adaptive` spelling (one option key,
  ///    one label across both MiniMax video wires); the payload builder
  ///    translates it to H3-Base's `auto`.
  ///  * `seconds` — the same 4–15 s window as the cloud surface.
  ///
  /// `maxReferenceImages: 3` mirrors the cloud table's client-side ceiling:
  /// references travel as server-local file paths here, so size is no
  /// constraint, but the ref2va task documents no count of its own either.
  static const _minimaxH3Base = ModelCapabilities(
    isVideoGenerator: true,
    maxReferenceImages: 3,
    videoParams: [
      ParamSpec(
        key: 'aspectRatio',
        labelKey: 'aspectRatio',
        control: ParamControl.dropdown,
        defaultValue: 'adaptive',
        options: [
          ParamOption('adaptive'),
          ParamOption('21:9'),
          ParamOption('16:9'),
          ParamOption('4:3'),
          ParamOption('1:1'),
          ParamOption('3:4'),
          ParamOption('9:16'),
        ],
      ),
      ParamSpec(
        key: 'seconds',
        labelKey: 'videoSeconds',
        control: ParamControl.slider,
        defaultValue: '5',
        options: [],
        min: 4,
        max: 15,
      ),
    ],
  );
}
