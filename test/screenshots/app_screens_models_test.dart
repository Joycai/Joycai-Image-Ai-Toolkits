// Screenshots of the models and usage screens: the screen matrix, the
// fee-group editor, the add-channel dialog, the channel editor and the
// channel rail's hover handle. The model editor is in
// app_screens_model_editor_test.dart. See docs/ui-screenshot-harness.md.
//
//   flutter test test/screenshots
//   flutter test test/screenshots/app_screens_models_test.dart

@Tags(<String>['screenshots'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_segmented_control.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  shootMatrix(() => env, const <AppScreen>[AppScreen.models, AppScreen.usage]);

  // The fee-group editor (spec 10j / 10k). Two taps deep behind a tab index
  // that lives in the usage screen's own State, so nothing in AppState can
  // reach it — which is how a dialog the spec devotes two of its twelve frames
  // to went unphotographed. Driven the way a user reaches it instead.
  for (final _FeeGroupShot shot in _feeGroupShots) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('feeGroupEditor · ${shot.name} @ desktop ${brightness.name}', (
        WidgetTester tester,
      ) async {
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
      testWidgets('channelWizard @ $sizeLabel ${brightness.name}${step2 ? ' step2' : ''}', (
        WidgetTester tester,
      ) async {
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
    testWidgets('channelEditor @ $sizeLabel ${brightness.name}', (WidgetTester tester) async {
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

  // The channel rail's drag handle (spec D2 19a, 方案乙). The whole argument
  // for hover-reveal over an always-on grip is that the resting rail is
  // untouched, so the shot that matters is the hovered one: the handle sits
  // inside the row's existing left padding and nothing else has moved.
  // Platform is forced to macOS because the reveal is pointer-only — on a
  // touch platform the row is picked up by long press and never shows a
  // handle at rest.
  testWidgets('channelHover @ desktop light', (WidgetTester tester) async {
    // Reset inside the body, not via addTearDown: the framework asserts that
    // no foundation debug variable outlives the test, and tear-downs run
    // after that check.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: kShotSizes.firstWhere((ShotSize s) => s.label == 'desktop'),
        brightness: Brightness.light,
        suffix: 'channelHover',
        after: (WidgetTester tester) async {
          final TestGesture pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await pointer.addPointer(location: Offset.zero);
          addTearDown(pointer.removePointer);
          await pointer.moveTo(tester.getCenter(find.text('阿里云百炼')));
          for (int i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 60));
          }
        },
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
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
  )
  open;
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
    await tapText('按次', of: find.byType(AppSegmentedControl<String>));
  }),
  // D2b 21d ④: adding in spec mode — the initial state is the pinned
  // 「其他规格」 row alone, with the hint and the 「改用按次」 offer.
  _FeeGroupShot('addSpec', (_, tapText) async {
    await tapText('添加费率组');
    await tapText('按规格', of: find.byType(AppSegmentedControl<String>));
  }),
  // 10k: editing, with data. The seeded groups are named in fixture_seed.
  _FeeGroupShot('edit', (_, tapText) async {
    await tapText('Gemini Flash');
  }),
  // D2b 21b: the spec editor over a seeded four-row table.
  _FeeGroupShot('editSpec', (tester, tapText) async {
    await tapText('Veo 3 视频');
    // The editor opens below three group rows; bring its table into frame.
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -420));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }),
];
