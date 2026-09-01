import 'package:flutter/painting.dart';

/// How a thumbnail fills the tile it is drawn in.
///
/// One preference, shared by the workbench gallery, the file browser and the
/// assistant's reference panel, rather than one per grid: it says how the user
/// wants to *read* pictures, and the same photograph cropping in one grid and
/// letterboxing in the next is the part that confuses. Lives on [AppState]
/// beside the other look-and-feel settings for the same reason.
enum ThumbnailFit {
  /// The whole picture, letterboxed into the tile. Nothing is cut, so a
  /// panorama or a tall portrait still reads as itself — which is the point of
  /// having the choice at all.
  fit(BoxFit.contain),

  /// The tile filled edge to edge, with whatever overflows cropped away. A
  /// tidier grid, paid for with the edges of anything not roughly square.
  fill(BoxFit.cover);

  const ThumbnailFit(this.boxFit);

  /// The [BoxFit] to hand an `Image`.
  final BoxFit boxFit;

  /// Parses the persisted setting. Anything unrecognised — including the null
  /// of an install that predates the setting — reads as [fit]: showing the
  /// whole picture is the answer that never hides anything.
  static ThumbnailFit fromString(String? value) =>
      value == fill.name ? fill : fit;
}
