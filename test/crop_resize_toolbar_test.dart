import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/crop_resize_toolbar.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The crop toolbar as its own width shrinks.
///
/// The bug this pins: the bar chose between labelled buttons and bare icons
/// from a hardcoded `width < 1250`. A perfectly ordinary maximised window
/// leaves this bar under that, so the three save actions collapsed to three
/// unlabelled icons — one of which overwrites the user's original file. The
/// redesign's whole point was that the destructive action be named, and
/// quieter than the safe one; the threshold silently undid both.
///
/// Widths here are **not** comparable to real ones. flutter_test lays text
/// out in a placeholder font whose every glyph is a full square em, so labels
/// measure roughly twice their shipping width and the bar sheds them far
/// earlier. The assertions are therefore about the *order* things are dropped
/// in, which is font-independent, rather than about the pixel each drop
/// happens at — a constant tuned here would say nothing about the app.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => Directory.systemTemp.path,
  );

  const fileName = 'yaxin_cowboy_1.png';

  /// Renders the bar at [barWidth] while the window stays desktop-sized —
  /// the centre panel is what squeezes this bar, not the screen.
  Future<void> pumpAtWidth(WidgetTester tester, double barWidth) async {
    // Two things the window size has to satisfy. It must exceed the bar — a
    // SizedBox cannot outgrow the constraints handed to it, so a fixed 1600px
    // window silently clamps every wider case and the sweep tests nothing
    // above it. And it must stay desktop-sized (>= 1000), because a narrow
    // *window* switches this widget to the mobile bottom bar entirely. The
    // case under test is the real one: a wide window whose centre panel is
    // squeezed by the two side panels.
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

  testWidgets('given room, every control is named', (tester) async {
    await pumpAtWidth(tester, 2800);
    final l10n = await en();

    expect(find.text(l10n.saveCopy), findsOneWidget);
    expect(find.text(l10n.cropResizeSaveDestinationHint), findsOneWidget);
    expect(find.text(l10n.overwriteSource), findsOneWidget);
    expect(find.text(l10n.reset), findsOneWidget);
    expect(find.text(l10n.cropResizeResample), findsOneWidget);
    expect(find.text(fileName), findsOneWidget);
  });

  testWidgets('the bar sheds decoration before it sheds meaning', (tester) async {
    // The regression, stated so the shipping font cannot hide it: whatever the
    // pixel widths work out to, the filename caption and the save button's
    // destination hint must both be gone before an action loses its label.
    // Under the old single threshold every one of these vanished at once.
    final l10n = await en();

    final captionDropped = await widthWhereDropped(tester, find.text(fileName));
    final hintDropped = await widthWhereDropped(tester, find.text(l10n.cropResizeSaveDestinationHint));
    final labelDropped = await widthWhereDropped(tester, find.text(l10n.overwriteSource));

    expect(labelDropped, lessThan(captionDropped),
        reason: 'the overwrite label went at the same width as the filename, or before it');
    expect(labelDropped, lessThan(hintDropped),
        reason: 'the overwrite label went before the save button dropped its destination hint');
  });

  testWidgets('an action label outlives the sampler label and the portrait presets', (tester) async {
    final l10n = await en();

    final resampleDropped = await widthWhereDropped(tester, find.text(l10n.cropResizeResample));
    final portraitDropped = await widthWhereDropped(tester, find.text('9:16'));
    final labelDropped = await widthWhereDropped(tester, find.text(l10n.overwriteSource));

    expect(labelDropped, lessThan(resampleDropped));
    expect(labelDropped, lessThan(portraitDropped));
  });

  testWidgets('a genuinely narrow bar falls back to icons rather than clipping', (tester) async {
    await pumpAtWidth(tester, 620);
    final l10n = await en();

    expect(find.text(l10n.overwriteSource), findsNothing);
    // Still reachable, and still marked as the destructive one.
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset is the quiet one of the three', (tester) async {
    // Reset must not read as a peer of the two actions that write a file.
    // AppButton's `text` variant keeps Material's accent tint, which put it
    // at the same weight as them; AppToolButton is the neutral one.
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

  testWidgets('the dimension boxes label themselves and their unit while empty', (tester) async {
    // InputDecoration hides prefix/suffix text until a field has focus or
    // content, which left an empty box with neither its name nor "px" — the
    // exact moment the user most needs both.
    await pumpAtWidth(tester, 2800);
    final l10n = await en();

    expect(find.text(l10n.width), findsOneWidget);
    expect(find.text(l10n.height), findsOneWidget);
    expect(find.text('px'), findsNWidgets(2));
  });

  testWidgets('no width in the working range overflows or clips the actions', (tester) async {
    // A single threshold is a guess, and the width just above it is where a
    // guess shows. Sweeping checks the fit calculation instead of trusting it.
    for (var width = 560.0; width <= 2800.0; width += 40) {
      await pumpAtWidth(tester, width);

      expect(tester.takeException(), isNull, reason: 'Overflow at ${width}px');

      final bar = tester.getRect(find.byType(CropResizeToolbar));
      final save = tester.getRect(find.byIcon(Icons.save_outlined));
      expect(save.right, lessThanOrEqualTo(bar.right + 0.01),
          reason: 'the save action is clipped off the right edge at ${width}px');
      expect(save.left, greaterThanOrEqualTo(bar.left),
          reason: 'the save action starts before the bar does at ${width}px');
    }
  });
}
