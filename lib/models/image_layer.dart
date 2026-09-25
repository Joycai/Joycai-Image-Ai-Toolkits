/// Where a decomposed layer sits on its base image, in the base image's
/// pixels (docs/api/volcengine-ark.md §7: `bounding_box.absolute`, which is
/// measured against the *base* the model returned, not the input image).
class LayerBox {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const LayerBox(this.left, this.top, this.right, this.bottom);

  int get width => right - left;
  int get height => bottom - top;

  /// `[x0, y0, x1, y1]` → a box, or null for anything that is not four
  /// numbers describing a non-empty rectangle.
  static LayerBox? fromList(Object? raw) {
    if (raw is! List || raw.length != 4 || raw.any((v) => v is! num)) {
      return null;
    }
    final v = [for (final n in raw) (n as num).round()];
    if (v[2] <= v[0] || v[3] <= v[1]) return null;
    return LayerBox(v[0], v[1], v[2], v[3]);
  }

  @override
  bool operator ==(Object other) =>
      other is LayerBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => '[$left, $top, $right, $bottom]';
}

/// One saved file of a layer decomposition (`image_layers`): the base
/// (`zIndex` 0, no box) or a layer placed at [box].
class ImageLayer {
  final String path;

  /// Shared by every file one response produced.
  final String setId;
  final int zIndex;
  final String? name;
  final String? description;

  /// Null for the base, and for a layer upstream sent no box for (it is
  /// then drawn over the whole base).
  final LayerBox? box;

  const ImageLayer({
    required this.path,
    required this.setId,
    required this.zIndex,
    this.name,
    this.description,
    this.box,
  });

  bool get isBase => zIndex == 0;
}

/// Every saved file of one decomposition, bottom to top.
class ImageLayerSet {
  final String setId;

  /// Sorted by [ImageLayer.zIndex]: the base first when it survived.
  final List<ImageLayer> layers;

  ImageLayerSet(this.setId, Iterable<ImageLayer> layers)
    : layers = List.unmodifiable([...layers]..sort((a, b) => a.zIndex.compareTo(b.zIndex)));

  /// The base, or null when its file is gone.
  ImageLayer? get base => layers.isNotEmpty && layers.first.isBase ? layers.first : null;

  /// Everything above the base.
  List<ImageLayer> get overlays => [
    for (final l in layers)
      if (!l.isBase) l,
  ];
}
