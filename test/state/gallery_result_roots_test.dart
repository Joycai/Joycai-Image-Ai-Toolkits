import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/in_memory_database.dart';
import '../support/private_data_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  usePrivateDataDir('joycai_result_roots');

  test('result roots exclude legacy files without deleting them or recovery metadata', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));
    final root = await Directory.systemTemp.createTemp('joycai_result_roots');
    addTearDown(() => root.delete(recursive: true));
    final output = await Directory(p.join(root.path, 'output')).create();
    final legacy = await Directory(p.join(root.path, 'legacy', 'results')).create(recursive: true);
    final oldFile = await File(p.join(legacy.path, 'old.png')).writeAsString('keep original');
    await db.saveSetting('output_directory', output.path);
    await db.saveSetting('legacy_result_cache_directory', legacy.path);

    final state = GalleryState(database: db);
    addTearDown(state.dispose);
    await state.settingsLoaded;
    final cache = state.resultCacheDirectory;
    expect(state.resultRootDirectories, [output.path, ?cache]);
    await state.refreshImages();
    expect(state.processedImages, isEmpty);
    expect(await oldFile.readAsString(), 'keep original');
    expect(await db.getSetting('legacy_result_cache_directory'), legacy.path);

    // The list identity stays stable for selectors until either root changes.
    final before = state.resultRootDirectories;
    expect(identical(before, state.resultRootDirectories), isTrue);
    state.resultCacheDirectory = output.path;
    expect(state.resultRootDirectories, [output.path]);
    expect(identical(before, state.resultRootDirectories), isFalse);
    state.outputDirectory = '';
    expect(state.resultRootDirectories, [output.path]);
    state.resultCacheDirectory = null;
    expect(state.resultRootDirectories, isEmpty);
  });
}
