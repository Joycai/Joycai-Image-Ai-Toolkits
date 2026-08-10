import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_side_panel.dart';

/// Covers the panel shell the prompt library and prompt history share.
///
/// Both used to carry their own copy of this: the same 46-line
/// `isNarrow ? showModalBottomSheet : showGeneralDialog` branch and the same
/// 450px shadowed container, duplicated verbatim. These pin the behaviour
/// that duplication was hiding, so the next panel inherits it rather than
/// re-deriving it.
void main() {
  Future<void> pumpAndOpen(WidgetTester tester, Size size, {Locale? locale}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => AppSidePanel.show<void>(
                  context,
                  builder: (context) => const Text('panel body'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a wide window gets a panel of the shared width', (tester) async {
    await pumpAndOpen(tester, const Size(1400, 900));

    expect(find.text('panel body'), findsOneWidget);
    expect(tester.getSize(find.byType(AppSidePanel)).width, appSidePanelWidth);
  });

  testWidgets('the wide panel is pinned to the right edge, full height', (tester) async {
    // The point of a side panel over a dialog: it can be as tall as the
    // window and leaves the work it belongs to visible beside it.
    await pumpAndOpen(tester, const Size(1400, 900));

    final panel = tester.getRect(find.byType(AppSidePanel));
    expect(panel.right, 1400);
    expect(panel.height, 900);
  });

  testWidgets('a narrow window gets a bottom sheet spanning the width', (tester) async {
    await pumpAndOpen(tester, const Size(400, 800));

    expect(find.text('panel body'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(tester.getSize(find.byType(AppSidePanel)).width, 400,
        reason: 'the sheet kept the desktop panel width on a phone');
  });

  testWidgets('tapping outside the panel closes it', (tester) async {
    await pumpAndOpen(tester, const Size(1400, 900));

    expect(tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).dismissible, isTrue);

    await tester.tapAt(const Offset(100, 450));
    await tester.pumpAndSettle();
    expect(find.text('panel body'), findsNothing);
  });

  testWidgets('the barrier announces itself in the reader\'s own language', (tester) async {
    // The two copies hardcoded an English "Dismiss" here — this string is what
    // a screen reader reads for the region outside the panel. Asserting it is
    // not the English word would prove nothing, since Material's own English
    // translation is also "Dismiss"; what matters is that it *moves* with the
    // locale, which a hardcoded literal cannot.
    // The route's barrier is the one carrying the label; the others in the
    // tree have none, so pick by that rather than by position.
    String currentLabel() => tester
        .widgetList<ModalBarrier>(find.byType(ModalBarrier))
        .map((barrier) => barrier.semanticsLabel)
        .firstWhere((label) => label != null)!;

    await pumpAndOpen(tester, const Size(1400, 900), locale: const Locale('en'));
    final english = currentLabel();

    // Dismiss before reopening: the first panel's barrier would otherwise
    // swallow the tap meant for the button underneath it.
    await tester.tapAt(const Offset(100, 450));
    await tester.pumpAndSettle();

    await pumpAndOpen(tester, const Size(1400, 900), locale: const Locale('zh'));
    final chinese = currentLabel();

    expect(english, isNotEmpty);
    expect(chinese, isNot(english),
        reason: 'the barrier label is a hardcoded string, not a translated one');
  });

  testWidgets('the panel paints one surface, not two stacked ones', (tester) async {
    // The shell casts the shadow and the Material inside it paints the fill.
    // Colouring both is how the copies ended up with a square surface behind
    // a rounded one on mobile.
    await pumpAndOpen(tester, const Size(1400, 900));

    final container = tester.widget<Container>(
      find.descendant(of: find.byType(AppSidePanel), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.color, isNull, reason: 'the shell is painting a fill of its own');
    expect(decoration.boxShadow, isNotNull);
  });

  testWidgets('it resolves with whatever the panel is popped with', (tester) async {
    // Panels are pickers as often as they are lists; a caller has to be able
    // to hear what was chosen.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  chosen = await AppSidePanel.show<String>(
                    context,
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.pop(context, 'picked'),
                      child: const Text('choose'),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('choose'));
    await tester.pumpAndSettle();

    expect(chosen, 'picked');
  });
}
