import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// What the task queue labels a task with.
///
/// The bug this pins: `addTask` takes either a legacy model-id string or the
/// model's row id, and derived the label with `toString()`. Callers that pass
/// the row id and no display string — the prompt assistant, the AI rename
/// dialog, the downloader — therefore titled their cards with the primary key
/// ("88") instead of the model's name.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_task_label_test');

  Future<int> addModel({required String modelId, required String modelName}) =>
      DatabaseService().addModel({
        'model_id': modelId,
        'model_name': modelName,
        'tag': 'chat',
      });

  Future<void> storeTask(String id, {required String modelId, int? modelDbId}) =>
      DatabaseService().saveTask(TaskItem(
        id: id,
        imagePaths: const <String>[],
        modelId: modelId,
        modelDbId: modelDbId,
        parameters: const <String, dynamic>{},
        status: TaskStatus.completed,
      ).toMap());

  /// A service that has finished loading [holding]'s row, and runs nothing:
  /// the queue is what is under test, not the executors.
  Future<TaskQueueService> serviceHolding(String holding) async {
    final service = TaskQueueService();
    for (var i = 0; i < 200 && !service.queue.any((t) => t.id == holding); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(service.queue.any((t) => t.id == holding), isTrue,
        reason: 'the service never finished loading its rows');
    service.updateConcurrency(0);
    return service;
  }

  /// A loaded, idle service, seeded with a row of its own so the load has
  /// something to be waited on.
  Future<TaskQueueService> idleService() async {
    const sentinel = 'loaded-sentinel';
    await storeTask(sentinel, modelId: 'seed');
    return serviceHolding(sentinel);
  }

  TaskItem added(TaskQueueService service, String id) =>
      service.queue.firstWhere((t) => t.id == id);

  test('a task queued by row id is labelled with the model name', () async {
    final dbId = await addModel(modelId: 'gemini-3.5-flash', modelName: 'Gemini 3.5 Flash');
    final service = await idleService();

    await service.addTask(const <String>[], dbId, const <String, dynamic>{},
        type: TaskType.promptRefine, useStream: false, id: 'refine-1');

    final task = added(service, 'refine-1');
    expect(task.modelId, 'Gemini 3.5 Flash',
        reason: 'the card would show the primary key instead of the name');
    expect(task.modelDbId, dbId, reason: 'routing still goes by the row id');
  });

  test('a model with no name falls back to its model id', () async {
    final dbId = await addModel(modelId: 'qwen-image-edit', modelName: '');
    final service = await idleService();

    await service.addTask(const <String>[], dbId, const <String, dynamic>{},
        type: TaskType.promptRefine, useStream: false, id: 'refine-2');

    expect(added(service, 'refine-2').modelId, 'qwen-image-edit');
  });

  test('history stored with the row id as its title is relabelled on load', () async {
    final dbId = await addModel(modelId: 'veo-4.0', modelName: 'Veo 4');
    await storeTask('legacy-1', modelId: '$dbId', modelDbId: dbId);

    final service = await serviceHolding('legacy-1');

    expect(added(service, 'legacy-1').modelId, 'Veo 4',
        reason: 'tasks queued before the fix keep showing the primary key');
  });

  test('a title that is not the row id is left alone', () async {
    final dbId = await addModel(modelId: 'gpt-image-3', modelName: 'GPT Image 3');
    await storeTask('kept-1', modelId: 'my own label', modelDbId: dbId);

    final service = await serviceHolding('kept-1');

    expect(added(service, 'kept-1').modelId, 'my own label');
  });

  test('an explicit display string still wins', () async {
    final dbId = await addModel(modelId: 'gpt-image-2', modelName: 'GPT Image 2');
    final service = await idleService();

    await service.addTask(const <String>[], dbId, const <String, dynamic>{},
        modelIdDisplay: '[R]gpt-image-2', id: 'image-1');

    expect(added(service, 'image-1').modelId, '[R]gpt-image-2');
  });
}
