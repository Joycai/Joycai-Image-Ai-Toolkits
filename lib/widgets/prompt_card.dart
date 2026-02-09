import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/prompt.dart';

class PromptCard extends StatelessWidget {
  final Prompt prompt;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showCategory;
  final VoidCallback? onMoveToTop;
  final VoidCallback? onMoveToBottom;

  const PromptCard({
    super.key,
    required this.prompt,
    required this.isExpanded,
    required this.onToggle,
    this.actions,
    this.leading,
    this.showCategory = true,
    this.onMoveToTop,
    this.onMoveToBottom,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryTagColor = prompt.tags.isNotEmpty 
        ? Color(prompt.tags.first.color) 
        : Colors.blueGrey;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? colorScheme.primary.withAlpha(80) : colorScheme.outlineVariant,
          width: isExpanded ? 2 : 1,
        ),
        boxShadow: isExpanded ? [
          BoxShadow(
            color: colorScheme.primary.withAlpha(30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent line
            if (showCategory)
              Container(
                width: 4,
                color: primaryTagColor.withAlpha(180),
              ),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, colorScheme),
                  if (isExpanded) _buildExpandedContent(context, colorScheme)
                  else _buildCollapsedContent(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 8),
            ],
            AnimatedRotation(
              duration: const Duration(milliseconds: 200),
              turns: isExpanded ? 0.25 : 0,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isExpanded ? colorScheme.primary : colorScheme.outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                prompt.title,
                style: TextStyle(
                  fontWeight: isExpanded ? FontWeight.bold : FontWeight.w600,
                  fontSize: 14,
                  color: isExpanded ? colorScheme.primary : colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showCategory) ...[
              _buildTagsList(),
              const SizedBox(width: 8),
            ],
            
            // Reordering actions
            if (onMoveToTop != null || onMoveToBottom != null)
              _buildSortActions(colorScheme),

            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }

  Widget _buildSortActions(ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onMoveToTop != null)
          IconButton(
            icon: const Icon(Icons.vertical_align_top_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: "Move to Top",
            onPressed: onMoveToTop,
            color: colorScheme.outline,
          ),
        if (onMoveToBottom != null)
          IconButton(
            icon: const Icon(Icons.vertical_align_bottom_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: "Move to Bottom",
            onPressed: onMoveToBottom,
            color: colorScheme.outline,
          ),
        const VerticalDivider(width: 12, indent: 8, endIndent: 8),
      ],
    );
  }

  Widget _buildTagsList() {
    final displayTags = prompt.tags.isEmpty 
        ? [null] 
        : prompt.tags;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: displayTags.map((t) => _buildCategoryTag(
        t?.name ?? 'General',
        t?.color,
      )).toList(),
    );
  }

  Widget _buildExpandedContent(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: colorScheme.outlineVariant.withAlpha(100)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: prompt.isMarkdown
                ? SelectionArea(
                    child: MarkdownBody(
                      data: prompt.content,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 13, 
                          height: 1.6, 
                          color: colorScheme.onSurface.withAlpha(230)
                        ),
                        code: TextStyle(
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  )
                : SelectionArea(
                    child: Text(
                      prompt.content,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedContent(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 40.0, bottom: 12, right: 16),
      child: Text(
        prompt.content.toString().replaceAll('\n', ' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildCategoryTag(String tag, int? tagColor) {
    final color = tagColor != null ? Color(tagColor) : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10, 
          fontWeight: FontWeight.bold, 
          color: color.withAlpha(220),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
