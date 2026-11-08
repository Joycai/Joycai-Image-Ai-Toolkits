import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// Keyboard and semantics behavior for a custom-painted, single action.
/// The child supplies the existing appearance, never another interactive control.
class AppActionTarget extends StatefulWidget {
  const AppActionTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
    this.selected,
    this.excludeChildSemantics = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.control)),
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? label;
  final bool? selected;

  /// Use when an ancestor already supplies the complete accessible name.
  final bool excludeChildSemantics;
  final BorderRadius borderRadius;

  @override
  State<AppActionTarget> createState() => _AppActionTargetState();
}

class _AppActionTargetState extends State<AppActionTarget> {
  final _focus = FocusNode();
  bool _highlight = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _activate() {
    if (widget.onTap == null) return;
    _focus.requestFocus();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return FocusableActionDetector(
      focusNode: _focus,
      enabled: enabled,
      includeFocusSemantics: false,
      onFocusChange: (_) => setState(() {}),
      onShowFocusHighlight: (value) => setState(() => _highlight = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: widget.selected,
        label: widget.label,
        focusable: enabled,
        focused: enabled && _focus.hasFocus,
        onFocus: enabled ? _focus.requestFocus : null,
        onTap: enabled ? _activate : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: enabled ? _activate : null,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: _highlight && enabled
                  ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                  : null,
            ),
            child: ExcludeSemantics(
              excluding: widget.label != null || widget.excludeChildSemantics,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
