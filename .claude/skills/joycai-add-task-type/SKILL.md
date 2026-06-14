---
name: joycai-add-task-type
description: >
  Guides adding a new background task type to the Joycai Image AI Toolkits task queue.
  Use whenever asked to "add a new task", "create a task type", "extend the task queue",
  "add a batch processing mode", or "add a new background operation". Also trigger when
  a new AI-powered workflow needs to be integrated into the existing queue system
  (TaskQueueService). This skill covers the full checklist: enum value, logging branch,
  dispatcher branch, execute method (with cancellation and streaming patterns), l10n
  strings, and UI display — ensuring nothing is forgotten.
---

# Add a New Task Type to the Task Queue

All background operations in this app flow through `TaskQueueService`
(`lib/services/task_queue_service.dart`). Adding a new task type requires
touching several points in that file in a coordinated way. Missing any step
causes silent failures or tasks that get stuck in "processing" with no progress.

## Files to Touch

| File | What to do |
|------|-----------|
| `lib/services/task_queue_service.dart` | Primary — all logic lives here |
| `lib/l10n/src/en/tasks.arb` (+ zh, zh_Hant, ja) | Add display name / status strings |
| `lib/screens/batch/task_queue_screen.dart` | Add UI label/icon for the new type (optional but recommended) |

## Checklist

- [ ] 1. Add value to `TaskType` enum (~line 18)
- [ ] 2. Add creation log message in `addTask()` (~line 201)
- [ ] 3. Add dispatch branch in `_executeTask()` (~line 283)
- [ ] 4. Implement `_executeNewTypeTask(TaskItem task)` method
- [ ] 5. Add l10n strings for task label / status messages (run `joycai-l10n` skill)
- [ ] 6. Update task queue screen display label if needed
- [ ] 7. Run `flutter analyze` — must report **"No issues found!"**

## Step 1 — TaskType Enum

```dart
// lib/services/task_queue_service.dart, line ~18
enum TaskType { imageProcess, imageDownload, promptRefine, aiRename, videoGenerate, myNewType }
```

## Step 2 — Creation Log in `addTask()`

```dart
// Inside addTask(), after creating the TaskItem:
} else if (type == TaskType.myNewType) {
  task.addLog('My new type task created using $modelIdStr.');
}
```

## Step 3 — Dispatch Branch in `_executeTask()`

```dart
// Inside _executeTask(), in the try block (~line 283):
} else if (task.type == TaskType.myNewType) {
  await _executeMyNewTypeTask(task);
}
```

## Step 4 — Execute Method

This is the main implementation. Follow the pattern from existing methods.
The two critical invariants are:
- **Check cancellation** inside streaming loops — tasks can be cancelled mid-execution
- **Emit events** via `_emit()` — the UI shows live progress only through these events

### Streaming template (preferred when model supports it)

```dart
Future<void> _executeMyNewTypeTask(TaskItem task) async {
  task.addLog('Starting my new type task.');

  // Extract parameters stored as JSON in task.parameters
  final myParam = task.parameters['myParam'] as String? ?? '';

  final messages = [
    LLMMessage(role: LLMRole.system, content: 'Your system prompt here.'),
    LLMMessage(
      role: LLMRole.user,
      content: myParam,
      // Attach files if needed:
      // attachments: task.imagePaths.map((p) => LLMAttachment.fromFile(File(p), _getMimeType(p))).toList(),
    ),
  ];

  final actualUseStream = await _shouldUseStream(task);

  if (actualUseStream) {
    final stream = LLMService().requestStream(
      modelIdentifier: task.modelDbId ?? task.modelId,
      messages: messages,
      contextId: task.id,
      options: task.parameters,
    );

    final buffer = StringBuffer();
    await for (final chunk in stream) {
      if (task.status == TaskStatus.cancelled) break; // REQUIRED

      if (chunk.textPart != null) {
        buffer.write(chunk.textPart);
        _emit(task.id, TaskEventType.textChunk, chunk.textPart); // drives live UI
        notifyListeners();
      }
    }

    if (task.status == TaskStatus.cancelled) return;

    final result = buffer.toString().trim();
    task.parameters['result'] = result; // store text result in parameters
    task.addLog('Task complete. Result length: ${result.length} chars.');

  } else {
    // Non-streaming fallback
    final response = await LLMService().request(
      modelIdentifier: task.modelDbId ?? task.modelId,
      messages: messages,
      useStream: false,
    );
    if (response.text.isNotEmpty) {
      _emit(task.id, TaskEventType.textChunk, response.text);
      task.parameters['result'] = response.text;
      task.addLog('Task complete.');
    }
  }
}
```

### If the task produces output files

```dart
// After processing, save files and register them so gallery picks them up:
final outputDir = await _getEffectiveOutputDir(task);
final filePath = p.join(outputDir, 'output_${DateTime.now().millisecondsSinceEpoch}.png');
await File(filePath).writeAsBytes(imageBytes);
task.resultPaths.add(filePath);
_emit(task.id, TaskEventType.imageResult, filePath);
onTaskCompleted?.call(File(filePath)); // notifies GalleryState
```

### If the task is a long-running operation (e.g., video generation)

See `_executeVideoGenerateTask()` for the polling pattern using
`LLMService().startLongRunning()` and `LLMService().checkOperation()`.

## Common Pitfalls

**Forgetting the cancellation check** — Without `if (task.status == TaskStatus.cancelled) break`
inside the streaming loop, a cancelled task keeps consuming API tokens and never stops.

**Not calling `_emit()`** — The task queue UI listens to the event stream. Without
`_emit(task.id, TaskEventType.textChunk, chunk)`, the UI shows no live output even
though the model is responding.

**Not calling `_shouldUseStream()`** — Some models (`supportsStream == false`) will
error if asked to stream. Always check before choosing the streaming path.

**Storing non-serializable data in `task.parameters`** — Parameters are persisted as
JSON via `toMap()`. Only store strings, numbers, booleans, lists, and maps.

**Forgetting to add the l10n string** — The task queue screen displays a human-readable
label for each task type. If no string is added, it falls back to the raw enum name.
Run the `joycai-l10n` skill to add display labels to `tasks.arb`.
