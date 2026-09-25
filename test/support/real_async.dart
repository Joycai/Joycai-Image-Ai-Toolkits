import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_async_database_rule.dart';

// The ways a widget test keeps its database calls out of `testWidgets`' fake
// clock — the rule `test/support/fake_async_database_rule.dart` enforces, and explains.

/// How long a wait here goes on before it fails the test: far longer than any
/// runner needs, so that it only ever means the thing is not going to happen.
const Duration realAsyncGiveUp = Duration(seconds: 30);

/// Builds the [AppState] singleton in `setUpAll`, which runs in real async.
///
/// Every sub-state reads its settings from its constructor, fire-and-forget,
/// so whoever says `AppState()` first decides which clock those reads run on.
/// Left to the first `testWidgets` body they start under the fake one. Call
/// from `main()`, after whatever points path_provider somewhere private
/// (`usePrivateDataDir`, `installFixtureEnv`).
void useRealAsyncAppState() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final AppState appState = AppState();
    await appState.galleryState.settingsLoaded;
    await appState.fileStagingState.ready;
    // The file browser's and the task queue's reads have no future to await.
    await databaseIdle();
  });
}

/// [WidgetTester.runAsync], except that what [body] throws is thrown here.
///
/// `runAsync` itself catches it, hands it to `FlutterError.reportError` and
/// returns null: the test carries on past a failed tap or a wait that gave up,
/// and fails — if nothing drains `takeException` first — somewhere else, about
/// something else.
///
/// Returns what [body] returns — `(await tester.runAsync(...))!` turns a throw
/// into a null-check error that names nothing.
Future<T> runAsyncRethrowing<T>(WidgetTester tester, Future<T> Function() body) async {
  Object? error;
  StackTrace? stack;
  late T result;
  await tester.runAsync(() async {
    try {
      result = await body();
    } catch (e, s) {
      error = e;
      stack = s;
    }
  });
  if (error case final Object e) Error.throwWithStackTrace(e, stack!);
  return result;
}

/// Completes once the database work already started has finished, along with
/// whatever further queries its results went on to start. Real async only.
///
/// sqflite's ffi worker answers every database's calls in the order they were
/// sent, so the reply to a query sent now arrives after the replies to all the
/// earlier ones; and a reply's continuation runs before the next reply is
/// delivered, so a query *it* starts has been counted by the time this one's
/// comes back. Round again until a round starts nothing.
///
/// What it counts is reads of `DatabaseService.database`, so two things get
/// past it. A chain with some other wait in the middle — a file read, a
/// `compute` — is over as far as this can tell once it gets there. And a
/// transaction reads the database once and then sends statement after
/// statement: this can return in the middle of one. It is for letting loads
/// land before a frame, not for the outcome of a write — assert that after
/// [inRealAsyncUntil].
Future<void> databaseIdle({Duration giveUpAfter = realAsyncGiveUp}) async {
  final Future<Database> opening = _barrier ??= databaseFactoryFfi.openDatabase(
    'file:joycai_test_barrier?mode=memory&cache=shared',
  );
  final Database barrier;
  try {
    barrier = await opening;
  } catch (_) {
    _barrier = null;
    rethrow;
  }
  // Something that polls the database never lets a round come back quiet.
  final DateTime giveUp = DateTime.now().add(giveUpAfter);
  int seen;
  int rounds = 0;
  // A worker that has answered once is not stuck: time running out after that,
  // even in the middle of a query, is the polling.
  Never gaveUp() => fail(
    rounds == 0
        ? 'the database worker never answered — a call ahead of this one is stuck'
        : 'the database never went quiet — something is polling it',
  );
  do {
    final Duration left = giveUp.difference(DateTime.now());
    if (left <= Duration.zero) gaveUp();
    seen = databaseAccesses;
    await barrier.rawQuery('SELECT 1').timeout(left, onTimeout: gaveUp);
    rounds++;
    await Future<void>.delayed(Duration.zero);
  } while (databaseAccesses != seen);
}

/// One for the isolate, left open: a test file is a process of its own.
Future<Database>? _barrier;

/// Runs [action] in real async *together with the frame it asks for*, then
/// leaves the caller to settle animations under the fake clock as usual.
///
/// For an action that reaches the database — a key that persists a setting, a
/// tab switch that mounts a panel which loads on mount. The frame is the part
/// that is easy to leave outside: the action only marks the tree dirty, and
/// it is the next pump that mounts the new panel and runs the post-frame
/// callback that starts its query.
///
/// The second frame draws what [databaseIdle] waited for. [wait] is extra, for
/// loads that are not the database's (a folder scan, an image decode), and for
/// what they draw, not for safety: started out here, work finishes on its own
/// however late it is.
Future<void> inRealAsync(
  WidgetTester tester,
  FutureOr<void> Function() action, {
  Duration wait = Duration.zero,
}) => runAsyncRethrowing<void>(tester, () async {
  await action();
  await tester.pump();
  await databaseIdle();
  if (wait > Duration.zero) await Future<void>.delayed(wait);
  await tester.pump();
});

/// [WidgetTester.pumpWidget] for a tree whose `initState`s read the database:
/// the first frame, and the loads it starts, happen in real async.
Future<void> pumpWidgetInRealAsync(
  WidgetTester tester,
  Widget widget, {
  Duration wait = Duration.zero,
}) => inRealAsync(tester, () => tester.pumpWidget(widget), wait: wait);

/// [inRealAsync], but waiting for [until] — what the database work [action]
/// started ends in — instead of for the database to go quiet. For a chain the
/// test goes on to assert the outcome of: several round trips, then a dialog,
/// a removed row, a changed list.
///
/// Frames are pumped while waiting, so [until] may be a finder. They carry no
/// duration, so animations still belong to the fake clock: settle afterwards.
Future<void> inRealAsyncUntil(
  WidgetTester tester,
  FutureOr<void> Function() action, {
  required bool Function() until,
  Duration giveUpAfter = realAsyncGiveUp,
}) => runAsyncRethrowing<void>(tester, () async {
  await action();
  final DateTime giveUp = DateTime.now().add(giveUpAfter);
  while (true) {
    await tester.pump();
    if (until()) return;
    if (DateTime.now().isAfter(giveUp)) {
      fail('the work the action started never reached the state waited for');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
});
