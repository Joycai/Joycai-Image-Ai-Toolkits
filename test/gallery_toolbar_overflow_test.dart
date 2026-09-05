import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/gallery_toolbar.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_dialog.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the gallery toolbar's behaviour as its own width shrinks.
///
/// The bug this pins: the bar used to decide its layout from the *screen*
/// breakpoint, but what actually squeezes it is the centre panel. Open both
/// side panels on a wide monitor and the screen is still "desktop" while this
/// bar has a few hundred pixels, so it laid out the full set of controls and
/// clipped the view toggle mid-word.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => Directory.systemTemp.path,
  );

  /// Renders the toolbar at [barWidth] while the *window* stays desktop-sized,
  /// which is exactly the situation that broke.
  ///
  /// [workspaceCount] seeds the temporary workspace and switches the gallery
  /// to it, which is the state the clear-workspace action keys off.
  Future<AppState> pumpAtWidth(
    WidgetTester tester,
    double barWidth, {
    int workspaceCount = 0,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Deliberately not disposed: the widget tree outlives the pump, and a
    // disposed GalleryState throws the moment the toolbar rebuilds. The other
    // widget tests in this repo leave it to the test runner for the same
    // reason.
    final appState = AppState();

    if (workspaceCount > 0) {
      appState.galleryState.addDroppedFiles([
        for (var i = 0; i < workspaceCount; i++)
          AppImage(path: '/tmp/workspace_$i.png', name: 'workspace_$i.png'),
      ]);
      appState.galleryState.setViewMode(GalleryViewMode.temp);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: appState.galleryState),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: barWidth, child: const GalleryToolbar()),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return appState;
  }

  testWidgets('a squeezed bar still renders without overflowing', (tester) async {
    // The reported symptom was a clipped toggle; the underlying failure is a
    // RenderFlex that does not fit. Any overflow here is the bug returning.
    await pumpAtWidth(tester, 420);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the squeezed bar never pushes the view toggle outside itself', (tester) async {
    // The reported symptom, stated directly: "全部来源" rendered as "全部来".
    // Both labels have to sit inside the bar's own bounds, because the
    // trailing controls collapsed instead of taking the space. Asserting the
    // toggle's *size* would not catch this -- it used to live in a horizontal
    // scroll view, which reports a full natural width while painting a
    // fraction of it.
    await pumpAtWidth(tester, 420);

    final bar = tester.getRect(find.byType(GalleryToolbar));

    for (final label in ['All Sources', 'All Results']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(bar.left),
          reason: '"$label" starts before the bar does');
      expect(rect.right, lessThanOrEqualTo(bar.right),
          reason: '"$label" is clipped off the right edge of the bar');
    }
  });

  testWidgets('the other controls collapse into one menu when the bar is squeezed', (tester) async {
    await pumpAtWidth(tester, 420);

    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    // The wide-layout controls are gone from the bar itself, not merely
    // scrolled out of sight where they cannot be reached.
    expect(find.byType(Slider), findsNothing);
    expect(find.byIcon(Icons.select_all), findsNothing);
  });

  testWidgets('a roomy bar lays the controls out inline, with no menu', (tester) async {
    await pumpAtWidth(tester, 1200);

    expect(find.byType(Slider), findsOneWidget);
    expect(find.byIcon(Icons.select_all), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('no width between collapsed and roomy clips or overflows', (tester) async {
    // A single threshold is a guess, and the width just above it is where a
    // guess shows: the inline layout has to actually fit everywhere it is
    // chosen. Sweeping the range checks the threshold rather than trusting it.
    //
    // The sweep starts at 420 rather than 0 because flutter_test lays text out
    // in a placeholder font whose every glyph is a full square em -- "All
    // Sources" measures ~2.4x what real text of either language does, so the
    // view toggle alone reports 320px here against roughly 130 on screen.
    // That inflation makes the sweep conservative, which is what we want, but
    // it also means widths below ~420 fail on the font rather than on the
    // layout. 420 test-pixels is already a narrower bar than the panel
    // minimums (left 200 + right 250) permit in practice.
    for (var width = 420.0; width <= 1400.0; width += 20) {
      await pumpAtWidth(tester, width);

      expect(tester.takeException(), isNull, reason: 'Overflow at ${width}px');

      final bar = tester.getRect(find.byType(GalleryToolbar));
      final toggle = tester.getRect(find.text('All Results'));
      expect(toggle.right, lessThanOrEqualTo(bar.right + 0.01),
          reason: 'View toggle clipped at ${width}px');
    }
  });

  testWidgets('the thumbnail dialog slider follows the drag it caused', (tester) async {
    // The handle used to spring back to where the dialog opened while the
    // grid behind it kept resizing: the local holding the value was declared
    // inside the StatefulBuilder, so every rebuild reinitialised it. The grid
    // moved because the state was written through directly, which is what
    // made this read as lag rather than as a broken control.
    await pumpAtWidth(tester, 420);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thumbnail Size'));
    await tester.pumpAndSettle();

    final before = tester.widget<Slider>(find.byType(Slider)).value;

    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();

    final after = tester.widget<Slider>(find.byType(Slider)).value;
    expect(after, greaterThan(before), reason: 'The slider did not keep the value it was dragged to');

    // The readout beside it has to agree, and so does the grid it drives.
    expect(find.text('${after.toInt()}px'), findsOneWidget);
  });

  testWidgets('the thumbnail dialog is built from the themed dialog shell', (tester) async {
    // Raw AlertDialog ignores the app's surface and corner radius, which is
    // how this one ended up looking like a different application.
    await pumpAtWidth(tester, 420);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thumbnail Size'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a roomy bar carries the clear-workspace action', (tester) async {
    // The bug: this action was gated on `!isDesktop` inline and otherwise
    // lived only in the overflow menu, which exists only once the bar is too
    // narrow to inline. On a wide desktop bar both hosts were absent and the
    // temporary workspace could not be emptied at all.
    //
    // 1500 rather than the 1200 the other roomy test uses: flutter_test's
    // placeholder font measures every glyph as a full square em, so the added
    // button costs ~2.4x its real width and 1200 test-pixels no longer inlines.
    await pumpAtWidth(tester, 1500, workspaceCount: 3);

    expect(find.byType(PopupMenuButton<String>), findsNothing,
        reason: 'This width inlines, so the menu is not the host here');
    expect(find.text('Clear Workspace'), findsOneWidget);
  });

  testWidgets('the clear-workspace action stays off the bar outside the workspace view', (tester) async {
    // Nothing dropped, so nothing to clear -- and the action acts on a view
    // that is not the one on screen.
    await pumpAtWidth(tester, 1200);

    expect(find.text('Clear Workspace'), findsNothing);
  });

  testWidgets('the squeezed bar keeps the clear-workspace action in its menu', (tester) async {
    await pumpAtWidth(tester, 420, workspaceCount: 3);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Clear Workspace'), findsOneWidget);
  });

  testWidgets('clearing the workspace asks first, and empties it on yes', (tester) async {
    final appState = await pumpAtWidth(tester, 1500, workspaceCount: 3);

    await tester.tap(find.text('Clear Workspace'));
    await tester.pumpAndSettle();

    // Asked, not done: the workspace is assembled by hand and has no undo.
    expect(find.byType(AppDialog), findsOneWidget);
    expect(appState.galleryState.droppedImages, hasLength(3));

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(appState.galleryState.droppedImages, hasLength(3),
        reason: 'Cancel must leave the workspace alone');

    await tester.tap(find.text('Clear Workspace'));
    await tester.pumpAndSettle();
    // The dialog's own button, not the one on the bar behind it.
    await tester.tap(find.descendant(
      of: find.byType(AppDialog),
      matching: find.text('Clear Workspace'),
    ));
    await tester.pumpAndSettle();

    expect(appState.galleryState.droppedImages, isEmpty);
  });

  testWidgets('no width clips or overflows with the workspace on screen', (tester) async {
    // The same sweep as above, but with the clear button present: its width
    // has to be part of what decides whether the bar can inline. Left out of
    // that sum, the workspace view measured as though the button were not
    // there and overflowed by exactly its width.
    for (var width = 420.0; width <= 1400.0; width += 20) {
      await pumpAtWidth(tester, width, workspaceCount: 3);

      expect(tester.takeException(), isNull, reason: 'Overflow at ${width}px');

      final bar = tester.getRect(find.byType(GalleryToolbar));
      final toggle = tester.getRect(find.text('All Results'));
      expect(toggle.right, lessThanOrEqualTo(bar.right + 0.01),
          reason: 'View toggle clipped at ${width}px');
    }
  });

  testWidgets('the collapsed menu still reaches every control it swallowed', (tester) async {
    // Collapsing must not strand an action: select-all has no other entry
    // point on this screen.
    await pumpAtWidth(tester, 420);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Thumbnail Size'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });
}
