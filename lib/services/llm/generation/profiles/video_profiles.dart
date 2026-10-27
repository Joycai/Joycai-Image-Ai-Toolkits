part of '../../model_capabilities.dart';

/// Sora 2 / grok-imagine / Wanxiang / Kling / Vidu / Jimeng served via
/// NewAPI's OpenAI-compatible `/v1/videos` surface. Submit → poll → mp4 URL.
///
/// Accepts up to one `input_reference` image (mapped from `firstFramePath`)
/// and up to 7 reference images (mapped to `images[]`). The shared
/// aspectRatio + resolution dropdowns in the video panel still drive the
/// upstream `size` field; the parameters below are the openaiVideo-only
/// extensions that wouldn't make sense for Veo.
/// Veo's resolution and aspect ratio, declared like every other family's
/// video controls. They used to be two dropdowns built into the video panel
/// for every model that did not override them — Veo's vocabulary shown to
/// MiniMax's H3, which reads no resolution at all.
const _veoResolutionParam = ParamSpec(
  key: 'resolution',
  labelKey: 'resolution',
  control: ParamControl.dropdown,
  defaultValue: '720p',
  options: [ParamOption('720p'), ParamOption('1080p'), ParamOption('4k')],
);

const _veoAspectRatioParam = ParamSpec(
  key: 'aspectRatio',
  labelKey: 'aspectRatio',
  control: ParamControl.dropdown,
  defaultValue: '16:9',
  options: [ParamOption('16:9'), ParamOption('9:16')],
);

/// Veo (Gemini `predictLongRunning`): the two controls above.
const _veoVideo = ModelCapabilities(
  isVideoGenerator: true,
  videoParams: [_veoResolutionParam, _veoAspectRatioParam],
);

/// Native xAI profiles. Keep the existing profile ID for 1.5 snapshots.
const _grokImagineVideo = ModelCapabilities(
  isVideoGenerator: true,
  maxReferenceImages: 14,
  nativeVideoContract: GenerationProtocolContract(
    standaloneLastFrame: true,
    referenceMaxResolution: '720p',
  ),
  videoParams: [_grokAspect, _grokResolution, _grokSeconds],
);

const _grokImagineVideoClassic = ModelCapabilities(
  isVideoGenerator: true,
  maxReferenceImages: 7,
  nativeVideoContract: GenerationProtocolContract(
    lastFrame: false,
    exclusiveFrames: true,
    referenceMaxSeconds: 10,
    referenceMaxResolution: '720p',
  ),
  videoParams: [
    _grokAspect,
    ParamSpec(
      key: 'resolution',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '720p',
      options: [ParamOption('480p'), ParamOption('720p')],
    ),
    _grokSeconds,
  ],
);

const _grokImagineVideoLite = ModelCapabilities(
  isVideoGenerator: true,
  maxReferenceImages: 0,
  nativeVideoContract: GenerationProtocolContract(lastFrame: false, exclusiveFrames: true),
  videoParams: [_grokAspect, _grokResolution, _grokSeconds],
);

const _grokAspect = ParamSpec(
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
    ParamOption('21:9'),
    ParamOption('5:2'),
  ],
);
const _grokResolution = ParamSpec(
  key: 'resolution',
  labelKey: 'resolution',
  control: ParamControl.segmented,
  defaultValue: '720p',
  options: [ParamOption('480p'), ParamOption('720p'), ParamOption('1080p')],
);
const _grokSeconds = ParamSpec(
  key: 'seconds',
  valueType: ParamValueType.integer,
  labelKey: 'videoSeconds',
  control: ParamControl.slider,
  defaultValue: '6',
  options: [],
  min: 1,
  max: 15,
);
