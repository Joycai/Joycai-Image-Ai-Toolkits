// Renders every screen of the real app to a PNG in build/ui-screenshots/.
//
//   flutter test test/screenshots
//   flutter test test/screenshots --plain-name workbench
//
// This is a debugging tool, not a regression gate: the comparator installed by
// flutter_test_config.dart always overwrites and always passes. See
// docs/ui-screenshot-harness.md.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:joycai_image_ai_toolkits/services/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/services/task_list_ordering.dart';
import 'package:joycai_image_ai_toolkits/widgets/task_capsule_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
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

  // The staging area only exists once something is in it, and the loop above
  // photographs the browser with an empty one — which is the one state of this
  // feature that shows none of it. `12a` is the frame being implemented here,
  // so it gets its own shot with the panel populated, a destination named, a
  // selection live (floating bar) and a mark that has gone stale.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('fileBrowser · staging @ desktop ${brightness.name}', (
      WidgetTester tester,
    ) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'staging',
        before: (WidgetTester tester) async {
          final AppState appState = AppState();
          final browser = appState.fileBrowserState;
          final staging = appState.fileStagingState;

          staging.clear();
          staging.addAll(browser.filteredFiles.take(5));
          // A mark whose file is gone — the panel has to keep showing it.
          staging.addAll(<BrowserFile>[
            BrowserFile(
              path: p.join(env.browserDir.path, 'deleted_by_someone_else.png'),
              name: 'deleted_by_someone_else.png',
              category: FileCategory.image,
              size: 0,
              modified: DateTime(2026, 8, 1),
            ),
          ]);
          // `runAsync`, not a bare await: `before` runs inside the test's
          // fake-async zone, where a real `File.stat()` never completes and the
          // await hangs the shot forever.
          await tester.runAsync(() => staging.revalidate());
          staging.setDestination(env.browserDir.path);

          browser.clearSelection();
          for (final BrowserFile f in browser.filteredFiles.skip(4).take(3)) {
            browser.toggleSelection(f);
          }
        },
      );
    });
  }

  // `B1a 12c` — the panel with nothing in it. The loop above photographs the
  // browser with an empty staging area, but the panel only opens itself once
  // something is staged, so the state that has to explain the feature was the
  // one state never rendered.
  testWidgets('fileBrowser · stagingEmpty @ desktop light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: kShotSizes.last,
      suffix: 'stagingEmpty',
      before: (WidgetTester tester) async {
        final AppState appState = AppState();
        appState.fileStagingState.clear();
        appState.fileStagingState.setDestination(null);
        appState.fileBrowserState.clearSelection();
      },
      after: (WidgetTester tester) async {
        await tester.tap(find.byTooltip('暂存区').first);
        for (int i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      },
    );
  });

  // `B1a 12e` — the conflict pass. Needs a real name collision on disk, so the
  // fixture grows a subfolder holding a file the staged one would land on.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('fileBrowser · conflicts @ desktop ${brightness.name}', (
      WidgetTester tester,
    ) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'conflicts',
        before: (WidgetTester tester) async {
          final AppState appState = AppState();
          final browser = appState.fileBrowserState;
          final staging = appState.fileStagingState;

          final Directory dest =
              Directory(p.join(env.browserDir.path, 'archive'));
          // Real files, written through runAsync: `before` runs in the
          // fake-async zone where dart:io never completes.
          await tester.runAsync(() async {
            if (!await dest.exists()) await dest.create();
            for (final BrowserFile f in browser.filteredFiles.take(3)) {
              await File(p.join(dest.path, f.name)).writeAsString('older copy');
            }
          });

          staging.clear();
          staging.addAll(browser.filteredFiles.take(3));
          staging.setDestination(dest.path);
          browser.clearSelection();
        },
        after: (WidgetTester tester) async {
          await tester.runAsync(() async {
            await tester.tap(find.text('移动到此'));
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 500));
          });
          for (int i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
        },
      );
    });
  }

  // The AI rename dialog — `B4 13a`. Its result states need a live model, so
  // only the opened-but-not-generated frame is reachable here; that still
  // covers the shell, the config column, the result toolbar, the empty state
  // and the footer, which is where the redraw's shape lives.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('fileBrowser · aiRename @ desktop ${brightness.name}', (
      WidgetTester tester,
    ) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'aiRename',
        before: (WidgetTester tester) async {
          final AppState appState = AppState();
          appState.fileStagingState.clear();
          final browser = appState.fileBrowserState;
          browser.clearSelection();
          for (final BrowserFile f in browser.filteredFiles.take(6)) {
            browser.toggleSelection(f);
          }
        },
        after: (WidgetTester tester) async {
          // Tap and wait inside `runAsync`: the dialog reads its templates and
          // its last-used model out of the database on mount, and that real
          // I/O never completes in the fake-async zone. Without it the shot
          // photographs an empty config column and calls it the design.
          await tester.runAsync(() async {
            await tester.tap(find.text('AI 批量重命名').last);
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 600));
          });
          for (int i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
        },
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

  // The image workbench with a selection live (spec A1 16a). Tab 0's own
  // loop shot only ever catches the empty state, and the right column is a
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

  // A queue row opened. `C1 10i` is most of what a row can show — the log, the
  // parameters, the outputs, the way out — and all of it is behind a tap, so
  // the loop above only ever photographs the collapsed third of this screen.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('tasks · expanded @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.tasks,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'expanded',
        // Console collapsed: the panel is the point of this shot, and an
        // expanded console leaves it a third of the window to open into.
        before: (_) async => AppState().isConsoleExpanded = false,
        after: (WidgetTester tester) async {
          // The failed row: the one whose detail panel has something to say.
          await tester.tap(find.text('source_4.png'));
          for (int p = 0; p < 5; p++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        },
      );
    });
  }

  // The phone's more-menu (`C1 11c`): sort, pin and the bulk actions, all
  // behind one button, and a hand-positioned `showMenu` — the one thing on
  // this screen a wrong anchor would put off the edge of a 375px window.
  testWidgets('tasks · menu @ mobile light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.tasks,
      size: kShotSizes.first,
      brightness: Brightness.light,
      suffix: 'menu',
      after: (WidgetTester tester) async {
        await tester.tap(find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert),
        ));
        for (int p = 0; p < 5; p++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );
  });

  // A filter with nothing in it (`C1 11d`): the counts stay, the block is a
  // size down from the queue's own empty state, and the one button puts the
  // filter back. The fixture has every status, so the failed rows are lifted
  // out of the live queue for the shot and put back after it.
  testWidgets('tasks · filteredEmpty @ desktop light', (WidgetTester tester) async {
    final List<TaskItem> queue = AppState().taskQueue.queue;
    final List<TaskItem> lifted = queue
        .where((TaskItem t) => t.status == TaskStatus.failed || t.status == TaskStatus.cancelled)
        .toList();
    try {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.tasks,
        size: kShotSizes.last,
        brightness: Brightness.light,
        suffix: 'filteredEmpty',
        before: (_) async {
          queue.removeWhere(lifted.contains);
          AppState().taskListState.setFilter(TaskFilter.failed);
        },
      );
    } finally {
      queue.addAll(lifted);
      AppState().taskListState.setFilter(TaskFilter.all);
      AppState().taskQueue.refreshQueue();
    }
  });

  // The floating task capsule, opened. It is only on screen while the queue has
  // work and no screen is already showing that queue, and its interesting half
  // — the per-task rows — is behind a tap, so no shot in the loop above has
  // ever caught it. Photographed on the prompts screen for the first reason:
  // `C1` keeps it off both the workbench and the queue.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('prompts · capsule @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.prompts,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'capsule',
        after: (WidgetTester tester) async {
          await tester.tap(find.byType(TaskCapsuleMonitor));
          for (int p = 0; p < 5; p++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        },
      );
    });
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
    testWidgets('modelEditor @ $sizeLabel ${brightness.name}${newModel ? ' new' : ''}', (
      WidgetTester tester,
    ) async {
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

  // The protocol selector (spec D2 18a state ③): the one dialog state the
  // GPT-5 shot cannot show, because only the DashScope fixture channel has a
  // menu longer than one entry. wan2.7-image is seeded pinned to the async
  // task, so this frame carries the selector, the dimmed streaming toggle
  // and the queue note in one shot.
  for (final Brightness brightness in const <Brightness>[Brightness.light, Brightness.dark]) {
    testWidgets('modelEditor protocol @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: kShotSizes.firstWhere((ShotSize s) => s.label == 'desktop'),
        brightness: brightness,
        suffix: 'editorProtocol',
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

          await tapText('渠道管理');
          await tapText('阿里云百炼');
          await tapText('万相 2.7 图像');
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
  // The two frames `A2` added beside the finished one. Neither is
  // reachable from the settled fixture: the running state exists only
  // while a model is being called, and system-prompt mode replaces the
  // whole right column with a card the knowledge modes never draw.
  _WorkbenchTab('assistant_running', 4, seedOptimizerRunning),
  _WorkbenchTab('assistant_sysprompt', 4, seedOptimizerSystemPrompt),
  _WorkbenchTab('assistant_kbedit', 4, seedOptimizerKbEdit),
  // The other half of the workbench. It has its own right panel — model,
  // resolution, aspect, duration, the first/last-frame drop targets — and
  // shares nothing with tab 0's below the shell, so leaving it out meant half
  // the workbench was never photographed at all. Seeded with a selection, as
  // the frame slots are the point and they are empty without one.
  _WorkbenchTab('video', 5, (AppState s) => seedImageSelection(s), seedOnSettled: true),
];
