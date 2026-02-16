import 'package:flutter/material.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';

class PromptLibrarySheet extends StatefulWidget {
  final List<Prompt> allPrompts;
  final List<PromptTag> tags;
  final String initialContent;
  final Function(String, bool isAppend) onApply;

  const PromptLibrarySheet({
    super.key,
    required this.allPrompts,
    required this.tags,
    required this.initialContent,
    required this.onApply,
  });

  static Future<void> show({
    required BuildContext context,
    required List<Prompt> allPrompts,
    required List<PromptTag> tags,
    required String initialContent,
    required Function(String, bool isAppend) onApply,
  }) async {
    final isNarrow = Responsive.isNarrow(context);
    
    if (isNarrow) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => PromptLibrarySheet(
            allPrompts: allPrompts,
            tags: tags,
            initialContent: initialContent,
            onApply: onApply,
          ),
        ),
      );
    } else {
      await showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) => Align(
          alignment: Alignment.centerRight,
          child: PromptLibrarySheet(
            allPrompts: allPrompts,
            tags: tags,
            initialContent: initialContent,
            onApply: onApply,
          ),
        ),
        transitionBuilder: (context, anim1, anim2, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
      );
    }
  }

  @override
  State<PromptLibrarySheet> createState() => _PromptLibrarySheetState();
}

class _PromptLibrarySheetState extends State<PromptLibrarySheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _selectedFilterTagIds = {};
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);

    final filteredPrompts = widget.allPrompts.where((p) {
      final matchesSearch = p.title.toLowerCase().contains(_searchQuery) || 
                            p.content.toLowerCase().contains(_searchQuery);
      if (_selectedFilterTagIds.isEmpty) return matchesSearch;
      final promptTagIds = p.tags.map((t) => t.id!).toSet();
      return matchesSearch && _selectedFilterTagIds.any((id) => promptTagIds.contains(id));
    }).toList();

    final sheetContent = Container(
      width: isNarrow ? double.infinity : 450,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: isNarrow ? const BorderRadius.vertical(top: Radius.circular(20)) : null,
        boxShadow: isNarrow ? null : [
          BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 20, offset: const Offset(-5, 0))
        ],
      ),
      child: Material( // Need material for inkwell and text styles
        child: Column(
          children: [
            _buildHeader(l10n, colorScheme, isNarrow),
            _buildTagFilterBar(colorScheme),
            const Divider(height: 1),
            Expanded(
              child: _buildPromptList(filteredPrompts, l10n, colorScheme),
            ),
          ],
        ),
      ),
    );

    return isNarrow ? sheetContent : sheetContent;
  }

  Widget _buildHeader(AppLocalizations l10n, ColorScheme colorScheme, bool isNarrow) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.library_books_outlined, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.promptLibrary,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          SizedBox(
            width: isNarrow ? 120 : 180,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.filterPrompts, 
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(100),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTagFilterBar(ColorScheme colorScheme) {
    if (widget.tags.isEmpty) return const SizedBox.shrink();
    
    return Container(
      height: 48,
      padding: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: widget.tags.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = widget.tags[index];
          final id = tag.id as int;
          final isSelected = _selectedFilterTagIds.contains(id);
          final color = Color(tag.color);

          return FilterChip(
            label: Text(tag.name, style: TextStyle(
              fontSize: 11, 
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          );
        },
      ),
    );
  }

  Widget _buildPromptList(List<Prompt> prompts, AppLocalizations l10n, ColorScheme colorScheme) {
    if (prompts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_outlined, size: 48, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(l10n.noPromptsSaved, style: TextStyle(color: colorScheme.outline)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: prompts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final p = prompts[index];
        return _CompactPromptCard(
          prompt: p,
          onApply: (isAppend) {
            widget.onApply(p.content, isAppend);
            Navigator.pop(context);
          },
        );
      },
    );
  }
}

class _CompactPromptCard extends StatelessWidget {
  final Prompt prompt;
  final Function(bool isAppend) onApply;

  const _CompactPromptCard({required this.prompt, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    prompt.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (prompt.tags.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(prompt.tags.first.color).withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      prompt.tags.first.name,
                      style: TextStyle(fontSize: 10, color: Color(prompt.tags.first.color), fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              prompt.content,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => onApply(true),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.add, style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => onApply(false),
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(l10n.apply, style: const TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
