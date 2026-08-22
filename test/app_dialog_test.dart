import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_dialog.dart';

/// Covers [AppDialog]'s shared chrome — the shell every hand-built dialog in
/// `lib/widgets/dialogs/` and `lib/widgets/models/` should eventually sit on.
void main() {
  const seed = Colors.indigo;

  Widget host(WidgetBuilder builder) => MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
        home: Builder(builder: builder),
      );

  testWidgets('show displays the title, content and actions', (tester) async {
    await tester.pumpWidget(host((context) {
      return Center(
        child: ElevatedButton(
          onPressed: () => AppDialog.show<void>(
            context,
            title: 'Delete channel?',
            content: const Text('This cannot be undone.'),
            actions: [TextButton(onPressed: () {}, child: const Text('Cancel'))],
          ),
          child: const Text('Open'),
        ),
      );
    }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Delete channel?'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('the title reads from textTheme.titleLarge', (tester) async {
    await tester.pumpWidget(host((context) {
      return Center(
        child: ElevatedButton(
          onPressed: () => AppDialog.show<void>(context, title: 'Title', content: const SizedBox()),
          child: const Text('Open'),
        ),
      );
    }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final titleWidget = tester.widget<Text>(find.text('Title'));
    expect(titleWidget.style?.fontSize, theme.textTheme.titleLarge?.fontSize);
  });

  testWidgets('popping with a result returns it from show', (tester) async {
    String? result;

    await tester.pumpWidget(host((context) {
      return Center(
        child: ElevatedButton(
          onPressed: () async {
            result = await AppDialog.show<String>(
              context,
              content: Builder(
                builder: (dialogContext) => ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, 'confirmed'),
                  child: const Text('Confirm'),
                ),
              ),
            );
          },
          child: const Text('Open'),
        ),
      );
    }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(result, 'confirmed');
  });

  testWidgets('the surface takes surfaceContainer at a 12px radius, matching PanelCard', (tester) async {
    await tester.pumpWidget(host((context) {
      return Center(
        child: ElevatedButton(
          onPressed: () => AppDialog.show<void>(context, content: const SizedBox()),
          child: const Text('Open'),
        ),
      );
    }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    final shape = dialog.shape! as RoundedRectangleBorder;

    expect(dialog.backgroundColor, theme.colorScheme.surfaceContainer);
    expect(shape.borderRadius, BorderRadius.circular(appDialogRadius));
  });

  group('the dialog grows into place', () {
    // showDialog's own transition is opacity alone, so a dialog arrived at
    // final size getting less see-through — present before it had finished
    // appearing. A surface that scales while it fades reads as arriving.
    testWidgets('scales up on the way in and is settled by the end',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(seedColor: Colors.indigo, brightness: Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppDialog.show(
              context,
              title: 'Overwrite?',
              content: const Text('body'),
            ),
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      double scaleOf(WidgetTester t) => t
          .widget<ScaleTransition>(
            find.ancestor(of: find.byType(Dialog), matching: find.byType(ScaleTransition)).first,
          )
          .scale
          .value;

      final mid = scaleOf(tester);
      expect(mid, greaterThan(0.9), reason: 'never small enough to read as a zoom');
      expect(mid, lessThan(1.0), reason: 'still growing');

      await tester.pumpAndSettle();
      expect(scaleOf(tester), 1.0);
    });

    testWidgets('drops the scale entirely under reduce-motion', (tester) async {
      // The fade stays — it is opacity, not travel, and it is what tells the
      // user something appeared at all.
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(seedColor: Colors.indigo, brightness: Brightness.light),
        builder: (context, navigator) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: navigator!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppDialog.show(
              context,
              title: 'Overwrite?',
              content: const Text('body'),
            ),
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        find.ancestor(of: find.byType(Dialog), matching: find.byType(ScaleTransition)),
        findsNothing,
      );
      expect(find.text('Overwrite?'), findsOneWidget);
    });
  });
}
