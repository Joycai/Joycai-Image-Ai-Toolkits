part of 'model_capabilities.dart';

// --- Family parameter tables ---------------------------------------------

/// 1K / 2K / 4K resolution control shared by the nanoBanana image families
/// that have one.
///
/// `not_set` is the default and means the field is not sent — the upstream
/// default is the 1K tier, so nothing is lost, and "not sent" is the one
/// spelling every host accepts. The value must be uppercase `K` on the
/// wire; the options carry it that way so nothing has to translate.
const _geminiSizeParam = ParamSpec(
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
const _geminiAspectParam = ParamSpec(
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
const _geminiImage = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: null,
  imageParams: [_geminiAspectParam, _geminiSizeParam],
);

/// The first nanoBanana, `gemini-2.5-flash-image`: the same ratios, but
/// **no resolution control** — the model has a single 1024px tier and no
/// `imageSize` field. Its own table so the control is never rendered and
/// the field never sent; the shared table used to send `imageSize: 1K` to
/// it on every request by default.
const _geminiImageLegacy = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: null,
  imageParams: [_geminiAspectParam],
);

/// Nano Banana Pro — `gemini-3.1-pro-image`. The standard nanoBanana set plus
/// the 21:9 ultrawide ratio.
const _geminiImagePro = ModelCapabilities(
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
const _geminiImageV2 = ModelCapabilities(
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
const _imagen = ModelCapabilities(
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

/// Quality control shared by the native OpenAI image models up to
/// gpt-image-2. OpenAI documents these as capped at `high`; the taller
/// ladder is [_openaiQuality25Param].
const _openaiQualityParam = ParamSpec(
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

/// Sora 2 / grok-imagine / Wanxiang / Kling / Vidu / Jimeng served via
/// NewAPI's OpenAI-compatible `/v1/videos` surface. Submit → poll → mp4 URL.
///
/// Accepts up to one `input_reference` image (mapped from `firstFramePath`)
/// and up to 7 reference images (mapped to `images[]`). The shared
/// aspectRatio + resolution dropdowns in the video panel still drive the
/// upstream `size` field; the parameters below are the openaiVideo-only
/// extensions that wouldn't make sense for Veo.
const _openaiVideo = ModelCapabilities(
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
const _dashscopeWanVideo = ModelCapabilities(
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
const _xaiImage = ModelCapabilities(
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
const _dashscopePromptExtend = ParamSpec(
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
const _dashscopeQwenImage = ModelCapabilities(
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
const _dashscopeQwenImageEdit = ModelCapabilities(
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
const _dashscopeWanImage = ModelCapabilities(
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
const _midjourney = ModelCapabilities(
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
      customValidator: isValidOpenAIImage2Size,
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
      customValidator: isValidOpenAIImage2Size,
    ),
    _openaiQuality25Param,
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
      labelKey: 'videoSeconds',
      control: ParamControl.slider,
      defaultValue: '5',
      options: [],
      min: 4,
      max: 15,
    ),
  ],
);

// ---------------------------------------------------------------------------
// Seedream (Volcengine Ark) — docs/api/volcengine-ark.md
// ---------------------------------------------------------------------------
//
// One family, five generations that disagree about almost everything, so
// each carries its own table and the workbench shows only what that version
// accepts. Shared rulings:
//
//  * **Size is two controls.** `imageSize` is the resolution tier and is
//    always sent — every version has a tier it accepts, so there is no
//    "unset" to offer. `aspectRatio` defaults to `not_set`, which sends the
//    tier alone and lets the model read the ratio off the prompt; a chosen
//    ratio sends that version's own pixels for the pair ([tierPixelSizes]).
//  * **Watermark is sent, off by default.** Upstream defaults it *on* and
//    bills the image all the same; every documented example turns it off.
//    Explicit rather than inherited, like wan3's billed audio switch.
//  * `longRunning`: the request returns only once every image exists — 43 s
//    measured for one 1K 5.0 pro image, minutes for a group.

/// The ratio vocabulary every Seedream generation documents a mapping for.
const _seedreamAspectRatio = ParamSpec(
  key: 'aspectRatio',
  labelKey: 'aspectRatio',
  control: ParamControl.dropdown,
  defaultValue: 'not_set',
  options: [
    ParamOption('not_set'),
    ParamOption('1:1'),
    ParamOption('4:3'),
    ParamOption('3:4'),
    ParamOption('16:9'),
    ParamOption('9:16'),
    ParamOption('3:2'),
    ParamOption('2:3'),
    ParamOption('21:9'),
  ],
);

/// `sequential_image_generation` behind one control: `1` sends nothing (a
/// single image, upstream's default); `n > 1` turns group generation on with
/// `max_images: n`. The model decides how many to draw — this is a ceiling.
const _seedreamMaxImages = ParamSpec(
  key: 'maxImages',
  labelKey: 'maxImages',
  control: ParamControl.dropdown,
  defaultValue: '1',
  options: [
    ParamOption('1'),
    ParamOption('2'),
    ParamOption('3'),
    ParamOption('4'),
    ParamOption('5'),
    ParamOption('6'),
    ParamOption('7'),
    ParamOption('8'),
    ParamOption('9'),
    ParamOption('10'),
    ParamOption('11'),
    ParamOption('12'),
    ParamOption('13'),
    ParamOption('14'),
    ParamOption('15'),
  ],
);

const _seedreamWatermark = ParamSpec(
  key: 'watermark',
  labelKey: 'watermark',
  control: ParamControl.segmented,
  defaultValue: 'off',
  options: [ParamOption('off'), ParamOption('on')],
);

/// `output_format` — 5.0 only; 4.x always answers JPEG.
const _seedreamOutputFormat = ParamSpec(
  key: 'outputFormat',
  labelKey: 'outputFormat',
  control: ParamControl.segmented,
  defaultValue: 'jpeg',
  options: [ParamOption('jpeg'), ParamOption('png')],
);

/// `optimize_prompt_options.mode` — `fast` exists on 5.0 pro and 4.0 only.
const _seedreamOptimizeMode = ParamSpec(
  key: 'optimizeMode',
  labelKey: 'optimizeMode',
  control: ParamControl.segmented,
  defaultValue: 'standard',
  options: [ParamOption('standard'), ParamOption('fast')],
);

/// The documented pixels of each generation's 2K / 4K tiers — identical on
/// 5.0 lite, 4.5 and 4.0.
const _seedream2K = {
  '1:1': '2048x2048',
  '4:3': '2304x1728',
  '3:4': '1728x2304',
  '16:9': '2848x1600',
  '9:16': '1600x2848',
  '3:2': '2496x1664',
  '2:3': '1664x2496',
  '21:9': '3136x1344',
};

const _seedream4K = {
  '1:1': '4096x4096',
  '4:3': '4704x3520',
  '3:4': '3520x4704',
  '16:9': '5504x3040',
  '9:16': '3040x5504',
  '3:2': '4992x3328',
  '2:3': '3328x4992',
  '21:9': '6240x2656',
};

/// 4.0's 1K tier (and 3.0's only size range) as the API reference spells it.
/// The tutorial page gives 1312x736 / 736x1312 / 1568x672 for three of these;
/// both sets sit inside 4.0's pixel range.
const _seedream1K = {
  '1:1': '1024x1024',
  '4:3': '1152x864',
  '3:4': '864x1152',
  '16:9': '1280x720',
  '9:16': '720x1280',
  '3:2': '1248x832',
  '2:3': '832x1248',
  '21:9': '1512x648',
};

/// Seedream 5.0 pro (`doubao-seedream-5-0-pro-260628`, plan alias
/// `doubao-seedream-5.0-pro`). The one generation without group generation,
/// and the one with task modes: layer decomposition and transparent-layer
/// editing each need exactly one reference image, and are mutually
/// exclusive, so they are one three-way control rather than two switches
/// whose "both on" is a guaranteed 400. Interactive editing has no field —
/// it is the prompt's `<bbox>` tags or marks drawn on the reference.
const _seedream50Pro = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 10,
  longRunning: true,
  imageParams: [
    ParamSpec(
      key: 'imageTask',
      labelKey: 'imageTask',
      control: ParamControl.segmented,
      defaultValue: 'generate',
      options: [
        ParamOption('generate'),
        ParamOption('layers'),
        ParamOption('transparent'),
      ],
    ),
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '2K',
      options: [ParamOption('1K'), ParamOption('1.5K'), ParamOption('2K')],
    ),
    _seedreamAspectRatio,
    _seedreamOutputFormat,
    _seedreamOptimizeMode,
    _seedreamWatermark,
  ],
  tierPixelSizes: {
    '1K': {
      '1:1': '1024x1024',
      '4:3': '1152x864',
      '3:4': '864x1152',
      '16:9': '1424x800',
      '9:16': '800x1424',
      '3:2': '1248x832',
      '2:3': '832x1248',
      '21:9': '1568x672',
    },
    '1.5K': {
      '1:1': '1536x1536',
      '4:3': '1792x1344',
      '3:4': '1344x1792',
      '16:9': '2048x1152',
      '9:16': '1152x2048',
      '3:2': '1872x1248',
      '2:3': '1248x1872',
      '21:9': '2352x1008',
    },
    '2K': {
      '1:1': '2048x2048',
      '4:3': '2368x1776',
      '3:4': '1776x2368',
      '16:9': '2816x1584',
      '9:16': '1584x2816',
      '3:2': '2496x1664',
      '2:3': '1664x2496',
      '21:9': '3136x1344',
    },
  },
);

/// Seedream 5.0 lite (`doubao-seedream-5-0-lite-260128`, the bare dated
/// `doubao-seedream-5-0-260128`, plan alias `doubao-seedream-5.0-lite`).
/// The only generation with web search.
const _seedream50Lite = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 14,
  longRunning: true,
  imageParams: [
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '2K',
      options: [ParamOption('2K'), ParamOption('3K'), ParamOption('4K')],
    ),
    _seedreamAspectRatio,
    _seedreamMaxImages,
    _seedreamOutputFormat,
    ParamSpec(
      key: 'webSearch',
      labelKey: 'webSearch',
      control: ParamControl.segmented,
      defaultValue: 'off',
      options: [ParamOption('off'), ParamOption('on')],
    ),
    _seedreamWatermark,
  ],
  tierPixelSizes: {
    '2K': _seedream2K,
    '3K': {
      '1:1': '3072x3072',
      '4:3': '3456x2592',
      '3:4': '2592x3456',
      '16:9': '4096x2304',
      '9:16': '2304x4096',
      '3:2': '3744x2496',
      '2:3': '2496x3744',
      '21:9': '4704x2016',
    },
    '4K': _seedream4K,
  },
);

/// Seedream 4.5 (`doubao-seedream-4-5-251128`). JPEG only, standard prompt
/// optimization only — neither gets a control.
const _seedream45 = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 14,
  longRunning: true,
  imageParams: [
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '2K',
      options: [ParamOption('2K'), ParamOption('4K')],
    ),
    _seedreamAspectRatio,
    _seedreamMaxImages,
    _seedreamWatermark,
  ],
  tierPixelSizes: {'2K': _seedream2K, '4K': _seedream4K},
);

/// Seedream 4.0 (`doubao-seedream-4-0-250828`). JPEG only; `fast` prompt
/// optimization is offered.
const _seedream40 = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 14,
  longRunning: true,
  imageParams: [
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '2K',
      options: [ParamOption('1K'), ParamOption('2K'), ParamOption('4K')],
    ),
    _seedreamAspectRatio,
    _seedreamMaxImages,
    _seedreamOptimizeMode,
    _seedreamWatermark,
  ],
  tierPixelSizes: {'1K': _seedream1K, '2K': _seedream2K, '4K': _seedream4K},
);

/// Seedream 3.0 text-to-image (`doubao-seedream-3-0-t2i-250415`): pixels only
/// (no tiers), no references, no groups. The ratio maps onto its ~1 MP sizes.
const _seedream30 = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 0,
  longRunning: true,
  imageParams: [_seedreamAspectRatio, _seedreamWatermark],
  tierPixelSizes: {'1K': _seedream1K},
);

/// A Seedream id whose generation cannot be read (a relay alias) — and the
/// table the Ark image protocol implies for an id that is not a Seedream id
/// at all (an Ark endpoint id `ep-…` pinned to it).
///
/// Errs toward what every current generation accepts: the tier may be left
/// unset (each version then applies its own default), 2K is valid on all
/// four, 4K on three — the one that rejects it (5.0 pro) says so with a 400,
/// which beats a control that silently does nothing. References capped at
/// 5.0 pro's 10, the lowest ceiling.
const _seedreamGeneric = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 10,
  longRunning: true,
  imageParams: [
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: 'not_set',
      options: [ParamOption('not_set'), ParamOption('2K'), ParamOption('4K')],
    ),
    _seedreamAspectRatio,
    _seedreamMaxImages,
    _seedreamWatermark,
  ],
  tierPixelSizes: {'2K': _seedream2K, '4K': _seedream4K},
);
