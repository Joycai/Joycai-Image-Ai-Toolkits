import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// A panel has one way of saying where it came from, and that is the corner
  /// it grows out of. The corner on the point is not always the top-left: a
  /// dropdown is laid right-edge-to-right-edge under its button, and a menu
  /// near a window edge is flipped to the other side of the click.
  Alignment originOf(WidgetTester tester) {
    final ScaleTransition scale = tester.widget(
      find.ancestor(of: find.byType(AppGlassMenu), matching: find.byType(ScaleTransition)),
    );
    return scale.alignment;
  }

  testWidgets('a right-click menu grows out of the pointer, top-left', (tester) async {
    await pumpHost(tester);
    await open(tester, [AppGlassMenuItem(label: 'One', onSelected: () {})]);
    expect(originOf(tester), Alignment.topLeft);
  });

  testWidgets('a dropdown under a button grows out of its top-right corner', (tester) async {
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

    // The helper lays the menu's *right* edge on the button's right edge, so
    // the corner on the button is the top-right one.
    showAppGlassMenuBelow(
      tester.element(find.byKey(anchorKey)),
      entries: [AppGlassMenuItem(label: 'One', onSelected: () {})],
    );
    await tester.pumpAndSettle();
    expect(originOf(tester), Alignment.topRight);
  });

  testWidgets('a menu flipped at the corner grows out of the corner it was flipped onto',
      (tester) async {
    await pumpHost(tester);
    await open(tester, [
      AppGlassMenuItem(label: 'One', onSelected: () {}),
      AppGlassMenuItem(label: 'Two', onSelected: () {}),
    ], at: const Offset(780, 580));

    // Same click as the flip test above: both edges land on the pointer, so
    // the panel must grow up and to the left, out of its bottom-right corner.
    expect(originOf(tester), Alignment.bottomRight);
  });

  // `A1 · 2a`: a row with children opens a second panel beside the menu, 4px
  // out from its edge, whose first row is level with the row that opened it.
  List<AppGlassMenuEntry> withSubmenu({VoidCallback? onRename}) => [
        AppGlassMenuItem(label: 'One', onSelected: () {}),
        AppGlassMenuItem(label: 'Two', onSelected: () {}),
        AppGlassMenuItem(label: 'File', children: [
          AppGlassMenuItem(label: 'Rename', onSelected: onRename ?? () {}),
          AppGlassMenuItem(label: 'Copy name', onSelected: () {}),
        ]),
      ];

  Rect submenuRect(WidgetTester tester) =>
      tester.getRect(find.ancestor(of: find.text('Rename'), matching: find.byType(AppGlassMenu)));

  testWidgets('a submenu opens beside the menu, level with its row, and its action runs after the pop',
      (tester) async {
    await pumpHost(tester);
    var ran = false;
    await open(tester, withSubmenu(onRename: () => ran = true));
    expect(find.byType(AppGlassMenu), findsOneWidget);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.byType(AppGlassMenu), findsNWidgets(2));

    final Rect menu = tester.getRect(find.byType(AppGlassMenu).first);
    final Rect sub = submenuRect(tester);
    expect(sub.left, closeTo(menu.right + 4, 0.01), reason: 'submenu $sub is not 4px right of the menu $menu');
    expect(sub.width, kAppGlassSubmenuWidth);
    expect(
      tester.getTopLeft(find.text('Rename')).dy,
      closeTo(tester.getTopLeft(find.text('File')).dy, 0.01),
      reason: 'the first submenu row is not level with the row that opened it',
    );

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(ran, isTrue);
    expect(find.byType(AppGlassMenu), findsNothing);
  });

  testWidgets('the submenu follows the pointer: opens on its row, survives the crossing, closes on another row',
      (tester) async {
    await pumpHost(tester);
    await open(tester, withSubmenu());

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.text('File')));
    await tester.pumpAndSettle();
    expect(find.byType(AppGlassMenu), findsNWidgets(2), reason: 'hovering the row did not open its submenu');

    await gesture.moveTo(tester.getCenter(find.text('Copy name')));
    await tester.pumpAndSettle();
    expect(find.byType(AppGlassMenu), findsNWidgets(2), reason: 'crossing into the submenu closed it');

    await gesture.moveTo(tester.getCenter(find.text('One')));
    await tester.pumpAndSettle();
    expect(find.byType(AppGlassMenu), findsOneWidget, reason: 'hovering another row left the submenu open');
  });

  testWidgets('→ opens a submenu from the keyboard and ← closes it again', (tester) async {
    await pumpHost(tester);
    await open(tester, [
      AppGlassMenuItem(label: 'File', children: [
        AppGlassMenuItem(label: 'Rename', onSelected: () {}),
      ]),
    ]);

    // The first enabled row has focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.byType(AppGlassMenu), findsNWidgets(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byType(AppGlassMenu), findsOneWidget);
  });

  testWidgets('a submenu that would run off the right edge opens on the left instead', (tester) async {
    await pumpHost(tester);
    // 500 + 230 + 4 + 200 runs past an 800 window: the panel goes left.
    await open(tester, withSubmenu(), at: const Offset(500, 100));
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    final Rect menu = tester.getRect(find.byType(AppGlassMenu).first);
    final Rect sub = submenuRect(tester);
    expect(sub.right, closeTo(menu.left - 4, 0.01), reason: 'submenu $sub did not flip to the left of $menu');
  });

  testWidgets('quick cells and grid cells run their action after the pop, like rows', (tester) async {
    await pumpHost(tester);
    String? ran;
    await open(tester, [
      AppGlassMenuQuickBlock([
        AppGlassMenuQuickCell(icon: Icons.visibility_outlined, label: 'Preview', onSelected: () => ran = 'preview'),
        AppGlassMenuQuickCell(icon: Icons.brush_outlined, label: 'Mask', onSelected: () => ran = 'mask'),
      ]),
      const AppGlassMenuDivider(),
      const AppGlassMenuHeading('Set as'),
      AppGlassMenuGrid([
        AppGlassMenuItem(label: 'Before', onSelected: () => ran = 'before'),
        AppGlassMenuItem(label: 'After', onSelected: () => ran = 'after'),
        AppGlassMenuItem(label: 'First frame', onSelected: () => ran = 'first'),
      ]),
    ]);

    expect(find.text('Set as'), findsOneWidget);
    // Two across: the second cell sits beside the first, the third under it.
    expect(tester.getTopLeft(find.text('After')).dy, closeTo(tester.getTopLeft(find.text('Before')).dy, 0.01));
    expect(tester.getTopLeft(find.text('First frame')).dy, greaterThan(tester.getTopLeft(find.text('Before')).dy));
    expect(tester.getTopLeft(find.text('First frame')).dx, closeTo(tester.getTopLeft(find.text('Before')).dx, 0.01));

    await tester.tap(find.text('Mask'));
    await tester.pumpAndSettle();
    expect(ran, 'mask');
    expect(find.byType(AppGlassMenu), findsNothing);

    await open(tester, [
      AppGlassMenuGrid([
        AppGlassMenuItem(label: 'Before', onSelected: () => ran = 'before'),
        AppGlassMenuItem(label: 'After', onSelected: () => ran = 'after'),
      ]),
    ]);
    await tester.tap(find.text('After'));
    await tester.pumpAndSettle();
    expect(ran, 'after');
  });

  test('the measured height counts a quick block, a heading and a grid the way they are drawn', () {
    final entries = <AppGlassMenuEntry>[
      AppGlassMenuQuickBlock([
        AppGlassMenuQuickCell(icon: Icons.visibility_outlined, label: 'Preview', onSelected: () {}),
      ]),
      const AppGlassMenuHeading('Set as'),
      AppGlassMenuGrid([
        AppGlassMenuItem(label: 'A', onSelected: () {}),
        AppGlassMenuItem(label: 'B', onSelected: () {}),
        AppGlassMenuItem(label: 'C', onSelected: () {}),
      ]),
    ];
    // 6 + 6 of padding, 48, 20, two ranks of 28 with 2 between.
    expect(appGlassMenuHeight(entries), 12 + 48 + 20 + 28 * 2 + 2);
  });
}
