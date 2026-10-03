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

/// grok-imagine-video-1.5 — xAI's native async video surface
/// (`/videos/generations`, see `_submitXaiVideo`) on xAI channels, or the
/// NewAPI `/v1/videos` relay otherwise. Overrides the shared Veo
/// resolution/aspect-ratio dropdowns (the video panel hides those and
/// renders these instead) since xAI's option set is different:
///  * `aspectRatio` — 1:1, 16:9/9:16, 4:3/3:4, 3:2/2:3, or unset (skips the
///    `aspect_ratio` field entirely and lets the model choose).
///  * `resolution` — 480p / 720p / 1080p.
///  * `seconds` — a 1–15s duration slider (xAI's `duration` field).
const _grokImagineVideo = ModelCapabilities(
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
      options: [ParamOption('480p'), ParamOption('720p'), ParamOption('1080p')],
    ),
    ParamSpec(
      key: 'seconds',
      valueType: ParamValueType.integer,
      labelKey: 'videoSeconds',
      control: ParamControl.slider,
      defaultValue: '6',
      options: [],
      min: 1,
      max: 15,
    ),
  ],
);
