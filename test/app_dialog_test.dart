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
    expect(shape.borderRadius, BorderRadius.circular(12));
  });
}
