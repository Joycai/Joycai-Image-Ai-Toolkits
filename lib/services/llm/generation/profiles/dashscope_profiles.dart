part of '../../model_capabilities.dart';

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
      options: [ParamOption('480p'), ParamOption('720p'), ParamOption('1080p')],
    ),
    ParamSpec(
      key: 'seconds',
      valueType: ParamValueType.integer,
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

/// `qwen-image-2.0*` / `-3.0*` on DashScope's native surface — the
/// `input.messages` shape. Up to 3 reference images (10 MB each). The size
/// is a free `WxH` inside [kDashscopeQwenSizeRules] (area 512²–2048²,
/// 1:8–8:1), picked in the size dialog — presets, a ratio calculator, or
/// typed edges — and normalized to DashScope's `W*H` spelling on the wire.
///
/// `not_set` here does **not** mean "send nothing": this endpoint renders an
/// unsized request at 2048² and bills it at the 2K tier — twice the 1K
/// price — so the dialect always sends a size, and `not_set` means "the
/// dialect's default": a 1K square for text-to-image, the input's own
/// proportions fitted into the 1K area for an edit (`dashscopeQwenDefaultSize`).
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
      control: ParamControl.customSize,
      defaultValue: 'not_set',
      options: [ParamOption('not_set')],
      sizeRules: kDashscopeQwenSizeRules,
      sizeVocabulary: _dashscopeQwenSizeVocabulary,
    ),
    _dashscopePromptExtend,
  ],
);

/// `qwen-image-edit-max` / `-plus` (and their dated builds): the same shape,
/// references and `not_set` default as [_dashscopeQwenImage], but a
/// **per-edge** size range — each edge 512–2048 — rather than 2.0 / 3.0's
/// area range ([kDashscopeQwenEditSizeRules]). Sharing the area rules let
/// the picker offer `4096x512`, an edge twice the documented ceiling.
const _dashscopeQwenImageEditMaxPlus = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 3,
  longRunning: true,
  imageRequestShape: ImageRequestShape.dashscopeQwen,
  imageParams: [
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.customSize,
      defaultValue: 'not_set',
      options: [ParamOption('not_set')],
      sizeRules: kDashscopeQwenEditSizeRules,
      sizeVocabulary: _dashscopeQwenSizeVocabulary,
    ),
    _dashscopePromptExtend,
  ],
);

/// A DashScope image model identified only by its protocol (a free-text
/// relay id pinned to the DashScope image wire): qwen's shape and reference
/// ceiling — the smaller — and [kDashscopeCommonSizeRules], the box every
/// free-size DashScope family accepts, so a guess errs toward a request
/// upstream takes.
const _dashscopeImageFallback = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 3,
  longRunning: true,
  imageRequestShape: ImageRequestShape.dashscopeQwen,
  imageParams: [
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.customSize,
      defaultValue: 'not_set',
      options: [ParamOption('not_set')],
      sizeRules: kDashscopeCommonSizeRules,
      sizeVocabulary: _dashscopeQwenSizeVocabulary,
    ),
    _dashscopePromptExtend,
  ],
);

/// The size picker's offer on qwen (`A1c · 30c`): upstream's five ratios,
/// and 1K / 2K as the two area tiers it bills by. No table — the tier's
/// pixels are computed at the ratio (`tierSize`).
const _dashscopeQwenSizeVocabulary = ImageSizeVocabulary(
  ratios: ['1:1', '16:9', '9:16', '4:3', '3:4'],
  tiers: ['1K', '2K'],
  tierKind: SizeTierKind.areaTier,
  sentinel: SizeSentinelMeaning.followsInput,
);

/// wan2.7-image's recommendation table (text-to-image guide, 2026-09-19):
/// tier → landscape ratio → pixels. The 1:1 row is the keyword itself.
const _dashscopeWanOfficialTable = {
  '1K': {'16:9': '1696x960', '4:3': '1472x1104'},
  '2K': {'16:9': '2688x1536', '4:3': '2368x1728'},
  '4K': {'16:9': '4096x2304', '4:3': '4096x3072'},
};

const _dashscopeWanSizeVocabulary = ImageSizeVocabulary(
  ratios: ['1:1', '16:9', '9:16', '4:3', '3:4'],
  tiers: ['1K', '2K'],
  tierKind: SizeTierKind.keyword,
  sentinel: SizeSentinelMeaning.sendsLowestTier,
  officialTable: _dashscopeWanOfficialTable,
);

const _dashscopeWanProSizeVocabulary = ImageSizeVocabulary(
  ratios: ['1:1', '16:9', '9:16', '4:3', '3:4'],
  tiers: ['1K', '2K', '4K'],
  tierKind: SizeTierKind.keyword,
  sentinel: SizeSentinelMeaning.sendsLowestTier,
  officialTable: _dashscopeWanOfficialTable,
);

/// The first-generation `qwen-image` / `qwen-image-plus` / `qwen-image-max`:
/// text-to-image only (no reference images — the `-edit-` models are the
/// ones that take them), and **five fixed sizes and nothing else**, so this
/// is a closed list and there is no `not_set` — the dialect's computed
/// default (`dashscopeQwenDefaultSize`) is not one of the five; the protocol
/// normalizes a stale or missing size to this spec's default instead.
/// Upstream's own default is the 16:9; the square leads here because every
/// other family in the app defaults to one.
/// ⚠ From the platform docs' size table (2026-09), not verified with a key;
/// a wrong guess is a 400, not a silent resize.
const _dashscopeQwenImageFixed = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 0,
  longRunning: true,
  imageRequestShape: ImageRequestShape.dashscopeQwen,
  imageParams: [
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.dropdown,
      defaultValue: '1328x1328',
      options: [
        ParamOption('1328x1328'),
        ParamOption('1664x928'),
        ParamOption('928x1664'),
        ParamOption('1472x1104'),
        ParamOption('1104x1472'),
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
/// (`dashscopeSizeSpec`), so this table is the *only* place that fact
/// lives.
const _dashscopeQwenImageEdit = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 3,
  longRunning: true,
  imageRequestShape: ImageRequestShape.dashscopeQwen,
  imageParams: [_dashscopePromptExtend],
);

/// `wan2.7-image` on DashScope's native surface — the text-first content
/// order. Up to 9 reference images (20 MB each). The size is a tier keyword
/// (`1K` / `2K`) or a free `WxH` inside [kDashscopeWanSizeRules]; the size
/// picker offers upstream's own recommendation table as its ratio × tier
/// cells (16:9 / 9:16 / 4:3 / 3:4 at each tier — the keywords themselves
/// render squares).
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
      control: ParamControl.customSize,
      defaultValue: 'not_set',
      options: [ParamOption('not_set'), ParamOption('1K'), ParamOption('2K')],
      sizeRules: kDashscopeWanSizeRules,
      sizeVocabulary: _dashscopeWanSizeVocabulary,
    ),
    _dashscopePromptExtend,
  ],
);

/// `wan2.7-image-pro`: [_dashscopeWanImage] with the ceiling raised to 4096²
/// and a `4K` keyword. Upstream documents 4K for text-to-image; whether an
/// edit accepts it is not stated ⚠ — a refusal there is a 400.
const _dashscopeWanImagePro = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 9,
  longRunning: true,
  supportsAsyncImageTask: true,
  imageRequestShape: ImageRequestShape.dashscopeWan,
  imageParams: [
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.customSize,
      defaultValue: 'not_set',
      options: [ParamOption('not_set'), ParamOption('1K'), ParamOption('2K'), ParamOption('4K')],
      sizeRules: kDashscopeWanProSizeRules,
      sizeVocabulary: _dashscopeWanProSizeVocabulary,
    ),
    _dashscopePromptExtend,
  ],
);
