// Every component the design spec's 标准组件 sheet lists, on one page, rendered
// once per theme seed in both brightnesses.
//
// The screen matrix next door answers "does this screen lay out?". This
// answers the other question the spec raises: the sheet is drawn in one teal,
// the app ships seven seeds, and the accent rules only work if the *structure*
// survives all of them. Fourteen PNGs is few enough to actually look at, which
// is the point — 8 screens × 7 seeds × 2 brightnesses is not.
//
// What to look for in the output:
//   · greys stay grey — no seed tint in the panel, the track or the rules
//   · every selected thing uses accentTint/accentRing, at the same strength
//   · success/warning/info are identical across all seven columns
//   · the focused input's glow ring is visible at every seed, in both themes
//   · the selected segment's label reads at every seed, especially in dark

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_semantic_colors.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_button.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_card.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_dialog.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_icon_button.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_search_field.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_segmented_control.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_status_badge.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_text_field.dart';

void main() {
  for (final MapEntry<String, Color> seed in AppConstants.presetThemes.entries) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('gallery · ${seed.key} · ${brightness.name}', (tester) async {
        tester.view.physicalSize = const Size(720, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          // Not optional: AppDialog's close button reads its tooltip from
          // AppLocalizations, so a MaterialApp without the delegates throws
          // rather than degrading. The real app always has them.
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The font the app actually runs with. Without it the theme falls
          // back to Roboto, which has no CJK — every label in this gallery
          // photographs as a row of tofu boxes.
          theme: buildAppTheme(
            seedColor: seed.value,
            brightness: brightness,
            fontFamily: 'NotoSansSC',
          ),
          home: const _Gallery(),
        ));

        // The focus ring is a state, not a static style — it only appears in
        // the shot if something actually holds focus.
        await tester.tap(find.byKey(const ValueKey('focused-field')));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(_Gallery),
          matchesGoldenFile('gallery_${seed.key.toLowerCase()}_${brightness.name}.png'),
        );
      });
    }
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('按钮'),
              Wrap(spacing: 10, runSpacing: 10, children: [
                AppButton(label: '主操作', icon: Icons.save_outlined, onPressed: () {}),
                AppButton(
                  label: '次级操作',
                  onPressed: () {},
                  variant: AppButtonVariant.secondary,
                ),
                AppButton(
                  label: '危险操作',
                  icon: Icons.warning_amber_rounded,
                  onPressed: () {},
                  variant: AppButtonVariant.destructiveOutline,
                ),
                AppButton(label: '静默操作', onPressed: () {}, variant: AppButtonVariant.text),
                const AppButton(label: '禁用', onPressed: null),
                AppIconButton(icon: Icons.settings, tooltip: '设置', onPressed: () {}),
                AppIconButton(
                  icon: Icons.grid_view,
                  tooltip: '已选',
                  selected: true,
                  onPressed: () {},
                ),
              ]),
              const _Label('分段控件'),
              AppSegmentedControl<int>(
                value: 0,
                onChanged: (_) {},
                segments: const [
                  AppSegment(value: 0, label: '选中', icon: Icons.check),
                  AppSegment(value: 1, label: '未选'),
                  AppSegment(value: 2, label: '未选'),
                ],
              ),
              const _Label('输入'),
              Row(children: [
                // The real search component, not an AppTextField wearing a
                // search icon: it is what six filter fields across the app now
                // are, and its clear button only exists once there is text.
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: AppSearchField(
                      controller: TextEditingController(text: '猫'),
                      hint: '搜索文件…',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(key: const ValueKey('focused-field'), hint: '聚焦态'),
                ),
              ]),
              const SizedBox(height: 12),
              // Bare TextField / DropdownButtonFormField, styled by nothing but
              // `inputDecorationTheme`. This is what ~40 call sites across the
              // screens actually are — the ones whose hand-rolled decorations
              // were deleted in favour of the theme — so if the theme ever
              // stops reaching them, it shows up here rather than on one screen
              // nobody happened to open.
              Row(children: [
                const Expanded(
                  child: TextField(decoration: InputDecoration(labelText: '裸 TextField · 仅靠主题')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: '下拉'),
                    initialValue: 0,
                    items: const [DropdownMenuItem(value: 0, child: Text('Lanczos'))],
                    onChanged: (_) {},
                  ),
                ),
              ]),
              const _Label('开关与选择'),
              Row(children: [
                Switch(value: true, onChanged: (_) {}),
                const SizedBox(width: 8),
                Switch(value: false, onChanged: (_) {}),
                const SizedBox(width: 20),
                Checkbox(value: true, onChanged: (_) {}),
                const SizedBox(width: 8),
                Checkbox(value: false, onChanged: (_) {}),
              ]),
              const _Label('状态徽标'),
              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: const [
                AppStatusBadge(label: '执行中', kind: AppStatusKind.running),
                AppStatusBadge(label: '待处理', kind: AppStatusKind.pending),
                AppStatusBadge(label: '已完成', kind: AppStatusKind.done),
                AppStatusBadge(label: '失败', kind: AppStatusKind.failed),
                AppCountBadge(count: 3),
                AppCountBadge(count: 128),
              ]),
              const _Label('语义色 · 七个种子色下应完全一致'),
              const _SemanticRow(),
              const _Label('对话框外壳 · 危险动作'),
              // The chrome only, not any one dialog's body: the icon plate
              // takes its tint from `iconColor`, so this is also the check
              // that a destructive dialog comes out red at every seed rather
              // than in the user's accent.
              AppDialog(
                icon: Icons.warning_amber_rounded,
                iconColor: colorScheme.error,
                title: '覆盖原图？',
                subtitle: '此操作无法撤销',
                maxWidth: 460,
                onClose: () {},
                content: const Text('原始文件将被裁剪结果永久替换。'),
                actions: [
                  AppButton(label: '取消', variant: AppButtonVariant.text, onPressed: () {}),
                  AppButton(label: '覆盖原图', variant: AppButtonVariant.destructive, onPressed: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The spec's tracked group label: 600 weight, wide tracking, tertiary text.
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _SemanticRow extends StatelessWidget {
  const _SemanticRow();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final colorScheme = Theme.of(context).colorScheme;

    Widget chip(String label, Color background, Color foreground) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        );

    return Wrap(spacing: 10, runSpacing: 10, children: [
      chip('成功', semantic.successContainer, semantic.onSuccessContainer),
      chip('警告', semantic.warningContainer, semantic.onWarningContainer),
      chip('信息', semantic.infoContainer, semantic.onInfoContainer),
      // Matches AppStatusBadge's failed pairing rather than Material's own
      // container, so the four read as one family at the same weight.
      chip('危险', colorScheme.error.withValues(alpha: AppAlpha.tint), colorScheme.error),
    ]);
  }
}
