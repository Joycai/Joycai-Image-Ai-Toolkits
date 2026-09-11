import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../services/database_service.dart';
import '../../../widgets/app_snackbar.dart';
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

      content = ReorderableListView.builder(
        padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, bottom),
        itemCount: prompts.length,
        buildDefaultDragHandles: false,
        onReorderItem: (oldIndex, newIndex) => _reorder(prompts, oldIndex, newIndex),
        proxyDecorator: (child, index, animation) =>
            promptDragProxyDecorator(child, index, animation, gap: _kCardGap),
        itemBuilder: (context, index) {
          final systemPrompt = prompts[index];
          final id = systemPrompt.id!;
          final isExpanded = _expandedSysPromptIds.contains(id);
          final isSelected = widget.selectedIds.contains(id);

          // Map to Prompt for PromptCard
          final promptForCard = Prompt(
            id: systemPrompt.id,
            title: systemPrompt.title,
            content: systemPrompt.content,
            isMarkdown: systemPrompt.isMarkdown,
            tags: systemPrompt.tags,
          );

          return Padding(
            key: ValueKey('sys_$id'),
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
