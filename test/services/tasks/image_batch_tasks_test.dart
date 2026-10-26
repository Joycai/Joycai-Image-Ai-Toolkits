import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/task_repository.dart';
import 'package:joycai_image_ai_toolkits/services/llm/image_batch_session.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_list_ordering.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/task_list_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

class _Remote extends ImageBatchSession {
  _Remote()
    : super(
        LLMTarget(
          config: LLMModelConfig(
            modelId: 'gpt-image-2',
            channelType: Vendors.openAIRest,
            endpoint: 'https://api.openai.com/v1',
            apiKey: 'secret',
          ),
          vendor: Vendors.byId(Vendors.openAIRest),
          model: ModelDescriptor.of('gpt-image-2'),
        ),
      );
  int submissions = 0;
  int inspections = 0;
  int cancellations = 0;
  String status = 'in_progress';
  String? customId;
  bool ambiguous = false;
  bool missingLine = false;
  bool includeOutput = false;
  Object? pollError;
  Completer<void>? pollGate;
  Map<String, dynamic> body = {
    'data': [
      {'b64_json': base64Encode(_png)},
    ],
    'usage': {
      'input_tokens': 30,
      'input_tokens_details': {'text_tokens': 10, 'image_tokens': 20},
      'output_tokens': 50,
    },
  };
  @override
  Future<String> upload(String id, Map<String, dynamic> body) async {
    customId = id;
    return 'file-input';
  }

  @override
  Future<Map<String, dynamic>> create(String file, String intent, bool edit) async {
    submissions++;
    if (ambiguous) throw const SocketException('response lost');
    return {'id': 'batch-1', 'status': status};
  }

  @override
  Future<Map<String, dynamic>?> reconcile(String intent, String file) async => {
    'id': 'batch-1',
    'status': status,
  };
  @override
  Future<Map<String, dynamic>> inspect(String id) async {
    inspections++;
    await pollGate?.future;
    if (pollError != null) throw pollError!;
    return {
      'id': id,
      'status': status,
      if (status == 'completed' || includeOutput) 'output_file_id': 'output',
    };
  }

  @override
  Future<Map<String, dynamic>> cancel(String id) async {
    cancellations++;
    status = 'cancelling';
    return {'id': id, 'status': status};
  }

  @override
  Future<Map<String, dynamic>?> resultLine(String file, String id) async => missingLine
      ? null
      : {
          'custom_id': id,
          'response': {'status_code': 200, 'body': body},
        };
}

Future<void> _until(bool Function() ready) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(end)) fail('State did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  sqfliteFfiInit();
  late DatabaseService db;
  late Directory dir;
  late _Remote remote;
  final queues = <TaskQueueService>[];
  setUp(() async {
    db = await openTestDatabase();
    dir = await Directory.systemTemp.createTemp('batch-test');
    remote = _Remote();
  });
  tearDown(() async {
    for (final q in queues) {
      q.dispose();
    }
    queues.clear();
    await closeTestDatabase(db);
    await dir.delete(recursive: true);
  });
  TaskQueueService queue() {
    final q = TaskQueueService(
      database: db,
      batchSessionFactory: (_) async => remote,
      batchPayloadBuilder: (_) async => {'model': 'gpt-image-2', 'prompt': 'frozen prompt'},
    );
    queues.add(q);
    return q;
  }

  Future<TaskItem> submit(TaskQueueService q) async {
    await q.addTask([], 'gpt-image-2', {
      'executionMode': 'batch',
      'outputDirectory': dir.path,
      'prompt': 'p',
    });
    await _until(() => q.queue.single.status == TaskStatus.awaitingRemote && q.runningCount == 0);
    return q.queue.single;
  }

  test('submit releases local concurrency, durable id survives restart without re-buy', () async {
    final first = queue();
    final task = await submit(first);
    expect(remote.submissions, 1);
    expect(first.runningCount, 0);
    expect(task.endTime, isNull);
    expect(task.batchState!['batchId'], 'batch-1');
    expect(jsonEncode(task.toMap()), isNot(contains('secret')));
    first.dispose();
    queues.remove(first);
    final second = queue();
    await second.resumePendingTasks();
    await second.refreshBatchTask(task.id);
    expect(remote.submissions, 1);
    expect(remote.inspections, 1);
    expect(second.queue.single.status, TaskStatus.awaitingRemote);
  });

  test('remote task is protected in queue and direct repository delete', () async {
    final q = queue();
    final task = await submit(q);
    await q.removeTask(task.id);
    await TaskRepository(db: db).deleteTask(task.id);
    expect(q.queue, hasLength(1));
    expect(await TaskRepository(db: db).getTask(task.id), isNotNull);
  });

  test('completed result saves once and settles exact official mixed input rates once', () async {
    final q = queue();
    final task = await submit(q);
    remote.status = 'completed';
    await Future.wait([q.refreshBatchTask(task.id), q.refreshBatchTask(task.id)]);
    expect(remote.inspections, 1);
    expect(task.status, TaskStatus.completed);
    expect(task.resultPaths, hasLength(1));
    expect(await File(task.resultPaths.single).readAsBytes(), _png);
    final usages = await db.getTokenUsage();
    expect(usages, hasLength(1));
    expect(usages.single.cost, closeTo((10 * 2.5 + 20 * 4 + 50 * 15) / 1000000, 1e-12));
    await q.refreshBatchTask(task.id);
    expect(await db.getTokenUsage(), hasLength(1));
    await q.removeTask(task.id);
    expect(q.queue, isEmpty);
    expect(await File(task.resultPaths.single).exists(), isTrue);
  });

  test('unknown create is reconciled, not resubmitted', () async {
    remote.ambiguous = true;
    final q = queue();
    final task = await submit(q);
    expect(task.batchState!['phase'], 'submitting');
    expect(task.canRemove, isFalse);
    await q.refreshBatchTask(task.id);
    expect(remote.submissions, 1);
    expect(task.batchState!['batchId'], 'batch-1');
  });

  test('cancel remains protected until remote terminal confirmation', () async {
    final q = queue();
    final task = await submit(q);
    await q.cancelTask(task.id);
    expect(remote.cancellations, 1);
    expect(task.canRemove, isFalse);
    expect(task.status, TaskStatus.awaitingRemote);
    remote.status = 'cancelled';
    await q.refreshBatchTask(task.id);
    expect(task.status, TaskStatus.cancelled);
    expect(task.canRemove, isTrue);
  });

  test('network failure does not become terminal or allow clearing', () async {
    final q = queue();
    final task = await submit(q);
    remote.pollError = const SocketException('offline');
    await q.refreshBatchTask(task.id);
    expect(task.status, TaskStatus.awaitingRemote);
    expect(task.canRemove, isFalse);
    expect(task.batchState!['failures'], 1);
    expect(remote.submissions, 1);
    remote.pollError = null;
    await q.refreshBatchTask(task.id);
    expect(task.batchState!['lastError'], isNull);
  });

  test('server retry-after applies even to manual refresh', () async {
    final q = queue();
    final task = await submit(q);
    remote.pollError = LLMApiException(
      'slow down',
      statusCode: 429,
      retryAfter: const Duration(minutes: 10),
    );
    await q.refreshBatchTask(task.id);
    await q.refreshBatchTask(task.id);
    expect(remote.inspections, 1);
    expect(task.canRemove, isFalse);
  });

  test('download failure retains remote id and retries same result', () async {
    final q = queue();
    final task = await submit(q);
    remote.status = 'completed';
    final body = remote.body;
    remote.body = {
      ...body,
      'data': [
        {'b64_json': 'broken'},
      ],
    };
    await q.refreshBatchTask(task.id);
    expect(task.status, TaskStatus.awaitingRemote);
    expect(task.resultPaths, isEmpty);
    remote.body = body;
    await q.refreshBatchTask(task.id);
    expect(task.status, TaskStatus.completed);
    expect(remote.submissions, 1);
  });

  test('missing usage keeps delivered image and permits later settlement', () async {
    final q = queue();
    final task = await submit(q);
    remote.status = 'completed';
    final body = remote.body;
    remote.body = {...body}..remove('usage');
    await q.refreshBatchTask(task.id);
    expect(task.resultPaths, hasLength(1));
    expect(task.canRemove, isFalse);
    expect(await db.getTokenUsage(), isEmpty);
    remote.body = body;
    await q.refreshBatchTask(task.id);
    expect(task.resultPaths, hasLength(1));
    expect(task.status, TaskStatus.completed);
  });

  test('startup recovers processing and active jobs outside history window', () async {
    final q = queue();
    final task = await submit(q);
    task.status = TaskStatus.processing;
    await db.saveTask(task);
    for (var i = 0; i < 205; i++) {
      await db.saveTask(
        TaskItem(
          id: 'history-$i',
          imagePaths: [],
          modelId: 'other',
          parameters: {},
          status: TaskStatus.completed,
        ),
      );
    }
    q.dispose();
    queues.remove(q);
    final restarted = queue();
    await restarted.resumePendingTasks();
    final loaded = restarted.queue.firstWhere((t) => t.id == task.id);
    expect(loaded.status, TaskStatus.awaitingRemote);
    await restarted.refreshBatchTask(task.id);
    expect(remote.submissions, 1);
  });

  test('automatic poll resumes overdue jobs without a screen', () async {
    final q = queue();
    final task = await submit(q);
    task.batchState!['nextPollAt'] = DateTime.now()
        .subtract(const Duration(minutes: 1))
        .toIso8601String();
    await db.saveTask(task);
    q.dispose();
    queues.remove(q);
    final restarted = queue();
    await restarted.resumePendingTasks();
    await _until(() => remote.inspections == 1 && !restarted.isBatchRefreshing(task.id));
    expect(remote.submissions, 1);
  });

  test('expired batch with uncollected output stays protected', () async {
    final q = queue();
    final task = await submit(q);
    remote.status = 'expired';
    remote.includeOutput = true;
    remote.missingLine = true;
    await q.refreshBatchTask(task.id);
    expect(task.canRemove, isFalse);
    expect(task.status, TaskStatus.awaitingRemote);
    remote.missingLine = false;
    await q.refreshBatchTask(task.id);
    expect(task.status, TaskStatus.completed);
    expect(remote.submissions, 1);
  });

  test('restart after usage persisted but before image save does not double bill', () async {
    final q = queue();
    final task = await submit(q);
    remote.status = 'completed';
    final original = remote.body;
    remote.body = {
      ...original,
      'data': [
        {'b64_json': 'broken'},
      ],
    };
    await q.refreshBatchTask(task.id);
    expect(await db.getTokenUsage(), hasLength(1));
    expect(task.resultPaths, isEmpty);
    q.dispose();
    queues.remove(q);
    remote.body = original;
    final recovered = queue();
    await recovered.resumePendingTasks();
    await recovered.refreshBatchTask(task.id);
    expect(recovered.queue.single.status, TaskStatus.completed);
    expect(await db.getTokenUsage(), hasLength(1));
    expect(remote.submissions, 1);
  });

  test('method filter intersects status and includes completed batch history', () async {
    final q = queue();
    final task = await submit(q);
    final state = TaskListState(database: db)..setModeFilter(TaskModeFilter.batch);
    expect(state.arrange(q.queue).pinned, [task]);
    state.setFilter(TaskFilter.done);
    expect(state.arrange(q.queue).isEmpty, isTrue);
    remote.status = 'completed';
    await q.refreshBatchTask(task.id);
    expect(state.arrange(q.queue).rest, [task]);
    state.dispose();
  });
}

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
