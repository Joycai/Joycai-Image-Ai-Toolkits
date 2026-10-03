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

enum GenerationMediaRole { source, reference, firstFrame, lastFrame }

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

  GenerationFieldState fieldState(String key, GenerationOperation operation) {
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
      if (fieldState(param.key, operation) != GenerationFieldState.inactive)
        param.key: fieldState(param.key, operation) == GenerationFieldState.fixed
            ? const GenerationValue(GenerationValueKind.choice, 'png')
            : draft[param.key] ?? param.defaultValue,
  };

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

  List<GenerationDiagnostic> validate(
    Map<String, GenerationValue> values,
    List<GenerationMedia> media,
  ) {
    final diagnostics = <GenerationDiagnostic>[...configurationDiagnostics];
    for (final param in params) {
      if (values[param.key] case final value?) {
        if (!param.accepts(value)) {
          diagnostics.add(GenerationDiagnostic('invalidParameter', field: param.key));
        }
      }
    }
    final first = media.where((m) => m.role == GenerationMediaRole.firstFrame).length;
    final last = media.where((m) => m.role == GenerationMediaRole.lastFrame).length;
    final refs = media.length - first - last;
    if (first > 1 || last > 1) diagnostics.add(const GenerationDiagnostic('duplicateFrame'));
    if (last > 0 && !supportsLastFrame) {
      diagnostics.add(const GenerationDiagnostic('unsupportedLastFrame'));
    }
    if (last > 0 && first == 0) diagnostics.add(const GenerationDiagnostic('missingFirstFrame'));
    if (exclusiveFrames && first + last > 0 && refs > 0) {
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
