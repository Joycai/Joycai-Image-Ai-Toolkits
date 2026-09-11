import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';

/// The one glass context menu every screen opens (`AppGlassMenu`).
///
/// Four screens used to carry their own copy of this route, each with a
/// slightly different contract for when the chosen action runs. What is
/// pinned here is the contract they now share.
void main() {
  late BuildContext host;

  Future<void> pumpHost(WidgetTester tester, {Size size = const Size(800, 600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          host = context;
          return const SizedBox.expand();
        }),
      ),
    ));
  }

  Future<void> open(WidgetTester tester, List<AppGlassMenuEntry> entries, {Offset at = const Offset(100, 100)}) async {
    showAppGlassMenu(host, position: at, entries: entries);
    await tester.pumpAndSettle();
  }

  testWidgets('the chosen action runs once the menu is no longer the current route', (tester) async {
    await pumpHost(tester);
    bool? hostWasCurrent;
    await open(tester, [
      AppGlassMenuItem(
        label: 'Rename',
        onSelected: () => hostWasCurrent = ModalRoute.of(host)!.isCurrent,
      ),
    ]);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    // Popped first, then run: a dialog the action opens goes on top of the
    // page, not under a menu that is still the current route. (The menu may
    // still be fading out underneath it, as Material's own menus do.)
    expect(hostWasCurrent, isTrue, reason: 'the action ran while the menu was still the current route');
    expect(find.byType(AppGlassMenu), findsNothing);
  });

  testWidgets('a disabled row does nothing and can say why', (tester) async {
    await pumpHost(tester);
    var ran = false;
    await open(tester, [
      AppGlassMenuItem(label: 'Move to…', note: 'Root folders cannot be moved', enabled: false, onSelected: () => ran = true),
      AppGlassMenuItem(label: 'Delete', onSelected: () {}),
    ]);

    expect(find.text('Root folders cannot be moved'), findsOneWidget);
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();

    expect(ran, isFalse);
    expect(find.byType(AppGlassMenu), findsOneWidget, reason: 'tapping a disabled row closed the menu');
  });

  testWidgets('a row with no action is disabled, and its note shows', (tester) async {
    await pumpHost(tester);
    await open(tester, const [
      AppGlassMenuItem(label: 'Nothing to do', note: 'why', onSelected: null),
    ]);

    expect(find.text('why'), findsOneWidget);
  });

  testWidgets('dividers draw between rows and the trailing hint shows', (tester) async {
    await pumpHost(tester);
    await open(tester, [
      AppGlassMenuItem(label: 'Rename', trailing: 'F2', onSelected: () {}),
      const AppGlassMenuDivider(),
      AppGlassMenuItem(label: 'Delete', danger: true, onSelected: () {}),
    ]);

    expect(find.text('F2'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('tapping outside dismisses without running anything', (tester) async {
    await pumpHost(tester);
    var ran = false;
    await open(tester, [AppGlassMenuItem(label: 'Rename', onSelected: () => ran = true)]);

    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();

    expect(find.byType(AppGlassMenu), findsNothing);
    expect(ran, isFalse);
  });

  testWidgets('a menu opened near the corner flips to the other side of the click', (tester) async {
    await pumpHost(tester);
    const click = Offset(780, 580);
    await open(tester, [
      AppGlassMenuItem(label: 'One', onSelected: () {}),
      AppGlassMenuItem(label: 'Two', onSelected: () {}),
    ], at: click);

    final rect = tester.getRect(find.byType(AppGlassMenu));
    expect(rect.right, lessThanOrEqualTo(click.dx + 0.01), reason: 'menu $rect ran past the click horizontally');
    expect(rect.bottom, lessThanOrEqualTo(click.dy + 0.01), reason: 'menu $rect ran past the click vertically');
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('the position below an anchor puts the right edges together', (tester) async {
    final anchorKey = GlobalKey();
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(key: anchorKey, width: 32, height: 32),
        ),
      ),
    ));

    final anchor = tester.element(find.byKey(anchorKey));
    final position = appGlassMenuPositionBelow(anchor, width: 210);
    final box = tester.getRect(find.byKey(anchorKey));
    expect(position.dx + 210, closeTo(box.right, 0.01));
    expect(position.dy, closeTo(box.bottom + 4, 0.01));
  });
}
