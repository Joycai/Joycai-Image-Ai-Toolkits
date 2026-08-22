import 'package:flutter/widgets.dart';

/// Physical-pixel step the thumbnail grids decode on.
///
/// Small enough that a tile is never scaled up from a noticeably coarser
/// bitmap, large enough that the whole 80–400pt size range collapses onto a
/// handful of values.
const int _kDecodeStep = 128;

/// Widest bitmap worth holding for a grid tile, whatever the size slider and
/// the display's pixel ratio multiply out to.
const int _kMaxDecodeWidth = 1024;

/// The width a grid tile of [logicalSize] should be decoded at, snapped to a
/// ladder.
///
/// `ResizeImage`'s cache key includes this width, so decoding at exactly the
/// displayed size means the key moves with the size slider — and the slider is
/// a continuous gesture. Dragging it from 80 to 400 handed the decoder a
/// brand-new key on every frame, so every visible tile was decoded again from
/// scratch sixty times a second and the image cache was pushed past its
/// ceiling while it happened.
///
/// Rounding *up* to a step keeps that from being a quality trade: the bitmap
/// is never smaller than the box it is painted into, only sometimes larger
/// than it strictly needs to be. What it buys is that a whole drag crosses a
/// few keys instead of hundreds, and that two tiles at neighbouring sizes
/// share one decode.
int thumbnailDecodeWidth(BuildContext context, double logicalSize) {
  final physical = logicalSize * MediaQuery.devicePixelRatioOf(context);
  final stepped = ((physical / _kDecodeStep).ceil()) * _kDecodeStep;
  return stepped.clamp(_kDecodeStep, _kMaxDecodeWidth);
}
