import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class PromptCard extends StatelessWidget {
  final Map<String, dynamic> prompt;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showCategory;
  final double maxHeight;

  const PromptCard({
    super.key,
    required this.prompt,
    required this.isExpanded,
    required this.onToggle,
    this.actions,
    this.leading,
    this.showCategory = true,
    this.maxHeight = 100,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 12),
                  ],
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      prompt['title'],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showCategory) ...[
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: ((prompt['tags'] as List?) ?? []).isEmpty
                          ? [_buildCategoryTag('General', null)]
                          : (prompt['tags'] as List).map((t) {
                              return _buildCategoryTag(t['name'], t['color']);
                            }).toList(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (actions != null) ...actions!,
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  prompt['is_markdown'] == 1
                      ? SelectionArea(
                          child: MarkdownBody(
                            data: prompt['content'],
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(fontSize: 13, height: 1.5),
                            ),
                          ),
                        )
                      : SelectionArea(
                          child: Text(
                            prompt['content'],
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 44.0, bottom: 12, right: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  prompt['content'].toString().replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryTag(String tag, int? tagColor) {
    final color = tagColor != null ? Color(tagColor) : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        tag.toUpperCase(),
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
