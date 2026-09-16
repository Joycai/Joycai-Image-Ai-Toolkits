import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../services/catalogue/context_window_scale.dart';

/// The context window's Specify slider (`D1c · 1a`): nine equidistant stops
/// in two ranks, a magnet that pulls a drag onto a stop, and tick labels
/// that are buttons.
///
/// Major stops (8k · 32k · 96k · 256k · 1M) carry a 2×14 tick and a bold
/// 10px label; the minor ones between them a 2×10 tick and a 9px label in the
/// tertiary ink. Ticks up to the thumb take the accent. A drag that comes
/// within ±3% of the track of any stop lands on it ([ContextWindowScale.magnet]);
/// a tap on a label goes straight to that stop; arrow keys walk the stops and
/// ⇧-arrows only the major ones.
///
/// [value] is a track position in stop units, as [ContextWindowScale] hands it
/// out, so a typed figure that is no preset rests in proportion between two
/// stops. Not built on [ModelEditTrackSlider]: that one draws the reasoning
/// ladder's dots and single-rank labels, and every difference here — bars,
/// two label ranks, tappable labels, the magnet — is the point of this one.
class ContextWindowSlider extends StatefulWidget {
  const ContextWindowSlider({
    super.key,
    required this.value,
    required this.semanticLabel,
    required this.semanticValueOf,
    this.onChanged,
    this.inset = 20,
  });

  /// Where the thumb sits, `0` at 8k to `ContextWindowScale.maxPosition` at 1M.
  final double value;

  final String semanticLabel;

  /// How a position reads to assistive tech.
  final String Function(double position) semanticValueOf;

  /// Called with a track position: a whole stop after a magnet pull, a label
  /// tap or an arrow key, anything in between from a free drag.
  final ValueChanged<double>? onChanged;

  /// Room left of the first stop and right of the last, for their labels.
  final double inset;

  @override
  State<ContextWindowSlider> createState() => _ContextWindowSliderState();
}

class _ContextWindowSliderState extends State<ContextWindowSlider> {
  static const double _trackBand = 18;
  static const double _labelGap = 6;
  static const double _labelBand = 22;
  static const double _labelSlot = 64;

  bool _focused = false;

  double get _last => ContextWindowScale.maxPosition;
  int get _stopCount => ContextWindowScale.stops.length;

  void _emit(double v) {
    final next = v.clamp(0.0, _last);
    if (next != widget.value) widget.onChanged?.call(next);
  }

  /// A pointer at [dx]: the position under it, pulled onto a stop within reach.
  void _seek(double dx, double width) {
    final span = width - widget.inset * 2;
    if (span <= 0) return;
    _emit(ContextWindowScale.magnet((dx - widget.inset) / span * _last));
  }

  /// The stop an arrow lands on: the neighbour, from between two stops as
  /// well; with [majorOnly] the next major rung.
  double _neighbour(int direction, {bool majorOnly = false}) {
    const e = 1e-6;
    final v = widget.value;
    var i = direction > 0 ? (v + e).floor() + 1 : (v - e).ceil() - 1;
    while (majorOnly && i >= 0 && i < _stopCount && !ContextWindowScale.isMajor(i)) {
      i += direction;
    }
    return i.clamp(0, _stopCount - 1).toDouble();
  }

  void _step(int direction, {bool majorOnly = false}) =>
      _emit(_neighbour(direction, majorOnly: majorOnly));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.onChanged != null;
    final value = widget.value.clamp(0.0, _last);
    final onStop = (value - value.roundToDouble()).abs() < 1e-6 ? value.round() : null;
    final labelBase = theme.textTheme.labelSmall?.mono.copyWith(height: 1.2);

    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: widget.semanticValueOf(value),
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
          SingleActivator(LogicalKeyboardKey.arrowRight): _StopIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _StopIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _StopIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _StopIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): _StopIntent(1, majorOnly: true),
          SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): _StopIntent(1, majorOnly: true),
          SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): _StopIntent(-1, majorOnly: true),
          SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): _StopIntent(-1, majorOnly: true),
        },
        actions: {
          _StopIntent: CallbackAction<_StopIntent>(onInvoke: (intent) {
            _step(intent.direction, majorOnly: intent.majorOnly);
            return null;
          }),
        },
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final span = math.max(0.0, width - widget.inset * 2);
          double xOf(int stop) => widget.inset + stop / _last * span;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled ? (d) => _seek(d.localPosition.dx, width) : null,
                onHorizontalDragStart: enabled ? (d) => _seek(d.localPosition.dx, width) : null,
                onHorizontalDragUpdate: enabled ? (d) => _seek(d.localPosition.dx, width) : null,
                child: SizedBox(
                  height: _trackBand,
                  child: CustomPaint(
                    painter: _TieredTrackPainter(
                      value: value,
                      inset: widget.inset,
                      enabled: enabled,
                      focused: _focused && enabled,
                      track: scheme.outlineVariant,
                      majorTick: scheme.outline,
                      active: scheme.primary,
                      thumb: enabled ? scheme.primary : scheme.surfaceContainer,
                      thumbEdge: scheme.surface,
                      ring: scheme.accentRing,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _labelGap),
              SizedBox(
                height: _labelBand,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < _stopCount; i++)
                      Positioned(
                        left: xOf(i) - _labelSlot / 2,
                        width: _labelSlot,
                        top: 0,
                        height: _labelBand,
                        child: Center(
                          child: _TickLabel(
                            text: ContextWindowScale.label(ContextWindowScale.stops[i]),
                            major: ContextWindowScale.isMajor(i),
                            selected: enabled && onStop == i,
                            enabled: enabled,
                            style: labelBase,
                            onTap: enabled ? () => _emit(i.toDouble()) : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _StopIntent extends Intent {
  const _StopIntent(this.direction, {this.majorOnly = false});

  final int direction;
  final bool majorOnly;
}

/// One tick's label: a button (`1a` 「刻度标签本身是按钮」), 3/5 padding at r4,
/// the accent wash under the stop the thumb rests on.
class _TickLabel extends StatelessWidget {
  const _TickLabel({
    required this.text,
    required this.major,
    required this.selected,
    required this.enabled,
    required this.style,
    required this.onTap,
  });

  final String text;
  final bool major;
  final bool selected;
  final bool enabled;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.xs);
    final color = !enabled
        ? scheme.outline
        : selected
            ? scheme.onAccentTint
            : major
                ? scheme.onSurface
                : scheme.outline;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.accentTint : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: style?.copyWith(
                fontSize: major ? 10 : 9,
                fontWeight: selected || major ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The track: a 4px rail, filled to the thumb; a bar on every stop — 2×14 on
/// a major stop, 2×10 on a minor one — in the accent up to the thumb, the
/// tertiary ink (major) or the hairline (minor) beyond it; a 16px thumb with
/// the panel colour as its edge.
class _TieredTrackPainter extends CustomPainter {
  _TieredTrackPainter({
    required this.value,
    required this.inset,
    required this.enabled,
    required this.focused,
    required this.track,
    required this.majorTick,
    required this.active,
    required this.thumb,
    required this.thumbEdge,
    required this.ring,
  });

  final double value;
  final double inset;
  final bool enabled;
  final bool focused;
  final Color track;
  final Color majorTick;
  final Color active;
  final Color thumb;
  final Color thumbEdge;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final last = ContextWindowScale.maxPosition;
    final span = math.max(0.0, size.width - inset * 2);
    double xOf(double stop) => inset + stop / last * span;
    const cap = Radius.circular(2);

    canvas.drawRRect(RRect.fromLTRBR(inset, cy - 2, inset + span, cy + 2, cap), Paint()..color = track);
    final thumbX = xOf(value);
    if (enabled) {
      canvas.drawRRect(RRect.fromLTRBR(inset, cy - 2, thumbX, cy + 2, cap), Paint()..color = active);
    }
    for (var i = 0; i < ContextWindowScale.stops.length; i++) {
      final major = ContextWindowScale.isMajor(i);
      final reached = enabled && i <= value + 1e-9;
      final half = major ? 7.0 : 5.0;
      final x = xOf(i.toDouble());
      canvas.drawRRect(
        RRect.fromLTRBR(x - 1, cy - half, x + 1, cy + half, const Radius.circular(1)),
        Paint()..color = reached ? active : (major ? majorTick : track),
      );
    }

    final centre = Offset(thumbX, cy);
    if (focused) canvas.drawCircle(centre, 11, Paint()..color = ring);
    if (enabled) {
      canvas.drawCircle(
        centre.translate(0, 1),
        8,
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
    canvas.drawCircle(centre, 8, Paint()..color = thumbEdge);
    canvas.drawCircle(centre, 6, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(_TieredTrackPainter old) =>
      old.value != value ||
      old.inset != inset ||
      old.enabled != enabled ||
      old.focused != focused ||
      old.track != track ||
      old.majorTick != majorTick ||
      old.active != active ||
      old.thumb != thumb ||
      old.thumbEdge != thumbEdge ||
      old.ring != ring;
}

/// The field's trailing 「档位」 control: a divider, a label and a chevron on
/// the field's own height, opening a single-column menu of the nine stops
/// (`1a` second card).
///
/// Major stops get a 6px solid dot in the accent and the body size; minor
/// stops sit 12 further in with a 4px dot in the tertiary ink and the label
/// size. The exact token count runs down the right in mono; the selected row
/// takes the accent wash and a check.
class ContextWindowPresetMenu extends StatelessWidget {
  const ContextWindowPresetMenu({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.height,
  });

  /// The control's text (「档位」).
  final String label;

  /// The stop the value is on, or null between stops.
  final int? selected;
  final ValueChanged<int> onSelected;

  /// The field's height, so the divider spans it.
  final double height;

  static const double _menuWidth = 220;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final labelStyle = textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: scheme.onAccentTint);

    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpace.s4),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpace.s4)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control))),
      ),
      menuChildren: [
        for (var i = 0; i < ContextWindowScale.stops.length; i++)
          _presetRow(context, i, on: i == selected),
      ],
      builder: (context, controller, _) {
        final open = controller.isOpen;
        return Semantics(
          button: true,
          label: label,
          child: Material(
            color: open ? scheme.accentTint : Colors.transparent,
            // The field's own corner, so the open wash ends where the box does.
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppRadius.control)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => open ? controller.close() : controller.open(),
              child: Container(
                height: height,
                padding: const EdgeInsets.only(left: AppSpace.s10, right: 8),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: scheme.outlineVariant)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: labelStyle),
                    const SizedBox(width: AppSpace.s4),
                    Icon(open ? Icons.expand_less : Icons.expand_more, size: AppSize.iconMd, color: scheme.onAccentTint),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _presetRow(BuildContext context, int index, {required bool on}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final major = ContextWindowScale.isMajor(index);
    final tokens = ContextWindowScale.stops[index];
    final dotSize = major ? 6.0 : 4.0;
    final ink = on
        ? scheme.onAccentTint
        : major
            ? scheme.onSurface
            : scheme.onSurfaceVariant;

    return MenuItemButton(
      onPressed: () => onSelected(index),
      style: MenuItemButton.styleFrom(
        minimumSize: const Size(_menuWidth, AppSize.compact),
        maximumSize: const Size(_menuWidth, AppSize.compact),
        padding: EdgeInsets.only(left: major ? 8 : 20, right: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        backgroundColor: on ? scheme.accentTint : null,
      ),
      child: Row(
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(shape: BoxShape.circle, color: major ? scheme.primary : scheme.outline),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ContextWindowScale.label(tokens),
              style: (major ? textTheme.bodyMedium : textTheme.bodySmall)?.mono.copyWith(
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: ink,
              ),
            ),
          ),
          Text(
            _grouped(tokens),
            style: textTheme.labelSmall?.mono.copyWith(fontSize: 10, color: scheme.outline),
          ),
          if (on) ...[
            const SizedBox(width: AppSpace.s6),
            Icon(Icons.check, size: AppSize.iconSm, color: scheme.primary),
          ],
        ],
      ),
    );
  }

  /// `131,072` — the menu's right column, grouped the way the design sets it.
  static String _grouped(int tokens) {
    final digits = tokens.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
