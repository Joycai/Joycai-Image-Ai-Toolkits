// One rule, enforced for the whole suite — installed by both
// `flutter_test_config.dart` files (test/ and test/screenshots/, which has its
// own because flutter_test takes the nearest one): **no database call starts
// under `testWidgets`' fake clock.**
//
// A call that does is a race with the runner's disk, and it loses only on a
// slow one — which is why this read as two unrelated Linux-CI flakes for a
// while. Its sqflite reply arrives on the real event loop, but its
// continuation is a microtask of the fake zone, so it moves only when the
// test pumps *after* the reply is in:
//
//  - a fixed number of pumps is a bet on how fast the reply comes back (the
//    cookie-history row that was "still on screen");
//  - the query's ten-second lock watchdog is a fake timer nothing cancels if
//    the test ends first ("A Timer is still pending even after the widget
//    tree was disposed");
//  - and a query still in flight when the test ends never continues at all,
//    so sqflite's lock is never released and the next test to touch the
//    database waits on it forever.
//
// None of that depends on timing once the call is made out in real async, so
// that is where it has to be made: build `AppState()` in `setUpAll`, and put
// an action that reaches the database — *and the frame it asks for*, which is
// what mounts a panel that loads on mount — inside `tester.runAsync`. The
// helpers for all of it are in `real_async.dart`, beside this file. The check
// below turns
// a violation into a failure on every machine, every run, with the stack of
// the call that made it.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';

/// Call from a `testExecutable`, before `testMain`.
void installFakeAsyncDatabaseRule() {
  final List<String> underFakeAsync = <String>[];

  DatabaseService.debugOnDatabaseAccess = () {
    if (!_clockIsFake()) return;
    final String frames = StackTrace.current
        .toString()
        .split('\n')
        .where((String l) => l.contains('package:joycai_image_ai_toolkits/') && !l.contains('database_service.dart'))
        .take(4)
        .map((String l) => l.replaceFirst(RegExp(r'^#\d+\s+'), ''))
        .join('\n      ');
    underFakeAsync.add(frames.isEmpty ? '(no app frame — called straight from the test)' : frames);
  };

  setUp(underFakeAsync.clear);
  tearDown(() {
    if (underFakeAsync.isEmpty) return;
    final String report = underFakeAsync.toSet().join('\n  -   ');
    underFakeAsync.clear();
    fail('A database call started under fake async — see test/support/fake_async_database_rule.dart.\n'
        'Make it in real async: AppState() in setUpAll, the action and its frame in tester.runAsync.\n'
        '  -   $report');
  });
}

/// Whether a timer made here would belong to `testWidgets`' fake clock.
///
/// Asked of a timer rather than of the binding because that is the fact that
/// matters — sqflite's watchdog is made the same way — and because the binding
/// keeps whether it is inside `runAsync` to itself. `fake_async` is not a
/// dependency of this package, hence the type's name rather than the type.
bool _clockIsFake() {
  final Timer timer = Timer(Duration.zero, () {});
  final bool fake = timer.runtimeType.toString().contains('Fake');
  timer.cancel();
  return fake;
}
