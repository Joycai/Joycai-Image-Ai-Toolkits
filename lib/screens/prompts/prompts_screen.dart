import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
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
  
  List<Map<String, dynamic>> _userPrompts = [];
  List<Map<String, dynamic>> _systemPrompts = [];
  List<Map<String, dynamic>> _tags = [];
  String _searchQuery = "";
  final Set<int> _selectedFilterTagIds = {};
  final Set<int> _expandedPromptIds = {};
  final Set<int> _expandedSysPromptIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      _userPrompts = List.from(userPrompts);
      _systemPrompts = List.from(systemPrompts);
      _tags = List.from(tags);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    
    final filteredUser = _userPrompts.where((p) {
      final matchesSearch = p['title'].toLowerCase().contains(_searchQuery) || 
                            p['content'].toLowerCase().contains(_searchQuery);
      
      if (_selectedFilterTagIds.isEmpty) return matchesSearch;
      
      final promptTagIds = (p['tags'] as List).map((t) => t['id'] as int).toSet();
      final matchesTags = _selectedFilterTagIds.every((id) => promptTagIds.contains(id));
      
      return matchesSearch && matchesTags;
    }).toList();

    final filteredRefiner = _systemPrompts.where((p) {
      return p['title'].toLowerCase().contains(_searchQuery) || 
             p['content'].toLowerCase().contains(_searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promptLibrary),
        actions: [
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
            icon: const Icon(Icons.upload),
            tooltip: l10n.importSettings,
            onPressed: () => _importPrompts(l10n),
          ),
          IconButton(
            icon: const Icon(Icons.download),
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
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.userPrompts),
            Tab(text: l10n.refinerPrompts),
            Tab(text: l10n.categoriesTab),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_tabController.index == 0 && _tags.isNotEmpty)
            _buildFilterBar(colorScheme),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserPromptList(filteredUser, l10n),
                _buildSystemPromptList(filteredRefiner, l10n),
                _buildTagList(l10n),
              ],
            ),
          ),
        ],
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
          final id = tag['id'] as int;
          final isSelected = _selectedFilterTagIds.contains(id);
          final color = Color(tag['color'] ?? 0xFF607D8B);

          return FilterChip(
            label: Text(tag['name'], style: TextStyle(
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

  Widget _buildUserPromptList(List<Map<String, dynamic>> prompts, AppLocalizations l10n) {
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
        await _db.updatePromptOrder(_userPrompts.map((p) => p['id'] as int).toList());
      },
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: child,
      ),
      itemBuilder: (context, index) {
        final prompt = prompts[index];
        final id = prompt['id'] as int;
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
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: prompt['content']));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.copiedToClipboard(prompt['title']))),
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

  Widget _buildSystemPromptList(List<Map<String, dynamic>> prompts, AppLocalizations l10n) {
    if (prompts.isEmpty) {
      return _buildEmptyState(l10n, true);
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: prompts.length,
      itemBuilder: (context, index) {
        final prompt = prompts[index];
        final id = prompt['id'] as int;
        final isExpanded = _expandedSysPromptIds.contains(id);

        return Padding(
          key: ValueKey('sys_$id'),
          padding: const EdgeInsets.only(bottom: 12),
          child: PromptCard(
            prompt: prompt,
            isExpanded: isExpanded,
            onToggle: () => setState(() {
              if (isExpanded) {
                _expandedSysPromptIds.remove(id);
              } else {
                _expandedSysPromptIds.add(id);
              }
            }),
            leading: const Icon(Icons.auto_fix_high, color: Colors.purple, size: 20),
            showCategory: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: prompt['content']));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.copiedToClipboard(prompt['title']))),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _showSystemPromptDialog(l10n, prompt: prompt),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => _confirmDelete(l10n, prompt, isSystem: true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTagList(AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tags.length,
      itemBuilder: (context, index) {
        final tag = _tags[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(tag['color'] ?? 0xFF607D8B),
              radius: 12,
            ),
            title: Text(tag['name']),
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

  void _confirmDelete(AppLocalizations l10n, Map<String, dynamic> prompt, {required bool isSystem}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePromptConfirmTitle),
        content: Text(l10n.deletePromptConfirmMessage(prompt['title'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (isSystem) {
                await _db.deleteSystemPrompt(prompt['id']);
              } else {
                await _db.deletePrompt(prompt['id']);
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

  void _confirmDeleteTag(AppLocalizations l10n, Map<String, dynamic> tag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text("Are you sure you want to delete category \"${tag['name']}\"? Prompts will be moved to General."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.deletePromptTag(tag['id']);
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

  void _showTagDialog(AppLocalizations l10n, {Map<String, dynamic>? tag}) {
    final nameCtrl = TextEditingController(text: tag?['name'] ?? '');
    final hexCtrl = TextEditingController(text: tag != null ? '#${(tag['color'] as int).toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}' : '#607D8B');
    int selectedColor = tag?['color'] ?? AppConstants.tagColors.first.toARGB32();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tag == null ? l10n.addCategory : l10n.editCategory),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.name)),
              const SizedBox(height: 16),
              TextField(
                controller: hexCtrl, 
                decoration: const InputDecoration(labelText: 'HEX Color (e.g. #FFAABB)', prefixIcon: Icon(Icons.colorize)),
                onChanged: (v) {
                  if (v.startsWith('#') && v.length == 7) {
                    try {
                      final color = int.parse('FF${v.substring(1)}', radix: 16);
                      setDialogState(() => selectedColor = color);
                    } catch (_) {}
                  }
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppConstants.tagColors.map((color) => InkWell(
                  onTap: () {
                    setDialogState(() {
                      selectedColor = color.toARGB32();
                      hexCtrl.text = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                    });
                  },
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
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () async {
                final data = {'name': nameCtrl.text, 'color': selectedColor};
                if (tag == null) {
                  await _db.addPromptTag(data);
                } else {
                  await _db.updatePromptTag(tag['id'], data);
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

  void _showSystemPromptDialog(AppLocalizations l10n, {Map<String, dynamic>? prompt}) {
    final titleCtrl = TextEditingController(text: prompt?['title'] ?? '');
    final contentCtrl = TextEditingController(text: prompt?['content'] ?? '');
    bool isMarkdown = (prompt?['is_markdown'] ?? 1) == 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.auto_fix_high, color: Colors.purple),
              const SizedBox(width: 12),
              Text(prompt == null ? "New Refiner Prompt" : "Edit Refiner Prompt"),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleCtrl, decoration: InputDecoration(labelText: l10n.title, border: const OutlineInputBorder())),
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
                  'type': 'refiner',
                  'is_markdown': isMarkdown ? 1 : 0,
                };
                if (prompt == null) {
                  await _db.addSystemPrompt(data);
                } else {
                  await _db.updateSystemPrompt(prompt['id'], data);
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

  void _showPromptDialog(AppLocalizations l10n, {Map<String, dynamic>? prompt}) {
    final titleCtrl = TextEditingController(text: prompt?['title'] ?? '');
    final contentCtrl = TextEditingController(text: prompt?['content'] ?? '');
    bool isMarkdown = (prompt?['is_markdown'] ?? 1) == 1;

    final Set<int> selectedTagIds = {};
    if (prompt != null && prompt['tags'] != null) {
      for (var t in prompt['tags']) {
        selectedTagIds.add(t['id'] as int);
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
                      final id = t['id'] as int;
                      final isSelected = selectedTagIds.contains(id);
                      final color = Color(t['color'] ?? 0xFF607D8B);
                      return FilterChip(
                        label: Text(t['name'], style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : color)),
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
                };
                if (prompt == null) {
                  data['sort_order'] = 0;
                  await _db.addPrompt(data, tagIds: selectedTagIds.toList());
                } else {
                  await _db.updatePrompt(prompt['id'] as int, data, tagIds: selectedTagIds.toList());
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
      'tags': _tags,
      'user_prompts': _userPrompts,
      'system_prompts': _systemPrompts,
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Import Prompts?"),
        content: const Text("This will MERGE imported prompts and tags with your current library. Existing items with same IDs may be updated."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Merge Import")),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final file = File(result.files.single.path!);
      final Map<String, dynamic> data = jsonDecode(await file.readAsString());
      
      await _db.database.then((db) async {
        await db.transaction((txn) async {
          // Import Tags first to get new IDs
          final Map<int, int> tagIdMap = {};
          if (data['tags'] != null) {
            for (var t in data['tags']) {
              final oldId = t['id'] as int;
              final Map<String, dynamic> row = Map.from(t)..remove('id');
              // Check if tag exists by name
              final existing = await txn.query('prompt_tags', where: 'name = ?', whereArgs: [row['name']]);
              if (existing.isNotEmpty) {
                tagIdMap[oldId] = existing.first['id'] as int;
              } else {
                final newId = await txn.insert('prompt_tags', row);
                tagIdMap[oldId] = newId;
              }
            }
          }

          // Import User Prompts
          if (data['user_prompts'] != null) {
            for (var p in data['user_prompts']) {
              final Map<String, dynamic> row = Map.from(p)..remove('id');
              final List<dynamic>? tags = row['tags'];
              row.remove('tags');
              row.remove('tag_name'); // Clean up old format fields if any
              row.remove('tag_color');
              row.remove('tag_is_system');
              row.remove('tag_id');

              final newPromptId = await txn.insert('prompts', row);
              if (tags != null) {
                for (var t in tags) {
                  final oldTagId = t['id'] as int;
                  final newTagId = tagIdMap[oldTagId];
                  if (newTagId != null) {
                    await txn.insert('prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
                  }
                }
              }
            }
          }

          // Import System Prompts
          if (data['system_prompts'] != null) {
            for (var p in data['system_prompts']) {
              final Map<String, dynamic> row = Map.from(p)..remove('id');
              await txn.insert('system_prompts', row);
            }
          }
        });
      });

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