import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/main.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/private_data_dir.dart';
import '../support/real_async.dart';

void main() {
  usePrivateDataDir('joycai_widget_test');
  useRealAsyncAppState();

  setUpAll(() {
    // Initialize FFI for desktop (windows/linux/macos) unit tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Set a large surface size to mimic desktop
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;

    // Build our app and trigger a frame.
    final appState = AppState();
    // Real async: every screen's initState reads the database.
    await pumpWidgetInRealAsync(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: appState.taskQueue),
          ChangeNotifierProvider.value(value: appState.workbenchUIState),
          ChangeNotifierProvider.value(value: appState.fileBrowserState),
          ChangeNotifierProvider.value(value: appState.galleryState),
          ChangeNotifierProvider.value(value: appState.downloaderState),
          ChangeNotifierProvider.value(value: appState.logState),
        ],
        child: const MyApp(version: '2.1.0'),
      ),
    );

    // Wait for the async initialization in AppState (loadSettings)
    // We pump a few frames to allow async ops to start, though strictly
    // async filesystem/db calls might not complete without proper mocking.
    // For a smoke test, we just want to ensure the UI renders without crashing.
    await tester.pump();

    // Desktop layout uses a custom nav rail, not Flutter's NavigationRail.
    // Verify desktop mode by asserting no bottom NavigationBar is shown.
    expect(find.byType(NavigationBar), findsNothing);

    // Exercise the real root: a global ExcludeSemantics (formerly Windows-only)
    // leaves painted navigation intact while making it invisible to readers.
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;
    final nodes = <SemanticsNode>[];
    void collect(SemanticsNode node) {
      nodes.add(node);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
    expect(
      nodes.where((node) => node.label == l10n.settings && node.flagsCollection.isButton),
      isNotEmpty,
      reason: 'The shell navigation must remain accessible outside the Navigator.',
    );
    final settings = nodes
        .singleWhere((node) => node.label == l10n.settings && node.flagsCollection.isButton)
        .getSemanticsData();
    expect(settings.tooltip, isEmpty, reason: 'Navigation must not repeat its name as a tooltip.');
    expect(settings.hint, isNotEmpty, reason: 'Keep the keyboard shortcut available to readers.');
    semantics.dispose();
  });
}
