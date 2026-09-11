import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import 'app_glass.dart';

/// Controls drawn *on* a glass bar (`A1 · 1a` floating toolbar, `A4–A6` tool
/// headers).
///
/// They take their ink from the nearest [GlassInk], so the same control is
/// `gink` on glass and body ink on the reduced-effects surface, and they spend
/// no glass of their own except the lens that marks what is selected or
/// pressed (G3) — the lens is the one glass layer allowed inside another.

/// A 1px rule between groups on a glass bar (`--gedge`, 20 tall, 4 either
/// side).
class GlassDivider extends StatelessWidget {
  const GlassDivider({super.key, this.height = 20});

  final double height;

  /// Horizontal space the divider takes, for bars that measure before laying
  /// out.
  static const double extent = 9;

  @override
  Widget build(BuildContext context) {
    final edge = GlassInk.maybeOf(context)?.edge ?? Theme.of(context).colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(width: 1, height: height, child: ColoredBox(color: edge)),
    );
  }
}

/// Width of [text] in [style], honouring the text scale.
double measureGlassText(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// One option of a [GlassSegmented].
@immutable
class GlassSegment<T> {
  const GlassSegment({required this.value, required this.label, this.icon, this.tooltip});

  final T value;
  final String label;
  final IconData? icon;

  /// Shown when the label is dropped; defaults to [label].
  final String? tooltip;
}

/// A segmented control on glass: a faint track (glass ink at 8%, r10, 2px
/// inset) with the selected segment as a lens (G3, r6) — `A1 · 1a` 「图像 /
/// 视频」 and 「全部来源 / 全部结果」.
///
/// [accent] marks a *mode* switch: the selected icon takes the accent and its
/// label the deep ink. A *view* switch (sources/results) stays neutral — the
/// accent is not spent on how you are looking at the work. Reduced effects
/// turn the lens into the 12% wash (`A1 · 1h`).
class GlassSegmented<T> extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.showLabels = true,
    this.accent = false,
    this.segmentHeight = AppSize.compact,
  });

  final List<GlassSegment<T>> segments;

  /// Null when no segment is current.
  final T? value;
  final ValueChanged<T> onChanged;
  final bool showLabels;
  final bool accent;
  final double segmentHeight;

  static TextStyle labelStyle(BuildContext context, {required bool selected}) =>
      Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          );

  /// The width this control takes, measured at the selected weight so a
  /// selection change can never make it wider than planned.
  static double widthFor<T>(
    BuildContext context,
    List<GlassSegment<T>> segments, {
    required bool showLabels,
  }) {
    double width = 4 + 2.0 * (segments.length - 1);
    for (final s in segments) {
      final hasIcon = s.icon != null;
      if (!showLabels && hasIcon) {
        width += 10 + AppSize.iconMd + 10;
        continue;
      }
      width += 12 +
          (hasIcon ? AppSize.iconMd + 6 : 0) +
          measureGlassText(context, s.label, labelStyle(context, selected: true)) +
          12;
    }
    return width.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: (glass?.reduced ?? false)
            ? scheme.surfaceContainerHighest
            : ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            _GlassSegmentItem<T>(
              segment: segments[i],
              selected: segments[i].value == value,
              showLabel: showLabels || segments[i].icon == null,
              accent: accent,
              height: segmentHeight,
              onTap: () => onChanged(segments[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlassSegmentItem<T> extends StatefulWidget {
  const _GlassSegmentItem({
    required this.segment,
    required this.selected,
    required this.showLabel,
    required this.accent,
    required this.height,
    required this.onTap,
  });

  final GlassSegment<T> segment;
  final bool selected;
  final bool showLabel;
  final bool accent;
  final double height;
  final VoidCallback onTap;

  @override
  State<_GlassSegmentItem<T>> createState() => _GlassSegmentItemState<T>();
}

class _GlassSegmentItemState<T> extends State<_GlassSegmentItem<T>> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final s = widget.segment;
    final selected = widget.selected;

    final Color labelColor = selected ? (widget.accent ? scheme.onAccentTint : ink) : ink2;
    final Color iconColor = selected && widget.accent ? scheme.primary : labelColor;

    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.showLabel ? 12 : 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.icon != null) Icon(s.icon, size: AppSize.iconMd, color: iconColor),
          if (s.icon != null && widget.showLabel) const SizedBox(width: 6),
          if (widget.showLabel)
            Text(
              s.label,
              maxLines: 1,
              style: GlassSegmented.labelStyle(context, selected: selected).copyWith(color: labelColor),
            ),
        ],
      ),
    );

    final radius = BorderRadius.circular(AppRadius.sm);
    final reduced = glass?.reduced ?? false;
    final lensContent = SizedBox(height: widget.height, child: Center(widthFactor: 1, child: content));
    final Widget box = selected
        ? (reduced && !widget.accent
            // `A1 · 1h`: a neutral switch's selection, opaque, is the raised
            // panel segment — the wash belongs to the accent form alone.
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: radius,
                  boxShadow: scheme.shadowRaised,
                ),
                child: lensContent,
              )
            : AppGlass(
                grade: GlassGrade.lens,
                borderRadius: radius,
                reducedColor: scheme.accentTint,
                child: lensContent,
              ))
        : AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            height: widget.height,
            decoration: BoxDecoration(
              color: _hovering ? ink.withValues(alpha: 0.06) : Colors.transparent,
              borderRadius: radius,
            ),
            child: Center(widthFactor: 1, child: content),
          );

    Widget result = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: box,
      ),
    );
    if (!widget.showLabel) {
      result = Tooltip(message: s.tooltip ?? s.label, child: result);
    }
    return Semantics(button: true, selected: selected, label: s.label, child: result);
  }
}

/// A 32px action on a glass bar: a bare 20px glyph, a glyph with a 12px
/// label, or a label alone (`A1 · 1a` 「对比器 · 蒙版」, selection bar 「全选」).
///
/// Hover is a faint wash of the glass ink; [active] is a lens with the glyph
/// in the accent (`A1 · 1c` the fill toggle, `A1 · 1d` the open drawer).
class GlassIconButton extends StatefulWidget {
  const GlassIconButton({
    super.key,
    this.icon,
    required this.onPressed,
    this.tooltip,
    this.label,
    this.active = false,
    this.danger = false,
    this.size = AppSize.control,
  }) : assert(icon != null || label != null, 'give GlassIconButton an icon, a label or both');

  final IconData? icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? label;
  final bool active;
  final bool danger;
  final double size;

  static TextStyle labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.metricsOnly;

  /// The width this button takes with the given parts.
  static double widthFor(
    BuildContext context, {
    String? label,
    bool hasIcon = true,
    double size = AppSize.control,
  }) {
    if (label == null) return size;
    final text = measureGlassText(context, label, labelStyle(context).copyWith(fontWeight: FontWeight.w500));
    return (10 + (hasIcon ? AppSize.iconLg + 6 : 0) + text + 10).ceilToDouble();
  }

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final enabled = widget.onPressed != null;

    final Color color = !enabled
        ? ink2.withValues(alpha: ink2.a * 0.6)
        : widget.danger
            ? scheme.error
            : widget.active
                ? scheme.primary
                : ink;

    final Widget content;
    if (widget.label == null) {
      content = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Icon(widget.icon, size: AppSize.iconLg, color: color),
      );
    } else {
      final Color labelColor = !enabled
          ? color
          : widget.danger
              ? scheme.error
              : (widget.active ? scheme.onAccentTint : ink);
      content = SizedBox(
        height: widget.size,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: AppSize.iconLg, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label!,
                maxLines: 1,
                style: GlassIconButton.labelStyle(context).copyWith(
                  color: labelColor,
                  fontWeight: widget.active || widget.danger ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final radius = BorderRadius.circular(AppRadius.control);
    final Widget box = widget.active
        ? AppGlass(
            grade: GlassGrade.lens,
            borderRadius: radius,
            reducedColor: scheme.accentTint,
            child: content,
          )
        : AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            decoration: BoxDecoration(
              color: _hovering && enabled ? ink.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: radius,
            ),
            child: content,
          );

    Widget result = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: box,
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.active,
      label: widget.tooltip ?? widget.label,
      child: result,
    );
  }
}

/// The accent's solid form as a 56px floating button on a phone (`A1 · 1e`
/// FAB: tinted glass at r22).
class GlassFab extends StatelessWidget {
  const GlassFab({super.key, required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget fab = Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: AppTintedGlass(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          child: SizedBox(width: 56, height: 56, child: Icon(icon, size: 24)),
        ),
      ),
    );
    if (tooltip != null) fab = Tooltip(message: tooltip!, child: fab);
    return fab;
  }
}
