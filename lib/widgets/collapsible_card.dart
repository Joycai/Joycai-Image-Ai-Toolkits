// ignore_for_file: use_null_aware_elements
// ignore_for_file: use_if_null_to_and_then
import 'package:flutter/material.dart';

import '../core/constants.dart';

class CollapsibleCard extends StatefulWidget {
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
  State<CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<CollapsibleCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppConstants.animationDuration,
      vsync: this,
    );
    _heightFactor = _controller.drive(CurveTween(curve: Curves.easeInOut));
    if (widget.isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(CollapsibleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                RotationTransition(
                  turns: _heightFactor.drive(Tween(begin: 0.0, end: 0.25)),
                  child: Icon(
                    widget.collapsedIcon ?? Icons.keyboard_arrow_right,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      SizeTransition(
                        sizeFactor: _controller.drive(Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut))),
                        child: widget.subtitle != null 
                          ? Text(
                              widget.subtitle!,
                              style: TextStyle(fontSize: 11, color: colorScheme.outline),
                            )
                          : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _heightFactor,
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: widget.content,
          ),
        ),
      ],
    );
  }
}
