import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/state/file_browser_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/files/file_visuals.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/in_memory_database.dart';
import '../support/private_data_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // GalleryState also initializes its platform result cache on macOS/iOS.
  usePrivateDataDir('joycai_image_refresh_cache');

  test('gallery refresh versions source, result, folder and dropped images', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));
    final dir = await Directory.systemTemp.createTemp('joycai_image_refresh');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'image.png'));
    await file.writeAsString('before');
    final state = GalleryState(database: db);
    addTearDown(state.dispose);
    await state.settingsLoaded;
    state.sourceDirectories = [dir.path];
    state.activeSourceDirectories = [dir.path];
    state.outputDirectory = dir.path;
    state.viewMode = GalleryViewMode.folder;
    state.viewSourcePath = dir.path;
    state.addDroppedFiles([AppImage.fromFile(file)]);

    await state.refreshImages();
    final before = state.galleryImages.single.imageProvider;
    await state.refreshImages();
    expect(
      state.galleryImages.single.imageProvider,
      before,
      reason: 'unchanged files reuse decodes',
    );

    final modified = await file.lastModified();
    await file.writeAsString('replaced with different bytes');
    await file.setLastModified(modified);
    await state.refreshImages();
    for (final images in [
      state.galleryImages,
      state.processedImages,
      state.folderImages,
      state.droppedImages,
    ]) {
      expect(images.single.imageProvider, isNot(before));
      expect(images.single.version, state.galleryImages.single.version);
    }
  });

  test('browser refresh changes provider when size changes with timestamp preserved', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));
    final dir = await Directory.systemTemp.createTemp('joycai_browser_refresh');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'image.png'));
    await file.writeAsString('before');
    final state = FileBrowserState(database: db);
    addTearDown(state.dispose);
    await state.reloadSettings();
    state.sourceDirectories = [dir.path];
    state.activeDirectories = [dir.path];

    await state.refresh();
    final before = state.allFiles.single.imageProvider;
    await state.refresh();
    expect(state.allFiles.single.imageProvider, before);
    final modified = await file.lastModified();
    await file.writeAsString('replacement');
    await file.setLastModified(modified);
    await state.refresh();
    expect(state.allFiles.single.imageProvider, isNot(before));
  });
}
