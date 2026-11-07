import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('v53 upgrade preserves rows and explicit downgrade refusal preserves the version', () async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('joycai-version-barrier-');
    addTearDown(() => root.delete(recursive: true));
    final path = p.join(root.path, 'test.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 53,
        singleInstance: false,
        onCreate: (db, _) => DatabaseMigration.onCreate(db),
      ),
    );
    await old.insert('settings', {'key': 'synthetic', 'value': 'preserve'});
    await old.close();
    final upgraded = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DatabaseService.dbVersion,
        singleInstance: false,
        onUpgrade: DatabaseMigration.migrate,
      ),
    );
    expect((await upgraded.query('settings')).single['value'], 'preserve');
    await upgraded.close();
    await expectLater(
      databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 53,
          singleInstance: false,
          onDowngrade: DatabaseMigration.rejectDowngrade,
        ),
      ),
      throwsStateError,
    );
    final verify = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    expect(await verify.getVersion(), DatabaseService.dbVersion);
    expect((await verify.query('settings')).single['value'], 'preserve');
    await verify.close();
  });
}
