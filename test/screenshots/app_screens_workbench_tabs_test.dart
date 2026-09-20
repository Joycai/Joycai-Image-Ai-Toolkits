// Screenshots of every workbench tab past tab 0, seeded into the state its
// frame is about, plus the prompt assistant at iPad width. See
// docs/ui-screenshot-harness.md.
//
//   flutter test test/screenshots
//   flutter test test/screenshots/app_screens_workbench_tabs_test.dart

@Tags(<String>['screenshots'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  // The workbench is eight screens wearing one nav entry, and the matrix
  // only ever photographs tab 0. The crop editor and the prompt assistant —
  // two of the three pages the design spec redraws in full — were therefore
  // never rendered at all, which is how a grid that only appears mid-drag and
  // a composer still wearing the old grey fill both survived a design pass.
  //
  // Each needs its tab's own state seeded before mount, so they take `before`
  // rather than riding the matrix.
  for (final _WorkbenchTab tab in _workbenchTabs) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('workbench · ${tab.name} @ desktop ${brightness.name}', (
        WidgetTester tester,
      ) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.workbench,
          size: kShotSizes.last,
          brightness: brightness,
          suffix: tab.name,
          before: (WidgetTester tester) async {
            final AppState appState = AppState();
            appState.setWorkbenchTab(tab.index);
            // In real time: a seed may read the fixture database.
            if (!tab.seedOnSettled) await tester.runAsync(() async => tab.seed(appState));
          },
          after: tab.seedOnSettled
              ? (WidgetTester tester) async {
                  await tab.seed(AppState());
                  await tester.pump();
                }
              : null,
        );
      });
    }
  }

  // The prompt assistant at iPad width. It is the only tab that keeps both side
  // panels, so it is the only one that can run out of centre — and the size
  // band it ran out in (screen over the desktop breakpoint, content box under
  // it) is the one the matrix never photographed. Light only: this shot is
  // about widths, and the desktop pass already covers both brightnesses.
  testWidgets('workbench · assistant @ ipad light', (WidgetTester tester) async {
    final _WorkbenchTab tab = _workbenchTabs.firstWhere((t) => t.name == 'assistant');
    await shoot(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: kShotSizes.firstWhere((ShotSize s) => s.label == 'ipad'),
      suffix: tab.name,
      before: (_) async {
        final AppState appState = AppState();
        appState.setWorkbenchTab(tab.index);
        tab.seed(appState);
      },
      // Scrolled to the end of the transcript, because the refined-prompt card
      // is the part of this screen worth photographing and the run console
      // leaves the transcript barely 300px to show it in. A restored session
      // opens at the top — only a live reply auto-scrolls — so the shot would
      // otherwise be of the card's first two lines.
      after: (WidgetTester tester) async {
        final Finder transcript = find.descendant(
          of: find.byType(ListView),
          matching: find.text('优化提示词'),
        );
        if (transcript.evaluate().isEmpty) return;
        await tester.drag(transcript.first, const Offset(0, -400));
        await tester.pump();
      },
    );
  });
}

class _WorkbenchTab {
  const _WorkbenchTab(this.name, this.index, this.seed, {this.seedOnSettled = false});
  final String name;
  final int index;
  final FutureOr<void> Function(AppState appState) seed;

  /// Seed after the first frame instead of before it.
  ///
  /// For state the screen's own mount would undo: the gallery rescans on
  /// mount and the scan rebuilds its [AppImage] list, dropping a selection
  /// made against the previous instances. Seeding on the settled tree is the
  /// same order a user produces.
  final bool seedOnSettled;
}

/// Indices match the `switch` in `workbench_screen.dart`'s build.
final List<_WorkbenchTab> _workbenchTabs = <_WorkbenchTab>[
  // Tab 0 again, but with pictures selected: the config panel's reference
  // strip is empty otherwise, and the strip is where the selection order the
  // model receives is shown and edited.
  _WorkbenchTab('selection', 0, (AppState s) => seedImageSelection(s), seedOnSettled: true),
  // One entry per arrangement: the three are separate rendering paths, not
  // three settings of one, and only the default would ever be photographed
  // otherwise.
  _WorkbenchTab('comparator', 1, seedComparatorPair),
  _WorkbenchTab('comparator_stacked', 1, (AppState s) {
    seedComparatorPair(s);
    s.workbenchUIState.setComparatorLayout(ComparatorLayout.stacked);
  }),
  _WorkbenchTab('comparator_slider', 1, (AppState s) {
    seedComparatorPair(s);
    s.workbenchUIState.setComparatorLayout(ComparatorLayout.slider);
  }),
  // The empty state is the first thing anyone opening the comparator sees,
  // and it is a screen of its own, not a placeholder — the spec draws it as a
  // frame of its own too.
  //
  // Cleared rather than merely unseeded. `WorkbenchUIState` outlives the
  // shots, so leaving this one to seed nothing meant it photographed whatever
  // the three comparator shots before it had left in place: this "empty" state
  // has been a picture of two loaded images for as long as it has existed.
  _WorkbenchTab('comparator_empty', 1, (AppState s) => s.workbenchUIState.clearComparator()),
  _WorkbenchTab('mask', 2, seedMaskSource),
  _WorkbenchTab('crop', 3, seedCropSource),
  _WorkbenchTab('assistant', 4, seedOptimizerSession),
  // The two frames `A2` added beside the finished one. Neither is
  // reachable from the settled fixture: the running state exists only
  // while a model is being called, and system-prompt mode replaces the
  // whole right column with a card the knowledge modes never draw.
  _WorkbenchTab('assistant_running', 4, seedOptimizerRunning),
  _WorkbenchTab('assistant_sysprompt', 4, seedOptimizerSystemPrompt),
  _WorkbenchTab('assistant_kbedit', 4, seedOptimizerKbEdit),
  // `A3e 5e`: an analysis preset's answer — a reply with a copy row, not a
  // card — and the prompt card the same session can still produce.
  _WorkbenchTab('assistant_analysis', 4, seedOptimizerAnalysis),
  // The other half of the workbench. It has its own right panel — model,
  // resolution, aspect, duration, the first/last-frame drop targets — and
  // shares nothing with tab 0's below the shell, so leaving it out meant half
  // the workbench was never photographed at all. Seeded with a selection, as
  // the frame slots are the point and they are empty without one.
  _WorkbenchTab('video', 5, (AppState s) => seedImageSelection(s), seedOnSettled: true),
  // The same panel once it is used: both frames and two references filled.
  // Last in the list because `WorkbenchUIState` outlives the shots, and every
  // shot after this one would otherwise inherit the filled slots.
  _WorkbenchTab('video_filled', 5, seedVideoInputs, seedOnSettled: true),
];
