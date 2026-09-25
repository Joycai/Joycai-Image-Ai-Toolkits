import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/image_layer.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/image_layer_repository.dart';
import 'package:joycai_image_ai_toolkits/services/files/file_rename_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// A file rename carries the file's layer rows along, and only once the file
/// has actually moved. This used to be two calls inside the rename dialog.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseService db;
  late ImageLayerRepository layers;
  late Directory dir;

  setUp(() async {
    db = await openTestDatabase();
    layers = ImageLayerRepository(db: db);
    // The repository's path index is process-wide: start it from this database.
    await layers.loadPaths();
    dir = Directory.systemTemp.createTempSync('joycai_file_rename_service');
  });

  tearDown(() async {
    dir.deleteSync(recursive: true);
    await closeTestDatabase(db);
  });

  /// A two-layer set on disk and in the table.
  Future<(String base, String top)> saveSet() async {
    final base = p.join(dir.path, 'base.png');
    final top = p.join(dir.path, 'top.png');
    File(base).createSync();
    File(top).createSync();
    await layers.save(ImageLayer(path: base, setId: 'set', zIndex: 0, name: 'base'));
    await layers.save(
      ImageLayer(path: top, setId: 'set', zIndex: 1, name: 'top', box: const LayerBox(0, 0, 1, 1)),
    );
    return (base, top);
  }

  test('renames the file and moves its layer row with it', () async {
    final (base, top) = await saveSet();

    final renamed = await FileRenameService.rename(top, 'overlay.png', database: db);

    expect(renamed, p.join(dir.path, 'overlay.png'));
    expect(File(renamed).existsSync(), isTrue);
    expect(File(top).existsSync(), isFalse);
    final set = await layers.setFor(base);
    expect(set!.layers.map((l) => l.path), [base, renamed]);
    expect(ImageLayerRepository.layeredPaths.value.keys, containsAll([base, renamed]));
    expect(ImageLayerRepository.layeredPaths.value, isNot(contains(top)));
  });

  test('a rename the disk refuses leaves the layer rows where they were', () async {
    final (base, top) = await saveSet();
    // The row stays; the file goes, so the rename itself is what fails. A
    // path with no row would pass this whichever order the two steps ran in.
    File(top).deleteSync();

    await expectLater(
      FileRenameService.rename(top, 'moved.png', database: db),
      throwsA(isA<FileSystemException>()),
    );

    expect(ImageLayerRepository.layeredPaths.value.keys, containsAll([base, top]));
    expect(ImageLayerRepository.layeredPaths.value, isNot(contains(p.join(dir.path, 'moved.png'))));
    final rows = await (await db.database).query('image_layers', columns: ['path']);
    expect(rows.map((r) => r['path']), containsAll([base, top]));
  });
}
