import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../dashed_border.dart';

/// `00d · 1a / 1b` 「空位即落点」: the drop indicator of a reorderable list,
/// drawn inside the gap the framework opens for the dragged item.
///
/// [ReorderableListView] already makes that gap — it keeps an empty box in the
/// dragged item's old slot and slides the items between that slot and the
/// pointer by one extent — but offers no hook to draw in it. So this host
/// finds it. Every item goes through [AppReorderGapController.item], which
/// wraps it in a probe reporting where the item is painted and how far the
/// list has slid it; on each frame of a drag, whatever part of the items'
/// slots no item covers is the gap, painted as `--tint`, a 1px dashed accent
/// edge at r10, and 「放到第 3 位」. While the list animates, the gap that is
/// closing and the one that is opening are both painted at their current size
/// — the design's 「空位开合」.
///
/// After a drop that moved something, the item in its new place carries a 1px
/// `--ring` edge for 600ms (1.2s when the platform asks for less motion), and
/// the new position is announced.
///
/// Near a scrollable list's edge the host also shows the edge-scroll hint
/// (`1f` ③): a 48 band washed with the accent and a capsule saying 「继续拖动以
/// 滚动」.
class AppReorderGap extends StatefulWidget {
  const AppReorderGap({
    super.key,
    required this.itemCount,
    required this.builder,
    this.axis = Axis.vertical,
    this.slotPadding = EdgeInsets.zero,
    this.touch = false,
    this.showLabel = true,
  });

  final int itemCount;

  /// Builds the reorderable list, taking its callbacks and item wrapper from
  /// the controller.
  final Widget Function(BuildContext context, AppReorderGapController gap) builder;

  final Axis axis;

  /// Space inside each item that is not the item — the gap below a card, the
  /// margin after a thumbnail. The indicator and the confirmation ring are
  /// inset by it, so they match the card rather than its slot.
  final EdgeInsets slotPadding;

  /// A touch list: a selection click each time the drop position changes
  /// (`1f` 触觉), and the phone's 12/500 label.
  final bool touch;

  /// Whether the gap says where the drop lands. Off for slots too small to
  /// carry a line.
  final bool showLabel;

  @override
  State<AppReorderGap> createState() => _AppReorderGapState();
}

/// What a reorderable list takes from [AppReorderGap].
class AppReorderGapController {
  AppReorderGapController._(this._state);

  final _AppReorderGapState _state;

  /// The gap rects painted on the last frame, in the host's coordinates.
  @visibleForTesting
  List<Rect> get debugGaps => _state._frame.value.gaps;

  /// The drop-position line painted on the last frame.
  @visibleForTesting
  String? get debugLabel => _state._frame.value.label;

  /// Whether the confirmation ring is showing.
  @visibleForTesting
  bool get debugConfirming => _state._frame.value.confirm != null;

  /// Wraps one list item. The returned widget carries [key], as the list
  /// requires of what its item builder returns.
  Widget item({required Key key, required int index, required Widget child}) =>
      KeyedSubtree(key: key, child: _GapProbe(state: _state, index: index, child: child));

  /// The list's `onReorderStart`, calling [then] after the host has noted the
  /// drag.
  void Function(int index) onReorderStart([void Function(int index)? then]) => (index) {
        _state._begin(index);
        then?.call(index);
      };

  /// The list's `onReorderItem`, calling [then] first and then confirming the
  /// drop.
  void Function(int oldIndex, int newIndex) onReorderItem(void Function(int oldIndex, int newIndex) then) =>
      (oldIndex, newIndex) {
        then(oldIndex, newIndex);
        _state._dropped(oldIndex, newIndex);
      };
}

class _Geometry {
  const _Geometry(this.index, this.rect, this.shift);

  final int index;

  /// Where the item is painted, in the host's coordinates.
  final Rect rect;

  /// How far the list has slid it along the main axis.
  final double shift;
}

class _GapFrame {
  const _GapFrame({
    this.gaps = const [],
    this.labelRect,
    this.label,
    this.confirm,
    this.confirmOpacity = 0,
  });

  final List<Rect> gaps;
  final Rect? labelRect;
  final String? label;
  final Rect? confirm;
  final double confirmOpacity;

  bool get isEmpty => gaps.isEmpty && confirm == null;
}

enum _EdgeHint { none, start, end }

class _AppReorderGapState extends State<AppReorderGap> with SingleTickerProviderStateMixin {
  static const double _edgeBand = 48;

  late final AppReorderGapController _controller = AppReorderGapController._(this);
  late final Ticker _ticker = createTicker(_tick);

  /// Every attached probe. Not keyed by index: while an item is lifted the
  /// list builds its child a second time in the overlay for the proxy, and
  /// that copy carries the same index as the slot it left.
  final Set<_RenderGapProbe> _probes = {};
  final Map<int, double> _extents = {};
  final ValueNotifier<_GapFrame> _frame = ValueNotifier(const _GapFrame());
  final ValueNotifier<_EdgeHint> _edge = ValueNotifier(_EdgeHint.none);

  int? _dragIndex;
  double _extent = 0;
  bool _placeholderSeen = false;
  int? _target;

  int? _confirmIndex;
  Duration? _confirmStart;
  Duration _elapsed = Duration.zero;

  Offset? _pointer;
  ScrollMetrics? _metrics;

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _edge.dispose();
    super.dispose();
  }

  void _register(_RenderGapProbe probe) => _probes.add(probe);

  void _unregister(_RenderGapProbe probe) => _probes.remove(probe);

  void _measured(int index, Size size) {
    _extents[index] = widget.axis == Axis.vertical ? size.height : size.width;
  }

  void _begin(int index) {
    _dragIndex = index;
    _extent = _extents[index] ?? 0;
    _placeholderSeen = false;
    _target = index;
    _confirmIndex = null;
    _confirmStart = null;
    if (!_ticker.isActive) {
      _elapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _dropped(int oldIndex, int newIndex) {
    _dragIndex = null;
    _edge.value = _EdgeHint.none;
    if (oldIndex == newIndex || !mounted) return;
    _confirmIndex = newIndex;
    _confirmStart = _elapsed;
    if (!_ticker.isActive) {
      _elapsed = Duration.zero;
      _confirmStart = Duration.zero;
      _ticker.start();
    }
    if (widget.touch) HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context)!;
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.reorderPositionOf(newIndex + 1, widget.itemCount),
      Directionality.of(context),
    );
  }

  double _start(Rect r) => widget.axis == Axis.vertical ? r.top : r.left;
  double _end(Rect r) => widget.axis == Axis.vertical ? r.bottom : r.right;

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    final host = context.findRenderObject();
    if (host is! RenderBox || !host.hasSize) return;

    // Only probes inside the list: the proxy's copy of the lifted item lives
    // in the overlay, has no list slot, and must count neither as an item nor
    // as the dragged item being back.
    final byIndex = <int, _Geometry>{};
    for (final probe in _probes) {
      if (!probe.attached || !probe.hasSize) continue;
      final item = probe.listItem;
      if (item == null) continue;
      byIndex[probe.index] = _Geometry(
        probe.index,
        MatrixUtils.transformRect(probe.getTransformTo(host), Offset.zero & probe.size),
        probe.shiftWithin(item, widget.axis),
      );
    }
    final geometry = byIndex.values.toList()..sort((a, b) => a.index.compareTo(b.index));

    final drag = _dragIndex;
    if (drag != null) {
      final present = byIndex.containsKey(drag);
      if (!present) _placeholderSeen = true;
      // The dragged item's own probe is back: the list has dropped it without
      // a reorder (a cancel, or a drop back into its old place).
      if (present && _placeholderSeen) {
        _dragIndex = null;
        _edge.value = _EdgeHint.none;
      }
    }

    final gaps = <Rect>[];
    Rect? labelRect;
    String? label;
    if (_dragIndex != null && _placeholderSeen && geometry.isNotEmpty && _extent > 0) {
      _findGaps(geometry, gaps);
      if (gaps.isNotEmpty) {
        labelRect = gaps.reduce((a, b) => _length(a) >= _length(b) ? a : b);
        final target = _targetIndex(geometry);
        if (target != _target) {
          _target = target;
          if (widget.touch) HapticFeedback.selectionClick();
        }
        if (widget.showLabel) {
          final l10n = AppLocalizations.of(context)!;
          label = target >= widget.itemCount - 1 && widget.itemCount > 1
              ? l10n.dropAtEnd
              : l10n.dropAtPosition(target + 1);
        }
      }
      _updateEdge(host);
    }

    Rect? confirm;
    double confirmOpacity = 0;
    final confirmIndex = _confirmIndex;
    final confirmStart = _confirmStart;
    if (confirmIndex != null && confirmStart != null) {
      final reduced = AppMotion.prefersReduced(context);
      final hold = reduced ? const Duration(milliseconds: 1200) : const Duration(milliseconds: 600);
      final fade = reduced ? Duration.zero : AppMotion.hover;
      final age = elapsed - confirmStart;
      if (age >= hold + fade) {
        _confirmIndex = null;
        _confirmStart = null;
      } else {
        final match = geometry.where((g) => g.index == confirmIndex);
        if (match.isNotEmpty) {
          confirm = _inset(match.first.rect);
          confirmOpacity = age <= hold
              ? 1
              : 1 - AppMotion.quick.transform((age - hold).inMicroseconds / fade.inMicroseconds);
        }
      }
    }

    _frame.value = _GapFrame(
      gaps: [for (final g in gaps) _inset(g)],
      labelRect: labelRect == null ? null : _inset(labelRect),
      label: label,
      confirm: confirm,
      confirmOpacity: confirmOpacity,
    );

    if (_dragIndex == null && _confirmIndex == null) {
      _ticker.stop();
      if (!_frame.value.isEmpty) _frame.value = const _GapFrame();
    }
  }

  double _length(Rect r) => _end(r) - _start(r);

  /// The stretches of the slot band that no item covers, as full-width rects.
  void _findGaps(List<_Geometry> geometry, List<Rect> out) {
    final vertical = widget.axis == Axis.vertical;
    final first = geometry.first;
    final last = geometry.last;
    final drag = _dragIndex!;

    double bandStart = _start(first.rect) - first.shift;
    if (drag == first.index - 1) bandStart -= _extent;
    double bandEnd = _end(last.rect) - last.shift;
    if (drag == last.index + 1) bandEnd += _extent;

    double crossStart = double.infinity;
    double crossEnd = double.negativeInfinity;
    for (final g in geometry) {
      crossStart = vertical ? (g.rect.left < crossStart ? g.rect.left : crossStart) : (g.rect.top < crossStart ? g.rect.top : crossStart);
      crossEnd = vertical ? (g.rect.right > crossEnd ? g.rect.right : crossEnd) : (g.rect.bottom > crossEnd ? g.rect.bottom : crossEnd);
    }

    final covered = [for (final g in geometry) (_start(g.rect), _end(g.rect))]..sort((a, b) => a.$1.compareTo(b.$1));
    var cursor = bandStart;
    void addGap(double from, double to) {
      if (to - from < 1) return;
      out.add(vertical ? Rect.fromLTRB(crossStart, from, crossEnd, to) : Rect.fromLTRB(from, crossStart, to, crossEnd));
    }

    for (final (start, end) in covered) {
      if (start > cursor) addGap(cursor, start < bandEnd ? start : bandEnd);
      if (end > cursor) cursor = end;
      if (cursor >= bandEnd) break;
    }
    if (cursor < bandEnd) addGap(cursor, bandEnd);
  }

  /// Where the dragged item lands if dropped now, read off which items the
  /// list has slid past half an extent.
  int _targetIndex(List<_Geometry> geometry) {
    final drag = _dragIndex!;
    final half = _extent / 2;
    int? before;
    int? after;
    for (final g in geometry) {
      if (g.index < drag && g.shift > half) before = before == null || g.index < before ? g.index : before;
      if (g.index > drag && g.shift < -half) after = after == null || g.index > after ? g.index : after;
    }
    return before ?? after ?? drag;
  }

  Rect _inset(Rect r) {
    final p = widget.slotPadding;
    return Rect.fromLTRB(r.left + p.left, r.top + p.top, r.right - p.right, r.bottom - p.bottom);
  }

  void _updateEdge(RenderBox host) {
    final pointer = _pointer;
    final metrics = _metrics;
    if (widget.axis != Axis.vertical || pointer == null || metrics == null) {
      _edge.value = _EdgeHint.none;
      return;
    }
    final local = host.globalToLocal(pointer);
    if (local.dy < _edgeBand && metrics.extentBefore > 0) {
      _edge.value = _EdgeHint.start;
    } else if (local.dy > host.size.height - _edgeBand && metrics.extentAfter > 0) {
      _edge.value = _EdgeHint.end;
    } else {
      _edge.value = _EdgeHint.none;
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0) _metrics = n.metrics;
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    if (n.depth == 0) _metrics = n.metrics;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phone = widget.touch && Responsive.isMobile(context);
    final labelStyle = (phone ? theme.textTheme.bodySmall! : theme.textTheme.labelSmall!)
        .metricsOnly
        .copyWith(fontWeight: FontWeight.w500, color: scheme.onAccentTint);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _pointer = e.position,
      onPointerMove: (e) => _pointer = e.position,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: Stack(
            children: [
              widget.builder(context, _controller),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GapPainter(
                      frame: _frame,
                      tint: scheme.accentTint,
                      edge: scheme.primary,
                      ring: scheme.accentRing,
                      labelStyle: labelStyle,
                      textDirection: Directionality.of(context),
                    ),
                  ),
                ),
              ),
              if (widget.axis == Axis.vertical)
                Positioned.fill(child: IgnorePointer(child: _EdgeScrollHint(edge: _edge))),
            ],
          ),
        ),
      ),
    );
  }
}

class _GapProbe extends SingleChildRenderObjectWidget {
  const _GapProbe({required this.state, required this.index, required super.child});

  final _AppReorderGapState state;
  final int index;

  @override
  _RenderGapProbe createRenderObject(BuildContext context) => _RenderGapProbe(state, index);

  @override
  void updateRenderObject(BuildContext context, _RenderGapProbe renderObject) {
    renderObject
      ..state = state
      ..index = index;
  }
}

class _RenderGapProbe extends RenderProxyBox {
  _RenderGapProbe(this._state, this.index);

  _AppReorderGapState _state;
  set state(_AppReorderGapState value) {
    if (identical(value, _state)) return;
    if (attached) _state._unregister(this);
    _state = value;
    if (attached) _state._register(this);
  }

  /// The item's index in the list — or, for the proxy's copy, the index of
  /// the slot it was lifted from.
  int index;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _state._register(this);
  }

  @override
  void detach() {
    _state._unregister(this);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _state._measured(index, size);
  }

  /// The list's own child for this item — where the list lays the item out
  /// before sliding it — or null for a copy outside the list (the proxy).
  RenderObject? get listItem {
    RenderObject? node = parent;
    while (node != null && node.parentData is! SliverMultiBoxAdaptorParentData) {
      node = node.parent;
    }
    return node;
  }

  /// How far the list has translated this item along [axis] within [item].
  double shiftWithin(RenderObject item, Axis axis) {
    final translation = getTransformTo(item).getTranslation();
    return axis == Axis.vertical ? translation.y : translation.x;
  }
}

class _GapPainter extends CustomPainter {
  _GapPainter({
    required this.frame,
    required this.tint,
    required this.edge,
    required this.ring,
    required this.labelStyle,
    required this.textDirection,
  }) : super(repaint: frame);

  final ValueListenable<_GapFrame> frame;
  final Color tint;
  final Color edge;
  final Color ring;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  static const double _minSide = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame.value;
    if (f.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final radius = const Radius.circular(AppRadius.control);
    final fill = Paint()..color = tint;
    final dash = Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final gap in f.gaps) {
      if (gap.width < _minSide || gap.height < _minSide) continue;
      final rrect = RRect.fromRectAndRadius(gap, radius);
      canvas.drawRRect(rrect, fill);
      drawDashedRRect(canvas, rrect.deflate(0.5), dash);
    }

    final labelRect = f.labelRect;
    final label = f.label;
    if (labelRect != null && label != null) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textAlign: TextAlign.center,
        textDirection: textDirection,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: (labelRect.width - 12).clamp(0, double.infinity));
      if (painter.height <= labelRect.height - 4 && painter.width > 0) {
        painter.paint(canvas, labelRect.center - Offset(painter.width / 2, painter.height / 2));
      }
      painter.dispose();
    }

    final confirm = f.confirm;
    if (confirm != null && f.confirmOpacity > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(confirm, radius).deflate(0.5),
        Paint()
          ..color = ring.withValues(alpha: ring.a * f.confirmOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GapPainter old) =>
      old.frame != frame ||
      old.tint != tint ||
      old.edge != edge ||
      old.ring != ring ||
      old.labelStyle != labelStyle ||
      old.textDirection != textDirection;
}

/// `1f` ③: while a drag sits in the 48 band at a scrollable edge, the band
/// fades in the accent wash and a capsule says the list will keep scrolling.
class _EdgeScrollHint extends StatelessWidget {
  const _EdgeScrollHint({required this.edge});

  final ValueListenable<_EdgeHint> edge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final duration = AppMotion.durationOf(context, AppMotion.hover);

    return ValueListenableBuilder<_EdgeHint>(
      valueListenable: edge,
      builder: (context, hint, _) {
        final atStart = hint == _EdgeHint.start;
        return AnimatedOpacity(
          opacity: hint == _EdgeHint.none ? 0 : 1,
          duration: duration,
          child: Align(
            alignment: atStart ? Alignment.topCenter : Alignment.bottomCenter,
            child: SizedBox(
              height: _AppReorderGapState._edgeBand,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: atStart ? Alignment.topCenter : Alignment.bottomCenter,
                    end: atStart ? Alignment.bottomCenter : Alignment.topCenter,
                    colors: [scheme.accentTint, scheme.accentTint.withValues(alpha: 0)],
                  ),
                ),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: scheme.primary),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            atStart ? Icons.keyboard_double_arrow_up : Icons.keyboard_double_arrow_down,
                            size: AppSize.iconSm,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: AppSpace.s4),
                          Text(
                            l10n.dragKeepToScroll,
                            style: theme.textTheme.labelSmall!.metricsOnly.copyWith(
                              fontWeight: FontWeight.w500,
                              color: scheme.onAccentTint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
