import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/size_picker/size_field.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/size_picker/size_picker_panel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/size_picker/size_picker_parts.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_layout.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_button.dart';
import 'package:provider/provider.dart';

/// The `A1c` size picker: what it writes, when it refuses to, and where it
/// opens.
void main() {
  ParamSpec sizeSpec(String modelId) =>
      ModelCapabilities.forModel(modelId).imageParams.firstWhere((p) => p.key == 'imageSize');

  Widget host(Widget child, {double width = 340}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAppTheme(accent: ThemeAccent.fromSeed(Colors.indigo), brightness: Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
          ),
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('the rule line is mono; its status is in the UI face', (tester) async {
    // The status once left mono with `copyWith(fontFamilyFallback: null)`,
    // which keeps the fallback — harmless only while mono never took effect.
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(
        accent: ThemeAccent.fromSeed(Colors.indigo),
        brightness: Brightness.light,
        fontFamily: 'Microsoft YaHei',
      ),
      home: const Scaffold(
        body: SizeRuleLine(parts: [SizeRulePart('×16')], status: 'All pass', failLabel: 'fails'),
      ),
    ));
    final status = tester.widget<Text>(find.text('All pass')).style!;
    expect(status.fontFamily, 'Microsoft YaHei');
    expect(status.fontFamilyFallback, isNull);
    final rule = tester.widget<Text>(find.byType(Text).first).textSpan! as TextSpan;
    expect(rule.children!.single.style!.fontFamily, kMonoFontFamilyFallback.first);
  });

  group('the panel', () {
    Future<(List<String>, List<int>)> open(
      WidgetTester tester,
      String modelId,
      String value, {
      List<SpecRate>? rates,
    }) async {
      tall(tester);
      final written = <String>[];
      final closed = <int>[];
      await tester.pumpWidget(host(SizePickerPanel(
        spec: sizeSpec(modelId),
        value: value,
        modelName: modelId,
        rates: rates,
        onChanged: written.add,
        onClose: () => closed.add(1),
      )));
      await tester.pumpAndSettle();
      return (written, closed);
    }

    AppButton button(WidgetTester tester, String label) => tester.widget<AppButton>(
          find.ancestor(of: find.text(label), matching: find.byType(AppButton)),
        );

    testWidgets('a new ratio keeps the tier; a tier keeps the ratio', (tester) async {
      // `30b`: any cell of the ratio × tier table in two clicks.
      final (written, _) = await open(tester, 'wan2.7-image-pro', '2K');
      await tester.tap(find.text('16:9'));
      await tester.pumpAndSettle();
      expect(written.last, '2688x1536');

      await tester.tap(find.text('4K'));
      await tester.pumpAndSettle();
      expect(written.last, '4096x2304');

      // Back to the square: the keyword itself, not its pixels.
      await tester.tap(find.text('1:1'));
      await tester.pumpAndSettle();
      expect(written.last, '4K');
    });

    testWidgets('Esc puts back the value it opened on', (tester) async {
      final (written, closed) = await open(tester, 'wan2.7-image-pro', '2K');
      await tester.tap(find.text('16:9'));
      await tester.pumpAndSettle();
      expect(written.last, '2688x1536');

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(written.last, '2K');
      expect(closed, isNotEmpty);
    });

    testWidgets('an illegal size is never written; the fix is one click', (tester) async {
      // `30f`: 4000×400 is 10:1 on wan's 8:1.
      final (written, _) = await open(tester, 'wan2.7-image', '1696x960');
      await tester.tap(find.byIcon(Icons.link)); // lock off: the sides are independent
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(1), '4000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(2), '400');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(written, isNot(contains('4000x400')));
      expect(find.textContaining('Aspect ratio 10:1 is over 8:1'), findsOneWidget);
      expect(button(tester, 'Done').onPressed, isNull);
      await tester.tap(find.text('Use 3200 × 400'));
      await tester.pumpAndSettle();
      expect(written.last, '3200x400');
      expect(button(tester, 'Done').onPressed, isNotNull);
    });

    testWidgets('a ratio past the limit has no solution, and says which', (tester) async {
      // `30e`: 4:1 on gpt-image-2's 3:1.
      final (written, _) = await open(tester, 'gpt-image-2', '3840x2160');
      await tester.tap(find.byIcon(Icons.tune)); // the ratio chip, not the tier segment
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '4:1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('no size works'), findsOneWidget);
      expect(find.textContaining('3840 × 2160'), findsWidgets); // the kept value
      expect(written, isEmpty);
      await tester.tap(find.text('Use 3:1'));
      await tester.pumpAndSettle();
      expect(written, isNotEmpty);
      expect(button(tester, 'Done').onPressed, isNotNull);
    });

    testWidgets('a portrait ratio past the limit is fixed on its own side', (tester) async {
      final (written, _) = await open(tester, 'gpt-image-2', '2160x3840');
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '1:4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use 1:3'));
      await tester.pumpAndSettle();
      final (w, h) = (int.parse(written.last.split('x')[0]), int.parse(written.last.split('x')[1]));
      expect(h, greaterThan(w));
      expect(find.text('3:1'), findsNothing);
    });

    testWidgets('a click after typing replaces the typed edge and writes', (tester) async {
      // A chip does not take focus from the box: the edge is still "typing".
      final (written, _) = await open(tester, 'wan2.7-image-pro', '2K');
      await tester.enterText(find.byType(TextField).first, '3000');
      await tester.pump();
      await tester.tap(find.text('16:9'));
      await tester.pumpAndSettle();
      expect(written.last, '2688x1536');

      await tester.enterText(find.byType(TextField).first, '3000');
      await tester.pump();
      await tester.tap(find.text('Not set'));
      await tester.pumpAndSettle();
      expect(written.last, 'not_set');
    });

    testWidgets('the billing tier is named only when a table prices tiers', (tester) async {
      const rates = [SpecRate(size: '1K', price: 0.2), SpecRate(size: '2K', price: 0.4)];
      await open(tester, 'qwen-image-3.0', 'not_set', rates: rates);
      await tester.tap(find.text('1K'));
      await tester.pumpAndSettle();
      expect(find.text('Billed 1K'), findsOneWidget);
      expect(find.textContaining('Over the 1K area'), findsNothing);

      // `30c` 越线: the tag changes tier and the reason appears.
      await tester.tap(find.text('2K'));
      await tester.pumpAndSettle();
      expect(find.text('Billed 2K'), findsOneWidget);
      expect(find.textContaining('Over the 1K area'), findsOneWidget);
    });

    testWidgets('without billing information nothing stands in for it', (tester) async {
      await open(tester, 'qwen-image-3.0', '1024x1024');
      expect(find.textContaining('Billed'), findsNothing);
    });

    testWidgets("the model's own rules are the ones drawn", (tester) async {
      await open(tester, 'wan2.7-image', 'not_set');
      expect(find.textContaining('≤ 8:1'), findsOneWidget);
      expect(find.textContaining('long edge ≤'), findsNothing); // wan has no edge ceiling
      expect(find.textContaining('Sends 1K'), findsOneWidget);
    });
  });

  group('the field', () {
    Future<List<String>> field(
      WidgetTester tester,
      String modelId,
      String value, {
      String? stored,
      WorkbenchLayoutState? layout,
    }) async {
      tall(tester);
      final written = <String>[];
      final f = SizeField(
        spec: sizeSpec(modelId),
        value: value,
        modelName: modelId,
        storedValue: stored,
        onChanged: written.add,
      );
      await tester.pumpWidget(host(
        layout == null ? f : Provider<WorkbenchLayoutState>.value(value: layout, child: f),
        width: 300,
      ));
      await tester.pumpAndSettle();
      return written;
    }

    testWidgets('says once, quietly, when a sibling model\'s size fell back', (tester) async {
      await field(tester, 'wan2.7-image', 'not_set', stored: '4K');
      expect(find.textContaining('4K is not valid on wan2.7-image'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('swaps a size on its side without opening anything', (tester) async {
      final written = await field(tester, 'wan2.7-image', '1696x960');
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pump();
      expect(written, ['960x1696']);
      expect(find.byType(SizePickerPanel), findsNothing);
    });

    testWidgets('a square has nothing to swap', (tester) async {
      final written = await field(tester, 'wan2.7-image', '2K');
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pump();
      expect(written, isEmpty);
    });

    testWidgets('on desktop it opens a popover with its own header', (tester) async {
      await field(tester, 'wan2.7-image-pro', '2K');
      await tester.tap(find.text('2K'));
      await tester.pumpAndSettle();
      expect(find.byType(SizePickerPanel), findsOneWidget);
      expect(find.text('Image size'), findsOneWidget);
    });

    testWidgets('Esc in the popover reverts though no box has focus', (tester) async {
      final written = await field(tester, 'wan2.7-image-pro', '2K');
      await tester.tap(find.text('2K'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16:9'));
      await tester.pumpAndSettle();
      expect(written.last, '2688x1536');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(written.last, '2K');
      expect(find.byType(SizePickerPanel), findsNothing);
    });

    testWidgets('on a phone it unfolds in the sheet instead of stacking one', (tester) async {
      final layout = WorkbenchLayoutState(
        GlobalKey<ScaffoldState>(),
        contentWidth: 390,
        leftInDrawer: true,
        rightInDrawer: false,
        rightSheetOpener: () {},
      );
      await field(tester, 'wan2.7-image-pro', '2K', layout: layout);
      await tester.tap(find.text('2K'));
      await tester.pumpAndSettle();
      expect(find.byType(SizePickerPanel), findsOneWidget);
      // No second layer: the field above is the header.
      expect(find.text('Image size'), findsNothing);
      expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
    });
  });
}
