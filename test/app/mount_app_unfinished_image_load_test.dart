import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import '../screenshots/harness/fixture_env.dart';
import '../screenshots/harness/fixture_seed.dart';
import '../screenshots/harness/shoot.dart';

/// An image load one test leaves unfinished must not hang the next one.
///
/// The image cache is process-wide. A load started inside a `testWidgets` body
/// belongs to that test's fake-async zone; once the test ends nothing flushes
/// the zone again, so the load stays pending for good, and the next
/// `precacheImage` of the same path — `mountApp`'s warm-up does one per
/// fixture — is handed that completer and never returns. It took
/// `render_probe.dart` down from its second test on, and that file is outside
/// CI, so nothing noticed.
///
/// The tests run in pairs and the order is the point: the first of each pair
/// leaves the mess, the second has to survive it. A regression shows up as the
/// second one failing in the harness's warm-up, which bounds each decode and
/// names the path; the timeout on those tests is only the backstop for a hang
/// somewhere the warm-up does not cover. Each half of a pair means nothing run
/// on its own.
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

  const Timeout hangs = Timeout(Duration(seconds: 60));

  /// Starts a load in the calling test's zone and leaves it unfinished.
  ///
  /// [listened] stands in for whatever was showing the image: the cache only
  /// keeps a load in its live map while something listens to it.
  FileImage startLoad(String path, {bool listened = false}) {
    final FileImage image = FileImage(File(path));
    imageCache.evict(image);
    final ImageStream stream = image.resolve(ImageConfiguration.empty);
    if (listened) stream.addListener(ImageStreamListener((_, _) {}));
    expect(imageCache.statusForKey(image).pending, isTrue);
    return image;
  }

  Future<void> mount(WidgetTester tester) => mountApp(
        tester,
        env: env,
        screen: AppScreen.tasks,
        size: const Size(1440, 900),
        label: 'unfinished-load',
      );

  testWidgets('a test that never mounts leaves a load pending', (WidgetTester tester) async {
    startLoad(env.fixtureImagePaths.first);
  });

  testWidgets('…and the next mount drops it on the way in', timeout: hangs, (WidgetTester tester) async {
    await mount(tester);
  });

  // `ImageCache.clear()` empties the pending map but not the live one, and
  // `putIfAbsent` hands a completer back from either.
  testWidgets('a cleared cache still tracks the dead load as live', (WidgetTester tester) async {
    final FileImage image = startLoad(env.fixtureImagePaths.first, listened: true);
    imageCache.clear();
    expect(imageCache.pendingImageCount, 0);
    expect(imageCache.statusForKey(image).live, isTrue);
  });

  testWidgets('…and the next mount drops the live entry too', timeout: hangs, (WidgetTester tester) async {
    await mount(tester);
  });

  FileImage? left;

  testWidgets('a mounted test leaves a load pending', (WidgetTester tester) async {
    await mount(tester);
    left = startLoad(env.fixtureImagePaths.first);
  });

  // Without a mount of its own: what cleans up here is the first test's
  // teardown, which is all a test calling `precacheImage` itself can rely on.
  testWidgets('…and the next test inherits none of it', (WidgetTester tester) async {
    final FileImage? image = left;
    if (image == null) return markTestSkipped('needs the test before it to have run');
    expect(imageCache.statusForKey(image).untracked, isTrue);
  });
}
