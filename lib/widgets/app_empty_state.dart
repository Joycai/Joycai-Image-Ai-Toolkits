import 'package:flutter/material.dart';

/// The "nothing here" block a list draws in place of its rows.
///
/// Two of these existed — the prompt library's and the searchable picker's —
/// at two glyph sizes, two gaps and two type roles, for the same sentence in
/// the same situation. They are one component with a density, not two
/// components.
///
/// Deliberately *not* the same thing as the discovery dialog's full-page state
/// view, which carries a title, a subtitle and an action and fills a dialog
/// body. Folding that in here would be a redesign of it rather than a
/// de-duplication of this.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.label,
    this.compact = false,
  });

  final IconData icon;
  final String label;

  /// Sized for a list *inside* another control — a picker's dialog — rather
  /// than one filling a panel of its own.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: compact ? 32 : 48, color: colorScheme.outlineVariant),
          SizedBox(height: compact ? 10 : 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: (compact ? textTheme.bodySmall : textTheme.bodyMedium)
                ?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
