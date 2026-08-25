// Every component the design spec's 标准组件 sheet lists, on one page, rendered
// once per theme seed in both brightnesses.
//
// The screen matrix next door answers "does this screen lay out?". This
// answers the other question the spec raises: the sheet is drawn in one teal,
// the app ships eight seeds, and the accent rules only work if the *structure*
// survives all of them. Fourteen PNGs is few enough to actually look at, which
// is the point — 8 screens × 8 seeds × 2 brightnesses is not.
//
// What to look for in the output:
//   · greys stay grey — no seed tint in the panel, the track or the rules
//   · every selected thing uses accentTint/accentRing, at the same strength
//   · success/warning/info are identical across all seven columns
//   · the focused input's glow ring is visible at every seed, in both themes
//   · the selected segment's label reads at every seed, especially in dark
//   · the list row's selected label is the *darker* accent on its own wash,
//     not one tone against itself
//   · the neutral slider stays grey while the parameter one takes the accent
//
// Two families here are drawn as specimens rather than mounted for real, and
// the reason is the same for both: a [Tooltip]'s bubble and a [PopupMenu]'s
// sheet live in the [Overlay], which is outside the subtree this golden
// captures. The tooltip specimen reads its own [TooltipThemeData] and paints
// it, so it still photographs the theme rather than a copy of it. The menu is
// absent altogether — its item geometry is not themed (see the note on
// `popupMenuTheme`), so a specimen would be inventing the very thing that is
// missing.

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
import 'package:joycai_image_ai_toolkits/widgets/app_empty_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_icon_button.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_search_field.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_section_label.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_segmented_control.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_status_badge.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_text_field.dart';

void main() {
  for (final MapEntry<String, Color> seed in AppConstants.presetThemes.entries) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('gallery · ${seed.key} · ${brightness.name}', (tester) async {
        // Tall enough for the whole column. The golden captures the rendered
        // subtree, and a [SingleChildScrollView] clips — anything past the
        // viewport is simply not in the PNG, silently.
        tester.view.physicalSize = const Size(720, 1860);
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

        // Pumped to a fixed point rather than settled. The page carries two
        // indeterminate progress indicators, which never stop animating, so
        // `pumpAndSettle` waits for a frame that will not come. A fixed
        // duration also puts their sweep in the same place in all sixteen
        // shots, which is what makes them comparable at a glance.
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

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
                AppStatusBadge(label: '未保存', kind: AppStatusKind.warning),
                AppStatusBadge(label: '失败', kind: AppStatusKind.failed),
                AppCountBadge(count: 3),
                AppCountBadge(count: 128),
              ]),
              const _Label('分组小标题 · 两种语气'),
              // The accent tone is the one that has to be checked here: it is
              // small, semibold, and sits on `surface`, which is where an
              // accent is least forgiving. The neutral tone is what every
              // caption on this page already is.
              const Row(children: [
                Expanded(
                  child: AppSectionLabel('价格配置', padding: EdgeInsets.zero),
                ),
                Expanded(
                  child: AppSectionLabel(
                    '分类管理',
                    tone: AppSectionTone.neutral,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ]),
              const _Label('语义色 · 七个种子色下应完全一致'),
              const _SemanticRow(),
              const _Label('列表行 · 40 单行 / 48 双行'),
              const _ListRows(),
              const _Label('滑杆 · 参数（主色）与中性（灰阶）'),
              const _Sliders(),
              const _Label('筛选 chip'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilterChip(
                  label: const Text('全部'),
                  selected: true,
                  onSelected: (_) {},
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                FilterChip(
                  label: const Text('对话'),
                  selected: false,
                  onSelected: (_) {},
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const FilterChip(
                  label: Text('禁用'),
                  selected: false,
                  onSelected: null,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ]),
              const _Label('进度条'),
              const _Progress(),
              const _Label('工具提示 · 明暗共用同一个底'),
              const _TooltipSpecimen(),
              const _Label('空状态'),
              AppEmptyState(
                icon: Icons.inbox_outlined,
                label: '还没有模型',
                description: '先添加一个渠道，再从它拉取可用的模型。',
                action: AppButton(
                  label: '添加渠道',
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.compact,
                  accentLabel: true,
                  onPressed: () {},
                ),
              ),
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

/// The states `10e` 「列表行」 draws, minus hover — which is a pointer state and
/// so cannot be photographed by a golden that never moves a mouse.
class _ListRows extends StatelessWidget {
  const _ListRows();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      outlined: true,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.folder, size: 20, color: Color(0xFFE0A64B)),
            title: const Text('ai_res'),
            trailing: Text('39', style: Theme.of(context).textTheme.labelMedium?.mono),
            onTap: () {},
          ),
          ListTile(
            selected: true,
            leading: const Icon(Icons.photo_library_outlined, size: 20),
            title: const Text('全部来源'),
            trailing: Text('39', style: Theme.of(context).textTheme.labelMedium?.mono),
            onTap: () {},
          ),
          ListTile(
            enabled: false,
            leading: Icon(Icons.folder, size: 20, color: colorScheme.outline),
            title: const Text('离线卷 (D:)'),
            trailing: Text('—', style: Theme.of(context).textTheme.labelMedium?.mono),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.memory_outlined, size: 20),
            title: const Text('gemini-2.5-flash-image'),
            subtitle: const Text('图生图 · 1568×2712 上限'),
            trailing: const Icon(Icons.chevron_right, size: 17),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

/// Both halves of `10e`'s two-slider split, side by side — which is the only
/// way to see that the neutral one has stayed neutral.
class _Sliders extends StatelessWidget {
  const _Sliders();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Slider(value: 0.62, onChanged: (_) {})),
      const SizedBox(width: 16),
      Expanded(
        child: SliderTheme(
          data: neutralSliderTheme(Theme.of(context).colorScheme),
          child: Slider(value: 0.52, onChanged: (_) {}),
        ),
      ),
    ]);
  }
}

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Expanded(child: LinearProgressIndicator(value: 0.34)),
      const SizedBox(width: 16),
      // Indeterminate. Pumped to a fixed point by the harness, so the sweep
      // lands in the same place in every shot.
      const Expanded(child: LinearProgressIndicator()),
      const SizedBox(width: 16),
      const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(value: 0.68, strokeWidth: 2.5),
      ),
      const SizedBox(width: 12),
      const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ]);
  }
}

/// The tooltip bubble, painted from its own theme.
///
/// A real [Tooltip] renders into the [Overlay], which this golden's subtree
/// does not include — so mounting one would photograph nothing. Reading
/// [TooltipTheme] and drawing it keeps the specimen honest: change the theme
/// and this changes with it, exactly as the real bubble does.
class _TooltipSpecimen extends StatelessWidget {
  const _TooltipSpecimen();

  @override
  Widget build(BuildContext context) {
    final tooltip = TooltipTheme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        decoration: tooltip.decoration,
        padding: tooltip.padding,
        child: Text('在系统播放器中打开', style: tooltip.textStyle),
      ),
    );
  }
}

/// The gallery's own section captions.
///
/// The real component now, not a fourth hand-rolled copy of it — so this sheet
/// also photographs the label itself under every seed, which is where the
/// accent tone has to prove it stays legible. Neutral here: these caption the
/// specimens rather than group a form's controls.
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => AppSectionLabel(
        text,
        tone: AppSectionTone.neutral,
        padding: const EdgeInsets.only(top: 22, bottom: 10),
      );
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
