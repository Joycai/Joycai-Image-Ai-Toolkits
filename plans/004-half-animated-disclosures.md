# 004 — 修复"半动画"展开控件:容器在动,内容在跳

- **Status**: DONE(2026-08-22 执行,diff 审查通过,analyze 零问题,截图测试 87 通过无溢出)
- **Commit**: b2d4b9c
- **Severity**: MEDIUM
- **Category**: 目的与频率 / 可中断性
- **Estimated scope**: 3 个文件,各 1 处结构性小改

同一缺陷的三个实例:动画描述了错误的轴,或只动了装饰、正文瞬移。修好的样板就在仓库里
——`lib/widgets/collapsible_card.dart:99-120` 用 `SizeTransition` 让内容与高度同步展开。
三处共用一个修法:**让尺寸变化经过 `AnimatedSize`(隐式、可中途重定向),内容保持挂载**。

如 002 号计划已落地,下文所有 `Duration(milliseconds: 200)` 用 `AppMotion.reveal`、
`Curves.easeOutCubic` 用 `AppMotion.enter`、`Curves.easeInOutCubic` 用 `AppMotion.move`
(字面值等价);未落地则用字面值。

---

## (a) 任务胶囊:宽度滑行 300ms,高度瞬间跳变

```dart
// lib/widgets/task_capsule_monitor.dart:81-84 — 现状
child: AnimatedContainer(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOut,
  width: capsuleWidth,
```
```dart
// task_capsule_monitor.dart:174-175 — 现状(点击展开时这段直接插入,高度无动画)
if (_isExpanded) ...[
  const Divider(height: 20),
```

**目标**:
1. `AnimatedContainer` 的时长降为 200ms(直接点按的控件,300ms 顶着预算上限),曲线改
   `Curves.easeInOutCubic`(宽度形变属于屏上移动):
   ```dart
   child: AnimatedContainer(
     duration: const Duration(milliseconds: 200),
     curve: Curves.easeInOutCubic,
     width: capsuleWidth,
   ```
2. 在 `ClipRRect`(:102)内、`Column`(:107)外包一层 `AnimatedSize`,让高度与宽度同步动:
   ```dart
   child: ClipRRect(
     borderRadius: BorderRadius.circular(24),
     child: AnimatedSize(
       duration: const Duration(milliseconds: 200),
       curve: Curves.easeInOutCubic,
       alignment: Alignment.topCenter,
       child: Column(
   ```
   (`AnimatedSize` 是隐式动画,连点展开/收起会从当前尺寸重定向,不会从零重播。)

---

## (b) 提示词卡片:箭头旋转 200ms,解释一个早已瞬间完成的展开

```dart
// lib/widgets/prompt_card.dart:70-71 — 现状(内容硬切换)
if (isExpanded) _buildExpandedContent(context, colorScheme)
else _buildCollapsedContent(context, colorScheme),
```
(同文件 :102-104 的 `AnimatedRotation` 箭头在转,正文却瞬移——002 计划只给它加曲线,
结构问题在本计划修。)

**目标**:给内容切换区包 `ClipRect` + `AnimatedSize`,高度随内容过渡:

```dart
ClipRect(
  child: AnimatedSize(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: isExpanded
        ? _buildExpandedContent(context, colorScheme)
        : _buildCollapsedContent(context, colorScheme),
  ),
),
```

注意 `prompt_card.dart` 是 StatelessWidget、展开态来自外部 `isExpanded`——`AnimatedSize`
不需要本地状态,正好适配。文本内容本身瞬换、高度滑动,与箭头旋转同步即达标;不要求交叉淡化。

---

## (c) 下载器日志面板:0px 高的盒子里塞着整块面板

```dart
// lib/screens/downloader/image_downloader_screen.dart:317-327 — 现状
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  height: _showLogs && state.logs.isNotEmpty ? 196 : 0,
  child: _showLogs && state.logs.isNotEmpty
      ? _DownloaderLogPanel(
          logs: state.logs,
          isAnalyzing: state.isAnalyzing,
          onClose: () => setState(() => _showLogs = false),
        )
      : const SizedBox.shrink(),
),
```

同一条件同时驱动补间和子树替换:收起时缩的是一个已经空了的盒子,展开时把完整面板硬挤进
0px 高的容器里 200ms(触发布局溢出风险)。

**目标**:子树常驻(仅在 `state.logs.isNotEmpty` 时构建),用 `ClipRect` + `OverflowBox`
让面板始终按 196px 排版、由容器裁切:

```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOutCubic,
  height: _showLogs && state.logs.isNotEmpty ? 196 : 0,
  child: state.logs.isNotEmpty
      ? ClipRect(
          child: OverflowBox(
            minHeight: 196,
            maxHeight: 196,
            alignment: Alignment.topCenter,
            child: _DownloaderLogPanel(
              logs: state.logs,
              isAnalyzing: state.isAnalyzing,
              onClose: () => setState(() => _showLogs = false),
            ),
          ),
        )
      : const SizedBox.shrink(),
),
```

## Repo conventions to follow

- 正确样板:`lib/widgets/collapsible_card.dart:99-120`(SizeTransition + ClipRect 思路)。
- 状态管理规则(CLAUDE.md):不为共享数据新建 StatefulWidget——本计划全部用隐式动画,不新增控制器。

## Steps

1. 改 (a):`task_capsule_monitor.dart`,两处如上。
2. 改 (b):`prompt_card.dart`,一处如上。
3. 改 (c):`image_downloader_screen.dart`,一处如上。
4. `flutter analyze` → "No issues found!"。
5. `flutter test test/screenshots` 跑一遍,确认运行输出没有新增 overflow 报告
   (尤其 (c) 的 OverflowBox 不应再触发布局溢出)。

## Boundaries

- 不改三个组件的颜色、圆角、文案、内边距。
- 不动 `collapsible_card.dart`(它是样板,且归 002 调曲线)。
- 不新增依赖、不引入 AnimationController。
- 与摘录不符即停止上报。

## Verification

- **机械验证**:`flutter analyze` 零问题;截图测试无新增 overflow 输出。
- **感受验证**(`flutter run --release`):
  - 跑一个批量任务,点击浮动胶囊:宽与高作为同一个动作一起展开;连续快速点击,动画从当前值折返,不闪跳;
  - 提示词库里展开/收起卡片:高度随箭头旋转同步滑动,下方卡片被平滑推开而非跳位;
  - 下载器切换日志:面板像从上边缘卷帘展开/收起,而非凭空出现;分析进行中(日志持续增长)切换依然顺滑。
- **Done when**:三处均无"容器在动、内容瞬移"现象,analyze 与截图测试通过。
