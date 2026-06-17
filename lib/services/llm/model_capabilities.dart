import 'model_family.dart';

/// How a parameter should be rendered in the workbench config UI.
enum ParamControl { dropdown, segmented }

/// A single selectable option for a parameter.
///
/// [value] is what gets sent to the provider; the human-readable label is
/// resolved in the UI layer (so localization stays out of this pure-data file).
class ParamOption {
  final String value;
  const ParamOption(this.value);
}

/// Declarative spec for one configurable generation parameter.
///
/// [key] is the option key handed to the provider (e.g. `aspectRatio`,
/// `imageSize`, `quality`) and must match what the providers read from the
/// task `options` map. [labelKey] is a stable token the UI maps to a localized
/// label.
class ParamSpec {
  final String key;
  final String labelKey;
  final ParamControl control;
  final List<ParamOption> options;
  final String defaultValue;

  const ParamSpec({
    required this.key,
    required this.labelKey,
    required this.control,
    required this.options,
    required this.defaultValue,
  });

  bool isValid(String? value) => options.any((o) => o.value == value);

  /// Returns [value] when it is a valid option for this spec, otherwise the
  /// default. Guarantees the UI never tries to render an out-of-range value
  /// and the provider never receives one (important when switching families).
  String normalize(String? value) => isValid(value) ? value! : defaultValue;
}

/// What a model family can do, and which parameters apply to it.
class ModelCapabilities {
  /// True when the model's primary output is a generated image (and therefore
  /// the image parameter controls should be shown).
  final bool isImageGenerator;

  /// The image-generation parameters this family understands. Empty for chat /
  /// multimodal / video models — which is what keeps the wrong controls from
  /// showing up for, say, a GPT-4o chat model or a `gemini-2.5-pro` text model.
  final List<ParamSpec> imageParams;

  const ModelCapabilities({
    this.isImageGenerator = false,
    this.imageParams = const [],
  });

  static ModelCapabilities forModel(String modelId) =>
      forFamily(ModelFamilyClassifier.classify(modelId));

  static ModelCapabilities forFamily(ModelFamily family) {
    switch (family) {
      case ModelFamily.geminiImage:
        return _geminiImage;
      case ModelFamily.geminiImagen:
        return _imagen;
      case ModelFamily.openaiImage:
        return _openaiImage;
      case ModelFamily.geminiVideo:
      case ModelFamily.geminiChat:
      case ModelFamily.openaiChat:
      case ModelFamily.other:
        return const ModelCapabilities();
    }
  }

  // --- Family parameter tables ---------------------------------------------

  /// nanoBanana — `gemini-*-image`. Full Gemini aspect-ratio set + 1K/2K/4K.
  static const _geminiImage = ModelCapabilities(
    isImageGenerator: true,
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
        ],
      ),
      ParamSpec(
        key: 'imageSize',
        labelKey: 'resolution',
        control: ParamControl.segmented,
        defaultValue: '1K',
        options: [ParamOption('1K'), ParamOption('2K'), ParamOption('4K')],
      ),
    ],
  );

  /// Imagen — `:predict`. Supports a restricted aspect-ratio set, no 4K.
  static const _imagen = ModelCapabilities(
    isImageGenerator: true,
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

  /// Native OpenAI image (`gpt-image-1`). Pixel sizes + quality, no separate
  /// aspect-ratio control (size encodes the ratio).
  static const _openaiImage = ModelCapabilities(
    isImageGenerator: true,
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
      ParamSpec(
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
      ),
    ],
  );
}
