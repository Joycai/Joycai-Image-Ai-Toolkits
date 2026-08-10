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

  testWidgets('spans its column rather than hugging a short child', (tester) async {
    // Cards stacked in a panel are bands across it. Left to shrink-wrap, one
    // whose body is a short line came out a stub beside its neighbours — and
    // whether any given card looked right was an accident of whether
    // something inside it happened to be full-width already.
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: Column(
            children: const [
              AppCard(child: Text('short')),
              AppCard(child: SizedBox(width: 300, height: 20)),
            ],
          ),
        ),
      ),
    ));

    final cards = find.byType(AppCard);
    expect(tester.getSize(cards.at(0)).width, 400);
    expect(tester.getSize(cards.at(1)).width, 400,
        reason: 'A card sized itself from its content instead of its column');
  });

  testWidgets('a wide child still drives the height, not a fixed box', (tester) async {
    // Full width must not mean a fixed size: the card still grows to whatever
    // its body needs vertically.
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
      home: const Scaffold(
        body: SizedBox(
          width: 400,
          child: Column(children: [AppCard(child: SizedBox(height: 120))]),
        ),
      ),
    ));

    // 120 plus the card's default 12pt padding top and bottom.
    expect(tester.getSize(find.byType(AppCard)).height, 144);
  });
}
