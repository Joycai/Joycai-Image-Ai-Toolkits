import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/image_layer.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/layers/layer_canvas_page.dart';
import 'package:joycai_image_ai_toolkits/services/media/layer_composite_service.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// The layer canvas (`A7`) puts every layer back in its box on the base —
/// the one thing it exists for — and exports exactly what is visible.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = usePrivateDataDir('joycai_layer_canvas_test');

  /// A solid [w]×[h] PNG of [color] (RGBA) at [name].
  String png(String name, int w, int h, img.Color color) {
    final image = img.Image(width: w, height: h, numChannels: 4)..clear(color);
    final path = p.join(dir.path, name);
    File(path).writeAsBytesSync(img.encodePng(image));
    return path;
  }

  late ImageLayerSet set;

  setUpAll(() {
    final base = png('base.png', 100, 200, img.ColorRgba8(255, 0, 0, 255));
    final figure = png('figure.png', 40, 100, img.ColorRgba8(0, 0, 255, 255));
    final title = png('title.png', 20, 10, img.ColorRgba8(0, 255, 0, 255));
    set = ImageLayerSet('s', [
      ImageLayer(
        path: title,
        setId: 's',
        zIndex: 2,
        name: 'title',
        box: const LayerBox(70, 180, 90, 190),
      ),
      ImageLayer(path: base, setId: 's', zIndex: 0),
      ImageLayer(
        path: figure,
        setId: 's',
        zIndex: 1,
        name: 'figure',
        description: 'the character',
        box: const LayerBox(10, 20, 50, 120),
      ),
    ]);
  });

  Future<void> pumpCanvas(WidgetTester tester, Size window) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => WorkbenchUIState(),
        child: MaterialApp(
          theme: buildAppTheme(
            accent: ThemeAccent.fromSeed(Colors.blue),
            brightness: Brightness.light,
          ),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LayerCanvasPage(set: set),
        ),
      ),
    );
    // The base's size is read from the file, off the fake clock.
    final canvas = find.byWidgetPredicate((w) => w is Image && w.key == ValueKey(set.base!.path));
    for (var i = 0; i < 50 && canvas.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Rect rectOfImage(WidgetTester tester, String path) =>
      tester.getRect(find.byWidgetPredicate((w) => w is Image && w.key == ValueKey(path)));

  testWidgets('each layer sits in its box, in the base\'s pixels', (tester) async {
    await pumpCanvas(tester, const Size(1440, 900));
    final base = rectOfImage(tester, set.base!.path);
    final scale = base.width / 100;
    expect(base.height / scale, closeTo(200, 0.01), reason: 'the base keeps its own aspect');

    final figure = rectOfImage(tester, set.overlays.first.path);
    expect((figure.left - base.left) / scale, closeTo(10, 0.01));
    expect((figure.top - base.top) / scale, closeTo(20, 0.01));
    expect(figure.width / scale, closeTo(40, 0.01));
    expect(figure.height / scale, closeTo(100, 0.01));

    final title = rectOfImage(tester, set.overlays.last.path);
    expect((title.left - base.left) / scale, closeTo(70, 0.01));
    expect((title.bottom - base.top) / scale, closeTo(190, 0.01));
  });

  testWidgets('the list runs top of the stack first; the eye hides a layer', (tester) async {
    await pumpCanvas(tester, const Size(1440, 900));
    final titleY = tester.getTopLeft(find.text('title')).dy;
    final figureY = tester.getTopLeft(find.text('figure')).dy;
    final baseY = tester.getTopLeft(find.text('Base')).dy;
    expect(titleY, lessThan(figureY));
    expect(figureY, lessThan(baseY));

    await tester.tap(find.byTooltip('Hide layer').at(1)); // figure's row
    await tester.pump();
    expect(
      find.byWidgetPredicate((w) => w is Image && w.key == ValueKey(set.overlays.first.path)),
      findsNothing,
    );
    expect(find.byTooltip('Show layer'), findsOneWidget);
  });

  testWidgets('a tap on the canvas picks the topmost box under it', (tester) async {
    await pumpCanvas(tester, const Size(1440, 900));
    final base = rectOfImage(tester, set.base!.path);
    final scale = base.width / 100;
    await tester.tapAt(base.topLeft + const Offset(30, 70) * scale);
    await tester.pump();
    // The details block names the picked layer and gives its box.
    expect(find.text('Position 10, 20'), findsOneWidget);
    expect(find.text('Size 40×100'), findsOneWidget);

    // Empty ground clears it — inside the picture and round it.
    await tester.tapAt(base.topLeft + const Offset(95, 5) * scale);
    await tester.pump();
    expect(find.text('Position 10, 20'), findsNothing);
    await tester.tapAt(base.topLeft + const Offset(30, 70) * scale);
    await tester.pump();
    expect(find.text('Position 10, 20'), findsOneWidget);
    await tester.tapAt(base.topLeft - const Offset(20, 0));
    await tester.pump();
    expect(find.text('Position 10, 20'), findsNothing);
  });

  testWidgets('a single layer is counted in the singular', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(l10n.layerCanvasSubtitle(912, 1168, 1), 'Base 912×1168 · 1 layer');
    expect(l10n.menuLayerCount(3), '3 layers');
  });

  testWidgets('narrow widths keep every row and the export', (tester) async {
    for (final size in const [Size(390, 844), Size(834, 1112)]) {
      await pumpCanvas(tester, size);
      expect(find.text('title'), findsOneWidget, reason: '$size');
      expect(find.text('Base'), findsOneWidget, reason: '$size');
      expect(
        find.byTooltip('Export composite').evaluate().isNotEmpty ||
            find.text('Export composite').evaluate().isNotEmpty,
        isTrue,
        reason: '$size',
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  test('the composite is the visible stack at the base\'s size', () async {
    final bytes = await LayerCompositeService.composite(set.layers, 100, 200);
    final out = img.decodePng(bytes)!;
    expect([out.width, out.height], [100, 200]);
    int rgb(int x, int y) {
      final px = out.getPixel(x, y);
      return (px.r.toInt() << 16) | (px.g.toInt() << 8) | px.b.toInt();
    }

    expect(rgb(5, 5), 0xFF0000, reason: 'base');
    expect(rgb(30, 70), 0x0000FF, reason: 'figure in its box');
    expect(rgb(80, 185), 0x00FF00, reason: 'title in its box');
    expect(rgb(60, 70), 0xFF0000, reason: 'outside every box');

    // Base hidden: the ground is transparent and the layers stay put.
    final noBase = img.decodePng(await LayerCompositeService.composite(set.overlays, 100, 200))!;
    expect(noBase.getPixel(5, 5).a, 0);
    expect(noBase.getPixel(30, 70).b, 255);
  });

  test('the export lands beside the base and never overwrites', () async {
    final base = set.base!.path;
    final first = await LayerCompositeService.save(
      base,
      img.encodePng(img.Image(width: 1, height: 1)),
    );
    final second = await LayerCompositeService.save(
      base,
      img.encodePng(img.Image(width: 1, height: 1)),
    );
    expect(p.basename(first), 'base_composite.png');
    expect(p.basename(second), 'base_composite (2).png');
    expect(p.dirname(first), p.dirname(base));
  });
}
