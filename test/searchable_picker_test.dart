import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/searchable_picker.dart';

/// Covers [SearchablePickerField]'s load-bearing behaviours, each of which
/// went wrong in a way that only shows up under a state a single mount does not
/// reach: a keypress before any typing, a query that matched nothing, a text
/// scale above 1.0, a tag longer than the field, and a `T` that is itself
/// nullable — where `null` is an answer rather than an absence.
///
/// The scroll and overflow cases in particular are worth pinning because they
/// are held by an arrangement rather than a number — a `ScrollPosition` that
/// has to survive the empty state, and an `itemExtent` that has to track the
/// type it is sizing. Either regressing looks fine on the developer's machine
/// at 100% text and wrong on the user's.
void main() {
  const seed = Colors.indigo;

  /// [count] models, every third one tagged, ids distinct from names so the
  /// secondary line (and so the two-line row extent) is exercised.
  List<PickerOption<int>> options(int count) => [
        for (var i = 0; i < count; i++)
          PickerOption<int>(
            value: i,
            label: 'Model $i',
            secondary: 'vendor/model-id-$i',
            badge: i % 3 == 0 ? 'prod' : null,
            badgeColor: const Color(0xFF2196F3),
          ),
      ];

  Widget host(
    List<PickerOption<int>> opts, {
    required void Function(int) onChanged,
    int? selected,
    TextScaler textScaler = TextScaler.noScaling,
    double width = 400,
  }) {
    return MaterialApp(
      theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SearchablePickerField<int>(
              selected: selected == null
                  ? null
                  : opts.firstWhere((o) => o.value == selected),
              optionsBuilder: () => opts,
              onChanged: onChanged,
              hint: 'Select a model',
              searchHint: 'Search models',
              dialogIcon: Icons.memory_outlined,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byType(InputDecorator));
    await tester.pumpAndSettle();
  }

  ScrollController listController(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!;

  group('committing with the keyboard', () {
    testWidgets('Enter before typing keeps the selection', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(host(options(50), onChanged: picked.add, selected: 30));
      await openPicker(tester);

      // The search field autofocuses, so this is one reflexive keypress on
      // every open. It used to pop `_filtered.first` — model 0, not model 30 —
      // and the workbench persisted it.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(picked, isEmpty);
      expect(find.byType(ListView), findsOneWidget, reason: 'picker should still be open');
    });

    testWidgets('Enter after a query takes the top match', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(host(options(50), onChanged: picked.add, selected: 30));
      await openPicker(tester);

      await tester.enterText(find.byType(TextField), 'model-id-17');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(picked, [17]);
    });
  });

  testWidgets('results reopen at the top after a query that matched nothing', (tester) async {
    await tester.pumpWidget(host(options(400), onChanged: (_) {}, selected: 300));
    await openPicker(tester);

    // Opens scrolled to the selection, which is the whole point of the
    // uniform extent.
    expect(listController(tester).offset, greaterThan(0));

    await tester.enterText(find.byType(TextField), 'zzzzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);

    // Backspacing to something that matches again used to remount the list,
    // which re-applied `initialScrollOffset` and dropped the user at the
    // bottom of their results.
    await tester.enterText(find.byType(TextField), 'model-id-3');
    await tester.pumpAndSettle();

    expect(listController(tester).offset, 0);
  });

  group('accessibility text scales', () {
    for (final scale in <double>[1.0, 1.3, 1.5, 2.0, 2.25]) {
      testWidgets('rows do not overflow at ${scale}x', (tester) async {
        await tester.pumpWidget(host(
          options(40),
          onChanged: (_) {},
          selected: 5,
          textScaler: TextScaler.linear(scale),
        ));
        await openPicker(tester);

        // `itemExtent` hands each row a tight box, so a constant measured at
        // 1.0 stripes every visible row at once — the whole list, not one edge.
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('a long tag does not overflow the collapsed field', (tester) async {
    final tagged = [
      PickerOption<int>(
        value: 1,
        label: 'GPT Image 1',
        badge: 'production-relay-eu-west',
        badgeColor: const Color(0xFF2196F3),
      ),
    ];

    // Half a 375px phone's config panel, which is where the field actually
    // has to survive: the tag is free text with no length limit.
    await tester.pumpWidget(host(tagged, onChanged: (_) {}, selected: 1, width: 151));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('GPT Image 1'), findsOneWidget);
  });

  group('a picker whose T is itself nullable', () {
    /// The settings screen's knowledge-base sub-agent binding: `null` is not
    /// "nothing chosen", it is "follow the main model". A bare `T?` return
    /// cannot tell that apart from a dismissal.
    Widget nullableHost({required void Function(int?) onChanged}) {
      final opts = [
        PickerOption<int?>(value: null, label: 'Follow the main model'),
        PickerOption<int?>(value: 7, label: 'Claude Sonnet'),
      ];
      return MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SearchablePickerField<int?>(
                selected: opts[1],
                optionsBuilder: () => opts,
                onChanged: onChanged,
                hint: 'Select a model',
                searchHint: 'Search models',
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('choosing the null row fires onChanged with null', (tester) async {
      final picked = <int?>[];
      await tester.pumpWidget(nullableHost(onChanged: picked.add));
      await openPicker(tester);

      await tester.tap(find.text('Follow the main model'));
      await tester.pumpAndSettle();

      // Not `isEmpty`: the callback must have run, carrying null.
      expect(picked, [null]);
    });

    testWidgets('dismissing fires nothing', (tester) async {
      final picked = <int?>[];
      await tester.pumpWidget(nullableHost(onChanged: picked.add));
      await openPicker(tester);

      Navigator.of(tester.element(find.byType(ListView))).pop();
      await tester.pumpAndSettle();

      expect(picked, isEmpty);
    });
  });

  testWidgets('the field carries a button role and its value', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(options(5), onChanged: (_) {}, selected: 2));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(InputDecorator)),
      matchesSemantics(
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        value: 'Model 2',
      ),
    );
    handle.dispose();
  });
}
