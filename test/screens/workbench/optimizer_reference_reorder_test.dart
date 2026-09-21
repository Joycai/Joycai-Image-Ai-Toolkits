// `A3c`: the Prompt Assistant's reference images reorder by drag, and the
// list order is what the next turn sends — the number on a card is the image
// id the model sees.
//
// Pinned here: the state move keeps result images at their own list
// positions, the panel's drag moves the list, a running turn locks it, and
// the footer line says which of those states the column is in.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/optimizer_reference_panel.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';
import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

AppImage _img(String name) => AppImage(path: '/nowhere/$name', name: name);

List<String> _names(WorkbenchUIState s) => [for (final i in s.optimizerReferenceImages) i.name];

void main() {
  usePrivateDataDir('joycai_optimizer_reference_reorder_test');
  useRealAsyncAppState();

  Future<AppLocalizations> en() => AppLocalizations.delegate.load(const Locale('en'));

  group('reorderAssistantReferences', () {
    test('moves within the given slots and leaves the others in place', () {
      final state = WorkbenchUIState()
        ..addAssistantImages([_img('a'), _img('r'), _img('b'), _img('c')]);
      // `r` is a result at list position 1: its id must not move.
      expect(state.reorderAssistantReferences(const [0, 2, 3], 2, 0), isTrue);
      expect(_names(state), ['c', 'r', 'a', 'b']);
    });

    test('hands out a new list, and a no-op move does not notify', () {
      final state = WorkbenchUIState()..addAssistantImages([_img('a'), _img('b')]);
      var notified = 0;
      state.addListener(() => notified++);

      final before = state.optimizerReferenceImages;
      state.reorderAssistantReferences(const [0, 1], 0, 0);
      expect(notified, 0);
      expect(identical(state.optimizerReferenceImages, before), isTrue);

      state.reorderAssistantReferences(const [0, 1], 0, 1);
      expect(notified, 1);
      expect(identical(state.optimizerReferenceImages, before), isFalse);
      expect(_names(state), ['b', 'a']);
    });

    test('refuses while a turn runs', () {
      final state = WorkbenchUIState()..addAssistantImages([_img('a'), _img('b')]);
      state.optimizerSession.setRunningForTest(true);
      expect(state.reorderAssistantReferences(const [0, 1], 0, 1), isFalse);
      expect(_names(state), ['a', 'b']);
      state.optimizerSession.setRunningForTest(false);
    });

    test('ignores indices from a stale build', () {
      final state = WorkbenchUIState()..addAssistantImages([_img('a'), _img('b')]);
      state.reorderAssistantReferences(const [0, 1, 2], 2, 0);
      state.reorderAssistantReferences(const [0, 1], 0, 5);
      expect(_names(state), ['a', 'b']);
    });
  });

  group('the reference column', () {
    Future<WorkbenchUIState> pumpPanel(
      WidgetTester tester,
      List<String> names, {
      void Function(AppState appState, WorkbenchUIState wui)? seed,
    }) async {
      final wui = WorkbenchUIState()..addAssistantImages([for (final n in names) _img(n)]);
      final appState = AppState();
      seed?.call(appState, wui);
      // Tall enough for three 110px cards and the footer line.
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<WorkbenchUIState>.value(value: wui),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(width: 240, height: 900, child: OptimizerReferencePanel()),
          ),
        ),
      ));
      await tester.pump();
      return wui;
    }

    Future<void> dragUp(WidgetTester tester, String name) async {
      final gesture = await tester.startGesture(tester.getCenter(find.text(name)));
      // Past the touch long-press (300ms); a mouse drag starts at once anyway.
      await tester.pump(const Duration(milliseconds: 500));
      // Two cards up: a small move to start the drag, then the rest. The list
      // takes a slot when the lifted card's top edge is in that slot's upper
      // half, so the move stops there rather than overshooting the list.
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -280));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a drag moves the image in the list the next turn sends', (tester) async {
      final wui = await pumpPanel(tester, ['a.png', 'b.png', 'c.png']);
      final l10n = await en();
      final touch = defaultTargetPlatform == TargetPlatform.android;
      expect(find.text(touch ? l10n.optRefReorderHintTouch : l10n.optRefReorderHint), findsOneWidget);

      await dragUp(tester, 'c.png');

      expect(_names(wui), ['c.png', 'a.png', 'b.png']);
      expect(tester.takeException(), isNull);
    }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.macOS, TargetPlatform.android}));

    testWidgets('a running turn locks the order and says so', (tester) async {
      final wui = await pumpPanel(tester, ['a.png', 'b.png', 'c.png']);
      final l10n = await en();
      wui.optimizerSession.setRunningForTest(true);
      await tester.pump();

      expect(find.text(l10n.optRefReorderLocked), findsOneWidget);
      await dragUp(tester, 'c.png');
      expect(_names(wui), ['a.png', 'b.png', 'c.png']);

      wui.optimizerSession.setRunningForTest(false);
    });

    testWidgets('a turn still waiting in the queue locks the order too', (tester) async {
      // Taken by the queue but not yet in the agent (the executor reads the
      // model and settings first): the session is not running, but the task
      // has already fixed the images in their current order. `processing`
      // rather than `pending`, which the queue would pick up and run here.
      final wui = await pumpPanel(
        tester,
        ['a.png', 'b.png', 'c.png'],
        seed: (appState, wui) => appState.taskQueue.setQueueForTest([
          TaskItem(
            id: 'queued-turn',
            type: TaskType.promptRefine,
            imagePaths: [for (final i in wui.optimizerReferenceImages) i.path],
            modelId: 'm',
            parameters: {'sessionId': wui.optimizerSession.id},
            status: TaskStatus.processing,
          ),
        ]),
      );
      final l10n = await en();

      expect(wui.optimizerSession.isRunning, isFalse);
      expect(find.text(l10n.optRefReorderLocked), findsOneWidget);
      await dragUp(tester, 'c.png');
      expect(_names(wui), ['a.png', 'b.png', 'c.png']);
    });

    testWidgets('a single image keeps the numbering line', (tester) async {
      await pumpPanel(tester, ['a.png']);
      final l10n = await en();
      expect(find.text(l10n.optRefNumberingHint), findsOneWidget);
      expect(find.text(l10n.optRefReorderHint), findsNothing);
      expect(find.text(l10n.optRefReorderHintTouch), findsNothing);
    });
  });
}
