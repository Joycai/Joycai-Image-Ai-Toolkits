# 014 — 侧边面板:退场不再是入场倒放

- **Status**: TODO
- **Commit**: 0b97136
- **Severity**: MEDIUM
- **Category**: 缓动与时长(2)/ 一致性(7)
- **Estimated scope**: 1 个文件,新增 1 个私有路由类约 20 行 + 改写 `show` 约 15 行

## Problem

```dart
// lib/widgets/app_side_panel.dart:65-104 — 现状(节选)
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x40000000),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: AppMotion.prefersReduced(context)
          ? AppMotion.reveal
          : AppMotion.panel,
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: AppSidePanel(width: width, child: builder(context)),
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter);
        if (AppMotion.prefersReduced(context)) {
          return FadeTransition(opacity: curved, child: child);
        }
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(curved),
          child: child,
        );
      },
    );
```

两处:

1. **`CurvedAnimation` 没有 `reverseCurve`。** 关闭时 `AppMotion.enter`
   (`Cubic(0.2, 0.8, 0.2, 1)`,一条强 ease-out)被倒着播,得到的正是一条 ease-in:
   450px 宽的面板先几乎不动,再加速甩出屏幕。准则第 3 条把 UI 上的 ease-in 列为
   直接拦截项。
2. **退场与入场等长。** `showGeneralDialog` 不接受 `reverseTransitionDuration`,
   `RawDialogRoute` 也不覆盖它,`TransitionRoute` 于是回落到入场时长——面板要花满
   280ms 才走完。而 `AppMotion` 自己就定义了这件事该怎么办:

```dart
// lib/core/design_tokens.dart:333-334 — 应用自己的规矩
  /// How much faster an M3 exit runs than its entrance.
  static const double exitFactor = 0.6;
```

这条规矩在选择栏上已经用了(`browser_selection_bar.dart:60-62`),在玻璃菜单上也用了
(`app_glass_menu.dart:130`:反向走 M1)。**侧边面板是唯一一个两件事都没做的浮层**,
而它又是全应用位移最大的那一个,所以也是最容易看出来的那一个。

## Target

一个只加了「反向时长」的 `RawDialogRoute` 子类,外加一条回程曲线:

```dart
// lib/widgets/app_side_panel.dart — 目标(新增,放在 AppSidePanel 类之后)

/// [showGeneralDialog] with one thing added: an exit shorter than the
/// entrance.
///
/// `showGeneralDialog` takes no `reverseTransitionDuration`, `RawDialogRoute`
/// never overrides it, and `TransitionRoute` falls back to the forward one —
/// so 450px of panel used to take as long leaving as arriving. Everything else
/// here is what `showGeneralDialog` would have built.
class _AppSidePanelRoute<T> extends RawDialogRoute<T> {
  _AppSidePanelRoute({
    required super.pageBuilder,
    required super.transitionBuilder,
    required super.transitionDuration,
    required super.barrierColor,
    required super.barrierLabel,
    required this.reverseDuration,
  }) : super(barrierDismissible: true);

  final Duration reverseDuration;

  @override
  Duration get reverseTransitionDuration => reverseDuration;
}
```

```dart
// lib/widgets/app_side_panel.dart:65-104 — 目标(改)
    // Read once, here, rather than inside the transition builder: a route's
    // durations are fixed when it is pushed, so a builder that disagreed with
    // them would animate against a clock it cannot change.
    final Duration enter = AppMotion.prefersReduced(context)
        ? AppMotion.reveal
        : AppMotion.panel;
    // `00 · 1e`: an M3 exit runs at [AppMotion.exitFactor] of its entrance.
    // Arriving is the event; leaving is getting out of the way.
    final Duration leave =
        Duration(milliseconds: (enter.inMilliseconds * AppMotion.exitFactor).round());

    return Navigator.of(context, rootNavigator: true).push<T>(
      _AppSidePanelRoute<T>(
        // 25%, not the 50% black showGeneralDialog defaults to. … (既有注释原样保留)
        barrierColor: const Color(0x40000000),
        // Material's own translated label … (既有注释原样保留)
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
        transitionDuration: enter,
        reverseDuration: leave,
        pageBuilder: (context, _, _) => Align(
          alignment: Alignment.centerRight,
          child: AppSidePanel(width: width, child: builder(context)),
        ),
        // The one transition in the app that does *not* collapse to nothing
        // under reduce-motion … (既有注释原样保留)
        transitionBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.enter,
            // M1 out. Without this the panel leaves on `enter` played
            // backwards, which is an ease-in: it hangs, then bolts.
            reverseCurve: AppMotion.quick,
          );
          if (AppMotion.prefersReduced(context)) {
            return FadeTransition(opacity: curved, child: child);
          }
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(curved),
            child: child,
          );
        },
      ),
    );
```

数值:入场 280ms(减少动态效果时 180),退场 168ms(减少动态效果时 108)。

## Repo conventions to follow

- `AppMotion`(`lib/core/design_tokens.dart:317`):`panel` = 280、`reveal` = 180、
  `exitFactor` = 0.6、`enter` = `Cubic(0.2, 0.8, 0.2, 1)`、`quick` = `Cubic(0, 0, 0.2, 1)`。
- `exitFactor` 的既有算法样板照抄
  `lib/screens/browser/widgets/browser_selection_bar.dart:60-62`:
  `Duration(milliseconds: (duration.inMilliseconds * AppMotion.exitFactor).round())`。
- 「入场 M2/M3、退场 M1」的既有样板:`lib/widgets/glass/app_glass_menu.dart:127-130`
  与 `:152`。那个文件同样是自己 push 一个 `PopupRoute` 而不是用 `showXxx` 辅助函数——
  本计划让侧边面板走上同一条路。
- 文件已 import `package:flutter/material.dart`(含 `RawDialogRoute`、`Navigator`、
  `MaterialLocalizations`),无需新增 import。

## Steps

1. `lib/widgets/app_side_panel.dart`:在 `AppSidePanel` 类的右花括号之后新增
   `_AppSidePanelRoute<T>`,内容照抄 Target 节。
2. 同文件 `AppSidePanel.show`(第 41 行起)的 **desktop 分支**(第 65-104 行,
   即 `return showGeneralDialog<T>(` 那一段)按 Target 节改写:
   - 在 `return` 之前算出 `enter` 与 `leave` 两个局部变量;
   - `showGeneralDialog<T>(context: context, …)` 换成
     `Navigator.of(context, rootNavigator: true).push<T>(_AppSidePanelRoute<T>(…))`;
   - 删掉 `context:` 与 `barrierDismissible: true`(后者移进了路由类的 `super` 调用);
   - `transitionDuration:` 用 `enter`,新增 `reverseDuration: leave`;
   - `CurvedAnimation` 加 `reverseCurve: AppMotion.quick`;
   - **第 67-73、75-76、88-93 行那几段既有注释一个字都不要删**,原样跟着各自的参数走。
3. `flutter analyze`。

## Boundaries

- **窄窗口分支不要动**(第 47-62 行的 `showModalBottomSheet` / `DraggableScrollableSheet`):
  手机上的表单是另一套呈现,有它自己的手势与物理。
- 不要改 `barrierColor` 的 `0x40000000`、不要改 `barrierLabel`、不要改
  `Offset(1, 0)` 的入场方向、不要改 `appSidePanelWidth`、不要碰 `AppSidePanel.build`
  里的阴影与圆角。
- **不要动那条减少动态效果时改用淡入的例外**(第 88-93 行的注释与
  `if (AppMotion.prefersReduced(context)) return FadeTransition(...)`)。那是
  `design_tokens.dart` 点名记录在案的刻意取舍,不翻案——只是它现在也一并拿到了
  更短的退场。
- 不要顺手加 `InheritedTheme.capture`:`showGeneralDialog` 本来也不做(已核对 SDK
  `widgets/routes.dart:2760-2788`),加了就是行为变更。
- 不要改 `showDialog` 相关的任何东西——那是 `plans/013`,两份计划不重叠文件。
- 不要新增依赖。
- 若第 65-104 行与上文引用的不符,**停下来报告**。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `flutter test test/app_side_panel_test.dart` → 全绿。该文件用的是
    `pumpAndSettle`(第 41/76/99/156/158 行),对时长不敏感,不应受影响。
  - `flutter test test/prompt_history_sheet_test.dart` → 全绿
  - `flutter test` → 全量通过
  - `grep -n "showGeneralDialog" lib/widgets/app_side_panel.dart` → 只应剩类文档
    第 20 行那句史料引用
- **Feel check**:`flutter run --release`,窗口拉宽(≥1000px),打开一个侧边面板
  (工作台 → 提示词库,或历史记录):
  - **关闭**它(点幕布或关闭按钮)。修复后应该是干脆地滑走;修复前是「先吊着、
    最后一下甩出去」。若一时看不出,连续开关三次,只盯**最初的 60ms**——那正是
    ease-in 与 ease-out 分道扬镳的地方。
  - 入场必须与修复前**完全一致**(280ms、`enter` 曲线、从右侧滑入)。这是回归面。
  - 幕布现在会跟着面板一起更快地退掉(它跑同一条 animation),这是预期的。
  - 打开系统「减少动态效果」后重启:开与关都应是交叉淡入淡出、无位移,关比开更快
    (108ms vs 180ms)。面板**不应**瞬间消失——那条例外是刻意保留的。
  - 把窗口缩窄到手机宽度,再开一次:应仍是从底部升起的表单,行为与修复前一致。
- **Done when**:退场明显快于入场且起手即动;入场逐帧与修复前一致;
  `flutter analyze` 零问题;全量测试通过。
