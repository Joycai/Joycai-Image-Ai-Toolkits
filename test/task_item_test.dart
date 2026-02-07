import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/task_queue_service.dart';

void main() {
  group('TaskItem', () {
    test('toMap and fromMap should be consistent', () {
      final task = TaskItem(
        id: 'test-id',
        imagePaths: ['path1.png', 'path2.jpg'],
        modelId: 'gpt-4o',
        modelPk: 1,
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
      expect(decodedTask.modelPk, task.modelPk);
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
  });
}
