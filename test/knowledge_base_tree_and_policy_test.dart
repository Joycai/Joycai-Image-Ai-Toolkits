// What `A2 10h` needs from the knowledge-base service: a tree the left column
// can draw, a backup copy, and the three write switches.
//
// The tree is pinned to the same rules as `scanTree` and `listFiles` — the
// column is a promise about what the assistant can reach, and a row for a file
// the agent cannot read invites the user to ask about a document that is not
// there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('kb_tree_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can still hold a handle from the copy above; systemTemp is
      // reaped by the OS either way.
    }
  });

  void writeFile(String relPath, {String body = '# rule'}) {
    final file = File(p.join(root.path, relPath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(body);
  }

  List<KbTreeEntry> walk() => KnowledgeBaseService().walkTree(root.path);

  group('walkTree', () {
    test('splices each folder’s contents in directly behind it', () {
      writeFile('README.md');
      writeFile('01_rules/01a_light.md');
      writeFile('01_rules/01b_lens.md');
      writeFile('05_layers.md');

      expect(
        walk().map((e) => '${'  ' * e.depth}${e.name}').toList(),
        <String>[
          '01_rules',
          '  01a_light.md',
          '  01b_lens.md',
          '05_layers.md',
          'README.md',
        ],
      );
    });

    test('carries the nesting depth, not just the path', () {
      writeFile('a/b/c/deep.md');
      final byName = {for (final e in walk()) e.name: e.depth};
      expect(byName, <String, int>{'a': 0, 'b': 1, 'c': 2, 'deep.md': 3});
    });

    test('surfaces only what listFiles would', () {
      writeFile('README.md');
      writeFile('notes.txt');
      writeFile('.hidden/secret.md');

      expect(walk().map((e) => e.name), <String>['README.md']);
    });

    test('relative paths use forward slashes whatever the host', () {
      // The panel splits on `/` to find a row's ancestors; a Windows separator
      // here would make every nested row look like a top-level one.
      writeFile('01_rules/01a_light.md');
      final file = walk().firstWhere((e) => !e.isDir);
      expect(file.relPath, '01_rules/01a_light.md');
    });

    test('an empty base is an empty tree, not an error', () {
      expect(walk(), isEmpty);
    });
  });

  group('backupFile', () {
    test('copies the version about to be overwritten', () async {
      writeFile('rules.md', body: 'before');
      await KnowledgeBaseService().backupFile(root.path, 'rules.md');

      final backup = File(p.join(root.path, 'rules.md${KnowledgeBaseService.backupSuffix}'));
      expect(backup.readAsStringSync(), 'before');
    });

    test('the copy stays invisible to the agent', () async {
      // `.bak` is appended to the whole name rather than replacing `.md`, so
      // listFiles never surfaces it — otherwise every backup would come back
      // as a second document saying nearly the same thing.
      writeFile('rules.md', body: 'before');
      await KnowledgeBaseService().backupFile(root.path, 'rules.md');

      expect(walk().map((e) => e.name), <String>['rules.md']);
    });

    test('a file that does not exist yet has no previous version to keep', () async {
      await KnowledgeBaseService().backupFile(root.path, 'new.md');
      expect(
        File(p.join(root.path, 'new.md${KnowledgeBaseService.backupSuffix}')).existsSync(),
        isFalse,
      );
    });

    test('replaces an earlier backup rather than piling them up', () async {
      writeFile('rules.md', body: 'v1');
      await KnowledgeBaseService().backupFile(root.path, 'rules.md');
      writeFile('rules.md', body: 'v2');
      await KnowledgeBaseService().backupFile(root.path, 'rules.md');

      final backup = File(p.join(root.path, 'rules.md${KnowledgeBaseService.backupSuffix}'));
      expect(backup.readAsStringSync(), 'v2');
      expect(
        root.listSync().where((e) => e.path.endsWith(KnowledgeBaseService.backupSuffix)),
        hasLength(1),
      );
    });
  });

  group('KbWritePolicy', () {
    test('defaults let the agent propose but nothing land unread', () {
      const policy = KbWritePolicy.defaults;
      expect(policy.allowWrites, isTrue);
      expect(policy.confirmEachWrite, isTrue);
      expect(policy.backupBeforeOverwrite, isFalse);
    });

    test('copyWith changes one switch and leaves the others', () {
      const policy = KbWritePolicy.defaults;
      final off = policy.copyWith(confirmEachWrite: false);
      expect(off.confirmEachWrite, isFalse);
      expect(off.allowWrites, isTrue);
      expect(off.backupBeforeOverwrite, isFalse);
      expect(off, isNot(policy));
      expect(policy.copyWith(), policy);
    });
  });
}
