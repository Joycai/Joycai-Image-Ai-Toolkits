import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../app_button.dart';
import '../app_empty_state.dart';
import '../app_search_field.dart';
import '../app_side_panel.dart';

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
    await AppSidePanel.show<void>(
      context,
      builder: (context) => PromptLibrarySheet(
        allPrompts: allPrompts,
        tags: tags,
        initialContent: initialContent,
        onApply: onApply,
      ),
    );
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

    // Surface, width and shadow belong to AppSidePanel, which is what
    // presents this. All that is left here is what the panel contains.
    return Column(
      children: [
        _buildHeader(l10n, colorScheme, isNarrow),
        _buildTagFilterBar(colorScheme),
        const Divider(height: 1),
        Expanded(
          child: _buildPromptList(filteredPrompts, l10n, colorScheme),
        ),
      ],
    );
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
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          SizedBox(
            width: isNarrow ? 120 : 180,
            height: 36,
            child: AppSearchField(
              controller: _searchCtrl,
              hint: l10n.filterPrompts,
              compact: true,
              onChanged: (_) => setState(() {}),
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
            label: Text(tag.name, style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: isSelected ? Colors.white : color,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400
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
      return AppEmptyState(
        icon: Icons.search_off_outlined,
        label: l10n.noPromptsSaved,
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
                    style: Theme.of(context).textTheme.titleMedium,
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Color(prompt.tags.first.color),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              prompt.content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: l10n.add,
                  icon: Icons.add,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.compact,
                  onPressed: () => onApply(true),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: l10n.apply,
                  icon: Icons.check,
                  size: AppButtonSize.compact,
                  onPressed: () => onApply(false),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
