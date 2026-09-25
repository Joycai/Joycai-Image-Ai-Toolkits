import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/models/tag.dart';
import 'package:joycai_image_ai_toolkits/screens/prompts/widgets/prompt_dialogs.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_edit_dialog.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';
import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

/// An edit must not reset what its form does not show. Both cases here were
/// real: the editors used to hand the database a map of just the form's
/// fields, the columns left out fell back to their defaults on the way through
/// `fromMap`, and the whole row was written back.
///
/// Every test changes a field that *is* on the form and checks that too —
/// otherwise a Save that never landed would look like a Save that kept
/// everything.
void main() {
  usePrivateDataDir('joycai_edit_keeps_unedited_columns_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Finder fieldHolding(String text) =>
      find.byWidgetPredicate((w) => w is EditableText && w.controller.text == text);

  group('an update leaves alone what has a writer of its own', () {
    late DatabaseService db;
    setUp(() async => db = await openTestDatabase());
    tearDown(() async => closeTestDatabase(db));

    test('a model: its place in the list and its ETA estimate', () async {
      final id = await db.addModel(
        LLMModel(modelId: 'm', modelName: 'Before', tag: 'image', sortOrder: 7),
      );
      await db.updateModelEstimation(id, 4200.0, 650.0, 3);

      // What an editor that opened before the estimate landed would send.
      await db.updateModel(id, LLMModel(modelId: 'm', modelName: 'After', tag: 'image'));

      final saved = (await db.getModels()).single;
      expect(saved.modelName, 'After');
      expect(saved.sortOrder, 7);
      expect(saved.estMeanMs, 4200.0);
      expect(saved.estSdMs, 650.0);
      expect(saved.tasksSinceUpdate, 3);
    });

    // Each is reordered *after* the editor's copy was taken, then saved from
    // that copy — the workbench holds a preset like this for a whole session.
    test('a prompt, a preset and a tag: their place in the list', () async {
      final prompt = await db.addPrompt(Prompt(title: 'P', content: 'c'));
      final preset = await db.addSystemPrompt(
        SystemPrompt(title: 'S', content: 'c', type: SystemPrompt.typeRefiner),
      );
      final tag = await db.addPromptTag(PromptTag(name: 'T'));
      final heldPreset = (await db.getSystemPrompts()).firstWhere((r) => r.id == preset);

      // Two rows each, so that a reorder moves the one under test to 1.
      final prompt0 = await db.addPrompt(Prompt(title: 'P0', content: 'c'));
      final preset0 = await db.addSystemPrompt(
        SystemPrompt(title: 'S0', content: 'c', type: SystemPrompt.typeRefiner),
      );
      final tag0 = await db.addPromptTag(PromptTag(name: 'T0'));
      await db.updatePromptOrder([prompt0, prompt]);
      await db.updateSystemPromptOrder([preset0, preset]);
      await db.updateTagOrder([tag0, tag]);

      await db.updatePrompt(prompt, Prompt(title: 'P!', content: 'c'));
      await db.updateSystemPrompt(preset, heldPreset.withContent('c!'));
      await db.updatePromptTag(tag, PromptTag(name: 'T!'));

      final p = (await db.getPrompts()).firstWhere((r) => r.id == prompt);
      final s = (await db.getSystemPrompts()).firstWhere((r) => r.id == preset);
      final t = (await db.getPromptTags()).firstWhere((r) => r.id == tag);
      expect((p.title, p.sortOrder), ('P!', 1));
      expect((s.content, s.sortOrder), ('c!', 1));
      expect((t.name, t.sortOrder), ('T!', 1));
    });
  });

  testWidgets('saving a model keeps its place in the list and its ETA estimate', (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final (state, model) = await runAsyncRethrowing(tester, () async {
      final state = AppState();
      final channelId = await state.addChannel(
        LLMChannel(
          displayName: 'Relay',
          type: 'openai-api-rest',
          endpoint: 'https://relay.example.com/v1',
          apiKey: 'k',
        ),
      );
      final id = await state.addModel(
        LLMModel(
          modelId: 'gpt-image-1',
          modelName: 'GPT Image',
          tag: 'image',
          channelId: channelId,
          sortOrder: 7,
        ),
      );
      await DatabaseService().updateModelEstimation(id, 4200.0, 650.0, 3);
      await state.refreshDataCache();
      return (state, state.allModels.firstWhere((m) => m.id == id));
    });
    expect(model.estMeanMs, 4200.0);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ModelEditDialog(
              l10n: AppLocalizations.of(context)!,
              appState: state,
              model: model,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(fieldHolding('GPT Image'), 'Renamed');
    // The save is a database write: made in real async, and waited for by
    // the cache it refreshes rather than by a number of frames.
    await inRealAsyncUntil(
      tester,
      () => tester.tap(find.text('Save').last),
      until: () => state.allModels.any((m) => m.id == model.id && m.modelName == 'Renamed'),
    );
    await tester.pumpAndSettle();

    final saved = await runAsyncRethrowing(tester, () async {
      await state.refreshDataCache();
      return state.allModels.firstWhere((m) => m.id == model.id);
    });
    expect(saved.modelName, 'Renamed');
    expect(saved.sortOrder, 7);
    expect(saved.estMeanMs, 4200.0);
    expect(saved.estSdMs, 650.0);
    expect(saved.tasksSinceUpdate, 3);
  });

  testWidgets('renaming a built-in tag leaves it built-in', (tester) async {
    final (state, tag) = await runAsyncRethrowing(tester, () async {
      final state = AppState();
      final id = await state.addPromptTag(
        PromptTag(name: 'Built in', isSystem: true, sortOrder: 4),
      );
      final tags = await state.getPromptTags();
      return (state, tags.firstWhere((t) => t.id == id));
    });
    expect(tag.isSystem, isTrue);

    late BuildContext host;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    final tags = await runAsyncRethrowing(tester, state.getPromptTags);
    showTagEditDialog(host, AppLocalizations.of(host)!, tag: tag, tags: tags).ignore();
    await tester.pumpAndSettle();
    await tester.enterText(fieldHolding('Built in'), 'Renamed');
    // The write is real I/O: start it in real async, and wait until it has
    // landed, however long that is.
    // What it ends in is a row, which takes a query to see — hence a loop of
    // its own rather than `inRealAsyncUntil`, whose condition cannot await.
    final saved = await runAsyncRethrowing(tester, () async {
      await tester.tap(find.text('Save').last);
      final giveUp = DateTime.now().add(realAsyncGiveUp);
      while (true) {
        final now = (await state.getPromptTags()).firstWhere((t) => t.id == tag.id);
        if (now.name == 'Renamed') return now;
        if (DateTime.now().isAfter(giveUp)) fail('the save never reached the database');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();
    expect(saved.isSystem, isTrue);
    expect(saved.sortOrder, 4);
  });
}
