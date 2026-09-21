import '../db/database_service.dart';

/// A resizable panel whose width survives a restart, and the `settings` row it
/// is kept in.
///
/// The key strings are the app's on-disk contract: users already have these
/// rows, so renaming one does not migrate a layout, it silently forgets it.
/// They appear in `lib/` only here.
enum UiPanel {
  /// File Browser's folder tree column.
  browserSidebar('browser_sidebar_width'),

  /// Models page's channel column.
  modelsSidebar('models_sidebar_width'),

  /// Prompt library's category column.
  promptsSidebar('prompts_sidebar_width'),

  /// Workbench's right-hand tool column. (The left one is `AppState.sidebarWidth`,
  /// which the state layer already owns under the `sidebar_width` key.)
  workbenchRightPanel('workbench_right_panel_width');

  const UiPanel(this.settingKey);

  /// The `settings.key` this panel's width is stored under.
  final String settingKey;
}

/// The one place a panel width is read from and written to the database.
///
/// `AppState` owns one, built over the same [DatabaseService] it hands every
/// sub-state; a screen asks `AppState.uiPrefs` and never reaches for a
/// [DatabaseService] of its own from `initState` or a drag callback. The key
/// strings live on [UiPanel] and nowhere else
/// (`test/architecture/panel_width_keys_scan_test.dart`).
///
/// The clamp belongs to the screen, not here: a panel's min and max are layout
/// facts of that screen, and the drag path clamps against the live constraints
/// anyway.
class UiPrefs {
  UiPrefs({DatabaseService? database}) : _db = database ?? DatabaseService();

  final DatabaseService _db;

  /// The stored width of [panel], or null when it was never saved or the row
  /// does not parse as a number.
  Future<double?> panelWidth(UiPanel panel) async =>
      double.tryParse(await _db.getSetting(panel.settingKey) ?? '');

  /// Stores [width] for [panel], rounded to whole pixels.
  Future<void> savePanelWidth(UiPanel panel, double width) =>
      _db.saveSetting(panel.settingKey, width.round().toString());
}
