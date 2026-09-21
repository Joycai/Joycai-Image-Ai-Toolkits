// Pins what `real_async.dart`'s helpers promise, since every widget test that
// reaches the database now stands on them.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'in_memory_database.dart';
import 'real_async.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('what a runAsync body throws is thrown at the call', (WidgetTester tester) async {
    await expectLater(
      runAsyncRethrowing(tester, () async => throw StateError('from the body')),
      throwsStateError,
    );
    // And not parked as well, to fail the test a second time at its end.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wait that gives up fails where it was made', (WidgetTester tester) async {
    await expectLater(
      inRealAsyncUntil(
        tester,
        () {},
        until: () => false,
        giveUpAfter: const Duration(milliseconds: 50),
      ),
      throwsA(isA<TestFailure>()),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an action that throws fails inRealAsync', (WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await expectLater(
      inRealAsync(tester, () => tester.tap(find.text('not on screen'))),
      throwsA(anything),
    );
  });

  testWidgets('databaseIdle outlasts a chain of queries', (WidgetTester tester) async {
    late DatabaseService db;
    await tester.runAsync(() async => db = await openTestDatabase());

    int finished = 0;
    // Each query is started by the reply to the one before, as a load that
    // reads a setting and then the rows it names is.
    Future<void> chain() async {
      for (int i = 0; i < 5; i++) {
        await (await db.database).rawQuery('SELECT 1');
        finished++;
      }
    }

    await runAsyncRethrowing(tester, () async {
      // ignore: unawaited_futures
      chain();
      await databaseIdle();
    });
    expect(finished, 5);
    await tester.runAsync(() => closeTestDatabase(db));
  });

  testWidgets('databaseIdle gives up on something that polls', (WidgetTester tester) async {
    late DatabaseService db;
    await tester.runAsync(() async => db = await openTestDatabase());

    bool polling = true;
    // Once per turn of the event loop, so no round of the wait misses it.
    Future<void> poll() async {
      while (polling) {
        await db.database;
        await Future<void>.delayed(Duration.zero);
      }
    }

    await expectLater(
      runAsyncRethrowing(tester, () async {
        // ignore: unawaited_futures
        poll();
        try {
          await databaseIdle(giveUpAfter: const Duration(milliseconds: 100));
        } finally {
          polling = false;
        }
      }),
      throwsA(isA<TestFailure>().having((TestFailure f) => f.message, 'message', contains('polling'))),
    );
    await tester.runAsync(() => closeTestDatabase(db));
  });
}
