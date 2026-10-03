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
const _minimaxVideo = ModelCapabilities(
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
