part of '../workbench_config_panel.dart';

/// A card in the right column (`A1 · 1a`): the panel's ground, a hairline,
/// r16, inset 10.
///
/// Not [AppCard], whose radius and tones belong to the previous column; this
/// is the column's own card, used for every group in it.
class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

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
        child: Padding(padding: const EdgeInsets.all(_kCardPadding), child: child),
      ),
    );
  }
}
