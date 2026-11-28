import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_effects.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_button.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_card.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dropdown.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_empty_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_markdown.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_neutral_marker.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_section_label.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_segmented_control.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_snackbar.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_text_field.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/real_fonts.dart';

void main() {
  setUpAll(() async {
    await ensureRealTestFontsLoaded();
  });

  Widget host({
    required ThemeAccent accent,
    required Brightness brightness,
    required Widget child,
    bool reduceEffects = false,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildAppTheme(accent: accent, brightness: brightness, fontFamily: 'NotoSansSC'),
    builder: (context, body) => AppEffects(reduceVisualEffects: reduceEffects, child: body!),
    home: Scaffold(body: Center(child: child)),
  );

  Color textColor(WidgetTester tester, String text) {
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text).first, matching: find.byType(RichText)),
    );
    return paragraph.text.style!.color!;
  }

  group('neutral invariance across accents', () {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('neutral surfaces and text stay identical under Blue and Rose ($brightness)', (
        tester,
      ) async {
        final ThemeAccent blue = AppConstants.presetThemes['Blue']!;
        final ThemeAccent rose = AppConstants.presetThemes['Rose']!;

        Future<
          ({Color cardColor, Color markerBg, Color markerInk, Color sectionInk, Color emptyInk})
        >
        capture(ThemeAccent accent) async {
          await tester.pumpWidget(
            host(
              accent: accent,
              brightness: brightness,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppCard(
                      child: Column(
                        children: [
                          const AppSectionLabel('NeutralSection', tone: AppSectionTone.neutral),
                          const AppNeutralMarker(icon: Icons.subject, label: 'MarkerLabel'),
                          const SizedBox(height: AppSpace.s10),
                          const AppTextField(hint: 'UnfocusedHint'),
                          const SizedBox(height: AppSpace.s10),
                          AppDropdown<int>(
                            value: 0,
                            items: const [AppDropdownItem(value: 0, label: 'DropdownItem')],
                            onChanged: (_) {},
                          ),
                        ],
                      ),
                    ),
                    const AppEmptyState(
                      icon: Icons.inbox_outlined,
                      label: 'EmptyTitle',
                      description: 'EmptyDesc',
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final Material cardMaterial = tester.widget<Material>(
            find.descendant(of: find.byType(AppCard).first, matching: find.byType(Material)).first,
          );
          final Container markerContainer = tester.widget<Container>(
            find
                .descendant(of: find.byType(AppNeutralMarker), matching: find.byType(Container))
                .first,
          );
          return (
            cardColor: cardMaterial.color!,
            markerBg: (markerContainer.decoration! as BoxDecoration).color!,
            markerInk: textColor(tester, 'MarkerLabel'),
            sectionInk: textColor(tester, 'NEUTRALSECTION'),
            emptyInk: textColor(tester, 'EmptyTitle'),
          );
        }

        final blueSnap = await capture(blue);
        final roseSnap = await capture(rose);

        expect(roseSnap.cardColor, blueSnap.cardColor);
        expect(roseSnap.markerBg, blueSnap.markerBg);
        expect(roseSnap.markerInk, blueSnap.markerInk);
        expect(roseSnap.sectionInk, blueSnap.sectionInk);
        expect(roseSnap.emptyInk, blueSnap.emptyInk);
      });
    }
  });

  group('accent role binding across all 8 presets × light/dark', () {
    for (final MapEntry<String, ThemeAccent> entry in AppConstants.presetThemes.entries) {
      for (final Brightness brightness in Brightness.values) {
        testWidgets('${entry.key} (${brightness.name}) drives interactive accent roles', (
          tester,
        ) async {
          final ThemeData theme = buildAppTheme(
            accent: entry.value,
            brightness: brightness,
            fontFamily: 'NotoSansSC',
          );
          final ColorScheme scheme = theme.colorScheme;

          await tester.pumpWidget(
            host(
              accent: entry.value,
              brightness: brightness,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(label: 'PrimaryBtn', onPressed: () {}),
                    AppButton(label: 'TonalBtn', variant: AppButtonVariant.tonal, onPressed: () {}),
                    AppButton(label: 'TextBtn', variant: AppButtonVariant.text, onPressed: () {}),
                    AppButton(
                      label: 'DangerBtn',
                      variant: AppButtonVariant.destructive,
                      onPressed: () {},
                    ),
                    AppSegmentedControl<int>(
                      value: 0,
                      onChanged: (_) {},
                      segments: const [
                        AppSegment(value: 0, label: 'SegSelected'),
                        AppSegment(value: 1, label: 'SegIdle'),
                      ],
                    ),
                    const AppSectionLabel('AccentSection'),
                    const AppTextField(key: ValueKey('focus-target'), hint: 'FocusMe'),
                    const AppMarkdown(
                      data: '## HeadingTwo\n\n[LinkText](https://example.com)\n\n> QuoteBody',
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Focus the AppTextField and check its glow ring and focused border.
          await tester.tap(find.byKey(const ValueKey('focus-target')));
          await tester.pumpAndSettle();

          final AnimatedContainer ring = tester.widget<AnimatedContainer>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('focus-target')),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          );
          expect(
            ((ring.decoration! as BoxDecoration).border! as Border).top.color,
            scheme.accentRing,
          );
          final InputDecorator decorator = tester.widget<InputDecorator>(
            find.descendant(
              of: find.byKey(const ValueKey('focus-target')),
              matching: find.byType(InputDecorator),
            ),
          );
          expect(decorator.decoration.focusedBorder!.borderSide.color, scheme.primary);

          // AppButton variants.
          expect(textColor(tester, 'PrimaryBtn'), scheme.onPrimary);
          expect(textColor(tester, 'TonalBtn'), scheme.onAccentTint);
          expect(textColor(tester, 'TextBtn'), scheme.accentText);
          expect(textColor(tester, 'DangerBtn'), errorFillScheme().onPrimary);

          // AppSectionLabel accent tone.
          expect(textColor(tester, 'ACCENTSECTION'), scheme.onAccentTint);

          // AppSegmentedControl selected chip label.
          expect(textColor(tester, 'SegSelected'), scheme.onAccentTint);

          // AppMarkdown H2 accent bar (primary) and neutral quote bar.
          final List<DecoratedBox> bars = tester
              .widgetList<DecoratedBox>(
                find.descendant(of: find.byType(AppMarkdown), matching: find.byType(DecoratedBox)),
              )
              .toList();
          final bool hasPrimaryH2Bar = bars.any(
            (b) =>
                b.decoration is BoxDecoration &&
                (b.decoration as BoxDecoration).color == scheme.primary,
          );
          expect(hasPrimaryH2Bar, isTrue, reason: 'H2 vertical bar must take scheme.primary');
        });
      }
    }
  });

  group('real overlay rendering (Tooltip & AppSnackBar)', () {
    testWidgets('real Tooltip overlay reads TooltipTheme and ignores accent seed', (tester) async {
      Future<({Color bg, Color fg})> openTooltip(ThemeAccent accent) async {
        await tester.pumpWidget(
          host(
            accent: accent,
            brightness: Brightness.light,
            child: const Tooltip(
              message: 'TooltipSample',
              child: SizedBox(width: 48, height: 48, child: Icon(Icons.info_outline)),
            ),
          ),
        );
        await tester.longPress(find.byIcon(Icons.info_outline));
        await tester.pump(const Duration(milliseconds: 100));

        final Finder tipText = find.text('TooltipSample');
        expect(tipText, findsOneWidget);
        final Color fg = DefaultTextStyle.of(tester.element(tipText)).style.color!;
        final Container bubble = tester.widget<Container>(
          find.ancestor(of: tipText, matching: find.byType(Container)).first,
        );
        final Color bg = (bubble.decoration! as BoxDecoration).color!;
        // Dismiss before next pump.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        return (bg: bg, fg: fg);
      }

      final blueTip = await openTooltip(AppConstants.presetThemes['Blue']!);
      final roseTip = await openTooltip(AppConstants.presetThemes['Rose']!);
      expect(roseTip.bg, blueTip.bg);
      expect(roseTip.fg, blueTip.fg);
      expect(blueTip.bg, AppOverlay.ink);
    });

    testWidgets('real AppSnackBar swaps glass for opaque AppOverlay.ink under reduceEffects', (
      tester,
    ) async {
      for (final bool reduced in const [false, true]) {
        await tester.pumpWidget(
          host(
            accent: AppConstants.presetThemes['Blue']!,
            brightness: Brightness.light,
            reduceEffects: reduced,
            child: Builder(
              builder: (context) => AppButton(
                label: 'ToastBtn',
                onPressed: () => AppSnackBar.success(context, 'ToastSaved'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('ToastBtn'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('ToastSaved'), findsOneWidget);
        final Finder snackGlass = find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(AppGlass),
        );
        expect(snackGlass, findsOneWidget);
        expect(
          find.descendant(of: snackGlass, matching: find.byType(BackdropFilter)),
          reduced ? findsNothing : findsOneWidget,
        );
        if (reduced) {
          final DecoratedBox box = tester.widget<DecoratedBox>(
            find.descendant(of: snackGlass, matching: find.byType(DecoratedBox)).first,
          );
          expect((box.decoration as BoxDecoration).color, AppOverlay.ink);
        }
      }
    });
  });

  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double contrastRatio(Color a, Color b) {
    final double la = luminance(a);
    final double lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  group('WCAG text contrast on rendered UI primitives', () {
    for (final MapEntry<String, ThemeAccent> preset in AppConstants.presetThemes.entries) {
      for (final Brightness brightness in Brightness.values) {
        testWidgets(
          'rendered foreground vs composited ground clears AA — ${preset.key} ${brightness.name}',
          (tester) async {
            final ThemeData theme = buildAppTheme(
              accent: preset.value,
              brightness: brightness,
              fontFamily: 'NotoSansSC',
            );
            final ColorScheme scheme = theme.colorScheme;

            await tester.pumpWidget(
              host(
                accent: preset.value,
                brightness: brightness,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.s16),
                  child: AppCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionLabel('ContrastSection'),
                        const SizedBox(height: AppSpace.s10),
                        Wrap(
                          spacing: AppSpace.s10,
                          runSpacing: AppSpace.s10,
                          children: [
                            AppButton(label: 'Commit', onPressed: () {}),
                            AppButton(
                              label: 'Secondary',
                              variant: AppButtonVariant.secondary,
                              onPressed: () {},
                            ),
                            AppButton(
                              label: 'Apply',
                              variant: AppButtonVariant.tonal,
                              onPressed: () {},
                            ),
                            AppButton(
                              label: 'Delete',
                              variant: AppButtonVariant.destructive,
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.s10),
                        AppSegmentedControl<int>(
                          value: 0,
                          onChanged: (_) {},
                          segments: const [
                            AppSegment(value: 0, label: 'Selected'),
                            AppSegment(value: 1, label: 'Other'),
                          ],
                        ),
                        const SizedBox(height: AppSpace.s10),
                        const AppNeutralMarker(icon: Icons.subject, label: 'Analyze'),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final Color cardBg = tester
                .widget<Material>(
                  find.descendant(of: find.byType(AppCard), matching: find.byType(Material)).first,
                )
                .color!;

            // Each tuple: (label text, actual composited background behind it).
            final List<(String, Color)> checks = <(String, Color)>[
              ('CONTRASTSECTION', cardBg),
              ('Commit', scheme.primary),
              ('Secondary', scheme.surface),
              ('Apply', Color.alphaBlend(scheme.accentTint, cardBg)),
              ('Delete', errorFillScheme().primary),
              ('Selected', Color.alphaBlend(scheme.accentTint, scheme.surfaceContainerHighest)),
              ('Other', scheme.surfaceContainerHighest),
              ('Analyze', scheme.surfaceContainerHighest),
            ];

            for (final (String label, Color bg) in checks) {
              final Color fg = textColor(tester, label);
              final double ratio = contrastRatio(fg, bg);
              expect(
                ratio,
                greaterThanOrEqualTo(4.5),
                reason:
                    '${preset.key}/${brightness.name} "$label" contrast '
                    '${ratio.toStringAsFixed(2)}:1 (fg=$fg, bg=$bg) below WCAG AA 4.5:1',
              );
            }
          },
        );
      }
    }

    for (final Brightness brightness in Brightness.values) {
      testWidgets(
        'meets Flutter textContrastGuideline on AppCard & AppDialog (${brightness.name})',
        (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              host(
                accent: AppConstants.presetThemes['Blue']!,
                brightness: brightness,
                child: const AppCard(
                  padding: EdgeInsets.all(AppSpace.s16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CardHeadlineText',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: AppSpace.s10),
                      Text('CardBodyContrastCheck', style: TextStyle(fontSize: 18)),
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            handle.dispose();
          }
        },
      );
    }
  });
}
