import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/task_queue_service.dart';

void main() {
  group('TaskItem', () {
    test('toMap and fromMap should be consistent', () {
      final task = TaskItem(
        id: 'test-id',
        imagePaths: ['path1.png', 'path2.jpg'],
        modelId: 'gpt-4o',
        modelDbId: 1,
        channelTag: 'OpenAI',
        channelColor: 0xFF00FF00,
        parameters: {'prompt': 'hello', 'imagePrefix': 'test'},
        status: TaskStatus.processing,
        startTime: DateTime(2023, 1, 1, 10, 0),
        endTime: DateTime(2023, 1, 1, 10, 5),
      );

      final map = task.toMap();
      final decodedTask = TaskItem.fromMap(map);

      expect(decodedTask.id, task.id);
      expect(decodedTask.imagePaths, task.imagePaths);
      expect(decodedTask.modelId, task.modelId);
      expect(decodedTask.modelDbId, task.modelDbId);
      expect(decodedTask.channelTag, task.channelTag);
      expect(decodedTask.channelColor, task.channelColor);
      expect(decodedTask.status, task.status);
      expect(decodedTask.parameters, task.parameters);
      expect(decodedTask.startTime, task.startTime);
      expect(decodedTask.endTime, task.endTime);
    });

    test('addLog should add formatted message', () {
      final task = TaskItem(
        id: 'test-id',
        imagePaths: [],
        modelId: 'test-model',
        parameters: {},
      );

      task.addLog('Test message');
      expect(task.logs.length, 1);
      expect(task.logs.first, contains('Test message'));
      expect(task.logs.first, matches(r'\[\d{2}:\d{2}:\d{2}\] Test message'));
    });

    test('logs survive a toMap/fromMap round trip', () {
      final task = _bareTask();
      task.addLog('first');
      task.addLog('second');

      final decoded = TaskItem.fromMap(task.toMap());

      expect(decoded.logs, task.logs);
    });

    test('fromMap tolerates a missing or unreadable logs column', () {
      // Rows written before schema v31 have no `logs` value at all.
      final legacy = _bareTask().toMap()..remove('logs');
      expect(TaskItem.fromMap(legacy).logs, isEmpty);

      final corrupt = _bareTask().toMap()..['logs'] = '{not json';
      expect(TaskItem.fromMap(corrupt).logs, isEmpty);
    });

    test('addLog caps the log and flags the truncation', () {
      final task = _bareTask();
      for (var i = 0; i < TaskItem.maxLogLines + 50; i++) {
        task.addLog('line $i');
      }

      expect(task.logs.length, TaskItem.maxLogLines);
      // The marker is pinned at the head and not re-added on later trims, so a
      // truncated log always says so exactly once.
      expect(task.logs.first, TaskItem.logTruncationMarker);
      expect(task.logs.where((l) => l == TaskItem.logTruncationMarker).length, 1);
      // Newest lines are the ones kept.
      expect(task.logs.last, contains('line ${TaskItem.maxLogLines + 49}'));
      expect(task.logs.any((l) => l.contains('line 0')), isFalse);
    });
  });
}

TaskItem _bareTask() => TaskItem(
      id: 'test-id',
      imagePaths: [],
      modelId: 'test-model',
      parameters: {},
    );
