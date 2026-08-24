import 'package:flutter/material.dart';

import 'app_card.dart';

/// The "nothing here" block a list or a panel draws in place of its content.
///
/// Two of these existed — the prompt library's and the searchable picker's —
/// at two glyph sizes, two gaps and two type roles, for the same sentence in
/// the same situation. They are one component with a density, not two
/// components.
///
/// The full form is `10e` 「空状态」: a boxed, full-width block with a grey
/// glyph, a title, an optional line of explanation and an optional single
/// action. The glyph carries no accent and no circular backing — an empty
/// state is not a thing that happened, and colouring it makes it look like
/// one. The action is deliberately the *secondary* form: the accent-filled CTA
/// belongs to the page's own toolbar, and two of them on a screen with nothing
/// in it is a screen arguing with itself.
///
/// Deliberately *not* the same thing as the discovery dialog's full-page state
/// view, which carries its own artwork and fills a dialog body. Folding that
/// in here would be a redesign of it rather than a de-duplication of this.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    this.action,
    this.compact = false,
  });

  final IconData icon;

  /// The one line that says what is missing.
  final String label;

  /// Why it is missing, or what to do about it. Capped at the spec's 240 so it
  /// breaks into two or three short lines rather than one long one.
  final String? description;

  /// A single way out. Pass an `AppButton` in its secondary form — see the
  /// class doc for why it is not the filled one.
  final Widget? action;

  /// Sized for a list *inside* another control — a picker's dialog — rather
  /// than one filling a panel of its own. Drops the box, the description and
  /// the action: at that size the block is a caption, not a state.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (compact) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: colorScheme.outlineVariant),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return AppCard(
      outlined: true,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `outline`, not `outlineVariant`: the spec's `#c0c6d8` is this
            // rung of the ramp exactly, and the one below it is the hairline
            // a divider is drawn in — invisible at 40px.
            Icon(icon, size: 40, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  // The spec sets 11.5/400 against a ramp of five greys; the
                  // app has three, and `bodySmall` is 12/400. Half a pixel,
                  // and the weight — which is the part that carries — matches.
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                    height: 1.55,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
