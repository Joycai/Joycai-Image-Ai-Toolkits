import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';

/// Small pieces the Prompt Library (`C1`) draws in more than one place.
///
/// Category colours are **identity** colours: they tell categories apart and
/// say nothing about state, so they never follow the accent and never tint a
/// whole row — only a dot. Filtering and selection are the accent's job, and
/// a row washed in its category colour would collide with both.

/// A category's identity dot.
class PromptCategoryDot extends StatelessWidget {
  const PromptCategoryDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

/// A selectable category pill (`C1 · 1c` strip, `1d` dialogs): r999, a
/// hairline and a 6px identity dot at rest; the accent wash, ring and deep ink
/// when chosen.
class PromptCategoryChip extends StatelessWidget {
  const PromptCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.count,
    this.height = AppSize.compact,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The category's identity colour. Null draws no dot — the "All" chip.
  final Color? color;

  /// A trailing mono count.
  final int? count;
  final double height;

  static TextStyle labelStyle(BuildContext context, {required bool selected}) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = selected ? scheme.onAccentTint : scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(AppRadius.pill);

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.hover),
        curve: AppMotion.quick,
        height: height,
        decoration: BoxDecoration(
          color: selected ? scheme.accentTint : scheme.surface,
          borderRadius: radius,
          border: Border.all(color: selected ? scheme.accentRing : scheme.outlineVariant),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (color != null) ...[
                    PromptCategoryDot(color: color!, size: 6),
                    const SizedBox(width: AppSpace.s6),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: labelStyle(context, selected: selected).copyWith(color: ink),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: AppSpace.s6),
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(color: ink),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A system template's type, as the pair the design gives it: the refiner in
/// the accent's wash, batch rename in the information container.
({IconData icon, Color background, Color foreground, Color glyph, String label}) promptTemplateTypeStyle(
  BuildContext context,
  String type,
) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = context.semantic;
  final l10n = AppLocalizations.of(context)!;
  if (type == 'rename') {
    return (
      icon: Icons.drive_file_rename_outline,
      background: semantic.infoContainer,
      foreground: semantic.onInfoContainer,
      glyph: semantic.info,
      label: l10n.typeRename,
    );
  }
  return (
    icon: Icons.text_snippet_outlined,
    background: scheme.accentTint,
    foreground: scheme.onAccentTint,
    glyph: scheme.primary,
    label: l10n.typeRefiner,
  );
}

/// The 28px r6 type glyph that fronts a template card (`C1 · 1b`).
class PromptTemplateTypeIcon extends StatelessWidget {
  const PromptTemplateTypeIcon({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final style = promptTemplateTypeStyle(context, type);
    return Container(
      width: AppSize.compact,
      height: AppSize.compact,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(style.icon, size: AppSize.iconMd, color: style.glyph),
    );
  }
}

/// The r4 type badge beside a template's title.
class PromptTemplateTypeBadge extends StatelessWidget {
  const PromptTemplateTypeBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final style = promptTemplateTypeStyle(context, type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        style.label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: style.foreground),
      ),
    );
  }
}

/// The 32px r6 accent tile that fronts a column heading (`C1 · 1a` sidebar,
/// `1b` categories header).
class PromptHeaderTile extends StatelessWidget {
  const PromptHeaderTile({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: AppSize.control,
      height: AppSize.control,
      decoration: BoxDecoration(
        color: scheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: AppSize.iconMd + 2, color: scheme.primary),
    );
  }
}

/// A list with nothing in it (`C1 · 1d` 空态): a quiet glyph, the line that
/// says what is missing, why, and the one way out — solid, because on an empty
/// library creating the first prompt *is* the screen's main action.
class PromptLibraryEmptyState extends StatelessWidget {
  const PromptLibraryEmptyState({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    this.icon = Icons.auto_awesome,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSpace.s28, color: scheme.outline),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: textTheme.titleLarge),
            const SizedBox(height: AppSpace.s6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            AppButton(label: actionLabel, icon: Icons.add, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}

/// Why dragging is off (`C1 · 1a` 底部通栏): a 36px warning strip across the
/// foot of the list while a filter or search narrows it. Dragging a list with
/// half its rows hidden has no honest drop position.
class PromptReorderBlockedStrip extends StatelessWidget {
  const PromptReorderBlockedStrip({super.key});

  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
      color: semantic.warningContainer,
      child: Row(
        children: [
          Icon(Icons.info_outline, size: AppSize.iconSm, color: semantic.onWarningContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.reorderDisabledWhileFiltered,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// The drag grip at a card's leading edge.
///
/// Live, it starts a drag at once from the handle ([ReorderableDragStartListener])
/// so a long press on the card stays free for selection. Blocked, it keeps its
/// place — the list does not jump when a filter comes on — but says why on a
/// tap, the same message the strip under the list carries.
class PromptDragHandle extends StatelessWidget {
  const PromptDragHandle({
    super.key,
    required this.index,
    required this.enabled,
    required this.onBlockedTap,
  });

  final int index;
  final bool enabled;
  final VoidCallback onBlockedTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final glyph = Icon(
      Icons.drag_indicator,
      size: AppSize.iconMd,
      color: enabled ? scheme.outline : scheme.outline.withValues(alpha: AppAlpha.disabled),
    );
    final box = SizedBox(width: 20, height: AppSize.compact, child: Center(child: glyph));

    if (!enabled) {
      return Tooltip(
        message: l10n.reorderDisabledWhileFiltered,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onBlockedTap, child: box),
      );
    }
    return Tooltip(
      message: l10n.channelReorderHandleTooltip,
      child: ReorderableDragStartListener(
        index: index,
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: box),
      ),
    );
  }
}

/// Decorates the card a drag has lifted (`C1 · 1a`): the accent edge and a
/// deep soft shadow, drawn over the card and not over the gap below it.
Widget promptDragProxyDecorator(Widget child, int index, Animation<double> animation, {double gap = 8}) {
  return Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final radius = BorderRadius.circular(AppRadius.control);
      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: gap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.22),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
              ),
            ),
            child,
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: gap,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: scheme.primary),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
