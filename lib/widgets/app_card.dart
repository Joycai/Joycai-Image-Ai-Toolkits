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

  /// Group with a hairline outline instead of a step in fill.
  ///
  /// For cards on a panel that is already the lightest surface in play — the
  /// workbench's right column, whose [PanelCard] is `surface`. A tone *up*
  /// from there is a grey card on a white panel, which inverts the usual
  /// figure/ground: the group ends up looking recessed rather than raised.
  /// Same fill plus an edge reads as a group without that inversion.
  final bool outlined;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Material, not a decorated Container: a plain Container swallows the ink
    // response of any ListTile/InkWell inside it — the same reason PanelCard
    // uses one.
    return Material(
      color: outlined ? colorScheme.surface : colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      // shape, never borderRadius: Material asserts if given both, and the
      // outlined tone needs a side.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: outlined ? BorderSide(color: colorScheme.outlineVariant) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
