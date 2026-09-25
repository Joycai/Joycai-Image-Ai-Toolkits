part of '../workbench_config_panel.dart';

/// A card in the right column (`A1 · 1a`): the panel's ground, a hairline,
/// r16, inset 10.
///
/// Not [AppCard], whose radius and tones belong to the previous column; this
/// is the column's own card, used for every group in it.
class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child, this.padding = const EdgeInsets.all(_kCardPadding)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Material, not a decorated Container, so the ink of the buttons and
    // fields inside lands on it.
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A request toggle (`A1 · 1a` 「开关卡」): the label, its hint inline in the
/// secondary ink, and the switch at the end of a 36px row.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // Merged so the switch is announced with the words that name it.
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kToggleRowHeight),
        child: Padding(
          // Only felt when a long hint wraps: a second line never touches the
          // hairline beside it.
          padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
                      ),
                      const WidgetSpan(child: SizedBox(width: AppSpace.s6)),
                      TextSpan(
                        text: hint,
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.s10),
              AppSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
