import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/cookie_repository.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/task_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// S3: the downloader's cookies live as long as the user said, can be
/// removed one by one or all at once, and never land in a task row.
void main() {
  sqfliteFfiInit();

  final now = DateTime(2026, 9, 16, 12);

  // A database of this file's own, in memory: nothing here needs the app's
  // file, and a test file that does not open it cannot contend with the other
  // test files running beside it for its write lock.
  late DatabaseService db;
  late CookieRepository repo;
  late TaskRepository tasks;

  setUp(() async {
    db = await openTestDatabase();
    repo = CookieRepository(db: db);
    tasks = TaskRepository(db: db);
  });

  tearDown(() async => closeTestDatabase(db));

  test('30 days by default: an older row is dropped when the history is read', () async {
    expect(await repo.retention(), CookieRetention.month);
    await repo.save('old.example', 'a=1', now: now.subtract(const Duration(days: 31)));
    await repo.save('new.example', 'b=2', now: now.subtract(const Duration(days: 2)));

    final hosts = [for (final r in await repo.list(now: now)) r['host']];
    expect(hosts, ['new.example']);
    expect(await repo.lookup('old.example', now: now), isNull);
    expect(await repo.lookup('new.example', now: now), 'b=2');
  });

  test('7 days is shorter; until-cleared keeps everything', () async {
    await repo.setRetention(CookieRetention.week);
    await repo.save('a.example', 'a=1', now: now.subtract(const Duration(days: 8)));
    expect(await repo.list(now: now), isEmpty);

    await repo.setRetention(CookieRetention.untilCleared);
    await repo.save('b.example', 'b=1', now: now.subtract(const Duration(days: 400)));
    expect(await repo.list(now: now), hasLength(1));
  });

  test('off writes nothing and forgets what was kept', () async {
    await repo.save('a.example', 'a=1', now: now);
    await repo.setRetention(CookieRetention.off);
    expect(await repo.list(now: now), isEmpty);
    await repo.save('b.example', 'b=1', now: now);
    expect(await repo.list(now: now), isEmpty);
  });

  test('at most five hosts, newest kept', () async {
    for (var i = 0; i < 7; i++) {
      await repo.save('h$i.example', 'c=$i', now: now.add(Duration(minutes: i)));
    }
    final hosts = [for (final r in await repo.list(now: now)) r['host']];
    expect(hosts, ['h6.example', 'h5.example', 'h4.example', 'h3.example', 'h2.example']);
  });

  test('one host can be removed, or all of them', () async {
    await repo.save('a.example', 'a=1', now: now);
    await repo.save('b.example', 'b=1', now: now);
    await repo.delete('a.example');
    expect([for (final r in await repo.list(now: now)) r['host']], ['b.example']);
    await repo.clear();
    expect(await repo.list(now: now), isEmpty);
  });

  group('task rows', () {
    TaskItem download(String id, Map<String, dynamic> params) => TaskItem(
          id: id,
          type: TaskType.imageDownload,
          imagePaths: const [],
          modelId: 'm',
          parameters: params,
          createdAt: now,
        );

    Future<Map<String, dynamic>> storedParams(String id) async {
      final rows = await (await db.database)
          .query('tasks', where: 'id = ?', whereArgs: [id]);
      return jsonDecode(rows.single['parameters'] as String) as Map<String, dynamic>;
    }

    test('a saved download keeps everything but its cookies', () async {
      await tasks.saveTask(download('t1', {'url': 'https://a.example/p', 'cookies': 'sid=1', 'prefix': 'x'}));
      final params = await storedParams('t1');
      expect(params.containsKey('cookies'), isFalse);
      expect(params['url'], 'https://a.example/p');
      expect(params['prefix'], 'x');
    });

    test('rows written before the rule are scrubbed', () async {
      await (await db.database).insert(
          'tasks', download('t2', {'url': 'u', 'cookies': 'sid=2'}).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      await tasks.scrubStoredCookies();
      expect((await storedParams('t2')).containsKey('cookies'), isFalse);
    });

    test('a download queued without cookies keeps saying so', () async {
      await tasks.saveTask(download('t3', {'url': 'https://a.example/p', 'cookies': ''}));
      expect((await storedParams('t3'))['cookies'], '',
          reason: 'a missing key would make a restored task borrow the saved cookies');
      await tasks.scrubStoredCookies();
      expect((await storedParams('t3'))['cookies'], '');
    });

    test('parameters that are not JSON are left alone', () {
      expect(CookieRepository.withoutCookies('not json'), 'not json');
      expect(CookieRepository.withoutCookies('{"a":1}'), '{"a":1}');
    });
  });
}
