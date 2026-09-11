import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/workbench_glass_toolbar.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_layout.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_dialog.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// Covers the workbench's floating glass toolbar (`A1 · 1a`) as its own width
/// shrinks.
///
/// The bar decides what to show by measuring its own contents against its own
/// width — never by screen breakpoint, because what squeezes it is the centre
/// column, and never by a pixel constant, because its labels come in four
/// languages. So what is pinned here is the *order* things give way in, not
/// the widths they give way at:
///
/// 1. the tool and mode labels go;
/// 2. import, refresh, fit and size fold into the overflow menu;
/// 3. the tools collapse into a Tools menu;
/// 4. the view switch never gives way — it scrolls inside what is left.
///
/// A note on widths: flutter_test lays text out in a placeholder font whose
/// every glyph is a full em, so labels here measure roughly twice their real
/// width. The sweep is conservative for it; the widths themselves mean
/// nothing outside this file.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_workbench_glass_toolbar_test');

  final barKey = GlobalKey();

  /// Renders the toolbar at [barWidth] inside a desktop-sized window, which is
  /// the situation that matters: a wide screen, a squeezed centre column.
  Future<AppState> pumpAtWidth(
    WidgetTester tester,
    double barWidth, {
    int workspaceCount = 0,
    bool phone = false,
    int tab = WorkbenchTab.image,
  }) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Not disposed: the tree outlives the pump (see the other widget tests).
    final appState = AppState();
    if (workspaceCount > 0) {
      appState.galleryState.addDroppedFiles([
        for (var i = 0; i < workspaceCount; i++)
          AppImage(path: '/tmp/workspace_$i.png', name: 'workspace_$i.png'),
      ]);
      appState.galleryState.setViewMode(GalleryViewMode.temp);
    }

    final tabController = TabController(length: 6, vsync: const TestVSync(), initialIndex: tab);
    addTearDown(tabController.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: appState.galleryState),
          Provider<WorkbenchLayoutState>.value(
            value: WorkbenchLayoutState(
              GlobalKey<ScaffoldState>(),
              contentWidth: phone ? barWidth : 1400,
              leftInDrawer: false,
              rightInDrawer: false,
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: barKey,
                width: barWidth,
                child: WorkbenchGlassToolbar(tabController: tabController, phone: phone),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return appState;
  }

  bool toolLabelsShown() => find.text('Compare').evaluate().isNotEmpty;
  bool refreshInline() => find.byTooltip('Refresh').evaluate().isNotEmpty;
  bool toolsCollapsed() =>
      find.text('Tools').evaluate().isNotEmpty ||
      find.byIcon(Icons.handyman_outlined).evaluate().isNotEmpty;

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  testWidgets('a roomy bar lays everything out inline, labels and all', (tester) async {
    await pumpAtWidth(tester, 1700);

    expect(tester.takeException(), isNull);
    expect(toolLabelsShown(), isTrue);
    expect(refreshInline(), isTrue);
    expect(find.byTooltip('Thumbnail Size'), findsOneWidget);
    expect(find.byTooltip('Import from Gallery'), findsOneWidget);
    expect(toolsCollapsed(), isFalse);
  });

  testWidgets('a squeezed bar collapses to its floor without overflowing', (tester) async {
    await pumpAtWidth(tester, 420);

    expect(tester.takeException(), isNull);
    expect(toolLabelsShown(), isFalse);
    expect(refreshInline(), isFalse);
    expect(toolsCollapsed(), isTrue);
  });

  testWidgets('things give way in the declared order at every width', (tester) async {
    // Labels before icons, icons before tools: stated as "never this
    // combination" so it holds whatever widths the font puts the steps at.
    for (var width = 420.0; width <= 1700.0; width += 20) {
      await pumpAtWidth(tester, width);

      expect(tester.takeException(), isNull, reason: 'Overflow at ${width}px');
      expect(toolLabelsShown() && !refreshInline(), isFalse,
          reason: 'At ${width}px an icon folded while the labels were still shown');
      expect(toolsCollapsed() && refreshInline(), isFalse,
          reason: 'At ${width}px the tools collapsed while refresh was still inline');

      // The view switch is never pushed outside the bar.
      final bar = tester.getRect(find.byKey(barKey));
      final toggle = tester.getRect(find.text('All Sources'));
      expect(toggle.left, greaterThanOrEqualTo(bar.left - 0.01), reason: 'at ${width}px');
      expect(bar.right + 0.01, greaterThanOrEqualTo(tester.getRect(find.byTooltip('More')).right),
          reason: 'More fell off the bar at ${width}px');
    }
  });

  testWidgets('the overflow menu reaches every action the bar folded', (tester) async {
    await pumpAtWidth(tester, 420);
    await openMore(tester);

    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Thumbnail Size'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Import from Gallery'), findsOneWidget);
    expect(find.text('Fit (whole image)'), findsOneWidget);
    expect(find.text('Fill (cropped)'), findsOneWidget);
  });

  testWidgets('the collapsed tools menu still offers every tool by its full name', (tester) async {
    await pumpAtWidth(tester, 420);

    await tester.tap(find.byIcon(Icons.handyman_outlined).evaluate().isNotEmpty
        ? find.byIcon(Icons.handyman_outlined)
        : find.text('Tools'));
    await tester.pumpAndSettle();

    for (final name in ['Comparator', 'Mask Editor', 'Crop & Resize', 'Prompt Assistant']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('the workspace view gets its own segment and can be cleared, with a question', (tester) async {
    final appState = await pumpAtWidth(tester, 1700, workspaceCount: 3);

    expect(find.text('Workspace'), findsOneWidget);

    await openMore(tester);
    await tester.tap(find.text('Clear Workspace'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(appState.galleryState.droppedImages, hasLength(3), reason: 'asked, not done');

    await tester.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Clear Workspace')));
    await tester.pumpAndSettle();
    expect(appState.galleryState.droppedImages, isEmpty);
  });

  testWidgets('clear workspace is not offered outside the workspace view', (tester) async {
    await pumpAtWidth(tester, 1700);
    await openMore(tester);

    expect(find.text('Clear Workspace'), findsNothing);
  });

  testWidgets('the thumbnail dialog slider follows the drag it caused', (tester) async {
    // Carried over from the old gallery toolbar: the handle used to spring
    // back to where the dialog opened while the grid kept resizing.
    await pumpAtWidth(tester, 420);
    await openMore(tester);
    await tester.tap(find.text('Thumbnail Size'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    final before = tester.widget<Slider>(find.byType(Slider)).value;
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    final after = tester.widget<Slider>(find.byType(Slider)).value;

    expect(after, greaterThan(before));
    expect(find.text('${after.toInt()}px'), findsOneWidget);
  });

  testWidgets('the phone bar fits a phone', (tester) async {
    for (final width in [360.0, 390.0, 430.0]) {
      await pumpAtWidth(tester, width, phone: true);
      expect(tester.takeException(), isNull, reason: 'Overflow at ${width}px');
    }
  });

  testWidgets('tool tabs show back and the tool switch, and never overflow', (tester) async {
    for (var width = 300.0; width <= 1000.0; width += 50) {
      await pumpAtWidth(tester, width, tab: WorkbenchTab.crop);
      expect(tester.takeException(), isNull, reason: 'Overflow at ${width}px');
      expect(find.byTooltip('Back'), findsOneWidget);
    }
  });
}
