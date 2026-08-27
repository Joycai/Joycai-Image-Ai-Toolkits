# 010 — 收回模型编辑对话框里最后一处令牌漂移

- **Status**: DONE(2026-08-27 执行,flutter analyze 零问题,1130 个测试全通过)
- **Commit**: 07906de
- **Severity**: LOW
- **Category**: 一致性与令牌(7)/ 无障碍(6)
- **Estimated scope**: 1 个文件 2 行

## Problem

`plans/002` 把全应用的时长与曲线收进了 `AppMotion`,并规定每个 `duration:` 都要经过
`AppMotion.durationOf`。自那以后新写的模型编辑对话框漏了一处:

```dart
// lib/widgets/models/model_edit_dialog.dart:703 — 现状
        // The queue note (18a linkage: appears with the async selection).
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
```

数值本身是对的——`200` 就是 `AppMotion.reveal`,`Curves.easeOutCubic` 就是
`AppMotion.enter`。问题在于它绕开了 `durationOf`,于是**平台的「减少动态效果」开关对
这处完全无效**:开了该设置的用户在这个对话框里仍然会看到 200ms 的高度伸缩。

令牌自己的文档把这一点写得很直白:

```dart
// lib/core/design_tokens.dart:444 — 令牌的规定
  /// Every `duration:` in the app goes through this. Reaching for the raw
  /// token at a call site is now the drift, the same way a literal `160` was
  /// before the tokens existed.
```

修完这一处(以及 `plans/007` 里 `models_screen.dart:418` 那一处)之后,全应用就只剩
两个**刻意**不走 `durationOf` 的例外:`app_run_console.dart:382` 的呼吸圆点(它在
`didChangeDependencies` 里读 `prefersReduced` 并直接停表)与 `app_side_panel.dart:81`
(减弱动画时换成淡入而非归零,令牌文档点名的那个样板)。

## Target

```dart
// lib/widgets/models/model_edit_dialog.dart — 目标
        // The queue note (18a linkage: appears with the async selection).
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
```

## Repo conventions to follow

- `AppMotion` 在 `lib/core/design_tokens.dart:403`;`reveal` = 200ms(展开/揭示档),
  `enter` = `Curves.easeOutCubic`(入场/出场)。
- `model_edit_dialog.dart:26` 已经 import 了 `../../core/design_tokens.dart`,无需新增。
- 同一模式的正确样板就在隔壁:`lib/widgets/models/channel_form_sections.dart:238`。

## Steps

1. 打开 `lib/widgets/models/model_edit_dialog.dart`,把第 705 行
   `duration: const Duration(milliseconds: 200),` 换成
   `duration: AppMotion.durationOf(context, AppMotion.reveal),`。
2. 把第 706 行 `curve: Curves.easeOutCubic,` 换成 `curve: AppMotion.enter,`。
3. 第 707 行 `alignment: Alignment.topCenter,` 及其后的 `child:` 不动。
4. `flutter analyze`。

## Boundaries

- **只改这 2 行。** 不要改 `AnimatedSize` 的 `alignment`,不要改它的 child(那段
  `protocolAsyncQueueNote` 提示条的颜色、圆角、边框都由设计令牌决定,不在本计划内)。
- 不要顺手去改本文件其他地方的任何东西。
- 本计划**不**处理 `models_screen.dart:418` 的同类漂移——那处属于 `plans/007`,
  两份计划不重叠文件。
- 不要新增依赖。
- 若第 705–706 行与上文引用的不符,**停下来报告**。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `flutter test test/screenshots` → 通过
  - `grep -rn "Duration(milliseconds:" lib/widgets/models/` → 应无输出
- **Feel check**:`flutter run --release` → 「模型」屏 → 编辑任一模型 → 在协议一栏
  选中/取消一个异步(async)协议:
  - 那条队列说明的出现与收起仍是 200ms 的高度伸缩,顶部对齐,视觉与修复前一致。
  - 打开系统的「减少动态效果」后重启,重复上述操作:说明条应**瞬间**出现/消失。
    这一条是修复前做不到的,也是本计划唯一的可见收益。
- **Done when**:上述 `grep` 无输出,且减弱动画开关下该说明条不再伸缩。
