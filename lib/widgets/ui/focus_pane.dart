import 'package:flutter/material.dart';

import '../../core/app_shortcuts.dart';
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
class FocusPane extends StatefulWidget {
  const FocusPane({
    super.key,
    required this.node,
    required this.child,
    this.pane,
    this.onKeyEvent,
    this.showActiveEdge = true,
    this.autofocus = false,
  });

  /// Owned by the caller — a pane outlives any one build.
  final FocusNode node;

  /// Which region this is, for anything that has to *say* where the keyboard
  /// is — the `⌘/` panel names it and dims the others. Published through
  /// [active] rather than guessed from a focus node's debug label.
  final ShortcutPane? pane;

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

  /// The region that owns the keyboard right now, or null when none does —
  /// a legal state (just after a screen opens, or after a click on the
  /// chrome), in which no pane-level key is claimed at all.
  static final ValueNotifier<ShortcutPane?> active =
      ValueNotifier<ShortcutPane?>(null);

  /// *Which* pane made the current claim, as an object rather than a name.
  ///
  /// Both screens call their middle region [ShortcutPane.grid], so a claim
  /// cannot be released by matching the name: switching from the browser to
  /// the workbench mounts the gallery's pane (which takes focus and claims
  /// `grid`) before the browser's pane is disposed, and a release keyed on
  /// the name would then drop the *gallery's* live claim on the way out.
  static Object? _owner;

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
  State<FocusPane> createState() => _FocusPaneState();
}

class _FocusPaneState extends State<FocusPane> {
  @override
  void initState() {
    super.initState();
    widget.node.addListener(_publish);
  }

  @override
  void didUpdateWidget(FocusPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      oldWidget.node.removeListener(_publish);
      widget.node.addListener(_publish);
    }
  }

  @override
  void dispose() {
    widget.node.removeListener(_publish);
    _release();
    super.dispose();
  }

  /// Keeps [FocusPane.active] in step. The release is conditional on *this*
  /// pane still being the claimant, so the order two panes report a handover
  /// in cannot matter: whoever gained focus has already taken ownership, and
  /// the one losing it leaves that alone.
  void _publish() {
    final pane = widget.pane;
    if (pane == null) return;
    if (widget.node.hasFocus) {
      FocusPane._owner = this;
      FocusPane.active.value = pane;
    } else {
      _release();
    }
  }

  void _release() {
    if (!identical(FocusPane._owner, this)) return;
    FocusPane._owner = null;
    FocusPane.active.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final node = widget.node;
    final showActiveEdge = widget.showActiveEdge;

    return Focus(
      focusNode: node,
      onKeyEvent: widget.onKeyEvent,
      autofocus: widget.autofocus,
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
                      height: FocusPane.activeEdgeThickness,
                      color: node.hasFocus ? scheme.primary : Colors.transparent,
                    ),
                  ),
                ),
            ],
          ),
          child: widget.child,
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
