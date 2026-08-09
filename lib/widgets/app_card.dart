import 'package:flutter/material.dart';

/// A rounded content card for grouping related widgets inside a panel — a
/// settings block, a list row, a summary tile.
///
/// Not [PanelCard]: that one is the top-level surface a [PanelResizer] gutter
/// sits between, coloured `surface` against the canvas's `surfaceContainer`.
/// This card nests *inside* a panel, so it takes the next tone up
/// (`surfaceContainerHigh`) to still read as a distinct group against the
/// panel's own `surface` fill. Reaching for a decorated [Container] instead
/// is what left every card in the app a slightly different shade and radius.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Material, not a decorated Container: a plain Container swallows the ink
    // response of any ListTile/InkWell inside it — the same reason PanelCard
    // uses one.
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
