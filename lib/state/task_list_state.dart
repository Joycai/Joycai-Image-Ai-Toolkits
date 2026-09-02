import 'package:flutter/foundation.dart';

import '../models/task_item.dart';
import '../services/database_service.dart';
import '../services/task_list_ordering.dart';

/// How the task list is filtered, ordered and grouped.
///
/// Lives outside the screen because the screen does not: the shell swaps
/// screens in and out as the user navigates, so a filter kept in the screen's
/// own `State` was back on 「全部」 every time they came back to it.
///
/// Two kinds of thing here, with two lifetimes (`C1 11b` note 03):
///
/// - [sortOrder] and [pinActive] are *preferences* — how this user likes to
///   read the list — and persist across launches.
/// - [filter] is *session* state — what they are looking at right now — and
///   comes back to 「全部」 on the next launch, so the screen never opens on
///   an empty 「失败」 view left over from last week.
class TaskListState extends ChangeNotifier {
  static const String sortOrderKey = 'task_sort_order';
  static const String pinActiveKey = 'task_pin_active';

  final DatabaseService _db = DatabaseService();

  TaskFilter filter = TaskFilter.all;
  TaskSortOrder sortOrder = TaskSortOrder.newestFirst;
  bool pinActive = true;

  Future<void> load() async {
    final savedOrder = await _db.getSetting(sortOrderKey);
    sortOrder = TaskSortOrder.values.firstWhere(
      (order) => order.name == savedOrder,
      orElse: () => TaskSortOrder.newestFirst,
    );
    pinActive = (await _db.getSetting(pinActiveKey) ?? 'true') == 'true';
    notifyListeners();
  }

  void setFilter(TaskFilter value) {
    if (value == filter) return;
    filter = value;
    notifyListeners();
  }

  Future<void> setSortOrder(TaskSortOrder value) async {
    if (value == sortOrder) return;
    sortOrder = value;
    notifyListeners();
    await _db.saveSetting(sortOrderKey, value.name);
  }

  Future<void> setPinActive(bool value) async {
    if (value == pinActive) return;
    pinActive = value;
    notifyListeners();
    await _db.saveSetting(pinActiveKey, value.toString());
  }

  /// [queue] as the list should draw it under the current settings.
  ArrangedTasks arrange(List<TaskItem> queue) => arrangeTasks(
        queue,
        filter: filter,
        order: sortOrder,
        pinActive: pinActive,
      );
}
