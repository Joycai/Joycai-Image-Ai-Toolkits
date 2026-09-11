import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

/// Every input and select box draws its outline at the height of the box it
/// is given, and at the same height on the desktop as in this harness.
///
/// Both failed silently, and only one of them could ever show in a screenshot:
///
/// * An [InputDecorator] draws its outline around its *content*, not around
///   its box. A field pinned to 32 with no vertical inset drew a 19px outline
///   in the middle of a 32px slot — the model editor's ID and name fields, the
///   prompt dialog's title.
/// * Flutter's default density is compact on Windows, macOS and Linux and
///   standard on Android, which this harness runs as. Compact takes 8px off a
///   field's content, so a dropdown that measured 32 here drew 24 on the
///   desktop.
///
/// So each surface is mounted twice, once as each platform. Every bordered
/// field's outline must fill its box, and every single-line field must come
/// out the same height both times. Multi-line editors are left out of the
/// second check: they fill whatever the column has left, which the density of
/// the buttons around them changes.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    final AppState appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() => env.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> Function(WidgetTester) tapTexts(List<String> labels) => (WidgetTester tester) async {
        for (final label in labels) {
          final f = find.text(label);
          if (f.evaluate().isEmpty) continue;
          await tester.tap(f.first, warnIfMissed: false);
          await settle(tester);
        }
      };

  const desktop = Size(1440, 900);
  const phone = Size(390, 844);

  final surfaces = <(String, AppScreen, Size, Future<void> Function(WidgetTester)?)>[
    ('workbench desktop', AppScreen.workbench, desktop, null),
    ('model editor desktop', AppScreen.models, desktop, tapTexts(['中转 · OpenAI 兼容', 'GPT-5 Chat'])),
    ('add model desktop', AppScreen.models, desktop, tapTexts(['中转 · OpenAI 兼容', '添加模型'])),
    ('model editor phone', AppScreen.models, phone, tapTexts(['中转 · OpenAI 兼容', 'GPT-5 Chat'])),
    (
      'channel editor desktop',
      AppScreen.models,
      desktop,
      (WidgetTester tester) async {
        final edit = find.byTooltip('编辑');
        if (edit.evaluate().isEmpty) return;
        await tester.tap(edit.first, warnIfMissed: false);
        await settle(tester);
      }
    ),
    ('new prompt desktop', AppScreen.prompts, desktop, tapTexts(['新建提示词'])),
    ('settings desktop', AppScreen.settings, desktop, null),
    ('downloader desktop', AppScreen.downloader, desktop, null),
    ('file browser desktop', AppScreen.fileBrowser, desktop, null),
  ];

  /// Single-line field heights by platform, keyed by surface, order and text.
  final heights = <String, Map<String, double>>{'android': {}, 'windows': {}};

  InputDecorator? decoratorOf(Element border, void Function(Element) found) {
    InputDecorator? decorator;
    border.visitAncestorElements((a) {
      if (a.widget is InputDecorator) {
        decorator = a.widget as InputDecorator;
        found(a);
        return false;
      }
      return true;
    });
    return decorator;
  }

  void measure(WidgetTester tester, String surface, String platform) {
    final borders = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_BorderContainer');
    var singleLine = 0;
    for (final border in borders.evaluate()) {
      final box = border.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;

      late Element decoratorElement;
      final decorator = decoratorOf(border, (e) => decoratorElement = e);
      if (decorator == null) continue;
      // A borderless input inside a box drawn by its parent (the file
      // browser's search) has no outline to measure.
      if (decorator.decoration.isCollapsed ?? false) continue;

      final outer = (decoratorElement.renderObject! as RenderBox).size.height;
      var text = '';
      var multiLine = false;
      void walk(Element e) {
        final w = e.widget;
        if (w is EditableText) {
          multiLine = multiLine || w.maxLines != 1;
          if (text.isEmpty) text = w.controller.text;
        } else if (w is Text && text.isEmpty) {
          text = w.data ?? '';
        }
        e.visitChildren(walk);
      }

      walk(decoratorElement);
      final label = '$surface · "${text.length > 24 ? text.substring(0, 24) : text}"';

      expect(box.size.height, closeTo(outer, 0.5),
          reason: '$label on $platform: a ${box.size.height} outline in a $outer box');

      if (!multiLine) {
        heights[platform]!['$surface #${singleLine++} $text'] = box.size.height;
      }
    }
  }

  for (final platform in ['android', 'windows']) {
    for (final (name, screen, size, after) in surfaces) {
      testWidgets('$name fills its fields on $platform', (WidgetTester tester) async {
        if (platform == 'windows') debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await mountApp(tester, env: env, screen: screen, size: size, label: '$name $platform', after: after);
          measure(tester, name, platform);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('the video panel fills its fields on $platform', (WidgetTester tester) async {
      if (platform == 'windows') debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await mountApp(
          tester,
          env: env,
          screen: AppScreen.workbench,
          size: desktop,
          label: 'video $platform',
          before: (WidgetTester tester) async => AppState().setWorkbenchTab(5),
        );
        measure(tester, 'video desktop', platform);
      } finally {
        AppState().setWorkbenchTab(0);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('every single-line field is as tall on the desktop as in the harness', () {
    expect(heights['android'], isNotEmpty);
    expect(heights['windows'], heights['android']);
  });
}
