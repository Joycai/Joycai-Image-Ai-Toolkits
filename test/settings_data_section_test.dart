import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/data_section.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the data pane's action grid, and the scratch-file control in it.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory sandbox;

  setUp(() {
    // Its own directory: the button measures what it finds there and can
    // delete it, and `getTemporaryDirectory` on a dev machine can resolve to
    // the same place the installed app uses.
    sandbox = Directory.systemTemp.createTempSync('data_section_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => sandbox.path,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  /// Puts a file of [bytes] apparent length in the app's scratch directory.
  ///
  /// Truncated rather than written: the sizes here go up to most of a gigabyte
  /// to exercise the widest label, and actually writing that many zeroes cost
  /// nine seconds a test.
  void seedScratchFiles(int bytes) {
    final file = File(p.join(sandbox.path, 'joycai', 'masks', 'a.png'));
    file.parent.createSync(recursive: true);
    final handle = file.openSync(mode: FileMode.write);
    handle.truncateSync(bytes);
    handle.closeSync();
  }

  Future<void> pump(
    WidgetTester tester, {
    required bool isMobile,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = isMobile ? const Size(390, 1600) : const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Not disposed on purpose: the tree outlives the pump, and a disposed
    // AppState throws the moment anything in it rebuilds. The other widget
    // tests here do the same.
    final appState = AppState();

    // Pumped inside runAsync so the button's directory walk *starts* on the
    // real event loop. flutter_test runs the body in a fake-async zone, and
    // file I/O begun there is not guaranteed to complete however long the test
    // waits afterwards -- which is how this first read as "the label never
    // gets its size" rather than as a harness problem.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider.value(value: appState.galleryState),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(child: DataSection(isMobile: isMobile)),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  // The buttons sit in fixed 220px boxes, so a label that outgrows one
  // overflows rather than wrapping or shrinking. The scratch-file button
  // appends a measured size to its label, which makes it the longest label
  // here and the only one whose final length is not settled at translation
  // time -- so it is checked at a size wide enough to be realistic on a
  // working machine, in every locale the app ships.
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('the action grid lays out on desktop in ${locale.toLanguageTag()}',
        (tester) async {
      seedScratchFiles(987654321); // "941.9 MB"
      await pump(tester, isMobile: false, locale: locale);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the action grid lays out on mobile in ${locale.toLanguageTag()}',
        (tester) async {
      seedScratchFiles(987654321);
      await pump(tester, isMobile: true, locale: locale);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the scratch-file button reports what the app is holding', (tester) async {
    seedScratchFiles(123456);
    await pump(tester, isMobile: false);

    // 123456 B renders as "120.6 KB" through AppConstants.formatFileSize,
    // which keeps two decimals only under 10 of a unit.
    expect(find.textContaining('120.6 KB'), findsOneWidget);
  });

  testWidgets('the scratch-file button is inert with nothing to clear', (tester) async {
    await pump(tester, isMobile: false);

    // No size on the label, and no press to make: a greyed control is how a
    // settings pane says there is nothing here. "(0 B)" would be noise.
    expect(find.text('Clear Temporary Files'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Clear Temporary Files'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
