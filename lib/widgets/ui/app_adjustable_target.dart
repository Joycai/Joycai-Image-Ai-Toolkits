import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_tokens.dart';

/// Accessible hue adjustment around an existing pointer-driven color surface.
class AppAdjustableTarget extends StatefulWidget {
  const AppAdjustableTarget({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final Widget child;

  @override
  State<AppAdjustableTarget> createState() => _AppAdjustableTargetState();
}

class _AppAdjustableTargetState extends State<AppAdjustableTarget> {
  bool _focused = false;
  double _next(int direction) => (widget.value + direction * 5 + 360) % 360;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      slider: true,
      label: widget.label,
      value: '${widget.value.round()}°',
      increasedValue: '${_next(1).round()}°',
      decreasedValue: '${_next(-1).round()}°',
      onIncrease: () => widget.onChanged(_next(1)),
      onDecrease: () => widget.onChanged(_next(-1)),
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowRight): _HueStep(1),
          SingleActivator(LogicalKeyboardKey.arrowUp): _HueStep(1),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _HueStep(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown): _HueStep(-1),
        },
        actions: {
          _HueStep: CallbackAction<_HueStep>(
            onInvoke: (intent) {
              widget.onChanged(_next(intent.direction));
              return null;
            },
          ),
        },
        child: ExcludeSemantics(
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: _focused
                  ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

class _HueStep extends Intent {
  const _HueStep(this.direction);
  final int direction;
}
