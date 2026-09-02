// `C1 10h`'s two changes to the queue: the filter strip, and a picture on
// every row that has one.
//
// Both are asserted against the rendered screen rather than in isolation,
// because both are about what the *strip* and the *list* look like together —
// a count chip is only wrong next to four others, and a thumbnail is only
// missing next to the rows that have one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/widgets/dashed_border.dart';
import 'package:joycai_image_ai_toolkits/services/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);

    final AppState appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
    // Deliberately *not* marking one running: that leaves 执行中 at zero, which
    // is the count state worth asserting and the one the screenshot fixture
    // never has.
  });

  tearDownAll(() => env.dispose());

  Future<void> open(WidgetTester tester) => mountApp(
        tester,
        env: env,
        screen: AppScreen.tasks,
        size: const Size(1440, 900),
        label: 'queue-rows',
      );

  /// The filter pill labelled [label], anchored on the [Material] that paints
  /// its fill — the nearest one above the label.
  Finder pill(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Material)).first;

  /// The outline drawn around that pill.
  BoxDecoration outlineOf(WidgetTester tester, Finder widget) => tester
      .widgetList<Container>(find.descendant(of: widget, matching: find.byType(Container)))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .first;

  /// The fill *behind* it, which lives on that [Material] rather than on the
  /// [Container] that draws its edge — reading the Container's colour is how
  /// the first version of this test passed while the fill was still a grey
  /// slab.
  Color? fillOf(WidgetTester tester, Finder widget) => tester.widget<Material>(widget).color;

  testWidgets('the selected filter takes the accent ladder, label included',
      (WidgetTester tester) async {
    await open(tester);
    final ColorScheme scheme = Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

    // 全部 is the tab the screen opens on.
    final Finder selected = pill('全部');
    expect((outlineOf(tester, selected).border as Border).top.color, scheme.accentRing);
    expect(fillOf(tester, selected), scheme.accentTint);

    final Text label = tester.widget<Text>(find.text('全部'));
    // Not `primary`: at 13px on a 12% wash of itself that is the exact pairing
    // `onAccentTint` exists to replace.
    expect(label.style?.color, scheme.onAccentTint);
    expect(label.style?.color, isNot(scheme.primary));
  });

  testWidgets('an unselected filter is an outline, not a filled slab',
      (WidgetTester tester) async {
    await open(tester);
    final ColorScheme scheme = Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

    final Finder unselected = pill('已完成');
    expect((outlineOf(tester, unselected).border as Border).top.color, scheme.outlineVariant);
    // Five filled grey pills over a list of white cards read as a second
    // toolbar rather than as a filter that is currently off.
    expect(fillOf(tester, unselected), Colors.transparent);
    expect(fillOf(tester, unselected), isNot(scheme.surfaceContainerHighest));
  });

  testWidgets('a zero count is drawn quieter than a figure', (WidgetTester tester) async {
    await open(tester);
    final ColorScheme scheme = Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

    /// The fill behind the number on the pill labelled [label].
    Color? chipFill(String label) {
      final Iterable<BoxDecoration> boxes = tester
          .widgetList<Container>(find.descendant(of: pill(label), matching: find.byType(Container)))
          .map((Container c) => c.decoration)
          .whereType<BoxDecoration>();
      // The pill's own outline comes first; the chip is the one after it.
      return boxes.length < 2 ? null : boxes.elementAt(1).color;
    }

    // 执行中 is empty here (see setUpAll); 已完成 is not.
    expect(find.text('0'), findsWidgets, reason: 'no tab is empty — the fixture changed');
    expect(chipFill('执行中'), scheme.surfaceContainerHigh);
    expect(chipFill('已完成'), scheme.surfaceContainerHighest);
    // Tone, not hue: nothing here is a state to act on.
    expect(chipFill('执行中'), isNot(scheme.errorContainer));
  });

  testWidgets('the outputs column stays a column of outputs', (WidgetTester tester) async {
    await open(tester);

    // A row with no result shows an empty slot rather than its *source*
    // image. Putting an input where every other row shows a result is the one
    // place a picture must not be ambiguous about which it is — the queue is
    // scanned for "what came out", not "what went in".
    final int withResults = AppState()
        .taskQueue
        .queue
        .where((TaskItem t) => t.resultPaths.isNotEmpty)
        .length;
    final int withSourcesOnly = AppState()
        .taskQueue
        .queue
        .where((TaskItem t) => t.resultPaths.isEmpty && t.imagePaths.isNotEmpty)
        .length;
    expect(withResults, greaterThan(0));
    expect(withSourcesOnly, greaterThan(0), reason: 'fixture no longer exercises the empty slot');

    // The list opens newest-first (`C1 11a`), which puts the finished rows —
    // the ones with pictures — at the bottom, past a 900px viewport. Scroll
    // to them; the builder keeps enough above in its cache extent that the
    // empty slots stay on screen too.
    final Finder list = find.ancestor(
      of: find.byType(DashedBorder).first,
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, -1000));
    await tester.pumpAndSettle();

    // Every image on screen belongs to a task that produced one.
    expect(find.byType(Image), findsAtLeast(withResults));
    expect(find.byType(DashedBorder), findsWidgets);
  });

  testWidgets('a failed task says so where its result would be',
      (WidgetTester tester) async {
    await open(tester);

    // Filled with a mark rather than dashed: this task *should* have produced
    // something, and the difference from "not yet" is worth a pixel of weight.
    expect(find.byIcon(Icons.image_not_supported_outlined), findsWidgets);
  });

  testWidgets('a running row does not grow taller than a settled one',
      (WidgetTester tester) async {
    // `10h` runs the progress along the row's bottom edge and says why: every
    // row below a task that starts jumped down 16px, and back up when it
    // finished, which on a working queue is a list that will not hold still.
    await open(tester);
    markOneTaskRunning(AppState());
    await tester.pump();

    final Iterable<double> heights =
        tester.widgetList<Material>(find.byType(Material)).isEmpty
            ? const <double>[]
            : tester
                .renderObjectList<RenderBox>(find.byType(InkWell))
                .map((RenderBox b) => b.size.height)
                .where((double h) => h > 60 && h < 140);
    expect(heights, isNotEmpty);
    // Every row in the list is the same height, running or not.
    expect(heights.toSet(), hasLength(1), reason: 'rows: $heights');
  });
}
