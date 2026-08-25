import 'package:flutter/material.dart';

/// A run of settings rows, optionally under a heading.
///
/// [title] is null for a section whose name is already on the pane around it —
/// which is every top-level settings category, because both the two-pane
/// header and the mobile detail page's app bar name it. It had been printed
/// twice on every settings screen. A *sub*-section inside a category still
/// wants one: 「代理设置」 and 「MCP 服务器设置」 are two groups under
/// 「连通性」, and nothing else says so.
///
/// Can own the gap between its children rather than leaving each caller to
/// sprinkle `SizedBox`es — pass `gap: 10`, which is what `D1 12a` sets between
/// settings rows. Defaults to zero, because one section (appearance) is not a
/// run of rows at all but four selector blocks that want their own rhythm.
class AppSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double gap;

  const AppSection({
    super.key,
    this.title,
    required this.children,
    this.padding = const EdgeInsets.only(bottom: 32),
    this.gap = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                title!,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          for (final (int i, Widget child) in children.indexed) ...[
            if (i > 0) SizedBox(height: gap),
            child,
          ],
        ],
      ),
    );
  }
}
