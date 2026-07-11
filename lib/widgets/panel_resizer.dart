import 'package:flutter/material.dart';

/// Draggable divider between two panels. A hairline with a centered pill grip
/// so the affordance is visible at rest; the whole 9px-wide strip (not just
/// the grip) accepts the drag.
///
/// [axis] is the drag direction: [Axis.horizontal] (default) is a vertical
/// divider between side-by-side panels, [Axis.vertical] a horizontal divider
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

    final hairlineColor = active
        ? colorScheme.primary.withAlpha(120)
        : Theme.of(context).dividerColor;
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
          width: _isHorizontalDrag ? 9 : null,
          height: _isHorizontalDrag ? null : 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: _isHorizontalDrag ? 1 : null,
                    height: _isHorizontalDrag ? null : 1,
                    color: hairlineColor,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: _isHorizontalDrag ? gripThickness : 40,
                height: _isHorizontalDrag ? 40 : gripThickness,
                decoration: BoxDecoration(
                  color: gripColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
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
