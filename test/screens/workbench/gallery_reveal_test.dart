import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/gallery.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:provider/provider.dart';

import '../../screenshots/harness/fixture_env.dart';

/// `plans/README.md`'s oldest open line: a scan swapped its placeholder for a
/// screenful of tiles in one frame. The grid now fades in when it replaces a
/// placeholder — and only then, so a grid that stays up is never re-faded.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  setUpAll(() => env = installFixtureEnv(binding));
  tearDownAll(() => env.dispose());

  Future<GalleryState> pump(WidgetTester tester) async {
    final appState = AppState();
    final gallery = appState.galleryState
      ..clearDroppedImages()
      ..setViewMode(GalleryViewMode.temp);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<GalleryState>.value(value: gallery),
        ChangeNotifierProvider.value(value: appState.workbenchUIState),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Gallery()),
      ),
    ));
    await tester.pump();
    return gallery;
  }

  double gridOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find.ancestor(
        of: find.byType(CustomScrollView),
        matching: find.byType(Opacity),
      ).first)
      .opacity;

  testWidgets('the grid fades in over a placeholder, and does not fade again', (tester) async {
    final gallery = await pump(tester);
    expect(find.byType(CustomScrollView), findsNothing, reason: 'the empty workspace shows');

    gallery.addDroppedFiles([AppImage(path: '/nowhere/a.png', name: 'a.png')]);
    await tester.pump();
    expect(gridOpacity(tester), lessThan(0.2), reason: 'the first frame of the grid is still faint');
    await tester.pump(const Duration(milliseconds: 90));
    final mid = gridOpacity(tester);
    expect(mid, inExclusiveRange(0.2, 1.0));
    await tester.pumpAndSettle();
    expect(gridOpacity(tester), 1.0);

    final scroller = tester.element(find.byType(CustomScrollView));
    gallery.addDroppedFiles([AppImage(path: '/nowhere/b.png', name: 'b.png')]);
    await tester.pump();
    expect(gridOpacity(tester), 1.0, reason: 'more images in a grid already up is not a reveal');
    expect(tester.element(find.byType(CustomScrollView)), same(scroller),
        reason: 'and the grid is not remounted');

    // Thumbnail loads leave timers behind; let them run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('under reduce-motion the grid appears at once', (tester) async {
    final gallery = await pump(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    gallery.addDroppedFiles([AppImage(path: '/nowhere/a.png', name: 'a.png')]);
    await tester.pump();
    await tester.pump();
    expect(gridOpacity(tester), 1.0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
