import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/files/persistent_media_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_media_snapshot.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'authoritative generation media and prepared images are copied without mutating JSON',
    () async {
      final root = await Directory.systemTemp.createTemp('generation-media-test-');
      addTearDown(() => root.delete(recursive: true));
      final source = await File(p.join(root.path, 'mask.png')).writeAsString('mask');
      final storage = PersistentMediaService(
        dataDirectory: () async => p.join(root.path, 'private'),
      );
      final generation = <String, dynamic>{
        'version': 1,
        'schemaVersion': 1,
        'prompt': 'test',
        'operation': 'editImage',
        'values': <String, dynamic>{},
        'media': [
          {'role': 'source', 'path': source.path},
        ],
        'modelId': 'model',
        'channelType': 'openai',
        'protocolId': null,
        'profileId': 'test',
      };
      final staged = await snapshotTaskMedia(
        [],
        {'generation': generation},
        TaskType.imageProcess,
        storage: storage,
      );
      final newPath =
          ((staged.parameters['generation'] as Map)['media'] as List).single['path'] as String;
      expect((generation['media'] as List).single['path'], source.path);
      await source.delete();
      expect(await File(newPath).readAsString(), 'mask');
    },
  );

  test('queued media owns a copy without mutating the draft; renames keep originals', () async {
    final root = await Directory.systemTemp.createTemp('task-media-test-');
    addTearDown(() => root.delete(recursive: true));
    final storage = PersistentMediaService(dataDirectory: () async => p.join(root.path, 'private'));
    final source = await File(p.join(root.path, 'frame.png')).writeAsString('frame');
    final draft = <String, dynamic>{
      'firstFramePath': source.path,
      'referenceImagePaths': [source.path],
    };
    final staged = await snapshotTaskMedia(
      [source.path],
      draft,
      TaskType.videoGenerate,
      storage: storage,
    );
    expect(draft['firstFramePath'], source.path);
    expect(staged.images.single, isNot(source.path));
    expect(staged.parameters['firstFramePath'], staged.images.single);
    expect(staged.parameters['referenceImagePaths'], [staged.images.single]);
    final renamed = await snapshotTaskMedia(
      [source.path],
      draft,
      TaskType.aiRename,
      storage: storage,
    );
    expect(renamed.images, [source.path]);
    await source.delete();
    final task = TaskItem(
      id: 'saved',
      imagePaths: staged.images,
      modelId: 'model',
      parameters: staged.parameters,
    );
    final restored = TaskItem.fromMap(task.toMap());
    expect(await File(restored.imagePaths.single).readAsString(), 'frame');
  });
}
