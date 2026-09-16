part of '../task_queue_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
// Bands, counts, chips
// ════════════════════════════════════════════════════════════════════════════

/// An edge-to-edge strip on the column colour, ruled off below.
class _ColumnBand extends StatelessWidget {
  const _ColumnBand({
    required this.height,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final double height;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: child,
    );
  }
}

/// The counts on one line: 10 apart on the wide header, ` · ` between them on
/// the phone. Ellipsizes rather than wrapping, so the header stays 72.
class _CountsLine extends StatelessWidget {
  const _CountsLine({required this.items, required this.style, this.separator});

  final List<(String, Color, FontWeight)> items;
  final TextStyle style;

  /// Null draws a 10px gap instead of a separator.
  final String? separator;

  static const double _gap = AppSpace.s10;

  /// The width of the gapped form at [style].
  static double measure(BuildContext context, List<(String, Color, FontWeight)> items, TextStyle style) {
    var width = _gap * (items.length - 1);
    for (final (text, _, weight) in items) {
      width += measureGlassText(context, text, style.copyWith(fontWeight: weight));
    }
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sep = separator;
    return Text.rich(
      TextSpan(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              sep == null
                  ? const WidgetSpan(child: SizedBox(width: _gap))
                  : TextSpan(text: sep, style: TextStyle(color: scheme.outline)),
            TextSpan(
              text: items[i].$1,
              style: TextStyle(color: items[i].$2, fontWeight: items[i].$3),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// The five filter chips.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.entries,
    required this.selected,
    required this.onSelect,
    this.height = 28,
  });

  final List<(TaskFilter, String, int)> entries;
  final TaskFilter selected;
  final ValueChanged<TaskFilter> onSelect;
  final double height;

  static const double _gap = AppSpace.s6;

  /// The strip's natural width.
  static double measure(BuildContext context, List<(TaskFilter, String, int)> entries) {
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600);
    final count = textTheme.bodySmall!.mono;
    var width = _gap * (entries.length - 1);
    for (final (_, text, n) in entries) {
      width += _FilterChip.padX * 2 +
          measureGlassText(context, text, label) +
          _FilterChip.countGap +
          measureGlassText(context, '$n', count);
    }
    return width.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          _FilterChip(
            label: entries[i].$2,
            count: entries[i].$3,
            selected: entries[i].$1 == selected,
            danger: entries[i].$1 == TaskFilter.failed,
            height: height,
            onTap: () => onSelect(entries[i].$1),
          ),
        ],
      ],
    );
  }
}

/// `B2` 筛选胶囊: a capsule, the count after its label in mono at .8.
/// Selected is the accent's 12% form with no edge — the 失败 chip takes the
/// error container instead; unselected is a hairline outline on nothing.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.danger,
    required this.height,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool danger;
  final double height;
  final VoidCallback onTap;

  static const double padX = 12;
  static const double countGap = AppSpace.s6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.pill);

    final (Color fill, Color ink) = !selected
        ? (Colors.transparent, scheme.onSurfaceVariant)
        : danger
            ? (scheme.errorContainer, scheme.onErrorContainer)
            : (scheme.accentTint, scheme.onAccentTint);

    return Material(
      color: fill,
      borderRadius: radius,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: radius,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: padX),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: selected ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ),
              ),
              const SizedBox(width: countGap),
              Opacity(
                opacity: 0.8,
                child: Text('$count', style: textTheme.bodySmall?.mono.copyWith(color: ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pin switch beside the sort track, its label dropped to a tooltip when
/// the row is short of room.
class _PinToggle extends StatelessWidget {
  const _PinToggle({
    required this.label,
    required this.showLabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool showLabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final toggle = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLabel) ...[
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 8),
            ],
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
    return showLabel ? toggle : Tooltip(message: label, child: toggle);
  }
}

/// The seam between the pinned tasks and the rest: a tracked grey caption and
/// a hairline running on from it. Drawn only while both sides have rows.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: AppType.trackedLabelSpacing,
                  color: scheme.outline,
                ),
          ),
          const SizedBox(width: AppSpace.s10),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

/// A centred glyph, title, explanation and one way out.
class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.titleStyle,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final TextStyle? titleStyle;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: iconColor),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: titleStyle),
            const SizedBox(height: AppSpace.s6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: AppType.looseHeight,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            action,
          ],
        ),
      ),
    );
  }
}
