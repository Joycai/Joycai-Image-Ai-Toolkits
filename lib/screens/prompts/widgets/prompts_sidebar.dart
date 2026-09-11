import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/tag.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/scroll_edge_fade.dart';
import 'prompt_library_parts.dart';

/// The category filter in the library's left column (`C1 · 1a`).
///
/// "All" with the library's total, then one 32px row per category with its
/// 8px identity dot and count. A filtering row takes the accent wash and deep
/// ink — the category colour stays in the dot, so "this is Portrait" and
/// "Portrait is on" never compete for the same paint.
///
/// While any category filters, a footer pinned under the list (it does not
/// scroll away) holds the Any / All match mode and Clear.
class PromptsSidebar extends StatelessWidget {
  final List<PromptTag> tags;
  final Set<int> selectedFilterTagIds;
  final ValueChanged<int> onTagToggle;
  final VoidCallback onClear;

  /// Number of prompts in the active list per tag id.
  final Map<int, int> tagCounts;

  /// Total number of prompts in the active list (the "All" entry count).
  final int totalCount;

  /// When multiple categories are selected: false = match any, true = match all.
  final bool matchAll;
  final ValueChanged<bool>? onMatchModeChanged;

  /// How many prompts the active filter matches, for the footer's summary.
  final int? matchCount;

  const PromptsSidebar({
    super.key,
    required this.tags,
    required this.selectedFilterTagIds,
    required this.onTagToggle,
    required this.onClear,
    this.tagCounts = const {},
    this.totalCount = 0,
    this.matchAll = false,
    this.onMatchModeChanged,
    this.matchCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final allSelected = selectedFilterTagIds.isEmpty;

    return Column(
      children: [
        Expanded(
          child: ScrollEdgeFade(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
              children: [
                _SidebarRow(
                  leading: Icon(
                    Icons.apps,
                    size: AppSize.iconMd,
                    color: allSelected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  label: l10n.filterAll,
                  count: totalCount,
                  selected: allSelected,
                  onTap: onClear,
                  bottomGap: 2,
                ),
                for (final tag in tags)
                  _SidebarRow(
                    leading: PromptCategoryDot(color: Color(tag.color)),
                    label: tag.name,
                    count: tagCounts[tag.id] ?? 0,
                    selected: selectedFilterTagIds.contains(tag.id),
                    onTap: () => onTagToggle(tag.id!),
                  ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: AppMotion.durationOf(context, AppMotion.state),
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: allSelected
                ? const SizedBox(width: double.infinity)
                : _FilterFooter(
                    count: selectedFilterTagIds.length,
                    matchCount: matchCount,
                    matchAll: matchAll,
                    onMatchModeChanged: onMatchModeChanged,
                    onClear: onClear,
                  ),
          ),
        ),
      ],
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.leading,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.bottomGap = 1,
  });

  final Widget leading;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.sm);

    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.s6, 0, AppSpace.s6, bottomGap),
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.hover),
        curve: AppMotion.quick,
        decoration: BoxDecoration(
          color: selected ? scheme.accentTint : Colors.transparent,
          borderRadius: radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Semantics(
              selected: selected,
              button: true,
              child: SizedBox(
                height: AppSize.control,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                  child: Row(
                    children: [
                      // One column for the glyph and the dots, so the labels
                      // line up under "All".
                      SizedBox(width: AppSize.iconMd, child: Center(child: leading)),
                      const SizedBox(width: AppSpace.s10),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                            color: selected ? scheme.onAccentTint : scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$count',
                        style: textTheme.labelSmall!.mono.copyWith(
                          fontWeight: FontWeight.w400,
                          color: selected ? scheme.onAccentTint : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterFooter extends StatelessWidget {
  const _FilterFooter({
    required this.count,
    required this.matchCount,
    required this.matchAll,
    required this.onMatchModeChanged,
    required this.onClear,
  });

  final int count;
  final int? matchCount;
  final bool matchAll;
  final ValueChanged<bool>? onMatchModeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onMatchModeChanged != null) ...[
            Row(
              children: [
                Text(
                  l10n.matchModeLabel,
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppSegmentedControl<bool>(
                    segments: [
                      AppSegment(value: false, label: l10n.matchAny),
                      AppSegment(value: true, label: l10n.matchAllTags),
                    ],
                    value: matchAll,
                    onChanged: onMatchModeChanged!,
                    expand: true,
                    compact: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  matchCount == null
                      ? l10n.selectedCount(count)
                      : l10n.promptFilterSummary(count, matchCount!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              AppButton(
                label: l10n.clear,
                variant: AppButtonVariant.destructiveText,
                size: AppButtonSize.compact,
                onPressed: onClear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
