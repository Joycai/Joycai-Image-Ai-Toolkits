import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'folder_outline_geometry.dart';

/// Tracks which folder section a grouped scroll view is showing, and jumps
/// between them.
///
/// Owns nothing visual. It listens to a [ScrollController], keeps the
/// section offset table from [FolderOutlineGeometry] memoised against the
/// inputs it was computed from, and publishes one integer — [currentIndex]
/// — for the outline's chips to watch. The grid must never rebuild because
/// the user scrolled, so this is deliberately not a ChangeNotifier the grid
/// could end up subscribed to: the only thing that moves is the
/// `ValueNotifier`, and only the chips listen to it.
class FolderOutlineSpy {
  FolderOutlineSpy();

  /// The section under the top of the viewport. See
  /// [FolderOutlineGeometry.sectionAt].
  final ValueNotifier<int> currentIndex = ValueNotifier<int>(-1);

  ScrollController? _controller;
  List<double> _offsets = const [];
  double _line = 0;
  _LayoutKey? _key;

  /// While a [scrollTo] is in flight the index is pinned to its target, so
  /// the chips do not light up every section the animation passes through.
  bool _locked = false;

  /// The section offsets in use, for tests and for callers that need a
  /// header's position without scrolling to it.
  List<double> get offsets => _offsets;

  /// Where, in viewport coordinates, a section header counts as reached —
  /// the bottom edge of the outline bar the content scrolls under. Set by
  /// [layout].
  double get line => _line;

  /// Starts following [controller]; replaces any earlier one.
  void attach(ScrollController controller) {
    if (identical(_controller, controller)) return;
    _controller?.removeListener(_onScroll);
    _controller = controller..addListener(_onScroll);
    _onScroll();
  }

  /// Stops following the controller attached last, if any.
  void detach() {
    _controller?.removeListener(_onScroll);
    _controller = null;
  }

  /// Recomputes the offset table when any of its inputs changed, and is a
  /// no-op otherwise — so a layout pass that merely repeated itself does not
  /// allocate or re-notify.
  ///
  /// Parameters mirror [FolderOutlineGeometry.sectionOffsets]; [line] is the
  /// judgment line, see [FolderOutlineSpy.line].
  void layout({
    required List<int> counts,
    required int columns,
    required double cellExtent,
    required double headerExtent,
    required double spacing,
    double topInset = 0,
    double line = 0,
    double? leading,
    double? trailing,
  }) {
    final key = _LayoutKey(
      counts: counts,
      columns: columns,
      cellExtent: cellExtent,
      headerExtent: headerExtent,
      spacing: spacing,
      topInset: topInset,
      line: line,
      leading: leading,
      trailing: trailing,
    );
    // A layout scheduled for after a frame can land after the host is gone.
    if (_disposed || key == _key) return;
    _key = key;
    _line = line;
    _offsets = FolderOutlineGeometry.sectionOffsets(
      counts: counts,
      columns: columns,
      cellExtent: cellExtent,
      headerExtent: headerExtent,
      spacing: spacing,
      topInset: topInset,
      leading: leading,
      trailing: trailing,
    );
    _onScroll();
  }

  /// The scroll offset that puts section [index]'s header at the top of the
  /// viewport, clamped to what the view can actually scroll to; `null` when
  /// there is no such section.
  double? targetOffsetOf(int index) {
    final controller = _controller;
    if (index < 0 || index >= _offsets.length) return null;
    var target = _offsets[index] - _line;
    if (controller != null && controller.hasClients) {
      final position = controller.position;
      target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    }
    return target;
  }

  /// Scrolls to section [index]. A zero [duration] jumps — the reduce-motion
  /// case, and the one a caller uses when the user wants to *be* there.
  ///
  /// The index is pinned to [index] for the duration, so the chips do not
  /// flicker through every section on the way. Once the scroll ends the
  /// position is read back as usual — a section too short to reach the line
  /// still lights whichever section the viewport actually landed in.
  Future<void> scrollTo(
    int index, {
    required Duration duration,
    Curve curve = Curves.easeInOut,
  }) async {
    final controller = _controller;
    final target = targetOffsetOf(index);
    if (controller == null || target == null || !controller.hasClients) return;
    if (duration == Duration.zero) {
      controller.jumpTo(target);
      return;
    }
    _locked = true;
    if (currentIndex.value != index) currentIndex.value = index;
    try {
      await controller.animateTo(target, duration: duration, curve: curve);
    } finally {
      _locked = false;
      _onScroll();
    }
  }

  void _onScroll() {
    if (_locked) return;
    final controller = _controller;
    final offset =
        controller != null && controller.hasClients ? controller.offset : 0.0;
    final next = FolderOutlineGeometry.sectionAt(_offsets, offset + _line);
    if (next != currentIndex.value) currentIndex.value = next;
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    detach();
    currentIndex.dispose();
  }
}

@immutable
class _LayoutKey {
  const _LayoutKey({
    required this.counts,
    required this.columns,
    required this.cellExtent,
    required this.headerExtent,
    required this.spacing,
    required this.topInset,
    required this.line,
    required this.leading,
    required this.trailing,
  });

  final List<int> counts;
  final int columns;
  final double cellExtent;
  final double headerExtent;
  final double spacing;
  final double topInset;
  final double line;
  final double? leading;
  final double? trailing;

  @override
  bool operator ==(Object other) =>
      other is _LayoutKey &&
      columns == other.columns &&
      cellExtent == other.cellExtent &&
      headerExtent == other.headerExtent &&
      spacing == other.spacing &&
      topInset == other.topInset &&
      line == other.line &&
      leading == other.leading &&
      trailing == other.trailing &&
      listEquals(counts, other.counts);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(counts),
        columns,
        cellExtent,
        headerExtent,
        spacing,
        topInset,
        line,
        leading,
        trailing,
      );
}
