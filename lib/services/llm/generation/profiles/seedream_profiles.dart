part of '../../model_capabilities.dart';

// ---------------------------------------------------------------------------
// Seedream (Volcengine Ark) — docs/api/volcengine-ark.md
// ---------------------------------------------------------------------------
//
// One family, five generations that disagree about almost everything, so
// each carries its own table and the workbench shows only what that version
// accepts. Shared rulings:
//
//  * **Size is two controls.** `imageSize` is the resolution tier and
//    defaults to one — every version has a tier it accepts. Only where
//    leaving it off reaches something a tier cannot (5.0 pro's layer
//    decomposition, whose default keeps the source's size) is `not_set`
//    offered too. `aspectRatio` defaults to `not_set`, which sends the tier
//    alone and lets the model read the ratio off the prompt; a chosen ratio
//    sends that version's own pixels for the pair ([tierPixelSizes], whose
//    first tier is upstream's default).
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
  valueType: ParamValueType.integer,
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
///
/// The resolution control carries `not_set`, which sends no `size`: the one
/// way to reach layer decomposition's upstream default, `auto` — the source's
/// own size where it lies in [1280x720, 2K×1.1025] (docs/api/volcengine-ark.md
/// §6). A tier forces a resample, and the price follows the output: 0.3 元
/// an image up to 2.61 MP, 0.6 元 above it, so a forced 2K (4.19 MP) doubles
/// the price of a source that would have stayed under the line. Generation
/// reads the same `not_set` as upstream's generation default, 2K. The
/// default stays `2K`, which a tier-priced fee group can match; `not_set`
/// has no size to match until the output is known.
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
      options: [ParamOption('generate'), ParamOption('layers'), ParamOption('transparent')],
    ),
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '2K',
      options: [ParamOption('not_set'), ParamOption('1K'), ParamOption('1.5K'), ParamOption('2K')],
    ),
    _seedreamAspectRatio,
    _seedreamOutputFormat,
    _seedreamOptimizeMode,
    _seedreamWatermark,
  ],
  tierPixelSizes: {
    // Upstream's default first: the tier a ratio chosen with `not_set` is
    // looked up under ([ModelCapabilities.tierPixelSizes]).
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
  },
);

/// Seedream 5.0 lite (`doubao-seedream-5-0-lite-260128`, the bare dated
/// `doubao-seedream-5-0-260128`, plan alias `doubao-seedream-5.0-lite`).
/// The only generation with web search.
const _seedream50Lite = ModelCapabilities(
  isImageGenerator: true,
  streamsImages: true,
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
  streamsImages: true,
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
  streamsImages: true,
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
  tierPixelSizes: {'2K': _seedream2K, '1K': _seedream1K, '4K': _seedream4K},
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
