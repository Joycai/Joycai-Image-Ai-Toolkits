import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/dual_tone_swatch.dart';
import 'package:joycai_image_ai_toolkits/widgets/theme_accent_picker.dart';

/// Covers the theme-colour chooser's two forms (design `D1a 20b` / `20e`).
///
/// The width switch is the thing most likely to regress silently: both forms
/// render without error at either width, so only a test that counts which
/// widgets are on screen notices the wrong one being shown.
void main() {
  final ThemeAccent blue = AppConstants.presetThemes['Blue']!;

  Future<List<String>> pump(
    WidgetTester tester, {
    required double width,
    Brightness brightness = Brightness.light,
  }) async {
    final picked = <String>[];
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(accent: blue, brightness: brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ThemeAccentPicker(selected: blue, onSelect: picked.add),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('desktop shows one preview card per preset, and no dots', (tester) async {
    await pump(tester, width: 1440);

    expect(find.byType(ThemeAccentPreviewCard), findsNWidgets(AppConstants.presetThemes.length));
    expect(find.byType(DualToneSwatch), findsNothing);
  });

  testWidgets('mobile shows one dot per preset, and no cards', (tester) async {
    await pump(tester, width: 390);

    expect(find.byType(DualToneSwatch), findsNWidgets(AppConstants.presetThemes.length));
    expect(find.byType(ThemeAccentPreviewCard), findsNothing);
  });

  testWidgets('the selected card is the one carrying the tick', (tester) async {
    await pump(tester, width: 1440);

    // One tick on the whole grid, and it sits inside the Blue card.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      find.descendant(of: find.widgetWithText(ThemeAccentPreviewCard, 'Blue'), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });

  testWidgets('tapping a card reports the preset key, not a colour', (tester) async {
    // The preference is stored by key so a retuned preset follows the user;
    // the picker must hand the key up, or the caller has to reverse-map it.
    final picked = await pump(tester, width: 1440);

    await tester.tap(find.widgetWithText(ThemeAccentPreviewCard, 'Rose'));
    await tester.pumpAndSettle();

    expect(picked, ['Rose']);
  });

  testWidgets('tapping a dot reports the preset key too', (tester) async {
    final picked = await pump(tester, width: 390);

    await tester.tap(find.byType(DualToneSwatch).last);
    await tester.pumpAndSettle();

    expect(picked, [AppConstants.presetThemes.keys.last]);
  });

  testWidgets('a dot names the preset and both values on its tooltip', (tester) async {
    // The dots are the mobile form, where the picture cannot show the pair;
    // the tooltip is where the two values live instead.
    await pump(tester, width: 390);

    final Tooltip tip = tester.widget<Tooltip>(
      find.descendant(of: find.byType(DualToneSwatch).first, matching: find.byType(Tooltip)),
    );
    final String text = tip.richMessage!.toPlainText();
    expect(text, startsWith('Blue'));
    expect(text, contains('#0050E1'), reason: 'the rendered light primary, not the seed #4A72E8');
    expect(text, contains('#5B8DFF'));
    expect(text, isNot(contains('#4A72E8')));
  });

  testWidgets('the dot grid wraps rather than scrolling sideways', (tester) async {
    // `20e`: four to a row, two rows, at 390 wide. A horizontal scroll would
    // hide half the set, and the section's whole value is comparing all
    // eight at a glance.
    await pump(tester, width: 390);

    final List<double> lefts = find
        .byType(DualToneSwatch)
        .evaluate()
        .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dx)
        .toList();
    final List<double> tops = find
        .byType(DualToneSwatch)
        .evaluate()
        .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
        .toList();

    expect(tops.toSet().length, 2, reason: 'two rows');
    expect(lefts.toSet().length, 4, reason: 'four columns — pinned, not whatever the width allows');
    expect(lefts.reduce((a, b) => a > b ? a : b) + DualToneSwatch.hitSize, lessThanOrEqualTo(390),
        reason: 'every dot is inside the viewport');
  });
}
