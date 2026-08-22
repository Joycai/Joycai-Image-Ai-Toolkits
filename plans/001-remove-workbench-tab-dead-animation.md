# 001 — 移除工作台模式切换的 300ms 死区动画

- **Status**: DONE(2026-08-22 执行,diff 审查通过,analyze 零问题)
- **Commit**: b2d4b9c
- **Severity**: HIGH
- **Category**: 目的与频率 / 可中断性
- **Estimated scope**: 2 个文件,4 处单行修改

## Problem

工作台顶栏的模式切换是全应用使用频率最高的控件(每天数十到上百次),但它经由
`TabController.animateTo` 驱动一个**没有任何组件在渲染的动画**:整个
`lib/screens/workbench/` 下不存在 `TabBarView`(可用 grep 验证),中央内容实际由
`workbench_screen.dart:877` 的 `switch (appState.workbenchTabIndex)` 选择。

`workbench_screen.dart:642-649` 的监听器以 `!indexIsChanging` 为门:

```dart
// lib/screens/workbench/workbench_screen.dart:642 — 现状
_tabController.addListener(() {
  if (!_tabController.indexIsChanging) {
    if (_tabController.index != _lastKnownTabIndex) {
      _lastKnownTabIndex = _tabController.index;
      _appState!.setWorkbenchTab(_tabController.index);
```

`animateTo` 期间 `indexIsChanging` 保持 true 直到动画结束(`kTabScrollDuration` =
300ms),所以**每次切换模式,内容要等 300ms 的不可见动画跑完才更换**。这 300ms 里
`workbench_top_bar.dart:103` 的 `AnimatedBuilder(animation: tabController)` 还在每一
vsync 重建整条可滚动工具栏 Row。

触发 `animateTo` 的四个位置:

```dart
// lib/screens/workbench/widgets/workbench_top_bar.dart:123 — 现状
onChanged: tabController.animateTo,
```
```dart
// lib/screens/workbench/widgets/workbench_top_bar.dart:137 — 现状
onSelect: (i) => tabController.animateTo(i),
```
```dart
// lib/screens/workbench/widgets/workbench_top_bar.dart:147 — 现状
onPressed: () => tabController.animateTo(t.index),
```
```dart
// lib/screens/workbench/workbench_screen.dart:545 — 现状(外部导航同步回 controller)
_tabController.animateTo(targetIndex);
```

审计频率表:每天 100+ 次的操作——**永不加动画**。何况这个动画连画面都没有,是纯延迟。

## Target

四处全部改为直接赋值 `tabController.index = i`。`TabController` 的 `index` setter 等价于
零时长切换:立即更新 index、立即通知监听器、且通知时 `indexIsChanging` 为 false——
现有 642 行监听器无需改动即可即时生效。选中态的视觉反馈由 `AppSegmentedControl`
自带的 180ms 填充动画提供,不受影响。

```dart
// workbench_top_bar.dart:123 — 目标
onChanged: (i) => tabController.index = i,
```
```dart
// workbench_top_bar.dart:137 — 目标
onSelect: (i) => tabController.index = i,
```
```dart
// workbench_top_bar.dart:147 — 目标
onPressed: () => tabController.index = t.index,
```
```dart
// workbench_screen.dart:545 — 目标
_tabController.index = targetIndex;
```

## Repo conventions to follow

- 本仓库刻意让高频切换即时完成的先例:`lib/main.dart:355` 的
  `Expanded(child: screens[displayIndex])` ——主导航就是硬切换,数字快捷键同样走这条路。
- 修改后 `flutter analyze` 必须零问题(CLAUDE.md 硬性要求)。

## Steps

1. 先验证前提:`grep -r "TabBarView" lib/screens/workbench/` 应无结果。若有结果,停止并上报。
2. 修改 `lib/screens/workbench/widgets/workbench_top_bar.dart` 的 123、137、147 三处,如上。
3. 修改 `lib/screens/workbench/workbench_screen.dart:545`,如上。
4. 确认 `workbench_screen.dart:550` 的 `if (_tabController.index == 4) _refreshKbStatus();`
   逻辑不变(index setter 同步生效,此行为保持)。

## Boundaries

- 不要动 `_initTabController` 里的监听器(642-649 行)——它在新写法下天然即时。
- 不要动 `AppSegmentedControl` 本身的动画。
- 不要改 `TabController` 的长度、初始化或 dispose。
- 如发现代码与上述摘录不一致(commit 漂移),停止并上报,不要即兴发挥。

## Verification

- **机械验证**:`flutter analyze` → "No issues found!"。
- **感受验证**:运行应用(`flutter run --release`),在工作台顶栏快速连点各模式:
  - 中央内容应在点击当帧更换,无任何可感知延迟;
  - 分段控件的选中填充仍有 180ms 的柔和过渡;
  - 从主导航跳转回工作台(外部导航路径)同样即时。
- **Done when**:analyze 通过,且模式切换的内容更换与点击之间无可感知的时间差。
