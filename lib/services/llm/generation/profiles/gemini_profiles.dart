part of '../../model_capabilities.dart';

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
  options: [ParamOption('not_set'), ParamOption('1K'), ParamOption('2K'), ParamOption('4K')],
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
