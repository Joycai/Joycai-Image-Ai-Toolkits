import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_card.dart';

void main() {
  const seed = Colors.indigo;

  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders its child and takes surfaceContainerHigh, distinct from PanelCard\'s surface', (tester) async {
    await tester.pumpWidget(host(const AppCard(child: Text('Inside'))));

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final material = find.descendant(of: find.byType(AppCard), matching: find.byType(Material)).first;

    expect(find.text('Inside'), findsOneWidget);
    expect(tester.widget<Material>(material).color, theme.colorScheme.surfaceContainerHigh);
  });

  testWidgets('onTap fires through the InkWell', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(AppCard(onTap: () => tapped = true, child: const Text('Row'))));

    await tester.tap(find.text('Row'));
    expect(tapped, isTrue);
  });
}
