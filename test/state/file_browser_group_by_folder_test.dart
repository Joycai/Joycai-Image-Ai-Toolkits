import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/file_browser_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/private_data_dir.dart';

/// With several folders listed, the browser can lay the files out folder by
/// folder — the precondition for a folder outline to have anywhere to jump.
/// The list stays flat, so everything that reads its order (Shift ranges,
/// select-all) keeps working across the folder boundaries.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_group_by_folder_test');

  late Directory root;
  late Directory beta;
  late Directory alpha;

  setUp(() {
    root = Directory.systemTemp.createTempSync('joycai_group');
    // Named so that path order (alpha < beta) disagrees with creation order
    // and with the date sort, which is what makes the grouping visible.
    beta = Directory(p.join(root.path, 'beta'))..createSync();
    alpha = Directory(p.join(root.path, 'Alpha'))..createSync();
    final t0 = DateTime(2026, 1, 1);
    for (final (dir, name, minutes) in [
      (beta, 'b1.png', 0),
      (alpha, 'a1.png', 1),
      (beta, 'b2.png', 2),
      (alpha, 'a2.png', 3),
      (alpha, 'a3.png', 4),
    ]) {
      final file = File(p.join(dir.path, name))..writeAsStringSync('x');
      file.setLastModifiedSync(t0.add(Duration(minutes: minutes)));
    }
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // The OS reaps temp dirs anyway.
    }
  });

  Future<FileBrowserState> loadedState() async {
    final state = FileBrowserState();
    await state.reloadSettings();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return state;
  }

  List<String> names(FileBrowserState s) =>
      s.filteredFiles.map((f) => f.name).toList();

  test('two folders, grouping on: folder order first, then the sort', () async {
    final state = await loadedState();
    addTearDown(state.dispose);
    state.setSortField(BrowserSortField.date);
    state.setSortAscending(false);
    state.activeDirectories = [beta.path, alpha.path];
    await state.refresh();

    expect(state.isGrouped, isTrue);
    // Alpha before beta regardless of the date direction; newest first inside.
    expect(names(state), ['a3.png', 'a2.png', 'a1.png', 'b2.png', 'b1.png']);
    expect(state.folderSections, [
      (path: alpha.path, start: 0, count: 3),
      (path: beta.path, start: 3, count: 2),
    ]);
  });

  test('flipping the direction reverses files, not folders', () async {
    final state = await loadedState();
    addTearDown(state.dispose);
    state.activeDirectories = [beta.path, alpha.path];
    state.setSortField(BrowserSortField.date);
    state.setSortAscending(true);
    await state.refresh();

    expect(names(state), ['a1.png', 'a2.png', 'a3.png', 'b1.png', 'b2.png']);
    expect(state.folderSections.map((s) => s.path), [alpha.path, beta.path]);
  });

  test('grouping off interleaves the folders as before', () async {
    final state = await loadedState();
    addTearDown(state.dispose);
    state.activeDirectories = [beta.path, alpha.path];
    state.setSortField(BrowserSortField.date);
    state.setSortAscending(true);
    await state.refresh();
    final grouped = state.filteredFiles;

    state.setGroupByFolder(false);
    expect(state.isGrouped, isFalse);
    expect(names(state), ['b1.png', 'a1.png', 'b2.png', 'a2.png', 'a3.png']);
    expect(state.folderSections, isEmpty);
    // A new list, so a selector holding the old one sees the change.
    expect(identical(state.filteredFiles, grouped), isFalse);

    state.setGroupByFolder(true);
    expect(names(state), ['a1.png', 'a2.png', 'a3.png', 'b1.png', 'b2.png']);
  });

  test('a single folder never groups', () async {
    final state = await loadedState();
    addTearDown(state.dispose);
    state.activeDirectories = [alpha.path];
    await state.refresh();

    expect(state.groupByFolder, isTrue);
    expect(state.isGrouped, isFalse);
    expect(state.folderSections, isEmpty);
  });

  test('the filter narrows sections and drops emptied folders', () async {
    final state = await loadedState();
    addTearDown(state.dispose);
    state.activeDirectories = [beta.path, alpha.path];
    state.setSortField(BrowserSortField.name);
    state.setSortAscending(true);
    await state.refresh();

    state.setSearchQuery('b');
    expect(names(state), ['b1.png', 'b2.png']);
    expect(state.folderSections, [(path: beta.path, start: 0, count: 2)]);

    state.setSearchQuery('');
    expect(state.folderSections.length, 2);
  });

  test('a Shift range runs across the folder boundary in list order', () async {
    final state = await loadedState();
    addTearDown(state.dispose);
    state.activeDirectories = [beta.path, alpha.path];
    state.setSortField(BrowserSortField.name);
    state.setSortAscending(true);
    await state.refresh();
    // a1 a2 a3 | b1 b2
    state.toggleSelection(state.filteredFiles[1]);
    state.selectRangeTo(state.filteredFiles[3]);

    expect(
      state.selectedFiles.map((f) => f.name).toSet(),
      {'a2.png', 'a3.png', 'b1.png'},
    );
  });

  test('the preference survives a reload', () async {
    final state = await loadedState();
    state.setGroupByFolder(false);
    state.dispose();

    final again = await loadedState();
    addTearDown(again.dispose);
    expect(again.groupByFolder, isFalse);
    again.setGroupByFolder(true);
  });
}
