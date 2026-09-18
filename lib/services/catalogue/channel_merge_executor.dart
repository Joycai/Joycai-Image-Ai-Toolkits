import '../db/database_service.dart';
import '../db/repositories/assistant_session_repository.dart';
import '../db/repositories/model_repository.dart';
import '../db/repositories/usage_repository.dart';
import 'channel_merge.dart';

/// What a merge will rewrite, by kind — the preview says each on its own
/// (`D1f · 4f`).
class MergeReferences {
  /// Stored model selections (workbench, video, AI rename).
  final int selections;

  /// Usage and task rows.
  final int records;

  /// Model links inside saved assistant conversations.
  final int links;

  const MergeReferences({this.selections = 0, this.records = 0, this.links = 0});

  int get total => selections + records + links;
}

/// Where a merge is written. One method per step so the order the executor
/// takes them in is the thing a test pins.
abstract class MergeStore {
  /// The whole plan, in one transaction.
  Future<void> write(MergePlan plan);

  /// Every stored model selection (the workbench, video and AI-rename
  /// pickers) moved through [idMap].
  Future<void> remapSelections(Map<int, int> idMap);

  /// Usage and task history moved through [idMap].
  Future<void> remapHistory(Map<int, int> idMap);

  /// The model links inside saved assistant conversations moved through
  /// [idMap].
  Future<void> remapConversations(Map<int, int> idMap);

  /// How many stored references name one of [ids] — the preview's counts.
  Future<MergeReferences> countReferences(Iterable<int> ids);
}

/// Carries out a confirmed [MergePlan] (standard 04 §4): the plan in one
/// transaction, and only once it has committed, every reference to a model
/// that merged away — the selections first, since they decide what the
/// next task runs on, then the history, then the model links inside saved
/// assistant conversations.
///
/// A key has no separate cleanup step: it lives in the absorbed channel's
/// row, which the transaction deletes, and the kept channel holds the same
/// key.
class ChannelMergeExecutor {
  final MergeStore store;

  ChannelMergeExecutor([MergeStore? store])
    : store = store ?? DatabaseMergeStore();

  Future<void> run(MergePlan plan) async {
    await store.write(plan);
    if (plan.idMap.isEmpty) return;
    await store.remapSelections(plan.idMap);
    await store.remapHistory(plan.idMap);
    await store.remapConversations(plan.idMap);
  }

  /// References [plan] will rewrite, for the preview.
  Future<MergeReferences> referenceCount(MergePlan plan) =>
      store.countReferences(plan.idMap.keys);
}

class DatabaseMergeStore implements MergeStore {
  /// Settings that hold a model row id, as a stringified int.
  static const List<String> selectionKeys = [
    'last_model_id',
    'last_video_model_id',
    'last_ai_rename_model_id',
  ];

  final DatabaseService _db = DatabaseService();

  @override
  Future<void> write(MergePlan plan) => ModelRepository().mergeChannels(
    channel: plan.channel,
    updates: plan.updates,
    deletes: plan.deletes,
    absorbedChannelId: plan.absorbedChannelId,
  );

  @override
  Future<void> remapSelections(Map<int, int> idMap) async {
    for (final key in selectionKeys) {
      final to = idMap[int.tryParse(await _db.getSetting(key) ?? '')];
      if (to != null) await _db.saveSetting(key, '$to');
    }
  }

  @override
  Future<void> remapHistory(Map<int, int> idMap) =>
      UsageRepository().remapModels(idMap);

  @override
  Future<void> remapConversations(Map<int, int> idMap) =>
      AssistantSessionRepository().remapModelLinks(idMap);

  @override
  Future<MergeReferences> countReferences(Iterable<int> ids) async {
    final set = ids.toSet();
    var selections = 0;
    for (final key in selectionKeys) {
      if (set.contains(int.tryParse(await _db.getSetting(key) ?? ''))) {
        selections++;
      }
    }
    return MergeReferences(
      selections: selections,
      records: await UsageRepository().countModelRows(set),
      links: await AssistantSessionRepository().countModelLinks(set),
    );
  }
}
