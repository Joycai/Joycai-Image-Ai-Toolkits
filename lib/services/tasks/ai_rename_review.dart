import 'dart:io';

import 'package:path/path.dart' as p;

import '../files/file_transfer_service.dart';
import 'ai_rename_agent.dart';

/// How a reviewed row's target name clashes.
enum RenameConflict {
  none,

  /// Another file already carries this name on disk.
  targetExists,

  /// Two rows in this run propose the same name.
  duplicate,
}

/// What the user decided about a clashing row.
enum RenameConflictChoice { rename, skip, overwrite }

/// One line of the AI rename review list (`B1b 1e` / `1f`).
///
/// Mutable on purpose: the whole point of the review list is that a row is a
/// thing the user edits — skipped, renamed in place, a clash answered — rather
/// than a cell in a take-it-or-leave-it table.
class RenameReviewRow {
  RenameReviewRow(this.proposal) : newName = proposal.newName;

  final RenameProposal proposal;

  String newName;
  bool skipped = false;
  bool autoRenamed = false;
  RenameConflict conflict = RenameConflict.none;
  RenameConflictChoice? choice;

  String get path => proposal.path;
  String get oldName => proposal.oldName;
  String get directory => p.dirname(proposal.path);

  bool get hasConflict => conflict != RenameConflict.none;

  /// A conflict the user has not answered. These are subtracted from the apply
  /// count one by one — one bad name must not block thirty-five good ones.
  bool get unresolved => hasConflict && choice == null;

  bool get willApply => !skipped && !unresolved && newName.isNotEmpty && newName != oldName;
}

/// Sets every row's [RenameReviewRow.conflict], recomputed from scratch.
///
/// Recomputed rather than patched: a rename can resolve one clash and create
/// another in the same keystroke, and an incremental update has to get both
/// halves right; this is O(n) over a list that is at most a few hundred rows
/// long.
///
/// Two rows clash when their targets match ignoring case — the stricter of the
/// file systems this runs on. A row clashes with the disk when its target
/// exists and is not the row's own file (that is the no-op case, filtered out
/// by [RenameReviewRow.willApply]). A row whose clash has gone away forgets
/// its answer, unless the answer was to skip it.
Future<void> recomputeRenameConflicts(List<RenameReviewRow> rows) async {
  final taken = <String, int>{};
  for (final row in rows) {
    if (row.skipped) continue;
    final key = p.join(row.directory, row.newName).toLowerCase();
    taken[key] = (taken[key] ?? 0) + 1;
  }

  for (final row in rows) {
    if (row.skipped) {
      row.conflict = RenameConflict.none;
      continue;
    }
    final targetPath = p.join(row.directory, row.newName);
    if ((taken[targetPath.toLowerCase()] ?? 0) > 1) {
      row.conflict = RenameConflict.duplicate;
      continue;
    }
    // A name that only "exists" because it is this row's own file is not a
    // clash — that is the no-op case, filtered out by [RenameReviewRow.willApply].
    final exists = await File(targetPath).exists();
    row.conflict = (exists && !p.equals(targetPath, row.path))
        ? RenameConflict.targetExists
        : RenameConflict.none;
    if (row.conflict == RenameConflict.none && row.choice != RenameConflictChoice.skip) {
      row.choice = null;
    }
  }
}

/// Records the user's answer to [row]'s clash. Follow with
/// [recomputeRenameConflicts]: an answer can clear this clash or cause another.
///
/// [among] is the whole review list. A rename has to steer clear of the names
/// the *other* rows are about to take, not only of the disk — otherwise, on a
/// clash between two rows, it hands back the very name they share, and the
/// row reads as answered while still colliding.
///
/// Overwrite is refused on a clash between two rows. It means "replace the
/// file already at that name", and when the clash is between rows there is no
/// such file yet — the only thing it could replace is what another row in the
/// same run has just renamed there. The dialog shows the action disabled; this
/// is the check that holds if it ever is not.
void resolveRenameConflict(
  RenameReviewRow row,
  RenameConflictChoice choice, {
  required List<RenameReviewRow> among,
}) {
  if (choice == RenameConflictChoice.overwrite && row.conflict == RenameConflict.duplicate) {
    throw StateError(
      'Overwrite answers a clash with a file on disk. "${row.newName}" clashes '
      'with another row in this run, so it would replace that row\'s result.',
    );
  }
  row.choice = choice;
  switch (choice) {
    case RenameConflictChoice.rename:
      row.newName = _freeName(row, among);
      row.autoRenamed = true;
    case RenameConflictChoice.skip:
      row.skipped = true;
    case RenameConflictChoice.overwrite:
      break;
  }
}

/// The first name for [row] that is free on disk and that no other live row in
/// [among] is taking, compared ignoring case as [recomputeRenameConflicts] does.
String _freeName(RenameReviewRow row, List<RenameReviewRow> among) {
  final claimed = {
    for (final other in among)
      if (!identical(other, row) && !other.skipped)
        p.join(other.directory, other.newName).toLowerCase(),
  };
  // `uniqueTargetPath` knows the disk and the numbering; its `reserved` set is
  // compared exactly, so each candidate another row claims goes back in as
  // itself, which moves the search on to the next number.
  final reserved = <String>{};
  while (true) {
    final candidate = FileTransferService.uniqueTargetPath(row.directory, row.newName, reserved: reserved);
    if (!claimed.contains(candidate.toLowerCase())) return p.basename(candidate);
    reserved.add(candidate);
  }
}
