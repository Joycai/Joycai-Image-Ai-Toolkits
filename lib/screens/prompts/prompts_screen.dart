import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../state/app_state.dart';
import '../../widgets/markdown_editor.dart';
import 'widgets/color_hue_picker.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabController;
  
  List<Prompt> _userPrompts = [];
  List<SystemPrompt> _systemPrompts = [];
  List<PromptTag> _tags = [];
  String _searchQuery = "";
  String _selectedSystemType = 'refiner'; // 'refiner' or 'rename'
  final Set<int> _selectedFilterTagIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
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
    
    return ResponsiveBuilder(
      mobile: _buildMobileLayout(l10n),
      tablet: _buildDesktopLayout(l10n, isTablet: true),
      desktop: _buildDesktopLayout(l10n),
    );
  }

  // --- Mobile Layout ---
  Widget _buildMobileLayout(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(l10n.promptLibrary),
            pinned: true,
            floating: true,
            snap: true,
            actions: [
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

  // --- Desktop/Tablet Layout ---
  Widget _buildDesktopLayout(AppLocalizations l10n, {bool isTablet = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.promptLibrary, style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        centerTitle: false,
        actions: [
          _buildSearchField(l10n),
          const SizedBox(width: 8),
          _buildImportExportActions(l10n),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _handleAddAction,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.add),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(100)),
        ),
      ),
      body: Row(
        children: [
          // Navigation Rail / Sidebar
          NavigationRail(
            selectedIndex: _tabController.index,
            onDestinationSelected: (index) => setState(() => _tabController.index = index),
            labelType: NavigationRailLabelType.all,
            backgroundColor: colorScheme.surfaceContainerLow,
            destinations: [
              NavigationRailDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: Text(l10n.userPrompts)),
              NavigationRailDestination(icon: const Icon(Icons.auto_fix_high_outlined), selectedIcon: const Icon(Icons.auto_fix_high), label: Text(l10n.systemTemplates)),
              NavigationRailDestination(icon: const Icon(Icons.category_outlined), selectedIcon: const Icon(Icons.category), label: Text(l10n.categoriesTab)),
            ],
          ),
          const VerticalDivider(width: 1),
          // Tag Sidebar (Only for Prompts)
          if (_tabController.index != 2) ...[
            SizedBox(
              width: isTablet ? 200 : 260,
              child: PromptsSidebar(
                tags: _tags,
                selectedFilterTagIds: _selectedFilterTagIds,
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
            const VerticalDivider(width: 1),
          ],
          // Main Content
          Expanded(
            child: Container(
              color: colorScheme.surface,
              child: _buildTabViews(l10n)[_tabController.index],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTabViews(AppLocalizations l10n) {
    final filteredUser = _userPrompts.where((p) {
      final matchesSearch = p.title.toLowerCase().contains(_searchQuery) || 
                            p.content.toLowerCase().contains(_searchQuery);
      if (_selectedFilterTagIds.isEmpty) return matchesSearch;
      final promptTagIds = p.tags.map((t) => t.id!).toSet();
      return matchesSearch && _selectedFilterTagIds.every((id) => promptTagIds.contains(id));
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
      ),
      SystemTemplateList(
        prompts: filteredSystem, 
        searchQuery: _searchQuery,
        onRefresh: _loadData,
        onShowEditDialog: (l, {prompt}) => _showSystemPromptDialog(l, prompt: prompt),
        onConfirmDelete: _confirmDelete,
        header: _buildSystemTypeToggle(colorScheme, l10n),
      ),
      TagManagementList(
        tags: _tags,
        onRefresh: _loadData,
        onShowEditDialog: (l, {tag}) => _showTagDialog(l, tag: tag),
        onConfirmDelete: _confirmDeleteTag,
      ),
    ];
  }

  Widget _buildSearchField(AppLocalizations l10n, {bool isMobile = false}) {
    return Container(
      width: isMobile ? double.infinity : 300,
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
        itemCount: _tags.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = _tags[index];
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

  void _confirmDelete(AppLocalizations l10n, dynamic prompt, {required bool isSystem}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePromptConfirmTitle),
        content: Text(l10n.deletePromptConfirmMessage(prompt.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final appState = Provider.of<AppState>(context, listen: false);
              if (isSystem) {
                await appState.deleteSystemPrompt(prompt.id);
              } else {
                await appState.deletePrompt(prompt.id);
              }
              if (context.mounted) {
                Navigator.pop(context);
                _loadData();
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTag(AppLocalizations l10n, PromptTag tag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text("Are you sure you want to delete category \"${tag.name}\"? Prompts will be moved to General."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final appState = Provider.of<AppState>(context, listen: false);
              await appState.deletePromptTag(tag.id!);
              if (context.mounted) {
                Navigator.pop(context);
                _loadData();
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showTagDialog(AppLocalizations l10n, {PromptTag? tag}) {
    final nameCtrl = TextEditingController(text: tag?.name ?? '');
    final hexCtrl = TextEditingController(text: tag != null ? '#${tag.color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}' : '#607D8B');
    int selectedColor = tag?.color ?? AppConstants.tagColors.first.toARGB32();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void updateColor(int color) {
            setDialogState(() {
              selectedColor = color;
              hexCtrl.text = '#${color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
            });
          }

          return AlertDialog(
            title: Text(tag == null ? l10n.addCategory : l10n.editCategory),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.name)),
                    const SizedBox(height: 24),
                    
                    // Color Picker Section
                    ColorHuePicker(
                      initialColor: Color(selectedColor),
                      onColorChanged: updateColor,
                    ),
                    
                    const SizedBox(height: 24),
                    TextField(
                      controller: hexCtrl, 
                      decoration: const InputDecoration(
                        labelText: 'HEX Color', 
                        prefixIcon: Icon(Icons.colorize),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        if (v.startsWith('#') && (v.length == 7 || v.length == 9)) {
                          try {
                            final colorStr = v.length == 7 ? 'FF${v.substring(1)}' : v.substring(1);
                            final color = int.parse(colorStr, radix: 16);
                            setDialogState(() => selectedColor = color);
                          } catch (_) {}
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Presets", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AppConstants.tagColors.map((color) => InkWell(
                        onTap: () => updateColor(color.toARGB32()),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedColor == color.toARGB32() ? Colors.black : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
              ElevatedButton(
                onPressed: () async {
                  final appState = Provider.of<AppState>(context, listen: false);
                  final data = {
                    'name': nameCtrl.text, 
                    'color': selectedColor,
                    'sort_order': tag?.sortOrder ?? (_tags.isEmpty ? 0 : _tags.map((t) => t.sortOrder).reduce(math.max) + 1),
                  };
                  if (tag == null) {
                    await appState.addPromptTag(data);
                  } else {
                    await appState.updatePromptTag(tag.id!, data,);
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                    _loadData();
                  }
                },
                child: Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSystemPromptDialog(AppLocalizations l10n, {SystemPrompt? prompt}) {
    final titleCtrl = TextEditingController(text: prompt?.title ?? '');
    final contentCtrl = MarkdownTextEditingController(text: prompt?.content ?? '');
    bool isMarkdown = prompt?.isMarkdown ?? true;
    String selectedType = prompt?.type ?? _selectedSystemType;

    final Set<int> selectedTagIds = {};
    if (prompt != null) {
      for (var t in prompt.tags) {
        if (t.id != null) selectedTagIds.add(t.id!);
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(selectedType == 'refiner' ? Icons.auto_fix_high : Icons.drive_file_rename_outline, color: Colors.purple),
              const SizedBox(width: 12),
              Text(prompt == null ? l10n.add : l10n.editPrompt),
            ],
          ),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 800),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(controller: titleCtrl, decoration: InputDecoration(labelText: l10n.title, border: const OutlineInputBorder())),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedType,
                          decoration: InputDecoration(labelText: l10n.templateType, border: const OutlineInputBorder()),
                          items: [
                            DropdownMenuItem(value: 'refiner', child: Text(l10n.typeRefiner)),
                            DropdownMenuItem(value: 'rename', child: Text(l10n.typeRename)),
                          ],
                          onChanged: (v) => setDialogState(() => selectedType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.tagCategory, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tags.map((t) {
                      final id = t.id!;
                      final isSelected = selectedTagIds.contains(id);
                      final color = Color(t.color);
                      return FilterChip(
                        label: Text(t.name, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : color)),
                        selected: isSelected,
                        onSelected: (val) {
                          setDialogState(() {
                            if (val) {
                              selectedTagIds.add(id);
                            } else {
                              selectedTagIds.remove(id);
                            }
                          });
                        },
                        selectedColor: color,
                        checkmarkColor: Colors.white,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  MarkdownEditor(
                    controller: contentCtrl,
                    label: l10n.promptContent,
                    isMarkdown: isMarkdown,
                    onMarkdownChanged: (v) => setDialogState(() => isMarkdown = v),
                    initiallyPreview: false,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.isEmpty || contentCtrl.text.isEmpty) return;
                final appState = Provider.of<AppState>(context, listen: false);
                final data = {
                  'title': titleCtrl.text,
                  'content': contentCtrl.text,
                  'type': selectedType,
                  'is_markdown': isMarkdown ? 1 : 0,
                  'sort_order': prompt?.sortOrder ?? (_systemPrompts.isEmpty ? 0 : _systemPrompts.map((p) => p.sortOrder).reduce(math.max) + 1),
                };
                if (prompt == null) {
                  await appState.addSystemPrompt(data, tagIds: selectedTagIds.toList());
                } else {
                  await appState.updateSystemPrompt(prompt.id!, data, tagIds: selectedTagIds.toList());
                }
                if (context.mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showPromptDialog(AppLocalizations l10n, {Prompt? prompt}) {
    final titleCtrl = TextEditingController(text: prompt?.title ?? '');
    final contentCtrl = MarkdownTextEditingController(text: prompt?.content ?? '');
    bool isMarkdown = prompt?.isMarkdown ?? true;

    final Set<int> selectedTagIds = {};
    if (prompt != null) {
      for (var t in prompt.tags) {
        if (t.id != null) selectedTagIds.add(t.id!);
      }
    } else {
      // Default to 'General' tag if creating new
      final generalTag = _tags.cast<PromptTag?>().firstWhere((t) => t?.name == 'General', orElse: () => null);
      if (generalTag != null && generalTag.id != null) {
        selectedTagIds.add(generalTag.id!);
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(prompt == null ? Icons.add_circle_outline : Icons.edit_note, color: Colors.blue),
              const SizedBox(width: 12),
              Text(prompt == null ? l10n.newPrompt : l10n.editPrompt),
            ],
          ),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 800),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.title,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.tagCategory, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tags.map((t) {
                      final id = t.id!;
                      final isSelected = selectedTagIds.contains(id);
                      final color = Color(t.color);
                      return FilterChip(
                        label: Text(t.name, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : color)),
                        selected: isSelected,
                        onSelected: (val) {
                          setDialogState(() {
                            if (val) {
                              selectedTagIds.add(id);
                            } else {
                              selectedTagIds.remove(id);
                            }
                          });
                        },
                        selectedColor: color,
                        checkmarkColor: Colors.white,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  MarkdownEditor(
                    controller: contentCtrl,
                    label: l10n.promptContent,
                    isMarkdown: isMarkdown,
                    onMarkdownChanged: (v) => setDialogState(() => isMarkdown = v),
                    initiallyPreview: false,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.isEmpty || contentCtrl.text.isEmpty) return;

                final appState = Provider.of<AppState>(context, listen: false);
                final Map<String, dynamic> data = {
                  'title': titleCtrl.text,
                  'content': contentCtrl.text,
                  'is_markdown': isMarkdown ? 1 : 0,
                  'sort_order': prompt?.sortOrder ?? (_userPrompts.isEmpty ? 0 : _userPrompts.map((p) => p.sortOrder).reduce(math.max) + 1),
                };
                if (prompt == null) {
                  await appState.addPrompt(data, tagIds: selectedTagIds.toList());
                } else {
                  await appState.updatePrompt(prompt.id!, data, tagIds: selectedTagIds.toList());
                }
                if (context.mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: Text(prompt == null ? l10n.save : l10n.update),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPrompts(AppLocalizations l10n) async {
    final data = {
      'tags': _tags.map((t) => t.toMap()).toList(),
      'user_prompts': _userPrompts.map((p) => {
        ...p.toMap(),
        'tags': p.tags.map((t) => t.toMap()).toList()
      }).toList(),
      'system_prompts': _systemPrompts.map((p) => {
        ...p.toMap(),
        'tags': p.tags.map((t) => t.toMap()).toList()
      }).toList(),
      'export_type': 'prompts_only',
      'version': 1
    };
    
    final json = jsonEncode(data);
    final bytes = utf8.encode(json);

    String? path = await FilePicker.platform.saveFile(
      fileName: 'joycai_prompts.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    
    if (path != null && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      await File(path).writeAsString(json);
    }

    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsExported)));
    }
  }

  Future<void> _importPrompts(AppLocalizations l10n) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final successMsg = l10n.settingsImported;

    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (!mounted || result == null) return;

    final String? importMode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.importMode),
        content: Text(l10n.importModeDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'merge'),
            child: Text(l10n.merge),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, 'replace'),
            child: Text(l10n.replaceAll),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );

    if (importMode == null) return;

    try {
      final file = File(result.files.single.path!);
      final String content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      
      await appState.importPromptData(data, replace: importMode == 'replace');

      if (mounted) {
        // ignore: use_build_context_synchronously
        _loadData();
        // ignore: use_build_context_synchronously
        messenger.showSnackBar(SnackBar(content: Text(successMsg)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text("Import failed: $e"), backgroundColor: Colors.red));
      }
    }
  }
}