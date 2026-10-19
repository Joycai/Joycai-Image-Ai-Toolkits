import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/system/dock_badge_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('joycai/dock_badge');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DatabaseService database;
  late TaskQueueService queue;
  late List<int> counts;

  TaskItem task(String id, TaskStatus status) =>
      TaskItem(id: id, imagePaths: const [], modelId: 'test', parameters: const {}, status: status);

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    database = await openTestDatabase();
    queue = TaskQueueService(database: database);
    await queue.resumePendingTasks();
    counts = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setCount');
      counts.add(call.arguments as int);
      return null;
    });
  });

  tearDown(() async {
    queue.dispose();
    await closeTestDatabase(database);
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('counts processing tasks, deduplicates updates and clears when finished', () async {
    queue.setQueueForTest([
      task('running', TaskStatus.processing),
      task('waiting', TaskStatus.pending),
      task('done', TaskStatus.completed),
      task('failed', TaskStatus.failed),
      task('cancelled', TaskStatus.cancelled),
    ]);
    final badge = DockBadgeService(queue);
    queue.setQueueForTest(queue.queue);
    queue.setQueueForTest([...queue.queue, task('second', TaskStatus.processing)]);
    // Cancellation changes the badge immediately, before the executor unwinds.
    queue.queue.first.status = TaskStatus.cancelled;
    queue.setQueueForTest(queue.queue);
    queue.setQueueForTest([task('second', TaskStatus.completed)]);
    await Future<void>.delayed(Duration.zero);
    expect(counts, [1, 2, 1, 0]);
    badge.dispose();
  });

  test('clears stale badges on startup and detaches on disposal', () async {
    final badge = DockBadgeService(queue);
    queue.setQueueForTest([task('running', TaskStatus.processing)]);
    badge.dispose();
    queue.setQueueForTest([task('other', TaskStatus.processing)]);
    await Future<void>.delayed(Duration.zero);
    expect(counts, [0, 1, 0]);
  });

  test('does not call native code on other platforms', () async {
    for (final platform in TargetPlatform.values.where((p) => p != TargetPlatform.macOS)) {
      debugDefaultTargetPlatformOverride = platform;
      final badge = DockBadgeService(queue);
      queue.setQueueForTest([task(platform.name, TaskStatus.processing)]);
      badge.dispose();
    }
    await Future<void>.delayed(Duration.zero);
    expect(counts, isEmpty);
  });

  test('missing native channel does not interrupt queue updates', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final badge = DockBadgeService(queue);
    queue.setQueueForTest([task('running', TaskStatus.processing)]);
    badge.dispose();
    await Future<void>.delayed(Duration.zero);
  });
}
