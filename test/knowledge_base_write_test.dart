import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_starter.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory dbDir;
  final kb = KnowledgeBaseService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // A database directory of this file's own — `flutter test` runs files
    // concurrently and they would otherwise share one database file.
    dbDir = Directory.systemTemp.createTempSync('joycai_kb_write_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => dbDir.path,
    );
  });

  tearDownAll(() {
    try {
      dbDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The database handle may still be open; the OS reaps temp dirs anyway.
    }
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('kb_test_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('writeFile path safety', () {
    test('rejects paths escaping the root', () {
      expect(
        () => kb.writeFile(root.path, '../evil.md', 'x'),
        throwsA(isA<KbPathException>()),
      );
    });

    test('rejects absolute paths', () {
      expect(
        () => kb.writeFile(root.path, '/etc/passwd.md', 'x'),
        throwsA(isA<KbPathException>()),
      );
    });

    test('rejects the root itself', () {
      expect(
        () => kb.writeFile(root.path, '.', 'x'),
        throwsA(isA<KbPathException>()),
      );
    });

    test('rejects non-markdown files, which listFiles would hide', () {
      expect(
        () => kb.writeFile(root.path, 'notes.txt', 'x'),
        throwsA(isA<KbPathException>()),
      );
    });

    test('rejects dot-prefixed paths, which listFiles would skip', () {
      expect(
        () => kb.writeFile(root.path, '.hidden.md', 'x'),
        throwsA(isA<KbPathException>()),
      );
      expect(
        () => kb.writeFile(root.path, '.git/config.md', 'x'),
        throwsA(isA<KbPathException>()),
      );
    });

    test('writes a nested file, creating parent directories', () async {
      await kb.writeFile(root.path, 'templates/deep/nested.md', '# hi');
      expect(File(p.join(root.path, 'templates/deep/nested.md')).readAsStringSync(), '# hi');
    });

    test('written files are visible to listFiles', () async {
      await kb.writeFile(root.path, 'a.md', 'x');
      final listed = kb.listFiles(root.path).map((f) => f.relPath);
      expect(listed, contains('a.md'));
    });

    test('overwrites existing content', () async {
      await kb.writeFile(root.path, 'a.md', 'old');
      await kb.writeFile(root.path, 'a.md', 'new');
      expect(kb.readFullFile(root.path, 'a.md'), 'new');
    });
  });

  group('readFullFile', () {
    test('returns null for a missing file so callers can detect a create', () {
      expect(kb.readFullFile(root.path, 'nope.md'), isNull);
    });

    test('returns content unpaged, beyond one page size', () async {
      final big = 'x' * (KnowledgeBaseService.pageSize * 2);
      await kb.writeFile(root.path, 'big.md', big);
      expect(kb.readFullFile(root.path, 'big.md')!.length, big.length);
    });
  });

  group('scaffold', () {
    test('creates a knowledge base that validates as ok', () async {
      final result = await KnowledgeBaseStarter.scaffold(root.path);
      expect(result.created, hasLength(KnowledgeBaseStarter.files.length));
      expect(result.skipped, isEmpty);
      expect(result.isNoop, isFalse);
      expect(await kb.validate(root.path), KbStatus.ok);
    });

    test('never overwrites existing files', () async {
      await KnowledgeBaseStarter.scaffold(root.path);
      const sentinel = '# my own rules — do not clobber';
      File(p.join(root.path, 'always/output-rules.md')).writeAsStringSync(sentinel);

      final second = await KnowledgeBaseStarter.scaffold(root.path);
      expect(second.created, isEmpty);
      expect(second.skipped, hasLength(KnowledgeBaseStarter.files.length));
      expect(second.isNoop, isTrue);
      expect(kb.readFullFile(root.path, 'always/output-rules.md'), sentinel);
    });

    test('fills only what is missing', () async {
      await KnowledgeBaseStarter.scaffold(root.path);
      File(p.join(root.path, 'templates/text-to-image.md')).deleteSync();

      final third = await KnowledgeBaseStarter.scaffold(root.path);
      expect(third.created, ['templates/text-to-image.md']);
      expect(third.skipped, hasLength(KnowledgeBaseStarter.files.length - 1));
    });

    test('scaffolding an empty folder resolves missingEntry', () async {
      expect(await kb.validate(root.path), KbStatus.missingEntry);
      await KnowledgeBaseStarter.scaffold(root.path);
      expect(await kb.validate(root.path), KbStatus.ok);
    });

    test('entry file map lists every other starter file', () {
      final readme = KnowledgeBaseStarter.files[KnowledgeBaseService.entryFileName]!;
      for (final path in KnowledgeBaseStarter.files.keys) {
        if (path == KnowledgeBaseService.entryFileName) continue;
        expect(readme, contains(path),
            reason: '$path is missing from the file map, so the agent cannot discover it');
      }
    });

    test('every starter file is reachable by the agent listing', () async {
      await KnowledgeBaseStarter.scaffold(root.path);
      final rootEntries = kb.listFiles(root.path);
      final dirs = rootEntries.where((e) => e.isDir).map((e) => e.relPath);
      final found = <String>{
        ...rootEntries.where((e) => !e.isDir).map((e) => e.relPath),
        for (final d in dirs) ...kb.listFiles(root.path, dir: d).map((e) => e.relPath),
      };
      expect(found, containsAll(KnowledgeBaseStarter.files.keys));
    });
  });

  group('a knowledge base the user built themselves', () {
    /// Nothing in common with the starter but the entry file: its own layout,
    /// its own names, a file map written as bullets rather than tables, and a
    /// non-markdown asset.
    void seedCustomKb() {
      File(p.join(root.path, 'README.md')).writeAsStringSync('''
# 我的提示词库
- 画风规则见 style-guide.md
- 角色见 characters/lin.md
''');
      File(p.join(root.path, 'style-guide.md')).writeAsStringSync('# 画风');
      Directory(p.join(root.path, 'characters')).createSync();
      File(p.join(root.path, 'characters/lin.md')).writeAsStringSync('# 林');
      File(p.join(root.path, 'notes.txt')).writeAsStringSync('scratch');
    }

    test('validates as ok — only the entry file is required', () async {
      seedCustomKb();
      expect(await kb.validate(root.path), KbStatus.ok);
    });

    test('its own files are listable and readable', () {
      seedCustomKb();
      expect(
        kb.listFiles(root.path).map((e) => e.relPath),
        containsAll(['README.md', 'characters', 'style-guide.md']),
      );
      expect(kb.listFiles(root.path, dir: 'characters').single.relPath, 'characters/lin.md');
      expect(kb.readFile(root.path, 'characters/lin.md').content, '# 林');
      expect(kb.readEntry(root.path), contains('style-guide.md'));
    });

    test('the agent can edit its files, which keep their own names', () async {
      seedCustomKb();
      await kb.setRoot(root.path);
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      final id = session.stageKbEditForTest(
        relPath: 'style-guide.md',
        newContent: '# 画风\n补充说明',
        oldContent: '# 画风',
      );
      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: id);
      expect(kb.readFullFile(root.path, 'style-guide.md'), '# 画风\n补充说明');
    });

    test('is not mistaken for a starter base', () {
      seedCustomKb();
      // Drives whether the UI offers to add starter files. A false positive
      // here would bury the user's base in files its map never mentions.
      expect(KnowledgeBaseStarter.looksScaffolded(root.path), isFalse);
    });

    test('a starter base is recognised even with a starter file deleted', () async {
      await KnowledgeBaseStarter.scaffold(root.path);
      File(p.join(root.path, 'templates/text-to-image.md')).deleteSync();
      expect(KnowledgeBaseStarter.looksScaffolded(root.path), isTrue);
    });

    test('an entry file alone is not a starter base', () {
      File(p.join(root.path, 'README.md')).writeAsStringSync('# mine');
      // Every valid base has an entry file, so it cannot be the signal.
      expect(KnowledgeBaseStarter.looksScaffolded(root.path), isFalse);
    });
  });

  group('applyStagedKbEdit', () {
    test('writes the staged content and evicts every cached page of that file', () async {
      await kb.setRoot(root.path);
      await kb.writeFile(root.path, 'a.md', 'old body');

      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      // Pretend the agent read the file across two pages, plus an unrelated one.
      session.readKnowledgePages.addAll({'a.md#1', 'a.md#2', 'b.md#1'});
      final id = session.stageKbEditForTest(
        relPath: 'a.md',
        newContent: 'new body',
        oldContent: 'old body',
      );

      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: id);

      expect(kb.readFullFile(root.path, 'a.md'), 'new body');
      expect(session.transcript.firstWhere((e) => e.editId == id).editState,
          KbEditState.applied);
      // A rewrite moves page boundaries, so every page of a.md must go or the
      // agent would be told its own edit is "already in the conversation".
      expect(session.readKnowledgePages, isNot(contains('a.md#1')));
      expect(session.readKnowledgePages, isNot(contains('a.md#2')));
      expect(session.readKnowledgePages, contains('b.md#1'));
    });

    test('creates a file that did not exist', () async {
      await kb.setRoot(root.path);
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      final id = session.stageKbEditForTest(
        relPath: 'conditional/fresh.md',
        newContent: '# fresh',
        oldContent: null,
      );

      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: id);
      expect(kb.readFullFile(root.path, 'conditional/fresh.md'), '# fresh');
    });

    test('applying twice does not write again', () async {
      await kb.setRoot(root.path);
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      final id = session.stageKbEditForTest(
        relPath: 'a.md',
        newContent: 'first',
        oldContent: null,
      );
      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: id);
      File(p.join(root.path, 'a.md')).writeAsStringSync('edited by hand');

      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: id);
      expect(kb.readFullFile(root.path, 'a.md'), 'edited by hand');
    });

    test('a rejected edit can no longer be applied', () async {
      await kb.setRoot(root.path);
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      final id = session.stageKbEditForTest(
        relPath: 'a.md',
        newContent: 'x',
        oldContent: null,
      );
      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: id);

      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: id);
      expect(File(p.join(root.path, 'a.md')).existsSync(), isFalse);
    });

    test('a failed write marks the card failed rather than applied', () async {
      await kb.setRoot(root.path);
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      // Staging bypasses writeFile's validation, so this only fails on apply —
      // which is exactly why KbEditState.failed exists.
      final id = session.stageKbEditForTest(
        relPath: 'notes.txt',
        newContent: 'x',
        oldContent: null,
      );

      await expectLater(
        PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: id),
        throwsA(isA<KbPathException>()),
      );
      expect(session.transcript.firstWhere((e) => e.editId == id).editState,
          KbEditState.failed);
    });
  });
}
