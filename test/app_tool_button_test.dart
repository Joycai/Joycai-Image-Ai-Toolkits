import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_tool_button.dart';

/// Covers [AppToolButton], the quiet toolbar action.
///
/// Its whole job is to be subordinate: the workbench top bar puts four of
/// these next to the segmented control that picks the workbench's mode, and
/// if they carry a fill of their own the row reads as six peers.
void main() {
  const seed = Colors.indigo;
  final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);

  Widget host(Widget child) => MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      );

  ButtonStyle styleOf(WidgetTester tester) =>
      tester.widget<TextButton>(find.byType(TextButton)).style!;

  testWidgets('at rest it has no fill and a neutral label', (tester) async {
    // Transparent, not merely "the theme default": a TextButton left alone
    // still tints its label with the accent, which is the signal `active`
    // needs to keep for itself.
    await tester.pumpWidget(host(AppToolButton(icon: Icons.crop, label: 'Crop', onPressed: () {})));

    final style = styleOf(tester);
    expect(style.backgroundColor?.resolve(const {}), Colors.transparent);
    expect(style.foregroundColor?.resolve(const {}), theme.colorScheme.onSurfaceVariant);
  });

  testWidgets('active takes the accent, in fill and label', (tester) async {
    await tester.pumpWidget(
      host(AppToolButton(icon: Icons.crop, label: 'Crop', active: true, onPressed: () {})),
    );

    final style = styleOf(tester);
    expect(style.foregroundColor?.resolve(const {}), theme.colorScheme.primary);
    expect(style.backgroundColor?.resolve(const {})?.a, greaterThan(0));
  });

  testWidgets('the hover overlay stays neutral', (tester) async {
    // An accented hover on each of four tools reads as four half-selected
    // buttons, which is exactly the ambiguity `active` exists to resolve.
    // Compared channel-wise, not by equality: styleFrom resolves the overlay
    // with the state's own alpha applied, so only the hue is ours to assert.
    await tester.pumpWidget(host(AppToolButton(icon: Icons.crop, label: 'Crop', onPressed: () {})));

    final hover = styleOf(tester).overlayColor!.resolve({WidgetState.hovered})!;
    final neutral = theme.colorScheme.onSurface;

    expect(hover.r, neutral.r);
    expect(hover.g, neutral.g);
    expect(hover.b, neutral.b);
    expect(hover.a, greaterThan(0), reason: 'Hover produces no visible fill at all');
    expect(hover.r, hover.b, reason: 'The neutral overlay picked up a hue');
  });

  testWidgets('icon-only mode keeps the label reachable as a tooltip', (tester) async {
    // The narrow-toolbar path. Dropping the label without the tooltip would
    // leave an unexplained glyph.
    await tester.pumpWidget(
      host(AppToolButton(icon: Icons.crop, label: 'Crop', showLabel: false, onPressed: () {})),
    );

    expect(find.text('Crop'), findsNothing);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Crop');
    expect(find.byIcon(Icons.crop), findsOneWidget);
  });

  testWidgets('tapping fires onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(AppToolButton(icon: Icons.crop, label: 'Crop', onPressed: () => taps++)),
    );

    await tester.tap(find.byType(AppToolButton));
    expect(taps, 1);
  });
}
