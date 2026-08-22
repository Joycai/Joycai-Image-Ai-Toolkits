import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_semantic_colors.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_snackbar.dart';

/// Covers [AppSnackBar]'s three outcomes — the shared replacement for every
/// hand-rolled `ScaffoldMessenger.showSnackBar` call around the app.
void main() {
  const seed = Colors.indigo;

  Widget host(void Function(BuildContext) onPressed) => MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(onPressed: () => onPressed(context), child: const Text('Trigger')),
          ),
        ),
      );

  testWidgets('success shows the message on a green toast, whatever the seed', (tester) async {
    // Was `primaryContainer` — the user's own seed — so "saved" came out
    // orange for a user who picked orange and pink for one who picked rose,
    // colliding with the warning and error toasts respectively. A verdict has
    // to mean the same thing at every seed, which is what AppSemanticColors is
    // for and what design-tokens.md §3 requires.
    await tester.pumpWidget(host((context) => AppSnackBar.success(context, 'Saved')));
    await tester.tap(find.text('Trigger'));
    await tester.pump();

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        AppSemanticColors.light.successContainer);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        isNot(theme.colorScheme.primaryContainer));
  });

  testWidgets('error shows the message on an errorContainer toast', (tester) async {
    await tester.pumpWidget(host((context) => AppSnackBar.error(context, 'Failed')));
    await tester.tap(find.text('Trigger'));
    await tester.pump();

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, theme.colorScheme.errorContainer);
  });

  testWidgets('a second call replaces the first instead of queuing behind it', (tester) async {
    // The whole reason AppSnackBar always hides the current one first: a
    // batch operation reporting one failure per file must show only the
    // latest state, not a backlog the user has to dismiss one at a time.
    await tester.pumpWidget(host((context) {
      AppSnackBar.info(context, 'First');
      AppSnackBar.error(context, 'Second');
    }));
    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });
}
