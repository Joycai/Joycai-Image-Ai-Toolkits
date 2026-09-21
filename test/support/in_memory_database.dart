import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An empty database of the current schema, in this isolate's memory, wrapped
/// in the [DatabaseService] every state class, service and repository accepts
/// on its constructor.
///
/// The alternative — the default [DatabaseService] — is a singleton over one
/// real file that every concurrently running test file names, which is the
/// whole reason `usePrivateDataDir` exists. A test that injects this instead
/// touches no file at all, so it cannot contend for that write lock, cannot
/// see a row a neighbouring file wrote, and needs no temp directory:
///
/// ```dart
/// late DatabaseService db;
/// setUp(() async => db = await openTestDatabase());
/// tearDown(() async => closeTestDatabase(db));
///
/// test('...', () async {
///   final state = TaskListState(database: db);
/// });
/// ```
///
/// Call [sqfliteFfiInit] once from `main()`'s body first, as every database
/// test here already does. The schema is built by [DatabaseMigration.onCreate]
/// — the same call the real database's `onCreate` makes — so the tables match
/// the app's exactly; what is *not* run is `DatabaseService.syncPresets()`, so
/// a test that expects the shipped preset rows has to insert them itself.
Future<DatabaseService> openTestDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(
    'file:joycai_test_db_${++_opened}?mode=memory&cache=shared',
    options: OpenDatabaseOptions(
      version: DatabaseService.dbVersion,
      onCreate: (db, _) => DatabaseMigration.onCreate(db),
    ),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  return DatabaseService.forDatabase(db);
}

/// Names each database apart from the last.
///
/// The bare `:memory:` path does **not** do this: sqflite hands every opener
/// in an isolate the same anonymous database, so a `setUp` that opened one per
/// test would have each test reading the rows the last one left — and closing
/// it in `tearDown` would close it under whatever still held it. A named
/// `mode=memory` URI is a database of its own, and is freed when its last
/// connection goes.
int _opened = 0;

/// Closes what [openTestDatabase] opened.
///
/// A separate function because [DatabaseService] deliberately has no close:
/// the one it wraps in production lives as long as the process does.
Future<void> closeTestDatabase(DatabaseService service) async =>
    (await service.database).close();
