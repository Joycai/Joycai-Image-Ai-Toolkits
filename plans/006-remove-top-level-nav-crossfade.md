# 006 — 移除顶层导航的整屏交叉淡入

- **Status**: DONE(2026-08-27 执行,flutter analyze 零问题,1130 个测试全通过)
- **Commit**: 07906de
- **Severity**: HIGH
- **Category**: 目的与频率(1)/ 一致性(7)
- **Estimated scope**: 1 个文件,删除 12 行

## Problem

顶层导航(左侧 NavigationRail、移动端 NavigationBar、以及 **Ctrl/Cmd+1..8 快捷键**)
是全应用频率最高的动作。`7091ca5` 给它加了一层整屏 `AnimatedSwitcher` 交叉淡入:

```dart
// lib/main.dart:377 — 现状
                // The same crossfade the channel wizard gives its steps: the
                // app already had an opinion about moving between sibling
                // views, it just never applied it at the top level. Keyed by
                // index, not by widget — the screens are canonicalised consts,
                // so without a key the switcher would treat every destination
                // as the same child and never animate.
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.durationOf(context, AppMotion.reveal),
                    switchInCurve: AppMotion.enter,
                    switchOutCurve: AppMotion.enter,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: KeyedSubtree(
                      key: ValueKey(displayIndex),
                      child: screens[displayIndex],
                    ),
                  ),
                ),
```

三条独立的理由说明这层动画应当删除:

**一、它挂在键盘快捷键上。** 同一文件里 `lib/main.dart:225-233` 注册了 Ctrl/Cmd+1..8,
`lib/main.dart:262` 直接调用 `navigateToScreen(index)`,走的正是上面这个 switcher:

```dart
// lib/main.dart:262 — 现状
    Provider.of<AppState>(context, listen: false).navigateToScreen(index);
```

审计准则第 1 条把这一档定得很死:**每天 100 次以上的动作(键盘快捷键、命令面板)
不加动画,永远不加**。快捷键的全部意义是"立刻到那儿";200ms 的淡入把它变成"按下去,
等一下,到了"。Raycast 的命令面板没有开合动画,是同一条准则。

**二、整屏交叉淡入必然双重曝光。** 两个不透明的屏幕在 200ms 里同时挂在树上,中点是
两套完整 UI 的 50/50 混合——审计准则第 7 条点名的 "crossfades that visibly
double-expose"。渠道向导的两步之所以可以淡入,是因为两步的骨架相同、只换字段;工作台
和用量统计之间没有任何共同结构可言。

**三、它在最贵的时刻付双份渲染。** 淡入期间新旧两棵子树都要 build / layout / paint。
去往「模型」屏时,新树包含 `models_screen.dart:895` 那套 `IntrinsicHeight` 模型卡网格;
去往工作台时,新树包含整张缩略图网格,而旧树还在画。

上一轮审计(`plans/README.md`,commit `b2d4b9c`)明确把 `main.dart:355` 的**硬切换判为
正确**并写进了"勿改"清单。`7091ca5` 的提交说明把它记为一次"taste decision, decided
yes",理由是"渠道向导已经对兄弟视图有意见了,只是没用在顶层"——这是一致性论证,而
频率准则优先于一致性准则:同一条淡入用在每天点两次的向导上是对的,用在每天按几十次的
快捷键上是错的。

## Target

恢复 `7091ca5` 之前的写法——一行,无动画,无 key:

```dart
// lib/main.dart — 目标
                Expanded(child: screens[displayIndex]),
```

不要用更短的时长替代,不要保留 `KeyedSubtree`。屏幕切换的正确时长是**零**。

`KeyedSubtree` 可以一并删除:没有 `AnimatedSwitcher` 时 `screens[displayIndex]` 只占
一个孩子槽位,不同屏幕的 `runtimeType` 不同,Flutter 的 element 复用本来就会替换整棵
子树,key 不再承担任何作用。

## Repo conventions to follow

- 动效令牌在 `lib/core/design_tokens.dart:403`(`AppMotion`)。本计划**不新增令牌**,
  只做删除。
- "高频操作不加动画"在本仓库已有先例:`lib/screens/workbench/widgets/image_card.dart:234`
  的悬停操作条刻意不加动画(全应用最高频交互),`plans/001` 也是同一条准则的产物。
- 删除后 `lib/main.dart` 若不再用到 `AppMotion`,**不要**顺手删 import——同文件
  `lib/main.dart:708` 的导航栏项仍在用 `AppMotion.durationOf`。

## Steps

1. 打开 `lib/main.dart`,定位第 377–395 行。
2. 把第 377–395 行(注释块 + `Expanded(` 到与之配对的 `),`)整体替换为一行:
   ```dart
                Expanded(child: screens[displayIndex]),
   ```
   保持原有缩进(16 个空格),它是 `Row` 的 `children` 成员,后面紧跟着第 396 行的 `],`。
3. 不修改本文件的任何 import。
4. 运行 `flutter analyze`,确认 `AnimatedSwitcher` / `FadeTransition` / `KeyedSubtree`
   没有因此变成未使用的 import(它们来自 `package:flutter/material.dart`,不会)。

## Boundaries

- **只改 `lib/main.dart` 这一处。** 不要动 `lib/widgets/models/channel_wizard_dialog.dart:1213`
  的向导步骤淡入——那是每次建渠道才走一次的低频路径,判定为正确。
- 不要动 `lib/main.dart:707` 导航栏项自身的 `AnimatedContainer`(悬停/选中底色的
  160ms 变化),那是颜色反馈,不是屏幕切换。
- 不要改 `navigateToScreen`、快捷键注册、或 `AppState` 的任何逻辑。
- 不要新增依赖,不要改结构。
- 若第 377–395 行与上文引用的代码对不上(自 `07906de` 起有漂移),**停下来报告**,
  不要自行推断。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `flutter test test/screenshots` → 全部通过,无新增 overflow 输出
- **Feel check**:运行 `flutter run --release`,然后:
  - 按住 Ctrl 连点 1、2、3、4:每一屏必须在按键的那一帧就到位,不能看到上一屏的
    残影,也不能看到两屏叠在一起的灰糊状态。
  - 从「工作台」(有大量缩略图)按 Ctrl+5 切到「模型」再切回:切换瞬间不应有可见的
    掉帧或白闪。
  - 用鼠标点左侧导航栏逐个切换:导航项自己的底色仍然是柔和过渡(那个保留),但**内容
    区是硬切**。
- **Done when**:`grep -n "AnimatedSwitcher" lib/main.dart` 无输出,且
  `grep -n "Expanded(child: screens\[displayIndex\])" lib/main.dart` 命中一行。
