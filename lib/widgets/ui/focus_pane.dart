import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// A focus region — the unit that answers selection keys (`00f` 帧 3).
///
/// One of these wraps each column that can own the keyboard: the folder tree,
/// the file grid, the staging panel. Clicking anywhere inside makes it the
/// active pane, and `Delete` / `F2` / `Enter` / `⌘A` then act on *its*
/// selection and nothing else. That is the whole point: with the keys spread
/// across two tiers, whichever widget happened to take focus first kept them,
/// which is how `Delete` came to delete a folder clicked minutes earlier while
/// three files sat selected in the grid.
///
/// Deliberately one node per pane, never one per card: a few hundred
/// `FocusNode`s cost real memory and pollute the Tab order, and the only
/// feature that would need per-card focus — arrow-key navigation — is phase
/// two.
///
/// The active pane is drawn as a 2px accent rule along its top edge. It is a
/// quiet mark on purpose: the loud half of the signal is the selection itself,
/// which every pane draws in the accent while it is active and in neutral
/// while it is not (see `FocusPane.isActive`). The question a user actually
/// has is "does the keyboard still own the things I picked", so the answer is
/// painted on the things they picked.
class FocusPane extends StatelessWidget {
  const FocusPane({
    super.key,
    required this.node,
    required this.child,
    this.onKeyEvent,
    this.showActiveEdge = true,
  });

  /// Owned by the caller — a pane outlives any one build.
  final FocusNode node;

  /// The pane's keys. Events reach this only while the pane (or something
  /// inside it) holds focus, which is what makes "who answers `Delete`" a
  /// question with exactly one answer.
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  final Widget child;

  /// Off where the pane's own chrome already says it is active, or where the
  /// top edge is not visible (a drawer).
  final bool showActiveEdge;

  /// The rule's thickness (`00f` 规格).
  static const double activeEdgeThickness = 2;

  /// A node shaped for a pane: kept out of the Tab order, because pane focus
  /// follows the pointer and the keys that matter here are not reachable by
  /// tabbing anyway. Phase two's keyboard navigation revisits this.
  static FocusNode newNode(String debugLabel) =>
      FocusNode(debugLabel: debugLabel, skipTraversal: true);

  /// Whether [node] — or anything inside it — currently owns the keyboard.
  static bool isActive(FocusNode node) => node.hasFocus;

  /// Whether the enclosing pane owns the keyboard, from inside it.
  ///
  /// Call it only from something that is actually drawing a selection: the
  /// call registers a dependency, so an unselected card that asks anyway
  /// would rebuild on every pane switch for a value it does not use. True
  /// outside any pane, so a widget reused off a pane keeps its normal look.
  static bool activeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PaneActiveScope>()?.active ??
      true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: node,
      onKeyEvent: onKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // Only when nothing inside already holds it: a click that lands in the
        // tree's inline rename field must not be answered by stealing focus
        // from that field, which commits the half-typed name on blur.
        onPointerDown: (_) {
          if (!node.hasFocus) node.requestFocus();
        },
        child: ListenableBuilder(
          listenable: node,
          builder: (context, child) => Stack(
            children: [
              // The subtree is handed through unchanged, so a pane switch
              // rebuilds only what asked for the answer via [activeOf] —
              // in practice the handful of selected rows and cards.
              _PaneActiveScope(active: node.hasFocus, child: child!),
              if (showActiveEdge)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: AppMotion.hover,
                      curve: AppMotion.quick,
                      height: activeEdgeThickness,
                      color: node.hasFocus ? scheme.primary : Colors.transparent,
                    ),
                  ),
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Carries "is my pane active" down to whatever draws a selection.
class _PaneActiveScope extends InheritedWidget {
  const _PaneActiveScope({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_PaneActiveScope oldWidget) =>
      oldWidget.active != active;
}
