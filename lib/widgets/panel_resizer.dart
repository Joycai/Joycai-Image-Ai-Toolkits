import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// Height of the header row that lives inside the top of a [PanelCard].
///
/// Tabs drawn in a header have to fill it exactly for their indicator to land
/// on the header's bottom border, so the number is shared rather than repeated.
const double kPanelHeaderHeight = 56;

/// The shape a [PanelCard] and its neighbouring [PanelResizer] take.
///
/// The design spec draws both, on different screens, and they are not
/// interchangeable — each brings its own resizer treatment with it.
enum PanelShape {
  /// Edge-to-edge column separated from the next by a hairline. What the spec
  /// draws on the dense tool screens: `A1`'s three workbench columns are
  /// `#FAFBFF` with `1px solid #E8ECF7` between them, no radius and no gap.
  ///
  /// This reverses the inset-card layout the app shipped from v3.13, which was
  /// chosen precisely because hard divider lines read as harsh. The spec asks
  /// for them back on the tool screens and keeps cards on `D1` 设置; both are
  /// hand-finished frames, so the split is deliberate rather than an oversight.
  column,

  /// Rounded card floating on the canvas, separated by a gutter. What the spec
  /// still draws on `D1` 设置 — radius 12 on a `#EBEEF7` ground.
  card,
}

/// Which side of a [PanelResizer] strip its rule sits on: [leading] is left of
/// the ground when the resizer's axis is horizontal and above it when vertical,
/// [trailing] is right of it or below it.
enum PanelRuleSide { leading, trailing }

/// Draggable boundary between two panels. What it paints depends on [shape]:
/// a [PanelShape.column] boundary is a hairline the columns butt against, a
/// [PanelShape.card] one is an empty gutter with a pill grip floating in it.
/// Either way the whole strip accepts the drag, so the target stays
/// comfortable even where the line is one pixel.
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

  final PanelShape shape;

  /// What the strip paints either side of the rule — [PanelShape.column] only,
  /// since a card gutter is bare canvas by definition.
  ///
  /// Defaults to the ground every column [PanelCard] paints, which is the
  /// colour of the panel the rule belongs to on every boundary in the app.
  final Color? ground;

  /// Which edge of the strip the rule sits against.
  ///
  /// The rule belongs to a panel, not to the gap between two: the spec draws
  /// it as that column's `border-right` / `border-left` / `border-top`, with
  /// the next column starting on the very next pixel. Pushing it to the edge
  /// is what lets the rest of the strip take one flat [ground] and still meet
  /// the far neighbour cleanly *at every height* — which a strip split down
  /// the middle cannot do when that neighbour changes colour partway down, as
  /// the assistant's chat column does under its header.
  final PanelRuleSide ruleSide;

  const PanelResizer({
    super.key,
    required this.onDrag,
    this.onDragEnd,
    this.axis = Axis.horizontal,
    this.shape = PanelShape.card,
    this.ground,
    this.ruleSide = PanelRuleSide.trailing,
  });

  /// A card gutter is empty canvas, so it has to be wide enough to read as a
  /// deliberate separation rather than a misalignment.
  static const double kCardGutter = 14;

  /// A column boundary is a hairline, so this is a hit target, not a gap: the
  /// spec runs two columns flush and puts a single 1px rule between them, and
  /// [PanelShape.column] panels draw no border of their own because this rule
  /// is the only one — two would show as a double.
  ///
  /// The 8px beside the rule is painted *here*, by [ground]. It cannot be
  /// painted by the panels: this strip is their sibling in the row and
  /// [thicknessOf] takes its width out of the row, so while it was bare the
  /// window backdrop came through as an 8px band down every column boundary
  /// in the app.
  static const double kColumnGutter = 9;

  /// How much room the strip takes out of the row, by shape.
  ///
  /// Layout code has to agree with this or the panels it sizes will not add up
  /// to the row — see `_WorkbenchLayoutState._resolvePanels`.
  static double thicknessOf(PanelShape shape) =>
      shape == PanelShape.column ? kColumnGutter : kCardGutter;

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
    final isColumn = widget.shape == PanelShape.column;

    // A column boundary is a full-length rule that lights up; a card gutter is
    // a short grip that thickens. The same two states, drawn to suit the shape.
    //
    // At rest the rule is `surfaceContainerHigh`, not `outlineVariant`. The
    // spec draws this edge (#E8ECF7) a step softer than the ones inside a
    // panel (#DBE0EF), and on the ramp that step is exactly this role. It is
    // also the whole reason the card layout was adopted in the first place:
    // a full-height rule at divider strength is what reads as harsh.
    final gripColor = active
        ? colorScheme.primary
        : (isColumn ? colorScheme.surfaceContainerHigh : colorScheme.outlineVariant);
    final gripThickness = isColumn ? (active ? 2.0 : 1.0) : (active ? 5.0 : 4.0);
    final gripLength = isColumn ? double.infinity : 40.0;
    final thickness = PanelResizer.thicknessOf(widget.shape);

    final grip = AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.enter,
      width: _isHorizontalDrag ? gripThickness : gripLength,
      height: _isHorizontalDrag ? gripLength : gripThickness,
      decoration: BoxDecoration(
        color: gripColor,
        // Square at one pixel. A radius on a hairline rounds nothing
        // and only smears its ends.
        borderRadius: isColumn ? null : BorderRadius.circular(3),
      ),
    );

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
          width: _isHorizontalDrag ? thickness : null,
          height: _isHorizontalDrag ? null : thickness,
          // A card gutter is canvas the grip floats in; a column boundary is
          // two panel grounds meeting at a rule, so it has to carry them.
          child: isColumn
              ? Flex(
                  direction: widget.axis,
                  // Stretch, not the default centre: a [ColoredBox] with no
                  // child takes `constraints.smallest`, so under the loose
                  // cross-axis constraint a centred row hands out the ground
                  // would size to zero and paint nothing at all.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.ruleSide == PanelRuleSide.leading) grip,
                    Expanded(
                      child: ColoredBox(
                        color: widget.ground ?? colorScheme.surfaceContainerLow,
                      ),
                    ),
                    if (widget.ruleSide == PanelRuleSide.trailing) grip,
                  ],
                )
              : Center(child: grip),
        ),
      ),
    );
  }

  void _endDrag() {
    setState(() => _dragging = false);
    widget.onDragEnd?.call();
  }
}

/// One panel of a multi-column layout. Pairs with [PanelResizer], which has to
/// be given the same [shape] — the two together are what makes a boundary read
/// as a hairline or as a gutter.
///
/// [PanelShape.column] panels are flush and carry no border: the hairline
/// between two of them belongs to the resizer, and a panel drawing its own
/// edge as well would double it.
class PanelCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final PanelShape shape;

  /// The ground this panel paints, overriding the default for its [shape].
  ///
  /// [Colors.transparent] paints nothing at all and lets whatever the screen
  /// puts behind the row show through — what the workbench's gallery column
  /// wants, which the spec draws as bare image cards over the window's own
  /// backdrop while the two side columns stay opaque.
  ///
  /// A colour is for a centre column the spec gives a ground of its own: `10g`
  /// draws the prompt assistant's chat column `#F5F7FD`, one step below the
  /// `#FAFBFF` panels either side of it, so the conversation reads as a recess
  /// between them rather than as more backdrop.
  final Color? ground;

  const PanelCard({
    super.key,
    required this.child,
    this.width,
    this.shape = PanelShape.card,
    this.ground,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isColumn = shape == PanelShape.column;

    // Material (not a decorated Container) so descendant ListTiles/InkWells
    // paint their ink and selected tints on the panel surface.
    return SizedBox(
      width: width,
      child: Material(
        // A column is the spec's #FAFBFF, a step brighter than a card's
        // surface: with no radius and no gutter separating it from the canvas,
        // lightness is the only thing left to lift it.
        color: ground ??
            (isColumn ? colorScheme.surfaceContainerLow : colorScheme.surface),
        borderRadius: isColumn ? null : BorderRadius.circular(AppRadius.lg),
        clipBehavior: isColumn ? Clip.none : Clip.antiAlias,
        child: child,
      ),
    );
  }
}
