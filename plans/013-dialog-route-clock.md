# 013 — 对话框:入场时长与它自以为的对上,退场给一条回程曲线

- **Status**: DONE(2026-09-12 执行,flutter analyze 零问题,1763 个测试全通过)
- **Commit**: 0b97136
- **Severity**: HIGH
- **Category**: 缓动与时长(2)/ 无障碍(6)
- **Estimated scope**: 1 个文件新增约 20 行 + 17 个调用点各加 1 行 + 1 个测试

## Problem

### 一、它以为自己是 M3(280ms),实际上是 Flutter 的 150ms

```dart
// lib/widgets/app_dialog.dart:335-360 — 现状
/// Grows a dialog into place from 0.96 on the route's own animation (M3,
/// `00 · 1e`), so the exit mirrors the entrance for free. A plain fade under
/// reduce-motion; nothing outside a route, which is how widget tests render it.
class _Materialize extends StatelessWidget {
  const _Materialize({required this.child});

  final Widget child;

  static const double _from = 0.96;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || AppMotion.prefersReduced(context)) return child;

    return ScaleTransition(
      scale: Tween<double>(begin: _from, end: 1).animate(
        CurvedAnimation(parent: animation, curve: AppMotion.emphasized),
      ),
      child: child,
    );
  }
}
```

注释说 M3。`AppMotion.panel` 是 280ms。但这条 animation 的时钟不归本文件管,归
`showDialog` 造的 `DialogRoute` 管,而它的默认值是 **150ms**:

```dart
// flutter/packages/flutter/lib/src/material/dialog.dart:1853 — SDK,已核对
         transitionDuration: animationStyle?.duration ?? const Duration(milliseconds: 150),
```

全仓从没传过 `animationStyle`(`grep -rn "animationStyle" lib/` 为空)。所以:

- 缩放实际跑 150ms,却用着为 280ms 调的 `emphasized` 曲线(`Cubic(0.32, 0.72, 0, 1)`,
  一条慢起手、长尾巴的 M3 曲线)。在 150ms 里,这条曲线的尾巴被截断,0.96→1 的
  那点位移几乎全挤在前 60ms,读起来更像一次闪现而不是一次展开。
- 更要紧的是**它拿不到应用自己的降级**:`AppMotion.sceneOf`(`design_tokens.dart:362`)
  会在「减少视觉效果」开启时把 M3 降到 M2,在系统「减少动态效果」下归零。路由时长
  写死在 SDK 里,这两档降级对对话框一档都没生效——`_Materialize` 里那句
  `prefersReduced` 只关掉了缩放,幕布与淡入照旧跑 150ms。

`plans/README.md` 上一轮把这处列进了「判定正确、勿改」,理由是「骑路由自身 animation
所以出场自动反向」。那个**机制**是对的,本计划不动它;本计划修的是它骑着的那口钟。

### 二、退场是入场倒放,也就是一条 ease-in

`CurvedAnimation` 没给 `reverseCurve`。路由反向时,`emphasized` 被倒过来播——
`Cubic(0.32, 0.72, 0, 1)` 反过来是一条慢起手的 ease-in:对话框先在原尺寸上吊着,
再猛地缩走。准则第 3 条把 UI 上的 ease-in 列为直接拦截项。

## Target

一个集中的 `AnimationStyle`,加 `_Materialize` 的回程曲线:

```dart
// lib/widgets/app_dialog.dart — 目标(新增,放在 appDialogRadius 常量之后)

/// The clock every dialog route runs on.
///
/// `showDialog` hard-codes 150ms unless it is given an [AnimationStyle]
/// (`flutter/src/material/dialog.dart`), which is both off the M ladder and
/// deaf to the app's own reduce-visual-effects step-down. Passing this at
/// every call site is what puts dialogs back on [AppMotion.sceneOf]: M3
/// normally, M2 under reduce visual effects, nothing under the platform's
/// reduce motion.
///
/// Note `reverseDuration` is deliberately absent: `DialogRoute` extends
/// `RawDialogRoute`, which never overrides `reverseTransitionDuration`, so the
/// field would be silently ignored — the close is the same length as the open.
/// Shortening it would take a `DialogRoute` subclass and a hand-rolled
/// `showDialog`; that is deliberately out of scope here.
AnimationStyle appDialogAnimation(BuildContext context) => AnimationStyle(
      duration: AppMotion.sceneOf(context),
      curve: AppMotion.emphasized,
      reverseCurve: AppMotion.quick,
    );
```

```dart
// lib/widgets/app_dialog.dart:348-351 — 目标(改)
      scale: Tween<double>(begin: _from, end: 1).animate(
        CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          // M1 out: a dialog closing is a response, not a decision.
          reverseCurve: AppMotion.quick,
        ),
      ),
```

每个 `showDialog<…>(` 调用点多一行:

```dart
    return showDialog<T>(
      context: context,
      animationStyle: appDialogAnimation(context),
      barrierDismissible: barrierDismissible,
      …
```

## Repo conventions to follow

- `AppMotion` 在 `lib/core/design_tokens.dart:317`:`panel` = 280ms、`state` = 180ms、
  `emphasized` = `Cubic(0.32, 0.72, 0, 1)`、`quick` = `Cubic(0, 0, 0.2, 1)`;
  `sceneOf(context)`(`:362`)= 「M3,减少视觉效果时降 M2,减少动态效果时归零」。
- 「入场用 M2/M3、退场用 M1」这条已经有现成样板:
  `lib/widgets/glass/app_glass_menu.dart:127-130` 与 `:152`
  (`reverseCurve: AppMotion.quick`,反向时长 `AppMotion.hover`)。照它写。
- 集中一个 helper、让调用点只多一行,是本仓一贯做法(`showAppGlassMenu`、
  `AppSidePanel.show`、`AppSnackBar`)。

## Steps

1. `lib/widgets/app_dialog.dart`:在第 11 行 `const double appDialogRadius = …;`
   之后新增 `appDialogAnimation`(内容照抄 Target 节)。
2. 同文件 `_Materialize`(第 335 行):按 Target 节给 `CurvedAnimation` 加
   `reverseCurve: AppMotion.quick`。
3. 同文件类文档第 21-22 行那句
   `/// Use [AppDialog.show] for the common shape. For a dialog whose body owns its`
   `/// own layout, construct [AppDialog] inside your own `showDialog` call.`
   后面补一句:
   `/// Such a call must pass `animationStyle: appDialogAnimation(context)` — see there.`
4. 同文件 `AppDialog.show`(第 129 行的 `showDialog<T>(`):在 `context: context,`
   之后插入 `animationStyle: appDialogAnimation(context),`。
5. 其余 17 个 `showDialog<` 调用点同样处理。**每处都用它自己 `context:` 实参里的那个
   BuildContext**(不是别的局部变量):
   - `lib/screens/browser/folder_move_flow.dart:98`(`context: host` → 传 `host`)
   - `lib/screens/browser/staging_paste_flow.dart:122`
   - `lib/screens/browser/staging_paste_flow.dart:209`
   - `lib/screens/browser/widgets/folder_delete_dialog.dart:36`
   - `lib/screens/prompts/prompts_io.dart:88`
   - `lib/screens/prompts/widgets/prompt_dialogs.dart:86`
   - `lib/screens/prompts/widgets/prompt_dialogs.dart:181`
   - `lib/screens/prompts/widgets/prompt_dialogs.dart:285`
   - `lib/screens/prompts/widgets/prompt_dialogs.dart:498`
   - `lib/screens/workbench/widgets/result_feedback_dialog.dart:25`
   - `lib/widgets/dialogs/image_size_picker_dialog.dart:22`
   - `lib/widgets/dialogs/prompt_history_dialog.dart:180`
   - `lib/widgets/models/channel_form_sections.dart:927`
   - `lib/widgets/models/channel_wizard_dialog.dart:1061`
   - `lib/widgets/searchable_picker.dart:329`
   - `lib/widgets/settings_widgets.dart:295`
   - `lib/widgets/theme_accent_picker.dart:599`
   凡是尚未 import `app_dialog.dart` 的文件,加
   `import '<相对路径>/widgets/app_dialog.dart';`(多数已经 import 了)。
6. `test/reduced_motion_test.dart`:加一条钉住这次修复的测试——
   ```dart
   testWidgets('a dialog route runs on the M ladder, not showDialog\'s 150ms', (tester) async {
     // 挂一个带 MaterialApp 的宿主,调用 AppDialog.show,
     // 取 ModalRoute.of(dialogContext)!.transitionDuration:
     expect(route.transitionDuration, AppMotion.panel);
   });
   ```
   照该文件既有测试的挂载方式写;再加一条「开启减少动态效果时该值为 `Duration.zero`」。
7. `flutter analyze`。

## Boundaries

- **不要**去改 `DialogRoute` 的反向时长(不要写 `DialogRoute` 子类、不要手抄
  `showDialog` 的函数体、不要用 `PageRouteBuilder` 代替)。退场与入场等长是本计划
  **明知并接受**的限制,理由写在 `appDialogAnimation` 的文档注释里。
- 不要改 `_from = 0.96`、不要改 `_Materialize` 的 `prefersReduced` 分支、不要给它加
  淡入(幕布的淡入由 `DialogRoute` 自己做)。
- 不要动 `AppDialog` 的任何布局、圆角、内边距、footer、`barrierDismissible` 取值。
- 不要动 `showModalBottomSheet` 或 `showGeneralDialog` 的调用点——侧边面板是
  `plans/014`,两份计划不重叠文件。
- 不要顺手把 17 个调用点的其他参数「统一」一下。
- 不要新增依赖。
- 若 `lib/widgets/app_dialog.dart:335-360` 与上文引用的不符,**停下来报告**。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `grep -rn "showDialog<" lib/ | wc -l` 与
    `grep -rn "animationStyle: appDialogAnimation" lib/ | wc -l` → 两个数必须相等(18)
  - `flutter test` → 全量通过(注意 `test/app_dialog_test.dart`、
    `test/app_dialog_capabilities_test.dart`、`test/channel_wizard_dialog_test.dart`
    里若有 `pump(Duration(milliseconds: 150))` 之类的定量 pump,会因为时长变长而红;
    这种情况改测试里的 pump 时长,**不要**回退本计划)
  - `flutter test test/screenshots` → 通过且无新增溢出
- **Feel check**:`flutter run --release`
  - 任意打开一个对话框(设置 → 任一确认框、或「提示词」屏的编辑框)。修复前后最容易
    看出来的地方是**开的那一下**:修复后 0.96→1 的展开有了可读的行程(280ms),而不是
    一次几乎看不见的闪现。连开两次对比。
  - 关掉它:应该是**干脆地**收走(`quick` 是一条强 ease-out);若看到「先不动、
    最后一下猛缩」,说明 `reverseCurve` 没生效。
  - 打开系统「减少动态效果」后重启:对话框应瞬间出现与消失(路由时长归零),
    幕布也不再有 150ms 的淡入——这是修复前做不到的。
  - 打开应用自己的「减少视觉效果」:对话框应明显更快(180ms)但仍有行程。
- **Done when**:两个 `grep` 计数相等;新测试里
  `ModalRoute.transitionDuration == AppMotion.panel`;减少动态效果下为
  `Duration.zero`;全量测试与截图测试通过。
