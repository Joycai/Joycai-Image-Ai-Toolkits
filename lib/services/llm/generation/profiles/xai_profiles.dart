part of '../../model_capabilities.dart';

/// The ratio control every Grok Imagine image model shares. `auto` lets the
/// model pick the best ratio; for single-image edits the output follows the
/// input's ratio.
const _xaiAspectParam = ParamSpec(
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
);

/// xAI Grok Imagine image, the 2.0 shape (`grok-imagine-image-2.0` and, by
/// default, whatever comes after it). JSON `/images/generations` +
/// `/images/edits`; accepts one source `image` or up to 5 `images[]`
/// references (reference them as `<IMAGE_0>`… in the prompt).
///
/// 2.0 bills its output per resolution × quality (docs/api/usage.md §5), so
/// both are controls here:
///  * `quality` — `low` / `medium`. Medium is what upstream serves when the
///    field is left out, so it is the default: adding the control changes
///    nobody's picture or bill. `auto` exists upstream but hands the tier to
///    the model (measured 2026-09-22: it billed Low once), which no rate
///    table can be written against; `high` is refused with a 400.
///  * `imageSize` — `1k` / `1.5k` / `2k`, the three tiers the matrix prices.
/// Declared ratio → quality → size: the panel pairs cells in declaration
/// order and a three-way segmented control spans its row (`A1f · 4a`), so
/// this puts ratio and quality side by side and the size track underneath.
const _xaiImage = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 5,
  imageParams: [
    _xaiAspectParam,
    ParamSpec(
      key: 'quality',
      labelKey: 'quality',
      control: ParamControl.segmented,
      defaultValue: 'medium',
      options: [ParamOption('low'), ParamOption('medium')],
    ),
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '1k',
      options: [ParamOption('1k'), ParamOption('1.5k'), ParamOption('2k')],
    ),
  ],
);

/// The first-generation Grok Imagine image models — `grok-imagine-image` and
/// `grok-imagine-image-quality` — on the same wire as [_xaiImage] but with a
/// flat price per image (their `/v1/image-generation-models` entry carries
/// an empty `pricing` matrix). No quality control: upstream accepts the
/// field on them without a word, and a knob that moves neither the picture
/// nor the bill is a lie. No `1.5k` either: they answer it with a 400
/// ("1.5K resolution is not supported for this model", measured 2026-09-22).
const _xaiImageLegacy = ModelCapabilities(
  isImageGenerator: true,
  maxReferenceImages: 5,
  imageParams: [
    _xaiAspectParam,
    ParamSpec(
      key: 'imageSize',
      labelKey: 'resolution',
      control: ParamControl.segmented,
      defaultValue: '1k',
      options: [ParamOption('1k'), ParamOption('2k')],
    ),
  ],
);
