import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
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
                  ClipRect(
                    child: AnimatedSize(
                      duration: AppMotion.reveal,
                      curve: AppMotion.enter,
                      alignment: Alignment.topCenter,
                      child: isExpanded
                          ? _buildExpandedContent(context, colorScheme)
                          : _buildCollapsedContent(context, colorScheme),
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

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    // Everything on this row apart from the title is fixed-width chrome — a
    // chevron and up to five icon buttons. On a phone that leaves the title a
    // word at best, and a card carrying two tags overflows outright. The tags
    // are the one part that can move, so below the mobile breakpoint they drop
    // to a line of their own, indented to meet the preview text underneath.
    final tagsInline = !Responsive.isMobile(context);

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 8),
                ],
                AnimatedRotation(
                  duration: AppMotion.reveal,
                  curve: AppMotion.enter,
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: isExpanded ? FontWeight.bold : FontWeight.w600,
                          color: isExpanded ? colorScheme.primary : colorScheme.onSurface,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showCategory && tagsInline) ...[
                  _buildTagsList(context, alignment: WrapAlignment.end),
                  const SizedBox(width: 8),
                ],

                // Reordering actions
                if (onMoveToTop != null || onMoveToBottom != null)
                  _buildSortActions(context, colorScheme),

                ...?actions,
              ],
            ),
            if (showCategory && !tagsInline)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 8),
                child: _buildTagsList(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortActions(BuildContext context, ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onMoveToTop != null)
          IconButton(
            icon: const Icon(Icons.vertical_align_top_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: l10n.moveToTop,
            onPressed: onMoveToTop,
            color: colorScheme.outline,
          ),
        if (onMoveToBottom != null)
          IconButton(
            icon: const Icon(Icons.vertical_align_bottom_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: l10n.moveToBottom,
            onPressed: onMoveToBottom,
            color: colorScheme.outline,
          ),
        const VerticalDivider(width: 12, indent: 8, endIndent: 8),
      ],
    );
  }

  Widget _buildTagsList(BuildContext context, {WrapAlignment alignment = WrapAlignment.start}) {
    final displayTags = prompt.tags.isEmpty
        ? [null]
        : prompt.tags;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: alignment,
      children: displayTags.map((t) => _buildCategoryTag(
            context,
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
                        p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.6,
                              color: colorScheme.onSurface.withAlpha(230),
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

  Widget _buildCollapsedContent(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 40.0, bottom: 12, right: 16),
      child: Text(
        prompt.content.toString().replaceAll('\n', ' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
      ),
    );
  }

  Widget _buildCategoryTag(BuildContext context, String tag, int? tagColor) {
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color.withAlpha(220),
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}
