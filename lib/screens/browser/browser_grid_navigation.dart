import 'package:flutter/widgets.dart';

import '../../core/grid_cursor.dart';
import '../../models/browser_file.dart';
import '../../state/file_browser_state.dart';
import 'widgets/browser_selection_bar.dart';

/// Transient focus and geometry for the browser's virtualized file area.
class BrowserGridNavigation extends ChangeNotifier {
  BrowserGridNavigation(this.node, this.scroll) {
    node.addListener(_focusChanged);
  }

  final FocusNode node;
  final ScrollController scroll;
  final GridCursor cursor = GridCursor();
  final Map<String, double> _offsets = {};
  List<BrowserFile>? _files;
  Object? _geometry;
  double _extent = 0;
  bool _disposed = false;

  void layout(
    List<BrowserFile> files,
    List<FolderSection> sections, {
    required int columns,
    required double extent,
    required double header,
    required double gap,
    required double viewport,
  }) {
    final geometry = (columns, extent, header, gap, viewport, sections);
    if (identical(files, _files) && geometry == _geometry) return;
    _files = files;
    _geometry = geometry;
    _extent = extent;
    final groups = sections.isEmpty
        ? [files]
        : [
            for (final section in sections)
              files.sublist(section.start, section.start + section.count),
          ];
    cursor.layout([
      for (final group in groups) [for (final file in group) file.path],
    ], columns);
    _offsets.clear();
    var offset = 0.0;
    for (final group in groups) {
      offset += (sections.isEmpty ? 0 : header) + gap;
      for (var i = 0; i < group.length; i++) {
        _offsets[group[i].path] = offset + (i ~/ columns) * (extent + gap);
      }
      final rows = (group.length / columns).ceil();
      offset += rows * (extent + gap);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      notifyListeners();
      if (node.hasPrimaryFocus) reveal();
    });
  }

  void point(String path) {
    cursor.point(path);
    notifyListeners();
  }

  void moved() {
    notifyListeners();
    reveal();
  }

  void reveal() {
    final top = _offsets[cursor.active];
    if (top == null || !scroll.hasClients) return;
    final position = scroll.position;
    final visible = (position.viewportDimension - BrowserSelectionBar.clearance).clamp(
      _extent,
      double.infinity,
    );
    final target = top < position.pixels
        ? top
        : top + _extent > position.pixels + visible
        ? top + _extent - visible
        : position.pixels;
    scroll.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  void _focusChanged() {
    notifyListeners();
    if (node.hasPrimaryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && node.hasPrimaryFocus) reveal();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    node.removeListener(_focusChanged);
    super.dispose();
  }
}
