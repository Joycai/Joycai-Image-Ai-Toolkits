import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery/gallery_selection_bar.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:provider/provider.dart';

import '../../screenshots/harness/fixture_env.dart';

/// A selection bar's slide and fade leave on one clock (`plans/README.md`):
/// the slide ran the full M3 on the way out while the fade ran the shortened
/// exit.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  setUpAll(() => env = installFixtureEnv(binding));
  tearDownAll(() => env.dispose());

  testWidgets('the gallery bar slides and fades on the same duration, both ways', (tester) async {
    final appState = AppState();
    final gallery = appState.galleryState
      ..clearDroppedImages()
      ..setViewMode(GalleryViewMode.temp);
    final image = AppImage(path: '/nowhere/a.png', name: 'a.png');
    gallery.addDroppedFiles([image]);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<GalleryState>.value(value: gallery),
        ChangeNotifierProvider.value(value: appState.workbenchUIState),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: GallerySelectionBar())),
      ),
    ));

    (Duration, Duration) clocks() => (
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).duration,
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first).duration,
        );

    gallery.toggleImageSelection(image);
    await tester.pumpAndSettle();
    var (slide, fade) = clocks();
    expect(slide, AppMotion.panel);
    expect(fade, slide);

    gallery.toggleImageSelection(image);
    await tester.pump();
    (slide, fade) = clocks();
    expect(slide, Duration(milliseconds: (AppMotion.panel.inMilliseconds * AppMotion.exitFactor).round()));
    expect(fade, slide, reason: 'leaving together means leaving on one clock');
    await tester.pumpAndSettle();
    gallery.clearDroppedImages();
  });
}
