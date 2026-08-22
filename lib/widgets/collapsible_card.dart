// ignore_for_file: use_null_aware_elements
// ignore_for_file: use_if_null_to_and_then
import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

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
      duration: AppMotion.reveal,
      vsync: this,
    );
    _heightFactor = _controller.drive(CurveTween(curve: AppMotion.enter));
    if (widget.isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not `initState`: MediaQuery is not available there, and the platform's
    // reduce-motion flag can be toggled while the app is running. A controller
    // is the one place in the app where the duration outlives the build that
    // chose it, so it has to be re-read whenever the dependency changes.
    _controller.duration = AppMotion.durationOf(context, AppMotion.reveal);
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SizeTransition(
                        sizeFactor: _controller.drive(Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: AppMotion.enter))),
                        child: widget.subtitle != null 
                          ? Text(
                              widget.subtitle!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: colorScheme.outline),
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
