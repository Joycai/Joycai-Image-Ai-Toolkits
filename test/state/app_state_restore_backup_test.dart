import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import '../support/private_data_dir.dart';
import '../support/real_async.dart';

/// A restore or a reset replaces whole tables, and every state that cached
/// one of them has to reload. The settings page used to do those reloads
/// itself and the setup wizard forgot two of them, so a backup imported from
/// the wizard left the gallery on the pre-import directories until a restart.
///
/// On the real [AppState]: it is the one that owns the sub-states a restore
/// has to reach, and a test-only instance is not an option (its constructor
/// registers a global log listener that is never removed).
void main() {
  usePrivateDataDir('joycai_app_state_restore_test');
  useRealAsyncAppState();

  late AppState appState;

  setUp(() => appState = AppState());

  /// A backup naming an output directory, one source directory and a browser
  /// preference — one setting for each of the three states a restore reloads.
  Map<String, dynamic> backup({required String outputDir, required String sourceDir}) => {
    'export_type': 'full_backup',
    'schema_version': DatabaseService.dbVersion,
    'settings': [
      {'key': 'output_directory', 'value': outputDir},
      {'key': 'browser_sort_ascending', 'value': 'true'},
      {'key': 'concurrency_limit', 'value': '4'},
    ],
    'llm_channels': const [],
    'llm_models': const [],
    'fee_groups': const [],
    'source_directories': [
      {'path': sourceDir, 'is_selected': 1},
    ],
  };

  test('restoreBackup reloads AppState, the gallery and the browser', () async {
    appState.fileBrowserState.sortAscending = false;

    await appState.restoreBackup(backup(outputDir: '/backup/out', sourceDir: '/backup/src'));

    expect(appState.concurrencyLimit, 4);
    expect(appState.galleryState.outputDirectory, '/backup/out');
    expect(appState.galleryState.sourceDirectories, ['/backup/src']);
    expect(appState.galleryState.activeSourceDirectories, ['/backup/src']);
    expect(appState.fileBrowserState.sortAscending, isTrue);
  });

  test('includeDirectories: false keeps the directories the app had', () async {
    await appState.restoreBackup(backup(outputDir: '/first/out', sourceDir: '/first/src'));

    await appState.restoreBackup(
      backup(outputDir: '/second/out', sourceDir: '/second/src'),
      includeDirectories: false,
    );

    // Only the source directories: `DatabaseService.restoreBackup` wipes the
    // settings table either way and, without directories, does not put
    // `output_directory` back — that is its behaviour, not this state's.
    expect(appState.galleryState.sourceDirectories, ['/first/src']);
    expect(appState.galleryState.activeSourceDirectories, ['/first/src']);
  });

  test('resetAllSettings clears the tables and the states follow', () async {
    await appState.restoreBackup(backup(outputDir: '/backup/out', sourceDir: '/backup/src'));

    await appState.resetAllSettings();

    expect(appState.galleryState.outputDirectory, isNull);
    expect(appState.galleryState.sourceDirectories, isEmpty);
    expect(await appState.getSetting('concurrency_limit'), isNull);
  });

  test('exportBackup is what restoreBackup reads', () async {
    await appState.restoreBackup(backup(outputDir: '/backup/out', sourceDir: '/backup/src'));

    final data = await appState.exportBackup();

    expect(data['export_type'], 'full_backup');
    expect((data['source_directories'] as List).map((r) => (r as Map)['path']), ['/backup/src']);
    expect(await appState.databasePath(), await DatabaseService().getDatabasePath());
  });
}
