import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/bench/design_catalog.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dialog.dart';
import 'package:material_ui/material_ui.dart';

import '../support/real_fonts.dart';

void main() {
  setUpAll(() async {
    await ensureRealTestFontsLoaded();
  });

  testWidgets('Design Catalog switches themes, reduced effects, widths, and opens overlays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildDesignCatalogApp());
    await tester.pumpAndSettle();

    expect(find.text('Primary CTA'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);

    // Toggle dark brightness.
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // Toggle viewport width constraint.
    await tester.tap(find.text('390'));
    await tester.pumpAndSettle();

    // Toggle reduce visual effects -> BackdropFilters disappear.
    await tester.tap(find.byKey(const ValueKey('catalog-reduce-effects')));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);

    // Trigger live SnackBar.
    await tester.ensureVisible(find.text('Show Toast'));
    await tester.tap(find.text('Show Toast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Catalog toast triggered'), findsOneWidget);

    // Open and close live AppDialog.
    await tester.ensureVisible(find.text('Open Dialog'));
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
