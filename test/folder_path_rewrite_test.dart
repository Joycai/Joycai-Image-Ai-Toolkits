import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/file_utils.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/state/file_browser_state.dart';
import 'package:joycai_image_ai_toolkits/state/file_staging_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// What a folder rename or move has to do to everything that named the old
/// path. The failure this guards against is quiet: nothing crashes, the
/// staging area just reports files "missing" that are right there, and the
/// browser's roots point at a folder that no longer exists.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => Directory.systemTemp.path,
  );

  group('FileUtils.rebasePath', () {
    test('rewrites the prefix itself and paths inside it, segment-aware', () {
      final from = p.join('D:', 'ai_res');
      final to = p.join('D:', 'renders');
      expect(FileUtils.rebasePath(from, from: from, to: to), to);
      expect(
        FileUtils.rebasePath(p.join(from, 'cha', 'a.png'), from: from, to: to),
        p.join(to, 'cha', 'a.png'),
      );
      // `ai_res2` is not inside `ai_res`.
      expect(FileUtils.rebasePath('${from}2', from: from, to: to), isNull);
      expect(FileUtils.rebasePath(p.join('E:', 'other'), from: from, to: to), isNull);
    });
  });

  group('FileStagingState.rewritePathPrefix', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('joycai_rewrite');
      await DatabaseService().saveSetting(FileStagingState.settingsKey, '');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    BrowserFile fileAt(String path) => BrowserFile(
          path: path,
          name: p.basename(path),
          category: BrowserFile.categoryOf(path),
          size: 1,
          modified: DateTime(2026, 1, 1),
        );

    test('marks and the destination follow the folder; others stay', () async {
      final state = FileStagingState();
      await state.ready;
      final old = p.join(root.path, 'old');
      final fresh = p.join(root.path, 'new');
      final elsewhere = p.join(root.path, 'elsewhere', 'z.png');
      state.addAll([fileAt(p.join(old, 'a.png')), fileAt(p.join(old, 'sub', 'b.png')), fileAt(elsewhere)]);
      state.setDestination(p.join(old, 'sub'));

      state.rewritePathPrefix(old, fresh);

      expect(state.items.map((f) => f.path), [
        p.join(fresh, 'a.png'),
        p.join(fresh, 'sub', 'b.png'),
        elsewhere,
      ]);
      expect(state.contains(p.join(fresh, 'a.png')), isTrue);
      expect(state.contains(p.join(old, 'a.png')), isFalse);
      expect(state.destination, p.join(fresh, 'sub'));

      // Persisted under the new paths, so the next launch restores them.
      final restored = FileStagingState();
      await restored.ready;
      expect(restored.items.map((f) => f.path), state.items.map((f) => f.path));
    });

    test('a prefix nothing points at changes nothing', () async {
      final state = FileStagingState();
      await state.ready;
      state.addAll([fileAt(p.join(root.path, 'a.png'))]);
      var notified = 0;
      state.addListener(() => notified++);

      state.rewritePathPrefix(p.join(root.path, 'unrelated'), p.join(root.path, 'other'));

      expect(notified, 0);
    });
  });

  group('FileBrowserState', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('joycai_browser_rewrite');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    /// A state whose lists came from the database, so what the test sees is
    /// what the app would restore.
    Future<FileBrowserState> stateWith(List<String> sources, List<String> active) async {
      final db = DatabaseService();
      await db.saveSetting('browser_source_directories', sources.join('|'));
      await db.saveSetting('browser_active_directories', active.join('|'));
      final state = FileBrowserState();
      await state.reloadSettings();
      return state;
    }

    test('rewritePathPrefix follows a renamed root and its active children', () async {
      final a = await Directory(p.join(root.path, 'a')).create();
      final aSub = await Directory(p.join(a.path, 'sub')).create();
      final b = await Directory(p.join(root.path, 'b')).create();
      final state = await stateWith([a.path, b.path], [aSub.path, b.path]);
      final renamed = p.join(root.path, 'a2');

      await state.rewritePathPrefix(a.path, renamed);

      expect(state.sourceDirectories, [renamed, b.path]);
      expect(state.activeDirectories, [p.join(renamed, 'sub'), b.path]);
      expect(await DatabaseService().getSetting('browser_source_directories'), '$renamed|${b.path}');
    });

    test('pruneRemoved drops active paths under a deleted folder and falls back to the parent',
        () async {
      final a = await Directory(p.join(root.path, 'a')).create();
      final gone = await Directory(p.join(a.path, 'gone')).create();
      final deep = await Directory(p.join(gone.path, 'deep')).create();
      final state = await stateWith([a.path], [deep.path]);

      await state.pruneRemoved(gone.path);

      expect(state.activeDirectories, [a.path]);
    });

    test('pruneRemoved leaves an unrelated active list alone', () async {
      final a = await Directory(p.join(root.path, 'a')).create();
      final state = await stateWith([a.path], [a.path]);
      var notified = 0;
      state.addListener(() => notified++);

      await state.pruneRemoved(p.join(root.path, 'elsewhere'));

      expect(state.activeDirectories, [a.path]);
      expect(notified, 0);
    });
  });
}
