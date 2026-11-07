---
name: joycai-add-task-type
description: Add a background task type to Joycai's TaskQueueService, including dispatch, execution, persisted task data, events, localization, and UI presentation. Use when extending the app's task queue or adding a new queued operation.
---

# Add a New Task Type

Read `AGENTS.md` first. Business logic stays in `lib/services/tasks/`; task models
stay Flutter-free. Use the current implementation as the template rather than
copying old API signatures or relying on line numbers.

## Extension points

| File | Responsibility |
|---|---|
| `lib/models/task_item.dart` | `TaskType`, `TaskItem`, `TaskEvent`, serialization |
| `lib/services/tasks/task_queue_service.dart` | `_executeTask()` dispatch, lifecycle, concurrency, persistence |
| `lib/services/tasks/task_executors.dart` | `_executeXxxTask()` methods; a `part of` the queue service |
| `lib/services/tasks/generation_task_data.dart` | Typed generation snapshot creation and legacy-compatible reads |
| `lib/services/tasks/task_media_snapshot.dart` | Persistent copies of task input media |
| `lib/widgets/tasks/task_type_glyph.dart` | Shared task-type icons |
| `lib/screens/batch/task_card/task_card_cells.dart` | Task-type semantic colours |
| `lib/l10n/src/<lang>/tasks.arb` | Localized labels/status strings for all four languages |

## Workflow

1. Add a `TaskType` value in `task_item.dart`. Inspect `toMap`/`fromMap` and existing
   database migrations before changing persisted representations; retain compatibility
   with saved task history. A schema change needs matching create and upgrade paths.
2. Add a branch to `_executeTask()` in `task_queue_service.dart` calling the new
   executor. Leave common completion, failure, cancellation, running-count updates,
   and persistence in that lifecycle wrapper.
3. Implement the executor in `task_executors.dart`, following the closest existing
   task. Common task creation is reusable, but inspect `addTask()` and
   `snapshotGenerationTask()` for type-specific behavior: generation snapshots
   currently cover only `imageProcess` and `videoGenerate`. A new generation type
   needs deliberate integration with model-row resolution and snapshot creation.
   Keep new inputs serializable in `task.parameters`; follow the generation
   contract below for image/video operations.
4. For streaming, call `_shouldUseStream(task)` before choosing the path. Check
   `TaskStatus.cancelled` inside streaming/polling loops and after awaited work before
   storing results. Use `_emit()` for live output and `_notify()` for queue changes;
   direct `notifyListeners()` bypasses the queue's snapshot handling.
5. Route model requests by `task.modelDbId ?? task.modelId`, using current LLMService
   method signatures. Preserve usage metadata and context IDs. For polling and
   download deadlines, follow `_executeVideoGenerateTask()` rather than adding an
   uninterruptible sleep or an unbounded poll loop.
6. For output files, follow the existing executor's effective output directory,
   `resultPaths`, `TaskEventType.imageResult`, and `onTaskCompleted` conventions so
   the gallery sees results. Inspect the callback signature before calling it.
7. Find all `TaskType` switches and presentation sites with `rg -n TaskType lib test`.
   Update glyphs, semantic colours, labels, relevant controls, and exhaustive tests.
   Use `joycai-l10n` for user-visible strings in `en`, `zh`, `zh_Hant`, and `ja`.
8. Add meaningful executor/lifecycle tests under `test/services/tasks/`, using the
   injected database helpers from `AGENTS.md`. Cover cancellation, failure, progress
   events, and persisted results as appropriate for the new operation.
9. Run all three gates: `dart format lib test tool`, `flutter analyze`, and
   `flutter test -x screenshots`. For UI changes, render and inspect the relevant
   screenshot harness as required by `AGENTS.md`.

## Generation and accepted-job contracts

For image/video work, read `docs/architecture/generation-parameters.md` and
`docs/architecture/media-accounting.md` before extending the executor.

- Persist typed intent in `parameters.generation`: prompt, operation, values,
  role-tagged media, model/channel row identities, effective protocol, profile
  and schema version. Keep application metadata outside it. Runtime cancellation
  and abort controls belong in `GenerationExecutionContext`, never serialized.
- Read through `generationTaskOptions` / `task.generationOptions` and
  `task.generationImagePaths`; preserve the legacy flat-task read path. Do not
  persist a second flat copy of the snapshot's prompt, media or parameter values.
- Integrate new media roles with `snapshotTaskMedia` so authoritative and legacy
  paths refer to the same persistent copies when input preservation is enabled.
  Preserve original paths for rename operations and URLs for downloads.
- Before initial paid submission, validate model/channel, vendor, protocol,
  profile and schema compatibility. Resolve current credentials at execution.
  Resume accepted video jobs from their persisted operation/surface identity;
  do not apply initial-submission revalidation or submit a replacement generation.
  For Batch work, follow `image_batch_tasks.dart` and `image_batch_session.dart`
  under their respective task/LLM service folders, including durable submission
  intent and reconciliation of ambiguous submissions.
- Preserve submitted prices, usage scope and remote operation identity. Use the
  shared accounting and durable settlement path for terminal evidence; missing
  evidence remains incomplete and cancellation does not establish a refund.
  Test snapshot round trips, legacy reads, preserved media, configuration drift,
  accepted-job recovery and duplicate settlement where applicable.
