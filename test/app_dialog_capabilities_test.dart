import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_dialog.dart';

/// Covers the capabilities [AppDialog] grew so the app's ~50 hand-rolled
/// dialogs could move onto it.
///
/// Each one here unblocked a specific group of call sites; the comments name
/// the failure the capability exists to prevent, because "it renders" is not
/// what these are checking.
/// Identifies the test's own body widget. Dialog's internals paint boxes of
/// their own, so finding by type picks up more than the content.
const bodyKey = ValueKey('dialog-body');

void main() {
  const seed = Colors.indigo;
  final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);

  Widget host(Widget dialog) => MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: dialog)),
      );

  /// The painted card, not the [Dialog] widget.
  ///
  /// `Dialog` expands to the whole route and holds its inset padding, so its
  /// own rect is the screen — measuring it would make every size assertion
  /// here pass for the wrong reason. The `Material` it wraps its child in is
  /// the surface the user actually sees.
  Finder surface() =>
      find.descendant(of: find.byType(AppDialog), matching: find.byType(Material)).first;

  Size dialogSize(WidgetTester tester) => tester.getSize(surface());

  group('maxHeight', () {
    testWidgets('bounds a body that would otherwise grow past the screen', (tester) async {
      // The blocker for every list dialog. A dialog shrink-wraps, so without
      // a ceiling a long list just keeps growing.
      await tester.pumpWidget(host(AppDialog(
        title: 'Pick one',
        maxHeight: 300,
        content: ListView(
          shrinkWrap: true,
          children: [for (var i = 0; i < 200; i++) ListTile(title: Text('Row $i'))],
        ),
      )));

      expect(dialogSize(tester).height, lessThanOrEqualTo(300));
    });

    testWidgets('lets an Expanded child inside the body lay out', (tester) async {
      // An Expanded under an unbounded height throws outright. Several
      // pickers put a list in one, so this has to hold rather than merely
      // clip.
      await tester.pumpWidget(host(AppDialog(
        title: 'Discovered',
        maxHeight: 320,
        content: Column(
          children: [
            const Text('Header'),
            Expanded(
              child: ListView(children: const [Text('a'), Text('b')]),
            ),
          ],
        ),
      )));

      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the action row on screen instead of clipping it off', (tester) async {
      // The subtle half of the bug: bound the whole column instead of just
      // the body and the buttons are the part that falls off the bottom.
      await tester.pumpWidget(host(AppDialog(
        title: 'Pick one',
        maxHeight: 300,
        content: ListView(
          shrinkWrap: true,
          children: [for (var i = 0; i < 200; i++) ListTile(title: Text('Row $i'))],
        ),
        actions: [TextButton(onPressed: () {}, child: const Text('Close'))],
      )));

      final card = tester.getRect(surface());
      final button = tester.getRect(find.text('Close'));

      expect(button.bottom, lessThanOrEqualTo(card.bottom));
      expect(card.height, lessThanOrEqualTo(300));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('scrollable wraps the body so a bounded dialog can scroll', (tester) async {
    await tester.pumpWidget(host(AppDialog(
      title: 'Long',
      maxHeight: 240,
      scrollable: true,
      content: Column(
        children: [for (var i = 0; i < 60; i++) Text('Line $i')],
      ),
    )));

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('contentPadding', () {
    testWidgets('zero bleeds the body to the edges but not the title', (tester) async {
      // Full-bleed lists need the body at the edge; the heading must stay
      // inset or the dialog looks broken rather than deliberate.
      await tester.pumpWidget(host(const AppDialog(
        title: 'Channels',
        maxWidth: 400,
        contentPadding: EdgeInsets.zero,
        content: SizedBox(key: bodyKey, height: 40, width: double.infinity),
      )));

      final card = tester.getRect(surface());
      final body = tester.getRect(find.byKey(bodyKey));
      final title = tester.getRect(find.text('Channels'));

      expect(body.left, card.left);
      expect(body.right, card.right);
      expect(title.left, greaterThan(card.left));
    });

    testWidgets('the default insets the body on every free side', (tester) async {
      await tester.pumpWidget(host(const AppDialog(
        maxWidth: 400,
        content: SizedBox(key: bodyKey, height: 40, width: double.infinity),
      )));

      final card = tester.getRect(surface());
      final body = tester.getRect(find.byKey(bodyKey));

      // No title and no actions, so the body owns all four insets.
      expect(body.left, greaterThan(card.left));
      expect(body.top, greaterThan(card.top));
      expect(body.bottom, lessThan(card.bottom));
    });
  });

  group('heading', () {
    testWidgets('subtitle renders under the title, quieter', (tester) async {
      await tester.pumpWidget(host(const AppDialog(
        title: 'Rename files',
        subtitle: '12 images selected',
        content: SizedBox.shrink(),
      )));

      final title = tester.widget<Text>(find.text('Rename files'));
      final subtitle = tester.widget<Text>(find.text('12 images selected'));

      expect(subtitle.style!.fontSize, lessThan(title.style!.fontSize!));
      expect(subtitle.style!.color, theme.colorScheme.onSurfaceVariant);
    });

    testWidgets('icon takes the accent unless told otherwise', (tester) async {
      await tester.pumpWidget(host(const AppDialog(
        title: 'Delete',
        icon: Icons.warning_amber,
        content: SizedBox.shrink(),
      )));

      expect(tester.widget<Icon>(find.byIcon(Icons.warning_amber)).color, theme.colorScheme.primary);
    });

    testWidgets('iconColor overrides it, for destructive headings', (tester) async {
      await tester.pumpWidget(host(AppDialog(
        title: 'Delete',
        icon: Icons.warning_amber,
        iconColor: theme.colorScheme.error,
        content: const SizedBox.shrink(),
      )));

      expect(tester.widget<Icon>(find.byIcon(Icons.warning_amber)).color, theme.colorScheme.error);
    });

    testWidgets('a title and a titleWidget together is a mistake, not a silent win', (tester) async {
      expect(
        () => AppDialog(
          title: 'A',
          titleWidget: const Text('B'),
          content: const SizedBox.shrink(),
        ),
        throwsAssertionError,
      );
    });
  });

  testWidgets('actionsOverride replaces the right-aligned row wholesale', (tester) async {
    // The wizard footer: step dots pinned left, buttons right. Feeding that
    // through `actions` would wrap a full-width Row inside a
    // MainAxisAlignment.end Row and shove it off to one side.
    await tester.pumpWidget(host(AppDialog(
      title: 'Step 2',
      maxWidth: 400,
      content: const SizedBox(height: 40),
      actions: [TextButton(onPressed: () {}, child: const Text('Ignored'))],
      actionsOverride: Row(
        children: [
          const Text('dots'),
          const Spacer(),
          TextButton(onPressed: () {}, child: const Text('Next')),
        ],
      ),
    )));

    expect(find.text('Ignored'), findsNothing);

    final dots = tester.getRect(find.text('dots'));
    final next = tester.getRect(find.text('Next'));
    expect(dots.left, lessThan(next.left), reason: 'The override lost its own alignment');
  });

  testWidgets('the radius matches the panels, not Material stock', (tester) async {
    // Settled deliberately: one radius across the app, so a dialog reads as
    // another surface in the same system.
    await tester.pumpWidget(host(const AppDialog(content: SizedBox.shrink())));

    final dialog = tester.widget<Dialog>(
        find.descendant(of: find.byType(AppDialog), matching: find.byType(Dialog)));
    final shape = dialog.shape! as RoundedRectangleBorder;

    expect(shape.borderRadius, BorderRadius.circular(appDialogRadius));
    expect(appDialogRadius, 12);
  });
}
