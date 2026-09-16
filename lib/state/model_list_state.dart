import 'package:flutter/foundation.dart';

import '../models/llm_model.dart';
import '../services/database_service.dart';
import '../services/model_list_ordering.dart';

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

  final DatabaseService _db = DatabaseService();

  ModelSortKey sortKey = ModelSortKey.manual;
  ModelSortDirection sortDirection = ModelSortDirection.ascending;

  /// Whether the list is in the state it has always been in: stored order,
  /// running down. The sort button is quiet here and lit everywhere else.
  bool get isDefault =>
      sortKey == ModelSortKey.manual && sortDirection == ModelSortDirection.ascending;

  Future<void> load() async {
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

  /// [models] as the list should draw them under the current settings.
  List<LLMModel> arrange(List<LLMModel> models) =>
      sortModels(models, key: sortKey, direction: sortDirection);
}
