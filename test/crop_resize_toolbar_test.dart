import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/crop_resize_toolbar.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// The crop tool's controls — the content of the glass toolbar's tool slot
/// (`A4 · 1a`) — as the width they are handed shrinks.
///
/// The bug this pins: the bar once chose between labelled buttons and bare
/// icons from a hardcoded `width < 1250`. A perfectly ordinary maximised window
/// leaves this bar under that, so the three save actions collapsed to three
/// unlabelled icons — one of which overwrites the user's original file. The
/// design's whole point is that the destructive action be named, and quieter
/// than the safe one; the threshold silently undid both.
///
/// Widths here are **not** comparable to real ones. flutter_test lays text
/// out in a placeholder font whose every glyph is a full square em, so labels
/// measure roughly twice their shipping width and the bar sheds them far
/// earlier. The assertions are therefore about the *order* things are dropped
/// in, which is font-independent, rather than about the pixel each drop
/// happens at — a constant tuned here would say nothing about the app.
///
/// The source file does not exist, so the source-size caption never appears:
/// the order below starts from the resampler's name.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_crop_toolbar_test');

  const fileName = 'yaxin_cowboy_1.png';
  const samplerName = 'Lanczos';

  /// Renders the controls at [barWidth] while the window stays desktop-sized —
  /// the centre column is what squeezes the slot, not the screen.
  Future<void> pumpAtWidth(WidgetTester tester, double barWidth) async {
    // The window must exceed the bar: a SizedBox cannot outgrow the
    // constraints handed to it, so a fixed window would silently clamp every
    // wider case and the sweep would test nothing above it.
    tester.view.physicalSize = Size(barWidth + 200 > 1200 ? barWidth + 200 : 1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final appState = AppState();
    final uiState = WorkbenchUIState()
      ..cropResizeSourceImage = AppImage(path: '/tmp/$fileName', name: fileName);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: uiState),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: barWidth, child: const CropResizeToolbar()),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Widest width at which [gone] has already been dropped, scanning down.
  /// Comparing two of these is what pins the degradation order.
  Future<double> widthWhereDropped(WidgetTester tester, Finder gone) async {
    for (var w = 2800.0; w >= 400; w -= 25) {
      await pumpAtWidth(tester, w);
      if (gone.evaluate().isEmpty) return w;
    }
    return 400;
  }

  Future<AppLocalizations> en() => AppLocalizations.delegate.load(const Locale('en'));

  testWidgets('given room, every control is named and nothing is folded', (tester) async {
    await pumpAtWidth(tester, 2800);
    final l10n = await en();

    expect(find.text(l10n.saveCopy), findsOneWidget);
    expect(find.text(l10n.cropResizeSaveDestinationHint), findsOneWidget);
    expect(find.text(l10n.overwriteSource), findsOneWidget);
    expect(find.text(l10n.reset), findsOneWidget);
    expect(find.text(samplerName), findsOneWidget);
    expect(find.byTooltip(l10n.more), findsNothing);
  });

  testWidgets('at its own preferred width nothing has given way', (tester) async {
    // The glass toolbar weighs its tool switch's labels against this number;
    // if the row sheds anything at it, the number is a lie.
    await pumpAtWidth(tester, 2800);
    final preferred = CropResizeToolbar.preferredWidth(tester.element(find.byType(CropResizeToolbar)));
    await pumpAtWidth(tester, preferred);
    final l10n = await en();

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.overwriteSource), findsOneWidget);
    expect(find.text(l10n.reset), findsOneWidget);
    expect(find.text(samplerName), findsOneWidget);
    expect(find.text('9:16'), findsOneWidget);
    expect(find.byTooltip(l10n.more), findsNothing);
  });

  testWidgets('the bar sheds decoration before it sheds meaning', (tester) async {
    // The regression, stated so the shipping font cannot hide it: whatever the
    // pixel widths work out to, the resampler's name and the save button's
    // destination subtitle must both be gone before an action loses its label.
    // Under the old single threshold every one of these vanished at once.
    final l10n = await en();

    final samplerDropped = await widthWhereDropped(tester, find.text(samplerName));
    final hintDropped = await widthWhereDropped(tester, find.text(l10n.cropResizeSaveDestinationHint));
    final labelDropped = await widthWhereDropped(tester, find.text(l10n.overwriteSource));

    expect(labelDropped, lessThan(samplerDropped),
        reason: 'the overwrite label went at the same width as the resampler name, or before it');
    expect(labelDropped, lessThan(hintDropped),
        reason: 'the overwrite label went before the save button dropped its destination subtitle');
  });

  testWidgets('an action label outlives the portrait presets', (tester) async {
    final l10n = await en();

    final portraitDropped = await widthWhereDropped(tester, find.text('9:16'));
    final labelDropped = await widthWhereDropped(tester, find.text(l10n.overwriteSource));

    expect(labelDropped, lessThan(portraitDropped));
  });

  testWidgets('a genuinely narrow bar still reaches overwrite, still marked destructive', (tester) async {
    await pumpAtWidth(tester, 620);
    final l10n = await en();

    expect(tester.takeException(), isNull);
    expect(find.text(l10n.overwriteSource), findsNothing);

    // Wherever it went — a glyph in the row, the ⋮ menu, or the narrow step
    // flow's save menu — it is at most one tap away, under its warning glyph.
    if (find.byIcon(Icons.warning_amber_rounded).evaluate().isEmpty) {
      final opener = find.byTooltip(l10n.more).evaluate().isNotEmpty
          ? find.byTooltip(l10n.more)
          : find.byIcon(Icons.save_outlined);
      await tester.tap(opener);
      await tester.pumpAndSettle();
      expect(find.text(l10n.overwriteSource), findsOneWidget);
    }
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('reset is the quiet one of the three', (tester) async {
    // Reset must not read as a peer of the two actions that write a file.
    await pumpAtWidth(tester, 2800);
    final l10n = await en();

    expect(
      find.ancestor(of: find.text(l10n.reset), matching: find.byType(FilledButton)),
      findsNothing,
      reason: 'reset is drawn as a filled action',
    );
    expect(
      find.ancestor(of: find.text(l10n.reset), matching: find.byType(OutlinedButton)),
      findsNothing,
      reason: 'reset is drawn with a border, competing with overwrite',
    );
  });

  testWidgets('the ratio presets are a segmented control, not the old chip row', (tester) async {
    await pumpAtWidth(tester, 2800);

    expect(find.byType(ChoiceChip), findsNothing,
        reason: 'the chip row this redesign replaced is back');
    expect(find.text('16:9'), findsOneWidget);
    expect(find.text('9:16'), findsOneWidget);
  });

  testWidgets('the custom X:Y fields stay folded until Custom is chosen', (tester) async {
    await pumpAtWidth(tester, 2800);
    final l10n = await en();

    // Two dimension fields (width/height) and nothing else, while folded.
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.text(l10n.custom));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(4),
        reason: 'choosing Custom did not unfold the X:Y pair');
  });

  testWidgets('the bare dimension boxes still say what they are', (tester) async {
    // `A4 · 1a` draws the pair with no visible label, reading as W × H beside
    // the link. An empty box still owes its name to a pointer and to a screen
    // reader — the moment the user most needs it is before typing anything.
    await pumpAtWidth(tester, 2800);
    final l10n = await en();

    for (final name in [l10n.width, l10n.height]) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
      expect(
        find.byWidgetPredicate((w) => w is Semantics && w.properties.label == name),
        findsOneWidget,
        reason: name,
      );
    }
  });

  testWidgets('no width in the working range overflows or clips the save action', (tester) async {
    // A single threshold is a guess, and the width just above it is where a
    // guess shows. Sweeping checks the fit calculation instead of trusting it.
    final l10n = await en();
    for (var width = 560.0; width <= 2800.0; width += 40) {
      await pumpAtWidth(tester, width);

      expect(tester.takeException(), isNull, reason: 'Overflow at ${width}px');

      // Save Copy in the row, or the step flow's Save — never neither.
      final copy = find.text(l10n.saveCopy);
      final save = copy.evaluate().isNotEmpty ? copy : find.byIcon(Icons.save_outlined);
      expect(save, findsOneWidget, reason: 'no save action at ${width}px');

      final bar = tester.getRect(find.byType(CropResizeToolbar));
      final rect = tester.getRect(save);
      expect(rect.right, lessThanOrEqualTo(bar.right + 0.01),
          reason: 'the save action is clipped off the right edge at ${width}px');
      expect(rect.left, greaterThanOrEqualTo(bar.left),
          reason: 'the save action starts before the bar does at ${width}px');
    }
  });
}
