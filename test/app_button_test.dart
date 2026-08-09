import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_button.dart';

/// Covers [AppButton]'s four variants and its loading state.
void main() {
  const seed = Colors.indigo;

  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('primary takes the app-wide filled-button theme, not a style of its own', (tester) async {
    // No style is passed for primary — it must resolve through
    // FilledButtonThemeData (the vibrant fill), same as any other
    // FilledButton in the app.
    await tester.pumpWidget(host(AppButton(label: 'Go', onPressed: () {})));

    final filled = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(filled.style, isNull);
  });

  testWidgets('tapping calls onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(AppButton(label: 'Go', onPressed: () => tapped = true)));

    await tester.tap(find.byType(AppButton));
    expect(tapped, isTrue);
  });

  testWidgets('loading swaps the label for a spinner and disables the button', (tester) async {
    await tester.pumpWidget(host(AppButton(label: 'Go', onPressed: () {}, loading: true)));

    expect(find.text('Go'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('destructive fills from colorScheme.error, not the seed', (tester) async {
    await tester.pumpWidget(host(AppButton(label: 'Delete', onPressed: () {}, variant: AppButtonVariant.destructive)));

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;

    expect(style.backgroundColor?.resolve(const {}), theme.colorScheme.error);
  });

  testWidgets('secondary takes the tonal style, overriding the app-wide filled theme', (tester) async {
    // Without this override every FilledButton.tonal would inherit the
    // primary-filled background named in FilledButtonThemeData — the exact
    // trap tonalButtonStyle exists to route around.
    await tester.pumpWidget(host(AppButton(label: 'Maybe', onPressed: () {}, variant: AppButtonVariant.secondary)));

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;

    expect(style.backgroundColor?.resolve(const {}), theme.colorScheme.secondaryContainer);
  });

  testWidgets('text variant renders as a TextButton', (tester) async {
    await tester.pumpWidget(host(AppButton(label: 'Cancel', onPressed: () {}, variant: AppButtonVariant.text)));

    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('an icon switches to the .icon constructor without dropping the label', (tester) async {
    await tester.pumpWidget(host(AppButton(label: 'Save', icon: Icons.save, onPressed: () {})));

    expect(find.text('Save'), findsOneWidget);
    expect(find.byIcon(Icons.save), findsOneWidget);
  });
}
