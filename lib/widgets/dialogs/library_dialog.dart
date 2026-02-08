import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../markdown_editor.dart';
import '../prompt_card.dart';

class LibraryDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allPrompts;
  final List<Map<String, dynamic>> tags;
  final String initialContent;
  final Function(String, bool isAppend) onApply;

  const LibraryDialog({
    super.key,
    required this.allPrompts,
    required this.tags,
    required this.initialContent,
    required this.onApply,
  });

  @override
  State<LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends State<LibraryDialog> {
  late TextEditingController _draftController;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isMarkdown = true;
  final Set<int> _expandedPromptIds = {};
  final Set<int> _selectedFilterTagIds = {};
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController(text: widget.initialContent);
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _draftController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _appendToDraft(String text) {
    if (_draftController.text.isNotEmpty) {
      _draftController.text += "\n\n$text";
    } else {
      _draftController.text = text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final filteredPrompts = widget.allPrompts.where((p) {
      final matchesSearch = p['title'].toLowerCase().contains(_searchQuery) || 
                            p['content'].toLowerCase().contains(_searchQuery);
      
      if (_selectedFilterTagIds.isEmpty) return matchesSearch;
      
      final promptTagIds = (p['tags'] as List).map((t) => t['id'] as int).toSet();
      // "OR" logic: if any selected tag matches
      final matchesTags = _selectedFilterTagIds.any((id) => promptTagIds.contains(id));
      
      return matchesSearch && matchesTags;
    }).toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 800),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.library_books, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(l10n.promptLibrary, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 32),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.filterPrompts,
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Pane: Categories / Filters
                  Container(
                    width: 220,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
                      color: colorScheme.surfaceContainerLow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text("FILTER BY TAGS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.outline)),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: widget.tags.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final tag = widget.tags[index];
                              final id = tag['id'] as int;
                              final isSelected = _selectedFilterTagIds.contains(id);
                              final color = Color(tag['color'] ?? 0xFF607D8B);
                              
                              return FilterChip(
                                label: Text(tag['name'], style: TextStyle(
                                  fontSize: 12, 
                                  color: isSelected ? Colors.white : color,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
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
                                visualDensity: VisualDensity.compact,
                              );
                            },
                          ),
                        ),
                        if (_selectedFilterTagIds.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextButton.icon(
                              onPressed: () => setState(() => _selectedFilterTagIds.clear()),
                              icon: const Icon(Icons.clear_all, size: 16),
                              label: const Text("Clear Filters", style: TextStyle(fontSize: 12)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Middle Pane: Prompts
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text("SELECT PROMPT (${filteredPrompts.length})", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.outline)),
                        ),
                        Expanded(
                          child: filteredPrompts.isEmpty 
                          ? Center(child: Text(l10n.noPromptsSaved)) 
                          : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredPrompts.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final p = filteredPrompts[index];
                              final id = p['id'] as int;
                              final isExpanded = _expandedPromptIds.contains(id);

                              return PromptCard(
                                prompt: p,
                                isExpanded: isExpanded,
                                onToggle: () => setState(() {
                                  if (isExpanded) {
                                    _expandedPromptIds.remove(id);
                                  } else {
                                    _expandedPromptIds.add(id);
                                  }
                                }),
                                showCategory: true,
                                actions: [
                                  TextButton.icon(
                                    onPressed: () => setState(() => _draftController.text = p['content']),
                                    icon: const Icon(Icons.find_replace, size: 14),
                                    label: const Text("Replace", style: TextStyle(fontSize: 10)),
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                  ),
                                  const SizedBox(width: 4),
                                  FilledButton.icon(
                                    onPressed: () => setState(() => _appendToDraft(p['content'])),
                                    icon: const Icon(Icons.add, size: 14),
                                    label: const Text("Append", style: TextStyle(fontSize: 10)),
                                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right Pane: Drafting Area
                  Container(
                    width: 350,
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
                      color: colorScheme.surfaceContainerLowest,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("PROMPT DRAFT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.outline)),
                          const SizedBox(height: 12),
                          Expanded(
                            child: MarkdownEditor(
                              controller: _draftController,
                              label: "Draft",
                              isMarkdown: _isMarkdown,
                              onMarkdownChanged: (v) => setState(() => _isMarkdown = v), 
                              maxLines: 20,
                              initiallyPreview: false,
                              expand: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                widget.onApply(_draftController.text, false);
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.check),
                              label: const Text("Apply (Overwrite)"),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                widget.onApply(_draftController.text, true);
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.add_task),
                              label: const Text("Apply (Append)"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}