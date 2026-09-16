import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/ai_rename_agent.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/ai_rename_review.dart';
import 'package:path/path.dart' as p;

/// Covers the review half of AI batch rename — what the dialog decides before
/// anything reaches [AiRenameAgent.applyProposals].
///
/// A row that reads "resolved" goes to the executor as-is, so the cases that
/// must hold are about what counts as resolved: a clash is never hidden, and
/// an answer is never silently dropped.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('joycai_rename_review');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  String touch(String name) {
    final file = File(p.join(dir.path, name))..writeAsStringSync(name);
    return file.path;
  }

  RenameReviewRow row(String oldName, String newName) => RenameReviewRow(RenameProposal(
        path: touch(oldName),
        oldName: oldName,
        newName: newName,
      ));

  test('two rows proposing one name both clash, whatever the case', () async {
    final rows = [row('a.jpg', 'beach.jpg'), row('b.jpg', 'Beach.JPG'), row('c.jpg', 'dunes.jpg')];
    await recomputeRenameConflicts(rows);

    expect(rows.map((r) => r.conflict), [
      RenameConflict.duplicate,
      RenameConflict.duplicate,
      RenameConflict.none,
    ]);
    expect(rows.map((r) => r.willApply), [false, false, true]);
  });

  test('a name another file already has is a clash with the disk', () async {
    touch('beach.jpg');
    final rows = [row('a.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    expect(rows.single.conflict, RenameConflict.targetExists);
    expect(rows.single.unresolved, isTrue);
    expect(rows.single.willApply, isFalse);
  });

  test("a row's own file is not a clash, and an unchanged name does not apply", () async {
    final rows = [row('beach.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    expect(rows.single.conflict, RenameConflict.none);
    expect(rows.single.willApply, isFalse);
  });

  test('a skipped row clashes with nothing and keeps its answer', () async {
    final rows = [row('a.jpg', 'beach.jpg'), row('b.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    resolveRenameConflict(rows[1], RenameConflictChoice.skip);
    await recomputeRenameConflicts(rows);

    expect(rows[0].conflict, RenameConflict.none, reason: 'the skipped row no longer claims the name');
    expect(rows[0].willApply, isTrue);
    expect(rows[1].conflict, RenameConflict.none);
    expect(rows[1].choice, RenameConflictChoice.skip);
    expect(rows[1].willApply, isFalse);
  });

  test('overwrite leaves the clash visible but answered', () async {
    touch('beach.jpg');
    final rows = [row('a.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    resolveRenameConflict(rows.single, RenameConflictChoice.overwrite);
    await recomputeRenameConflicts(rows);

    expect(rows.single.conflict, RenameConflict.targetExists);
    expect(rows.single.choice, RenameConflictChoice.overwrite);
    expect(rows.single.unresolved, isFalse);
    expect(rows.single.willApply, isTrue);
  });

  test('an edit that clears a clash also clears the answer to it', () async {
    touch('beach.jpg');
    final rows = [row('a.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);
    resolveRenameConflict(rows.single, RenameConflictChoice.overwrite);

    rows.single.newName = 'dunes.jpg';
    await recomputeRenameConflicts(rows);

    expect(rows.single.conflict, RenameConflict.none);
    expect(rows.single.choice, isNull, reason: 'an overwrite must not outlive the clash it answered');
  });

  test('rename picks the next free name on disk', () async {
    touch('beach.jpg');
    final rows = [row('a.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    resolveRenameConflict(rows.single, RenameConflictChoice.rename);
    await recomputeRenameConflicts(rows);

    expect(rows.single.newName, 'beach (2).jpg');
    expect(rows.single.autoRenamed, isTrue);
    expect(rows.single.conflict, RenameConflict.none);
    expect(rows.single.willApply, isTrue);
  });
}
