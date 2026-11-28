import 'package:material_ui/material_ui.dart';

import '../../core/design_tokens.dart';
import '../ui/ui_previews.dart';
import 'app_glass.dart';
import 'glass_controls.dart';

@JoycaiBrightnessPreview(name: 'AppGlass grades', group: 'Joycai Glass', size: Size(520, 240))
Widget previewAppGlassGrades() => Builder(
  builder: (context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.surfaceContainer, scheme.primary]),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppGlass(
              grade: GlassGrade.bar,
              edges: GlassEdges.bottom,
              shadow: false,
              padding: EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
              child: Text('GlassGrade.bar'),
            ),
            const SizedBox(height: AppSpace.s10),
            AppGlass(
              grade: GlassGrade.float,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              padding: const EdgeInsets.all(AppSpace.s10),
              child: const Text('GlassGrade.float'),
            ),
            const SizedBox(height: AppSpace.s10),
            AppGlass(
              grade: GlassGrade.lens,
              borderRadius: BorderRadius.circular(AppRadius.control),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
              child: const Text('GlassGrade.lens'),
            ),
          ],
        ),
      ),
    );
  },
);

@JoycaiBrightnessPreview(
  name: 'AppTintedGlass & GlassControls',
  group: 'Joycai Glass',
  size: Size(520, 180),
)
Widget previewGlassControls() => Builder(
  builder: (context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.surfaceContainer, scheme.primary]),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppGlass(
                grade: GlassGrade.float,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.s10,
                  vertical: AppSpace.s6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassSegmented<int>(
                      value: 0,
                      accent: true,
                      onChanged: (_) {},
                      segments: const [
                        GlassSegment(value: 0, label: 'Image', icon: Icons.image_outlined),
                        GlassSegment(value: 1, label: 'Video', icon: Icons.movie_outlined),
                      ],
                    ),
                    const GlassDivider(),
                    GlassIconButton(
                      icon: Icons.tune_outlined,
                      tooltip: 'Options',
                      onPressed: () {},
                    ),
                    const SizedBox(width: AppSpace.s6),
                    const AppTintedGlass(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpace.s10,
                        vertical: AppSpace.s6,
                      ),
                      child: Text('Run'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.s16),
              GlassFab(icon: Icons.auto_awesome, tooltip: 'Generate', onPressed: () {}),
            ],
          ),
        ),
      ),
    );
  },
);
