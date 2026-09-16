import '../models/llm_model.dart';

/// Which key the right-hand model list runs on (`D1d` 排序键).
///
/// Four keys, each answering one question: 「渠道给我的次序」,「那个模型叫
/// 什么来着」,「先给我看图像模型」,「我刚才加的那个」. Anything narrower —
/// context window, measured speed — waits until every model carries the
/// field, or the list sorts on a column most rows leave blank.
enum ModelSortKey {
  /// The stored order (`llm_models.sort_order`), which is what the list has
  /// always shown: discovery order, or whatever a hand reorder left behind.
  /// Also the way back — sorting is a *reading*, never a write, so this key
  /// can always restore what the channel gave.
  manual,
  name,
  kind,
  added,
}

/// Which way the list runs along its key.
enum ModelSortDirection { ascending, descending }

/// The order the kind key groups by: the order of the filter chips above the
/// list (`D1a · 1a`), not alphabetical — the two rows are read together, and
/// a list whose groups ran 对话 · 图像 · 多模态 · 视频 under chips that run
/// 对话 · 图像 · 视频 · 多模态 reads as no order at all. Legacy `refiner` and
/// anything a newer build invents fall in after the four.
const List<String> _kindRank = ['chat', 'image', 'video', 'multimodal'];

int _rankOf(String tag) {
  final index = _kindRank.indexOf(tag.toLowerCase());
  return index < 0 ? _kindRank.length : index;
}

/// [models] in the order the list should draw them.
///
/// Always a new list; [models] is never touched. Dart's `sort` is not stable,
/// so the stored index is carried explicitly and breaks every tie — two
/// models with the same name, or the whole list under [ModelSortKey.manual].
/// The tiebreak runs in the same direction as the key, which is what makes
/// 「降序」 the exact reverse of 「升序」 rather than a reshuffle of the ties.
List<LLMModel> sortModels(
  List<LLMModel> models, {
  required ModelSortKey key,
  required ModelSortDirection direction,
}) {
  final indexed = <(int, LLMModel)>[for (final (index, m) in models.indexed) (index, m)];
  final int sign = direction == ModelSortDirection.ascending ? 1 : -1;

  indexed.sort((a, b) {
    final compared = switch (key) {
      ModelSortKey.manual => 0,
      ModelSortKey.name => _byName(a.$2, b.$2),
      ModelSortKey.kind => _byKind(a.$2, b.$2),
      // Row ids rise with insertion, so they are the only record of when a
      // model was added — nothing on the row carries a timestamp. A model
      // not yet in the database sorts oldest, which is where an unsaved row
      // would sit anyway.
      ModelSortKey.added => (a.$2.id ?? -1).compareTo(b.$2.id ?? -1),
    };
    if (compared != 0) return compared * sign;
    return a.$1.compareTo(b.$1) * sign;
  });

  return [for (final entry in indexed) entry.$2];
}

/// The chip order, then the name inside a group — a kind sort that left its
/// groups in stored order would look like it had only half worked.
int _byKind(LLMModel a, LLMModel b) {
  final byRank = _rankOf(a.tag).compareTo(_rankOf(b.tag));
  if (byRank != 0) return byRank;
  return _byName(a, b);
}

/// Display name, case-insensitively, then the model id — two rows can share a
/// display name (the same model behind two relays) and the id is what tells
/// them apart.
int _byName(LLMModel a, LLMModel b) {
  final byName = a.modelName.toLowerCase().compareTo(b.modelName.toLowerCase());
  if (byName != 0) return byName;
  return a.modelId.toLowerCase().compareTo(b.modelId.toLowerCase());
}
