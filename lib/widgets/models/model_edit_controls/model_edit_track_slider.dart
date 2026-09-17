import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';

/// `D1c`'s slider, for reasoning effort and the context window: a 4px track
/// at r999, a 6px dot on every stop, a 16px thumb, and a mono label under a
/// stop.
///
/// Stops sit at equal distances and [value] is in stop units, so a discrete
/// ladder snaps to whole stops while a scale like the context window rests
/// anywhere between two. Drawn here rather than themed onto Material's
/// [Slider]: the dots have to sit exactly over their labels, and [Slider]
/// places its thumb inside a track it insets by the overlay radius and by the
/// track's own rounding.
class ModelEditTrackSlider extends StatefulWidget {
  const ModelEditTrackSlider({
    super.key,
    required this.stopCount,
    required this.value,
    required this.labels,
    required this.semanticLabel,
    required this.semanticValueOf,
    this.onChanged,
    this.snap = false,
    this.highlight,
    this.inset = 24,
  });

  final int stopCount;

  /// Where the thumb sits, from 0 at the first stop to `stopCount - 1`.
  final double value;

  /// One per stop; null leaves that stop unlabelled.
  final List<String?> labels;

  final String semanticLabel;

  /// How a position reads to assistive tech. Asked for the current value and
  /// for where an increase or a decrease would land, so it is never empty.
  final String Function(double value) semanticValueOf;

  /// Null greys the control out. The thumb still sits at [value].
  final ValueChanged<double>? onChanged;

  /// Whether a drag lands only on whole stops.
  final bool snap;

  /// The stop whose label is set in the full ink.
  final int? highlight;

  /// Room left of the first stop and right of the last, for their labels.
  final double inset;

  @override
  State<ModelEditTrackSlider> createState() => _ModelEditTrackSliderState();
}

class _ModelEditTrackSliderState extends State<ModelEditTrackSlider> {
  static const double _trackBand = 18;
  static const double _labelGap = 4;
  static const double _labelBand = 13;
  static const double _labelSlot = 80;

  bool _focused = false;

  double get _last => (widget.stopCount - 1).toDouble();

  void _emit(double v) {
    final next = (widget.snap ? v.roundToDouble() : v).clamp(0.0, _last);
    if (next != widget.value) widget.onChanged?.call(next);
  }

  void _seek(double dx, double width) {
    final span = width - widget.inset * 2;
    if (span <= 0) return;
    _emit((dx - widget.inset) / span * _last);
  }

  /// Where an arrow key, or an assistive increase or decrease, lands: the
  /// neighbouring stop, from between two stops as well.
  double _neighbour(int direction) {
    const e = 1e-6;
    final v = widget.value;
    final next = direction > 0 ? (v + e).floorToDouble() + 1 : (v - e).ceilToDouble() - 1;
    return next.clamp(0.0, _last);
  }

  void _step(int direction) => _emit(_neighbour(direction));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.onChanged != null;
    final labelStyle = theme.textTheme.labelSmall?.mono.copyWith(fontSize: 10, height: 1.2);

    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: widget.semanticValueOf(widget.value.clamp(0.0, _last)),
      // A node that can be increased or decreased has to say what it would
      // read afterwards; the framework asserts on one without the other.
      increasedValue: enabled ? widget.semanticValueOf(_neighbour(1)) : null,
      decreasedValue: enabled ? widget.semanticValueOf(_neighbour(-1)) : null,
      enabled: enabled,
      onIncrease: enabled ? () => _step(1) : null,
      onDecrease: enabled ? () => _step(-1) : null,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowRight): _TrackStepIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _TrackStepIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _TrackStepIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _TrackStepIntent(-1),
        },
        actions: {
          _TrackStepIntent: CallbackAction<_TrackStepIntent>(onInvoke: (intent) {
            _step(intent.direction);
            return null;
          }),
        },
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final span = math.max(0.0, width - widget.inset * 2);
          double xOf(int stop) => widget.inset + (_last == 0 ? 0 : stop / _last * span);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (d) => _seek(d.localPosition.dx, width) : null,
            onHorizontalDragStart: enabled ? (d) => _seek(d.localPosition.dx, width) : null,
            onHorizontalDragUpdate: enabled ? (d) => _seek(d.localPosition.dx, width) : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _trackBand,
                  child: CustomPaint(
                    painter: _TrackPainter(
                      stopCount: widget.stopCount,
                      value: widget.value.clamp(0.0, _last),
                      inset: widget.inset,
                      enabled: enabled,
                      focused: _focused && enabled,
                      track: scheme.outlineVariant,
                      active: scheme.primary,
                      thumb: enabled ? scheme.primary : scheme.surfaceContainer,
                      thumbEdge: enabled ? scheme.surface : scheme.outlineVariant,
                      ring: scheme.accentRing,
                    ),
                  ),
                ),
                const SizedBox(height: _labelGap),
                SizedBox(
                  height: _labelBand,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < widget.stopCount; i++)
                        if (widget.labels[i] != null)
                          Positioned(
                            left: xOf(i) - _labelSlot / 2,
                            width: _labelSlot,
                            top: 0,
                            child: Text(
                              widget.labels[i]!,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: labelStyle?.copyWith(
                                color: !enabled
                                    ? scheme.outline
                                    : i == widget.highlight
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                fontWeight:
                                    enabled && i == widget.highlight ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _TrackStepIntent extends Intent {
  const _TrackStepIntent(this.direction);

  final int direction;
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.stopCount,
    required this.value,
    required this.inset,
    required this.enabled,
    required this.focused,
    required this.track,
    required this.active,
    required this.thumb,
    required this.thumbEdge,
    required this.ring,
  });

  final int stopCount;
  final double value;
  final double inset;
  final bool enabled;
  final bool focused;
  final Color track;
  final Color active;
  final Color thumb;
  final Color thumbEdge;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final last = (stopCount - 1).toDouble();
    final span = math.max(0.0, size.width - inset * 2);
    double xOf(double stop) => inset + (last == 0 ? 0 : stop / last * span);
    const cap = Radius.circular(2);

    canvas.drawRRect(RRect.fromLTRBR(inset, cy - 2, inset + span, cy + 2, cap), Paint()..color = track);
    final thumbX = xOf(value);
    // Greyed, the track keeps no fill: nothing chosen here would be sent.
    if (enabled) {
      canvas.drawRRect(RRect.fromLTRBR(inset, cy - 2, thumbX, cy + 2, cap), Paint()..color = active);
    }
    for (var i = 0; i < stopCount; i++) {
      final reached = enabled && i <= value + 1e-9;
      canvas.drawCircle(Offset(xOf(i.toDouble()), cy), 3, Paint()..color = reached ? active : track);
    }

    final centre = Offset(thumbX, cy);
    if (focused) canvas.drawCircle(centre, 11, Paint()..color = ring);
    if (enabled) {
      canvas.drawCircle(
        centre.translate(0, 1),
        8,
        Paint()
          ..color = const Color(0x59000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
    canvas.drawCircle(centre, 8, Paint()..color = thumbEdge);
    canvas.drawCircle(centre, 6, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.stopCount != stopCount ||
      old.value != value ||
      old.inset != inset ||
      old.enabled != enabled ||
      old.focused != focused ||
      old.track != track ||
      old.active != active ||
      old.thumb != thumb ||
      old.thumbEdge != thumbEdge ||
      old.ring != ring;
}
