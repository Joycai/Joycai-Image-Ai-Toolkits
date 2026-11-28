import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_effects.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double contrast(Color a, Color b) {
    final double la = luminance(a);
    final double lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  Widget host({
    required ThemeAccent accent,
    required Brightness brightness,
    required bool reduceEffects,
    required Widget child,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(accent: accent, brightness: brightness),
    builder: (context, body) => AppEffects(reduceVisualEffects: reduceEffects, child: body!),
    home: Scaffold(body: Center(child: child)),
  );

  group('AppGlass grades × tones × brightness × reduceVisualEffects', () {
    for (final GlassGrade grade in GlassGrade.values) {
      for (final GlassTone tone in GlassTone.values) {
        for (final Brightness brightness in Brightness.values) {
          testWidgets('$grade / $tone / $brightness toggles blur and keeps AA ink', (tester) async {
            final ThemeAccent accent = AppConstants.presetThemes['Blue']!;
            final ThemeData theme = buildAppTheme(accent: accent, brightness: brightness);
            final ColorScheme scheme = theme.colorScheme;

            // 1. Live glass mode -> BackdropFilter present.
            await tester.pumpWidget(
              host(
                accent: accent,
                brightness: brightness,
                reduceEffects: false,
                child: AppGlass(
                  grade: grade,
                  tone: tone,
                  child: const SizedBox(width: 80, height: 32, child: Text('Glass')),
                ),
              ),
            );
            expect(find.byType(BackdropFilter), findsOneWidget);

            // 2. Reduced effects mode -> no BackdropFilter, exact opaque fallback + AA ink.
            late GlassInk resolvedInk;
            await tester.pumpWidget(
              host(
                accent: accent,
                brightness: brightness,
                reduceEffects: true,
                child: AppGlass(
                  grade: grade,
                  tone: tone,
                  child: Builder(
                    builder: (context) {
                      resolvedInk = GlassInk.maybeOf(context)!;
                      return const SizedBox(width: 80, height: 32, child: Text('Reduced'));
                    },
                  ),
                ),
              ),
            );

            expect(find.byType(BackdropFilter), findsNothing);
            expect(resolvedInk.reduced, isTrue);

            final bool offTone =
                tone != (brightness == Brightness.dark ? GlassTone.dark : GlassTone.light) &&
                tone == GlassTone.dark;
            final Color expectedBg = offTone
                ? AppOverlay.ink
                : grade == GlassGrade.bar
                ? scheme.surfaceContainerLow
                : scheme.surface;

            final DecoratedBox box = tester.widget<DecoratedBox>(
              find.descendant(of: find.byType(AppGlass), matching: find.byType(DecoratedBox)).first,
            );
            expect((box.decoration as BoxDecoration).color, expectedBg);
            expect(
              contrast(resolvedInk.ink, expectedBg),
              greaterThanOrEqualTo(4.5),
              reason: '$grade/$tone/$brightness reduced ink failed WCAG AA',
            );
          });
        }
      }
    }
  });

  group('AppTintedGlass across all 8 presets × brightness × reduceEffects', () {
    for (final MapEntry<String, ThemeAccent> entry in AppConstants.presetThemes.entries) {
      for (final Brightness brightness in Brightness.values) {
        testWidgets('${entry.key} (${brightness.name}) glass vs reduced', (tester) async {
          final ThemeData theme = buildAppTheme(accent: entry.value, brightness: brightness);

          await tester.pumpWidget(
            host(
              accent: entry.value,
              brightness: brightness,
              reduceEffects: false,
              child: const AppTintedGlass(
                padding: EdgeInsets.all(AppSpace.s10),
                child: Text('Run'),
              ),
            ),
          );
          expect(find.byType(BackdropFilter), findsOneWidget);

          await tester.pumpWidget(
            host(
              accent: entry.value,
              brightness: brightness,
              reduceEffects: true,
              child: const AppTintedGlass(
                padding: EdgeInsets.all(AppSpace.s10),
                child: Text('Run'),
              ),
            ),
          );
          expect(find.byType(BackdropFilter), findsNothing);
          final DecoratedBox box = tester.widget<DecoratedBox>(
            find
                .descendant(of: find.byType(AppTintedGlass), matching: find.byType(DecoratedBox))
                .first,
          );
          expect((box.decoration as BoxDecoration).color, theme.colorScheme.primary);
        });
      }
    }
  });

  group('real AppGlassMenu in live Overlay', () {
    for (final bool reduced in const [false, true]) {
      testWidgets('showAppGlassMenu obeys reduceVisualEffects=$reduced', (tester) async {
        await tester.pumpWidget(
          host(
            accent: AppConstants.presetThemes['Blue']!,
            brightness: Brightness.dark,
            reduceEffects: reduced,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  unawaited(
                    showAppGlassMenu(
                      context,
                      position: const Offset(100, 100),
                      entries: [
                        AppGlassMenuItem(icon: Icons.edit, label: 'Rename', onSelected: () {}),
                        const AppGlassMenuDivider(),
                        AppGlassMenuItem(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          danger: true,
                          onSelected: () {},
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('MenuTrigger'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('MenuTrigger'));
        await tester.pumpAndSettle();

        expect(find.text('Rename'), findsOneWidget);
        expect(find.byType(AppGlassMenu), findsOneWidget);
        expect(
          find.descendant(of: find.byType(AppGlassMenu), matching: find.byType(BackdropFilter)),
          reduced ? findsNothing : findsOneWidget,
        );
      });
    }
  });
}
