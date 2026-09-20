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
    this.autofocus = false,
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

  /// Whether this pane owns the keyboard when the screen opens. Exactly one
  /// pane per screen should set it: a screen whose keys all need an active
  /// pane would otherwise answer nothing at all until the first click, and
  /// `⌘A` in particular is a reasonable first act.
  final bool autofocus;

  /// The rule's thickness (`00f` 规格).
  static const double activeEdgeThickness = 2;

  /// A node shaped for a pane: kept out of the Tab order, because pane focus
  /// follows the pointer and the keys that matter here are not reachable by
  /// tabbing anyway. Phase two's keyboard navigation revisits this.
  static FocusNode newNode(String debugLabel) =>
      FocusNode(debugLabel: debugLabel, skipTraversal: true);

  /// Whether the enclosing pane owns the keyboard, from inside it.
  ///
  /// Ask only while actually drawing a selection. The dependency this
  /// registers is not dropped on a later rebuild — `Element._dependencies`
  /// survives until the element is deactivated — so a card that asks once
  /// keeps rebuilding on every pane switch for the rest of its life. Cards
  /// that have never been selected stay out of it, which is what keeps the
  /// cost proportional to the selection rather than to the grid.
  ///
  /// True outside any pane, so a widget reused off a pane keeps its normal
  /// look.
  static bool activeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PaneActiveScope>()?.active ??
      true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: node,
      onKeyEvent: onKeyEvent,
      autofocus: autofocus,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // Only when nothing inside already holds it: a click that lands in
        // this pane's own text field — the tree's inline rename — must not be
        // answered by stealing focus from it.
        //
        // A click in a *different* pane does move the keyboard, and the
        // editor then commits on blur. That is deliberate and is the rule
        // `FolderNameEditor` documents ("clicking away commits", an invalid
        // name being abandoned instead) — the same rule every file manager
        // has trained the user on. It is worth knowing that one such click
        // does two things: it commits the name and it still activates
        // whatever it landed on.
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
