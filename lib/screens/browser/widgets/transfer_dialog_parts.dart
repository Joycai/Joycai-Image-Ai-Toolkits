import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';

/// Pieces shared by the file browser's transfer dialogs — the staging paste
/// (`B1a 12e/12f`) and the folder move (`B1b 13f`), which the spec draws as
/// the same shell.

/// A quiet information-blue note inside a dialog body.
class TransferInfoNote extends StatelessWidget {
  final String text;

  const TransferInfoNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: semantic.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: AppSize.iconSm, color: semantic.info),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.55,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the three counts a transfer ends with.
///
/// Three counts rather than a sentence: succeeded, skipped and failed answer
/// three different questions, and a toast that runs them together makes the
/// one that matters easiest to miss.
class TransferStatCell extends StatelessWidget {
  final int value;
  final String label;
  final Color color;

  const TransferStatCell({
    super.key,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: textTheme.titleLarge?.mono.copyWith(
              // A zero is not news. Colouring it would make an untouched
              // counter as loud as a real failure.
              color: value == 0 ? colorScheme.outline : color,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

