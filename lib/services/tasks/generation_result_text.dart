import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/task_item.dart';
import 'generation_task_data.dart';

/// Saves the queued input alongside each delivered result. A sidecar failure
/// must never retry an already billed generation or hide its saved media.
Future<void> saveGenerationResultText(TaskItem task, String resultPath) async {
  if (task.parameters['saveGenerationText'] != true) return;
  final text = StringBuffer('Input images:\n');
  final paths = task.generationImagePaths;
  if (paths.isEmpty) text.writeln('(none)');
  for (final path in paths) {
    text.writeln(p.basename(path));
  }
  text.writeln('\nPrompt:');
  text.write(task.generationOptions['prompt'] ?? '');
  final path = p.setExtension(resultPath, '.txt');
  try {
    await File(path).writeAsString(text.toString(), flush: true);
    task.addLog('Saved generation text to: $path');
  } on FileSystemException catch (error) {
    task.addLog('Warning: could not save generation text to $path: $error');
  }
}
