# 008 — 进度条:把 2Hz 的阶跃换成连续推进

- **Status**: DONE(2026-08-27 执行,flutter analyze 零问题,1130 个测试全通过)
- **Commit**: 07906de
- **Severity**: MEDIUM
- **Category**: 错失机会(8)/ 可中断性(4)/ 一致性与令牌(7)
- **Estimated scope**: 新建 1 个文件(约 60 行)+ 改 3 个文件的 6 个调用点

## Problem

任务进度不是连续量,是一个定时器每 500ms 重算一次的估值:

```dart
// lib/services/task_queue_service.dart:285 — 现状
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _updateProgress());
```
```dart
// lib/services/task_queue_service.dart:316 — 现状
            task.progress = math.min(elapsed / targetMs, 0.99);
```

而全应用 6 个进度显示都把这个值**直接**交给 Flutter 的进度指示器。
`LinearProgressIndicator` / `CircularProgressIndicator` 在确定值模式下不做任何隐式动画
——给多少画多少。于是这 6 处**每秒钟只动两下**,每下跳一大格:

```dart
// lib/widgets/task_capsule_monitor.dart:280 — 现状
                        child: LinearProgressIndicator(
                          value: avgProgress,
```
```dart
// lib/widgets/task_capsule_monitor.dart:321 — 现状
                                child: CircularProgressIndicator(
                                  value: t.progress,
```
```dart
// lib/widgets/task_capsule_monitor.dart:362 — 现状
            CircularProgressIndicator(
              value: progress,
```
```dart
// lib/widgets/app_run_console.dart:150 — 现状
                  child: LinearProgressIndicator(
                    value: avgProgress > 0 ? avgProgress : null,
```
```dart
// lib/widgets/app_run_console.dart:299 — 现状
                child: LinearProgressIndicator(
                  value: avgProgress > 0 ? avgProgress : null,
```
```dart
// lib/screens/batch/task_queue_screen.dart:1247 — 现状
    return LinearProgressIndicator(
      value: task.progress,
```

这是全应用**唯一**表示「正在干活」的视觉语言:悬浮任务胶囊、运行控制台状态栏、任务队列
每一行,都靠它。而 2Hz 的阶跃恰好落在"卡住了"和"在动"之间最难看的那一档——太慢,读不出
连续;太快,又不像刻意的分段。审计准则第 8 条点名的正是这类"本该有动画却硬跳"的接缝,
而准则第 2 条给出了这一类的曲线:**恒定运动用 `linear`**。

本仓库已经有一处正确样板,只是没有推广到进度上:

```dart
// lib/screens/workbench/widgets/video_workbench_view.dart:107 — 正确写法
        child: TweenAnimationBuilder<double>(
          key: ValueKey(uiState.lastGeneratedVideoPath),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: AppMotion.durationOf(context, AppMotion.panel),
          curve: AppMotion.enter,
```

## Target

新建 `lib/widgets/smooth_progress.dart`,内容如下,原样照抄:

```dart
import 'package:flutter/widgets.dart';

import '../core/design_tokens.dart';

/// 任务队列自己的节拍。
///
/// [TaskQueueService] 用一个周期定时器重算每个在跑任务的 progress,这就是那个定时器的
/// 周期——见 `lib/services/task_queue_service.dart:285`。补间时长取整整一拍,新值落地
/// 的那一刻上一拍刚好走完:连续行进,不追赶,也不过冲。
///
/// 刻意**不**放进 [AppMotion]。AppMotion 的阶梯是 UI 过渡的预算,上限 300ms;这不是一次
/// 过渡,而是被跟踪的外部数据源的节拍。
const Duration kTaskProgressTick = Duration(milliseconds: 500);

/// 让进度指示器在任务队列每 500ms 报一次的两个值之间连续推进。
///
/// 传 null 就原样透传——不确定态没有可插值的目标,Flutter 自己的循环动画接管。
class SmoothProgress extends StatelessWidget {
  const SmoothProgress({super.key, required this.value, required this.builder});

  /// 上报的进度,或 null 表示不确定态。
  final double? value;

  /// 构建指示器。回调拿到的是插值后的值,原样交给指示器的 `value:`。
  final Widget Function(BuildContext context, double? value) builder;

  @override
  Widget build(BuildContext context) {
    final target = value;
    if (target == null) return builder(context, null);

    return TweenAnimationBuilder<double>(
      // 不给 begin:TweenAnimationBuilder 首帧会把 end 抄进 begin
      // (SDK `widgets/tween_animation_builder.dart:187`),所以一条 60% 的进度条
      // 出现时就在 60%,不会从 0 扫上来。之后每次值变化都从补间**当前所在处**重新
      // 指向新目标——这正是任务被取消、重排或提前完成时不会跳格的原因。
      tween: Tween<double>(end: target),
      duration: AppMotion.durationOf(context, kTaskProgressTick),
      // 恒定运动,所以 linear。缓动过的进度条会在两个本就随时间线性变化的值之间
      // 忽快忽慢。
      curve: Curves.linear,
      builder: (context, v, _) => builder(context, v),
    );
  }
}
```

6 个调用点各自包一层。示例(其余 5 处同理,**只**把原指示器整体挪进 `builder`,
并把它的 `value:` 换成回调参数 `v`):

```dart
// lib/widgets/task_capsule_monitor.dart:280 — 目标
                        child: SmoothProgress(
                          value: avgProgress,
                          builder: (context, v) => LinearProgressIndicator(
                            value: v,
                            minHeight: 3,
                            backgroundColor: colorScheme.surfaceContainer,
                            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                          ),
                        ),
```

## Repo conventions to follow

- 共享组件放 `lib/widgets/`,一个文件一个组件,类名不带 `App` 前缀的先例:
  `lib/widgets/scroll_edge_fade.dart`(`ScrollEdgeFade`)、`lib/widgets/dashed_border.dart`。
- 动效令牌在 `lib/core/design_tokens.dart:403`;所有 `duration:` 走
  `AppMotion.durationOf(context, …)`(该文件 441-457 行说明了为什么)。
- 三个待改文件都已 import `design_tokens.dart`
  (`app_run_console.dart:5`、`task_capsule_monitor.dart:4`、`task_queue_screen.dart:14`),
  只需为新文件加相对 import。
- 文档注释解释**为什么**,不复述做了什么;中文注释在本仓库的计划与新代码里都可接受,
  但如果所在文件通篇英文注释(`app_run_console.dart` 等),调用点**不要**新增注释。

## Steps

1. 新建 `lib/widgets/smooth_progress.dart`,内容为上面 Target 节的代码,原样照抄。
2. `lib/widgets/task_capsule_monitor.dart`:在 import 区加 `import 'smooth_progress.dart';`
   (同目录,相对路径不带 `../`),按现有 import 的排列位置插入。
3. 同文件第 280–285 行,按 Target 节示例改写(`value: avgProgress`)。
4. 同文件第 321–325 行:
   ```dart
                                child: SmoothProgress(
                                  value: t.progress,
                                  builder: (context, v) => CircularProgressIndicator(
                                    value: v,
                                    strokeWidth: 2,
                                    backgroundColor: colorScheme.surfaceContainer,
                                  ),
                                ),
   ```
5. 同文件第 362–366 行(在 `_buildStatusIcon` 里):
   ```dart
            SmoothProgress(
              value: progress,
              builder: (context, v) => CircularProgressIndicator(
                value: v,
                strokeWidth: 2.5,
                backgroundColor: colorScheme.surfaceContainer,
              ),
            ),
   ```
6. `lib/widgets/app_run_console.dart`:加 `import 'smooth_progress.dart';`,
   然后第 150–155 行:
   ```dart
                  child: SmoothProgress(
                    value: avgProgress > 0 ? avgProgress : null,
                    builder: (context, v) => LinearProgressIndicator(
                      value: v,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: colorScheme.primary,
                    ),
                  ),
   ```
7. 同文件第 299–304 行:
   ```dart
                child: SmoothProgress(
                  value: avgProgress > 0 ? avgProgress : null,
                  builder: (context, v) => LinearProgressIndicator(
                    value: v,
                    minHeight: 4,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.18),
                    color: colorScheme.primary,
                  ),
                ),
   ```
8. `lib/screens/batch/task_queue_screen.dart`:加
   `import '../../widgets/smooth_progress.dart';`,然后第 1247–1253 行:
   ```dart
    return SmoothProgress(
      value: task.progress,
      builder: (context, v) => LinearProgressIndicator(
        value: v,
        minHeight: 3,
        borderRadius: BorderRadius.zero,
        backgroundColor: colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
      ),
    );
   ```
9. `flutter analyze`,修掉任何未使用的 import。

## Boundaries

- **只包这 6 个调用点。** 明确**不要**动下面两处——它们是比例条(占比可视化),不是任务
  进度,而且有测试直接读取其 `LinearProgressIndicator` widget:
  - `lib/screens/metrics/widgets/usage_summary.dart:288`(`test/usage_summary_test.dart:84,99`)
  - `lib/screens/metrics/widgets/usage_group_costs.dart:118`(`test/usage_group_costs_test.dart:74,101,114`)
- 也不要动这两处:`lib/screens/wizard/setup_wizard.dart:293`(向导步数,离散量,跳格是对的)、
  `lib/widgets/settings_widgets.dart:344`(备份进度,与任务队列的 500ms 节拍无关)、
  `lib/screens/downloader/image_downloader_screen.dart:438`(常量不确定态,无 value)。
- 不要改 `lib/services/task_queue_service.dart` 的定时器周期或 progress 计算。
- 不要往 `AppMotion` 里加 500ms 令牌——理由写在新文件的注释里。
- 不要新增依赖。
- 若引用的行与实际不符(自 `07906de` 起有漂移),**停下来报告**。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `flutter test test/task_queue_row_test.dart test/task_capsule_bounds_test.dart` → 通过
  - `flutter test test/usage_summary_test.dart test/usage_group_costs_test.dart` → 通过
    (这两个是本计划**不该**碰到的区域的护栏,必须依然绿)
  - `flutter test test/screenshots` → 通过,无新增 overflow
- **Feel check**:`flutter run --release`,派一批(≥3 张图)图像处理任务,然后:
  - 盯住悬浮胶囊的线性条与它左上角的环形进度:两者必须**同步、连续**地推进,
    不再每半秒跳一格。若两者不同步,说明其中一处漏改。
  - 打开「任务队列」屏,看任意一行底边那条 3px 进度沿:同样连续。
  - 任务完成的一瞬间:条走到头即停,不应回弹、不应从 0 重扫一遍。
  - 中途取消一个任务:条应从**当前位置**变化,不应先跳回 0 再动。
  - 打开系统的「减少动态效果」后重启:进度条恢复成每半秒跳一格(补间时长归零),
    这是预期行为,不是回归。
- **Done when**:`grep -rn "SmoothProgress" lib | wc -l` ≥ 7(1 处定义 + 6 处调用),
  `flutter analyze` 零问题,且胶囊上的线性条与环形进度肉眼同步连续。
