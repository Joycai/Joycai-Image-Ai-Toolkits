import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/tag.dart';
import '../../../widgets/scroll_edge_fade.dart';
import 'prompt_library_parts.dart';

/// The horizontal category filter (`C1 · 1c`): a 52px column-coloured strip
/// of pills under the phone's tabs, and under the tablet's header, where the
/// sidebar is too narrow to be the only way in.
///
/// "All" leads with the library's total; each category chip carries its 6px
/// identity dot. The trailing edge fades while there is more to scroll.
class PromptCategoryStrip extends StatelessWidget {
  const PromptCategoryStrip({
    super.key,
    required this.tags,
    required this.selectedFilterTagIds,
    required this.totalCount,
    required this.onTagToggle,
    required this.onClear,
    this.chipHeight = AppSize.compact,
  });

  static const double height = 52;

  final List<PromptTag> tags;
  final Set<int> selectedFilterTagIds;
  final int totalCount;
  final ValueChanged<int> onTagToggle;
  final VoidCallback onClear;

  /// 28 beside a pointer, 32 under a finger.
  final double chipHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ScrollEdgeFade(
        axis: Axis.horizontal,
        extent: AppSize.control,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
          itemCount: tags.length + 1,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Center(
                child: PromptCategoryChip(
                  label: l10n.filterAll,
                  count: totalCount,
                  selected: selectedFilterTagIds.isEmpty,
                  onTap: onClear,
                  height: chipHeight,
                ),
              );
            }
            final tag = tags[index - 1];
            return Center(
              child: PromptCategoryChip(
                label: tag.name,
                color: Color(tag.color),
                selected: selectedFilterTagIds.contains(tag.id),
                onTap: () => onTagToggle(tag.id!),
                height: chipHeight,
              ),
            );
          },
        ),
      ),
    );
  }
}
