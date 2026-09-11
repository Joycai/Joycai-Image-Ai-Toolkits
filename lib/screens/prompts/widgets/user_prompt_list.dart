import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../services/database_service.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/drag/app_drag_lift.dart';
import '../../../widgets/drag/app_reorder_gap.dart';
import '../../../widgets/prompt_card.dart';
import '../prompt_reorder.dart';
import 'prompt_library_parts.dart';
import 'prompt_selection_capsule.dart';

/// Gap under each card; the lifted card, the drop gap and the confirmation
/// ring all leave it out.
const double _kCardGap = 8;

class UserPromptList extends StatefulWidget {
  final List<Prompt> prompts;
  final String searchQuery;
  final Set<int> selectedFilterTagIds;
  final VoidCallback onRefresh;
  final Function(AppLocalizations, {Prompt? prompt}) onShowEditDialog;
  final Function(AppLocalizations, dynamic prompt, {required bool isSystem}) onConfirmDelete;

  final Set<int> selectedIds;
  final bool isSelectionMode;
  final Function(int) onToggleSelection;
  final Function(int) onEnterSelectionMode;

  /// The whole library in its stored order. Move to top / bottom work on this
  /// even while [prompts] is a filtered view of it, so the order written back
  /// is always the full one. Null falls back to [prompts].
  final List<Prompt>? allPrompts;

  const UserPromptList({
    super.key,
    required this.prompts,
    required this.searchQuery,
    required this.selectedFilterTagIds,
    required this.onRefresh,
    required this.onShowEditDialog,
    required this.onConfirmDelete,
    required this.selectedIds,
    required this.isSelectionMode,
    required this.onToggleSelection,
    required this.onEnterSelectionMode,
    this.allPrompts,
  });

  @override
  State<UserPromptList> createState() => _UserPromptListState();
}

class _UserPromptListState extends State<UserPromptList> {
  final DatabaseService _db = DatabaseService();
  final Set<int> _expandedPromptIds = {};
  final PromptReorderFocus _reorderFocus = PromptReorderFocus();

  /// The order just written, shown until the reload carrying it arrives, so a
  /// dropped card does not snap back for a frame.
  List<Prompt>? _optimistic;

  bool get _filtered => widget.searchQuery.isNotEmpty || widget.selectedFilterTagIds.isNotEmpty;

  @override
  void didUpdateWidget(UserPromptList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _optimistic;
    if (pending != null && !_sameIdSet(pending, widget.prompts)) {
      _optimistic = null;
    } else if (pending != null && _sameOrder(pending, widget.prompts)) {
      _optimistic = null;
    }
  }

  static bool _sameIdSet(List<Prompt> a, List<Prompt> b) =>
      a.length == b.length && a.map((p) => p.id).toSet().containsAll(b.map((p) => p.id));

  static bool _sameOrder(List<Prompt> a, List<Prompt> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _showBlocked() {
    AppSnackBar.info(context, AppLocalizations.of(context)!.reorderDisabledWhileFiltered);
  }

  Future<void> _reorder(List<Prompt> prompts, int oldIndex, int newIndex) async {
    if (_filtered) {
      _showBlocked();
      return;
    }
    final next = reorderedCopy(prompts, oldIndex, newIndex);
    setState(() => _optimistic = next);
    await _db.updatePromptOrder(next.map((p) => p.id!).toList());
    widget.onRefresh();
  }

  /// The stored order with the order on screen folded in — the two differ
  /// between a move and the reload that carries it, and a second move in that
  /// moment must build on the first.
  List<int> _fullIds(List<Prompt> shown) {
    final shownIds = [for (final p in shown) p.id!];
    final all = widget.allPrompts;
    return all == null ? shownIds : mergeSubsetOrder([for (final p in all) p.id!], shownIds);
  }

  /// Writes [nextIds], the whole stored order, showing [shown] in it at once.
  Future<void> _writeOrder(List<Prompt> shown, List<int> nextIds) async {
    final byId = {for (final p in shown) p.id!: p};
    setState(() => _optimistic = [for (final i in nextIds) if (byId.containsKey(i)) byId[i]!]);
    await _db.updatePromptOrder(nextIds);
    widget.onRefresh();
  }

  Future<void> _moveToEdge(List<Prompt> shown, int id, {required bool toEnd}) =>
      _writeOrder(shown, moveIdToEdge(_fullIds(shown), id, toEnd: toEnd));

  /// Move up / Move down and Ctrl+↑ / Ctrl+↓: past the card the user sees
  /// next to it, under a filter too — `00d` sends a filtered list's reordering
  /// here — trading places with it in the full order.
  Future<void> _moveStep(List<Prompt> shown, int id, {required bool down}) => _writeOrder(
        shown,
        moveIdPastVisibleNeighbour(_fullIds(shown), [for (final p in shown) p.id!], id, down: down),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final phone = Responsive.isMobile(context);
    final pending = _optimistic;
    final prompts = pending != null && _sameIdSet(pending, widget.prompts) ? pending : widget.prompts;

    if (prompts.isEmpty) {
      return PromptLibraryEmptyState(
        title: l10n.noPromptsSaved,
        description: l10n.promptLibraryEmptyHint,
        actionLabel: l10n.createFirstPrompt,
        onAction: () => widget.onShowEditDialog(l10n),
      );
    }

    final fullIds = (widget.allPrompts ?? prompts).map((p) => p.id).toList();
    final canDrag = !_filtered && !widget.isSelectionMode;
    final horizontal = phone ? 12.0 : 20.0;
    final bottom = 12 +
        MediaQuery.paddingOf(context).bottom +
        (phone && widget.isSelectionMode ? PromptSelectionCapsule.height + 28 : 0);

    // `00d · 1a`: the gap the list opens is the drop target, and says where.
    return AppReorderGap(
      itemCount: prompts.length,
      touch: phone,
      slotPadding: const EdgeInsets.only(bottom: _kCardGap),
      builder: (context, gap) {
        final reorder = gap.onReorderItem((oldIndex, newIndex) => _reorder(prompts, oldIndex, newIndex));
        // A move from a card's menu or keys, confirmed and announced as a drop
        // at [target] would be.
        void moveTo(int index, int target, Future<void> Function() move) =>
            gap.onReorderItem((_, _) => move())(index, target);
        return ReorderableListView.builder(
          padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, bottom),
          itemCount: prompts.length,
          buildDefaultDragHandles: false,
          onReorderItem: reorder,
          // `1f` 到时：触觉 medium + 抬起.
          onReorderStart: gap.onReorderStart((_) {
            if (phone) HapticFeedback.mediumImpact();
          }),
          proxyDecorator: (child, index, animation) => appReorderLiftDecorator(
            child,
            index,
            animation,
            slotPadding: const EdgeInsets.only(bottom: _kCardGap),
          ),
          itemBuilder: (context, index) {
            final prompt = prompts[index];
            final id = prompt.id!;
            final isExpanded = _expandedPromptIds.contains(id);
            final isSelected = widget.selectedIds.contains(id);
            final isFirst = fullIds.isNotEmpty && fullIds.first == id;
            final isLast = fullIds.isNotEmpty && fullIds.last == id;
            final selecting = widget.isSelectionMode;
            final last = prompts.length - 1;

            return gap.item(
              key: ValueKey('user_$id'),
              index: index,
              child: PromptReorderKeys(
                focus: _reorderFocus,
                id: id,
                onMove: selecting
                    ? null
                    : (delta) {
                        final target = index + delta;
                        if (target < 0 || target > last) return;
                        moveTo(index, target, () => _moveStep(prompts, id, down: delta > 0));
                      },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: _kCardGap),
                  child: PromptCard(
                    prompt: prompt,
                    isExpanded: isExpanded,
                    selectionMode: widget.isSelectionMode,
                    selected: isSelected,
                    onLongPress: () => widget.onEnterSelectionMode(id),
                    onToggle: widget.isSelectionMode
                        ? () => widget.onToggleSelection(id)
                        : () => setState(() {
                              if (isExpanded) {
                                _expandedPromptIds.remove(id);
                              } else {
                                _expandedPromptIds.add(id);
                              }
                            }),
                    dragHandle: PromptDragHandle(index: index, enabled: canDrag, onBlockedTap: _showBlocked),
                    onMoveUp: (selecting || index == 0)
                        ? null
                        : () => moveTo(index, index - 1, () => _moveStep(prompts, id, down: false)),
                    onMoveDown: (selecting || index == last)
                        ? null
                        : () => moveTo(index, index + 1, () => _moveStep(prompts, id, down: true)),
                    onMoveToTop: (isFirst || selecting)
                        ? null
                        : () => moveTo(index, 0, () => _moveToEdge(prompts, id, toEnd: false)),
                    onMoveToBottom: (isLast || selecting)
                        ? null
                        : () => moveTo(index, last, () => _moveToEdge(prompts, id, toEnd: true)),
                    menuActions: [
                      PromptCardAction(
                        icon: Icons.copy_all,
                        label: l10n.copyPrompt,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: prompt.content));
                          AppSnackBar.info(context, l10n.copiedToClipboard(prompt.title));
                        },
                      ),
                      PromptCardAction(
                        icon: Icons.edit_outlined,
                        label: l10n.edit,
                        onPressed: () => widget.onShowEditDialog(l10n, prompt: prompt),
                      ),
                      PromptCardAction(
                        icon: Icons.delete_outline,
                        label: l10n.delete,
                        danger: true,
                        onPressed: () => widget.onConfirmDelete(l10n, prompt, isSystem: false),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
