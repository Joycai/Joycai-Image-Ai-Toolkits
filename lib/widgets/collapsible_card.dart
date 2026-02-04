// ignore_for_file: use_null_aware_elements
// ignore_for_file: use_if_null_to_and_then
import 'package:flutter/material.dart';
import '../core/constants.dart';

class CollapsibleCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget? trailing;
  final IconData? expandedIcon;
  final IconData? collapsedIcon;

  const CollapsibleCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.content,
    required this.isExpanded,
    required this.onToggle,
    this.trailing,
    this.expandedIcon,
    this.collapsedIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Icon(
                  isExpanded 
                    ? (expandedIcon ?? Icons.keyboard_arrow_down) 
                    : (collapsedIcon ?? Icons.keyboard_arrow_right),
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (!isExpanded && subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 11, color: colorScheme.outline),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
        AnimatedContainer(
          duration: AppConstants.animationDuration,
          height: isExpanded ? null : 0,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(),
          child: isExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: content,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
