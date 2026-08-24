// Renders every screen of the real app to a PNG in build/ui-screenshots/.
//
//   flutter test test/screenshots
//   flutter test test/screenshots --plain-name workbench
//
// This is a debugging tool, not a regression gate: the comparator installed by
// flutter_test_config.dart always overwrites and always passes. See
// docs/ui-screenshot-harness.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_segmented_control.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    // Order matters: the environment must exist before the first AppState()
    // touch, and the seed before loadSettings() reads it back.
    env = installFixtureEnv(binding);
    await seedFixtures(env);

    final AppState appState = AppState();
    await appState.loadSettings();
    // setUpAll runs in real async (no fake-async zone), which is the only place
    // the compute()-based gallery and file-browser scans actually complete.
    await Future<void>.delayed(const Duration(seconds: 1));
    markOneTaskRunning(appState);
  });

  tearDownAll(() => env.dispose());

  for (final AppScreen screen in AppScreen.values) {
    for (final ShotSize size in kShotSizes) {
      testWidgets('${screen.name} @ ${size.label}', (WidgetTester tester) async {
        await shoot(tester, env: env, screen: screen, size: size);
      });
    }

    testWidgets('${screen.name} @ desktop dark', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: screen,
        size: kShotSizes.last,
        brightness: Brightness.dark,
      );
    });
  }

  // The workbench is eight screens wearing one nav entry, and the loop above
  // only ever photographs tab 0. The crop editor and the prompt assistant —
  // two of the three pages the design spec redraws in full — were therefore
  // never rendered at all, which is how a grid that only appears mid-drag and
  // a composer still wearing the old grey fill both survived a design pass.
  //
  // Each needs its tab's own state seeded before mount, so they take `before`
  // rather than riding the loop.
  for (final _WorkbenchTab tab in _workbenchTabs) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('workbench · ${tab.name} @ desktop ${brightness.name}',
          (WidgetTester tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.workbench,
          size: kShotSizes.last,
          brightness: brightness,
          suffix: tab.name,
          before: (_) async {
            final AppState appState = AppState();
            appState.setWorkbenchTab(tab.index);
            if (!tab.seedOnSettled) tab.seed(appState);
          },
          after: tab.seedOnSettled
              ? (WidgetTester tester) async {
                  tab.seed(AppState());
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
  // it) is the one the loop above never photographed. Light only: this shot is
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

  // The fee-group editor (spec 10j / 10k). Two taps deep behind a tab index
  // that lives in the usage screen's own State, so nothing in AppState can
  // reach it — which is how a dialog the spec devotes two of its twelve frames
  // to went unphotographed. Driven the way a user reaches it instead.
  for (final _FeeGroupShot shot in _feeGroupShots) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('feeGroupEditor · ${shot.name} @ desktop ${brightness.name}',
          (WidgetTester tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.usage,
          size: kShotSizes.last,
          brightness: brightness,
          suffix: shot.name,
          after: (WidgetTester tester) async {
            // `of` scopes the search, and the per-request shot is why it
            // exists: "按次计费" is both a segment inside the dialog and the
            // mode badge on a card behind it, and an unscoped `.first` found
            // the card — a tap outside the barrier, which closed the dialog
            // the shot was meant to photograph.
            Future<void> tapText(String label, {Finder? of}) async {
              final Finder finder = of == null
                  ? find.text(label)
                  : find.descendant(of: of, matching: find.text(label));
              if (finder.evaluate().isEmpty) return;
              await tester.tap(finder.first, warnIfMissed: false);
              for (int i = 0; i < 4; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            }

            await tapText('费率组');
            await shot.open(tester, tapText);
          },
        );
      });
    }
  }

  // The add-channel dialog (spec D2 12o). It is two layouts of one dialog —
  // a single page with a provider rail beside the form at desktop width, and
  // a two-step flow below the tablet breakpoint — and which one renders is
  // decided by the window, so a single shot could never show both. Neither is
  // reachable from AppState; both are driven the way a user reaches them.
  // `step2` walks the fallback past its picker: step 1 is the same card grid
  // the wizard always had, and the merged connection-plus-appearance step is
  // the half worth looking at.
  for (final (String sizeLabel, bool step2) in const <(String, bool)>[
    ('desktop', false),
    ('tablet', false),
    ('tablet', true),
  ]) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets(
          'channelWizard @ $sizeLabel ${brightness.name}${step2 ? ' step2' : ''}',
          (WidgetTester tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.models,
          size: kShotSizes.firstWhere((ShotSize s) => s.label == sizeLabel),
          brightness: brightness,
          suffix: step2 ? 'wizard2' : 'wizard',
          after: (WidgetTester tester) async {
            Future<void> settle() async {
              for (int i = 0; i < 5; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            }

            Future<bool> tapText(String label) async {
              final Finder finder = find.text(label);
              if (finder.evaluate().isEmpty) return false;
              await tester.tap(finder.first, warnIfMissed: false);
              await settle();
              return true;
            }

            // Narrow layouts put the channel list behind a tab; on desktop it
            // is already on screen and this is a no-op.
            await tapText('渠道管理');
            // The add action is a labelled button on desktop and a tooltipped
            // icon on narrow layouts; accept either spelling.
            Finder add = find.text('添加渠道');
            if (add.evaluate().isEmpty) add = find.byTooltip('添加渠道');
            if (add.evaluate().isEmpty) return;
            await tester.tap(add.first, warnIfMissed: false);
            await settle();
            if (step2) await tapText('下一步');
          },
        );
      });
    }
  }

  // The channel editor (spec D2 15a / 15c). Desktop is a 680-wide two-column
  // dialog reached from the detail header's pencil; mobile is a fullscreen
  // page reached by tapping a row in the channels tab.
  for (final (String sizeLabel, Brightness brightness) in const <(String, Brightness)>[
    ('desktop', Brightness.light),
    ('desktop', Brightness.dark),
    ('mobile', Brightness.light),
  ]) {
    testWidgets('channelEditor @ $sizeLabel ${brightness.name}',
        (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: kShotSizes.firstWhere((ShotSize s) => s.label == sizeLabel),
        brightness: brightness,
        suffix: 'channelEdit',
        after: (WidgetTester tester) async {
          Future<void> settle() async {
            for (int i = 0; i < 5; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }

          if (sizeLabel == 'mobile') {
            // The channels tab, then the row itself opens the editor.
            await tester.tap(find.text('渠道管理').first, warnIfMissed: false);
            await settle();
            await tester.tap(find.text('中转 · OpenAI 兼容').first, warnIfMissed: false);
            await settle();
          } else {
            final Finder edit = find.byTooltip('编辑');
            if (edit.evaluate().isEmpty) return;
            await tester.tap(edit.first, warnIfMissed: false);
            await settle();
          }
        },
      );
    });
  }

  // The model editor (spec D2 13a / 13b / 13c). One dialog in two layouts —
  // a single column below 1100 and two panes with a summary card above it —
  // decided by the window, so it takes one shot per band. `newModel` is 13b:
  // the empty form, whose footer states why Save is unavailable.
  //
  // GPT-5 Chat rather than whichever model the screen opens on: it is the
  // fixture's only OpenAI-format model, and the reasoning-effort field — the
  // one control the protocol family adds or removes — exists nowhere else.
  for (final (String sizeLabel, bool newModel, Brightness brightness)
      in const <(String, bool, Brightness)>[
    ('desktop', false, Brightness.light),
    ('desktop', false, Brightness.dark),
    ('desktop', true, Brightness.light),
    ('tablet', false, Brightness.light),
    ('mobile', false, Brightness.light),
  ]) {
    testWidgets(
        'modelEditor @ $sizeLabel ${brightness.name}${newModel ? ' new' : ''}',
        (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: kShotSizes.firstWhere((ShotSize s) => s.label == sizeLabel),
        brightness: brightness,
        suffix: newModel ? 'editorNew' : 'editor',
        after: (WidgetTester tester) async {
          Future<bool> tapText(String label) async {
            final Finder finder = find.text(label);
            if (finder.evaluate().isEmpty) return false;
            await tester.tap(finder.first, warnIfMissed: false);
            for (int i = 0; i < 5; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            return true;
          }

          // On a phone the models tab is already the one on screen and each
          // channel is a collapsed ExpansionTile, so the channel tap opens the
          // list rather than selecting a column. Taking the desktop detour
          // there lands on the channels tab and edits the channel instead.
          if (sizeLabel != 'mobile') await tapText('渠道管理');
          await tapText('中转 · OpenAI 兼容');
          await tapText(newModel ? '添加模型' : 'GPT-5 Chat');
        },
      );
    });
  }
}

class _FeeGroupShot {
  const _FeeGroupShot(this.name, this.open);
  final String name;

  /// Runs on the fee-group tab. `tapText` taps a label and settles; it is a
  /// no-op when the label is absent, so a shot degrades to the state before it
  /// rather than failing the whole run on a copy change.
  final Future<void> Function(
    WidgetTester tester,
    Future<void> Function(String label, {Finder? of}) tapText,
  ) open;
}

final List<_FeeGroupShot> _feeGroupShots = <_FeeGroupShot>[
  // 10j: adding, empty, token mode.
  _FeeGroupShot('add', (_, tapText) async {
    await tapText('添加费率组');
  }),
  // 10j, per-request mode — the branch that swaps all three price fields for
  // one, and the only place the new "billed per request" hint appears.
  _FeeGroupShot('addRequest', (_, tapText) async {
    await tapText('添加费率组');
    await tapText('按次计费', of: find.byType(AppSegmentedControl<String>));
  }),
  // 10k: editing, with data. The seeded groups are named in fixture_seed.
  _FeeGroupShot('edit', (_, tapText) async {
    await tapText('Gemini Flash');
  }),
];

class _WorkbenchTab {
  const _WorkbenchTab(this.name, this.index, this.seed, {this.seedOnSettled = false});
  final String name;
  final int index;
  final void Function(AppState appState) seed;

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
  // The other half of the workbench. It has its own right panel — model,
  // resolution, aspect, duration, the first/last-frame drop targets — and
  // shares nothing with tab 0's below the shell, so leaving it out meant half
  // the workbench was never photographed at all. Seeded with a selection, as
  // the frame slots are the point and they are empty without one.
  _WorkbenchTab('video', 5, (AppState s) => seedImageSelection(s), seedOnSettled: true),
];
