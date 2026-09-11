import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/workbench_ui_state.dart';
import '../gallery.dart';
import 'gallery_selection_bar.dart';
import 'video_workbench_view.dart';

/// How much of the bottom of the gallery area the video player panel covers
/// at [areaWidth] — nothing until a video has been generated (`A2 · 1a`,
/// `1e` 无结果: the panel does not take layout it has nothing to show in).
double videoPlayerClearance(BuildContext context, double areaWidth) {
  final path = context.select<WorkbenchUIState, String?>((s) => s.lastGeneratedVideoPath);
  if (path == null) return 0;
  return VideoWorkbenchOverlay.occupiedHeight(context, areaWidth);
}

/// The video tab's centre column: the same gallery as the image tab, with the
/// most recent result's player panel laid over its bottom edge and the grid
/// padded so its last row clears the panel.
class VideoGalleryArea extends StatelessWidget {
  const VideoGalleryArea({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final clearance = videoPlayerClearance(context, constraints.maxWidth);
        return Stack(
          children: [
            Positioned.fill(child: Gallery(extraBottomInset: clearance)),
            const VideoWorkbenchOverlay(),
          ],
        );
      },
    );
  }
}

/// The selection bar on the video tab, lifted clear of the player panel.
///
/// The layout floats the overlay 10px in from each side of the centre column,
/// so the column's width is this slot's width plus those 20px.
class VideoTabSelectionBar extends StatelessWidget {
  const VideoTabSelectionBar({super.key});

  static const double _layoutSideInsets = 20;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final clearance = videoPlayerClearance(context, constraints.maxWidth + _layoutSideInsets);
        return Padding(
          padding: EdgeInsets.only(bottom: clearance),
          child: const GallerySelectionBar(),
        );
      },
    );
  }
}
