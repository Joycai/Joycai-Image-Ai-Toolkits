import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// Non-pointer access to an existing splitter's delta and persistence callbacks.
class AppResizeTarget extends StatefulWidget {
  const AppResizeTarget({
    super.key,
    required this.axis,
    required this.onDrag,
    required this.child,
    this.onDragEnd,
  });

  final Axis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;
  final Widget child;

  @override
  State<AppResizeTarget> createState() => _AppResizeTargetState();
}

class _AppResizeTargetState extends State<AppResizeTarget> {
  bool _focused = false;

  void _move(double delta) {
    widget.onDrag(delta);
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? lookupAppLocalizations(const Locale('en'));
    final horizontal = widget.axis == Axis.horizontal;
    return MergeSemantics(
      child: Semantics(
        label: l10n.resizePane,
        customSemanticsActions: {
          CustomSemanticsAction(
            label: horizontal ? l10n.moveDividerLeft : l10n.moveDividerUp,
          ): () =>
              _move(-20),
          CustomSemanticsAction(
            label: horizontal ? l10n.moveDividerRight : l10n.moveDividerDown,
          ): () =>
              _move(20),
        },
        child: Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
            if (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isAltPressed) {
              return KeyEventResult.ignored;
            }
            final key = event.logicalKey;
            if (key == (horizontal ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowUp)) {
              _move(-20);
              return KeyEventResult.handled;
            }
            if (key ==
                (horizontal ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowDown)) {
              _move(20);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: _focused
                  ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
