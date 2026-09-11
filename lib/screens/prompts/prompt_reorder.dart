// Order arithmetic for the Prompt Library's lists.
//
// The repository stores one `sort_order` per row, written as each id's index
// in the list it is handed — so it must always be handed the **whole** list.
// A list the screen shows narrowed (by template type, or by a filter or
// search while a move from the card menu or the keyboard runs) is folded back
// into the full order here first.

/// [fullIds] with the positions held by [subsetInNewOrder]'s ids refilled, in
/// that new order. Ids outside the subset keep their places; subset ids that
/// are not in [fullIds] are ignored rather than taking a place they never had.
List<int> mergeSubsetOrder(List<int> fullIds, List<int> subsetInNewOrder) {
  final present = fullIds.toSet();
  final order = [for (final id in subsetInNewOrder) if (present.contains(id)) id];
  final subset = order.toSet();
  var next = 0;
  return [
    for (final id in fullIds)
      if (subset.contains(id)) order[next++] else id,
  ];
}

/// [ids] with [id] moved to the front (or the back when [toEnd]).
List<int> moveIdToEdge(List<int> ids, int id, {required bool toEnd}) {
  final rest = [for (final other in ids) if (other != id) other];
  return toEnd ? [...rest, id] : [id, ...rest];
}

/// Move up / Move down as the user sees it: [id] trades places with its
/// neighbour in [visibleIds] — the card shown above it, or below when [down] —
/// and each takes the other's slot in [fullIds]. Ids not shown keep theirs, so
/// under a filter the card passes exactly the card the user saw it pass, never
/// a hidden one (which would look like nothing happened).
///
/// [fullIds] unchanged when [id] is not shown or is already at that end.
List<int> moveIdPastVisibleNeighbour(
  List<int> fullIds,
  List<int> visibleIds,
  int id, {
  required bool down,
}) {
  final at = visibleIds.indexOf(id);
  final to = down ? at + 1 : at - 1;
  if (at < 0 || to < 0 || to >= visibleIds.length) return List.of(fullIds);
  final shown = List.of(visibleIds)
    ..[at] = visibleIds[to]
    ..[to] = id;
  return mergeSubsetOrder(fullIds, shown);
}

/// [items] reordered as a drag from [oldIndex] to [newIndex] leaves them,
/// where [newIndex] is already adjusted for the removal (`onReorderItem`).
List<T> reorderedCopy<T>(List<T> items, int oldIndex, int newIndex) {
  final copy = List<T>.of(items);
  final item = copy.removeAt(oldIndex);
  copy.insert(newIndex.clamp(0, copy.length), item);
  return copy;
}
