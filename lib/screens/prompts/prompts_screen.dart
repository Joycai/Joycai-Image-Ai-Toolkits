import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../services/database_service.dart';
import '../../widgets/markdown_editor.dart';
import '../../widgets/prompt_card.dart';

class PromptsScreen extends StatefulWidget {
  const PromptsScreen({super.key});

  @override
  State<PromptsScreen> createState() => _PromptsScreenState();
}

class _PromptsScreenState extends State<PromptsScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabController;
  
  List<Prompt> _userPrompts = [];
  List<SystemPrompt> _systemPrompts = [];
  List<PromptTag> _tags = [];
  String _searchQuery = "";
  String _selectedSystemType = 'refiner'; // 'refiner' or 'rename'
  final Set<int> _selectedFilterTagIds = {};
  final Set<int> _expandedPromptIds = {};
  final Set<int> _expandedSysPromptIds = {};

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
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userPrompts = await _db.getPrompts();
    final systemPrompts = await _db.getSystemPrompts();
    final tags = await _db.getPromptTags();
    setState(() {
      _userPrompts = userPrompts;
      _systemPrompts = systemPrompts;
      _tags = tags;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 800;
    
    final filteredUser = _userPrompts.where((p) {
      final matchesSearch = p.title.toLowerCase().contains(_searchQuery) || 
                            p.content.toLowerCase().contains(_searchQuery);
      
      if (_selectedFilterTagIds.isEmpty) return matchesSearch;
      
      final promptTagIds = p.tags.map((t) => t.id!).toSet();
      final matchesTags = _selectedFilterTagIds.every((id) => promptTagIds.contains(id));
      
      return matchesSearch && matchesTags;
    }).toList();

    final filteredSystem = _systemPrompts.where((p) {
      final matchesType = p.type == _selectedSystemType;
      final matchesSearch = p.title.toLowerCase().contains(_searchQuery) || 
                            p.content.toLowerCase().contains(_searchQuery);
      return matchesType && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promptLibrary),
        actions: isNarrow 
          ? [
              PopupMenuButton<String>(
                onSelected: (val) {
                  if (val == 'import') _importPrompts(l10n);
                  if (val == 'export') _exportPrompts(l10n);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'import', child: ListTile(leading: const Icon(Icons.upload_file_outlined), title: Text(l10n.importSettings), dense: true)),
                  PopupMenuItem(value: 'export', child: ListTile(leading: const Icon(Icons.download_for_offline_outlined), title: Text(l10n.exportSettings), dense: true)),
                ],
              ),
              IconButton(
                onPressed: () {
                  if (_tabController.index == 1) {
                    _showSystemPromptDialog(l10n);
                  } else if (_tabController.index == 2) {
                    _showTagDialog(l10n);
                  } else {
                    _showPromptDialog(l10n);
                  }
                },
                icon: const Icon(Icons.add),
              ),
            ]
          : [
              Container(
                width: 250,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.filterPrompts,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.upload_file_outlined),
                tooltip: l10n.importSettings,
                onPressed: () => _importPrompts(l10n),
              ),
              IconButton(
                icon: const Icon(Icons.download_for_offline_outlined),
                tooltip: l10n.exportSettings,
                onPressed: () => _exportPrompts(l10n),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: FilledButton.icon(
                  onPressed: () {
                    if (_tabController.index == 1) {
                      _showSystemPromptDialog(l10n);
                    } else if (_tabController.index == 2) {
                      _showTagDialog(l10n);
                    } else {
                      _showPromptDialog(l10n);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text(l10n.add),
                ),
              ),
            ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isNarrow ? 100 : 50),
          child: Column(
            children: [
              if (isNarrow)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.filterPrompts,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
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
      body: Column(
        children: [
          if (_tabController.index == 0 && _tags.isNotEmpty)
            _buildFilterBar(colorScheme),
          if (_tabController.index == 1)
            _buildSystemTypeToggle(colorScheme, l10n),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserPromptList(filteredUser, l10n),
                _buildSystemPromptList(filteredSystem, l10n),
                _buildTagList(l10n),
              ],
            ),
          ),
        ],
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
    );
  }

  Widget _buildFilterBar(ColorScheme colorScheme) {
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

  Widget _buildUserPromptList(List<Prompt> prompts, AppLocalizations l10n) {
    if (prompts.isEmpty) {
      return _buildEmptyState(l10n, false);
    }
    
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: prompts.length,
      onReorder: (oldIndex, newIndex) async {
        if (_searchQuery.isNotEmpty || _selectedFilterTagIds.isNotEmpty) return;
        
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _userPrompts.removeAt(oldIndex);
          _userPrompts.insert(newIndex, item);
        });
        await _db.updatePromptOrder(_userPrompts.map((p) => p.id!).toList());
      },
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: child,
      ),
      itemBuilder: (context, index) {
        final prompt = prompts[index];
        final id = prompt.id!;
        final isExpanded = _expandedPromptIds.contains(id);

        return Padding(
          key: ValueKey('user_$id'),
          padding: const EdgeInsets.only(bottom: 12),
          child: PromptCard(
            prompt: prompt,
            isExpanded: isExpanded,
            onToggle: () => setState(() {
              if (isExpanded) {
                _expandedPromptIds.remove(id);
              } else {
                _expandedPromptIds.add(id);
              }
            }),
            leading: (_searchQuery.isEmpty && _selectedFilterTagIds.isEmpty)
                ? ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
                  )
                : null,
            onMoveToTop: index == 0 ? null : () async {
              setState(() {
                final item = _userPrompts.removeAt(_userPrompts.indexWhere((p) => p.id == id));
                _userPrompts.insert(0, item);
              });
              await _db.updatePromptOrder(_userPrompts.map((p) => p.id!).toList());
            },
            onMoveToBottom: index == prompts.length - 1 ? null : () async {
              setState(() {
                final item = _userPrompts.removeAt(_userPrompts.indexWhere((p) => p.id == id));
                _userPrompts.add(item);
              });
              await _db.updatePromptOrder(_userPrompts.map((p) => p.id!).toList());
            },
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: prompt.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.copiedToClipboard(prompt.title))),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _showPromptDialog(l10n, prompt: prompt),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => _confirmDelete(l10n, prompt, isSystem: false),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSystemPromptList(List<SystemPrompt> prompts, AppLocalizations l10n) {
    if (prompts.isEmpty) {
      return _buildEmptyState(l10n, true);
    }
    
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: prompts.length,
      onReorder: (oldIndex, newIndex) async {
        if (_searchQuery.isNotEmpty) return;
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _systemPrompts.removeAt(oldIndex);
          _systemPrompts.insert(newIndex, item);
        });
        await _db.updateSystemPromptOrder(_systemPrompts.map((p) => p.id!).toList());
      },
      itemBuilder: (context, index) {
        final systemPrompt = prompts[index];
        final id = systemPrompt.id!;
        final isExpanded = _expandedSysPromptIds.contains(id);

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
          padding: const EdgeInsets.only(bottom: 12),
          child: PromptCard(
            prompt: promptForCard,
            isExpanded: isExpanded,
            onToggle: () => setState(() {
              if (isExpanded) {
                _expandedSysPromptIds.remove(id);
              } else {
                _expandedSysPromptIds.add(id);
              }
            }),
            leading: _searchQuery.isEmpty 
                ? ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20))
                : const Icon(Icons.auto_fix_high, color: Colors.purple, size: 20),
            showCategory: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: systemPrompt.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.copiedToClipboard(systemPrompt.title))),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _showSystemPromptDialog(l10n, prompt: systemPrompt),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => _confirmDelete(l10n, systemPrompt, isSystem: true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTagList(AppLocalizations l10n) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tags.length,
      onReorder: (oldIndex, newIndex) async {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _tags.removeAt(oldIndex);
          _tags.insert(newIndex, item);
        });
        await _db.updateTagOrder(_tags.map((t) => t.id!).toList());
      },
      itemBuilder: (context, index) {
        final tag = _tags[index];
        return Card(
          key: ValueKey('tag_${tag.id}'),
          child: ListTile(
            leading: ReorderableDragStartListener(
              index: index,
              child: CircleAvatar(
                backgroundColor: Color(tag.color),
                radius: 12,
              ),
            ),
            title: Text(tag.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _showTagDialog(l10n, tag: tag),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDeleteTag(l10n, tag),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, bool isRefiner) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isRefiner ? Icons.auto_fix_high : Icons.notes, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            l10n.noPromptsSaved, 
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
          ),
          const SizedBox(height: 8),
          Text(
            isRefiner ? "Add system prompts for the Refiner here." : l10n.saveFavoritePrompts, 
            style: const TextStyle(color: Colors.grey)
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => isRefiner ? _showSystemPromptDialog(l10n) : _showPromptDialog(l10n),
            icon: const Icon(Icons.add),
            label: Text(l10n.newPrompt),
          ),
        ],
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
              if (isSystem) {
                await _db.deleteSystemPrompt(prompt.id);
              } else {
                await _db.deletePrompt(prompt.id);
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
              await _db.deletePromptTag(tag.id!);
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
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.name)),
                  const SizedBox(height: 24),
                  
                  // Color Picker Section
                  _ColorHuePicker(
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
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
              ElevatedButton(
                onPressed: () async {
                  final data = {
                    'name': nameCtrl.text, 
                    'color': selectedColor,
                    'sort_order': tag?.sortOrder ?? (_tags.isEmpty ? 0 : _tags.map((t) => t.sortOrder).reduce(math.max) + 1),
                  };
                  if (tag == null) {
                    await _db.addPromptTag(data);
                  } else {
                    await _db.updatePromptTag(tag.id!, data);
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
    final contentCtrl = TextEditingController(text: prompt?.content ?? '');
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
              Text(prompt == null ? l10n.newPrompt : l10n.editPrompt),
            ],
          ),
          content: SizedBox(
            width: 600,
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
                    initiallyPreview: true,
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
                final data = {
                  'title': titleCtrl.text,
                  'content': contentCtrl.text,
                  'type': selectedType,
                  'is_markdown': isMarkdown ? 1 : 0,
                  'sort_order': prompt?.sortOrder ?? (_systemPrompts.isEmpty ? 0 : _systemPrompts.map((p) => p.sortOrder).reduce(math.max) + 1),
                };
                if (prompt == null) {
                  await _db.addSystemPrompt(data, tagIds: selectedTagIds.toList());
                } else {
                  await _db.updateSystemPrompt(prompt.id!, data, tagIds: selectedTagIds.toList());
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
    final contentCtrl = TextEditingController(text: prompt?.content ?? '');
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
            width: 600,
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
                    initiallyPreview: true,
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

                final Map<String, dynamic> data = {
                  'title': titleCtrl.text,
                  'content': contentCtrl.text,
                  'is_markdown': isMarkdown ? 1 : 0,
                  'sort_order': prompt?.sortOrder ?? (_userPrompts.isEmpty ? 0 : _userPrompts.map((p) => p.sortOrder).reduce(math.max) + 1),
                };
                if (prompt == null) {
                  await _db.addPrompt(data, tagIds: selectedTagIds.toList());
                } else {
                  await _db.updatePrompt(prompt.id!, data, tagIds: selectedTagIds.toList());
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
      'system_prompts': _systemPrompts.map((p) => p.toMap()).toList(),
      'export_type': 'prompts_only',
      'version': 1
    };
    
    final json = jsonEncode(data);
    String? path = await FilePicker.platform.saveFile(
      fileName: 'joycai_prompts.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    
    if (path != null) {
      await File(path).writeAsString(json);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsExported)));
      }
    }
  }

  Future<void> _importPrompts(AppLocalizations l10n) async {
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
      final Map<String, dynamic> data = jsonDecode(await file.readAsString());
      
      await _db.importPromptData(data, replace: importMode == 'replace');

      if (mounted) {
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsImported)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import failed: $e"), backgroundColor: Colors.red));
      }
    }
  }
}

/// A simple Hue color picker wheel implementation
class _ColorHuePicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<int> onColorChanged;

  const _ColorHuePicker({
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<_ColorHuePicker> createState() => _ColorHuePickerState();
}

class _ColorHuePickerState extends State<_ColorHuePicker> {
  late double _hue;

  @override
  void initState() {
    super.initState();
    _hue = HSVColor.fromColor(widget.initialColor).hue;
  }

  @override
  void didUpdateWidget(_ColorHuePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newHue = HSVColor.fromColor(widget.initialColor).hue;
    if ((newHue - _hue).abs() > 1.0) {
      setState(() => _hue = newHue);
    }
  }

  void _handleGesture(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    double rad = (localPosition - center).direction; // -pi to pi
    double deg = (rad * 180 / 3.1415926535) + 90;
    if (deg < 0) deg += 360;

    setState(() {
      _hue = deg % 360;
    });
    
    final color = HSVColor.fromAHSV(1.0, _hue, 0.8, 0.9).toColor();
    widget.onColorChanged(color.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    const size = Size(160, 160);
    return GestureDetector(
      onPanUpdate: (details) => _handleGesture(details.localPosition, size),
      onPanDown: (details) => _handleGesture(details.localPosition, size),
      child: CustomPaint(
        size: size,
        painter: _ColorWheelPainter(hue: _hue),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final double hue;
  _ColorWheelPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 20.0;

    for (double i = 0; i < 360; i += 1) {
      final paint = Paint()
        ..color = HSVColor.fromAHSV(1.0, i, 1.0, 1.0).toColor()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 1;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - (strokeWidth / 2)),
        (i - 90) * 3.1415926535 / 180,
        1.5 * 3.1415926535 / 180,
        false,
        paint,
      );
    }

    final indicatorAngle = (hue - 90) * 3.1415926535 / 180;
    final indicatorOffset = Offset(
      center.dx + (radius - (strokeWidth / 2)) * math.cos(indicatorAngle),
      center.dy + (radius - (strokeWidth / 2)) * math.sin(indicatorAngle),
    );

    canvas.drawCircle(
      indicatorOffset, 
      12, 
      Paint()..color = Colors.black26..style = PaintingStyle.fill..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
    );
    canvas.drawCircle(
      indicatorOffset, 
      10, 
      Paint()..color = Colors.white..style = PaintingStyle.fill
    );
    canvas.drawCircle(
      indicatorOffset, 
      7, 
      Paint()..color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor()..style = PaintingStyle.fill
    );

    canvas.drawCircle(
      center, 
      radius - strokeWidth - 12, 
      Paint()..color = HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor()..style = PaintingStyle.fill
    );
    canvas.drawCircle(
      center, 
      radius - strokeWidth - 12, 
      Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 2
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) => oldDelegate.hue != hue;
}

