import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/tag.dart';
import '../../../services/database_service.dart';
import '../prompt_reorder.dart';
import 'prompt_library_parts.dart';

const double _kCardGap = 8;

/// The Categories view (`C1 · 1b` 分类视图): one 52px panel card per
/// category — grip, its 20px identity circle, name and prompt count, edit and
/// delete — reorderable by the grip.
class TagManagementList extends StatefulWidget {
  final List<PromptTag> tags;
  final VoidCallback onRefresh;
  final Function(AppLocalizations, {PromptTag? tag}) onShowEditDialog;
  final Function(AppLocalizations, PromptTag tag) onConfirmDelete;

  /// Number of prompts in each category, keyed by tag id.
  final Map<int, int> promptCounts;

  const TagManagementList({
    super.key,
    required this.tags,
    required this.onRefresh,
    required this.onShowEditDialog,
    required this.onConfirmDelete,
    this.promptCounts = const {},
  });

  @override
  State<TagManagementList> createState() => _TagManagementListState();
}

class _TagManagementListState extends State<TagManagementList> {
  final DatabaseService _db = DatabaseService();
  List<PromptTag>? _optimistic;

  @override
  void didUpdateWidget(TagManagementList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _optimistic;
    if (pending == null) return;
    final sameSet = pending.length == widget.tags.length &&
        pending.map((t) => t.id).toSet().containsAll(widget.tags.map((t) => t.id));
    var sameOrder = sameSet;
    for (int i = 0; sameOrder && i < pending.length; i++) {
      sameOrder = pending[i].id == widget.tags[i].id;
    }
    if (!sameSet || sameOrder) _optimistic = null;
  }

  Future<void> _reorder(List<PromptTag> tags, int oldIndex, int newIndex) async {
    final next = reorderedCopy(tags, oldIndex, newIndex);
    setState(() => _optimistic = next);
    await _db.updateTagOrder(next.map((t) => t.id!).toList());
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final phone = Responsive.isMobile(context);
    final pending = _optimistic;
    final tags = pending != null && pending.length == widget.tags.length ? pending : widget.tags;
    final horizontal = phone ? 12.0 : 20.0;

    final list = ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 12),
      itemCount: tags.length,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) => _reorder(tags, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) =>
          promptDragProxyDecorator(child, index, animation, gap: _kCardGap),
      itemBuilder: (context, index) {
        final tag = tags[index];
        final count = widget.promptCounts[tag.id] ?? 0;

        return Padding(
          key: ValueKey('tag_${tag.id}'),
          padding: const EdgeInsets.only(bottom: _kCardGap),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                PromptDragHandle(index: index, enabled: true, onBlockedTap: () {}),
                const SizedBox(width: AppSpace.s10),
                PromptCategoryDot(color: Color(tag.color), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          tag.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.promptCount(count),
                        style: textTheme.labelSmall!.mono.copyWith(
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _RowGlyph(
                  icon: Icons.edit_outlined,
                  tooltip: l10n.edit,
                  color: scheme.onSurfaceVariant,
                  onPressed: () => widget.onShowEditDialog(l10n, tag: tag),
                ),
                _RowGlyph(
                  icon: Icons.delete_outline,
                  tooltip: l10n.delete,
                  color: scheme.error,
                  onPressed: () => widget.onConfirmDelete(l10n, tag),
                ),
              ],
            ),
          ),
        );
      },
    );

    // What deleting a category does, stated once at the foot of the column
    // rather than only inside the confirmation.
    return Column(
      children: [
        Expanded(child: list),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpace.s10,
            horizontal,
            AppSpace.s10 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Text(
            l10n.categoryDeleteNote,
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _RowGlyph extends StatelessWidget {
  const _RowGlyph({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSize.compact,
      height: AppSize.compact,
      child: IconButton(
        icon: Icon(icon, size: AppSize.iconMd),
        color: color,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSize.compact, AppSize.compact),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
