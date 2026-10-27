import '../image_size_rules.dart';
import '../model_capabilities.dart';
import '../protocols/generation_contract.dart';
import '../vendors/vendor_profile.dart';
import 'generation_param.dart';
import 'generation_value.dart';

enum GenerationOperation {
  textImage,
  editImage,
  subjectImage,
  layers,
  transparent,
  textVideo,
  firstFrame,
  firstLastFrame,
  referenceVideo,
}

enum GenerationMediaRole {
  source,
  reference,
  firstFrame,
  lastFrame,
  referenceVideo,
  referenceAudio,
}

enum GenerationFieldState { active, inactive, fixed }

class GenerationMedia {
  const GenerationMedia(this.role, this.path);
  final GenerationMediaRole role;
  final String path;

  Map<String, dynamic> toJson() => {'role': role.name, 'path': path};

  factory GenerationMedia.fromJson(Map<String, dynamic> json) => GenerationMedia(
    GenerationMediaRole.values.byName(json['role'] as String),
    json['path'] as String,
  );
}

class GenerationDiagnostic {
  const GenerationDiagnostic(this.code, {this.field, this.count});
  final String code;
  final String? field;
  final int? count;
}

/// An effective contract receives an already resolved wire, never routes.
class GenerationSchema {
  GenerationSchema({
    required this.protocol,
    required this.capabilities,
    required this.profileId,
    this.configurationDiagnostics = const [],
  }) : params = List.unmodifiable([
         for (final spec
             in capabilities.isVideoGenerator ? capabilities.videoParams : capabilities.imageParams)
           GenerationParam(spec),
       ]);

  final WireProtocol? protocol;
  final ModelCapabilities capabilities;
  final String profileId;
  final List<GenerationParam> params;
  final List<GenerationDiagnostic> configurationDiagnostics;
  static const version = 1;
  static final semanticKeys = Set<String>.unmodifiable({
    for (final caps in ModelCapabilities.profiles.values)
      for (final param in [...caps.imageParams, ...caps.videoParams]) param.key,
  });

  bool get isVideo => capabilities.isVideoGenerator;
  GenerationProtocolContract get contract => GenerationProtocolContract.forWire(protocol);
  bool get supportsLastFrame => isVideo && contract.lastFrame;
  bool get exclusiveFrames => contract.exclusiveFrames;

  GenerationOperation operation(Map<String, GenerationValue> values, List<GenerationMedia> media) {
    final mode = values['imageTask']?.value;
    if (mode == 'layers') return GenerationOperation.layers;
    if (mode == 'transparent') return GenerationOperation.transparent;
    if (!isVideo) {
      if (media.isEmpty) return GenerationOperation.textImage;
      return contract.subjectReferences
          ? GenerationOperation.subjectImage
          : GenerationOperation.editImage;
    }
    if (media.any((m) => m.role == GenerationMediaRole.lastFrame)) {
      return GenerationOperation.firstLastFrame;
    }
    if (media.any((m) => m.role == GenerationMediaRole.firstFrame)) {
      return GenerationOperation.firstFrame;
    }
    return media.isEmpty ? GenerationOperation.textVideo : GenerationOperation.referenceVideo;
  }

  GenerationFieldState fieldState(
    String key,
    GenerationOperation operation, [
    Map<String, GenerationValue> values = const {},
  ]) {
    if (key == 'aspectRatio' &&
        contract.frameRatioAdaptive &&
        (operation == GenerationOperation.firstFrame ||
            operation == GenerationOperation.firstLastFrame)) {
      return GenerationFieldState.fixed;
    }
    if (capabilities.imageRequestShape == ImageRequestShape.dashscopeWan &&
        key == 'imageThinking' &&
        operation != GenerationOperation.textImage) {
      return GenerationFieldState.inactive;
    }
    if ((key == 'promptExtendMode' || key == 'imageThinking') &&
        values['promptExtend']?.value == false) {
      return GenerationFieldState.inactive;
    }
    if (key == 'outputCompression' && !['jpeg', 'webp'].contains(values['outputFormat']?.value)) {
      return GenerationFieldState.inactive;
    }
    if (operation == GenerationOperation.layers && key == 'aspectRatio') {
      return GenerationFieldState.inactive;
    }
    if ((operation == GenerationOperation.layers || operation == GenerationOperation.transparent) &&
        key == 'maxImages') {
      return GenerationFieldState.inactive;
    }
    if (operation == GenerationOperation.transparent && key == 'outputFormat') {
      return GenerationFieldState.fixed;
    }
    return GenerationFieldState.active;
  }

  Map<String, GenerationValue> effective(
    Map<String, GenerationValue> draft,
    GenerationOperation operation,
  ) => {
    for (final param in params)
      if (fieldState(param.key, operation, draft) != GenerationFieldState.inactive)
        param.key: fieldState(param.key, operation, draft) == GenerationFieldState.fixed
            ? fixedValue(param.key)
            : draft[param.key] ?? param.defaultValue,
  };

  GenerationValue fixedValue(String key) =>
      GenerationValue(GenerationValueKind.choice, key == 'aspectRatio' ? 'adaptive' : 'png');

  Map<String, dynamic> legacyOptions(Map<String, GenerationValue> values) => {
    for (final param in params)
      if (values[param.key] case final value?) param.key: param.encode(value),
  };

  Map<String, GenerationValue> readLegacy(Map<String, dynamic> options) => {
    for (final param in params)
      param.key: options[param.key] == null
          ? param.defaultValue
          : param.decode(options[param.key].toString()),
  };

  List<GenerationDiagnostic> validatePrompt(String prompt) {
    final limit = contract.requiredPromptMaxCharacters;
    return [
      if (limit != null && (prompt.trim().isEmpty || prompt.runes.length > limit))
        const GenerationDiagnostic('videoPromptLength'),
    ];
  }

  List<GenerationDiagnostic> validate(
    Map<String, GenerationValue> values,
    List<GenerationMedia> media,
  ) {
    final diagnostics = <GenerationDiagnostic>[...configurationDiagnostics];
    if (media.isNotEmpty &&
        capabilities.imageRequestShape == ImageRequestShape.dashscopeWan &&
        dashscopeEditSizeTooLarge(values['imageSize']?.value?.toString())) {
      diagnostics.add(const GenerationDiagnostic('wanEditSize', field: 'imageSize'));
    }
    if (media.isNotEmpty &&
        values['promptExtendMode']?.value == 'agent' &&
        values['promptExtend']?.value != false) {
      diagnostics.add(const GenerationDiagnostic('agentTextOnly', field: 'promptExtendMode'));
    }
    for (final param in params) {
      if (fieldState(param.key, operation(values, media), values) == GenerationFieldState.fixed) {
        continue;
      }
      if (values[param.key] case final value?) {
        if (!param.accepts(value)) {
          diagnostics.add(GenerationDiagnostic('invalidParameter', field: param.key));
        }
      }
    }
    if (values['background']?.value == 'transparent' && values['outputFormat']?.value == 'jpeg') {
      diagnostics.add(const GenerationDiagnostic('transparentJpeg', field: 'outputFormat'));
    }
    final first = media.where((m) => m.role == GenerationMediaRole.firstFrame).length;
    final last = media.where((m) => m.role == GenerationMediaRole.lastFrame).length;
    final videos = media.where((m) => m.role == GenerationMediaRole.referenceVideo).length;
    final audios = media.where((m) => m.role == GenerationMediaRole.referenceAudio).length;
    final refs = media.length - first - last - videos - audios;
    if (videos + audios > 0 && !contract.referenceAudioVideo) {
      diagnostics.add(const GenerationDiagnostic('unsupportedReferenceMedia'));
    }
    if (contract.referenceAudioVideo && (videos > 3 || audios > 3 || media.length > 12)) {
      diagnostics.add(const GenerationDiagnostic('tooManyReferences'));
    }
    if (first > 1 || last > 1) diagnostics.add(const GenerationDiagnostic('duplicateFrame'));
    if (last > 0 && !supportsLastFrame) {
      diagnostics.add(const GenerationDiagnostic('unsupportedLastFrame'));
    }
    if (last > 0 && first == 0 && !contract.standaloneLastFrame) {
      diagnostics.add(const GenerationDiagnostic('missingFirstFrame'));
    }
    if (exclusiveFrames && first + last > 0 && refs + videos + audios > 0) {
      diagnostics.add(const GenerationDiagnostic('conflictingMedia'));
    }
    final limit = capabilities.maxReferenceImages;
    if (limit != null && refs > limit) {
      diagnostics.add(GenerationDiagnostic('tooManyReferences', count: limit));
    }
    final op = operation(values, media);
    if ((op == GenerationOperation.layers || op == GenerationOperation.transparent) &&
        media.length != 1) {
      diagnostics.add(const GenerationDiagnostic('singleSourceRequired'));
    }
    if (contract.groupLimit != null &&
        op != GenerationOperation.layers &&
        op != GenerationOperation.transparent) {
      final count = values['maxImages']?.value;
      if (count is int && count + media.length > contract.groupLimit!) {
        diagnostics.add(GenerationDiagnostic('groupLimit', count: contract.groupLimit));
      }
    }
    return List.unmodifiable(diagnostics);
  }
}
