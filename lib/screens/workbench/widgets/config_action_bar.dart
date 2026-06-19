import 'package:flutter/material.dart';

/// A docked footer that keeps a config panel's primary action always reachable
/// on desktop, without scrolling to the end of a long form. Sits below the
/// scrollable content with a hairline top border.
class ConfigActionBar extends StatelessWidget {
  final Widget child;
  const ConfigActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: child,
    );
  }
}
