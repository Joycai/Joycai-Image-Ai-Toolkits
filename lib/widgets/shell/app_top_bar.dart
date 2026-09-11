import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design_tokens.dart';
import '../../state/app_state.dart';
import '../app_window_frame.dart';
import '../glass/app_glass.dart';
import 'app_destinations.dart';
import 'nav_lens_group.dart';

/// The tablet's top bar: the same navigation model as the desktop title bar,
/// on a device that has no window to title (`01 · 1f`).
///
/// 48px of G1 glass under the status bar — the screen's one full-width glass
/// layer — with the lens group centred and the app mark at the leading edge.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final current = AppDestination.values[
        context.select<AppState, int>((s) => s.activeScreenIndex)];

    return AppGlass(
      grade: GlassGrade.bar,
      edges: GlassEdges.bottom,
      shadow: false,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const leading = AppSpace.s16 + 20 + AppSpace.s16;
              final full = NavLensGroup.widthFor(context,
                  density: NavLensDensity.topBar, current: current, showSelectedLabel: true);
              final showLabel = full + leading * 2 <= constraints.maxWidth;
              return Stack(
                children: [
                  const Positioned(
                    left: AppSpace.s16,
                    top: 0,
                    bottom: 0,
                    child: Center(child: AppMark(size: 20)),
                  ),
                  Center(
                    child: NavLensGroup(
                      density: NavLensDensity.topBar,
                      showSelectedLabel: showLabel,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
