import 'package:flutter/material.dart';

/// Height of the header row that lives inside the top of a [PanelCard].
///
/// Tabs drawn in a header have to fill it exactly for their indicator to land
/// on the header's bottom border, so the number is shared rather than repeated.
const double kPanelHeaderHeight = 56;

/// Draggable gutter between two panel cards. No divider line — the boundary
/// is formed by the canvas color showing through the 14px gap; only a pill
/// grip floats in the middle. The whole strip accepts the drag.
///
/// [axis] is the drag direction: [Axis.horizontal] (default) is a vertical
/// gutter between side-by-side panels, [Axis.vertical] a horizontal gutter
/// between stacked panels (e.g. the bottom console).
class PanelResizer extends StatefulWidget {
  /// Called with the drag delta along [axis] (dx when horizontal, dy when
  /// vertical; positive = pointer moved right/down).
  final void Function(double delta) onDrag;

  /// Called when the drag ends — the moment to persist the final size.
  final VoidCallback? onDragEnd;

  final Axis axis;

  const PanelResizer({
    super.key,
    required this.onDrag,
    this.onDragEnd,
    this.axis = Axis.horizontal,
  });

  @override
  State<PanelResizer> createState() => _PanelResizerState();
}

class _PanelResizerState extends State<PanelResizer> {
  bool _hovering = false;
  bool _dragging = false;

  bool get _isHorizontalDrag => widget.axis == Axis.horizontal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _hovering || _dragging;

    final gripColor = active ? colorScheme.primary : colorScheme.outlineVariant;
    final gripThickness = active ? 5.0 : 4.0;

    return MouseRegion(
      cursor: _isHorizontalDrag ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _isHorizontalDrag ? (_) => setState(() => _dragging = true) : null,
        onHorizontalDragUpdate: _isHorizontalDrag ? (d) => widget.onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: _isHorizontalDrag ? (_) => _endDrag() : null,
        onHorizontalDragCancel: _isHorizontalDrag ? () => setState(() => _dragging = false) : null,
        onVerticalDragStart: _isHorizontalDrag ? null : (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: _isHorizontalDrag ? null : (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: _isHorizontalDrag ? null : (_) => _endDrag(),
        onVerticalDragCancel: _isHorizontalDrag ? null : () => setState(() => _dragging = false),
        child: SizedBox(
          width: _isHorizontalDrag ? 14 : null,
          height: _isHorizontalDrag ? null : 14,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _isHorizontalDrag ? gripThickness : 40,
              height: _isHorizontalDrag ? 40 : gripThickness,
              decoration: BoxDecoration(
                color: gripColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _endDrag() {
    setState(() => _dragging = false);
    widget.onDragEnd?.call();
  }
}

/// Rounded surface card hosting one panel of an inset layout. Pairs with
/// [PanelResizer]: cards sit on a `surfaceContainer` canvas, separated by
/// resizer gutters instead of divider lines.
class PanelCard extends StatelessWidget {
  final Widget child;
  final double? width;

  const PanelCard({super.key, required this.child, this.width});

  @override
  Widget build(BuildContext context) {
    // Material (not a decorated Container) so descendant ListTiles/InkWells
    // paint their ink and selected tints on the card surface.
    return SizedBox(
      width: width,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
