import 'package:flutter/material.dart';

/// Fades a scrollable's content out where it runs under fixed chrome, instead
/// of cutting it off square.
///
/// A scroll view pinned under a toolbar or above a footer ends at a hard line:
/// whatever row happens to be at the boundary is sliced through its middle. A
/// half-drawn input or a card cropped at its rounded corner does not read as
/// "there is more below" — it reads as a rendering fault, which is what the
/// workbench config panel looked like above its Process button.
///
/// A divider is the usual fix and it is the wrong one here. It states that two
/// regions are separate, which is true of a heading and its body but not of a
/// list and the space it is scrolling through — and it still leaves the row
/// under it cut in half. The edge that says "continues" is a soft one.
///
/// The fade appears only on the side that actually has content beyond it. A
/// permanent gradient over a list short enough to fit would dim its last row
/// for no reason, which is the same mistake in the other direction.
///
/// Costs one `saveLayer` while the fade is showing, so this belongs on panels
/// and lists rather than around whole screens.
class ScrollEdgeFade extends StatefulWidget {
  /// The scrollable to fade. Its own scroll notifications drive the fade, so
  /// it needs no controller and may be any depth below this.
  final Widget child;

  /// How much of the edge the fade covers.
  ///
  /// Deep enough that a line of text passes through several steps of alpha on
  /// its way out — at much less than this the gradient reads as a blurry
  /// divider rather than as a fade.
  final double extent;

  final Axis axis;

  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.extent = 24,
    this.axis = Axis.vertical,
  });

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  /// Start with both edges hard. Anything else would flash a fade over a list
  /// that turns out to fit, on the frame before the first metrics arrive.
  bool _atStart = true;
  bool _atEnd = true;

  bool _update(ScrollMetrics metrics) {
    if (metrics.axis != widget.axis) return false;
    // Half a pixel, not zero: a fling settles on a fractional offset, and an
    // exact comparison leaves the fade on at a boundary the user has reached.
    final atStart = metrics.extentBefore <= 0.5;
    final atEnd = metrics.extentAfter <= 0.5;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;

    // Both notifications are needed. ScrollNotification covers scrolling;
    // ScrollMetricsNotification covers the content or the viewport changing
    // size underneath a stationary scroll position — a card expanding, the
    // window resizing — which is exactly when an edge stops or starts having
    // anything beyond it.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _update(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _update(n.metrics),
        child: _atStart && _atEnd
            // Nothing to fade: hand back the child untouched rather than a
            // fully-opaque mask, so a list that fits pays no saveLayer at all.
            ? widget.child
            : ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final span = vertical ? bounds.height : bounds.width;
                  // A fade taller than half the viewport would meet itself in
                  // the middle and dim the content the panel is there to show.
                  final fade = (widget.extent / span).clamp(0.0, 0.5);
                  return LinearGradient(
                    begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
                    end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
                    colors: [
                      _atStart ? Colors.white : Colors.transparent,
                      Colors.white,
                      Colors.white,
                      _atEnd ? Colors.white : Colors.transparent,
                    ],
                    stops: [0, fade, 1 - fade, 1],
                  ).createShader(bounds);
                },
                child: widget.child,
              ),
      ),
    );
  }
}
