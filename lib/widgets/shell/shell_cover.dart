// Stop paying for the shell while something opaque is sitting on top of it.
//
// Nothing in Flutter stops a route below from painting because something
// opaque covers it — an [Overlay] only stops descending at an entry that says
// it is `opaque`, and the media-preview lightbox says the opposite so its Hero
// can fly over the still-visible grid. Once that flight lands the grid is
// behind a solid black page, and every frame after that still pays for the
// gallery, its glass toolbar, the selection bar, the task capsule and the
// phone dock.
//
// Measured on the dev machine's integrated Radeon, maximized at 4K, GPU ms a
// frame (`tool/bench/gpu_bench.ps1`): the whole app 6.89, a blank window 2.58.
// So roughly three of those milliseconds were being spent on pixels nobody
// could see, for as long as a preview stayed open.
//
// Two seams to cross, because the shell is not all in one place:
//
//   * inside the [Navigator] — the screens. [FullScreenCoverRoute] flips its
//     own overlay entry to `opaque` once its transition settles, which is the
//     engine's own mechanism: the Overlay stops painting and laying out
//     everything below, and pauses its tickers, exactly as it does under an
//     ordinary opaque route.
//   * outside it — the window ground and the title bar, which live in
//     `MaterialApp.builder` above the Navigator. A route cannot cover those,
//     and the title bar genuinely stays visible beside a lightbox, so they
//     are not hidden: [ShellCover] only tells the ground to shrink to the
//     strip that is still showing behind the title bar.

import 'package:flutter/material.dart';

/// How many settled full-cover routes are on top of the shell.
///
/// A count rather than a flag: two can overlap for the length of one
/// transition, and the ground must not come back early because the first one
/// left.
class ShellCoverController extends ValueNotifier<int> {
  ShellCoverController() : super(0);

  bool get covered => value > 0;

  /// Declare that something opaque now covers the shell. Every [enter] must be
  /// paired with a [leave] — [FullScreenCoverRoute] is the only caller, and it
  /// pairs them in `dispose` as well as on the reverse of its transition.
  void enter() => value = value + 1;

  void leave() => value = value > 0 ? value - 1 : 0;
}

/// Publishes the [ShellCoverController] to the shell and to the routes below.
///
/// Must sit **above** the [Navigator] — it goes in `MaterialApp.builder`, so
/// that `navigator.context` can find it.
class ShellCover extends InheritedWidget {
  const ShellCover({super.key, required this.controller, required super.child});

  final ShellCoverController controller;

  static ShellCoverController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellCover>()?.controller;

  @override
  bool updateShouldNotify(ShellCover oldWidget) =>
      oldWidget.controller != controller;
}

/// A page route whose page is **fully opaque once the transition has landed**,
/// but transparent while it is landing.
///
/// The transparency is not decoration: a Hero only flies between PageRoutes,
/// and it has to fly over something. So the route enters `opaque: false` like
/// any transparent route, and the moment its animation reports `completed` it
/// sets its own overlay entry opaque — at which point the Overlay stops
/// painting, laying out and ticking everything underneath. Popping reverses
/// both, in that order: the animation leaves `completed` before the first
/// frame of the exit, so whatever is below is painting again by the time any
/// of it shows.
///
/// Only for a page that really does fill its route with opaque paint. A page
/// with a translucent scrim, rounded corners or a safe-area gap would show
/// black where the shell used to be. The lightbox qualifies because it is a
/// `Dialog.fullscreen(backgroundColor: Colors.black)`.
class FullScreenCoverRoute<T> extends PageRouteBuilder<T> {
  FullScreenCoverRoute({
    required super.pageBuilder,
    super.transitionsBuilder,
    super.transitionDuration,
    super.reverseTransitionDuration,
    super.settings,
    super.fullscreenDialog,
  }) : super(opaque: false);

  ShellCoverController? _shell;
  bool _covering = false;

  @override
  void install() {
    super.install();
    animation!.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    animation?.removeStatusListener(_onStatus);
    _setCovering(false);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) =>
      _setCovering(status == AnimationStatus.completed);

  void _setCovering(bool value) {
    if (_covering == value) return;
    _covering = value;

    // `ModalRoute` yields the barrier first and the modal scope second, and it
    // is the scope that carries `opaque`. Setting it notifies the Overlay,
    // which is why this is a supported thing to do after the fact rather than
    // a constructor-time decision.
    if (overlayEntries.isNotEmpty) {
      overlayEntries.last.opaque = value;
    }

    final BuildContext? context = navigator?.context;
    if (value) {
      _shell = context == null ? null : ShellCover.maybeOf(context);
      _shell?.enter();
    } else {
      _shell?.leave();
      _shell = null;
    }
  }
}
