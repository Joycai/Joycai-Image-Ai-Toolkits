import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:joycai_image_ai_toolkits/state/log_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the wiring between [AppState] and the notifiers it owns.
///
/// [AppState] used to subscribe to each of its sub-states and re-emit their
/// notifications as its own. Most widgets in the app listen to [AppState], so a
/// directory rescan, a queue progress tick or a streamed log line rebuilt the
/// entire tree. The forwarding is gone; these tests hold that open, because the
/// failure mode in both directions is silent — nothing throws when a panel
/// stops updating, and nothing throws when the whole app rebuilds too often.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => Directory.systemTemp.path,
  );

  AppImage img(String name) => AppImage(path: '/tmp/$name.png', name: '$name.png');

  group('AppState does not re-broadcast its sub-states', () {
    test('a gallery change leaves AppState quiet', () {
      final appState = AppState();
      var appStateNotifications = 0;
      void count() => appStateNotifications++;
      appState.addListener(count);
      addTearDown(() => appState.removeListener(count));

      appState.galleryState.toggleImageSelection(img('a'));

      expect(
        appStateNotifications,
        0,
        reason: 'selecting a thumbnail must not rebuild every AppState listener',
      );
    });

    test('a log line leaves AppState quiet', () {
      final appState = AppState();
      var appStateNotifications = 0;
      void count() => appStateNotifications++;
      appState.addListener(count);
      addTearDown(() => appState.removeListener(count));

      // The streaming path: one of these per chunk of model output.
      appState.addLog('[AI]: hello');
      appState.addLog('[AI]: world');

      expect(appStateNotifications, 0);
    });

    test('the log still reaches LogState, merged and flagged', () {
      final appState = AppState();
      appState.logState.clear();

      appState.addLog('[AI]: hel');
      appState.addLog('[AI]: lo');
      appState.addLog('boom', level: 'ERROR');

      expect(appState.logState.logs.length, 2);
      expect(appState.logState.logs.first.message, '[AI]: hello');
      expect(appState.logState.hasErrors, isTrue);
    });
  });

  group('derived model lists are stable', () {
    test('reading twice returns the same instance', () {
      final appState = AppState();

      // `context.select` compares with `==`, and List does not override it.
      // These were `_models.where(...).toList()` getters, so every read handed
      // back a new object and every selector over one reported "changed" on
      // every notification — the selector cost something and bought nothing.
      // Nothing throws when that regresses; the panels just rebuild forever.
      expect(identical(appState.imageModels, appState.imageModels), isTrue);
      expect(identical(appState.chatModels, appState.chatModels), isTrue);
      expect(identical(appState.videoModels, appState.videoModels), isTrue);
      expect(
        identical(appState.multimodalModels, appState.multimodalModels),
        isTrue,
      );
    });
  });

  group('sub-state consumers still rebuild', () {
    /// [GalleryState] reads its settings from SQLite while constructing. That
    /// query has to land on the real clock, before the widget binding's fake
    /// one takes over, or the test ends with a timer still pending.
    Future<GalleryState> settledGalleryState(WidgetTester tester) async {
      final state = GalleryState();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      return state;
    }

    testWidgets('a GalleryState selector fires on a selection change',
        (tester) async {
      final galleryState = await settledGalleryState(tester);
      var builds = 0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: galleryState)],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Selector<GalleryState, int>(
              selector: (_, s) => s.selectionNumberOf('/tmp/a.png'),
              builder: (context, number, _) {
                builds++;
                return Text('$number');
              },
            ),
          ),
        ),
      );

      expect(builds, 1);
      expect(find.text('0'), findsOneWidget);

      galleryState.toggleImageSelection(img('a'));
      await tester.pump();

      expect(builds, 2);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('the same selector ignores an unrelated AppState change',
        (tester) async {
      final appState = AppState();
      final galleryState = await settledGalleryState(tester);
      var builds = 0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider.value(value: galleryState),
          ],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Selector<GalleryState, int>(
              selector: (_, s) => s.selectedImages.length,
              builder: (context, count, _) {
                builds++;
                return Text('$count');
              },
            ),
          ),
        ),
      );

      expect(builds, 1);

      appState.notify();
      await tester.pump();

      expect(builds, 1);
    });
  });

  group('LogState coalesces', () {
    test('a burst of lines costs one notification after the first', () async {
      final logState = LogState();
      addTearDown(logState.dispose);

      var notifications = 0;
      logState.addListener(() => notifications++);

      for (var i = 0; i < 50; i++) {
        logState.add('chunk $i');
      }

      // Leading edge only: the first line is immediate, the other 49 are still
      // inside the coalescing window.
      expect(notifications, 1);

      // One more once the window closes, carrying everything that piled up.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifications, 2);
      expect(logState.logs.length, 50);
    });
  });
}
