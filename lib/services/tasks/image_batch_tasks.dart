part of 'task_queue_service.dart';

/// Batch checkpoints live on the task row, so status + provenance commit
/// atomically and existing full backups carry them without a second-table join.
extension ImageBatchTasks on TaskQueueService {
  Future<ImageBatchSession> _batchSession(TaskItem task) =>
      batchSessionFactory?.call(task) ??
      _llm.imageBatchSession(task.modelDbId ?? task.modelId, snapshot: task.batchState);

  Future<void> _prepareBatchTask(TaskItem task) async {
    final session = batchSessionFactory != null
        ? await batchSessionFactory!(task)
        : await _llm.imageBatchSession(task.modelDbId ?? task.modelId);
    final payload = batchPayloadBuilder != null
        ? await batchPayloadBuilder!(task)
        : await _llm.prepareImageBatch(task.modelDbId ?? task.modelId, [
            LLMMessage(
              role: LLMRole.user,
              content: task.generationOptions['prompt'] ?? '',
              attachments: await Future.wait(
                task.generationImagePaths.map((p) => _buildReferenceAttachment(task, p)),
              ),
            ),
          ], task.parameters);
    final output = await _getEffectiveOutputDir(task);
    // Frozen input survives edits/deletion of the user's source files.
    final directory = Directory(p.join(output, '.joycai-batch', task.id));
    await directory.create(recursive: true);
    final input = File(p.join(directory.path, 'input.json'));
    await input.writeAsString(jsonEncode(payload), flush: true);
    task.batchState = {
      ...session.snapshot,
      'intent': _uuid.v4(),
      'customId': task.id,
      'inputPath': input.path,
      'outputDir': output,
      'isEdit': payload.containsKey('images'),
      'inputs': (payload['images'] as List?)?.length ?? 0,
      'phase': 'prepared',
      'polls': 0,
      'settled': false,
    };
  }

  Future<void> _submitBatchTask(TaskItem task) async {
    final state = task.batchState!;
    final session = await _batchSession(task);
    // A bounded creation rate even when local concurrency is very high.
    final last = _lastBatchSubmit;
    _lastBatchSubmit = (last != null && last.isAfter(DateTime.now()) ? last : DateTime.now()).add(
      const Duration(seconds: 2),
    );
    if (last != null && last.isAfter(DateTime.now())) {
      await Future<void>.delayed(last.difference(DateTime.now()));
    }
    if (_disposed || state['cancelRequested'] == true) {
      if (!_disposed) await _finishBatch(task, TaskStatus.cancelled);
      return;
    }
    final payload = Map<String, dynamic>.from(
      jsonDecode(await File(state['inputPath'] as String).readAsString()) as Map,
    );
    state['phase'] = 'uploading';
    await _db.saveTask(task);
    state['inputFileId'] = await session.upload(state['customId'] as String, payload);
    state['phase'] = 'uploaded';
    await _db.saveTask(task);
    if (_disposed) return;
    if (state['cancelRequested'] == true) {
      await _finishBatch(task, TaskStatus.cancelled);
      return;
    }
    state['phase'] = 'submitting';
    state['submittedAt'] = DateTime.now().toUtc().toIso8601String();
    await _db.saveTask(task);
    // No catch/retry here. Ambiguous create is recovered through reconcile.
    final remote = await session.create(
      state['inputFileId'] as String,
      state['intent'] as String,
      state['isEdit'] == true,
    );
    _applyBatchRemote(task, remote);
    task.status = TaskStatus.awaitingRemote;
    state['nextPollAt'] = DateTime.now().add(const Duration(seconds: 30)).toUtc().toIso8601String();
    await _db.saveTask(task);
    if (state['cancelRequested'] == true) unawaited(refreshBatchTask(task.id));
  }

  void _applyBatchRemote(TaskItem task, Map<String, dynamic> remote) {
    final state = task.batchState!;
    if (remote['id'] is! String || (remote['id'] as String).isEmpty) {
      throw LLMApiException('Batch response has no ID.');
    }
    state['batchId'] = remote['id'];
    state['remoteStatus'] = remote['status'];
    for (final key in ['output_file_id', 'error_file_id', 'expires_at']) {
      if (remote[key] != null) state[key] = remote[key];
    }
    state['phase'] = 'remote';
    state['lastSuccessfulCheckAt'] = DateTime.now().toUtc().toIso8601String();
  }

  bool isBatchRefreshing(String id) => _batchRefreshes.containsKey(id);

  Future<void> refreshBatchTask(String id) {
    if (_batchRefreshes[id] case final Future<void> existing) return existing;
    final task = _queue.where((t) => t.id == id).firstOrNull;
    if (_disposed || task == null || !task.canRefresh) return Future.value();
    // Put the future into the map before the async work can notify listeners.
    final future = _batchSerial.then((_) async {
      if (!_disposed && task.canRefresh) await _refreshBatch(task);
    });
    _batchSerial = future.catchError((Object error) {
      onLogAdded?.call('Batch checkpoint failed: $error', level: 'ERROR', taskId: task.id);
    });
    _batchRefreshes[id] = future;
    _notify();
    return future.whenComplete(() {
      _batchRefreshes.remove(id);
      _notify();
      _scheduleBatchPoll();
    });
  }

  Future<void> refreshBatchTasks() async {
    for (final task in List.of(_queue)) {
      if (_disposed) return;
      if (task.canRefresh) await refreshBatchTask(task.id);
    }
  }

  void _scheduleBatchPoll() {
    _batchTimer?.cancel();
    if (_disposed) return;
    DateTime? next;
    for (final task in _queue) {
      if (!task.canRefresh || task.batchState?['paused'] == true || isBatchRefreshing(task.id)) {
        continue;
      }
      final due =
          DateTime.tryParse(task.batchState?['nextPollAt'] as String? ?? '') ?? DateTime.now();
      if (next == null || due.isBefore(next)) next = due;
    }
    if (next == null) return;
    final delay = next.difference(DateTime.now());
    _batchTimer = Timer(delay.isNegative ? Duration.zero : delay, () async {
      for (final task in List.of(_queue)) {
        if (_disposed) return;
        final state = task.batchState;
        final due = DateTime.tryParse(state?['nextPollAt'] as String? ?? '') ?? DateTime.now();
        if (task.canRefresh && state?['paused'] != true && !due.isAfter(DateTime.now())) {
          await refreshBatchTask(task.id);
        }
      }
      _scheduleBatchPoll();
    });
  }

  Future<void> _refreshBatch(TaskItem task) async {
    final state = task.batchState;
    if (state == null) return;
    final notBefore = DateTime.tryParse(state['notBefore'] as String? ?? '');
    if (notBefore != null && DateTime.now().isBefore(notBefore)) return;
    try {
      final session = await _batchSession(task);
      state['paused'] = false;
      state['lastCheckedAt'] = DateTime.now().toUtc().toIso8601String();
      if (state['batchId'] == null) {
        if (state['phase'] == 'submitting') {
          final match = await session.reconcile(
            state['intent'] as String,
            state['inputFileId'] as String,
          );
          if (match == null) {
            throw LLMApiException('Submission outcome unknown. No new generation was submitted.');
          }
          _applyBatchRemote(task, match);
        } else {
          // Before create, it is safe to resume upload/submission (an orphan
          // input file is not an image generation).
          task.status = TaskStatus.processing;
          await _submitBatchTask(task);
          return;
        }
      }
      if (_disposed) return;
      if (state['cancelRequested'] == true && state['cancelSent'] != true) {
        await session.cancel(state['batchId'] as String);
        state['cancelSent'] = true;
        await _db.saveTask(task);
      }
      final remote = await session.inspect(state['batchId'] as String);
      _applyBatchRemote(task, remote);
      await _db.saveTask(task); // retain result file IDs before any download
      final status = state['remoteStatus'];
      if (const ['completed', 'failed', 'expired', 'cancelled'].contains(status)) {
        state['phase'] = 'retrieving';
        await _db.saveTask(task);
        Map<String, dynamic>? line;
        for (final key in ['output_file_id', 'error_file_id']) {
          if (state[key] is String) {
            line ??= await session.resultLine(state[key] as String, state['customId'] as String);
          }
        }
        final response = line?['response'];
        if (response is Map && response['status_code'] == 200 && response['body'] is Map) {
          final body = Map<String, dynamic>.from(response['body'] as Map);
          state['usageBody'] = {if (body['usage'] != null) 'usage': body['usage']};
          await _db.saveTask(task);
          Object? settlementError;
          if (state['usageSettled'] != true) {
            try {
              await ImageBatchSession.settle(_db, task.id, task.modelDbId, state, body);
              state['usageSettled'] = true;
              await _db.saveTask(task);
            } catch (error) {
              settlementError = error;
            }
          }
          if (task.resultPaths.isEmpty) {
            final result = await session.decodeResult(body, state['inputs'] as int? ?? 0);
            if (result.generatedImages.length != 1) {
              throw LLMApiException('Batch expected exactly one generated image.');
            }
            for (final (i, bytes) in result.generatedImages.indexed) {
              final file = File(
                p.join(
                  state['outputDir'] as String,
                  'batch_${task.id}_$i${imageExtensionFromBytes(bytes)}',
                ),
              );
              if (await file.exists()) {
                final saved = await file.readAsBytes();
                if (!listEquals(saved, bytes)) {
                  throw LLMApiException('Batch output path contains a different file.');
                }
              } else {
                final tmp = File('${file.path}.partial');
                await tmp.writeAsBytes(bytes, flush: true);
                await tmp.rename(file.path);
              }
              task.resultPaths = [...task.resultPaths, file.path];
              await _db.saveTask(task);
              _emit(task.id, TaskEventType.imageResult, file.path);
              onTaskCompleted?.call(file);
              await saveGenerationResultText(task, file.path);
            }
          }
          state['phase'] = 'settling';
          await _db.saveTask(task);
          if (settlementError != null) throw settlementError;
          await _finishBatch(task, TaskStatus.completed);
        } else {
          if (line == null &&
              (status == 'completed' ||
                  state['output_file_id'] != null ||
                  state['error_file_id'] != null)) {
            throw LLMApiException('Terminal batch has no matching result yet.');
          }
          task.error = {
            'code': 'batch_$status',
            'message': '${line?['error'] ?? response ?? remote['errors'] ?? status}',
          };
          await _finishBatch(
            task,
            status == 'cancelled' ? TaskStatus.cancelled : TaskStatus.failed,
          );
        }
      }
      state.remove('lastError');
      state['failures'] = 0;
    } catch (e) {
      if (!task.isTerminal) task.status = TaskStatus.awaitingRemote;
      state['lastError'] = e.toString();
      if (e is LLMApiException && e.retryAfter != null) {
        state['notBefore'] = DateTime.now().add(e.retryAfter!).toUtc().toIso8601String();
      }
      state['failures'] = (state['failures'] as int? ?? 0) + 1;
      // Unknown submit/config/auth needs user attention, never automatic re-buy.
      state['paused'] =
          state['batchId'] == null ||
          e is LLMApiException && (e.statusCode == 401 || e.statusCode == 403) ||
          e.toString().contains('connection changed');
      task.addLog('Batch refresh: $e');
    } finally {
      state['polls'] = (state['polls'] as int? ?? 0) + 1;
      final failures = state['failures'] as int? ?? 0;
      final seconds = failures > 0
          ? math.min(1800, 60 * math.pow(2, math.min(failures, 5)).toInt())
          : switch (state['polls'] as int) {
              1 => 60,
              2 => 120,
              _ => 300,
            };
      var next = DateTime.now().add(Duration(seconds: seconds + task.id.hashCode.abs() % 13));
      final notBefore = DateTime.tryParse(state['notBefore'] as String? ?? '');
      if (notBefore != null && notBefore.isAfter(next)) next = notBefore;
      state['nextPollAt'] = next.toUtc().toIso8601String();
      await _db.saveTask(task);
      _notify();
    }
  }

  Future<void> _cancelBatchTask(TaskItem task) async {
    if (task.isTerminal || !_batchCancels.add(task.id)) return;
    try {
      if (task.status == TaskStatus.pending) {
        await _finishBatch(task, TaskStatus.cancelled);
      } else {
        task.batchState?['cancelRequested'] = true;
        await _db.saveTask(task);
        if (task.canRefresh) await refreshBatchTask(task.id);
      }
      _notify();
    } finally {
      _batchCancels.remove(task.id);
    }
  }

  Future<void> _finishBatch(TaskItem task, TaskStatus status) async {
    task.batchState?['settled'] = true;
    task.batchState?['phase'] = 'settled';
    task.status = status;
    task.endTime = DateTime.now();
    try {
      await _db.saveTask(task);
    } catch (_) {
      task.batchState?['settled'] = false;
      task.status = TaskStatus.awaitingRemote;
      task.endTime = null;
      rethrow;
    }
    _emit(task.id, TaskEventType.statusChanged, status);
    onTaskFinished?.call(task);
    _notify();
  }
}
