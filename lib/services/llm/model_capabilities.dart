import 'model_family.dart';

/// How a parameter should be rendered in the workbench config UI.
///
/// `customSize` is a specialised control for image-size parameters whose set
/// of legal values isn't enumerable — the spec lists popular presets, but the
/// dialog also lets the user type any WxH that satisfies the param's
/// [ParamSpec.customValidator]. Used by gpt-image-2, where OpenAI accepts any
/// pixel dimensions meeting four numeric constraints.
enum ParamControl { dropdown, segmented, customSize }

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

  const ParamSpec({
    required this.key,
    required this.labelKey,
    required this.control,
    required this.options,
    required this.defaultValue,
    this.customValidator,
  });

  bool isValid(String? value) {
    if (value == null) return false;
    if (options.any((o) => o.value == value)) return true;
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

  /// 1K / 2K / 4K resolution control shared by every nanoBanana image family.
  static const _geminiSizeParam = ParamSpec(
    key: 'imageSize',
    labelKey: 'resolution',
    control: ParamControl.segmented,
    defaultValue: '1K',
    options: [ParamOption('1K'), ParamOption('2K'), ParamOption('4K')],
  );

  /// nanoBanana — `gemini-*-image`. Full Gemini aspect-ratio set + 1K/2K/4K.
  /// Accepts multiple reference images (no hard limit enforced here).
  static const _geminiImage = ModelCapabilities(
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
        ],
      ),
      _geminiSizeParam,
    ],
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
}
