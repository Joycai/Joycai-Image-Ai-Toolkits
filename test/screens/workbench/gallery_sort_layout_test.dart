import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/gallery.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery/image_card.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/files/folder_group_header.dart';
import 'package:joycai_image_ai_toolkits/widgets/files/folder_outline_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../support/real_async.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  late Directory root;
  late Directory alpha;
  late Directory beta;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    root = await Directory.systemTemp.createTemp('joycai_gallery_sort_layout');
    alpha = await Directory(p.join(root.path, 'Alpha')).create();
    beta = await Directory(p.join(root.path, 'beta')).create();
    final png = img.encodePng(img.Image(width: 4, height: 4));
    final t0 = DateTime(2026, 6, 1, 12, 0);
    for (final (dir, name, minutes) in [
      (beta, 'b_old.png', 0),
      (alpha, 'a_mid.png', 1),
      (beta, 'b_new.png', 2),
    ]) {
      final file = File(p.join(dir.path, name))..writeAsBytesSync(png);
      file.setLastModifiedSync(t0.add(Duration(minutes: minutes)));
    }
  });
  useRealAsyncAppState();
  tearDownAll(() async {
    env.dispose();
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Best-effort temp cleanup on Windows.
    }
  });

  Future<GalleryState> mountGallery(WidgetTester tester, List<String> dirs) async {
    final app = AppState();
    final state = app.galleryState;
    await inRealAsync(tester, () async {
      await state.setSortField(GallerySortField.date);
      await state.setSortAscending(false);
      await state.setGroupByFolder(true);
      state.sourceDirectories = List<String>.of(dirs);
      state.activeSourceDirectories = List<String>.of(dirs);
      state.setViewMode(GalleryViewMode.all);
      await state.refreshImages();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: app.workbenchUIState),
        ],
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Gallery()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  List<String> renderedOrder(WidgetTester tester) {
    final cards = tester.widgetList<ImageCard>(find.byType(ImageCard)).toList();
    return [for (final card in cards) card.imageFile.name];
  }

  testWidgets('toggling groupByFolder with two folders toggles headers, outline, and order', (
    tester,
  ) async {
    final state = await mountGallery(tester, [beta.path, alpha.path]);

    expect(find.byType(FolderGroupHeader), findsNWidgets(2));
    expect(find.byType(FolderOutlineBar), findsOneWidget);
    expect(renderedOrder(tester), ['a_mid.png', 'b_new.png', 'b_old.png']);

    await inRealAsync(tester, () => state.setGroupByFolder(false));
    await tester.pumpAndSettle();

    expect(find.byType(FolderGroupHeader), findsNothing);
    expect(find.byType(FolderOutlineBar), findsNothing);
    expect(renderedOrder(tester), ['b_new.png', 'a_mid.png', 'b_old.png']);

    await inRealAsync(tester, () => state.setSortAscending(true));
    await tester.pumpAndSettle();
    expect(renderedOrder(tester), ['b_old.png', 'a_mid.png', 'b_new.png']);

    await inRealAsync(tester, () => state.setGroupByFolder(true));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('toggling groupByFolder with one folder keeps its path header', (tester) async {
    final state = await mountGallery(tester, [alpha.path]);

    expect(find.byType(FolderGroupHeader), findsOneWidget);
    expect(find.byType(FolderOutlineBar), findsNothing);

    await inRealAsync(tester, () => state.setGroupByFolder(false));
    await tester.pumpAndSettle();
    expect(find.byType(FolderGroupHeader), findsOneWidget);

    await inRealAsync(tester, () => state.setGroupByFolder(true));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
