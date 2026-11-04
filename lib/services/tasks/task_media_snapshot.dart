import '../../models/task_item.dart';
import '../files/persistent_media_service.dart';
import '../llm/generation/generation_request.dart';

/// Rewrite every authoritative/legacy media path together, never the caller's
/// mutable draft. Rename tasks must keep their originals; download inputs are URLs.
Future<({List<String> images, Map<String, dynamic> parameters})> snapshotTaskMedia(
  List<String> images,
  Map<String, dynamic> parameters,
  TaskType type, {
  PersistentMediaService? storage,
}) async {
  if (type == TaskType.aiRename || type == TaskType.imageDownload) {
    return (images: List.of(images), parameters: Map.of(parameters));
  }
  const singles = ['firstFramePath', 'lastFramePath'];
  const lists = ['referenceImagePaths', 'referenceVideoPaths', 'referenceAudioPaths'];
  final generation = GenerationRequest.fromTask(parameters)?.toJson();
  final paths = <String>[
    ...images,
    for (final key in singles)
      if (parameters[key] case final String value) value,
    for (final key in lists) ...((parameters[key] as List?)?.cast<String>() ?? <String>[]),
    if (generation != null)
      for (final media in generation['media'] as List) media['path'] as String,
  ];
  final copies = await (storage ?? PersistentMediaService.instance).snapshot(paths);
  String copy(String path) => copies[path] ?? path;
  final result = Map<String, dynamic>.of(parameters);
  result['_privateMediaVersion'] = 1;
  for (final key in singles) {
    if (result[key] case final String value) result[key] = copy(value);
  }
  for (final key in lists) {
    if (result[key] case final List values) result[key] = values.cast<String>().map(copy).toList();
  }
  if (generation != null) {
    generation['media'] = [
      for (final media in generation['media'] as List)
        {...media as Map, 'path': copy(media['path'] as String)},
    ];
    result[GenerationRequest.taskKey] = generation;
  }
  return (images: images.map(copy).toList(), parameters: result);
}
