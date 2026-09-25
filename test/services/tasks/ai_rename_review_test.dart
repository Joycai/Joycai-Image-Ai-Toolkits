import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/ai_rename_agent.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/ai_rename_review.dart';
import 'package:path/path.dart' as p;

/// Covers the review half of AI batch rename — what the dialog decides before
/// anything reaches [AiRenameAgent.applyProposals].
///
/// A row that reads "resolved" goes to the executor as-is, so the cases that
/// must hold are about what counts as resolved: a clash is never hidden, an
/// answer is never silently dropped, an answer that picks a new name picks one
/// nothing else in the run is about to take, and no answer lets one row's
/// file be deleted to make room for another's.
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

  RenameReviewRow row(String oldName, String newName) =>
      RenameReviewRow(RenameProposal(path: touch(oldName), oldName: oldName, newName: newName));

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

    resolveRenameConflict(rows[1], RenameConflictChoice.skip, among: rows);
    await recomputeRenameConflicts(rows);

    expect(
      rows[0].conflict,
      RenameConflict.none,
      reason: 'the skipped row no longer claims the name',
    );
    expect(rows[0].willApply, isTrue);
    expect(rows[1].conflict, RenameConflict.none);
    expect(rows[1].choice, RenameConflictChoice.skip);
    expect(rows[1].willApply, isFalse);
  });

  test('overwrite leaves the clash visible but answered', () async {
    touch('beach.jpg');
    final rows = [row('a.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    resolveRenameConflict(rows.single, RenameConflictChoice.overwrite, among: rows);
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
    resolveRenameConflict(rows.single, RenameConflictChoice.overwrite, among: rows);

    rows.single.newName = 'dunes.jpg';
    await recomputeRenameConflicts(rows);

    expect(rows.single.conflict, RenameConflict.none);
    expect(
      rows.single.choice,
      isNull,
      reason: 'an overwrite must not outlive the clash it answered',
    );
  });

  test('rename picks the next free name on disk', () async {
    touch('beach.jpg');
    final rows = [row('a.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    resolveRenameConflict(rows.single, RenameConflictChoice.rename, among: rows);
    await recomputeRenameConflicts(rows);

    expect(rows.single.newName, 'beach (2).jpg');
    expect(rows.single.autoRenamed, isTrue);
    expect(rows.single.conflict, RenameConflict.none);
    expect(rows.single.willApply, isTrue);
  });

  test('rename on a clash between two rows picks a name neither row takes', () async {
    final rows = [row('a.jpg', 'beach.jpg'), row('b.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    resolveRenameConflict(rows[1], RenameConflictChoice.rename, among: rows);
    await recomputeRenameConflicts(rows);

    expect(rows[1].newName, isNot('beach.jpg'));
    expect(rows.map((r) => r.conflict), everyElement(RenameConflict.none));
    expect(rows.map((r) => r.willApply), [true, true]);
  });

  test('rename steers clear of a name another row takes in a different case', () async {
    final rows = [
      row('a.jpg', 'Beach.JPG'),
      row('b.jpg', 'beach (2).jpg'),
      row('c.jpg', 'beach.jpg'),
    ];
    await recomputeRenameConflicts(rows);
    expect(rows[2].conflict, RenameConflict.duplicate);

    resolveRenameConflict(rows[2], RenameConflictChoice.rename, among: rows);
    await recomputeRenameConflicts(rows);

    expect(rows[2].newName, 'beach (3).jpg');
    expect(rows.map((r) => r.conflict), everyElement(RenameConflict.none));
  });

  test('overwrite is refused on a clash between two rows', () async {
    final rows = [row('a.jpg', 'beach.jpg'), row('b.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);

    expect(
      () => resolveRenameConflict(rows[1], RenameConflictChoice.overwrite, among: rows),
      throwsStateError,
    );
    expect(rows[1].choice, isNull, reason: 'a refused answer leaves the row unanswered');
    expect(rows[1].willApply, isFalse);
  });

  // The case that lost a photo: one row answered "rename", which handed back
  // the shared name, and the other "overwrite", which then deleted the first
  // row's file to make room. Driven end to end, the way the dialog drives it.
  test('no answers to a clash between two rows delete either file', () async {
    final rows = [row('a.jpg', 'beach.jpg'), row('b.jpg', 'beach.jpg')];
    await recomputeRenameConflicts(rows);
    resolveRenameConflict(rows[0], RenameConflictChoice.rename, among: rows);
    await recomputeRenameConflicts(rows);
    // The first answer cleared the clash, so the second row has nothing left
    // to answer and goes ahead under the name it asked for.
    expect(rows[1].conflict, RenameConflict.none);

    final applying = rows.where((r) => r.willApply).toList();
    await AiRenameAgent.applyProposals([
      for (final r in applying)
        RenameProposal(
          path: r.path,
          oldName: r.oldName,
          newName: r.newName,
          overwrite: r.choice == RenameConflictChoice.overwrite,
        ),
    ]);

    final contents = {
      for (final f in dir.listSync().whereType<File>()) p.basename(f.path): f.readAsStringSync(),
    };
    expect(contents, {'beach (2).jpg': 'a.jpg', 'beach.jpg': 'b.jpg'});
  });
}
