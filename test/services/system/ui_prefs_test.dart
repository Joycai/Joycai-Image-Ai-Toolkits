import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/system/ui_prefs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// [UiPrefs] is the only place in `lib/` that knows a panel width lives in the
/// `settings` table, and the only place the four key strings appear. Both
/// halves matter: the screens used to call `DatabaseService()` themselves, and
/// the keys are an on-disk contract — a renamed one does not migrate a user's
/// layout, it silently forgets it.
void main() {
  sqfliteFfiInit();

  late DatabaseService db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() async => closeTestDatabase(db));

  group('panelWidth', () {
    test('is null when nothing was ever saved', () async {
      final prefs = UiPrefs(database: db);
      for (final panel in UiPanel.values) {
        expect(await prefs.panelWidth(panel), isNull, reason: panel.name);
      }
    });

    test('round-trips a saved width', () async {
      final prefs = UiPrefs(database: db);
      await prefs.savePanelWidth(UiPanel.browserSidebar, 317);
      expect(await prefs.panelWidth(UiPanel.browserSidebar), 317);
    });

    test('is null when the stored row does not parse as a number', () async {
      await db.saveSetting(UiPanel.modelsSidebar.settingKey, 'wide-ish');
      expect(await UiPrefs(database: db).panelWidth(UiPanel.modelsSidebar), isNull);
    });

    test('reads the injected database, not the singleton', () async {
      final other = await openTestDatabase();
      addTearDown(() => closeTestDatabase(other));
      await other.saveSetting(UiPanel.promptsSidebar.settingKey, '199');

      expect(await UiPrefs(database: db).panelWidth(UiPanel.promptsSidebar), isNull);
      expect(await UiPrefs(database: other).panelWidth(UiPanel.promptsSidebar), 199);
    });
  });

  group('savePanelWidth', () {
    test('rounds to whole pixels', () async {
      final prefs = UiPrefs(database: db);
      await prefs.savePanelWidth(UiPanel.browserSidebar, 240.4);
      expect(await db.getSetting(UiPanel.browserSidebar.settingKey), '240');

      await prefs.savePanelWidth(UiPanel.browserSidebar, 240.5);
      expect(await db.getSetting(UiPanel.browserSidebar.settingKey), '241');
    });

    test('writes the injected database, not the singleton', () async {
      final other = await openTestDatabase();
      addTearDown(() => closeTestDatabase(other));

      await UiPrefs(database: other).savePanelWidth(UiPanel.workbenchRightPanel, 420);

      expect(await other.getSetting(UiPanel.workbenchRightPanel.settingKey), '420');
      expect(await db.getSetting(UiPanel.workbenchRightPanel.settingKey), isNull);
    });

    test('each panel writes its own row and reads back only its own', () async {
      final prefs = UiPrefs(database: db);
      final widths = <UiPanel, double>{
        UiPanel.browserSidebar: 201,
        UiPanel.modelsSidebar: 202,
        UiPanel.promptsSidebar: 203,
        UiPanel.workbenchRightPanel: 204,
      };
      for (final entry in widths.entries) {
        await prefs.savePanelWidth(entry.key, entry.value);
      }
      for (final entry in widths.entries) {
        expect(await prefs.panelWidth(entry.key), entry.value, reason: entry.key.name);
      }
    });
  });

  test('the key strings are exactly the rows users already have on disk', () {
    expect(
      {for (final panel in UiPanel.values) panel: panel.settingKey},
      {
        UiPanel.browserSidebar: 'browser_sidebar_width',
        UiPanel.modelsSidebar: 'models_sidebar_width',
        UiPanel.promptsSidebar: 'prompts_sidebar_width',
        UiPanel.workbenchRightPanel: 'workbench_right_panel_width',
      },
    );
  });
}
