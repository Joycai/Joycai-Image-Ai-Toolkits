import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/file_browser_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// What a folder scan that lands after a newer one is allowed to do.
///
/// The bug this pins: only the scanning *flag* was guarded by the scan's
/// generation. A superseded scan still assigned `allFiles` and re-sorted, so
/// the listing of directories the user had already turned off came back —
/// and a scan finishing after the state was disposed notified a disposed
/// ChangeNotifier.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_scan_race_test');

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('joycai_scan_race');
    for (var i = 0; i < 60; i++) {
      File(p.join(dir.path, 'f$i.png')).writeAsStringSync('x');
    }
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // The OS reaps temp dirs anyway.
    }
  });

  /// A state whose constructor has finished loading its settings, so the load's
  /// own refresh cannot be mistaken for one of the scans under test.
  Future<FileBrowserState> loadedState() async {
    final state = FileBrowserState();
    await state.reloadSettings();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return state;
  }

  test('a scan superseded by a newer one does not replace its listing', () async {
    final state = await loadedState();

    state.activeDirectories = [dir.path];
    final superseded = state.refresh();
    // The user turns the folder off while that scan is still out. This refresh
    // has nothing to list, so it finishes first and wins.
    state.activeDirectories = [];
    await state.refresh();
    await superseded;

    expect(state.allFiles, isEmpty,
        reason: 'the superseded scan put the turned-off folder back');
    expect(state.isScanning, isFalse);
    state.dispose();
  });

  test('a scan landing after dispose is dropped instead of notifying', () async {
    final state = await loadedState();

    state.activeDirectories = [dir.path];
    final pending = state.refresh();
    state.dispose();

    await pending; // used to throw: notifyListeners() on a disposed state
  });

  test('refresh after dispose does nothing', () async {
    final state = await loadedState();
    state.dispose();

    state.activeDirectories = [dir.path];
    await state.refresh();
  });
}
