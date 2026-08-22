import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// One choice in an [AppSegmentedControl].
class AppSegment<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// A choice that exists but cannot be taken yet — shown, so the user knows
  /// the mode is there, and why the one they want is missing.
  final bool enabled;

  const AppSegment({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });
}

/// How an [AppSegmentedControl] marks the chosen option.
enum AppSegmentStyle {
  /// Accent tint and outline. Reads as "on" against the track, which suits a
  /// control whose options are settings — streaming on/off, a filter.
  tinted,

  /// The chosen option lifts out of the track on a plain surface, the way a
  /// physical switch would. For a control that picks *which view you are in*
  /// rather than a value: the accent is then free to mean "selected" inside
  /// that view instead of being spent on the navigation.
  raised,
}

/// A single-choice control: a track holding its options, with the chosen one
/// filled in.
///
/// Replaces Material's [SegmentedButton], which draws the same choice as a pill
/// of hairline-divided buttons — at a glance the selection reads as "the button
/// that happens to be tinted" rather than as a position along a track. The
/// track also gives the control an edge of its own, which matters where these
/// sit on a bare canvas next to nothing else.
class AppSegmentedControl<T> extends StatefulWidget {
  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// Split the width evenly between the options rather than letting each take
  /// only what its label needs. For controls that own their row.
  final bool expand;

  /// Tighter type and padding, for controls tucked into a toolbar.
  final bool compact;

  /// Draw each option as its [AppSegment.icon] alone, with the label as its
  /// tooltip. For a toolbar on a phone, where the labelled track would take
  /// the whole row — the option is never left unexplained, only unlabelled.
  ///
  /// Segments without an icon keep their label, so a mixed track degrades
  /// rather than losing options.
  final bool iconOnly;

  /// How the chosen option is marked.
  final AppSegmentStyle style;

  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.compact = false,
    this.iconOnly = false,
    this.style = AppSegmentStyle.tinted,
  });

  @override
  State<AppSegmentedControl<T>> createState() => _AppSegmentedControlState<T>();
}

class _AppSegmentedControlState<T> extends State<AppSegmentedControl<T>> {
  /// The coordinate space the indicator is positioned in — the Stack inside
  /// the track's padding, so an offset measured against it is already the
  /// indicator's `left`/`top`.
  final GlobalKey _trackKey = GlobalKey();
  final Map<int, GlobalKey> _segmentKeys = <int, GlobalKey>{};

  /// Where the selected chip actually is, measured after layout.
  ///
  /// Null until the first measurement lands, which is the one frame where the
  /// selection is drawn by the chip itself instead — see `_ownsSkin`. Without
  /// that fallback the control would render its first frame with nothing
  /// selected.
  Rect? _indicator;

  GlobalKey _keyFor(int index) =>
      _segmentKeys.putIfAbsent(index, () => GlobalKey());

  /// Re-measures after every layout.
  ///
  /// Scheduled from `build` rather than from `didUpdateWidget` alone, because
  /// the chip moves for reasons the widget never hears about: the window
  /// resizing, a label changing width when the locale changes, an `expand`
  /// track sharing a row that got narrower. The measurement only calls
  /// `setState` when the rect actually moved, so this settles after one extra
  /// frame instead of looping.
  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final index = widget.segments.indexWhere((s) => s.value == widget.value);
    if (index < 0) return;

    final track = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    final chip = _segmentKeys[index]?.currentContext?.findRenderObject() as RenderBox?;
    if (track == null || chip == null || !track.hasSize || !chip.hasSize) return;

    final rect = chip.localToGlobal(Offset.zero, ancestor: track) & chip.size;
    if (rect != _indicator) setState(() => _indicator = rect);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _scheduleMeasure();

    final indicator = _indicator;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        // A tone above every surface the app puts this on, so the track is
        // visible whether it lands on a card or on the canvas.
        color: colorScheme.surfaceContainerHighest,
        // One step out from the chips it holds, so the gap between the two
        // curves stays even around the selected option's corners.
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Stack(
        key: _trackKey,
        children: [
          // One indicator that travels, rather than a fill that crossfades in
          // place. A segmented control says "you are *here* along this track",
          // and a selection that vanishes on the left and reappears on the
          // right leaves the user to infer the connection between the two —
          // the thing the movement is there to state. It is also why this uses
          // `move` and not `enter`: both endpoints are on screen, so the
          // travel accelerates and decelerates rather than only landing softly.
          if (indicator != null)
            AnimatedPositioned(
              duration: AppMotion.durationOf(context, AppMotion.state),
              curve: AppMotion.move,
              left: indicator.left,
              top: indicator.top,
              width: indicator.width,
              height: indicator.height,
              child: DecoratedBox(decoration: _indicatorDecoration(colorScheme)),
            ),
          Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              for (final (index, segment) in widget.segments.indexed)
                if (widget.expand)
                  Expanded(
                    child: KeyedSubtree(
                      key: _keyFor(index),
                      child: _buildSegment(context, colorScheme, segment),
                    ),
                  )
                else
                  KeyedSubtree(
                    key: _keyFor(index),
                    child: _buildSegment(context, colorScheme, segment),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  /// The travelling pill itself, in whichever of the two styles applies.
  ///
  /// This used to be the selected chip's own `decoration`, which is why the
  /// selection crossfaded in place: two chips each animating a fill of their
  /// own cannot describe one thing moving between them.
  BoxDecoration _indicatorDecoration(ColorScheme colorScheme) {
    if (widget.style == AppSegmentStyle.raised) {
      return BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        // Carries the same 1px edge as `tinted`, transparent. It draws
        // nothing; it exists so both styles inset their content identically
        // and a chip is the same size whichever one it is wearing. See
        // [_chipHitDecoration].
        border: Border.all(color: Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      );
    }
    return BoxDecoration(
      color: colorScheme.accentTint,
      borderRadius: BorderRadius.circular(AppRadius.control),
      // The spec's selection ring is markedly quieter than the 0.6 this used
      // to draw — at that strength the border was competing with the label
      // inside it for the eye.
      border: Border.all(color: colorScheme.accentRing),
    );
  }

  /// What an unselected chip decorates itself with: nothing visible, and
  /// exactly the same 1px edge the indicator has.
  ///
  /// A `BoxDecoration`'s border is layout, not just paint — a Container folds
  /// it into its padding. So the old control's selected chip, which was the
  /// only one with a border, was 2px wider and taller than its neighbours, and
  /// the whole track twitched every time the selection moved. Invisible at a
  /// crossfade; not invisible under a pill that is measured against those
  /// boxes, which is how this surfaced.
  BoxDecoration _chipHitDecoration() => BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: Colors.transparent),
      );

  Widget _buildSegment(BuildContext context, ColorScheme colorScheme, AppSegment<T> segment) {
    final selected = segment.value == widget.value;
    final raised = widget.style == AppSegmentStyle.raised;

    final Color color;
    if (!segment.enabled) {
      color = colorScheme.onSurface.withValues(alpha: AppAlpha.disabled);
    } else if (!selected) {
      color = colorScheme.onSurfaceVariant;
    } else {
      // Raised spends no accent on the label: the lift already says which one
      // is chosen, and the accent is needed for state *inside* the view.
      //
      // Tinted takes `onAccentTint`, not `primary`. The label is sitting on a
      // wash of primary, and primary on its own tint is the same tone twice —
      // legible in light mode by luck, and washed out in dark, where primary
      // is already a pale tone 80.
      color = raised ? colorScheme.onSurface : colorScheme.onAccentTint;
    }

    final bareIcon = widget.iconOnly && segment.icon != null;

    // The one frame before the first measurement lands, the chip draws the
    // selection itself so the control is never rendered with nothing chosen.
    final ownsSkin = selected && _indicator == null;

    final Widget chip = InkWell(
      onTap: selected || !segment.enabled ? null : () => widget.onChanged(segment.value),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 10 : 14,
          vertical: widget.compact ? 7 : 11,
        ),
        decoration: ownsSkin ? _indicatorDecoration(colorScheme) : _chipHitDecoration(),
        // The label crosses from the unselected tone to the selected one over
        // the same duration the pill travels, so the two read as one movement.
        // A hard colour swap under a sliding pill is the seam this avoids: the
        // text would change before the fill arrived under it.
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: AppMotion.durationOf(context, AppMotion.state),
          curve: AppMotion.enter,
          builder: (context, tint, _) => Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (segment.icon != null) ...[
                Icon(segment.icon, size: widget.compact ? 14 : 17, color: tint),
                if (!bareIcon) const SizedBox(width: 7),
              ],
              if (!bareIcon)
                Flexible(
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (widget.compact
                            ? Theme.of(context).textTheme.labelMedium
                            : Theme.of(context).textTheme.bodySmall)
                        ?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: tint,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return bareIcon ? Tooltip(message: segment.label, child: chip) : chip;
  }
}
