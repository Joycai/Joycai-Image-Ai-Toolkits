part of '../../model_capabilities.dart';

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
const _minimaxImage = ModelCapabilities(
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
const _minimaxPromptOptimizer = ParamSpec(
  key: 'promptExtend',
  labelKey: 'promptExtend',
  control: ParamControl.segmented,
  defaultValue: 'not_set',
  options: [ParamOption('not_set'), ParamOption('on'), ParamOption('off')],
);

/// Cloud H3 variants, verified against the official V2 create API 2026-10-27.
/// Keep model-specific vocabulary here; encoders consume the resolved profile.
const _minimaxVideo = ModelCapabilities(
  isVideoGenerator: true,
  maxReferenceImages: 9,
  videoParams: [
    _minimaxCloudRatio,
    ParamSpec(
      key: 'resolution',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '768P',
      options: [ParamOption('768P'), ParamOption('2K')],
    ),
    ParamSpec(
      key: 'seconds',
      valueType: ParamValueType.integer,
      labelKey: 'videoSeconds',
      control: ParamControl.slider,
      defaultValue: '5',
      options: [],
      min: 4,
      max: 15,
    ),
  ],
);

const _minimaxHighspeed = ModelCapabilities(
  isVideoGenerator: true,
  maxReferenceImages: 9,
  videoParams: [
    _minimaxCloudRatio,
    ParamSpec(
      key: 'resolution',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '768P',
      options: [ParamOption('768P')],
    ),
    ParamSpec(
      key: 'seconds',
      valueType: ParamValueType.integer,
      labelKey: 'videoSeconds',
      control: ParamControl.slider,
      defaultValue: '5',
      options: [],
      min: 4,
      max: 15,
    ),
  ],
);

const _minimaxLite = ModelCapabilities(
  isVideoGenerator: true,
  maxReferenceImages: 9,
  videoParams: [
    _minimaxFixedRatio,
    ParamSpec(
      key: 'resolution',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '768P',
      options: [ParamOption('480P'), ParamOption('768P')],
    ),
    ParamSpec(
      key: 'seconds',
      valueType: ParamValueType.integer,
      labelKey: 'videoSeconds',
      control: ParamControl.slider,
      defaultValue: '5',
      options: [],
      min: 4,
      max: 15,
    ),
  ],
);

const _minimaxMax = ModelCapabilities(
  isVideoGenerator: true,
  maxReferenceImages: 9,
  videoParams: [
    _minimaxCloudRatio,
    ParamSpec(
      key: 'resolution',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '768P',
      options: [ParamOption('480P'), ParamOption('768P')],
    ),
    ParamSpec(
      key: 'seconds',
      valueType: ParamValueType.integer,
      labelKey: 'videoSeconds',
      control: ParamControl.slider,
      defaultValue: '5',
      options: [],
      min: 5,
      max: 15,
    ),
    ParamSpec(
      key: 'promptExpansionMode',
      labelKey: 'promptExpansionMode',
      control: ParamControl.dropdown,
      defaultValue: 'balanced',
      options: [ParamOption('disabled'), ParamOption('balanced'), ParamOption('quality')],
    ),
  ],
);

const _minimaxCloudRatio = ParamSpec(
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
);

const _minimaxFixedRatio = ParamSpec(
  key: 'aspectRatio',
  labelKey: 'aspectRatio',
  control: ParamControl.dropdown,
  defaultValue: '16:9',
  options: [
    ParamOption('21:9'),
    ParamOption('16:9'),
    ParamOption('4:3'),
    ParamOption('1:1'),
    ParamOption('3:4'),
    ParamOption('9:16'),
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
/// The local checkpoint keeps its existing three-reference ceiling; the
/// cloud API's nine-image contract does not establish local checkpoint limits.
const _minimaxH3Base = ModelCapabilities(
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
      valueType: ParamValueType.integer,
      labelKey: 'videoSeconds',
      control: ParamControl.slider,
      defaultValue: '5',
      options: [],
      min: 4,
      max: 15,
    ),
  ],
);
