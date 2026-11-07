import 'package:flutter/material.dart';

/// Keeps a menu's traversal anchor separate from a tooltip inside its builder.
///
/// Without this boundary Flutter can merge two overlay traversal identifiers,
/// leaving orphaned nodes in Windows' AXTree (flutter/flutter#182444). Keep the
/// tooltip and menu accessible; do not suppress their semantics to hide errors.
class AppMenuAnchor extends StatelessWidget {
  const AppMenuAnchor({
    super.key,
    required this.menuChildren,
    required this.builder,
    this.controller,
    this.style,
    this.alignmentOffset,
  });

  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;
  final MenuController? controller;
  final MenuStyle? style;
  final Offset? alignmentOffset;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: controller,
    style: style,
    alignmentOffset: alignmentOffset,
    menuChildren: menuChildren,
    builder: (context, controller, child) =>
        Semantics(container: true, child: builder(context, controller, child)),
  );
}
