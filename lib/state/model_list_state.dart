import 'package:flutter/foundation.dart';

import '../models/llm_model.dart';
import '../services/catalogue/model_list_ordering.dart';
import '../services/db/database_service.dart';

/// How the Models screen's right-hand list is ordered (`D1d`).
///
/// Outside the screen for the reason `TaskListState` is: the shell throws the
/// screen away on every navigation, and a reading the user chose should not
/// come back to 「默认顺序」 because they looked at the gallery.
///
/// Both fields here are *preferences* — how this user likes to read a channel's
/// models — so both persist across launches and across channel switches. The
/// kind chip and the search box beside the sort button are session state and
/// deliberately stay where they are, in the column's own `State`.
class ModelListState extends ChangeNotifier {
  static const String sortKeySetting = 'model_sort_key';
  static const String sortDirectionSetting = 'model_sort_direction';
  static const String groupByChannelSetting = 'model_group_by_channel';

  ModelListState({DatabaseService? database}) : _db = database ?? DatabaseService();

  /// The database this state reads and writes. Defaults to the app's one
  /// [DatabaseService]; a test hands in a [DatabaseService.forDatabase] over
  /// an in-memory database and needs no private data directory.
  final DatabaseService _db;

  ModelSortKey sortKey = ModelSortKey.manual;
  ModelSortDirection sortDirection = ModelSortDirection.ascending;

  /// Whether the phone's Models tab keeps its per-channel groups (`D1d · 2e`).
  ///
  /// Only the phone asks this. Its tab lists *every* channel's models, so a
  /// key there has two readings that are both right — 「在这个渠道里按名称
  /// 排」 and 「不管渠道，按名称排」 — and the one thing that must not decide
  /// between them is the key itself: a screen that silently dissolves its
  /// groups because 「添加时间」 was picked is a screen nobody can predict.
  /// So it is a switch, laid over the key the way the file browser's
  /// 「按文件夹分组」 is (`B1a · 1f`). The desktop right column never asks:
  /// it is already one channel.
  ///
  /// On by default — that is what the tab has always done.
  bool groupByChannel = true;

  /// Whether the list is in the state it has always been in: stored order,
  /// running down. The sort button is quiet here and lit everywhere else.
  bool get isDefault =>
      sortKey == ModelSortKey.manual && sortDirection == ModelSortDirection.ascending;

  /// Whether the phone's tab is in the arrangement it has always had: the
  /// default reading *and* its channel groups. Its sort button lights on
  /// either departure — one flat list across every channel is as much a
  /// change to look at as a sort is.
  bool get isPhoneDefault => isDefault && groupByChannel;

  Future<void> load() async {
    // Anything that is not an explicit 「off」 reads as grouped, which is how
    // the two fields below treat a value they do not recognise. A default-on
    // flag that degraded the other way would dissolve every channel group on
    // the strength of one unparseable row.
    groupByChannel = await _db.getSetting(groupByChannelSetting) != false.toString();
    final savedKey = await _db.getSetting(sortKeySetting);
    sortKey = ModelSortKey.values.firstWhere(
      (key) => key.name == savedKey,
      orElse: () => ModelSortKey.manual,
    );
    final savedDirection = await _db.getSetting(sortDirectionSetting);
    sortDirection = ModelSortDirection.values.firstWhere(
      (direction) => direction.name == savedDirection,
      orElse: () => ModelSortDirection.ascending,
    );
    notifyListeners();
  }

  Future<void> setSortKey(ModelSortKey value) async {
    if (value == sortKey) return;
    sortKey = value;
    notifyListeners();
    await _db.saveSetting(sortKeySetting, value.name);
  }

  Future<void> setSortDirection(ModelSortDirection value) async {
    if (value == sortDirection) return;
    sortDirection = value;
    notifyListeners();
    await _db.saveSetting(sortDirectionSetting, value.name);
  }

  Future<void> setGroupByChannel(bool value) async {
    if (value == groupByChannel) return;
    groupByChannel = value;
    notifyListeners();
    await _db.saveSetting(groupByChannelSetting, value.toString());
  }

  /// [models] as the list should draw them under the current settings.
  List<LLMModel> arrange(List<LLMModel> models) =>
      sortModels(models, key: sortKey, direction: sortDirection);
}
