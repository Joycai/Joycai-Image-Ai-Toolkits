// Runs around every test file under test/ — except those in test/screenshots/,
// which has a config of its own (flutter_test takes the nearest one).

import 'dart:async';

import 'support/fake_async_database_rule.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  installFakeAsyncDatabaseRule();
  await testMain();
}
