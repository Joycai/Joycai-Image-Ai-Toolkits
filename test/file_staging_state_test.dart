import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/state/file_staging_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the file browser's staging area — the marks, not the transfer.
///
/// The one invariant worth a test file: this list outlives everything the
/// browser prunes. The selection is dropped on every refresh, filter and sort,
/// so if staging behaved like the selection the feature would not exist.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Persistence is the point of half of these tests, so the real database is
  // used rather than mocked away.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => Directory.systemTemp.path,
  );

  late Directory root;

  BrowserFile fileAt(Directory dir, String name) => BrowserFile(
        path: p.join(dir.path, name),
        name: name,
        category: BrowserFile.categoryOf(name),
        size: 10,
        modified: DateTime(2026, 1, 1),
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('joycai_staging');
    // Awaited, not fire-and-forget: the instance built below reads this key
    // while constructing, and a leftover list from the previous test would
    // race it.
    await DatabaseService().saveSetting(FileStagingState.settingsKey, '');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<FileStagingState> freshState() async {
    final state = FileStagingState();
    await state.ready;
    return state;
  }

  test('marks are appended in the order they were added, without duplicates',
      () async {
    final state = await freshState();
    final a = fileAt(root, 'a.png');
    final b = fileAt(root, 'b.png');

    state.addAll([a, b]);
    state.addAll([a]);

    expect(state.count, 2);
    expect(state.items.map((f) => f.name), ['a.png', 'b.png']);
    expect(state.contains(a.path), isTrue);
  });

  test('adding nothing new does not notify', () async {
    // Guards the grid: every card watches this state, so a no-op add that
    // still notified would rebuild the whole listing on a repeated click.
    final state = await freshState();
    final a = fileAt(root, 'a.png');
    state.addAll([a]);

    var notifications = 0;
    state.addListener(() => notifications++);
    state.addAll([a]);

    expect(notifications, 0);
  });

  test('removing takes out one mark and leaves the rest', () async {
    final state = await freshState();
    state.addAll([fileAt(root, 'a.png'), fileAt(root, 'b.png')]);

    state.remove(p.join(root.path, 'a.png'));

    expect(state.items.map((f) => f.name), ['b.png']);
    expect(state.contains(p.join(root.path, 'a.png')), isFalse);
  });

  test('clearing empties the list', () async {
    final state = await freshState();
    state.addAll([fileAt(root, 'a.png'), fileAt(root, 'b.png')]);

    state.clear();

    expect(state.isEmpty, isTrue);
    expect(state.stagedPaths, isEmpty);
  });

  test('source directories are distinct and in first-seen order', () async {
    // What the panel groups by, and the reason the paste destination has to be
    // named explicitly rather than inferred: with two entries here there is no
    // "the folder these came from".
    final state = await freshState();
    final one = await Directory(p.join(root.path, 'one')).create();
    final two = await Directory(p.join(root.path, 'two')).create();

    state.addAll([fileAt(one, 'a.png'), fileAt(two, 'b.png'), fileAt(one, 'c.png')]);

    expect(state.sourceDirectories, [one.path, two.path]);
  });

  test('total bytes sums the staged files', () async {
    final state = await freshState();
    state.addAll([fileAt(root, 'a.png'), fileAt(root, 'b.png')]);

    expect(state.totalBytes, 20);
  });

  group('revalidate', () {
    test('refreshes sizes from disk and finds nothing missing', () async {
      final state = await freshState();
      final file = File(p.join(root.path, 'a.png'));
      await file.writeAsString('12345');
      state.addAll([fileAt(root, 'a.png')]);

      await state.revalidate();

      expect(state.hasMissing, isFalse);
      // The staged snapshot said 10; the disk says 5, and the disk wins.
      expect(state.items.single.size, 5);
    });

    test('marks a file that went away, and keeps it in the list', () async {
      // Kept rather than dropped: a list that silently got shorter is how the
      // user loses track of what they staged.
      final state = await freshState();
      state.addAll([fileAt(root, 'ghost.png')]);

      await state.revalidate();

      expect(state.count, 1);
      expect(state.isMissing(p.join(root.path, 'ghost.png')), isTrue);
    });

    test('removeMissing drops exactly the gone ones', () async {
      final state = await freshState();
      await File(p.join(root.path, 'here.png')).writeAsString('x');
      state.addAll([fileAt(root, 'here.png'), fileAt(root, 'ghost.png')]);
      await state.revalidate();

      state.removeMissing();

      expect(state.items.map((f) => f.name), ['here.png']);
      expect(state.hasMissing, isFalse);
    });
  });

  group('persistence', () {
    test('marks come back after a restart', () async {
      // The feature is "stage here, paste somewhere else later"; a list that
      // did not survive the app being closed would break the "later".
      final state = await freshState();
      await File(p.join(root.path, 'a.png')).writeAsString('123');
      state.addAll([fileAt(root, 'a.png')]);
      // The write is fire-and-forget, so give it the microtask turn it needs
      // before reading the key back through a second instance.
      await Future<void>.delayed(Duration.zero);

      final restored = await freshState();

      expect(restored.items.map((f) => f.name), ['a.png']);
      expect(restored.contains(p.join(root.path, 'a.png')), isTrue);
    });

    test('a restored mark whose file is gone comes back marked missing',
        () async {
      await DatabaseService().saveSetting(
        FileStagingState.settingsKey,
        p.join(root.path, 'ghost.png'),
      );

      final restored = await freshState();

      expect(restored.count, 1);
      expect(restored.isMissing(p.join(root.path, 'ghost.png')), isTrue);
    });

    test('clearing is persisted too', () async {
      final state = await freshState();
      state.addAll([fileAt(root, 'a.png')]);
      state.clear();
      await Future<void>.delayed(Duration.zero);

      final restored = await freshState();

      expect(restored.isEmpty, isTrue);
    });
  });

  group('restored notice', () {
    test('counts what came back, and stops claiming it once the user edits',
        () async {
      // The line says how the panel got its contents, not what is in it. After
      // an add it is no longer describing the list on screen.
      await DatabaseService().saveSetting(
        FileStagingState.settingsKey,
        [p.join(root.path, 'a.png'), p.join(root.path, 'b.png')].join('\n'),
      );

      final state = await freshState();
      expect(state.restoredCount, 2);

      state.addAll([fileAt(root, 'c.png')]);

      expect(state.restoredCount, 0);
    });

    test('a session that staged its own files never claims a restore', () async {
      final state = await freshState();
      state.addAll([fileAt(root, 'a.png')]);

      expect(state.restoredCount, 0);
    });
  });

  group('destination', () {
    test('starts unset and notifies when named', () async {
      // Unset is the honest starting value: the browser shows several folders
      // merged, so there is no current one to default to.
      final state = await freshState();
      expect(state.destination, isNull);

      var notifications = 0;
      state.addListener(() => notifications++);
      state.setDestination(root.path);

      expect(state.destination, root.path);
      expect(notifications, 1);
    });

    test('naming the same folder twice does not notify', () async {
      final state = await freshState();
      state.setDestination(root.path);

      var notifications = 0;
      state.addListener(() => notifications++);
      state.setDestination(root.path);

      expect(notifications, 0);
    });

    test('is not persisted across a restart', () async {
      // A destination carried over from a previous session is a stale answer
      // to a question the user has not asked yet.
      final state = await freshState();
      state.setDestination(root.path);
      await Future<void>.delayed(Duration.zero);

      final restored = await freshState();

      expect(restored.destination, isNull);
    });
  });
}
