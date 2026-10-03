part of '../../model_capabilities.dart';

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
      options: [ParamOption('RELAX'), ParamOption('FAST'), ParamOption('TURBO')],
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
