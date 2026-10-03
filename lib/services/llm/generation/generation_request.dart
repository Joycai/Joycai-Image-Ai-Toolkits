import 'generation_schema.dart';
import 'generation_value.dart';

/// Immutable, JSON-safe intent. Credentials and execution callbacks belong
/// to the runtime, never to a queued request.
class GenerationRequest {
  GenerationRequest({
    required this.prompt,
    required this.operation,
    required Map<String, GenerationValue> values,
    required List<GenerationMedia> media,
    required this.modelId,
    required this.channelType,
    required this.protocolId,
    required this.profileId,
    this.modelRowId,
    this.channelRowId,
    this.schemaVersion = GenerationSchema.version,
  }) : values = Map.unmodifiable(values),
       media = List.unmodifiable(media);

  final String prompt;
  final GenerationOperation operation;
  final Map<String, GenerationValue> values;
  final List<GenerationMedia> media;
  final String modelId;
  final int? modelRowId;
  final int? channelRowId;
  final String channelType;
  final String? protocolId;
  final String profileId;
  final int schemaVersion;
  static const codecVersion = 1;
  static const taskKey = 'generation';

  Map<String, dynamic> toJson() => {
    'version': codecVersion,
    'schemaVersion': schemaVersion,
    'prompt': prompt,
    'operation': operation.name,
    'values': {for (final entry in values.entries) entry.key: entry.value.toJson()},
    'media': [for (final item in media) item.toJson()],
    'modelId': modelId,
    'modelRowId': modelRowId,
    'channelRowId': channelRowId,
    'channelType': channelType,
    'protocolId': protocolId,
    'profileId': profileId,
  };

  factory GenerationRequest.fromJson(Map<String, dynamic> json) {
    if (json['version'] != codecVersion) {
      throw const FormatException('Unsupported generation request version');
    }
    return GenerationRequest(
      prompt: json['prompt'] as String,
      operation: GenerationOperation.values.byName(json['operation'] as String),
      values: (json['values'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, GenerationValue.fromJson(Map<String, dynamic>.from(value as Map))),
      ),
      media: [
        for (final item in json['media'] as List)
          GenerationMedia.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      modelId: json['modelId'] as String,
      modelRowId: json['modelRowId'] as int?,
      channelRowId: json['channelRowId'] as int?,
      channelType: json['channelType'] as String,
      protocolId: json['protocolId'] as String?,
      profileId: json['profileId'] as String,
      schemaVersion: json['schemaVersion'] as int,
    );
  }

  static GenerationRequest? fromTask(Map<String, dynamic> params) {
    final json = params[taskKey];
    if (json == null) return null;
    if (json is! Map) throw const FormatException('Invalid generation task data');
    return GenerationRequest.fromJson(Map<String, dynamic>.from(json));
  }

  /// A read-only compatibility view for existing encoders, billing and UI.
  /// It is never persisted beside the authoritative nested representation.
  Map<String, dynamic> get legacyOptions => {
    'prompt': prompt,
    for (final entry in values.entries)
      entry.key: switch (entry.value.kind) {
        GenerationValueKind.unset => 'not_set',
        GenerationValueKind.auto => 'auto',
        GenerationValueKind.boolean => entry.value.value == true ? 'on' : 'off',
        _ => entry.value.value.toString(),
      },
    if (media.any((m) => m.role == GenerationMediaRole.firstFrame))
      'firstFramePath': media.firstWhere((m) => m.role == GenerationMediaRole.firstFrame).path,
    if (media.any((m) => m.role == GenerationMediaRole.lastFrame))
      'lastFramePath': media.firstWhere((m) => m.role == GenerationMediaRole.lastFrame).path,
    'referenceImagePaths': [
      for (final m in media)
        if (m.role == GenerationMediaRole.reference || m.role == GenerationMediaRole.source) m.path,
    ],
  };

  bool matches({required String model, required String vendor, required GenerationSchema schema}) =>
      modelId == model &&
      channelType == vendor &&
      protocolId == schema.protocol?.id &&
      profileId == schema.profileId &&
      schemaVersion == GenerationSchema.version;
}

Map<String, dynamic> generationTaskOptions(Map<String, dynamic> parameters) {
  final request = GenerationRequest.fromTask(parameters);
  if (request == null) return Map.of(parameters);
  const mediaKeys = {'prompt', 'firstFramePath', 'lastFramePath', 'referenceImagePaths'};
  return {
    for (final entry in parameters.entries)
      if (!mediaKeys.contains(entry.key)) entry.key: entry.value,
    ...request.legacyOptions,
  };
}
