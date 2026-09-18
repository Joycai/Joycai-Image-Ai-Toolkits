import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/channel_merge.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/channel_merge_executor.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// Standard 04 §4–5: the order a merge is written in, and what it rewrites.
class _RecordingStore implements MergeStore {
  final calls = <String>[];
  bool failWrite = false;

  @override
  Future<void> write(MergePlan plan) async {
    calls.add('write');
    if (failWrite) throw StateError('disk full');
  }

  @override
  Future<void> remapSelections(Map<int, int> idMap) async =>
      calls.add('selections');

  @override
  Future<void> remapHistory(Map<int, int> idMap) async => calls.add('history');

  @override
  Future<int> countReferences(Iterable<int> ids) async => 0;
}

MergePlan _plan(Map<int, int> idMap) => MergePlan(
  channel: LLMChannel(
    id: 1,
    displayName: 'k',
    endpoint: 'https://relay.example.com/v1',
    apiKey: 'k',
    type: Vendors.newApiOpenAI,
  ),
  addedRoutes: const [],
  updates: const [],
  deletes: idMap.keys.toList(),
  idMap: idMap,
  movedCount: 0,
  absorbedChannelId: 2,
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('order', () {
    test('the transaction, then selections, then history', () async {
      final store = _RecordingStore();
      await ChannelMergeExecutor(store).run(_plan({20: 10}));
      expect(store.calls, ['write', 'selections', 'history']);
    });

    test('nothing to rewrite when nothing merged away', () async {
      final store = _RecordingStore();
      await ChannelMergeExecutor(store).run(_plan(const {}));
      expect(store.calls, ['write']);
    });

    test('a failed transaction rewrites no reference', () async {
      final store = _RecordingStore()..failWrite = true;
      await expectLater(
        ChannelMergeExecutor(store).run(_plan({20: 10})),
        throwsStateError,
      );
      expect(store.calls, ['write']);
    });
  });

  group('against the database', () {
    usePrivateDataDir('joycai_channel_merge_executor_test');

    test('merges, moves, deletes and rewrites every reference', () async {
      final db = DatabaseService();
      final keepId = await db.addChannel({
        'display_name': 'Relay',
        'type': Vendors.newApiOpenAI,
        'endpoint': 'https://relay.example.com/v1',
        'api_key': 'sk-shared',
      });
      final absorbId = await db.addChannel({
        'display_name': 'Relay (Claude)',
        'type': Vendors.newApiAnthropic,
        'endpoint': 'https://relay.example.com/v1',
        'api_key': 'sk-shared',
      });
      final keptModel = await db.addModel({
        'model_id': 'claude-sonnet-4-5',
        'model_name': 'Sonnet',
        'tag': 'chat',
        'channel_id': keepId,
      });
      final twin = await db.addModel({
        'model_id': 'claude-sonnet-4-5',
        'model_name': 'Sonnet (Claude)',
        'tag': 'chat',
        'channel_id': absorbId,
        'max_output_tokens': 64000,
      });
      final lone = await db.addModel({
        'model_id': 'claude-opus-4-1',
        'model_name': 'Opus',
        'tag': 'chat',
        'channel_id': absorbId,
      });
      await db.saveSetting('last_model_id', '$twin');
      await db.saveSetting('last_video_model_id', '$lone');
      final raw = await db.database;
      await raw.insert('token_usage', {
        'model_id': 'claude-sonnet-4-5',
        'model_pk': twin,
        'timestamp': '2026-09-18T00:00:00',
      });
      await raw.insert('tasks', {'id': 't1', 'model_pk': twin});

      final channels = await db.getChannels();
      final plan = ChannelMerge.candidates(
        channels,
        await db.getModels(),
      ).single.plan;
      final executor = ChannelMergeExecutor();
      // Two usage/task rows and one selection name the merged-away model.
      expect(await executor.referenceCount(plan), 3);

      await executor.run(plan);

      final after = await db.getChannels();
      expect(after.map((c) => c.id), [keepId]);
      expect(
        RoutedChannel.routesOf(after.single).has(RouteKind.anthropic),
        isTrue,
      );
      final models = {for (final m in await db.getModels()) m.id!: m};
      expect(models.keys.toSet(), {keptModel, lone});
      expect(models[lone]!.channelId, keepId);
      expect(models[lone]!.activeRoute, 'anthropic');
      expect(
        ModelRoutes.parked(
          models[keptModel]!,
        )[RouteKind.anthropic]?.maxOutputTokens,
        64000,
      );

      expect(await db.getSetting('last_model_id'), '$keptModel');
      // A moved model keeps its id; its selection is left alone.
      expect(await db.getSetting('last_video_model_id'), '$lone');
      final usage = await raw.query('token_usage');
      expect(usage.single['model_pk'], keptModel);
      final tasks = await raw.query('tasks');
      expect(tasks.single['model_pk'], keptModel);
    });
  });
}
