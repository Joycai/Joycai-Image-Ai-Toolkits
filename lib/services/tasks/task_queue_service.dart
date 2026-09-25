import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/file_utils.dart';
import '../../core/image_magic.dart';
import '../../core/video_magic.dart';
import '../../models/image_layer.dart';
import '../../models/llm_model.dart';
import '../../models/prompt.dart';
import '../../models/task_item.dart';
import '../assistant/knowledge_base_service.dart';
import '../assistant/prompt_optimizer_agent.dart';
import '../db/database_service.dart';
import '../db/repositories/cookie_repository.dart';
import '../db/repositories/image_layer_repository.dart';
import '../llm/image_compression.dart';
import '../llm/job_poll.dart';
import '../llm/llm_service.dart';
import '../llm/llm_types.dart';
import '../llm/model_descriptor.dart';
import '../llm/output_spec.dart' show reportedCostOf;
import '../media/web_scraper_service.dart';
import 'ai_rename_agent.dart';

// Re-export the task data model so existing importers of this file keep working.
export '../../models/task_item.dart';

part 'task_executors.dart';

class TaskQueueService extends ChangeNotifier {
  /// Never edited in place: every change goes through [_setQueue], so the
  /// list [queue] hands out is a snapshot and its identity moves with its
  /// content.
  List<TaskItem> _queue = const [];
  int _concurrencyLimit = 2;
  int _runningCount = 0;
  final _uuid = const Uuid();
  Timer? _progressTimer;
  List<LLMModel>? _cachedModelsForProgress;

  // Event stream for real-time subscriptions
  final _eventController = StreamController<TaskEvent>.broadcast();
  Stream<TaskEvent> get eventStream => _eventController.stream;
  late final Future<void> _loadFuture;
  bool _disposed = false;

  void _setQueue(Iterable<TaskItem> tasks) => _queue = List.unmodifiable(tasks);

  /// Every notification carries a new list, not only the ones that add or
  /// remove a task. A [TaskItem] is mutable, so when one starts, finishes or
  /// is cancelled the list's content has changed with nothing in the list to
  /// show for it — and list identity is the only signal a `select` has. A
  /// selector returning [queue], or a slice of it, would otherwise never
  /// rebuild, silently. The copy is one reference per task — a queue is as
  /// long as a user makes it, [reloadLimit] of them on launch — and the 500ms
  /// progress estimate does not come through here (see [progressTick]).
  void _notify() {
    if (_disposed) return;
    _setQueue(_queue);
    notifyListeners();
  }

  /// Ticks twice a second while anything is running, and carries nothing but
  /// the fact that the estimated progress written onto the running tasks has
  /// moved.
  ///
  /// Separate from [notifyListeners] because the two have different
  /// audiences. The queue's *shape* — what is in it, what state each task is
  /// in — changes when a task is added, started, finished or removed, and
  /// that is what the task screen draws. Progress is an estimate recomputed
  /// on a 500ms timer, and the only things that show it are the running
  /// cards' progress edges and the shell's capsule.
  ///
  /// Broadcasting the estimate through the notifier meant the whole task
  /// screen rebuilt twice a second for as long as anything ran — re-running
  /// the filter, the sort and the queue-position pass, and rebuilding every
  /// visible card, ~1000 widget builds a tick with seven tasks in the queue —
  /// to move a 3px bar on one of them.
  final ValueNotifier<int> progressTick = ValueNotifier<int>(0);

  /// Returns a stream of events filtered by a specific task ID
  Stream<TaskEvent> subscribeToTask(String taskId) {
    return eventStream.where((event) => event.taskId == taskId);
  }

  void _emit(String taskId, TaskEventType type, [dynamic data]) {
    if (_disposed) return;
    final task = _queue.cast<TaskItem?>().firstWhere(
      (t) => t?.id == taskId,
      orElse: () => null,
    );
    _eventController.add(
      TaskEvent(taskId: taskId, taskType: task?.type, type: type, data: data),
    );
  }

  Function(File)? onTaskCompleted;
  Function(TaskItem)? onTaskFinished;
  Function(String, {String level, String? taskId})? onLogAdded;

  /// The tasks, oldest first. Unmodifiable, and a new list on every
  /// notification — see [_notify].
  List<TaskItem> get queue => _queue;

  /// Puts [tasks] in the queue as they are: nothing is persisted, nothing is
  /// started. [addTask] would try to run them.
  @visibleForTesting
  void setQueueForTest(Iterable<TaskItem> tasks) {
    _setQueue(tasks);
    _notify();
  }

  /// Whether a Prompt Assistant turn of session [sessionId] is queued or
  /// running. Wider than the session's own `isRunning`, which only flips once
  /// the turn starts: a queued turn has already fixed the reference images it
  /// sends, in the order they had when it was added.
  bool hasLiveAssistantTurn(String sessionId) => _queue.any((t) =>
      t.type == TaskType.promptRefine &&
      t.parameters['sessionId'] == sessionId &&
      (t.status == TaskStatus.pending || t.status == TaskStatus.processing));
  int get concurrencyLimit => _concurrencyLimit;
  int get runningCount => _runningCount;

  TaskQueueService({DatabaseService? database})
    : _db = database ?? DatabaseService() {
    _loadFuture = _loadRecentTasks();
  }

  /// The database this queue and its executors read and write. Defaults to
  /// the app's one [DatabaseService]; [AppState] hands down its own, so the
  /// state layer has a single point where the database enters.
  final DatabaseService _db;

  /// How many tasks come back from the database on launch.
  ///
  /// Was 10, which made the history a window rather than a list: a session
  /// of a dozen generations lost its first two on the next launch. Rows are
  /// cheap to hold (the log is capped at [TaskItem.maxLogLines]); the list
  /// is a builder, so nothing is laid out until scrolled to.
  static const int reloadLimit = 200;

  Future<void> _loadRecentTasks() async {
    await _db.cleanupStuckTasks();
    final tasks = await _relabelled(await _db.getRecentTasks(reloadLimit));
    if (_disposed) return;
    // Newest-first from the query, reversed so the queue itself runs oldest
    // to newest — the order `_attemptNextExecution` walks it in, which is
    // what makes a task submitted earlier run earlier.
    _setQueue(tasks.reversed);
    _notify();
  }

  /// Starts pending work after the host has finished restoring application
  /// settings and providers. Keeping this explicit prevents constructors from
  /// opening network requests while a host is still wiring its dependency tree.
  Future<void> resumePendingTasks() async {
    await _loadFuture;
    if (_disposed) return;
    _attemptNextExecution();
  }

  /// Repairs titles that hold a model's row id instead of its name.
  ///
  /// Rows written before [addTask] resolved the name carry the primary key
  /// ("88") as their label, because the label was the identifier the caller
  /// passed stringified. The label is display-only — the executors route by
  /// `model_pk` — so the history is relabelled as it loads rather than
  /// migrated, and a task whose model has since been deleted keeps the id it
  /// was stored with.
  Future<List<TaskItem>> _relabelled(List<TaskItem> tasks) async {
    bool needsName(TaskItem task) =>
        task.modelDbId != null && task.modelId == task.modelDbId.toString();

    if (!tasks.any(needsName)) return tasks;
    final models = await _db.getModels();
    final names = {
      for (final m in models)
        if (m.id != null)
          m.id!: m.modelName.isNotEmpty ? m.modelName : m.modelId,
    };
    return [
      for (final task in tasks)
        if (needsName(task) && names[task.modelDbId] != null)
          task.withModelId(names[task.modelDbId]!)
        else
          task,
    ];
  }

  Future<void> addTask(
    List<String> imagePaths,
    dynamic modelIdentifier,
    Map<String, dynamic> params, {
    String? modelIdDisplay,
    TaskType type = TaskType.imageProcess,
    bool useStream = true,
    String? id,
  }) async {
    await _loadFuture;
    if (_disposed) return;
    // Display only: the executors route by [modelDbId]. Callers that pass the
    // row id and no display string used to label the task with the primary
    // key ("88") — the lookup below replaces it with the model's own name.
    String modelIdStr = modelIdDisplay ?? modelIdentifier.toString();
    int? modelDbId;
    String? channelTag;
    int? channelColor;


    if (modelIdentifier is int) {
      modelDbId = modelIdentifier;
      // Fetch model and channel info for visual continuity in history
      final models = await _db.getModels();
      final model = models.cast<LLMModel?>().firstWhere(
        (m) => m?.id == modelDbId,
        orElse: () => null,
      );
      if (model != null) {
        if (modelIdDisplay == null) {
          modelIdStr = model.modelName.isNotEmpty
              ? model.modelName
              : model.modelId;
        }
        final channelId = model.channelId;
        if (channelId != null) {
          final channel = await _db.getChannel(channelId);
          if (channel != null) {
            channelTag = channel.tag;
            channelColor = channel.tagColor;
          }
        }
      }
    }

    final task = TaskItem(
      id: id ?? _uuid.v4(),
      type: type,
      imagePaths: imagePaths,
      modelId: modelIdStr,
      modelDbId: modelDbId,
      channelTag: channelTag,
      channelColor: channelColor,
      parameters: params,
      useStream: useStream,
    );
    if (type == TaskType.imageProcess) {
      task.addLog(
        'Task created for ${imagePaths.length} images using $modelIdStr.',
      );
    } else if (type == TaskType.imageDownload) {
      task.addLog('Download task created for ${imagePaths.length} URLs.');
    } else if (type == TaskType.promptRefine) {
      task.addLog('Prompt refinement task created using $modelIdStr.');
    } else if (type == TaskType.aiRename) {
      task.addLog(
        'AI Batch Rename task created for ${imagePaths.length} files using $modelIdStr.',
      );
    } else if (type == TaskType.videoGenerate) {
      task.addLog('Video generation task created using $modelIdStr.');
    }

    _setQueue([..._queue, task]);

    // Persist task immediately
    await _db.saveTask(task);

    _notify();
    _attemptNextExecution();
  }

  Future<void> cancelTask(String taskId) async {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _queue[index];
      // Processing tasks are cancellable too: every executor checks
      // TaskStatus.cancelled at its loop/poll checkpoints (and passes an
      // isCancelled callback to the agents), and _executeTask's
      // `status != cancelled` guards already handle the finalization.
      // Without this, a running video task polls its LRO for up to 30
      // minutes with no way to stop it, holding a concurrency slot.
      if (task.status == TaskStatus.pending ||
          task.status == TaskStatus.processing) {
        task.status = TaskStatus.cancelled;
        task.addLog('Task cancelled by user.');
        _emit(task.id, TaskEventType.statusChanged, task.status);
        await _db.saveTask(task);
        _notify();
      }
    }
  }

  /// Whether [task] can pick its upstream job back up instead of submitting
  /// a new one: a video task that ended — failed, or cancelled — after its
  /// job was accepted (and billed). The poll gave up at its deadline, a poll
  /// failed three times running, the download broke, or the user stopped
  /// watching: in every case the video may exist upstream already, and a
  /// [retryTask] would pay for it again.
  static bool canResumeVideoJob(TaskItem task) =>
      task.type == TaskType.videoGenerate &&
      (task.operationName?.isNotEmpty ?? false) &&
      (task.status == TaskStatus.failed ||
          task.status == TaskStatus.cancelled);

  /// Re-queues a video task on its existing upstream job: the executor
  /// resumes polling it (with a fresh deadline) and downloads the result,
  /// submitting nothing. See [canResumeVideoJob].
  Future<void> resumeVideoJob(String taskId) async {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = _queue[index];
    if (!canResumeVideoJob(task)) return;
    task.addLog('Resuming upstream job ${task.operationName}; no new job is '
        'submitted.');
    await _requeue(task);
  }

  /// Re-queues a failed or cancelled task for another attempt.
  Future<void> retryTask(String taskId) async {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = _queue[index];
    if (task.status != TaskStatus.failed &&
        task.status != TaskStatus.cancelled) {
      return;
    }
    // A retry is a request for a fresh attempt, so a video task forgets its
    // upstream job and submits a new one. Only an interrupted run resumes
    // its job (see TaskRepository.cleanupStuckTasks), or the user asking for
    // exactly that ([resumeVideoJob]).
    if (task.operationName != null) {
      task.addLog(
        'Previous upstream job ${task.operationName} is not reused; a new job '
        'will be submitted.',
      );
      task.operationName = null;
      task.operationSurface = null;
    }
    await _requeue(task);
  }

  Future<void> _requeue(TaskItem task) async {
    task.status = TaskStatus.pending;
    task.progress = null;
    task.startTime = null;
    task.endTime = null;
    task.addLog('Task re-queued by user.');
    await _db.saveTask(task);
    _notify();
    _attemptNextExecution();
  }

  /// Removes a finished task — completed, failed or cancelled — from the
  /// queue and deletes its row.
  ///
  /// A waiting or running task is left alone, row included. The row used to be
  /// deleted unconditionally while the in-memory guard kept the task queued,
  /// so "Clear All" on a queue with waiting tasks silently dropped their rows:
  /// they vanished on the next launch, and every later save of their progress
  /// wrote back into a table that no longer had them.
  ///
  /// An id that is not in the queue at all only has its row deleted — a stale
  /// row is still worth clearing.
  Future<void> removeTask(String taskId) async {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final status = _queue[index].status;
      final finished =
          status == TaskStatus.completed ||
          status == TaskStatus.failed ||
          status == TaskStatus.cancelled;
      if (!finished) return;
      _setQueue([..._queue]..removeAt(index));
    }
    await _db.deleteTask(taskId);
    _notify();
  }

  void updateConcurrency(int newLimit) {
    _concurrencyLimit = newLimit;
    _notify();
    _attemptNextExecution();
  }

  void refreshQueue() {
    _notify();
  }

  void _attemptNextExecution() {
    if (_disposed || _runningCount >= _concurrencyLimit) return;

    try {
      final nextTask = _queue.firstWhere(
        (task) => task.status == TaskStatus.pending,
      );

      _runningCount++;
      _startProgressTimer();
      _executeTask(nextTask);
      _attemptNextExecution();
    } catch (e) {
      // No pending tasks
    }
  }

  Future<void> _executeTask(TaskItem task) async {
    if (task.status == TaskStatus.cancelled) {
      _runningCount--;
      _attemptNextExecution();
      return;
    }

    task.status = TaskStatus.processing;
    task.startTime = DateTime.now();
    _emit(task.id, TaskEventType.statusChanged, task.status);
    onLogAdded?.call(
      'Processing task ${task.id.substring(0, 8)}...',
      level: 'RUNNING',
      taskId: task.id,
    );
    unawaited(_db.saveTask(task));
    _notify();

    try {
      if (task.type == TaskType.imageProcess) {
        await _executeImageProcessTask(task);
      } else if (task.type == TaskType.imageDownload) {
        await _executeDownloadTask(task);
      } else if (task.type == TaskType.promptRefine) {
        await _executePromptRefineTask(task);
      } else if (task.type == TaskType.aiRename) {
        await _executeAiRenameTask(task);
      } else if (task.type == TaskType.videoGenerate) {
        await _executeVideoGenerateTask(task);
      }

      if (task.status != TaskStatus.cancelled) {
        task.status = TaskStatus.completed;
        _emit(task.id, TaskEventType.statusChanged, task.status);
        task.addLog('Task completed successfully.');
        onLogAdded?.call(
          'Task ${task.id.substring(0, 8)} finished.',
          level: 'SUCCESS',
          taskId: task.id,
        );
      }
    } catch (e) {
      if (task.status != TaskStatus.cancelled) {
        task.status = TaskStatus.failed;
        _emit(task.id, TaskEventType.statusChanged, task.status);
        _emit(task.id, TaskEventType.error, e.toString());
        task.addLog('Error: ${e.toString()}');
        onLogAdded?.call(
          'Task ${task.id.substring(0, 8)} failed: $e',
          level: 'ERROR',
          taskId: task.id,
        );
      }
    } finally {
      task.endTime = DateTime.now();

      // Update Estimation Checkpoint
      if (task.status == TaskStatus.completed && task.modelDbId != null) {
        unawaited(_handleEstimationCheckpoint(task.modelDbId!));
      }

      _runningCount--;
      unawaited(_db.saveTask(task));
      onTaskFinished?.call(task);
      _notify();
      _attemptNextExecution();
    }
  }

  Future<void> _handleEstimationCheckpoint(int modelDbId) async {
    final models = await _db.getModels();
    final model = models.cast<LLMModel?>().firstWhere(
      (m) => m?.id == modelDbId,
      orElse: () => null,
    );

    if (model != null) {
      final int count = model.tasksSinceUpdate + 1;
      final mean = model.estMeanMs ?? 0.0;

      if (count >= 10 || mean == 0) {
        await _updateModelCheckpoint(modelDbId);
      } else {
        await _db.updateModelEstimation(
          modelDbId,
          mean,
          model.estSdMs ?? 0.0,
          count,
        );
      }
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _cachedModelsForProgress = null;
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _updateProgress(),
    );
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _cachedModelsForProgress = null;
  }

  Future<void> _updateProgress() async {
    bool hasActive = false;
    _cachedModelsForProgress ??= await _db.getModels();
    final models = _cachedModelsForProgress!;

    for (final task in _queue) {
      if (task.status == TaskStatus.processing && task.startTime != null) {
        hasActive = true;
        // Find checkpoint for this model
        final model = models.cast<LLMModel?>().firstWhere(
          (m) => m?.id == task.modelDbId,
          orElse: () => null,
        );

        if (model != null) {
          final mean = model.estMeanMs ?? 0.0;
          final sd = model.estSdMs ?? 0.0;

          if (mean > 0) {
            final targetMs = mean + (2 * sd);
            final elapsed = DateTime.now()
                .difference(task.startTime!)
                .inMilliseconds;
            task.progress = math.min(elapsed / targetMs, 0.99);
          }
        }
      }
    }

    if (hasActive) {
      if (!_disposed) progressTick.value++;
    } else {
      _stopProgressTimer();
    }
  }

  Future<void> _updateModelCheckpoint(int modelDbId) async {
    final durations = await _db.getTaskDurations(modelDbId, 50);

    if (durations.length >= 3) {
      // Calculate Mean
      final mean = durations.reduce((a, b) => a + b) / durations.length;
      // Calculate Standard Deviation
      final variance =
          durations.map((d) => math.pow(d - mean, 2)).reduce((a, b) => a + b) /
          durations.length;
      final sd = math.sqrt(variance);

      await _db.updateModelEstimation(modelDbId, mean, sd, 0);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    _eventController.close();
    progressTick.dispose();
    super.dispose();
  }
}
