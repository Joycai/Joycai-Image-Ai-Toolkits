import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/video/video_config_panel.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/fixture_seed.dart';
import '../../screenshots/harness/shoot.dart';

/// The video panel's desktop column pins its head above the prompt card only
/// while the head fits there. It used to pin it regardless: at 1440×900 with
/// the run console open the head got ~250px, and the reference card showed one
/// strip of thumbnails inside a scroller whose edge fade hid that it scrolled.
///
/// Pinned by the arrangement, not a pixel: whichever scroller holds the
/// reference card either has nothing to scroll, or also holds the prompt.
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

  for (final double height in <double>[700, 900, 1400]) {
    testWidgets('the head is never clipped at 1440×$height', (tester) async {
      await mountApp(
        tester,
        env: env,
        screen: AppScreen.workbench,
        size: Size(1440, height),
        label: 'video_head_$height',
        before: (_) async => AppState().setWorkbenchTab(5),
        after: (tester) async {
          seedVideoInputs(AppState());
          // Two frames: the measurement lands after the first.
          await tester.pump();
          await tester.pump();
        },
      );

      final Finder panel = find.byType(VideoConfigPanel);
      expect(panel, findsOneWidget);
      final Finder refs = find.descendant(of: panel, matching: find.text('参考图片'));
      expect(refs, findsOneWidget);

      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.ancestor(of: refs, matching: find.byType(Scrollable)).first,
      );
      final bool holdsPrompt = find
          .descendant(
            of: find.byWidget(scrollable.widget),
            matching: find.text('提示词'),
          )
          .evaluate()
          .isNotEmpty;
      expect(
        holdsPrompt || scrollable.position.maxScrollExtent == 0,
        isTrue,
        reason: 'the head is pinned but taller than its room — it is clipped '
            'inside its own scroller',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
