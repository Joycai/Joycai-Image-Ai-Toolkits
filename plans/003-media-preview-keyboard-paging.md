# 003 — 媒体预览:键盘翻页去动画,远跳不再刷屏

- **Status**: DONE(2026-08-22 执行,diff 审查通过,analyze 零问题)
- **Commit**: b2d4b9c
- **Severity**: HIGH
- **Category**: 目的与频率 / 缓动与时长
- **Estimated scope**: 1 个文件(media_preview_dialog.dart),3 个方法

## Problem

媒体预览对话框是每张生成图的复查回路,左右方向键绑定翻页:

```dart
// lib/screens/workbench/widgets/preview/media_preview_dialog.dart:132-135 — 现状
const SingleActivator(LogicalKeyboardKey.arrowLeft): _prevImage,
const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nextImage(images.length),
const SingleActivator(LogicalKeyboardKey.home): () => _jumpToPage(0),
const SingleActivator(LogicalKeyboardKey.end): () => _jumpToPage(images.length - 1),
```

而每次单步是 300ms `easeInOut`:

```dart
// media_preview_dialog.dart:48-67 — 现状
void _nextImage(int count) {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  if (workbenchUIState.activePreviewIndex < count - 1) {
    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }
}

void _prevImage() {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  if (workbenchUIState.activePreviewIndex > 0) {
    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }
}

void _jumpToPage(int index) {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  if (workbenchUIState.activePreviewIndex != index) {
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }
}
```

问题:(1) 键盘发起的高频操作,审计频率表规定"永不加动画";按住方向键扫一批 40 张
渲染结果时,每次按键重启一段 300ms 减速补间,`easeInOut` 前 ~90ms 几乎不动,正是用户
盯着看的时刻。(2) `Home`/`End` 及缩略图远跳用 `animateToPage` 在 300ms 里滚过整个
列表,是一场糊屏刮擦而非跳转。

## Target

- 键盘单步(`_nextImage` / `_prevImage`)→ **瞬时** `jumpToPage`,无动画;
- `_jumpToPage`:相邻页(距离 1)→ 200ms `easeOutCubic` 动画;更远 → 瞬时 `jumpToPage`。

```dart
// 目标
void _nextImage(int count) {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  final i = workbenchUIState.activePreviewIndex;
  if (i < count - 1) {
    _pageController.jumpToPage(i + 1);
  }
}

void _prevImage() {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  final i = workbenchUIState.activePreviewIndex;
  if (i > 0) {
    _pageController.jumpToPage(i - 1);
  }
}

void _jumpToPage(int index) {
  final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
  final current = workbenchUIState.activePreviewIndex;
  if (current == index) return;
  if ((current - index).abs() == 1) {
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  } else {
    _pageController.jumpToPage(index);
  }
}
```

若 002 号计划(AppMotion 令牌)已落地,把 `Duration(milliseconds: 200)` 写作
`AppMotion.reveal`、`Curves.easeOutCubic` 写作 `AppMotion.enter`(字面值等价);未落地则
用上面的字面值。

文件 272 行附近若还有第四处 `animateToPage(..., 300ms, easeInOut)`(缩略图点击路径),
将其改为调用统一后的 `_jumpToPage(index)`,不留第二套时长。

## Repo conventions to follow

- 本仓库对高频操作即时响应的先例:`lib/main.dart:355` 主导航硬切换;
  `lib/widgets/dialogs/task_log_dialog.dart:73-76` 日志尾随用 `jumpTo` 而非 `animateTo`。
- PageView 的手势滑动(触屏/拖拽)不经过这三个方法,天然保持原有物理滚动,勿动。

## Steps

1. 按上述目标改写 `_nextImage`、`_prevImage`、`_jumpToPage`(`media_preview_dialog.dart:48-67`)。
2. 搜索该文件所有 `animateToPage` / `nextPage` / `previousPage` 调用(含约 272 行处),
   统一收敛到这三个方法;不允许残留手写 300ms。
3. `flutter analyze` → "No issues found!"。

## Boundaries

- 只改这一个文件。不动键位绑定(132-138 行)。
- 不动 PageView 的构建、手势、图片加载逻辑。
- 不动 `setup_wizard.dart` 的翻页(首次运行场景,300ms 合理,归 002 令牌化)。
- 与摘录不符即停止上报。

## Verification

- **机械验证**:`flutter analyze` 零问题。
- **感受验证**(`flutter run --release`,打开一个多图文件夹的预览):
  - 单击方向键:图片瞬间切换,连按/按住时逐帧跟手,无补间残影;
  - `Home`/`End`:直接落到首/末张,不出现中间页扫过;
  - 点击相邻缩略图:有一段 200ms 的快出缓收滑动;点击远处缩略图:直接跳达;
  - 触屏/拖拽滑动翻页手感与改动前一致。
- **Done when**:上述四条全部成立,且文件内不再有 `Duration(milliseconds: 300)`。
