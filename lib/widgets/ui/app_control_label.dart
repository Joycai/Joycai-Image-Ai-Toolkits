import 'package:flutter/material.dart';

/// Names a standard control without repeating its visual tooltip to readers.
class AppControlLabel extends StatelessWidget {
  const AppControlLabel({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: label,
      child: Tooltip(message: label, excludeFromSemantics: true, child: child),
    ),
  );
}
