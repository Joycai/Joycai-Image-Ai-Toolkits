// Order arithmetic for the Prompt Library's lists.
//
// The repository stores one `sort_order` per row, written as each id's index
// in the list it is handed — so it must always be handed the **whole** list.
// A list the screen shows narrowed (by template type, or the full user list
// while a move button is pressed under a filter) is folded back into the
// full order here first.

/// [fullIds] with the positions held by [subsetInNewOrder]'s ids refilled, in
/// that new order. Ids outside the subset keep their places.
List<int> mergeSubsetOrder(List<int> fullIds, List<int> subsetInNewOrder) {
  final subset = subsetInNewOrder.toSet();
  var next = 0;
  return [
    for (final id in fullIds)
      if (subset.contains(id)) subsetInNewOrder[next++] else id,
  ];
}

/// [ids] with [id] moved to the front (or the back when [toEnd]).
List<int> moveIdToEdge(List<int> ids, int id, {required bool toEnd}) {
  final rest = [for (final other in ids) if (other != id) other];
  return toEnd ? [...rest, id] : [id, ...rest];
}

/// [items] reordered as a drag from [oldIndex] to [newIndex] leaves them,
/// where [newIndex] is already adjusted for the removal (`onReorderItem`).
List<T> reorderedCopy<T>(List<T> items, int oldIndex, int newIndex) {
  final copy = List<T>.of(items);
  final item = copy.removeAt(oldIndex);
  copy.insert(newIndex.clamp(0, copy.length), item);
  return copy;
}
