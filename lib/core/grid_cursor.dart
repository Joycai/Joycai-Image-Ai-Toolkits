/// Logical focus for a virtualized, grouped grid. No per-item focus nodes.
class GridCursor {
  List<String> _items = const [];
  List<List<String>> _rows = const [];
  String? active;
  String? anchor;

  List<String> get items => _items;

  /// Keeps identity through sorting; a removed item falls back to its old slot.
  void layout(List<List<String>> groups, int columns) {
    assert(columns > 0);
    final oldIndex = _items.indexOf(active ?? '');
    _items = [for (final group in groups) ...group];
    _rows = [
      for (final group in groups)
        for (var i = 0; i < group.length; i += columns)
          group.sublist(i, (i + columns).clamp(0, group.length)),
    ];
    if (!_items.contains(active)) {
      active = _items.isEmpty ? null : _items[oldIndex.clamp(0, _items.length - 1)];
    }
    if (!_items.contains(anchor)) anchor = active;
  }

  void point(String path) {
    if (!_items.contains(path)) return;
    active = path;
    anchor = path;
  }

  /// Horizontal moves follow display order; vertical moves follow actual rows,
  /// including partial rows on either side of a group header. Never wraps.
  String? move({int horizontal = 0, int vertical = 0, bool extend = false}) {
    if (active == null) return null;
    if (!extend) anchor = active;
    if (horizontal != 0) {
      final index = (_items.indexOf(active!) + horizontal).clamp(0, _items.length - 1);
      active = _items[index];
    } else if (vertical != 0) {
      final row = _rows.indexWhere((r) => r.contains(active));
      final column = _rows[row].indexOf(active!);
      final target = _rows[(row + vertical).clamp(0, _rows.length - 1)];
      active = target[column.clamp(0, target.length - 1)];
    }
    if (!extend) anchor = active;
    return active;
  }

  List<String> get range {
    if (active == null) return const [];
    final a = _items.indexOf(anchor ?? active!);
    final b = _items.indexOf(active!);
    return _items.sublist(a < b ? a : b, (a > b ? a : b) + 1);
  }
}
