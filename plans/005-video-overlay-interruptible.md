# 005 — 视频播放/暂停覆盖层改为可中断的常驻淡入淡出

- **Status**: DONE(2026-08-22 执行,diff 审查通过,analyze 零问题)
- **Commit**: b2d4b9c
- **Severity**: MEDIUM
- **Category**: 可中断性 / 一致性
- **Estimated scope**: 1 个文件,1 个 build 方法

## Problem

视频工作台的播放覆盖层用 `AnimatedSwitcher` 按 key 换件:

```dart
// lib/screens/workbench/widgets/video_workbench_view.dart:239-253 — 现状
return AnimatedSwitcher(
  duration: const Duration(milliseconds: 200),
  child: value.isPlaying
      ? const SizedBox.shrink(key: ValueKey('playing'))
      : Container(
          key: const ValueKey('paused'),
          color: Colors.black26,
          child: Center(
            child: IconButton(
              icon: const Icon(Icons.play_arrow, size: 64, color: Colors.white),
              onPressed: () => controller.play(),
            ),
          ),
        ),
);
```

`AnimatedSwitcher` 不会中途重定向——新 key 开一段新淡入并保留旧子件淡出,快速连点
播放/暂停会叠出播放按钮的重影;且每次切换都增删节点。而同一仓库的另一个视频播放器
已经写明了正确做法并解释了为什么:

```dart
// lib/screens/workbench/widgets/preview/video_preview_handler.dart:280-287 — 样板
// Always present (opacity-driven) so toggling play/pause never
// adds or removes a node from the tree — structural churn is a
// trigger for the accessibility-bridge tree-update errors.
ExcludeSemantics(
  child: IgnorePointer(
    child: AnimatedOpacity(
      opacity: (!_controller!.value.isPlaying && _showOverlay) ? 1.0 : 0.0,
```

同一个应用里,同一种覆盖层,一处可中断、一处不可。

## Target

改为常驻节点 + `AnimatedOpacity`(隐式,可中途折返),播放时穿透点击:

```dart
// 目标(替换 239-253 的整个 return)
return IgnorePointer(
  ignoring: value.isPlaying,
  child: AnimatedOpacity(
    opacity: value.isPlaying ? 0.0 : 1.0,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    child: Container(
      color: Colors.black26,
      child: Center(
        child: IconButton(
          icon: const Icon(Icons.play_arrow, size: 64, color: Colors.white),
          onPressed: () => controller.play(),
        ),
      ),
    ),
  ),
);
```

要点:
- `IgnorePointer(ignoring: value.isPlaying)` 保证隐藏时不拦截点击(原来 `SizedBox.shrink`
  的行为);显示时按钮可点,故不能像样板那样无条件 `IgnorePointer`(样板的点击由外层手势处理,
  此处按钮自己接收点击)。
- 不需要 `ExcludeSemantics`:按钮在可见时应保留语义;隐藏时如需屏蔽读屏,可用
  `ExcludeSemantics(excluding: value.isPlaying, child: ...)` 包在 `AnimatedOpacity` 外——
  执行时采用这个带条件的写法。
- 外层 `ValueListenableBuilder`(:236)保持不变,注释(:234-235)里提到 AnimatedSwitcher
  的句子相应更新。
- 如 002 号计划已落地,`Duration(milliseconds: 200)` 用 `AppMotion.reveal`、
  `Curves.easeOutCubic` 用 `AppMotion.enter`(字面值等价)。

## Repo conventions to follow

- 样板即 `video_preview_handler.dart:259-299` 的整段做法(RepaintBoundary 包纹理、
  覆盖层常驻、opacity 驱动)。
- `flutter analyze` 零问题(CLAUDE.md)。

## Steps

1. 按目标替换 `_VideoControls.build` 中的 `AnimatedSwitcher` 段(`video_workbench_view.dart:239-253`)。
2. 更新 :234-235 的注释,使其描述新的 opacity 常驻方案。
3. `flutter analyze` → "No issues found!"。

## Boundaries

- 只改 `_VideoControls` 这一个类。不动 `video_preview_handler.dart`(它是样板)。
- 不动播放器控制器逻辑、不动 :110-116 的结果卡入场动画(归 002)。
- 与摘录不符即停止上报。

## Verification

- **机械验证**:`flutter analyze` 零问题。
- **感受验证**(`flutter run --release`,生成或加载一个视频):
  - 快速连点视频区域切换播放/暂停:遮罩与按钮的透明度从当前值折返,无重影、无从头重播;
  - 播放中(覆盖层隐藏)点击视频画面:点击应到达底下的暂停手势,不被透明覆盖层吃掉;
  - 暂停时点击中央播放按钮:正常恢复播放。
- **Done when**:三条感受验证成立,analyze 通过。
