import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/panel_resizer.dart';
import 'prompts_io.dart';
import 'widgets/prompt_dialogs.dart';
import 'widgets/prompts_sidebar.dart';
import 'widgets/system_template_list.dart';
import 'widgets/tag_management_list.dart';
import 'widgets/user_prompt_list.dart';

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
  double _sidebarWidth = 230;

  List<Prompt> _userPrompts = [];
  List<SystemPrompt> _systemPrompts = [];
  List<PromptTag> _tags = [];
  String _searchQuery = "";
  String _selectedSystemType = 'refiner'; // 'refiner' or 'rename'
  final Set<int> _selectedFilterTagIds = {};
  // When multiple categories are selected: false = match any (OR), true = match all (AND).
  bool _filterMatchAll = false;

  final Set<int> _selectedIds = {};
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
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(int id) {
    if (!_isSelectionMode) {
      setState(() {
        _selectedIds.add(id);
      });
    }
  }

  void _clearSelection() {
    if (_selectedIds.isNotEmpty) {
      setState(() {
        _selectedIds.clear();
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: ResponsiveBuilder(
        mobile: _buildMobileLayout(l10n),
        tablet: _buildDesktopLayout(l10n, isTablet: true),
        desktop: _buildDesktopLayout(l10n),
      ),
      floatingActionButton: _isSelectionMode ? _buildBulkActionFAB(l10n) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBulkActionFAB(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isMobile(context);
    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _clearSelection,
              tooltip: l10n.cancel,
            ),
            const SizedBox(width: 4),
            Text(
              l10n.nSelected(_selectedIds.length),
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            const VerticalDivider(width: 1, indent: 8, endIndent: 8),
            const SizedBox(width: 4),
            if (isNarrow) ...[
              IconButton(
                icon: const Icon(Icons.category_outlined),
                tooltip: l10n.categorize,
                onPressed: _handleBulkCategorize,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: colorScheme.error),
                tooltip: l10n.delete,
                onPressed: _handleBulkDelete,
              ),
            ] else ...[
              TextButton.icon(
                icon: const Icon(Icons.category_outlined),
                label: Text(l10n.categorize),
                onPressed: _handleBulkCategorize,
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: Icon(Icons.delete_outline, color: colorScheme.error),
                label: Text(l10n.delete, style: TextStyle(color: colorScheme.error)),
                onPressed: _handleBulkDelete,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleBulkDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showBulkDeleteConfirm(context, l10n, _selectedIds.length);
    if (confirmed && mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (_tabController.index == 0) {
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
    final targetTagIds = await showBulkCategorizeDialog(context, l10n, _tags);
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

  // --- Mobile Layout ---
  Widget _buildMobileLayout(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(_isSelectionMode ? l10n.selectionMode : l10n.promptLibrary),
            pinned: true,
            floating: true,
            snap: true,
            actions: _isSelectionMode ? [] : [
              _buildImportExportMenu(l10n),
              IconButton(onPressed: _handleAddAction, icon: const Icon(Icons.add)),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(108),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _buildSearchField(l10n, isMobile: true),
                  ),
                  TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(text: l10n.userPrompts),
                      Tab(text: l10n.systemTemplates),
                      Tab(text: l10n.categoriesTab),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        body: Column(
          children: [
            if (_tabController.index == 0 && _tags.isNotEmpty)
              _buildMobileFilterBar(colorScheme),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _buildTabViews(l10n),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Desktop/Tablet Layout (inset panels on a tinted canvas) ---
  Widget _buildDesktopLayout(AppLocalizations l10n, {bool isTablet = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagCounts = _computeTagCounts();
    final isCategories = _tabController.index == 2;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            // ── Left card: library header + category filter ────────────────
            PanelCard(
              width: _sidebarWidth,
              child: Column(
                children: [
                  _buildSidebarHeader(l10n, colorScheme, isCategories: isCategories),
                  // Category filter list
                  Expanded(
                    child: PromptsSidebar(
                      tags: _tags,
                      selectedFilterTagIds: _selectedFilterTagIds,
                      tagCounts: tagCounts,
                      totalCount: _userPrompts.length,
                      matchAll: _filterMatchAll,
                      onMatchModeChanged: (val) => setState(() => _filterMatchAll = val),
                      onTagToggle: (id) {
                        setState(() {
                          if (_selectedFilterTagIds.contains(id)) {
                            _selectedFilterTagIds.remove(id);
                          } else {
                            _selectedFilterTagIds.add(id);
                          }
                        });
                      },
                      onClear: () => setState(() => _selectedFilterTagIds.clear()),
                    ),
                  ),
                ],
              ),
            ),
            PanelResizer(
              onDrag: (dx) => setState(() {
                _sidebarWidth = (_sidebarWidth + dx).clamp(_minSidebarWidth, _maxSidebarWidth);
              }),
              onDragEnd: () => DatabaseService()
                  .saveSetting('prompts_sidebar_width', _sidebarWidth.round().toString()),
            ),

            // ── Main card: 56px in-card header + content ────────────────────
            Expanded(
              child: PanelCard(
                child: Column(
                  children: [
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90)),
                        ),
                      ),
                      child: _buildDesktopHeader(l10n, colorScheme,
                          isTablet: isTablet, isCategories: isCategories),
                    ),
                    // Tablet: horizontal category filter when on user prompts tab
                    if (isTablet && _tabController.index == 0 && _tags.isNotEmpty)
                      _buildMobileFilterBar(colorScheme),
                    // Main content
                    Expanded(
                      child: _buildConstrainedContent(
                        _buildTabViews(l10n)[_tabController.index],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarHeader(
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    required bool isCategories,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 22, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.promptLibrary,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Manage categories button
          Tooltip(
            message: l10n.categoriesTab,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() {
                _tabController.index = isCategories ? 0 : 2;
                _clearSelection();
              }),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCategories
                      ? colorScheme.primary.withAlpha(28)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.category_outlined,
                  size: 18,
                  color: isCategories
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader(
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    bool isTablet = false,
    bool isCategories = false,
  }) {
    // ── Selection mode ──────────────────────────────────────────────────────
    if (_isSelectionMode) {
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _clearSelection,
            tooltip: l10n.cancel,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.nSelected(_selectedIds.length),
            style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.category_outlined, size: 16),
            label: Text(l10n.categorize),
            onPressed: _handleBulkCategorize,
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            icon: Icon(Icons.delete_outline, size: 16, color: colorScheme.error),
            label: Text(l10n.delete, style: TextStyle(color: colorScheme.error)),
            onPressed: _handleBulkDelete,
          ),
        ],
      );
    }

    // ── Categories tab ──────────────────────────────────────────────────────
    if (isCategories) {
      return Row(
        children: [
          Icon(Icons.category, size: 22, color: colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            l10n.categoriesTab,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _handleAddAction,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.addCategory),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              minimumSize: const Size(0, 38),
            ),
          ),
        ],
      );
    }

    // ── User / System prompts ───────────────────────────────────────────────
    return Row(
      children: [
        _buildTabToggle(l10n, colorScheme),
        const Spacer(),
        _buildSearchField(l10n, width: isTablet ? 180 : 250),
        const SizedBox(width: 10),
        _buildImportExportActions(l10n),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _handleAddAction,
          icon: const Icon(Icons.add, size: 18),
          label: Text(_addLabel(l10n)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            minimumSize: const Size(0, 38),
          ),
        ),
      ],
    );
  }

  Widget _buildTabToggle(AppLocalizations l10n, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(140),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleBtn(l10n.userPrompts, 0, colorScheme),
          _buildToggleBtn(l10n.systemTemplates, 1, colorScheme),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(String label, int index, ColorScheme colorScheme) {
    final selected = _tabController.index == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? colorScheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        boxShadow: selected
            ? [BoxShadow(color: Colors.black.withAlpha(18), blurRadius: 4, offset: const Offset(0, 1))]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => setState(() {
            _tabController.index = index;
            _clearSelection();
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Number of user prompts carrying each tag id.
  Map<int, int> _computeTagCounts() => {
        for (final t in _tags)
          t.id!: _userPrompts.where((p) => p.tags.any((pt) => pt.id == t.id)).length,
      };

  /// Caps content width on ultra-wide screens for readability, top-aligned.
  Widget _buildConstrainedContent(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: child,
      ),
    );
  }

  String _addLabel(AppLocalizations l10n) {
    if (_tabController.index == 1) return l10n.newTemplate;
    if (_tabController.index == 2) return l10n.addCategory;
    return l10n.newPrompt;
  }

  List<Widget> _buildTabViews(AppLocalizations l10n) {
    final filteredUser = _userPrompts.where((p) {
      final matchesSearch = p.title.toLowerCase().contains(_searchQuery) ||
                            p.content.toLowerCase().contains(_searchQuery);
      if (_selectedFilterTagIds.isEmpty) return matchesSearch;
      final promptTagIds = p.tags.map((t) => t.id!).toSet();
      final matchesTags = _filterMatchAll
          ? _selectedFilterTagIds.every((id) => promptTagIds.contains(id))
          : _selectedFilterTagIds.any((id) => promptTagIds.contains(id));
      return matchesSearch && matchesTags;
    }).toList();

    final filteredSystem = _systemPrompts.where((p) {
      final matchesType = p.type == _selectedSystemType;
      final matchesSearch = p.title.toLowerCase().contains(_searchQuery) ||
                            p.content.toLowerCase().contains(_searchQuery);
      return matchesType && matchesSearch;
    }).toList();

    final colorScheme = Theme.of(context).colorScheme;

    return [
      UserPromptList(
        prompts: filteredUser,
        searchQuery: _searchQuery,
        selectedFilterTagIds: _selectedFilterTagIds,
        onRefresh: _loadData,
        onShowEditDialog: (l, {prompt}) => _showPromptDialog(l, prompt: prompt),
        onConfirmDelete: _confirmDelete,
        selectedIds: _selectedIds,
        isSelectionMode: _isSelectionMode,
        onToggleSelection: _toggleSelection,
        onEnterSelectionMode: _enterSelectionMode,
      ),
      SystemTemplateList(
        prompts: filteredSystem,
        searchQuery: _searchQuery,
        onRefresh: _loadData,
        onShowEditDialog: (l, {prompt}) => _showSystemPromptDialog(l, prompt: prompt),
        onConfirmDelete: _confirmDelete,
        header: _buildSystemTypeToggle(colorScheme, l10n),
        selectedIds: _selectedIds,
        isSelectionMode: _isSelectionMode,
        onToggleSelection: _toggleSelection,
        onEnterSelectionMode: _enterSelectionMode,
      ),
      TagManagementList(
        tags: _tags,
        promptCounts: _computeTagCounts(),
        onRefresh: _loadData,
        onShowEditDialog: (l, {tag}) => _showTagDialog(l, tag: tag),
        onConfirmDelete: _confirmDeleteTag,
      ),
    ];
  }

  Widget _buildSearchField(AppLocalizations l10n, {bool isMobile = false, double width = 300}) {
    return Container(
      width: isMobile ? double.infinity : width,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _searchCtrl,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: l10n.filterPrompts,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => _searchCtrl.clear())
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildImportExportActions(AppLocalizations l10n) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          icon: const Icon(Icons.upload_file_outlined, size: 20),
          tooltip: l10n.importSettings,
          onPressed: () => _importPrompts(l10n),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          icon: const Icon(Icons.download_for_offline_outlined, size: 20),
          tooltip: l10n.exportSettings,
          onPressed: () => _exportPrompts(l10n),
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

  Widget _buildImportExportMenu(AppLocalizations l10n) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'import') _importPrompts(l10n);
        if (val == 'export') _exportPrompts(l10n);
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'import', child: ListTile(leading: const Icon(Icons.upload_file_outlined), title: Text(l10n.importSettings), dense: true)),
        PopupMenuItem(value: 'export', child: ListTile(leading: const Icon(Icons.download_for_offline_outlined), title: Text(l10n.exportSettings), dense: true)),
      ],
    );
  }

  Widget _buildMobileFilterBar(ColorScheme colorScheme) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // +1 for the leading "All" chip that clears the filter.
        itemCount: _tags.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final l10n = AppLocalizations.of(context)!;

          // Leading "All" chip.
          if (index == 0) {
            final allSelected = _selectedFilterTagIds.isEmpty;
            return FilterChip(
              label: Text(l10n.filterAll, style: TextStyle(
                fontSize: 12,
                color: allSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                fontWeight: allSelected ? FontWeight.bold : FontWeight.normal,
              )),
              selected: allSelected,
              onSelected: (_) => setState(() => _selectedFilterTagIds.clear()),
              selectedColor: colorScheme.primary,
              checkmarkColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              visualDensity: VisualDensity.compact,
            );
          }

          final tag = _tags[index - 1];
          final id = tag.id!;
          final isSelected = _selectedFilterTagIds.contains(id);
          final color = Color(tag.color);

          return FilterChip(
            label: Text(tag.name, style: TextStyle(
              fontSize: 12,
              color: isSelected ? Colors.white : color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            )),
            selected: isSelected,
            onSelected: (val) {
              setState(() {
                if (val) {
                  _selectedFilterTagIds.add(id);
                } else {
                  _selectedFilterTagIds.remove(id);
                }
              });
            },
            selectedColor: color,
            checkmarkColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: color.withValues(alpha: 0.5)),
            ),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildSystemTypeToggle(ColorScheme colorScheme, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'refiner', label: Text(l10n.typeRefiner), icon: const Icon(Icons.auto_fix_high, size: 16)),
              ButtonSegment(value: 'rename', label: Text(l10n.typeRename), icon: const Icon(Icons.drive_file_rename_outline, size: 16)),
            ],
            selected: {_selectedSystemType},
            onSelectionChanged: (val) {
              setState(() => _selectedSystemType = val.first);
            },
            showSelectedIcon: false,
          ),
        ),
      ),
    );
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
    final saved = await showTagEditDialog(context, l10n, tag: tag, tags: _tags);
    if (saved) _loadData();
  }

  void _showSystemPromptDialog(AppLocalizations l10n, {SystemPrompt? prompt}) async {
    final saved = await showSystemPromptEditDialog(
      context,
      l10n,
      prompt: prompt,
      systemPrompts: _systemPrompts,
      tags: _tags,
      defaultType: _selectedSystemType,
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
