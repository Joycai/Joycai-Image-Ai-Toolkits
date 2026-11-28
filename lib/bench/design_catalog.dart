import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/app_effects.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/design_tokens.dart';
import '../core/theme_accent.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localizations_delegates.dart';
import '../widgets/glass/app_glass.dart';
import '../widgets/glass/app_glass_menu.dart';
import '../widgets/glass/glass_controls.dart';
import '../widgets/shell/baked_backdrop.dart';
import '../widgets/ui/app_button.dart';
import '../widgets/ui/app_card.dart';
import '../widgets/ui/app_dialog.dart';
import '../widgets/ui/app_dropdown.dart';
import '../widgets/ui/app_empty_state.dart';
import '../widgets/ui/app_field_size.dart';
import '../widgets/ui/app_icon_button.dart';
import '../widgets/ui/app_markdown.dart';
import '../widgets/ui/app_neutral_marker.dart';
import '../widgets/ui/app_search_field.dart';
import '../widgets/ui/app_section_label.dart';
import '../widgets/ui/app_segmented_control.dart';
import '../widgets/ui/app_side_panel.dart';
import '../widgets/ui/app_slider.dart';
import '../widgets/ui/app_snackbar.dart';
import '../widgets/ui/app_switch.dart';
import '../widgets/ui/app_text_field.dart';

/// Launches an interactive standalone Design System Catalog instead of the main
/// database-backed app when `CATALOG=1` is present in the environment.
bool get catalogEnabled => Platform.environment['CATALOG'] == '1';

/// Builds the standalone interactive Design System Catalog application.
///
/// Allows live inspection of all 8 preset accents, light/dark modes, reduced
/// visual effects, 4 locales, viewport width constraints, and interactive
/// overlays (dialog, side panel, glass menu, snackbars, tooltips).
Widget buildDesignCatalogApp() => const _DesignCatalogApp();

class _DesignCatalogApp extends StatefulWidget {
  const _DesignCatalogApp();

  @override
  State<_DesignCatalogApp> createState() => _DesignCatalogAppState();
}

class _DesignCatalogAppState extends State<_DesignCatalogApp> {
  String _accentKey = AppConstants.defaultThemeAccentKey;
  Brightness _brightness = Brightness.light;
  bool _reduceEffects = false;
  Locale _locale = const Locale('zh');
  double? _viewportWidth;
  int _segmentValue = 0;
  int _glassSegmentValue = 0;
  int _dropdownValue = 0;
  bool _switchValue = true;
  double _sliderValue = 0.6;
  final TextEditingController _searchController = TextEditingController(text: 'Neon');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeAccent accent =
        AppConstants.presetThemes[_accentKey] ?? AppConstants.presetThemes.values.first;
    final ThemeData theme = buildAppTheme(
      accent: accent,
      brightness: _brightness,
      fontFamily: 'NotoSansSC',
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Joycai Design System Catalog',
      theme: theme,
      locale: _locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppEffects(reduceVisualEffects: _reduceEffects, child: child!),
      home: Builder(
        builder: (context) {
          final ColorScheme scheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surfaceContainer,
            body: Stack(
              children: [
                const Positioned.fill(child: BakedAuroraBackdrop()),
                Column(
                  children: [
                    _buildControlBar(context),
                    Expanded(
                      child: Center(
                        child: AnimatedContainer(
                          duration: AppMotion.durationOf(context, AppMotion.state),
                          width: _viewportWidth,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpace.s22),
                            child: _buildShowcase(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlBar(BuildContext context) {
    return AppGlass(
      grade: GlassGrade.bar,
      edges: GlassEdges.bottom,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s10),
      child: Wrap(
        spacing: AppSpace.s10,
        runSpacing: AppSpace.s10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: AppDropdown<String>(
              size: AppFieldSize.regular,
              value: _accentKey,
              items: [
                for (final String key in AppConstants.presetThemes.keys)
                  AppDropdownItem(value: key, label: key),
              ],
              onChanged: (String? v) {
                if (v != null) setState(() => _accentKey = v);
              },
            ),
          ),
          AppSegmentedControl<Brightness>(
            compact: true,
            value: _brightness,
            onChanged: (Brightness b) => setState(() => _brightness = b),
            segments: const [
              AppSegment(value: Brightness.light, label: 'Light'),
              AppSegment(value: Brightness.dark, label: 'Dark'),
            ],
          ),
          AppSegmentedControl<Locale>(
            compact: true,
            value: _locale,
            onChanged: (Locale l) => setState(() => _locale = l),
            segments: const [
              AppSegment(value: Locale('zh'), label: '简'),
              AppSegment(value: Locale('en'), label: 'EN'),
              AppSegment(
                value: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
                label: '繁',
              ),
              AppSegment(value: Locale('ja'), label: '日'),
            ],
          ),
          AppSegmentedControl<double?>(
            compact: true,
            value: _viewportWidth,
            onChanged: (double? w) => setState(() => _viewportWidth = w),
            segments: const [
              AppSegment(value: null, label: 'Full'),
              AppSegment(value: 390, label: '390'),
              AppSegment(value: 834, label: '834'),
              AppSegment(value: 1024, label: '1024'),
              AppSegment(value: 1440, label: '1440'),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Reduce effects'),
              const SizedBox(width: AppSpace.s6),
              AppSwitch(
                key: const ValueKey('catalog-reduce-effects'),
                value: _reduceEffects,
                onChanged: (bool v) => setState(() => _reduceEffects = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShowcase(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionLabel(
                'Buttons & Controls',
                padding: EdgeInsets.only(bottom: AppSpace.s10),
              ),
              Wrap(
                spacing: AppSpace.s10,
                runSpacing: AppSpace.s10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton(label: 'Primary CTA', icon: Icons.auto_awesome, onPressed: () {}),
                  AppButton(
                    label: 'Secondary',
                    variant: AppButtonVariant.secondary,
                    onPressed: () {},
                  ),
                  AppButton(label: 'Tonal', variant: AppButtonVariant.tonal, onPressed: () {}),
                  AppButton(label: 'Text', variant: AppButtonVariant.text, onPressed: () {}),
                  AppButton(
                    label: 'Destructive',
                    variant: AppButtonVariant.destructive,
                    onPressed: () {},
                  ),
                  AppIconButton(
                    icon: Icons.tune_outlined,
                    tooltip: 'Tooltip check',
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s10),
              AppSegmentedControl<int>(
                value: _segmentValue,
                onChanged: (int v) => setState(() => _segmentValue = v),
                segments: const [
                  AppSegment(value: 0, label: 'Chat', icon: Icons.chat_bubble_outline),
                  AppSegment(value: 1, label: 'Image', icon: Icons.image_outlined),
                  AppSegment(value: 2, label: 'Video', icon: Icons.movie_outlined),
                ],
              ),
              const AppSectionLabel('Inputs, Slider & Markers'),
              Wrap(
                spacing: AppSpace.s10,
                runSpacing: AppSpace.s10,
                children: [
                  SizedBox(
                    width: 240,
                    child: AppSearchField(controller: _searchController, hint: 'Search...'),
                  ),
                  const SizedBox(width: 240, child: AppTextField(hint: 'Focused glow check')),
                  SizedBox(
                    width: 220,
                    child: AppDropdown<int>(
                      value: _dropdownValue,
                      items: const [
                        AppDropdownItem(value: 0, label: 'OpenAI Compatible'),
                        AppDropdownItem(value: 1, label: 'Google Gemini'),
                      ],
                      onChanged: (int? v) {
                        if (v != null) setState(() => _dropdownValue = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s10),
              Row(
                children: [
                  AppSwitch(
                    value: _switchValue,
                    onChanged: (bool v) => setState(() => _switchValue = v),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  const AppNeutralMarker(icon: Icons.subject, label: 'Analyze'),
                  const SizedBox(width: AppSpace.s16),
                  Expanded(
                    child: AppSlider(
                      value: _sliderValue,
                      onChanged: (double v) => setState(() => _sliderValue = v),
                    ),
                  ),
                ],
              ),
              const AppSectionLabel('Interactive Overlays'),
              Wrap(
                spacing: AppSpace.s10,
                runSpacing: AppSpace.s10,
                children: [
                  AppButton(
                    label: 'Open Dialog',
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      unawaited(
                        AppDialog.show<void>(
                          context,
                          icon: Icons.info_outline,
                          iconColor: scheme.primary,
                          title: 'Catalog Dialog',
                          subtitle: 'Opaque r22 panel',
                          content: const Text('Verified inside live Design Catalog.'),
                          actions: [
                            AppButton(
                              label: 'Close',
                              variant: AppButtonVariant.text,
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  AppButton(
                    label: 'Open Side Panel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      unawaited(
                        AppSidePanel.show<void>(
                          context,
                          builder: (ctx) => Padding(
                            padding: const EdgeInsets.all(AppSpace.s16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Side Panel', style: Theme.of(ctx).textTheme.titleMedium),
                                const SizedBox(height: AppSpace.s10),
                                const Text('Responsive right sheet / mobile bottom sheet.'),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Builder(
                    builder: (btnCtx) => AppButton(
                      label: 'Open Glass Menu',
                      variant: AppButtonVariant.secondary,
                      onPressed: () {
                        unawaited(
                          showAppGlassMenuBelow(
                            btnCtx,
                            entries: [
                              AppGlassMenuItem(icon: Icons.edit, label: 'Edit', onSelected: () {}),
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
                    ),
                  ),
                  AppButton(
                    label: 'Show Toast',
                    variant: AppButtonVariant.tonal,
                    onPressed: () => AppSnackBar.success(context, 'Catalog toast triggered'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        AppGlass(
          grade: GlassGrade.float,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          padding: const EdgeInsets.all(AppSpace.s10),
          child: Wrap(
            spacing: AppSpace.s10,
            runSpacing: AppSpace.s10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GlassSegmented<int>(
                value: _glassSegmentValue,
                accent: true,
                onChanged: (int v) => setState(() => _glassSegmentValue = v),
                segments: const [
                  GlassSegment(value: 0, label: 'Image', icon: Icons.image_outlined),
                  GlassSegment(value: 1, label: 'Video', icon: Icons.movie_outlined),
                ],
              ),
              const GlassDivider(),
              GlassIconButton(icon: Icons.refresh, tooltip: 'Refresh', onPressed: () {}),
              const AppTintedGlass(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
                child: Text('Tinted Glass CTA'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        const AppCard(
          child: AppMarkdown(
            data: '## Markdown Specimen\n\nBody with `mono` and [accent link](https://example.com).\n\n> Neutral quote block.',
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        AppEmptyState(
          icon: Icons.inbox_outlined,
          label: 'Empty State',
          description: 'Consistent spacing and neutral contrast.',
          action: AppButton(
            label: 'Action',
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.compact,
            onPressed: () {},
          ),
        ),
      ],
    );
  }
}
