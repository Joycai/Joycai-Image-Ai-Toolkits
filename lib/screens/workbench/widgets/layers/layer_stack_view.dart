import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../../../models/image_layer.dart';
import '../../../../widgets/ui/dashed_border.dart';

/// The layer canvas's picture (`A7 · 7a`): the base, and every visible
/// layer stretched into its box, in the base's pixel grid scaled to fit.
///
/// Coordinates are the base's pixels throughout — that is what
/// `bounding_box.absolute` is measured in — and the whole stack is scaled
/// once, so a layer can never drift from the base under zoom.
class LayerStackView extends StatelessWidget {
  const LayerStackView({
    super.key,
    required this.set,
    required this.baseSize,
    required this.hidden,
    required this.selected,
    required this.showBounds,
    required this.onSelect,
    required this.transformation,
    this.padding = EdgeInsets.zero,
  });

  final ImageLayerSet set;

  /// The base's pixel size: the canvas's coordinate system.
  final Size baseSize;

  /// Paths of the layers switched off.
  final Set<String> hidden;
  final String? selected;

  /// Draw a dashed outline round every unselected layer (`A7 · 7a` ④).
  final bool showBounds;

  /// A tap picks the topmost visible layer whose box holds the point, or
  /// clears the selection on empty ground.
  final ValueChanged<String?> onSelect;
  final TransformationController transformation;

  /// Room the picture must leave free — the phone's bottom sheet.
  final EdgeInsets padding;

  /// A layer's box in base pixels; a layer with none covers the base.
  Rect _boxOf(ImageLayer layer) {
    final b = layer.box;
    if (b == null) return Offset.zero & baseSize;
    return Rect.fromLTRB(
      b.left.toDouble(),
      b.top.toDouble(),
      b.right.toDouble(),
      b.bottom.toDouble(),
    );
  }

  String? _hit(Offset basePoint) {
    for (final layer in set.overlays.reversed) {
      if (hidden.contains(layer.path)) continue;
      if (_boxOf(layer).contains(basePoint)) return layer.path;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: CheckerboardPainter(
              light: scheme.surfaceContainerLow,
              dark: scheme.surfaceContainerHigh,
            ),
          ),
        ),
        Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // A little air round the picture at rest, as the design draws it.
              final scale =
                  0.92 *
                  math.min(
                    constraints.maxWidth / baseSize.width,
                    constraints.maxHeight / baseSize.height,
                  );
              final size = baseSize * scale;
              return InteractiveViewer(
                transformationController: transformation,
                minScale: 0.5,
                maxScale: 16,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                // The ground round the picture is empty ground too: a tap on
                // it clears the pick (`A7 · 7a` ③). The picture's own
                // detector wins inside it.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(null),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => onSelect(_hit(d.localPosition / scale)),
                        child: SizedBox.fromSize(
                          size: size,
                          child: _stack(context, scheme, scale),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _stack(BuildContext context, ColorScheme scheme, double scale) {
    Rect onScreen(ImageLayer l) {
      final r = _boxOf(l);
      return Rect.fromLTWH(
        r.left * scale,
        r.top * scale,
        r.width * scale,
        r.height * scale,
      );
    }

    final base = set.base;
    ImageLayer? chosen;
    for (final l in set.overlays) {
      if (l.path == selected) chosen = l;
    }
    final showBase = base != null && !hidden.contains(base.path);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Lifts the picture off the ground; only under an opaque base — a
        // shadow is a filled shape and would show through a transparent one.
        if (showBase)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
        if (showBase)
          Positioned.fill(
            child: Image.file(
              File(base.path),
              key: ValueKey(base.path),
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          ),
        for (final layer in set.overlays)
          if (!hidden.contains(layer.path))
            Positioned.fromRect(
              rect: onScreen(layer),
              child: Image.file(
                File(layer.path),
                key: ValueKey(layer.path),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
        if (showBounds)
          for (final layer in set.overlays)
            if (!hidden.contains(layer.path) && layer.path != selected)
              Positioned.fromRect(
                rect: onScreen(layer),
                child: IgnorePointer(
                  child: DashedBorder(
                    color: scheme.accentRule,
                    radius: 0,
                    strokeWidth: 1,
                  ),
                ),
              ),
        if (chosen != null && !hidden.contains(chosen.path))
          Positioned.fromRect(
            rect: onScreen(chosen),
            child: IgnorePointer(child: _Selection(label: chosen.name)),
          ),
      ],
    );
  }
}

/// The selected layer's outline and name tag (`A7 · 7a` ③): a 1.5px accent
/// stroke with a 3px ring, the name on an accent plate above the top-left
/// corner.
class _Selection extends StatelessWidget {
  const _Selection({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Two strokes, not a BoxShadow: a shadow is a filled shape, and it
        // would wash the very layer being pointed at.
        Positioned.fill(
          left: -3,
          top: -3,
          right: -3,
          bottom: -3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.accentRing, width: 3),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.primary, width: 1.5),
            ),
          ),
        ),
        if (label != null)
          Positioned(
            left: -1,
            top: -20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.xs),
                  topRight: Radius.circular(AppRadius.xs),
                  bottomRight: Radius.circular(AppRadius.xs),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  label!,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                    height: AppType.tightHeight,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The transparency ground (`A7`: card / column in 16px squares).
class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({
    required this.light,
    required this.dark,
    this.cell = 16,
  });

  final Color light;
  final Color dark;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final paint = Paint()..color = dark;
    final path = Path();
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 0 : 1; x * cell < size.width; x += 2) {
        path.addRect(Rect.fromLTWH(x * cell, y * cell, cell, cell));
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CheckerboardPainter old) =>
      old.light != light || old.dark != dark || old.cell != cell;
}
