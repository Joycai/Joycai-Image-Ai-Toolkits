import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/in_memory_database.dart';
import '../support/private_data_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  usePrivateDataDir('joycai_gallery_sort_test');

  late Directory root;
  late Directory alpha;
  late Directory beta;
  late Directory output;

  setUp(() {
    root = Directory.systemTemp.createTempSync('joycai_gallery_sort');
    beta = Directory(p.join(root.path, 'beta'))..createSync();
    alpha = Directory(p.join(root.path, 'Alpha'))..createSync();
    output = Directory(p.join(root.path, 'output'))..createSync();

    final t0 = DateTime(2026, 6, 1, 12, 0);
    for (final (dir, name, minutes) in [
      (beta, 'b_clip.mp4', 0),
      (alpha, 'a_second.jpg', 1),
      (beta, 'b_first.png', 2),
      (alpha, 'a_first.png', 3),
      (alpha, 'a_video.mp4', 4),
      (output, 'out_old.png', 10),
      (output, 'out_new.jpg', 20),
    ]) {
      final file = File(p.join(dir.path, name))..writeAsStringSync('x');
      file.setLastModifiedSync(t0.add(Duration(minutes: minutes)));
    }
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Temp directory cleanup is best-effort on Windows.
    }
  });

  List<String> names(List<AppImage> images) => [for (final i in images) i.name];

  test('sorts grouped folders by date, name, and type while keeping folder order', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));

    final state = GalleryState(database: db);
    addTearDown(state.dispose);
    await state.settingsLoaded;
    state.sourceDirectories = [beta.path, alpha.path];
    state.activeSourceDirectories = [beta.path, alpha.path];
    state.outputDirectory = output.path;
    await state.refreshImages();

    // Default: date descending, grouped by folder (Alpha before beta).
    expect(state.sortField, GallerySortField.date);
    expect(state.sortAscending, isFalse);
    expect(state.groupByFolder, isTrue);
    expect(names(state.galleryImages), [
      'a_video.mp4',
      'a_first.png',
      'a_second.jpg',
      'b_first.png',
      'b_clip.mp4',
    ]);
    expect(names(state.processedImages), ['out_new.jpg', 'out_old.png']);

    // Flipping direction reverses files inside each folder, not the folders.
    final beforeDir = state.galleryImages;
    await state.setSortAscending(true);
    expect(identical(state.galleryImages, beforeDir), isFalse);
    expect(names(state.galleryImages), [
      'a_second.jpg',
      'a_first.png',
      'a_video.mp4',
      'b_clip.mp4',
      'b_first.png',
    ]);
    expect(names(state.processedImages), ['out_old.png', 'out_new.jpg']);

    // Sort by name ascending.
    await state.setSortField(GallerySortField.name);
    expect(names(state.galleryImages), [
      'a_first.png',
      'a_second.jpg',
      'a_video.mp4',
      'b_clip.mp4',
      'b_first.png',
    ]);

    // Sort by type ascending: images (.jpg before .png) before videos (.mp4).
    await state.setSortField(GallerySortField.type);
    expect(names(state.galleryImages), [
      'a_second.jpg',
      'a_first.png',
      'a_video.mp4',
      'b_first.png',
      'b_clip.mp4',
    ]);
  });

  test('ungrouping interleaves files across folders and replaces list identity', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));

    final state = GalleryState(database: db);
    addTearDown(state.dispose);
    await state.settingsLoaded;
    state.sourceDirectories = [beta.path, alpha.path];
    state.activeSourceDirectories = [beta.path, alpha.path];
    await state.refreshImages();

    final grouped = state.galleryImages;
    await state.setGroupByFolder(false);
    expect(identical(state.galleryImages, grouped), isFalse);
    expect(names(state.galleryImages), [
      'a_video.mp4',
      'a_first.png',
      'b_first.png',
      'a_second.jpg',
      'b_clip.mp4',
    ]);

    await state.setSortAscending(true);
    expect(names(state.galleryImages), [
      'b_clip.mp4',
      'a_second.jpg',
      'b_first.png',
      'a_first.png',
      'a_video.mp4',
    ]);
  });

  test('folder view and workspace respect sort; timeless workspace entries keep order', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));

    final state = GalleryState(database: db);
    addTearDown(state.dispose);
    await state.settingsLoaded;

    // Timeless synthetic dropped items keep insertion order under default date sort.
    state.addDroppedFiles([
      for (var i = 0; i < 40; i++) AppImage(path: '/nowhere/$i.png', name: '$i.png'),
    ]);
    expect(names(state.droppedImages).take(5), ['0.png', '1.png', '2.png', '3.png', '4.png']);

    // Real workspace files sort by modification time and name.
    state.clearDroppedImages();
    final f1 = await AppImage.fromPathAsync(p.join(alpha.path, 'a_second.jpg'));
    final f2 = await AppImage.fromPathAsync(p.join(alpha.path, 'a_first.png'));
    state.addDroppedFiles([f1, f2]);
    expect(names(state.droppedImages), ['a_first.png', 'a_second.jpg']);

    await state.setSortField(GallerySortField.name);
    await state.setSortAscending(false);
    expect(names(state.droppedImages), ['a_second.jpg', 'a_first.png']);

    state.setViewFolder(alpha.path);
    await state.refreshImages();
    expect(names(state.folderImages), ['a_video.mp4', 'a_second.jpg', 'a_first.png']);
  });

  test('sort preferences persist across reload', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));

    final first = GalleryState(database: db);
    await first.settingsLoaded;
    await first.setSortField(GallerySortField.type);
    await first.setSortAscending(true);
    await first.setGroupByFolder(false);
    first.dispose();

    final second = GalleryState(database: db);
    addTearDown(second.dispose);
    await second.settingsLoaded;
    expect(second.sortField, GallerySortField.type);
    expect(second.sortAscending, isTrue);
    expect(second.groupByFolder, isFalse);

    // Clearing settings (e.g. reset or restoring an older backup without
    // gallery_sort_* keys) must reset to defaults and re-sort cached lists.
    final rawDb = await db.database;
    await rawDb.delete('settings');
    final f1 = await AppImage.fromPathAsync(p.join(alpha.path, 'a_second.jpg'));
    final f2 = await AppImage.fromPathAsync(p.join(alpha.path, 'a_first.png'));
    second.addDroppedFiles([f1, f2]);
    expect(names(second.droppedImages), ['a_second.jpg', 'a_first.png']);

    await second.reloadSettings();
    expect(second.sortField, GallerySortField.date);
    expect(second.sortAscending, isFalse);
    expect(second.groupByFolder, isTrue);
    expect(names(second.droppedImages), ['a_first.png', 'a_second.jpg']);
  });
}
