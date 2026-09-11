import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_semantic_colors.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_snackbar.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass.dart';

/// Covers [AppSnackBar]'s four outcomes (`01 全局壳层 · 1d / 1h`).
///
/// One dark glass pill for all four, the state in the glyph. What these pin is
/// that the pill's tone never moves — not with the seed, which was the
/// original bug, and not with the brightness, which is what makes a toast read
/// as a label over the app rather than a surface in it.
void main() {
  const seed = Colors.indigo;

  Widget host(
    void Function(BuildContext) onPressed, {
    Color seedColor = seed,
    Brightness brightness = Brightness.light,
  }) =>
      MaterialApp(
        theme: buildAppTheme(accent: ThemeAccent.fromSeed(seedColor), brightness: brightness),
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

  /// The glass the toast is drawn on.
  AppGlass pillOf(WidgetTester tester) => tester.widget<AppGlass>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(AppGlass)),
      );

  /// The colour of the toast's leading glyph.
  Color glyphColour(WidgetTester tester, IconData icon) =>
      tester.widget<Icon>(find.byIcon(icon)).color!;

  testWidgets('success reads as success through its glyph, not its ground', (tester) async {
    final bar = await trigger(tester, host((c) => AppSnackBar.success(c, 'Saved')));

    expect(find.text('Saved'), findsOneWidget);
    expect(bar.backgroundColor, Colors.transparent,
        reason: 'the SnackBar itself paints nothing; the pill is the toast');
    expect(pillOf(tester).tone, GlassTone.dark);
    expect(pillOf(tester).grade, GlassGrade.float);
    expect(glyphColour(tester, Icons.check_circle), AppSemanticColors.dark.success);
  });

  testWidgets('the other three take the same ground and their own glyph', (tester) async {
    await trigger(tester, host((c) => AppSnackBar.error(c, 'Failed')));
    expect(pillOf(tester).tone, GlassTone.dark);
    expect(glyphColour(tester, Icons.error), AppOverlay.danger);

    await trigger(tester, host((c) => AppSnackBar.warning(c, 'Pick one')));
    expect(pillOf(tester).tone, GlassTone.dark);
    expect(glyphColour(tester, Icons.warning), AppSemanticColors.dark.warning);

    await trigger(tester, host((c) => AppSnackBar.info(c, 'Queued')));
    expect(pillOf(tester).tone, GlassTone.dark);
    expect(glyphColour(tester, Icons.info), AppSemanticColors.dark.info);
  });

  testWidgets('nothing about a toast follows the seed', (tester) async {
    for (final Color other in <Color>[Colors.orange, Colors.pink, Colors.teal]) {
      await trigger(
        tester,
        host((c) => AppSnackBar.success(c, 'Saved'), seedColor: other),
      );
      expect(pillOf(tester).tone, GlassTone.dark, reason: '$other');
      expect(glyphColour(tester, Icons.check_circle), AppSemanticColors.dark.success);
    }
  });

  testWidgets('nor the brightness — the ground is pinned in both', (tester) async {
    for (final Brightness brightness in Brightness.values) {
      await trigger(
        tester,
        host((c) => AppSnackBar.error(c, 'Failed'), brightness: brightness),
      );
      expect(pillOf(tester).tone, GlassTone.dark, reason: '$brightness');
      expect(glyphColour(tester, Icons.error), AppOverlay.danger);
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

    final theme = buildAppTheme(accent: ThemeAccent.fromSeed(seed), brightness: Brightness.light);
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Retry'));
    final colour = button.style!.foregroundColor!.resolve({});
    expect(colour, theme.colorScheme.accentOnOverlay);
    // Not the plain light accent: tone 44 all but vanishes on a dark pill.
    expect(colour, isNot(theme.colorScheme.primary));
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
    await tester.pumpWidget(host((context) {
      AppSnackBar.info(context, 'First');
      AppSnackBar.error(context, 'Second');
    }));
    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('replacing a toast already on screen swaps it, it does not play an exit',
      (tester) async {
    // Fixed pumps rather than pumpAndSettle: `hideCurrentSnackBar` would
    // still show 'First' a frame later; only `removeCurrentSnackBar` has
    // swapped the contents by now.
    int calls = 0;
    await tester.pumpWidget(host((context) {
      calls++;
      if (calls == 1) {
        AppSnackBar.info(context, 'First');
      } else {
        AppSnackBar.error(context, 'Second');
      }
    }));

    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget, reason: 'the first toast should be fully in');

    await tester.tap(find.text('Trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });
}
