import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_semantic_colors.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_snackbar.dart';

/// Covers [AppSnackBar]'s four outcomes — the shared replacement for every
/// hand-rolled `ScaffoldMessenger.showSnackBar` call around the app.
///
/// `E1 12i` gives all four one dark ground and puts the state in the glyph.
/// What these pin is that the ground never moves — not with the seed, which
/// was the original bug, and not with the brightness either, which is what
/// makes a toast read as a label over the app rather than a surface in it.
void main() {
  const seed = Colors.indigo;

  Widget host(
    void Function(BuildContext) onPressed, {
    Color seedColor = seed,
    Brightness brightness = Brightness.light,
  }) =>
      MaterialApp(
        theme: buildAppTheme(seedColor: seedColor, brightness: brightness),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(onPressed: () => onPressed(context), child: const Text('Trigger')),
          ),
        ),
      );

  Future<SnackBar> trigger(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.tap(find.text('Trigger'));
    await tester.pump();
    return tester.widget<SnackBar>(find.byType(SnackBar));
  }

  /// The colour of the toast's leading glyph.
  Color glyphColour(WidgetTester tester, IconData icon) =>
      tester.widget<Icon>(find.byIcon(icon)).color!;

  testWidgets('success reads as success through its glyph, not its ground', (tester) async {
    final bar = await trigger(tester, host((c) => AppSnackBar.success(c, 'Saved')));

    expect(find.text('Saved'), findsOneWidget);
    expect(bar.backgroundColor, AppOverlay.ink);
    expect(glyphColour(tester, Icons.check_circle_outline), AppSemanticColors.dark.success);
  });

  testWidgets('the other three take the same ground and their own glyph', (tester) async {
    final error = await trigger(tester, host((c) => AppSnackBar.error(c, 'Failed')));
    expect(error.backgroundColor, AppOverlay.ink);
    expect(glyphColour(tester, Icons.error_outline), AppOverlay.danger);

    final warning = await trigger(tester, host((c) => AppSnackBar.warning(c, 'Pick one')));
    expect(warning.backgroundColor, AppOverlay.ink);
    expect(glyphColour(tester, Icons.warning_amber_rounded), AppSemanticColors.dark.warning);

    final info = await trigger(tester, host((c) => AppSnackBar.info(c, 'Queued')));
    expect(info.backgroundColor, AppOverlay.ink);
    expect(glyphColour(tester, Icons.info_outline), AppSemanticColors.dark.info);
  });

  testWidgets('nothing about a toast follows the seed', (tester) async {
    // The original bug: the ground was `primaryContainer`, so "saved" came out
    // orange for a user who picked orange and pink for one who picked rose —
    // colliding with the warning and error toasts respectively. A verdict has
    // to mean the same thing at every seed (design-tokens.md §3).
    for (final Color other in <Color>[Colors.orange, Colors.pink, Colors.teal]) {
      final bar = await trigger(
        tester,
        host((c) => AppSnackBar.success(c, 'Saved'), seedColor: other),
      );
      expect(bar.backgroundColor, AppOverlay.ink, reason: '$other');
      expect(glyphColour(tester, Icons.check_circle_outline), AppSemanticColors.dark.success);
    }
  });

  testWidgets('nor the brightness — the ground is pinned in both', (tester) async {
    // The ink is the same literal a tooltip uses, and for the same reason: a
    // thing laid *over* the app keeps one colour whatever the app is wearing.
    for (final Brightness brightness in Brightness.values) {
      final bar = await trigger(
        tester,
        host((c) => AppSnackBar.error(c, 'Failed'), brightness: brightness),
      );
      expect(bar.backgroundColor, AppOverlay.ink, reason: '$brightness');
      expect(glyphColour(tester, Icons.error_outline), AppOverlay.danger);
    }
  });

  testWidgets('an action label is the accent at a tone that survives the ink', (tester) async {
    await trigger(
      tester,
      host((c) => AppSnackBar.error(
            c,
            'Failed',
            action: AppSnackBarAction(label: 'Retry', onPressed: () {}),
          )),
    );

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    expect(action.textColor, theme.colorScheme.accentOnOverlay);
    // Not the plain accent: in light mode that is tone 40 and would all but
    // vanish on this ground.
    expect(action.textColor, isNot(theme.colorScheme.primary));
  });

  testWidgets('a toast with something to do outlasts one that only reports', (tester) async {
    final plain = await trigger(tester, host((c) => AppSnackBar.info(c, 'Queued')));
    expect(plain.duration, const Duration(seconds: 4));

    final actionable = await trigger(
      tester,
      host((c) => AppSnackBar.info(
            c,
            'Queued',
            action: AppSnackBarAction(label: 'View', onPressed: () {}),
          )),
    );
    expect(actionable.duration, const Duration(seconds: 8));
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
