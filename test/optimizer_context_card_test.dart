import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/optimizer_context_card.dart';
import 'package:joycai_image_ai_toolkits/services/assistant_context_usage.dart';

/// The card has to render four states of one number, three of which carry no
/// window: nothing measured yet, an unlimited model, a model with no window
/// configured, and a real measurement. The two obvious ways to draw a stacked
/// bar — `Expanded(flex:)` and `used / window` — blow up on the first three.
void main() {
  Future<void> pump(
    WidgetTester tester,
    ContextUsageSnapshot usage, {
    Size size = const Size(300, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: size.width,
            child: OptimizerContextCard(usage: usage),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<AppLocalizations> en() => AppLocalizations.delegate.load(const Locale('en'));

  testWidgets('the placeholder renders an empty window rather than throwing', (tester) async {
    await pump(tester, ContextUsageSnapshot.placeholder);
    final l10n = await en();

    expect(find.text(l10n.optCtxWindowUnknown), findsOneWidget);
    // Every figure reads as "no number", not as a confident zero.
    expect(find.text('—'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all four legend rows are named', (tester) async {
    await pump(tester, ContextUsageSnapshot.placeholder);
    final l10n = await en();

    for (final label in [
      l10n.optCtxSystemPrompt,
      l10n.optCtxTools,
      l10n.optCtxHistory,
      l10n.optCtxRemaining,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('real figures give a readout and a remainder', (tester) async {
    await pump(
      tester,
      const ContextUsageSnapshot(
        windowChars: 200000,
        slices: {
          ContextUsageSlice.systemPrompt: 18200,
          ContextUsageSlice.tools: 9600,
          ContextUsageSlice.history: 74400,
        },
      ),
    );

    // 18.2K + 9.6K + 74.4K = 102.2K, against a 200K window.
    expect(find.textContaining('102.2K'), findsOneWidget);
    expect(find.text('97.8K'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a session over its window clamps rather than going negative', (tester) async {
    await pump(
      tester,
      const ContextUsageSnapshot(
        windowChars: 1000,
        slices: {
          ContextUsageSlice.systemPrompt: 0,
          ContextUsageSlice.tools: 0,
          ContextUsageSlice.history: 4000,
        },
      ),
    );

    // The two unspent slices and the remainder all read 0 — never "-3.0K".
    expect(find.text('0'), findsNWidgets(3), reason: 'remaining floors at zero');
    expect(find.text('4.0K'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unlimited model shows the spend and no remainder', (tester) async {
    await pump(
      tester,
      const ContextUsageSnapshot(
        windowChars: 0,
        basis: ContextWindowBasis.unlimited,
        slices: {
          ContextUsageSlice.systemPrompt: 18200,
          ContextUsageSlice.tools: 1200,
          ContextUsageSlice.history: 74400,
        },
      ),
    );
    final l10n = await en();

    expect(find.textContaining('93.8K'), findsOneWidget);
    expect(find.textContaining(l10n.optCtxWindowUnlimited), findsOneWidget);
    // The slices are still real; only "remaining" is unanswerable — and a bare
    // 0 there would read as "full", the opposite of the truth.
    expect(find.text('18.2K'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text(l10n.optCtxWindowAssumed), findsNothing);
  });

  testWidgets('a slice nobody has measured yet reads as unknown, not as free', (tester) async {
    // What a session restored from the database looks like: the history is
    // known exactly, the system prompt the next turn will build is not.
    await pump(
      tester,
      const ContextUsageSnapshot(
        windowChars: 200000,
        slices: {ContextUsageSlice.history: 74400},
      ),
    );

    expect(find.text('74.4K'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2), reason: 'system prompt and tools');
    expect(find.text('0'), findsNothing);
  });

  testWidgets('an unset window says so rather than passing the default off as measured',
      (tester) async {
    const slices = {ContextUsageSlice.systemPrompt: 18200};
    await pump(
      tester,
      // What measureContext produces for a model with no window: the default
      // assumption, drawn, and labelled as an assumption.
      const ContextUsageSnapshot(
        windowChars: 49152,
        basis: ContextWindowBasis.assumed,
        slices: slices,
      ),
    );
    final l10n = await en();
    expect(find.text(l10n.optCtxWindowAssumed), findsOneWidget);

    await pump(
      tester,
      const ContextUsageSnapshot(windowChars: 49152, slices: slices),
    );
    expect(find.text(l10n.optCtxWindowAssumed), findsNothing,
        reason: 'a configured window carries no caveat');
  });

  for (final width in [250.0, 600.0]) {
    testWidgets('it fits the right panel at ${width.toInt()}px', (tester) async {
      await pump(
        tester,
        const ContextUsageSnapshot(
          windowChars: 200000,
          slices: {
            ContextUsageSlice.systemPrompt: 18200,
            ContextUsageSlice.tools: 9600,
            ContextUsageSlice.history: 74400,
          },
        ),
        size: Size(width, 900),
      );

      // The panel resizes between these two; a legend label must ellipsize,
      // never overflow.
      expect(tester.takeException(), isNull);
    });
  }
}
