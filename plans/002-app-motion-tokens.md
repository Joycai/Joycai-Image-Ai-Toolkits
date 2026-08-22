# 002 — 建立 AppMotion 动效令牌,消灭 19 处 linear 默认曲线

- **Status**: DONE(2026-08-22 执行,27/27 替换落地,diff 抽查通过,analyze 零问题)
- **Commit**: b2d4b9c
- **Severity**: HIGH
- **Category**: 缓动与时长 / 一致性与令牌
- **Estimated scope**: 约 16 个文件,每处 1-3 行;新增 1 个令牌类

## Problem

Flutter 所有隐式动画组件的默认曲线是 `Curves.linear`(SDK
`implicit_animations.dart` 中 `this.curve = Curves.linear`)。本仓库有 **19 处 UI 动画
未传 `curve:`,即以 linear 运行**——而 linear 只适用于匀速运动(跑马灯、进度条),
用在状态变化/出现消失上会显得机械呆板。同时时长是手写的散值
(90/120/140/150/180/200/250/300/350ms),同一类工作用着两三种不同的数字。典型:

```dart
// lib/screens/workbench/widgets/image_card.dart:242 — 现状(无 curve → linear)
child: AnimatedContainer(
  duration: const Duration(milliseconds: 200),
```
```dart
// lib/screens/browser/widgets/browser_selection_bar.dart:29-35 — 现状
// 同一次出现,滑动 180ms easeOutCubic、淡入 150ms linear,两条腿不同步
child: AnimatedSlide(
  offset: visible ? Offset.zero : const Offset(0, 2),
  duration: const Duration(milliseconds: 180),
  curve: Curves.easeOutCubic,
  child: AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 150),
```
```dart
// lib/core/constants.dart:65 — 现状(失败的事实令牌:全库仅 1 处使用)
static const Duration animationDuration = Duration(milliseconds: 200);
```

`constants.dart:67-70` 的注释记载了几何常量正是因为"没人用、应用全在用字面量"才迁去
`design_tokens.dart`——`animationDuration` 是那次迁移的漏网之鱼,正在重演同样的失败。

## Target

### 1. 新令牌类(加入 `lib/core/design_tokens.dart`)

按该文件的既有惯例:裸 class + `static const`、成员名表达"职责"而非数值、每个成员带
说明用途与取值理由的文档注释、阶梯刻意量化。需要 `import 'package:flutter/animation.dart';`
(若该文件现有 import 已覆盖则不加)。

```dart
/// Motion tokens. One duration per job, one curve per direction of travel —
/// not per hand-typed value. Before this class the app had nine durations
/// (90–350ms) and three curves doing four jobs, 19 sites shipping Flutter's
/// default `Curves.linear`. The ladder is quantised the same way AppRadius
/// and AppAlpha are: using a value not on it is how motion drifts.
class AppMotion {
  /// Hover / focus micro-feedback. Short enough to feel attached to the
  /// pointer; anything longer trails it.
  static const Duration hover = Duration(milliseconds: 120);

  /// Selection state: card borders, chip fills, segment pills. 160 sits in
  /// the press-feedback band (100–160ms) — selection is feedback, not a scene
  /// change, and grids animate many tiles at once (Ctrl+A), so shorter is
  /// calmer.
  static const Duration state = Duration(milliseconds: 160);

  /// Disclosure and reveal: expand/collapse, crossfades, overlay fades.
  static const Duration reveal = Duration(milliseconds: 200);

  /// Panels and paging: drawers, side panels, wizard pages. Top of the UI
  /// budget; nothing in the app should exceed this.
  static const Duration panel = Duration(milliseconds: 300);

  /// Entrances, exits and state changes — starts fast, lands softly, so the
  /// change registers the moment it begins. Never use easeIn on UI.
  static const Curve enter = Curves.easeOutCubic;

  /// On-screen movement (width morphs, page slides): accelerates and
  /// decelerates because both endpoints are visible.
  static const Curve move = Curves.easeInOutCubic;
}
```

### 2. 全量替换表

每一行:改 `duration:` 为对应令牌、加(或替换)`curve:`。文件需
`import '...core/design_tokens.dart';`(多数已导入,按需补)。

| 文件:行 | 元素 | 现状 | 目标 |
|---|---|---|---|
| `lib/widgets/panel_resizer.dart:127` | 分隔条手柄 hover | 120ms,无 curve | `AppMotion.hover` + `curve: AppMotion.enter` |
| `lib/main.dart:660` | 导航栏条目底色/宽度 | 140ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/widgets/app_text_field.dart:138-139` | 焦点环 | 140ms easeOut | `AppMotion.hover` + `curve: AppMotion.enter` |
| `lib/screens/downloader/widgets/downloader_results_area.dart:182` | 选中勾选框 | 150ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/screens/workbench/widgets/optimizer_config_panel.dart:705` | 过滤 chip | 150ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/widgets/models/channel_wizard_dialog.dart:1082` | 供应商卡片选中 | 150ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/widgets/app_segmented_control.dart:131-132` | 分段控件填充 | 180ms easeOut | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/screens/workbench/widgets/gallery_toolbar.dart:480-481` | 视图切换按钮 | 180ms easeOut | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/widgets/settings_widgets.dart:80` | 主题色块边框 | 200ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/widgets/settings_widgets.dart:374` | 字体选项行 | 200ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/screens/workbench/widgets/image_card.dart:243` | 画廊卡片选中边框 | 200ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/screens/browser/widgets/file_card.dart:71` | 浏览器文件卡片选中 | 200ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/screens/browser/widgets/browser_selection_bar.dart:31-32` | 选择条滑入 | 180ms easeOutCubic | `AppMotion.state` + `curve: AppMotion.enter` |
| `lib/screens/browser/widgets/browser_selection_bar.dart:35` | 选择条淡入 | 150ms,无 curve | `AppMotion.state` + `curve: AppMotion.enter`(与滑入统一) |
| `lib/widgets/prompt_card.dart:103` | 展开箭头旋转 | 200ms,无 curve | `AppMotion.reveal` + `curve: AppMotion.enter` |
| `lib/widgets/models/channel_wizard_dialog.dart:991` | 步骤内容 AnimatedSwitcher | 200ms,无 curve | `AppMotion.reveal` + `switchInCurve: AppMotion.enter, switchOutCurve: AppMotion.enter` |
| `lib/widgets/models/channel_wizard_dialog.dart:1146` | 步骤圆点宽度 6↔18 | 200ms,无 curve | `AppMotion.reveal` + `curve: AppMotion.move` |
| `lib/widgets/models/channel_form_sections.dart:215` | 颜色选择 AnimatedCrossFade | 200ms,三条 curve 全 linear | `AppMotion.reveal` + `firstCurve: AppMotion.enter, secondCurve: AppMotion.enter, sizeCurve: AppMotion.enter` |
| `lib/screens/workbench/widgets/preview/video_preview_handler.dart:271` | 控制条淡入淡出 | 300ms,无 curve | `AppMotion.reveal` + `curve: AppMotion.enter`(顺带修复与 :287 的 300/200 不一致) |
| `lib/screens/workbench/widgets/preview/video_preview_handler.dart:287` | 中央播放按钮淡入 | 200ms,无 curve | `AppMotion.reveal` + `curve: AppMotion.enter` |
| `lib/widgets/collapsible_card.dart:41` | 折叠卡控制器 | `AppConstants.animationDuration` | `AppMotion.reveal` |
| `lib/widgets/collapsible_card.dart:44` | 高度因子曲线 | `Curves.easeInOut` | `AppMotion.enter`(展开/收起是 reveal,按决策序用 ease-out 族) |
| `lib/widgets/collapsible_card.dart:100` | SizeTransition 曲线 | `Curves.easeInOut` | `AppMotion.enter` |
| `lib/widgets/app_side_panel.dart:70,77` | 右侧面板滑入 | 300ms easeOutCubic | `AppMotion.panel` + `AppMotion.enter`(数值不变,仅令牌化) |
| `lib/screens/wizard/setup_wizard.dart:118,141,147,164,224` | 首次运行向导翻页 | 300ms easeInOut | `AppMotion.panel` + `AppMotion.move` |
| `lib/screens/workbench/widgets/prompt_optimizer_view.dart:134-135` | 聊天滚动到底 | 250ms easeOut | `AppMotion.panel` + `AppMotion.enter`(滚动距离可观,归 panel 档) |
| `lib/screens/workbench/widgets/video_workbench_view.dart:110-111` | 生成结果卡入场 | 350ms easeOutCubic | `AppMotion.panel` + `AppMotion.enter`(350 超出 300ms UI 上限,降为 panel) |

### 3. 删除失败令牌

迁移 `collapsible_card.dart:41` 之后删除 `lib/core/constants.dart:65` 的
`animationDuration`。同时更新 `test/screenshots/harness/shoot.dart` 约 145 行提及
"AppConstants.animationDuration" 的注释,改述为 AppMotion。

## Repo conventions to follow

- **先读 `docs/architecture/design-tokens.md`**(CLAUDE.md 对改动 `design_tokens.dart` 的硬性要求)。
- 令牌类范式的样板:`design_tokens.dart` 中现有的 `AppRadius` / `AppAlpha`——裸 class、
  `static const`、职责命名、每个成员的文档注释记录取值理由与被否方案。
- **不要动这些(刻意设计,已在审计中判定正确)**:
  - `lib/widgets/app_window_frame.dart:471` 的 90ms 标题栏按钮 hover(匹配 Windows 原生窗框节奏);
  - `lib/widgets/app_run_console.dart:334-339` 的 1400ms 呼吸脉冲(匀速往复的环境动画,easeInOut 正确);
  - `lib/screens/metrics/widgets/usage_list.dart:402` 的 600ms 是 Tooltip 的 `waitDuration`(延迟,非动画);
  - `lib/state/`、`lib/services/` 下的一切 `Duration`(防抖/轮询/超时,不是动画)。

## Steps

1. 读 `docs/architecture/design-tokens.md`,然后在 `lib/core/design_tokens.dart` 末尾加入上述 `AppMotion` 类。
2. 逐行执行替换表。每改一个文件确认 import 齐全。
3. 迁移 `collapsible_card.dart` 后删除 `constants.dart:65`,再
   `grep -rn "animationDuration" lib/ test/` 确认仅剩 shoot.dart 注释,更新之。
4. `flutter analyze` → 必须 "No issues found!"。

## Boundaries

- 仅改 `duration:` / `curve:` / 令牌定义,**不改任何布局、颜色、结构**。
- 不要碰 `task_capsule_monitor.dart`、`image_downloader_screen.dart`(归 004 计划)、
  `media_preview_dialog.dart`(归 003)、`video_workbench_view.dart:240` 的 AnimatedSwitcher(归 005)。
- 不新增依赖。发现与摘录不符即停止上报。

## Verification

- **机械验证**:`flutter analyze` 零问题;`flutter test test/screenshots/component_gallery_test.dart` 正常通过(静态截图不受动画值影响,此处是回归保险)。
- **感受验证**(`flutter run --release`):
  - 画廊中点选/取消点选图片卡:边框变化应"落地柔和"而非匀速呆板;Ctrl+A 全选时整屏卡片同时过渡不掉帧;
  - 浏览器中选中文件让选择条出现:滑入与淡入应完全同步为一个动作;
  - 折叠卡展开/收起:开头快、结尾缓,而不是对称的 easeInOut;
  - 视频预览控制条的显隐不再比中央播放按钮慢半拍。
- **Done when**:`grep -rn "Curves.linear" lib/` 无 UI 动画命中;替换表全部落地;analyze 通过。
