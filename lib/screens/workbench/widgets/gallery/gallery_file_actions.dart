import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_image.dart';
import '../../../../models/browser_file.dart';
import '../../../../models/llm_model.dart';
import '../../../../models/task_item.dart';
import '../../../../services/assistant/prompt_optimizer_agent.dart';
import '../../../../state/app_state.dart';
import '../../../../state/workbench_ui_state.dart';
import '../../../../widgets/files/file_delete_dialog.dart';
import '../../../../widgets/ui/app_snackbar.dart';
import '../../assistant/result_feedback_dialog.dart';

/// File-system side effects for gallery items (save / share / delete).
///
/// Kept separate from the card and context-menu UI so the widgets stay
/// presentation-only. Each function shows its own user feedback via the given
/// [context] and triggers a gallery refresh where appropriate.

/// Save a single file: a save-dialog on desktop, the system gallery on mobile.
Future<void> saveImageFile(
  BuildContext context,
  String sourcePath,
  String fileName,
  AppLocalizations l10n,
) async {
  try {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final extension = sourcePath.split('.').last;
      final bytes = await File(sourcePath).readAsBytes();
      final outputFile = await FilePicker.saveFile(
        dialogTitle: l10n.save,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );

      if (outputFile != null && context.mounted) {
        AppSnackBar.success(context, l10n.settingsExported);
      }
    } else {
      if (AppConstants.isVideoFile(sourcePath)) {
        await Gal.putVideo(sourcePath);
      } else {
        await Gal.putImage(sourcePath);
      }
      if (context.mounted) {
        AppSnackBar.success(context, l10n.savedToPhotos);
      }
    }
  } catch (e) {
    if (context.mounted) {
      AppSnackBar.error(context, l10n.saveFailed(e.toString()));
    }
  }
}

/// Share one or more files via the platform share sheet.
Future<void> shareImageFiles(
  BuildContext context,
  List<AppImage> filesToShare,
  AppLocalizations l10n, {
  required Offset position,
}) async {
  try {
    final xFiles = filesToShare
        .map((f) => XFile(f.path, name: f.name, mimeType: AppConstants.getMimeType(f.path)))
        .toList();

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      xFiles,
      subject: filesToShare.length == 1 ? filesToShare.first.name : l10n.appTitle,
      sharePositionOrigin: Rect.fromLTWH(position.dx, position.dy, 1, 1),
    );
  } catch (e) {
    if (context.mounted) {
      AppSnackBar.error(context, l10n.shareFailed(e.toString()));
    }
  }
}

/// Confirm then delete one or more gallery files, through the same flow and
/// the same dialog the file browser uses.
///
/// This used to be a second implementation: a one-line confirmation, the
/// recycle bin on Windows via PowerShell, and `File.delete()` — a permanent
/// delete — on macOS and Linux. Same app, same files, two different fates
/// depending on which screen you happened to be looking at. The shared run
/// sends everything to the trash wherever the platform has one, says which it
/// is going to do *before* the user decides, refuses to delete a registered
/// source folder, and reports a partial failure instead of hiding it.
Future<void> confirmAndDeleteImageFiles(BuildContext context, List<AppImage> images) async {
  if (images.isEmpty) return;
  final galleryState = Provider.of<AppState>(context, listen: false).galleryState;

  // `BrowserFile` is "a file on disk with its stat", which is what the dialog
  // lists; the gallery's `AppImage` carries only path and name, so the stat
  // is taken here. A file that has gone missing since the scan is dropped —
  // the run would only report it as a failure.
  final files = <BrowserFile>[];
  for (final image in images) {
    final file = File(image.path);
    if (file.existsSync()) files.add(BrowserFile.fromFile(file));
  }
  if (!context.mounted) return;
  if (files.isEmpty) {
    // `existsSync` answers "no" for a file the process cannot reach at all —
    // gone since the scan, a broken link, a folder it has no permission to
    // read — so silence here would look like a dead button. Say it instead.
    AppSnackBar.error(context, AppLocalizations.of(context)!.deleteFailed(images.first.name));
    return;
  }

  await runFileDelete(
    context,
    files,
    protectedRoots: galleryState.sourceDirectories,
    // The selection is deliberately not cleared: `refreshImages` ends in
    // `_cleanupSelection`, which drops exactly the pictures that are gone and
    // keeps the rest. Clearing it wholesale threw away a selection the user
    // had built for something else whenever they deleted one unrelated file
    // from the context menu, and would have thrown away the survivors of a
    // half-failed run.
    onDeleted: () async => galleryState.refreshImages(),
  );
}

/// Whether [path] can be fed back to the assistant right now (`A1 · 3a`).
///
/// The report is about the conversation's prompt, so the session must have
/// staged at least one version — with none there is nothing to judge, and
/// the row greys out. Provenance is not required: a picture the task record
/// ties to a version reports on that version, any other reports on the
/// latest (see [resultFeedbackVersion]), since the user may well be judging
/// a run whose prompt they edited before generating. The action is withdrawn
/// while a turn is running so a click cannot land in the middle of one. The
/// card's hover strip and the context menu both read this so they agree.
bool canSendResultFeedback(WorkbenchUIState workbenchUIState, String path) =>
    workbenchUIState.optimizerSession.promptVersions > 0 &&
    !workbenchUIState.optimizerSession.isRunning;

/// The prompt version a report on [path] binds to: provenance first, the
/// latest staged version as the fallback. An image the task record ties to
/// v2 gives feedback on v2 even after v3 was staged — that binding is the
/// whole reason the tag exists. Null when the session has staged nothing.
int? resultFeedbackVersion(WorkbenchUIState workbenchUIState, String path) {
  final version =
      workbenchUIState.resultVersionByPath[path] ??
      workbenchUIState.optimizerSession.promptVersions;
  return version < 1 ? null : version;
}

/// Collects the verdict on [image] (`3b`) and stages it on the assistant
/// session, which latches an assistant-turn request the workbench screen
/// consumes. The user stays where they are — `3a`: 「不切换页面」 — and a
/// toast says the report went through.
///
/// The version comes from [resultFeedbackVersion]; the run recap in the
/// heading only appears when the task record names the run, so a picture
/// without provenance shows the version and the prompt line alone.
Future<void> sendResultFeedbackFromGallery(BuildContext context, AppImage image) async {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  final appState = Provider.of<AppState>(context, listen: false);
  final version = resultFeedbackVersion(workbenchUIState, image.path);
  if (version == null) return;
  final task = await workbenchUIState.resultTaskForPath(image.path);
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final feedback = await showResultFeedbackDialog(
    context,
    image: image,
    promptVersion: version,
    runMeta: task == null ? null : _describeRun(task, appState, l10n),
    promptText: _promptFirstLine(workbenchUIState.optimizerSession, version),
  );
  if (feedback == null) return;
  if (!workbenchUIState.sendResultFeedback(image, feedback: feedback, promptVersion: version)) {
    return;
  }
  if (context.mounted) AppSnackBar.success(context, l10n.optResultFeedbackSent);
}

/// 「gpt-image-1 · 今天 14:02」: the model the run used and when it started.
String _describeRun(TaskItem task, AppState appState, AppLocalizations l10n) {
  final model = appState.allModels.cast<LLMModel?>().firstWhere(
    (m) => m?.id == task.modelDbId,
    orElse: () => null,
  );
  final modelLabel = model?.modelName ?? task.modelId;
  final when = task.createdAt;
  final now = DateTime.now();
  final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
  final clock = DateFormat('HH:mm').format(when);
  final timeLabel = sameDay
      ? l10n.optFeedbackRunToday(clock)
      : DateFormat('MM-dd HH:mm').format(when);
  return [if (modelLabel.isNotEmpty) modelLabel, timeLabel].join(' · ');
}

/// The first line of the prompt staged as [version], or null when the
/// transcript no longer holds it.
String? _promptFirstLine(PromptOptimizerSession session, int version) {
  for (final e in session.transcript.reversed) {
    if (e.kind != OptimizerEntryKind.prompt || e.version != version) continue;
    final line = e.text.trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  }
  return null;
}
