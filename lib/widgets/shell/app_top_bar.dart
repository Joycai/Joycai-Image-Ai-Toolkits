import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../app_window_frame.dart';
import '../glass/app_glass.dart';
import 'app_destinations.dart';
import 'nav_lens_group.dart';

/// The tablet's top bar: the same navigation model as the desktop title bar,
/// on a device that has no window to title (`01 · 1f`).
///
/// 48px of G1 glass under the status bar — the screen's one full-width glass
/// layer — with the lens group centred, the app mark at the leading edge and
/// the current destination's name at the trailing one (`01b · 1e`).
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final theme = Theme.of(context);
    final current = AppDestination.values[
        context.select<AppState, int>((s) => s.activeScreenIndex)];
    final destination = current.label(AppLocalizations.of(context)!);
    final destinationStyle = theme.textTheme.bodyMedium!.metricsOnly.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onAccentTint,
    );

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
              final nav = NavLensGroup.widthFor(density: NavLensDensity.topBar);
              final nameWidth = (TextPainter(
                text: TextSpan(text: destination, style: destinationStyle),
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout())
                  .width;
              // The name takes the trailing half beside the centred group, or
              // nothing: it never pushes the group off centre.
              final showName = nameWidth + AppSpace.s16 * 2 <= (constraints.maxWidth - nav) / 2;
              return Stack(
                children: [
                  const Positioned(
                    left: AppSpace.s16,
                    top: 0,
                    bottom: 0,
                    child: Center(child: AppMark(size: 20)),
                  ),
                  const Center(child: NavLensGroup(density: NavLensDensity.topBar)),
                  if (showName)
                    Positioned(
                      right: AppSpace.s16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(destination, maxLines: 1, softWrap: false, style: destinationStyle),
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
