import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../markdown_editor.dart';
import '../prompt_card.dart';

class LibraryDialog extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> groupedPrompts;
  final List<Map<String, dynamic>> tags;
  final String initialContent;
  final Function(String, bool isAppend) onApply;

  const LibraryDialog({
    super.key,
    required this.groupedPrompts,
    required this.tags,
    required this.initialContent,
    required this.onApply,
  });

  @override
  State<LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends State<LibraryDialog> {
  String? _selectedCategory;
  late TextEditingController _draftController;
  bool _isMarkdown = true;
  final Set<int> _expandedPromptIds = {};

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController(text: widget.initialContent);
    if (widget.groupedPrompts.isNotEmpty) {
      _selectedCategory = widget.groupedPrompts.keys.first;
    }
  }

  @override
  void dispose() {
    _draftController.dispose();
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
    final categories = widget.groupedPrompts.keys.toList();
    final currentPrompts = _selectedCategory != null 
        ? (widget.groupedPrompts[_selectedCategory] ?? []) 
        : <Map<String, dynamic>>[];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 800),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.library_books, color: Colors.blue),
                      const SizedBox(width: 12),
                      Text(l10n.promptLibrary, style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
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
                  // Left Pane: Categories
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
                      color: colorScheme.surfaceContainerLow,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text("CATEGORIES", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.outline)),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: categories.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final catName = categories[index];
                              final isSelected = catName == _selectedCategory;
                              final tagData = widget.tags.cast<Map<String, dynamic>?>().firstWhere((t) => t?['name'] == catName, orElse: () => null);
                              
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Color(tagData?['color'] ?? 0xFF607D8B),
                                  radius: 6,
                                ),
                                title: Text(catName, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                selected: isSelected,
                                selectedTileColor: colorScheme.secondaryContainer,
                                selectedColor: colorScheme.onSecondaryContainer,
                                onTap: () => setState(() => _selectedCategory = catName),
                                dense: true,
                              );
                            },
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
                          child: Text("SELECT PROMPT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.outline)),
                        ),
                        Expanded(
                          child: currentPrompts.isEmpty 
                          ? Center(child: Text(l10n.noPromptsSaved)) 
                          : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: currentPrompts.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final p = currentPrompts[index];
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
                                showCategory: false,
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
