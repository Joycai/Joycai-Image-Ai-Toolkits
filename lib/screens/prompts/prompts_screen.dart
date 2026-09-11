import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/app_run_console.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/glass/app_glass.dart';
import '../../widgets/panel_resizer.dart';
import 'prompts_io.dart';
import 'widgets/prompt_category_strip.dart';
import 'widgets/prompt_dialogs.dart';
import 'widgets/prompt_library_parts.dart';
import 'widgets/prompt_selection_capsule.dart';
import 'widgets/prompts_header.dart';
import 'widgets/prompts_sidebar.dart';
import 'widgets/system_template_list.dart';
import 'widgets/tag_management_list.dart';
import 'widgets/user_prompt_list.dart';

/// The Prompt Library (`C1`): user prompts, system templates and categories.
///
/// ≥ 600 wide, two opaque columns — the category filter (drag-resizable,
/// persisted) and the list under a 56px header that folds by measurement and
/// turns into the selection header while prompts are picked. Tablets add the
/// horizontal category strip under that header.
///
/// < 600, a glass app bar with the pinned search and a three-tab bar, the same
/// strip under it, and selection actions in a floating glass capsule.
class PromptsScreen extends StatefulWidget {
  const PromptsScreen({super.key});

  @override
  State<PromptsScreen> createState() => _PromptsScreenState();
}

class _PromptsScreenState extends State<PromptsScreen> with SingleTickerProviderStateMixin {
  static const double _minSidebarWidth = 170;
  static const double _maxSidebarWidth = 340;

  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabController;
  double _sidebarWidth = 260;

  /// Drag accumulator, allowed [_kDragSlack] past the limits so the handle
  /// re-engages where the pointer actually is after a drag past the end,
  /// instead of the instant the pointer reverses. Null when no drag is live.
  static const double _kDragSlack = 24;
  double? _dragSidebarWidth;

  List<Prompt> _userPrompts = [];
  List<SystemPrompt> _systemPrompts = [];
  List<PromptTag> _tags = [];
  String _searchQuery = "";

  /// 'all', 'refiner' or 'rename'.
  String _selectedSystemType = 'all';
  Set<int> _selectedFilterTagIds = {};
  // When multiple categories are selected: false = match any (OR), true = match all (AND).
  bool _filterMatchAll = false;

  Set<int> _selectedIds = {};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _clearSelection();
        setState(() {});
      }
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    _loadSidebarWidth();
  }

  Future<void> _loadSidebarWidth() async {
    final saved = await DatabaseService().getSetting('prompts_sidebar_width');
    final width = double.tryParse(saved ?? '');
    if (width != null && mounted) {
      setState(() => _sidebarWidth = width.clamp(_minSidebarWidth, _maxSidebarWidth));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSelection(int id) {
    setState(() {
      _selectedIds = _selectedIds.contains(id)
          ? ({..._selectedIds}..remove(id))
          : {..._selectedIds, id};
    });
  }

  void _enterSelectionMode(int id) {
    if (!_isSelectionMode) {
      setState(() => _selectedIds = {id});
    }
  }

  void _clearSelection() {
    if (_selectedIds.isNotEmpty) {
      setState(() => _selectedIds = {});
    }
  }

  void _toggleFilterTag(int id) {
    setState(() {
      _selectedFilterTagIds = _selectedFilterTagIds.contains(id)
          ? ({..._selectedFilterTagIds}..remove(id))
          : {..._selectedFilterTagIds, id};
    });
  }

  void _clearFilterTags() => setState(() => _selectedFilterTagIds = {});

  void _setView(int index) {
    setState(() {
      _tabController.index = index;
      _clearSelection();
    });
  }

  Future<void> _loadData() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userPrompts = await appState.getPrompts();
    final systemPrompts = await appState.getSystemPrompts();
    final tags = await appState.getPromptTags();
    if (mounted) {
      setState(() {
        _userPrompts = userPrompts;
        _systemPrompts = systemPrompts;
        _tags = tags;
      });
    }
  }

  // --- Derived lists ---------------------------------------------------------

  List<Prompt> get _filteredUser => _userPrompts.where((p) {
        final matchesSearch = p.title.toLowerCase().contains(_searchQuery) ||
            p.content.toLowerCase().contains(_searchQuery);
        if (_selectedFilterTagIds.isEmpty) return matchesSearch;
        final promptTagIds = p.tags.map((t) => t.id!).toSet();
        final matchesTags = _filterMatchAll
            ? _selectedFilterTagIds.every((id) => promptTagIds.contains(id))
            : _selectedFilterTagIds.any((id) => promptTagIds.contains(id));
        return matchesSearch && matchesTags;
      }).toList();

  List<SystemPrompt> get _filteredSystem => _systemPrompts.where((p) {
        final matchesType = _selectedSystemType == 'all' || p.type == _selectedSystemType;
        final matchesSearch = p.title.toLowerCase().contains(_searchQuery) ||
            p.content.toLowerCase().contains(_searchQuery);
        return matchesType && matchesSearch;
      }).toList();

  /// Number of user prompts carrying each tag id.
  Map<int, int> _computeTagCounts() => {
        for (final t in _tags)
          t.id!: _userPrompts.where((p) => p.tags.any((pt) => pt.id == t.id)).length,
      };

  String _addLabel(AppLocalizations l10n) {
    if (_tabController.index == 1) return l10n.newTemplate;
    if (_tabController.index == 2) return l10n.addCategory;
    return l10n.newPrompt;
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final phone = Responsive.isMobile(context);
    final filteredUser = _filteredUser;
    final filteredSystem = _filteredSystem;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ResponsiveBuilder(
        mobile: _buildMobileLayout(l10n, filteredUser, filteredSystem),
        tablet: _buildDesktopLayout(l10n, filteredUser, filteredSystem, isTablet: true),
        desktop: _buildDesktopLayout(l10n, filteredUser, filteredSystem),
      ),
      bottomNavigationBar: const AppRunConsole(),
      floatingActionButton: phone && _isSelectionMode
          ? PromptSelectionCapsule(
              count: _selectedIds.length,
              onClose: _clearSelection,
              onCategorize: _handleBulkCategorize,
              onDelete: _handleBulkDelete,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _handleBulkDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final isUser = _tabController.index == 0;
    final titles = isUser
        ? [for (final p in _userPrompts) if (_selectedIds.contains(p.id)) p.title]
        : [for (final p in _systemPrompts) if (_selectedIds.contains(p.id)) p.title];
    final confirmed = await showBulkDeleteConfirm(context, l10n, _selectedIds.length, titles: titles);
    if (confirmed && mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (isUser) {
        await appState.deletePrompts(_selectedIds.toList());
      } else {
        await appState.deleteSystemPrompts(_selectedIds.toList());
      }
      _clearSelection();
      _loadData();
    }
  }

  Future<void> _handleBulkCategorize() async {
    final l10n = AppLocalizations.of(context)!;
    final targetTagIds = await showBulkCategorizeDialog(context, l10n, _tags, count: _selectedIds.length);
    if (targetTagIds != null && mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (_tabController.index == 0) {
        await appState.updatePromptsTags(_selectedIds.toList(), targetTagIds);
      } else {
        await appState.updateSystemPromptsTags(_selectedIds.toList(), targetTagIds);
      }
      _clearSelection();
      _loadData();
    }
  }

  /// Whether the list on [tab] is narrowed in a way that turns dragging off.
  bool _reorderBlocked(int tab, List<Prompt> filteredUser, List<SystemPrompt> filteredSystem) {
    if (tab == 0) {
      return (_searchQuery.isNotEmpty || _selectedFilterTagIds.isNotEmpty) && filteredUser.isNotEmpty;
    }
    if (tab == 1) return _searchQuery.isNotEmpty && filteredSystem.isNotEmpty;
    return false;
  }

  /// [child] with the warning strip under it while dragging is off.
  Widget _withReorderStrip(bool blocked, Widget child) {
    return Column(
      children: [
        Expanded(child: child),
        if (blocked) const PromptReorderBlockedStrip(),
      ],
    );
  }

  Widget _buildUserList(List<Prompt> filteredUser) {
    return UserPromptList(
      prompts: filteredUser,
      allPrompts: _userPrompts,
      searchQuery: _searchQuery,
      selectedFilterTagIds: _selectedFilterTagIds,
      onRefresh: _loadData,
      onShowEditDialog: (l, {prompt}) => _showPromptDialog(l, prompt: prompt),
      onConfirmDelete: _confirmDelete,
      selectedIds: _selectedIds,
      isSelectionMode: _isSelectionMode,
      onToggleSelection: _toggleSelection,
      onEnterSelectionMode: _enterSelectionMode,
    );
  }

  Widget _buildSystemList(List<SystemPrompt> filteredSystem, {Widget? header}) {
    return SystemTemplateList(
      prompts: filteredSystem,
      allPrompts: _systemPrompts,
      searchQuery: _searchQuery,
      onRefresh: _loadData,
      onShowEditDialog: (l, {prompt}) => _showSystemPromptDialog(l, prompt: prompt),
      onConfirmDelete: _confirmDelete,
      header: header,
      selectedIds: _selectedIds,
      isSelectionMode: _isSelectionMode,
      onToggleSelection: _toggleSelection,
      onEnterSelectionMode: _enterSelectionMode,
    );
  }

  Widget _buildTagList() {
    return TagManagementList(
      tags: _tags,
      promptCounts: _computeTagCounts(),
      onRefresh: _loadData,
      onShowEditDialog: (l, {tag}) => _showTagDialog(l, tag: tag),
      onConfirmDelete: _confirmDeleteTag,
    );
  }

  // --- Phone -----------------------------------------------------------------

  Widget _buildMobileLayout(
    AppLocalizations l10n,
    List<Prompt> filteredUser,
    List<SystemPrompt> filteredSystem,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const double searchRow = 40 + 8;
    const double tabRow = 44;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 56,
          titleSpacing: AppSpace.s16,
          // The screen's one full-width glass layer, behind the title row, the
          // search and the tabs alike.
          flexibleSpace: const AppGlass(
            grade: GlassGrade.bar,
            edges: GlassEdges.bottom,
            shadow: false,
            child: SizedBox.expand(),
          ),
          title: Text(
            _isSelectionMode ? l10n.selectionMode : l10n.promptLibrary,
            style: textTheme.headlineMedium,
          ),
          actions: _isSelectionMode
              ? [
                  IconButton(icon: const Icon(Icons.close), tooltip: l10n.cancel, onPressed: _clearSelection),
                  const SizedBox(width: AppSpace.s6),
                ]
              : [
                  PromptImportExportMenu(
                    boxed: false,
                    onImport: () => _importPrompts(l10n),
                    onExport: () => _exportPrompts(l10n),
                  ),
                  IconButton(icon: const Icon(Icons.add), tooltip: _addLabel(l10n), onPressed: _handleAddAction),
                  const SizedBox(width: AppSpace.s6),
                ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(searchRow + tabRow),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    // 40: a phone app bar's touch slot, not the pointer 32.
                    child: AppSearchField(controller: _searchCtrl, hint: l10n.filterPrompts, height: 40),
                  ),
                ),
                SizedBox(
                  height: tabRow,
                  child: TabBar(
                    controller: _tabController,
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(color: scheme.primary, width: 2),
                    ),
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    labelColor: scheme.onAccentTint,
                    unselectedLabelColor: scheme.onSurfaceVariant,
                    labelStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    unselectedLabelStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    tabs: [
                      Tab(height: tabRow, text: l10n.userPrompts),
                      Tab(height: tabRow, text: l10n.systemTemplates),
                      Tab(height: tabRow, text: l10n.categoriesTab),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      body: Column(
        children: [
          if (_tabController.index == 0 && _tags.isNotEmpty)
            PromptCategoryStrip(
              tags: _tags,
              selectedFilterTagIds: _selectedFilterTagIds,
              totalCount: _userPrompts.length,
              onTagToggle: _toggleFilterTag,
              onClear: _clearFilterTags,
              chipHeight: AppSize.control,
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _withReorderStrip(_reorderBlocked(0, filteredUser, filteredSystem), _buildUserList(filteredUser)),
                _withReorderStrip(
                  _reorderBlocked(1, filteredUser, filteredSystem),
                  _buildSystemList(
                    filteredSystem,
                    header: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: PromptTemplateTypeSegmented(
                          value: _selectedSystemType,
                          onChanged: (v) => setState(() => _selectedSystemType = v),
                        ),
                      ),
                    ),
                  ),
                ),
                _buildTagList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Desktop / tablet ------------------------------------------------------

  Widget _buildDesktopLayout(
    AppLocalizations l10n,
    List<Prompt> filteredUser,
    List<SystemPrompt> filteredSystem, {
    bool isTablet = false,
  }) {
    final tab = _tabController.index;
    final isCategories = tab == 2;

    final Widget content = switch (tab) {
      1 => _buildSystemList(filteredSystem),
      2 => _buildTagList(),
      _ => _buildUserList(filteredUser),
    };

    return Row(
      children: [
        // ── Left column: library header + category filter ──────────────
        PanelCard(
          width: _sidebarWidth,
          shape: PanelShape.column,
          child: Column(
            children: [
              PromptsSidebarHeader(
                isCategories: isCategories,
                onToggleCategories: () => _setView(isCategories ? 0 : 2),
              ),
              Expanded(
                child: PromptsSidebar(
                  tags: _tags,
                  selectedFilterTagIds: _selectedFilterTagIds,
                  tagCounts: _computeTagCounts(),
                  totalCount: _userPrompts.length,
                  matchAll: _filterMatchAll,
                  matchCount: filteredUser.length,
                  onMatchModeChanged: (val) => setState(() => _filterMatchAll = val),
                  onTagToggle: _toggleFilterTag,
                  onClear: _clearFilterTags,
                ),
              ),
            ],
          ),
        ),
        PanelResizer(
          shape: PanelShape.column,
          onDrag: (dx) => setState(() {
            _dragSidebarWidth = ((_dragSidebarWidth ?? _sidebarWidth) + dx)
                .clamp(_minSidebarWidth - _kDragSlack, _maxSidebarWidth + _kDragSlack);
            _sidebarWidth = _dragSidebarWidth!.clamp(_minSidebarWidth, _maxSidebarWidth);
          }),
          onDragEnd: () {
            _dragSidebarWidth = null;
            DatabaseService()
                .saveSetting('prompts_sidebar_width', _sidebarWidth.round().toString());
          },
        ),

        // ── Main column: 56px header + content ─────────────────────────
        Expanded(
          child: PanelCard(
            shape: PanelShape.column,
            child: Column(
              children: [
                PromptsMainHeader(
                  view: tab,
                  onViewChanged: _setView,
                  searchController: _searchCtrl,
                  systemType: _selectedSystemType,
                  onSystemTypeChanged: (v) => setState(() => _selectedSystemType = v),
                  addLabel: _addLabel(l10n),
                  onAdd: _handleAddAction,
                  onImport: () => _importPrompts(l10n),
                  onExport: () => _exportPrompts(l10n),
                  selectionCount: _selectedIds.length,
                  onClearSelection: _clearSelection,
                  onCategorize: _handleBulkCategorize,
                  onDelete: _handleBulkDelete,
                ),
                // Tablet: horizontal category filter when on user prompts tab
                if (isTablet && tab == 0 && _tags.isNotEmpty)
                  PromptCategoryStrip(
                    tags: _tags,
                    selectedFilterTagIds: _selectedFilterTagIds,
                    totalCount: _userPrompts.length,
                    onTagToggle: _toggleFilterTag,
                    onClear: _clearFilterTags,
                  ),
                Expanded(
                  child: _withReorderStrip(_reorderBlocked(tab, filteredUser, filteredSystem), content),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _handleAddAction() {
    final l10n = AppLocalizations.of(context)!;
    if (_tabController.index == 1) {
      _showSystemPromptDialog(l10n);
    } else if (_tabController.index == 2) {
      _showTagDialog(l10n);
    } else {
      _showPromptDialog(l10n);
    }
  }

  // --- Dialog wrappers: delegate to prompt_dialogs.dart, then reload on change ---

  void _confirmDelete(AppLocalizations l10n, dynamic prompt, {required bool isSystem}) async {
    final deleted = await showDeletePromptConfirm(context, l10n, prompt, isSystem: isSystem);
    if (deleted) _loadData();
  }

  void _confirmDeleteTag(AppLocalizations l10n, PromptTag tag) async {
    final deleted = await showDeleteTagConfirm(context, l10n, tag);
    if (deleted) _loadData();
  }

  void _showTagDialog(AppLocalizations l10n, {PromptTag? tag}) async {
    final saved = await showTagEditDialog(
      context,
      l10n,
      tag: tag,
      tags: _tags,
      promptCount: tag == null ? 0 : _computeTagCounts()[tag.id] ?? 0,
    );
    if (saved) _loadData();
  }

  void _showSystemPromptDialog(AppLocalizations l10n, {SystemPrompt? prompt}) async {
    final saved = await showSystemPromptEditDialog(
      context,
      l10n,
      prompt: prompt,
      systemPrompts: _systemPrompts,
      tags: _tags,
      defaultType: _selectedSystemType == 'all' ? 'refiner' : _selectedSystemType,
    );
    if (saved) _loadData();
  }

  void _showPromptDialog(AppLocalizations l10n, {Prompt? prompt}) async {
    final saved = await showPromptEditDialog(
      context,
      l10n,
      prompt: prompt,
      userPrompts: _userPrompts,
      tags: _tags,
    );
    if (saved) _loadData();
  }

  Future<void> _exportPrompts(AppLocalizations l10n) async {
    await exportPrompts(
      context,
      l10n,
      tags: _tags,
      userPrompts: _userPrompts,
      systemPrompts: _systemPrompts,
    );
  }

  Future<void> _importPrompts(AppLocalizations l10n) async {
    final imported = await importPrompts(context, l10n);
    if (imported && mounted) _loadData();
  }
}
