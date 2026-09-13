import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../models/pricing_group.dart';
import '../state/app_state.dart';
import 'app_button.dart';
import 'app_icon_button.dart';
import 'app_search_field.dart';
import 'app_section_label.dart';
import 'dashed_border.dart';
import 'drag/app_drag_lift.dart';
import 'drag/app_reorder_gap.dart';
import 'glass/app_glass_menu.dart';
import 'models/fee_group_dialogs.dart';
import 'models/fee_group_draft.dart';
import 'models/fee_group_edit_page.dart';
import 'models/fee_group_editor_fields.dart';
import 'models/fee_group_row.dart';

enum PricingGroupManagerMode {
  /// Embedded in a page that scrolls it — the usage screen's fee-group tab
  /// (`D2 · 1d`–`1h`). The heading with the counts, filter, reorder and New,
  /// then the list beside the editor (desktop) or with the editor inlined
  /// under the edited group (tablet). On a phone: the cards alone, the
  /// editor being a page of its own.
  section,

  /// A page of its own, scrolling its list under a fixed heading.
  fullPage,

  /// The body of the fee-management dialog (`D1a · 1d`): its own heading — the
  /// payments plate, the counts, Add and close — over a scrolling list with
  /// the editor inlined. Host it in an [AppDialog] with no title and a
  /// `maxHeight`.
  dialog,
}

/// Lists fee groups and edits them in place.
///
/// `D2 · 1d`: each group is one row — the name, how many models it prices
/// (or that none do), its rates as mono tags, and edit / delete. Selecting a
/// row opens it in the editor card: the right column on desktop, where a
/// dashed placeholder holds the column's place until then so the list never
/// moves; directly under the row on tablet and in the dialog. 「新建组」 opens
/// the same card empty. There is no second dialog.
///
/// `1g`: rows reorder by drag — the grip appears on hover, or always in the
/// reorder mode the header's button toggles — and by Alt+↑/↓ on the selected
/// group or the row's context menu. The order is stored and read wherever
/// groups are listed.
class PricingGroupManager extends StatefulWidget {
  final PricingGroupManagerMode mode;

  /// A group to open in its editor as soon as the list mounts — the usage
  /// page's 「去补档位」 lands here with the group whose rates fell short.
  final int? initialEditGroupId;

  /// The phone's explicit reorder mode (`1h`), toggled by the screen's
  /// header: rows show the grip and lift on a long press.
  final bool phoneReorder;

  const PricingGroupManager({
    super.key,
    this.mode = PricingGroupManagerMode.section,
    this.initialEditGroupId,
    this.phoneReorder = false,
  });

  @override
  State<PricingGroupManager> createState() => _PricingGroupManagerState();
}

/// The [_PricingGroupManagerState._editing] value for a group being added.
const Object _newGroup = Object();

class _PricingGroupManagerState extends State<PricingGroupManager> {
  /// Null, [_newGroup], or the id of the group open in the editor.
  Object? _editing;

  /// The open editor's draft, built for [_editing] and dropped when the
  /// target changes or a save lands.
  FeeGroupDraft? _draft;
  Object? _draftTarget;
  bool _saving = false;

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// `1g`: the header's reorder mode — grips always on show.
  bool _reorderMode = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.initialEditGroupId;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _draft?.dispose();
    super.dispose();
  }

  bool get _adding => identical(_editing, _newGroup);

  void _dropDraft() {
    _draft?.removeListener(_refresh);
    _draft?.dispose();
    _draft = null;
    _draftTarget = null;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Builds the draft for whatever [_editing] names, once its group is known.
  void _ensureDraft(List<PricingGroup> groups) {
    final target = _editing;
    if (target == null) {
      if (_draft != null) _dropDraft();
      return;
    }
    if (_draft != null && _draftTarget == target) return;
    _dropDraft();
    final group = target is int ? groups.firstWhere((g) => g.id == target) : null;
    _draft = FeeGroupDraft(group)..addListener(_refresh);
    _draftTarget = target;
  }

  /// Opens [target] in the editor. `1e`: switching groups swaps the card's
  /// content in place; unsaved edits ask first.
  Future<void> _open(Object target) async {
    if (_editing == target) return;
    final draft = _draft;
    if (draft != null && draft.isDirty) {
      final discard = await confirmDiscardFeeGroupDraft(context);
      if (!discard || !mounted) return;
    }
    setState(() {
      _dropDraft();
      _editing = target;
    });
  }

  void _close() {
    if (!mounted) return;
    setState(() {
      _dropDraft();
      _editing = null;
    });
  }

  Future<void> _save(AppState appState) async {
    final draft = _draft;
    if (draft == null || _saving || !draft.canSave) return;
    setState(() => _saving = true);
    await draft.save(appState);
    if (!mounted) return;
    // Saving is the end of the edit: the card closes and the list shows the
    // group as stored (a new one at the end of the list).
    setState(() {
      _saving = false;
      _dropDraft();
      _editing = null;
    });
  }

  Future<void> _delete(AppState appState, PricingGroup group, int modelCount) async {
    final deleted = await confirmDeleteFeeGroup(context, appState, group, modelCount: modelCount);
    if (deleted && _editing == group.id) _close();
  }

  void _move(AppState appState, int from, int to) {
    final count = appState.allPricingGroups.length;
    if (to < 0 || to >= count || from == to) return;
    appState.reorderPricingGroups(from, to);
  }

  /// Alt+↑/↓ on the selected group (`1g`, as the channel rail binds them).
  void _moveSelected(AppState appState, int delta) {
    final id = _editing;
    if (id is! int || _query.isNotEmpty) return;
    final index = appState.allPricingGroups.indexWhere((g) => g.id == id);
    if (index < 0) return;
    _move(appState, index, index + delta);
  }

  Future<void> _openPhoneEditor(PricingGroup? group) async {
    await FeeGroupEditPage.push(context, group: group);
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final groups = appState.allPricingGroups;
    final phone = Responsive.isMobile(context);

    // A group deleted while open simply closes its editor.
    if (_editing is int && !groups.any((g) => g.id == _editing)) _editing = null;
    if (!phone) _ensureDraft(groups);

    switch (widget.mode) {
      case PricingGroupManagerMode.dialog:
        final groupIds = {for (final g in groups) g.id};
        final pricedModels = appState.allModels.where((m) => groupIds.contains(m.feeGroupId)).length;
        return _shortcuts(
          appState,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeading(
                groupCount: groups.length,
                modelCount: pricedModels,
                onAdd: () => _open(_newGroup),
              ),
              const SizedBox(height: AppSpace.s16),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildList(context, appState, l10n, groups, inlineEditor: true),
                ),
              ),
            ],
          ),
        );
      case PricingGroupManagerMode.fullPage:
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: phone
              ? FloatingActionButton.extended(
                  onPressed: () => _openPhoneEditor(null),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.newFeeGroup),
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!phone)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _buildHeading(context, appState, l10n, groups),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: phone
                      ? _buildPhoneList(context, appState, l10n, groups)
                      : _shortcuts(appState, _buildBody(context, appState, l10n, groups)),
                ),
              ),
            ],
          ),
        );
      case PricingGroupManagerMode.section:
        if (phone) return _buildPhoneList(context, appState, l10n, groups);
        return _shortcuts(
          appState,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeading(context, appState, l10n, groups),
              const SizedBox(height: 14),
              _buildBody(context, appState, l10n, groups),
            ],
          ),
        );
    }
  }

  /// Alt+↑/↓ move the selected group; Esc closes the editor (`1e`).
  Widget _shortcuts(AppState appState, Widget child) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () => _moveSelected(appState, -1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () => _moveSelected(appState, 1),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_editing != null) _close();
        },
      },
      child: child,
    );
  }

  /// `1d` 头行: the caption over the mono counts, the filter, the reorder
  /// button (tint-selected in reorder mode) and 「新建组」 (tint-selected while
  /// adding — `1f` 「正在新建」).
  Widget _buildHeading(BuildContext context, AppState appState, AppLocalizations l10n, List<PricingGroup> groups) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final groupIds = {for (final g in groups) g.id};
    final pricedModels = appState.allModels.where((m) => groupIds.contains(m.feeGroupId)).length;
    final desktop = Responsive.isDesktop(context);
    final filtered = _query.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // `D2 · 1b`: the embedded list names itself with the tracked
              // caption, not a second page title under the canvas tabs.
              AppSectionLabel(l10n.feeGroups, padding: EdgeInsets.zero),
              const SizedBox(height: 2),
              Text(
                '${l10n.countGroups(groups.length)} · ${l10n.feeGroupModelCount(pricedModels)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (desktop) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            child: AppSearchField(
              controller: _searchCtrl,
              hint: l10n.filterFeeGroups,
              compact: true,
              onChanged: (q) => setState(() {
                _query = q.trim().toLowerCase();
                // `1g`: a filtered list cannot be reordered, so the mode ends.
                if (_query.isNotEmpty) _reorderMode = false;
              }),
            ),
          ),
        ],
        const SizedBox(width: 12),
        AppIconButton(
          icon: Icons.swap_vert,
          tooltip: l10n.reorderFeeGroups,
          selected: _reorderMode,
          onPressed: filtered || groups.length < 2 ? null : () => setState(() => _reorderMode = !_reorderMode),
        ),
        const SizedBox(width: 12),
        AppButton(
          label: l10n.newFeeGroup,
          icon: Icons.add,
          variant: _adding ? AppButtonVariant.tonal : AppButtonVariant.primary,
          onPressed: () => _open(_newGroup),
        ),
      ],
    );
  }

  /// Desktop: the list beside the editor or its placeholder, `1fr 1fr gap
  /// 20`; the two columns never move for each other. Below desktop: the
  /// list with the editor inlined under the edited row.
  Widget _buildBody(BuildContext context, AppState appState, AppLocalizations l10n, List<PricingGroup> groups) {
    if (!Responsive.isDesktop(context)) {
      return _buildList(context, appState, l10n, groups, inlineEditor: true);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildList(context, appState, l10n, groups, inlineEditor: false)),
        const SizedBox(width: 20),
        Expanded(
          child: _editing == null
              ? _Placeholder(reorder: _reorderMode)
              : _buildEditor(context, appState, l10n, groups),
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context, AppState appState, AppLocalizations l10n, List<PricingGroup> groups) {
    final draft = _draft;
    if (draft == null) return const SizedBox.shrink();
    final group = draft.group;
    return _EditorCard(
      key: ValueKey(_editing),
      draft: draft,
      saving: _saving,
      onCancel: _close,
      onSave: () => _save(appState),
      onDelete: group == null
          ? null
          : () => _delete(appState, group, _modelsByGroup(appState)[group.id]?.length ?? 0),
    );
  }

  Widget _buildList(
    BuildContext context,
    AppState appState,
    AppLocalizations l10n,
    List<PricingGroup> groups, {
    required bool inlineEditor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final adding = _adding;
    if (groups.isEmpty && !adding) return const _EmptyGroups();

    final filtered = _query.isNotEmpty;
    final visible = filtered ? groups.where((g) => g.name.toLowerCase().contains(_query)).toList() : groups;
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final canReorder = !filtered && groups.length > 1;
    final handle = !canReorder
        ? FeeGroupHandle.none
        : _reorderMode
            ? FeeGroupHandle.always
            : touch
                ? FeeGroupHandle.none
                : FeeGroupHandle.hover;
    final modelsByGroup = _modelsByGroup(appState);

    final Widget list = AppReorderGap(
      itemCount: visible.length,
      touch: touch,
      slotPadding: const EdgeInsets.only(bottom: AppSpace.s6),
      builder: (context, gap) => ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: visible.length,
        // The grip is ours (hover-revealed, whole row draggable), not the
        // framework's trailing handles.
        buildDefaultDragHandles: false,
        onReorderItem: gap.onReorderItem((oldIndex, newIndex) {
          // Only reachable unfiltered, where `visible` is the stored order.
          if (canReorder) _move(appState, oldIndex, newIndex);
        }),
        onReorderStart: gap.onReorderStart((_) {
          if (touch) HapticFeedback.mediumImpact();
        }),
        proxyDecorator: (child, index, animation) => appReorderLiftDecorator(
          child,
          index,
          animation,
          slotPadding: const EdgeInsets.only(bottom: AppSpace.s6),
        ),
        itemBuilder: (context, index) {
          final group = visible[index];
          final models = modelsByGroup[group.id] ?? const <String>[];
          final storedIndex = groups.indexWhere((g) => g.id == group.id);

          final row = FeeGroupRow(
            group: group,
            models: models,
            selected: _editing == group.id,
            handle: handle,
            onTap: () => _open(group.id!),
            onDelete: () => _delete(appState, group, models.length),
            onContextMenu: (position) => showAppGlassMenu(
              context,
              position: position,
              entries: [
                AppGlassMenuItem(icon: Icons.edit_outlined, label: l10n.edit, onSelected: () => _open(group.id!)),
                AppGlassMenuItem(
                  icon: Icons.arrow_upward,
                  label: l10n.moveUp,
                  enabled: canReorder && storedIndex > 0,
                  onSelected: () => _move(appState, storedIndex, storedIndex - 1),
                ),
                AppGlassMenuItem(
                  icon: Icons.arrow_downward,
                  label: l10n.moveDown,
                  enabled: canReorder && storedIndex < groups.length - 1,
                  onSelected: () => _move(appState, storedIndex, storedIndex + 1),
                ),
                const AppGlassMenuDivider(),
                AppGlassMenuItem(
                  icon: Icons.delete_outline,
                  label: l10n.delete,
                  danger: true,
                  onSelected: () => _delete(appState, group, models.length),
                ),
              ],
            ),
          );

          // `1h` 平板: the editor card sits right under the edited row and the
          // rows below move down for it.
          final Widget slot = Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s6),
            child: inlineEditor
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      row,
                      AnimatedSize(
                        duration: AppMotion.durationOf(context, AppMotion.state),
                        curve: AppMotion.enter,
                        alignment: Alignment.topCenter,
                        child: _editing == group.id
                            ? Padding(
                                padding: const EdgeInsets.only(top: AppSpace.s6),
                                child: _buildEditor(context, appState, l10n, groups),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  )
                : row,
          );

          // Whole-row drag, so the pointer never has to find the grip. Touch
          // has no hover to reveal it, so there the gesture is an explicit
          // 300ms long press.
          final Widget child = !canReorder
              ? slot
              : touch
                  ? AppLongPressDragStartListener(index: index, child: slot)
                  : ReorderableDragStartListener(index: index, child: slot);
          return gap.item(key: ValueKey(group.id), index: index, child: child);
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `1f`: the new group's card opens at the top of the list.
        if (adding && inlineEditor)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s6),
            child: _buildEditor(context, appState, l10n, groups),
          ),
        if (filtered && visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s16),
            child: Text(
              l10n.pickerNoMatches,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          list,
        // `1g`: what reordering needs, said once — and that a filtered list
        // cannot be reordered.
        if ((_reorderMode || filtered) && groups.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpace.s4),
                Expanded(
                  child: Text(
                    l10n.feeGroupReorderNote,
                    style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: AppType.proseHeight),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// `1h` 手机: the two-line cards on the canvas; a tap opens the page. In
  /// reorder mode the cards carry the grip and lift on a long press.
  Widget _buildPhoneList(BuildContext context, AppState appState, AppLocalizations l10n, List<PricingGroup> groups) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (groups.isEmpty) return const _EmptyGroups();

    final modelsByGroup = _modelsByGroup(appState);
    final reorder = widget.phoneReorder && groups.length > 1;

    final list = AppReorderGap(
      itemCount: groups.length,
      touch: true,
      slotPadding: const EdgeInsets.only(bottom: 8),
      builder: (context, gap) => ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: groups.length,
        buildDefaultDragHandles: false,
        onReorderItem: gap.onReorderItem((oldIndex, newIndex) {
          if (reorder) _move(appState, oldIndex, newIndex);
        }),
        onReorderStart: gap.onReorderStart((_) => HapticFeedback.mediumImpact()),
        proxyDecorator: (child, index, animation) => appReorderLiftDecorator(
          child,
          index,
          animation,
          slotPadding: const EdgeInsets.only(bottom: 8),
        ),
        itemBuilder: (context, index) {
          final group = groups[index];
          final row = Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FeeGroupRow(
              group: group,
              models: modelsByGroup[group.id] ?? const <String>[],
              phone: true,
              handle: reorder ? FeeGroupHandle.always : FeeGroupHandle.none,
              onTap: () => _openPhoneEditor(group),
            ),
          );
          return gap.item(
            key: ValueKey(group.id),
            index: index,
            child: reorder ? AppLongPressDragStartListener(index: index, child: row) : row,
          );
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        list,
        if (reorder)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s4, 0, AppSpace.s4, AppSpace.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpace.s4),
                Expanded(
                  child: Text(
                    l10n.feeGroupReorderHint,
                    style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: AppType.proseHeight),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Display names of the models pointing at each group, by group id.
  ///
  /// A group only means something through the models it prices, so the row
  /// says which ones — and a group no model uses says that, which is otherwise
  /// invisible from this screen.
  Map<int, List<String>> _modelsByGroup(AppState appState) {
    final map = <int, List<String>>{};
    for (final model in appState.allModels) {
      final groupId = model.feeGroupId;
      if (groupId != null) {
        (map[groupId] ??= []).add(model.modelName);
      }
    }
    return map;
  }
}

/// `D1a · 1d` 费用管理 heading: the 44 payments plate on the accent wash, the
/// title over the mono counts, Add and close.
class _DialogHeading extends StatelessWidget {
  const _DialogHeading({required this.groupCount, required this.modelCount, required this.onAdd});

  final int groupCount;
  final int modelCount;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.accentTint,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(Icons.payments_outlined, size: 24, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.feeManagement, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                '${l10n.countGroups(groupCount)} · ${l10n.feeGroupModelCount(modelCount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        AppButton(label: l10n.newFeeGroup, icon: Icons.add, onPressed: onAdd),
        const SizedBox(width: AppSpace.s6),
        IconButton(
          icon: const Icon(Icons.close, size: AppSize.iconMd),
          tooltip: l10n.close,
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: AppSize.iconButton, height: AppSize.iconButton),
          style: IconButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }
}

/// `D1a · 1e` 「No fee groups created yet」.
class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s28, horizontal: AppSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.payments_outlined, size: AppSpace.s28, color: scheme.outline),
          const SizedBox(height: AppSpace.s10),
          Text(l10n.noFeeGroups, textAlign: TextAlign.center, style: textTheme.titleMedium),
          const SizedBox(height: AppSpace.s4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              l10n.noFeeGroupsHint,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: AppType.proseHeight),
            ),
          ),
        ],
      ),
    );
  }
}

/// `1d` / `1g` 右栏占位卡: a dashed r14 frame holding the editor column's
/// place so the two columns never move — 「选一组来编辑」, or in reorder mode
/// what the grips do.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.reorder});

  final bool reorder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DashedBorder(
      color: scheme.outlineVariant,
      radius: AppRadius.lg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 220),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(reorder ? Icons.swap_vert : Icons.payments_outlined, size: AppSpace.s28, color: scheme.outline),
              const SizedBox(height: 8),
              Text(
                reorder ? l10n.feeGroupReorderTitle : l10n.feeGroupPickTitle,
                textAlign: TextAlign.center,
                style: textTheme.titleSmall?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  reorder ? l10n.feeGroupReorderText : l10n.feeGroupPickText,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: AppType.proseHeight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `1e` 编辑卡: the accent edge on the accent wash around the fields, and
/// under it the footer — 「删除组」 on the left when the group exists, Cancel
/// and Save on the right. Save is off until the draft has a name and its
/// rates parse (`1f`).
class _EditorCard extends StatelessWidget {
  const _EditorCard({
    super.key,
    required this.draft,
    required this.saving,
    required this.onCancel,
    required this.onSave,
    required this.onDelete,
  });

  final FeeGroupDraft draft;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  /// Null while adding: there is nothing to delete, and the slot stays empty.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isNew = draft.isNew;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.accentTint,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.primary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isNew ? l10n.newFeeGroup : l10n.editGroupTitle,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: AppType.trackedLabelSpacing,
                  color: scheme.onAccentTint,
                ),
              ),
              const SizedBox(height: AppSpace.s10),
              FeeGroupEditorFields(draft: draft, narrow: Responsive.isMobile(context)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s10),
        ListenableBuilder(
          listenable: draft,
          builder: (context, _) => Row(
            children: [
              if (onDelete case final onDelete?)
                TextButton.icon(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                    minimumSize: const Size(0, AppSize.control),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                  icon: const Icon(Icons.delete_outline, size: AppSize.iconMd),
                  label: Text(l10n.deleteGroup),
                ),
              const Spacer(),
              AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: onCancel),
              const SizedBox(width: AppSpace.s6),
              AppButton(
                label: l10n.save,
                icon: Icons.save,
                loading: saving,
                onPressed: draft.canSave && !saving ? onSave : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
