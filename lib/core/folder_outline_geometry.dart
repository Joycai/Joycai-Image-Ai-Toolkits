import 'dart:math' as math;

/// Where each folder section of a grouped grid starts, computed rather than
/// measured.
///
/// The gallery and the file browser both lay their files out in sections —
/// one header row and one grid (or one run of fixed-height list rows) per
/// folder — and neither has a cell whose height is not fixed by the width.
/// So the scroll offset of any section header is arithmetic, which is what
/// a folder outline needs: `Scrollable.ensureVisible` cannot reach a header
/// whose sliver is outside the viewport, because that sliver was never built.
///
/// [columnsFor] and [cellExtentFor] replicate what
/// `SliverGridDelegateWithMaxCrossAxisExtent` does with the same inputs, so
/// the table agrees with the layout to the pixel. A widget test pins that.
abstract final class FolderOutlineGeometry {
  /// How many columns `SliverGridDelegateWithMaxCrossAxisExtent` makes of
  /// [crossAxisExtent] for a [maxCrossAxisExtent] tile and [spacing] gutter.
  static int columnsFor({
    required double crossAxisExtent,
    required double maxCrossAxisExtent,
    required double spacing,
  }) {
    if (crossAxisExtent <= 0) return 1;
    return math.max(1, (crossAxisExtent / (maxCrossAxisExtent + spacing)).ceil());
  }

  /// The width one tile actually gets for [columns] columns — the delegate's
  /// `childCrossAxisExtent`.
  static double cellExtentFor({
    required double crossAxisExtent,
    required int columns,
    required double spacing,
  }) {
    final usable = math.max(0.0, crossAxisExtent - spacing * (columns - 1));
    return usable / columns;
  }

  /// The scroll offset at which each section's header starts.
  ///
  /// A section is laid out as: a header of [headerExtent], then [leading],
  /// then `rows` cells of [cellExtent] separated by [spacing], then
  /// [trailing]. [leading] and [trailing] default to [spacing], which is what
  /// a `SliverPadding(EdgeInsets.all(gap))` around the grid gives. A list is
  /// the same shape with one column and no spacing.
  ///
  /// [topInset] is whatever scrolls before the first header — the toolbar
  /// clearance the gallery leaves, for one.
  static List<double> sectionOffsets({
    required List<int> counts,
    required int columns,
    required double cellExtent,
    required double headerExtent,
    required double spacing,
    double topInset = 0,
    double? leading,
    double? trailing,
  }) {
    assert(columns >= 1);
    final lead = leading ?? spacing;
    final trail = trailing ?? spacing;
    final offsets = List<double>.filled(counts.length, 0);
    var cursor = topInset;
    for (var i = 0; i < counts.length; i++) {
      offsets[i] = cursor;
      final rows = (counts[i] / columns).ceil();
      final body = rows == 0 ? 0.0 : rows * cellExtent + (rows - 1) * spacing;
      cursor += headerExtent + lead + body + trail;
    }
    return offsets;
  }

  /// The section whose header has crossed the top of a viewport scrolled to
  /// [scrollOffset]: the last entry of [offsets] at or above it, with a
  /// [tolerance] so a header the scroll landed on by animation, half a pixel
  /// short, still counts as reached.
  ///
  /// `0` before the first header; `-1` only when there are no sections.
  static int sectionAt(List<double> offsets, double scrollOffset, {double tolerance = 0.5}) {
    if (offsets.isEmpty) return -1;
    final target = scrollOffset + tolerance;
    var lo = 0;
    var hi = offsets.length - 1;
    var found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (offsets[mid] <= target) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}
