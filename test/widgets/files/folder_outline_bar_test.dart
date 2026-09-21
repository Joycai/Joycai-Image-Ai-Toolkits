import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/files/folder_outline_bar.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';

/// The outline bar's width degradation, its taps and its menus (`A1b`).
///
/// Levels are asserted by *order*, never by the pixel widths they flip at:
/// flutter_test's placeholder font makes every glyph a full em, so a width
/// tuned here would be wrong in the app and wrong again in Japanese.
void main() {
  List<FolderOutlineEntry> entries(int n) => [
        for (var i = 0; i < n; i++)
          FolderOutlineEntry(
            path: '/w/folder_$i',
            label: 'folder_$i',
            count: 10 + i,
            unreachable: i == n - 1,
          ),
      ];

  Widget host({
    required double width,
    required List<FolderOutlineEntry> items,
    required ValueNotifier<int> current,
    ValueChanged<int>? onJump,
    ValueChanged<String>? onShowOnly,
    ValueChanged<String>? onReveal,
    FolderOutlineHost hostKind = FolderOutlineHost.opaque,
    bool forceCollapsed = false,
  }) =>
      MaterialApp(
        theme: buildAppTheme(
          accent: AppConstants.presetThemes.values.first,
          brightness: Brightness.light,
        ),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: FolderOutlineBar(
                entries: items,
                currentIndex: current,
                onJump: onJump ?? (_) {},
                host: hostKind,
                forceCollapsed: forceCollapsed,
                onShowOnly: onShowOnly,
                onRemove: (_) {},
                onReveal: onReveal,
                onReAuthorize: (_) {},
              ),
            ),
          ),
        ),
      );

  /// Which level the bar is showing, read off the tree.
  FolderOutlineLevel shown(WidgetTester tester) {
    if (find.byType(SingleChildScrollView).evaluate().isNotEmpty) {
      return FolderOutlineLevel.scroll;
    }
    if (find.textContaining('/').evaluate().isNotEmpty) {
      return FolderOutlineLevel.collapsed;
    }
    // Counts are the only two-digit mono texts in the row.
    return find.text('10').evaluate().isNotEmpty
        ? FolderOutlineLevel.full
        : FolderOutlineLevel.noCounts;
  }

  testWidgets('narrowing the bar walks the levels in the declared order',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final current = ValueNotifier<int>(0);
    addTearDown(current.dispose);
    final items = entries(9);

    final seen = <FolderOutlineLevel>[];
    for (var width = 2300.0; width >= 60; width -= 40) {
      await tester.pumpWidget(host(width: width, items: items, current: current));
      await tester.pumpAndSettle();
      final level = shown(tester);
      if (seen.isEmpty || seen.last != level) seen.add(level);
    }
    expect(seen, FolderOutlineLevel.values,
        reason: 'every level, once, in order: full → noCounts → scroll → collapsed');
  });

  testWidgets('the phone collapses without measuring', (tester) async {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final current = ValueNotifier<int>(1);
    addTearDown(current.dispose);

    await tester.pumpWidget(host(
      width: 2000,
      items: entries(4),
      current: current,
      forceCollapsed: true,
      hostKind: FolderOutlineHost.glassFloat,
    ));
    await tester.pumpAndSettle();
    expect(shown(tester), FolderOutlineLevel.collapsed);
    expect(find.text('2/4'), findsOneWidget);
    expect(find.text('folder_1'), findsOneWidget);
  });

  testWidgets('a tap jumps to that chip, and the lit chip follows the index',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final current = ValueNotifier<int>(0);
    addTearDown(current.dispose);
    final jumps = <int>[];

    await tester.pumpWidget(host(
      width: 2000,
      items: entries(4),
      current: current,
      onJump: jumps.add,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('folder_2'));
    expect(jumps, [2]);

    TextStyle styleOf(String label) =>
        tester.widget<Text>(find.text(label)).style!;
    expect(styleOf('folder_0').fontWeight, FontWeight.w600);
    expect(styleOf('folder_2').fontWeight, FontWeight.w500);

    current.value = 2;
    await tester.pumpAndSettle();
    expect(styleOf('folder_0').fontWeight, FontWeight.w500);
    expect(styleOf('folder_2').fontWeight, FontWeight.w600);
  });

  testWidgets('an unreachable chip shows the lock and no count', (tester) async {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final current = ValueNotifier<int>(0);
    addTearDown(current.dispose);

    await tester.pumpWidget(host(width: 2000, items: entries(3), current: current));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_person), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsNWidgets(2));
    // Counts 10 and 11 for the reachable two; 12 is the locked one's.
    expect(find.text('10'), findsOneWidget);
    expect(find.text('12'), findsNothing);
  });

  testWidgets('a secondary tap opens the chip menu; re-authorize replaces show-only on a locked chip',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final current = ValueNotifier<int>(0);
    addTearDown(current.dispose);
    final shownOnly = <String>[];

    await tester.pumpWidget(host(
      width: 2000,
      items: entries(3),
      current: current,
      onShowOnly: shownOnly.add,
      onReveal: (_) {},
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('folder_0'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byType(AppGlassMenu), findsOneWidget);
    expect(find.text('Show only this folder'), findsOneWidget);
    expect(find.text('Remove from view'), findsOneWidget);
    expect(find.text('Reveal in folder tree'), findsOneWidget);
    expect(find.textContaining('/w/folder_0 · 10 files'), findsOneWidget);

    await tester.tap(find.text('Show only this folder'));
    await tester.pumpAndSettle();
    expect(shownOnly, ['/w/folder_0']);
    expect(find.byType(AppGlassMenu), findsNothing);

    await tester.tap(find.text('folder_2'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Re-authorize'), findsOneWidget);
    expect(find.text('Show only this folder'), findsNothing);
  });

  testWidgets('the collapsed chip opens the list, and a row jumps', (tester) async {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final current = ValueNotifier<int>(0);
    addTearDown(current.dispose);
    final jumps = <int>[];

    await tester.pumpWidget(host(
      width: 2000,
      items: entries(4),
      current: current,
      forceCollapsed: true,
      onJump: jumps.add,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1/4'));
    await tester.pumpAndSettle();
    expect(find.byType(AppGlassMenu), findsOneWidget);
    expect(find.text('folder_3'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('folder_3'));
    await tester.pumpAndSettle();
    expect(jumps, [3]);
  });
}
