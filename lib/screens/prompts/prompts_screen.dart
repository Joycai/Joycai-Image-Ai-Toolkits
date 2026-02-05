import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';

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
  List<Map<String, dynamic>> _refinerPrompts = [];
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
    _loadPrompts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrompts() async {
    final prompts = await _db.getPrompts();
    setState(() {
      _userPrompts = prompts.where((p) => p['tag'] != 'Refiner').toList();
      _refinerPrompts = prompts.where((p) => p['tag'] == 'Refiner').toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    final filteredUser = _userPrompts.where((p) => 
      p['title'].toLowerCase().contains(_searchQuery) || 
      p['content'].toLowerCase().contains(_searchQuery) || 
      p['tag'].toLowerCase().contains(_searchQuery)
    ).toList();

    final filteredRefiner = _refinerPrompts.where((p) => 
      p['title'].toLowerCase().contains(_searchQuery) || 
      p['content'].toLowerCase().contains(_searchQuery)
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promptLibrary),
        actions: [
          Container(
            width: 300,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.filterModels, // Reusing existing search string or similar
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              onPressed: () => _showPromptDialog(l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.newPrompt),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.userPrompts),
            Tab(text: l10n.refinerPrompts),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPromptList(filteredUser, l10n, isRefiner: false),
          _buildPromptList(filteredRefiner, l10n, isRefiner: true),
        ],
      ),
    );
  }

  Widget _buildPromptList(List<Map<String, dynamic>> prompts, AppLocalizations l10n, {required bool isRefiner}) {
    if (prompts.isEmpty) {
      return _buildEmptyState(l10n, isRefiner);
    }
    
    final colorScheme = Theme.of(context).colorScheme;

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: prompts.length,
      onReorder: (oldIndex, newIndex) async {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = prompts.removeAt(oldIndex);
          prompts.insert(newIndex, item);
        });
        await _db.updatePromptOrder(prompts.map((p) => p['id'] as int).toList());
      },
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: child,
      ),
      itemBuilder: (context, index) {
        final prompt = prompts[index];
        return Card(
          key: ValueKey(prompt['id']),
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: InkWell(
            onTap: () => _showPromptDialog(l10n, prompt: prompt),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          prompt['title'],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      if (!isRefiner) ...[
                        _buildCategoryTag(prompt['tag']),
                        const SizedBox(width: 8),
                      ],
                      IconButton(
                        icon: const Icon(Icons.copy_all, size: 18),
                        tooltip: "Copy Prompt",
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
                        onPressed: () => _confirmDelete(l10n, prompt),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: Text(
                      prompt['content'],
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13, 
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Text(
        tag.toUpperCase(),
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey),
      ),
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
            isRefiner ? l10n.noPromptsSaved : l10n.noPromptsSaved, 
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
          ),
          const SizedBox(height: 8),
          Text(
            isRefiner ? "Add system prompts for the Refiner here." : l10n.saveFavoritePrompts, 
            style: const TextStyle(color: Colors.grey)
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showPromptDialog(l10n, isRefinerTarget: isRefiner),
            icon: const Icon(Icons.add),
            label: Text(l10n.newPrompt),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(AppLocalizations l10n, Map<String, dynamic> prompt) {
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
              await _db.deletePrompt(prompt['id']);
              if (context.mounted) {
                Navigator.pop(context);
                _loadPrompts();
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPromptDialog(AppLocalizations l10n, {Map<String, dynamic>? prompt, bool isRefinerTarget = false}) {
    final titleCtrl = TextEditingController(text: prompt?['title'] ?? '');
    final contentCtrl = TextEditingController(text: prompt?['content'] ?? '');
    String currentTag = prompt?['tag'] ?? (isRefinerTarget ? 'Refiner' : 'General');
    final tagCtrl = TextEditingController(text: currentTag);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tagCtrl, 
                          decoration: InputDecoration(
                            labelText: l10n.tagCategory,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.tag),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => tagCtrl.text = 'Refiner',
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: Text(l10n.setAsRefiner),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 12,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.promptContent,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      counterText: '${contentCtrl.text.length} characters',
                    ),
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
                  'tag': tagCtrl.text.isEmpty ? 'General' : tagCtrl.text,
                };
                if (prompt == null) {
                  data['sort_order'] = 0;
                  await _db.addPrompt(data);
                } else {
                  await _db.updatePrompt(prompt['id'] as int, data);
                }
                if (context.mounted) {
                  Navigator.pop(context);
                  _loadPrompts();
                }
              },
              child: Text(prompt == null ? l10n.save : l10n.update),
            ),
          ],
        ),
      ),
    );
  }
}
