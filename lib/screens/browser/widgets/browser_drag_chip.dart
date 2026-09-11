import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/drag/app_drag_follower.dart';
import '../../workbench/directory_tree_item.dart' show FolderDropFollower;

/// What follows the pointer while files are dragged onto a folder
/// (`00d · 1e`): the opaque follower chip with the count, saying what a
/// release does — move, or copy while the copy key is held, switching the
/// moment the key goes down. Over a folder that refuses the files it gives
/// way to that folder's reason.
///
/// Shared by the grid card and the list row. The drag carries files rather
/// than paths so this chip can count them without asking the browser state.
class BrowserFileDragChip extends StatelessWidget {
  const BrowserFileDragChip({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return FolderDropFollower(
      builder: (context, copying) => AppDragFollower(
        // `00d` writes content_copy for the move; a copy glyph on a move reads
        // as a copy, so the move keeps the move glyph.
        icon: copying ? Icons.file_copy_outlined : Icons.drive_file_move_outline,
        label: copying ? l10n.dragCopyItems(count) : l10n.dragMoveItems(count),
        count: count,
        tone: copying ? AppDragTone.copy : AppDragTone.move,
      ),
    );
  }
}
