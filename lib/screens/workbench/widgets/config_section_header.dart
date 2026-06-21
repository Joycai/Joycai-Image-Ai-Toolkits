import 'package:flutter/material.dart';

/// A quiet, Apple-style section header shared across the workbench config
/// panels (Image / Video generation) so both speak the same visual language:
/// uppercase, muted, letter-spaced, with an optional trailing action.
class ConfigSectionHeader extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const ConfigSectionHeader(
    this.label, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 18, bottom: 6),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: colorScheme.primary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
