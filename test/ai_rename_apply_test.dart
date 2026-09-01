import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/ai_rename_agent.dart';
import 'package:path/path.dart' as p;

/// Covers the disk half of AI batch rename — what [AiRenameAgent.applyProposals]
/// does once the user has confirmed a list.
///
/// The `overwrite` flag is the reason this file exists. It is the only way this
/// app deletes a file the model never saw, so the cases that must hold are:
/// it does nothing unless a person set it, and when set it actually replaces
/// the target rather than silently skipping — the behaviour Windows would give
/// if the rename were left to overwrite on its own.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('joycai_rename');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<String> write(String name, String contents) async {
    final file = File(p.join(dir.path, name));
    await file.writeAsString(contents);
    return file.path;
  }

  RenameProposal proposal(String path, String newName, {bool overwrite = false}) =>
      RenameProposal(
        path: path,
        oldName: p.basename(path),
        newName: newName,
        overwrite: overwrite,
      );

  test('renames a file whose target name is free', () async {
    final source = await write('a.png', 'aaa');

    final count = await AiRenameAgent.applyProposals([proposal(source, 'b.png')]);

    expect(count, 1);
    expect(File(source).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'b.png')).readAsStringSync(), 'aaa');
  });

  test('skips a taken name when overwrite was not asked for', () async {
    final source = await write('a.png', 'new');
    await write('b.png', 'old');

    final count = await AiRenameAgent.applyProposals([proposal(source, 'b.png')]);

    expect(count, 0);
    expect(File(source).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'b.png')).readAsStringSync(), 'old');
  });

  test('overwrite replaces the file at the target name', () async {
    // Only reachable by answering a conflict in the review dialog. The delete
    // is explicit because `File.rename` onto an existing path throws on
    // Windows — leaving it to the rename would fail exactly where this app is
    // most used.
    final source = await write('a.png', 'new');
    await write('b.png', 'old');

    final count =
        await AiRenameAgent.applyProposals([proposal(source, 'b.png', overwrite: true)]);

    expect(count, 1);
    expect(File(source).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'b.png')).readAsStringSync(), 'new');
  });

  test('a proposal that does not change the name is a no-op', () async {
    final source = await write('a.png', 'aaa');

    final count = await AiRenameAgent.applyProposals([proposal(source, 'a.png')]);

    expect(count, 0);
    expect(File(source).readAsStringSync(), 'aaa');
  });

  test('a source that has gone is skipped, not thrown', () async {
    // Between the preview and the apply the file can be moved by anything on
    // the machine; the rest of the batch still has to land.
    final ghost = p.join(dir.path, 'gone.png');
    final real = await write('a.png', 'aaa');

    final count = await AiRenameAgent.applyProposals([
      proposal(ghost, 'x.png'),
      proposal(real, 'b.png'),
    ]);

    expect(count, 1);
    expect(File(p.join(dir.path, 'b.png')).existsSync(), isTrue);
  });

  test('proposals arriving from a model never carry overwrite', () async {
    // The default matters: a proposal built anywhere but the conflict UI must
    // not be able to delete anything.
    final made = RenameProposal(path: '/tmp/a.png', oldName: 'a.png', newName: 'b.png');

    expect(made.overwrite, isFalse);
  });
}
