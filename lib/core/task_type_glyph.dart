import 'package:flutter/material.dart';

import '../services/task_queue_service.dart';

/// One glyph per kind of task, shared by everything that lists them.
///
/// The task queue screen had this switch; the floating capsule (`E1 12g`) drew
/// `image_outlined` for everything, so a video generation and a batch rename
/// both appeared in the monitor as pictures. Two lists of the same queue
/// disagreeing about what its rows *are* is the kind of drift a shared mapping
/// exists to stop — the same argument as [AppStatusBadge] for the four
/// conditions.
///
/// Presentation rather than logic, so it lives beside
/// `settings_category_palette.dart` rather than on [TaskType] itself.
extension TaskTypeGlyph on TaskType {
  IconData get glyph => switch (this) {
        TaskType.imageProcess => Icons.image_outlined,
        TaskType.imageDownload => Icons.cloud_download_outlined,
        TaskType.promptRefine => Icons.auto_fix_high,
        TaskType.aiRename => Icons.drive_file_rename_outline,
        TaskType.videoGenerate => Icons.movie_outlined,
      };
}
