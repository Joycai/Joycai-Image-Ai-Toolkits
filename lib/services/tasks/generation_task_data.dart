import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/task_item.dart';
import '../llm/generation/generation_request.dart';
import '../llm/generation/generation_schema.dart';
import '../llm/llm_dispatcher.dart';
import '../llm/model_routes.dart';

extension GenerationTaskData on TaskItem {
  Map<String, dynamic> get generationOptions => generationTaskOptions(parameters);

  bool get generationSourceNeedsAlpha =>
      GenerationRequest.fromTask(parameters)?.operation == GenerationOperation.transparent ||
      generationOptions['imageTask'] == 'transparent';

  List<String> get generationImagePaths {
    final request = GenerationRequest.fromTask(parameters);
    return request == null ? imagePaths : [for (final media in request.media) media.path];
  }
}

Map<String, dynamic> snapshotGenerationTask({
  required LLMModel model,
  required LLMChannel channel,
  required TaskType type,
  required List<String> imagePaths,
  required Map<String, dynamic> options,
  String? profile,
}) {
  if (type != TaskType.imageProcess && type != TaskType.videoGenerate) return Map.of(options);
  if (GenerationRequest.fromTask(options) != null) return Map.of(options);
  final routed = RoutedChannel.forModel(channel, model);
  if (routed.missing) throw StateError('The generation route is no longer configured.');
  final schema = LLMDispatcher.generationSchemaFor(
    channelType: routed.channelType,
    modelId: model.modelId,
    tag: model.tag,
    wireProtocol: routed.wireProtocol,
    profile: profile,
  );
  final media = type == TaskType.videoGenerate
      ? <GenerationMedia>[
          if (options['firstFramePath'] case final String path)
            GenerationMedia(GenerationMediaRole.firstFrame, path),
          if (options['lastFramePath'] case final String path)
            GenerationMedia(GenerationMediaRole.lastFrame, path),
          for (final path in (options['referenceImagePaths'] as List?) ?? [])
            GenerationMedia(GenerationMediaRole.reference, path as String),
        ]
      : [for (final path in imagePaths) GenerationMedia(GenerationMediaRole.reference, path)];
  final draft = schema.readLegacy(options);
  final operation = schema.operation(draft, media);
  final values = schema.effective(draft, operation);
  final request = GenerationRequest(
    prompt: options['prompt'] as String? ?? '',
    operation: operation,
    values: values,
    media: media,
    modelId: model.modelId,
    modelRowId: model.id,
    channelRowId: channel.id,
    channelType: routed.channelType,
    protocolId: schema.protocol?.id,
    profileId: schema.profileId,
  );
  const mediaKeys = {'prompt', 'firstFramePath', 'lastFramePath', 'referenceImagePaths'};
  return {
    for (final entry in options.entries)
      if (!mediaKeys.contains(entry.key) && !schema.params.any((p) => p.key == entry.key))
        entry.key: entry.value,
    GenerationRequest.taskKey: request.toJson(),
  };
}
