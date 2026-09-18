// Screenshots of the workbench: the screen matrix, the image panel with a
// selection live, a card's context menu, and both model cards open. The other tabs are in
// app_screens_workbench_tabs_test.dart. See docs/ui-screenshot-harness.md.
//
//   flutter test test/screenshots
//   flutter test test/screenshots/app_screens_workbench_test.dart

@Tags(<String>['screenshots'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/image_card.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  shootMatrix(() => env, const <AppScreen>[AppScreen.workbench]);

  // The image workbench with a selection live (spec A1 16a). Tab 0's own
  // matrix shot only ever catches the empty state, and the right column is a
  // different panel with images picked: the strip of thumbnails, the model
  // section and the action bar's count all appear only then.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('workbench · selection @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.workbench,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'selection',
        // `16a` draws the console collapsed. Left expanded it eats half the
        // window, and the config panel — the whole point of this shot — is
        // then photographed at a height it never has in the design.
        before: (_) async {
          // Tab 0 explicitly: the workbench tab is app state, so whichever
          // tab the previous test in this file left selected is the one this
          // would otherwise photograph — the dark pass was shooting the video
          // panel under the name of the image one.
          AppState().setWorkbenchTab(0);
          AppState().isConsoleExpanded = false;
        },
        // Seeded on the *settled* tree, not before mount: the selection lives
        // on GalleryState's view list, and which images that holds depends on
        // the folder scan having finished. Cleared first because
        // [seedImageSelection] toggles — the second brightness would otherwise
        // deselect what the first picked and shoot "已选择 0 项".
        after: (WidgetTester tester) async {
          AppState().clearImageSelection();
          seedImageSelection(AppState());
          for (int p = 0; p < 5; p++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
        },
      );
    });
  }

  // A card's context menu (`A1 · 2a`): the quick block, the 「设为」 grid, the
  // two submenu rows and the destructive tail — with 「文件 ▸」 opened, so the
  // submenu's placement beside the panel, level with its row, is on film.
  Finder menuItem(String label) => find.descendant(
        of: find.byType(AppGlassMenu),
        matching: find.text(label),
      );

  for (final Brightness brightness in Brightness.values) {
    testWidgets('workbench · contextMenu @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.workbench,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'contextMenu',
        before: (_) async {
          AppState().setWorkbenchTab(0);
          AppState().isConsoleExpanded = false;
          AppState().clearImageSelection();
        },
        after: (WidgetTester tester) async {
          await tester.tap(find.byType(ImageCard).first, buttons: kSecondaryButton);
          await settle(tester);
          await tester.tap(menuItem('文件'));
          await settle(tester);
        },
      );
    });
  }

  // The same panel with the model card open — `16a` draws it that way, and
  // the two pickers plus the parameter rows under them are the only place in
  // the app the channel/model pair is drawn side by side, so a collapsed card
  // photographs none of what that frame settles. Same for `A6`'s video card.
  for (final _ModelCardShot card in const <_ModelCardShot>[
    _ModelCardShot(tab: 0, suffix: 'modelCard'),
    _ModelCardShot(tab: 5, suffix: 'videoModelCard'),
  ]) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('workbench · ${card.suffix} @ desktop ${brightness.name}', (
        WidgetTester tester,
      ) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.workbench,
          size: kShotSizes.last,
          brightness: brightness,
          suffix: card.suffix,
          before: (_) async {
            AppState().setWorkbenchTab(card.tab);
            AppState().isConsoleExpanded = false;
          },
          after: (WidgetTester tester) async {
            if (card.tab == 0) {
              AppState().clearImageSelection();
              seedImageSelection(AppState());
              for (int p = 0; p < 5; p++) {
                await tester.pump(const Duration(milliseconds: 120));
              }
            }
            await tester.tap(find.text('模型选择').last);
            for (int p = 0; p < 5; p++) {
              await tester.pump(const Duration(milliseconds: 120));
            }
          },
        );
      });
    }
  }
  // D1e 3c: the model card on Seedream — each generation grows only the
  // controls its table declares.
  for (final (String modelId, String suffix, Brightness brightness)
      in const <(String, String, Brightness)>[
    ('doubao-seedream-5-0-pro-260628', 'seedreamPro', Brightness.light),
    ('doubao-seedream-5-0-pro-260628', 'seedreamPro', Brightness.dark),
    ('doubao-seedream-5.0-lite', 'seedreamLite', Brightness.light),
  ]) {
    testWidgets('workbench · $suffix @ desktop ${brightness.name}', (
      WidgetTester tester,
    ) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.workbench,
        // Taller than the desktop shot: six controls outgrow a 900 px
        // window's card, and the card scrolls rather than showing them.
        size: const ShotSize('desktop', Size(1440, 1300)),
        brightness: brightness,
        suffix: suffix,
        before: (_) async {
          AppState().setWorkbenchTab(0);
          AppState().isConsoleExpanded = false;
          AppState().lastSelectedModelId = modelId;
        },
        after: (WidgetTester tester) async {
          AppState().clearImageSelection();
          seedImageSelection(AppState());
          for (int p = 0; p < 5; p++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
          await tester.tap(find.text('模型选择').last);
          for (int p = 0; p < 5; p++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
        },
      );
    });
  }
}

class _ModelCardShot {
  const _ModelCardShot({required this.tab, required this.suffix});

  final int tab;
  final String suffix;
}
