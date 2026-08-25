import 'package:flutter/material.dart';

import '../core/app_semantic_colors.dart';
import '../core/design_tokens.dart';

/// What a badge is reporting.
///
/// Deliberately about *condition*, not about any one screen's vocabulary: the
/// task queue, the downloader and the model-discovery dialog all draw the same
/// four states under different names, and each had grown its own colour switch
/// to say so.
enum AppStatusKind {
  /// Work in flight. The accent, because this is the app's own activity and
  /// the seed colour is what the user picked to represent it — and because
  /// green/amber/red are spoken for by outcomes.
  running,

  /// Queued, not started. Neutral on purpose: a pending item is not a
  /// condition to react to, and colouring it would put it in the same visual
  /// class as things that are.
  pending,

  /// Finished successfully.
  done,

  /// Not broken, but needing the user's attention before it settles — an edit
  /// that has not been saved, a change waiting to be confirmed. Amber, which
  /// is the one hue between [pending]'s neutral and [failed]'s red, and the
  /// colour the spec's 未保存 / 待确认 pills are drawn in.
  warning,

  /// Finished badly.
  failed,
}

/// A pill stating a condition — "执行中", "已完成", "3 failed".
///
/// The colours come from [AppSemanticColors] and [ColorScheme], never from a
/// literal, which is the whole point: the four call sites this replaces had
/// four slightly different greens between them, and the amber ones each
/// carried their own hand-written light/dark branch.
class AppStatusBadge extends StatelessWidget {
  final String label;
  final AppStatusKind kind;

  /// Draws the leading dot. On for [AppStatusKind.running], where the dot is
  /// what distinguishes "working on it" from a settled state at a glance; off
  /// elsewhere, where the fill already says everything.
  final bool showDot;

  const AppStatusBadge({
    super.key,
    required this.label,
    required this.kind,
    this.showDot = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;

    // (background, foreground). Each pair is a container/on-container set, so
    // the label's contrast against its own fill is guaranteed rather than
    // hoped for — including at the four seeds whose primary is pale.
    final (Color background, Color foreground) = switch (kind) {
      AppStatusKind.running => (colorScheme.accentTint, colorScheme.onAccentTint),
      AppStatusKind.pending => (colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
      AppStatusKind.done => (semantic.successContainer, semantic.onSuccessContainer),
      AppStatusKind.warning => (semantic.warningContainer, semantic.onWarningContainer),
      // A wash of `error` rather than `errorContainer`. Material's dark
      // error container is a deep, near-solid red — beside the other three,
      // which are all light tints, a failed badge stopped reading as one of
      // the four states and started reading as an alert. The spec draws all
      // four at the same weight, and the state itself is what distinguishes
      // them, not how loudly each is painted.
      AppStatusKind.failed => (
          colorScheme.error.withValues(alpha: AppAlpha.tint),
          colorScheme.error,
        ),
    };

    final dot = kind == AppStatusKind.running && showDot;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            // The spec pulses this. It is drawn static here: a repeating
            // animation makes `pumpAndSettle` never return and leaves the
            // screenshot harness capturing whichever frame it lands on, so a
            // badge would produce a different PNG on every run for a reason
            // that has nothing to do with layout. The dot's presence already
            // carries the distinction; the motion was only ever emphasis.
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

/// A small filled circle holding a number — the count on a nav destination.
///
/// [color] defaults to the accent rather than to the spec's red. In this app
/// red already means *a task failed*, and the count this sits on is of work
/// **in flight**; painting it red would make a healthy busy queue read as a
/// broken one. Pass `colorScheme.error` where the number genuinely is a
/// failure count.
class AppCountBadge extends StatelessWidget {
  final int count;
  final Color? color;

  const AppCountBadge({super.key, required this.count, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = color ?? colorScheme.primary;

    return Container(
      // A minimum rather than a fixed size, so a three-digit queue grows into
      // a stadium instead of overflowing a circle.
      constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      // `Center` with both factors at 1, not `alignment:` on the Container.
      // An aligned Container expands to whatever width it is offered, and the
      // two places this badge goes — a Stack's Positioned in the nav rail, and
      // a Wrap — both offer it unbounded width. With `alignment` it came out
      // as a bar across the whole row.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          '$count',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              // White, not `onPrimary`: the badge is painted in the seed's own
              // primary, and under a pale seed Material pairs that with a dark
              // `onPrimary` which disappears against the accent here.
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      ),
    );
  }
}
