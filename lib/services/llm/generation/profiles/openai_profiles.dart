part of '../../model_capabilities.dart';

/// Quality control shared by the native OpenAI image models up to
/// gpt-image-2. OpenAI documents these as capped at `high`; the taller
/// ladder is [_openaiQuality25Param].
const _openaiQualityParam = ParamSpec(
  key: 'quality',
  labelKey: 'quality',
  control: ParamControl.segmented,
  defaultValue: 'auto',
  options: [ParamOption('auto'), ParamOption('low'), ParamOption('medium'), ParamOption('high')],
);

/// gpt-image-2.5's quality ladder: the 2.5 generation (`-flare` /
/// `-sunburst`) adds `xhigh` and `max` above `high`. Kept apart from
/// [_openaiQualityParam] because earlier models reject the two new rungs.
///
/// A dropdown, not the segmented track the four-rung ladder uses: six
/// slots on the workbench's 300px panel leave ~24px per label, and the
/// two-character ones (「超高」, "Extra high") elide to nothing there — the
/// track showed 低 / 中 / 高 with three blank slots around them.
const _openaiQuality25Param = ParamSpec(
  key: 'quality',
  labelKey: 'quality',
  control: ParamControl.dropdown,
  defaultValue: 'auto',
  options: [
    ParamOption('auto'),
    ParamOption('low'),
    ParamOption('medium'),
    ParamOption('high'),
    ParamOption('xhigh'),
    ParamOption('max'),
  ],
);

/// Native OpenAI image (`gpt-image-1`). Pixel sizes + quality, no separate
/// aspect-ratio control (size encodes the ratio). Accepts up to 16 reference
/// images via the images/edits endpoint.
const _openaiImage = ModelCapabilities(
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

const _openaiVideo = ModelCapabilities(
  isVideoGenerator: true,
  maxReferenceImages: 7,
  videoParams: [
    // Sora's `size` is built from these two (`resolveVideoSize`); the panel
    // used to supply them through the shared Veo pair.
    _veoResolutionParam,
    _veoAspectRatioParam,
    ParamSpec(
      key: 'seconds',
      valueType: ParamValueType.integer,
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
      options: [ParamOption('standard'), ParamOption('high')],
    ),
  ],
);

/// The size picker's offer on gpt-image-2 / 2.5 (`A1c · 30d`): its own five
/// ratios, and 1K / 2K / 4K as area *targets* — 4K pushes the long edge to
/// the largest legal size at the ratio (16:9 → 3840×2160, 1:1 → 2880²).
const _gptImageSizeVocabulary = ImageSizeVocabulary(
  ratios: ['1:1', '16:9', '9:16', '3:2', '2:3'],
  tiers: ['1K', '2K', '4K'],
  tierKind: SizeTierKind.areaTarget,
  sentinel: SizeSentinelMeaning.modelDecides,
);

/// Native OpenAI image v2 (`gpt-image-2`). The size param renders as a
/// custom picker (preset chips + free WxH input). OpenAI accepts any
/// dimensions meeting four rules — see [kOpenAIImage2SizeRules] — so the
/// preset list below is only quick-pick scaffolding; the dialog enforces
/// the actual constraints.
const _openaiImage2 = ModelCapabilities(
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
      sizeRules: kOpenAIImage2SizeRules,
      sizeVocabulary: _gptImageSizeVocabulary,
    ),
    _openaiQualityParam,
  ],
);

/// Native OpenAI image v2.5 (`gpt-image-2.5-flare` / `-sunburst`,
/// 2026-09-08). Same endpoints, size rules and reference-image cap as
/// [_openaiImage2]; the only visible difference is the quality ladder,
/// which gains `xhigh` and `max`.
const _openaiImage25 = ModelCapabilities(
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
      sizeRules: kOpenAIImage2SizeRules,
      sizeVocabulary: _gptImageSizeVocabulary,
    ),
    _openaiQuality25Param,
  ],
);
