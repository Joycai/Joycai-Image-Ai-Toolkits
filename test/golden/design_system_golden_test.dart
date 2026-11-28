@Tags(<String>['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_effects.dart';
import 'package:joycai_image_ai_toolkits/core/app_semantic_colors.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/glass_controls.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_button.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_card.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dialog.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dropdown.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_icon_button.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_neutral_marker.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_section_label.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_segmented_control.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_switch.dart';
import 'package:material_ui/material_ui.dart';

import '../support/real_fonts.dart';
import '../support/tolerant_golden_comparator.dart';

void main() {
  late GoldenFileComparator previousComparator;

  setUpAll(() async {
    await ensureRealTestFontsLoaded();
    previousComparator = goldenFileComparator;
    goldenFileComparator = TolerantGoldenFileComparator(
      Uri.file('test/golden/design_system_golden_test.dart'),
    );
  });

  tearDownAll(() {
    goldenFileComparator = previousComparator;
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
    home: child,
  );

  for (final String presetName in const ['Blue', 'Orange']) {
    for (final Brightness brightness in Brightness.values) {
      final String name = 'goldens/controls_${presetName.toLowerCase()}_${brightness.name}.png';
      testWidgets('controls golden · $presetName ${brightness.name}', (tester) async {
        tester.view.physicalSize = const Size(640, 820);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          host(
            accent: AppConstants.presetThemes[presetName]!,
            brightness: brightness,
            child: const _ControlsSpecimen(),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(find.byType(_ControlsSpecimen), matchesGoldenFile(name));
      });
    }
  }

  for (final (Brightness brightness, bool reduced, String fileName) in const [
    (Brightness.light, false, 'goldens/glass_light.png'),
    (Brightness.dark, false, 'goldens/glass_dark.png'),
    (Brightness.dark, true, 'goldens/glass_reduced_dark.png'),
  ]) {
    testWidgets('glass golden · ${brightness.name} reduced=$reduced', (tester) async {
      tester.view.physicalSize = const Size(580, 340);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          accent: AppConstants.presetThemes['Blue']!,
          brightness: brightness,
          reduceEffects: reduced,
          child: const _GlassSpecimen(),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(find.byType(_GlassSpecimen), matchesGoldenFile(fileName));
    });
  }
}

class _ControlsSpecimen extends StatelessWidget {
  const _ControlsSpecimen();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppSemanticColors semantic = context.semantic;

    Widget chip(String label, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
    );

    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionLabel('主操作与次级操作', padding: EdgeInsets.only(bottom: AppSpace.s10)),
              Wrap(
                spacing: AppSpace.s10,
                runSpacing: AppSpace.s10,
                children: [
                  AppButton(label: '主按钮', icon: Icons.save_outlined, onPressed: () {}),
                  AppButton(label: '次级按钮', variant: AppButtonVariant.secondary, onPressed: () {}),
                  AppButton(label: 'Tonal', variant: AppButtonVariant.tonal, onPressed: () {}),
                  AppButton(label: '文本', variant: AppButtonVariant.text, onPressed: () {}),
                  AppButton(label: '删除', variant: AppButtonVariant.destructive, onPressed: () {}),
                  AppIconButton(icon: Icons.tune_outlined, tooltip: '设置', onPressed: () {}),
                  AppIconButton(
                    icon: Icons.grid_view,
                    tooltip: '网格',
                    selected: true,
                    onPressed: () {},
                  ),
                ],
              ),
              const AppSectionLabel('分段与选择'),
              Row(
                children: [
                  AppSegmentedControl<int>(
                    value: 0,
                    onChanged: (_) {},
                    segments: const [
                      AppSegment(value: 0, label: '选中', icon: Icons.check),
                      AppSegment(value: 1, label: '未选'),
                    ],
                  ),
                  const SizedBox(width: AppSpace.s16),
                  Expanded(
                    child: AppDropdown<int>(
                      value: 0,
                      items: const [AppDropdownItem(value: 0, label: 'OpenAI 兼容接口')],
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
              const AppSectionLabel('开关、语义与中性标记'),
              Wrap(
                spacing: AppSpace.s10,
                runSpacing: AppSpace.s10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppSwitch(value: true, onChanged: (_) {}),
                  AppSwitch(value: false, onChanged: (_) {}),
                  chip('成功', semantic.successContainer, semantic.onSuccessContainer),
                  chip('警告', semantic.warningContainer, semantic.onWarningContainer),
                  chip('信息', semantic.infoContainer, semantic.onInfoContainer),
                  const AppNeutralMarker(icon: Icons.subject, label: '分析'),
                ],
              ),
              const AppSectionLabel('对话框外壳', tone: AppSectionTone.neutral),
              AppDialog(
                icon: Icons.warning_amber_rounded,
                iconColor: scheme.error,
                title: '覆盖原图？',
                subtitle: '此操作无法撤销',
                maxWidth: 520,
                onClose: () {},
                content: const Text('原始文件将被裁剪结果永久替换。'),
                actions: [
                  AppButton(label: '取消', variant: AppButtonVariant.text, onPressed: () {}),
                  AppButton(label: '覆盖', variant: AppButtonVariant.destructive, onPressed: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassSpecimen extends StatelessWidget {
  const _GlassSpecimen();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.surfaceContainer, scheme.primary],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppGlass(
                grade: GlassGrade.bar,
                edges: GlassEdges.bottom,
                shadow: false,
                padding: EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
                child: Text('GlassGrade.bar · 顶栏'),
              ),
              const SizedBox(height: AppSpace.s16),
              Row(
                children: [
                  Expanded(
                    child: AppGlass(
                      grade: GlassGrade.float,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      padding: const EdgeInsets.all(AppSpace.s10),
                      child: Row(
                        children: [
                          GlassSegmented<int>(
                            value: 0,
                            accent: true,
                            onChanged: (_) {},
                            segments: const [
                              GlassSegment(value: 0, label: '图像', icon: Icons.image_outlined),
                              GlassSegment(value: 1, label: '视频', icon: Icons.movie_outlined),
                            ],
                          ),
                          const GlassDivider(),
                          GlassIconButton(
                            icon: Icons.tune_outlined,
                            tooltip: '选项',
                            onPressed: () {},
                          ),
                          const Spacer(),
                          const AppTintedGlass(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpace.s10,
                              vertical: AppSpace.s6,
                            ),
                            child: Text('运行'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s16),
                  GlassFab(icon: Icons.auto_awesome, tooltip: '生成', onPressed: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
