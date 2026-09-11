import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';

/// A docked footer that keeps a config panel's primary action always reachable
/// on desktop, without scrolling to the end of a long form.
///
/// `A1 · 1a`: the column's own ground under a hairline, inset 10 all round —
/// the same inset the cards above it sit at, so the button's edges line up
/// with theirs.
class ConfigActionBar extends StatelessWidget {
  final Widget child;
  const ConfigActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: child,
    );
  }
}
