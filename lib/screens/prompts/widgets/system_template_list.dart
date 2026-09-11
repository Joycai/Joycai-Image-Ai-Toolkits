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

const double _kCardGap = 8;

class SystemTemplateList extends StatefulWidget {
  final List<SystemPrompt> prompts;
  final String searchQuery;
  final VoidCallback onRefresh;
  final Function(AppLocalizations, {SystemPrompt? prompt}) onShowEditDialog;
  final Function(AppLocalizations, dynamic prompt, {required bool isSystem}) onConfirmDelete;
  final Widget? header;

  final Set<int> selectedIds;
  final bool isSelectionMode;
  final Function(int) onToggleSelection;
  final Function(int) onEnterSelectionMode;

  /// Every template in its stored order. [prompts] is narrowed by template
  /// type; a drag inside that view is folded back into this order before it
  /// is written, so the other type's templates keep their places.
  final List<SystemPrompt>? allPrompts;

  const SystemTemplateList({
    super.key,
    required this.prompts,
    required this.searchQuery,
    required this.onRefresh,
    required this.onShowEditDialog,
    required this.onConfirmDelete,
    this.header,
    required this.selectedIds,
    required this.isSelectionMode,
    required this.onToggleSelection,
    required this.onEnterSelectionMode,
    this.allPrompts,
  });

  @override
  State<SystemTemplateList> createState() => _SystemTemplateListState();
}

class _SystemTemplateListState extends State<SystemTemplateList> {
  final DatabaseService _db = DatabaseService();
  final Set<int> _expandedSysPromptIds = {};
  final PromptReorderFocus _reorderFocus = PromptReorderFocus();
  List<SystemPrompt>? _optimistic;

  @override
  void didUpdateWidget(SystemTemplateList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _optimistic;
    if (pending == null) return;
    if (!_sameIdSet(pending, widget.prompts) || _sameOrder(pending, widget.prompts)) {
      _optimistic = null;
    }
  }

  static bool _sameIdSet(List<SystemPrompt> a, List<SystemPrompt> b) =>
      a.length == b.length && a.map((p) => p.id).toSet().containsAll(b.map((p) => p.id));

  static bool _sameOrder(List<SystemPrompt> a, List<SystemPrompt> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _showBlocked() {
    AppSnackBar.info(context, AppLocalizations.of(context)!.reorderDisabledWhileFiltered);
  }

  Future<void> _reorder(List<SystemPrompt> prompts, int oldIndex, int newIndex) async {
    if (widget.searchQuery.isNotEmpty) {
      _showBlocked();
      return;
    }
    final next = reorderedCopy(prompts, oldIndex, newIndex);
    setState(() => _optimistic = next);
    final nextIds = next.map((p) => p.id!).toList();
    final all = widget.allPrompts;
    await _db.updateSystemPromptOrder(
      all == null ? nextIds : mergeSubsetOrder(all.map((p) => p.id!).toList(), nextIds),
    );
    widget.onRefresh();
  }

  /// The stored order with the order on screen folded in — the two differ
  /// between a move and the reload that carries it, and a second move in that
  /// moment must build on the first.
  List<int> _fullIds(List<SystemPrompt> shown) {
    final shownIds = [for (final p in shown) p.id!];
    final all = widget.allPrompts;
    return all == null ? shownIds : mergeSubsetOrder([for (final p in all) p.id!], shownIds);
  }

  /// Writes [nextIds], the whole stored order, showing [shown] in it at once.
  Future<void> _writeOrder(List<SystemPrompt> shown, List<int> nextIds) async {
    final byId = {for (final p in shown) p.id!: p};
    setState(() => _optimistic = [for (final i in nextIds) if (byId.containsKey(i)) byId[i]!]);
    await _db.updateSystemPromptOrder(nextIds);
    widget.onRefresh();
  }

  /// Move to top / bottom of every template, as the user list does.
  Future<void> _moveToEdge(List<SystemPrompt> shown, int id, {required bool toEnd}) =>
      _writeOrder(shown, moveIdToEdge(_fullIds(shown), id, toEnd: toEnd));

  /// Move up / Move down and Ctrl+↑ / Ctrl+↓: past the template the user sees
  /// next to it, under a type narrowing or a search too, trading places with
  /// it in the full order.
  Future<void> _moveStep(List<SystemPrompt> shown, int id, {required bool down}) => _writeOrder(
        shown,
        moveIdPastVisibleNeighbour(_fullIds(shown), [for (final p in shown) p.id!], id, down: down),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final phone = Responsive.isMobile(context);
    final pending = _optimistic;
    final prompts = pending != null && _sameIdSet(pending, widget.prompts) ? pending : widget.prompts;

    Widget content;
    if (prompts.isEmpty && widget.searchQuery.isEmpty) {
      content = PromptLibraryEmptyState(
        title: l10n.noPromptsSaved,
        description: l10n.addSystemTemplateHint,
        actionLabel: l10n.newTemplate,
        onAction: () => widget.onShowEditDialog(l10n),
      );
    } else {
      final canDrag = widget.searchQuery.isEmpty && !widget.isSelectionMode;
      final horizontal = phone ? 12.0 : 20.0;
      final bottom = 12 +
          MediaQuery.paddingOf(context).bottom +
          (phone && widget.isSelectionMode ? PromptSelectionCapsule.height + 28 : 0);

      // `00d · 1a`: the gap the list opens is the drop target, and says where.
      content = AppReorderGap(
        itemCount: prompts.length,
        touch: phone,
        slotPadding: const EdgeInsets.only(bottom: _kCardGap),
        builder: (context, gap) {
          final reorder = gap.onReorderItem((oldIndex, newIndex) => _reorder(prompts, oldIndex, newIndex));
          // A move from a card's menu or keys, confirmed and announced as a
          // drop at [target] would be.
          void moveTo(int index, int target, Future<void> Function() move) =>
              gap.onReorderItem((_, _) => move())(index, target);
          final fullIds = (widget.allPrompts ?? prompts).map((p) => p.id).toList();
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
              final systemPrompt = prompts[index];
              final id = systemPrompt.id!;
              final isExpanded = _expandedSysPromptIds.contains(id);
              final isSelected = widget.selectedIds.contains(id);
              final selecting = widget.isSelectionMode;
              final last = prompts.length - 1;
              final isFirst = fullIds.isNotEmpty && fullIds.first == id;
              final isLast = fullIds.isNotEmpty && fullIds.last == id;

              // Map to Prompt for PromptCard
              final promptForCard = Prompt(
                id: systemPrompt.id,
                title: systemPrompt.title,
                content: systemPrompt.content,
                isMarkdown: systemPrompt.isMarkdown,
                tags: systemPrompt.tags,
              );

              return gap.item(
                key: ValueKey('sys_$id'),
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
                      prompt: promptForCard,
                      isExpanded: isExpanded,
                      selectionMode: widget.isSelectionMode,
                      selected: isSelected,
                      onLongPress: () => widget.onEnterSelectionMode(id),
                      onToggle: widget.isSelectionMode
                          ? () => widget.onToggleSelection(id)
                          : () => setState(() {
                                if (isExpanded) {
                                  _expandedSysPromptIds.remove(id);
                                } else {
                                  _expandedSysPromptIds.add(id);
                                }
                              }),
                      dragHandle: PromptDragHandle(index: index, enabled: canDrag, onBlockedTap: _showBlocked),
                      leading: PromptTemplateTypeIcon(type: systemPrompt.type),
                      badge: PromptTemplateTypeBadge(type: systemPrompt.type),
                      showCategory: true,
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
                            Clipboard.setData(ClipboardData(text: systemPrompt.content));
                            AppSnackBar.info(context, l10n.copiedToClipboard(systemPrompt.title));
                          },
                        ),
                        PromptCardAction(
                          icon: Icons.edit_outlined,
                          label: l10n.edit,
                          onPressed: () => widget.onShowEditDialog(l10n, prompt: systemPrompt),
                        ),
                        PromptCardAction(
                          icon: Icons.delete_outline,
                          label: l10n.delete,
                          danger: true,
                          onPressed: () => widget.onConfirmDelete(l10n, systemPrompt, isSystem: true),
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

    if (widget.header != null) {
      return Column(
        children: [
          widget.header!,
          Expanded(child: content),
        ],
      );
    }
    return content;
  }
}
