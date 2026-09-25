// Screenshots of the model editor: its layout bands, the new-model form, the
// protocol selector and the relay states. See docs/ui-screenshot-harness.md.
//
//   flutter test test/screenshots
//   flutter test test/screenshots/app_screens_model_editor_test.dart

@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

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

  // Spec D2a: the relay states of the same editor. Each shot opens one seeded
  // model — see fixture_seed for why each exists — and photographs it at the
  // sizes and brightnesses its frame is about.
  for (final _EditorShot shot in _editorShots) {
    for (final String sizeLabel in shot.sizes) {
      for (final Brightness brightness in shot.brightnesses) {
        testWidgets('modelEditor ${shot.suffix} @ $sizeLabel ${brightness.name}', (
          WidgetTester tester,
        ) async {
          await shoot(
            tester,
            env: env,
            screen: AppScreen.models,
            size: kShotSizes.firstWhere((ShotSize s) => s.label == sizeLabel),
            brightness: brightness,
            suffix: shot.suffix,
            after: (WidgetTester tester) async {
              Future<void> tapText(String label) async {
                final Finder finder = find.text(label);
                if (finder.evaluate().isEmpty) return;
                await tester.tap(finder.first, warnIfMissed: false);
                for (int i = 0; i < 5; i++) {
                  await tester.pump(const Duration(milliseconds: 100));
                }
              }

              // Same detour rule as the GPT-5 shot above: on a phone the
              // models tab is already on screen, and 「渠道管理」 would land on
              // the channel editor instead of the model.
              if (sizeLabel != 'mobile') await tapText('渠道管理');
              await tapText(shot.channel);
              await tapText(shot.model);
              // A phone's single column puts the section below the fold; the
              // frame (20j) is about the section, so bring its caption to the
              // top of the dialog's scroll view.
              if (sizeLabel == 'mobile') {
                final Finder caption = find.text('接口协议');
                if (caption.evaluate().isNotEmpty) {
                  await tester.ensureVisible(caption.first);
                  for (int i = 0; i < 5; i++) {
                    await tester.pump(const Duration(milliseconds: 100));
                  }
                }
              }
            },
          );
        });
      }
    }
  }
}

/// One D2a editor frame: which seeded model to open, from which channel.
class _EditorShot {
  const _EditorShot(
    this.suffix,
    this.channel,
    this.model, {
    this.sizes = const <String>['desktop'],
    this.brightnesses = const <Brightness>[Brightness.light],
  });

  final String suffix;
  final String channel;
  final String model;
  final List<String> sizes;
  final List<Brightness> brightnesses;
}

const List<_EditorShot> _editorShots = <_EditorShot>[
  // 20b / 20i / 20j: unrecognized image model on auto — the unrecognized
  // sentence and the neutral parameter row.
  _EditorShot(
    'editorRelayAuto',
    '中转 · OpenAI 兼容',
    'Nano Banana Pro',
    sizes: <String>['desktop', 'mobile'],
    brightnesses: <Brightness>[Brightness.light, Brightness.dark],
  ),
  // 20c / 20i / 20j: pinned to the Images API — tinted field and row, the
  // ignored streaming toggle, 「改回自动」.
  _EditorShot(
    'editorRelayPinned',
    '中转 · OpenAI 兼容',
    'Img Fast',
    sizes: <String>['desktop', 'mobile'],
    brightnesses: <Brightness>[Brightness.light, Brightness.dark],
  ),
  // 20d: one route for an unrecognized video model — the read-only line.
  _EditorShot('editorRelayVideo', '中转 · OpenAI 兼容', 'My Sora'),
  // 20e: a video model on a channel with no video endpoint — the notice.
  _EditorShot('editorNoSurface', 'Claude 格式中转', 'My Video'),
];
