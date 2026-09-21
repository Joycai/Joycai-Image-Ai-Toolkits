// A `select` only sees a list change when the list is a new instance — the
// project rule is "new list before notifyListeners()". These pin it for the
// state methods that once mutated in place.

import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/downloader_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';

import 'support/in_memory_database.dart';

void main() {
  // The task queue is a service, not a state class, but it is a notifier the
  // shell `select`s on — and its tasks are mutable, so a change of status
  // leaves nothing in the list to compare. Every notification has to carry a
  // new list.
  group('the task queue hands out a new list with every notification', () {
    late DatabaseService db;
    late TaskQueueService service;

    setUp(() async {
      db = await openTestDatabase();
      service = TaskQueueService(database: db);
      await service.resumePendingTasks();
      // Nothing may start: a task that ran would notify on its own.
      service.updateConcurrency(0);
    });
    tearDown(() async {
      service.dispose();
      await closeTestDatabase(db);
    });

    Future<String> add() async {
      await service.addTask(const [], 'm', const {'prompt': 'p'});
      return service.queue.last.id;
    }

    test('when a task is added or removed', () async {
      final empty = service.queue;
      final id = await add();
      final one = service.queue;
      expect(identical(empty, one), isFalse);
      expect(empty, isEmpty, reason: 'the old list must not be touched');

      await service.cancelTask(id);
      final cancelled = service.queue;
      await service.removeTask(id);
      expect(identical(cancelled, service.queue), isFalse);
      expect(cancelled.map((t) => t.id), [id], reason: 'the old list must not be touched');
      expect(service.queue, isEmpty);
    });

    test('when a task only changes status', () async {
      final id = await add();
      final pending = service.queue;
      var notified = 0;
      service.addListener(() => notified++);

      await service.cancelTask(id);

      expect(notified, 1);
      expect(service.queue.single.status, TaskStatus.cancelled);
      expect(identical(pending, service.queue), isFalse);
    });

    test('and nobody else can edit it', () async {
      await add();
      expect(() => service.queue.clear(), throwsUnsupportedError);
      expect(() => service.queue.add(service.queue.single), throwsUnsupportedError);
    });
  });

  test('video reference images get a new list on add and remove', () {
    final ui = WorkbenchUIState();
    final a = AppImage(path: '/a.png', name: 'a.png');
    final b = AppImage(path: '/b.png', name: 'b.png');

    final before = ui.videoReferenceImages;
    ui.addVideoReferenceImage(a);
    expect(identical(before, ui.videoReferenceImages), isFalse);
    expect(before, isEmpty, reason: 'the old list must not be touched');

    ui.addVideoReferenceImage(b);
    final twoItems = ui.videoReferenceImages;
    ui.removeVideoReferenceImage(a);
    expect(identical(twoItems, ui.videoReferenceImages), isFalse);
    expect(twoItems.map((i) => i.path), ['/a.png', '/b.png']);
    expect(ui.videoReferenceImages.map((i) => i.path), ['/b.png']);
  });

  test('a no-op add or remove keeps the list and stays silent', () {
    final ui = WorkbenchUIState();
    final a = AppImage(path: '/a.png', name: 'a.png');
    ui.addVideoReferenceImage(a);
    final list = ui.videoReferenceImages;
    var notified = 0;
    ui.addListener(() => notified++);

    ui.addVideoReferenceImage(a);
    ui.removeVideoReferenceImage(AppImage(path: '/x.png', name: 'x'));
    expect(identical(list, ui.videoReferenceImages), isTrue);
    expect(notified, 0);
  });

  test('downloader logs get a new list on add and reset', () {
    final state = DownloaderState();
    final before = state.logs;
    state.addLog('hello');
    expect(identical(before, state.logs), isFalse);
    expect(before, isEmpty);

    final withLine = state.logs;
    state.reset();
    expect(identical(withLine, state.logs), isFalse);
    expect(withLine, hasLength(1));
  });
}
