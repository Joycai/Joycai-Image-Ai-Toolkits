import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('secondary is an outline, spending no accent on itself', (tester) async {
    // This was a tonal FilledButton — a secondaryContainer slab — until the
    // design spec landed. The seed's colour belongs on the action the user is
    // meant to take; a filled secondary spent it on the one beside it. The
    // separation from `primary` is now weight, not hue.
    await tester.pumpWidget(host(AppButton(label: 'Maybe', onPressed: () {}, variant: AppButtonVariant.secondary)));

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);

    final style = tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style!;
    expect(style.backgroundColor?.resolve(const {}), theme.colorScheme.surface);
    expect(style.foregroundColor?.resolve(const {}), theme.colorScheme.onSurface);
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

  /// The painted surface, not the button: a button pads itself out to a 48px
  /// tap target that is never drawn, so its own size says nothing about what
  /// the user sees.
  Size paintedSize(WidgetTester tester) => tester.getSize(
        find.descendant(of: find.byType(AppButton), matching: find.byType(Material)).first,
      );

  group('sizes', () {
    // Every one of these existed as a hand-rolled `minimumSize` or
    // `visualDensity` at some call site the migration could not bring across.
    // The component owning them is the point.

    testWidgets('compact is shorter than normal, large is taller', (tester) async {
      await tester.pumpWidget(host(AppButton(label: 'X', onPressed: () {}, size: AppButtonSize.compact)));
      final compact = paintedSize(tester).height;

      await tester.pumpWidget(host(AppButton(label: 'X', onPressed: () {})));
      final normal = paintedSize(tester).height;

      await tester.pumpWidget(host(AppButton(label: 'X', onPressed: () {}, size: AppButtonSize.large)));
      final large = paintedSize(tester).height;

      expect(compact, lessThan(normal));
      expect(normal, lessThan(large));
      expect(normal, appButtonMinHeight, reason: 'the default drifted away from the shared floor');
    });

    testWidgets('a compact button carries a smaller icon', (tester) async {
      // 18px inside a 30px button is most of its height.
      await tester.pumpWidget(host(
        AppButton(label: 'X', icon: Icons.close, onPressed: () {}, size: AppButtonSize.compact),
      ));
      final compact = tester.widget<Icon>(find.byIcon(Icons.close)).size;

      await tester.pumpWidget(host(AppButton(label: 'X', icon: Icons.close, onPressed: () {})));
      final normal = tester.widget<Icon>(find.byIcon(Icons.close)).size;

      expect(compact, lessThan(normal!));
    });

    testWidgets('fullWidth spans what it is offered', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: AppButton(label: 'Import now', onPressed: () {}, fullWidth: true),
          ),
        ),
      ));

      expect(paintedSize(tester).width, 400);
    });

    testWidgets('the label scales with the box', (tester) async {
      // A compact button holding a full-size label is not compact. It was
      // still overflowing the card it had been shrunk to fit, and every call
      // site that predates this had hand-set a `fontSize: 12` beside its
      // `visualDensity` — the pairing this encodes once.
      // The rendered paragraph, not the Text widget or the DefaultTextStyle
      // above it: the button resolves its own text style onto the label, and
      // only what was actually laid out settles whether it shrank.
      //
      // Each read needs pumpAndSettle first. A button animates its label
      // style, so reading straight after pumpWidget returns the *previous*
      // button's size -- which made all three look identical and sent me
      // hunting a bug in the widget that was not there.
      double labelSize(WidgetTester tester) => tester
          .renderObject<RenderParagraph>(
            find.descendant(of: find.text('X'), matching: find.byType(RichText)),
          )
          .text
          .style!
          .fontSize!;

      await tester.pumpWidget(host(AppButton(label: 'X', onPressed: () {}, size: AppButtonSize.compact)));
      await tester.pumpAndSettle();
      final compact = labelSize(tester);

      await tester.pumpWidget(host(AppButton(label: 'X', onPressed: () {})));
      await tester.pumpAndSettle();
      final normal = labelSize(tester);

      await tester.pumpWidget(host(AppButton(label: 'X', onPressed: () {}, size: AppButtonSize.large)));
      await tester.pumpAndSettle();
      final large = labelSize(tester);

      expect(compact, lessThan(normal));
      expect(normal, lessThan(large));
    });

    testWidgets('the label comes from the type scale, not a literal', (tester) async {
      // So that a change to the scale still reaches buttons — the whole
      // reason the scale exists.
      final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);

      await tester.pumpWidget(host(AppButton(label: 'X', onPressed: () {}, size: AppButtonSize.compact)));
      final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;

      expect(style.textStyle?.resolve(const {})?.fontSize, theme.textTheme.labelMedium?.fontSize);
    });

    testWidgets('the default size leaves the theme alone', (tester) async {
      // Restating the theme's own numbers over it is the drift this replaced;
      // a plain button must still resolve straight through the theme.
      await tester.pumpWidget(host(AppButton(label: 'Go', onPressed: () {})));

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).style, isNull);
    });

    testWidgets('sizing never repaints the variant', (tester) async {
      // Size and colour are merged from two styles; if the geometry were
      // merged over the variant instead of under it, a large destructive
      // button would come out the default fill.
      await tester.pumpWidget(host(AppButton(
        label: 'Delete',
        onPressed: () {},
        variant: AppButtonVariant.destructive,
        size: AppButtonSize.large,
      )));

      final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
      final style = tester.widget<FilledButton>(find.byType(FilledButton)).style!;

      expect(style.backgroundColor?.resolve(const {}), theme.colorScheme.error);
      expect(paintedSize(tester).height, 48);
    });
  });

  testWidgets('destructiveText is the error colour with no border', (tester) async {
    // For a toolbar of borderless controls, where destructiveOutline's edge
    // would be the only one in the row and destructive's fill would shout.
    await tester.pumpWidget(host(AppButton(
      label: 'Clear',
      onPressed: () {},
      variant: AppButtonVariant.destructiveText,
    )));

    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final style = tester.widget<TextButton>(find.byType(TextButton)).style!;

    expect(style.foregroundColor?.resolve(const {}), theme.colorScheme.error);
    expect(style.side?.resolve(const {}), isNull);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
