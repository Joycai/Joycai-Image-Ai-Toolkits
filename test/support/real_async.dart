import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// The ways a widget test keeps its database calls out of `testWidgets`' fake
// clock — the rule `test/support/fake_async_database_rule.dart` enforces, and explains.

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
    // Out here a late one is only late: it owns no fake timer and finishes on
    // its own, so this wait is for a quiet start, not for correctness.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
}

/// Runs [action] in real async *together with the frame it asks for*, then
/// leaves the caller to settle animations under the fake clock as usual.
///
/// For an action that reaches the database — a key that persists a setting, a
/// tab switch that mounts a panel which loads on mount. The frame is the part
/// that is easy to leave outside: the action only marks the tree dirty, and
/// it is the next pump that mounts the new panel and runs the post-frame
/// callback that starts its query.
///
/// [wait] is for what the loads draw, not for safety: started out here a
/// query finishes on its own however late it is.
Future<void> inRealAsync(
  WidgetTester tester,
  FutureOr<void> Function() action, {
  Duration wait = const Duration(milliseconds: 300),
}) async {
  await tester.runAsync(() async {
    await action();
    await tester.pump();
    await Future<void>.delayed(wait);
    await tester.pump();
  });
}

/// [WidgetTester.pumpWidget] for a tree whose `initState`s read the database:
/// the first frame, and the loads it starts, happen in real async.
Future<void> pumpWidgetInRealAsync(
  WidgetTester tester,
  Widget widget, {
  Duration wait = const Duration(milliseconds: 300),
}) =>
    inRealAsync(tester, () => tester.pumpWidget(widget), wait: wait);

/// [inRealAsync], but waiting for [until] — what the database work [action]
/// started ends in — instead of for a length of time. For a chain the test
/// goes on to assert the outcome of: several round trips, then a dialog, a
/// removed row, a changed list.
///
/// Frames are pumped while waiting, so [until] may be a finder. They carry no
/// duration, so animations still belong to the fake clock: settle afterwards.
Future<void> inRealAsyncUntil(
  WidgetTester tester,
  FutureOr<void> Function() action, {
  required bool Function() until,
  Duration giveUpAfter = const Duration(seconds: 30),
}) async {
  await tester.runAsync(() async {
    await action();
    final DateTime giveUp = DateTime.now().add(giveUpAfter);
    while (true) {
      await tester.pump();
      if (until()) return;
      if (DateTime.now().isAfter(giveUp)) fail('the work the action started never reached the state waited for');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
}
