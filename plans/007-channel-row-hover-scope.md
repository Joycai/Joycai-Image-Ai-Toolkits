# 007 — 渠道行悬停:把悬停状态从整屏下沉到行内

- **Status**: DONE(2026-08-27 执行,flutter analyze 零问题,1130 个测试全通过)
- **Commit**: 07906de
- **Severity**: HIGH
- **Category**: 性能(5)/ 一致性与令牌(7)/ 无障碍(6)
- **Estimated scope**: 1 个文件,新增 1 个私有 widget(约 55 行),删除 3 处

## Problem

「模型」屏左栏每一个渠道行的悬停状态存在**屏幕级** State 上:

```dart
// lib/screens/models/models_screen.dart:76 — 现状
  int? _hoveredChannelId;
```
```dart
// lib/screens/models/models_screen.dart:398 — 现状
        child: InkWell(
          onTap: () => setState(() => _selectedChannelId = channel.id),
          // Hover both reveals the handle and says the row can be picked up.
          onHover: draggable
              ? (hovering) => setState(
                  () => _hoveredChannelId = hovering ? channel.id : null)
              : null,
```

于是**指针每一次进出任何一个渠道行**,都会 `setState` 整个 `_ModelsScreenState`,重建
`build → _buildPanelLayout` 里那整个 `Row`——包括右侧那一栏。右栏不是懒加载列表:

```dart
// lib/screens/models/models_screen.dart:893 — 现状
        final cells = <Widget>[
          for (final m in visible) _buildModelCard(m, l10n, appState, channel),
          _buildAddModelCard(l10n, appState, channel),
        ];
```
```dart
// lib/screens/models/models_screen.dart:902 — 现状
                child: IntrinsicHeight(
```

当前渠道下的**每一张模型卡**都被急切构建,并且每两张卡包在一个 `IntrinsicHeight` 里。
`IntrinsicHeight` 会对子树做一次额外的完整测量 pass,是 Flutter 里最贵的 layout 之一。
把鼠标从渠道列表顶部划到底部(10 个渠道)= 20 次 `setState` = 20 次整屏 build + 20 次
全套 `IntrinsicHeight` 重测量,只为把一个 12px 的把手淡入。渠道越多、模型越多,越卡。

本仓库对这类问题已有明确判例——`test/workbench_rebuild_scope_test.dart` 的整个文件就是
为了钉住"父级不要把重建推给孩子"。同样地,本仓库自己的两个卡片组件把悬停状态放在行内:

```dart
// lib/screens/workbench/widgets/image_card.dart:234 — 正确写法
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
```

这里的 `setState` 只重建那一张卡。`file_card.dart:100` 同理。渠道行是全应用唯一把悬停
状态往上放的地方。

**同一处还有第二个问题——令牌漂移:**

```dart
// lib/screens/models/models_screen.dart:418 — 现状
                  child: AnimatedOpacity(
                    opacity: showHandle ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.linear,
```

`120` 恰好等于 `AppMotion.hover`,`Curves.linear` 却不是任何令牌;更重要的是它没有走
`AppMotion.durationOf`,因此**平台的「减少动态效果」开关对这处完全无效**——全应用只有
这里和 `model_edit_dialog.dart:705`(见 `plans/010`)漏网。审计准则第 2 条:入场/出场
一律 ease-out;本仓库的对应令牌是 `AppMotion.enter`。

## Target

悬停标志下沉到一个只包住「把手 + 行内容」的私有 widget,`setState` 的作用域缩到一行;
同时把时长/曲线收回令牌。

新增 widget(放在 `lib/screens/models/models_screen.dart` 第 52 行
`_ChannelLongPressDragListener` 之后、`class ModelsScreen` 之前):

```dart
/// 渠道行左内边距上那个悬停才出现的 12px 拖拽把手。
///
/// 单独成 widget 只为一件事:悬停标志留在这一行里。放在
/// [_ModelsScreenState] 上时,指针每进出一行都会重建左右两栏——包括右栏那一叠
/// 由 `IntrinsicHeight` 逐个测量的模型卡。同 `image_card.dart` 与
/// `file_card.dart`,悬停是行自己的事。
class _ChannelHoverHandle extends StatefulWidget {
  const _ChannelHoverHandle({
    required this.enabled,
    required this.tooltip,
    required this.child,
  });

  /// 该行是否可拖拽。为 false 时不装 [MouseRegion],把手恒隐。
  final bool enabled;

  final String tooltip;

  /// 行本身的内容。
  final Widget child;

  @override
  State<_ChannelHoverHandle> createState() => _ChannelHoverHandleState();
}

class _ChannelHoverHandleState extends State<_ChannelHoverHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = Stack(
      children: [
        // The handle is painted *over* the row's existing left padding
        // rather than taking a column of its own: revealing it must not
        // move the avatar, the name or the subline by a pixel, which is
        // the whole argument for 方案乙 over the always-on grip.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 12,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.enabled && _hovering ? 1 : 0,
              duration: AppMotion.durationOf(context, AppMotion.hover),
              curve: AppMotion.enter,
              child: Center(
                child: Tooltip(
                  message: widget.tooltip,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 12,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );

    if (!widget.enabled) return content;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: content,
    );
  }
}
```

调用处变成:

```dart
// lib/screens/models/models_screen.dart — 目标
        child: InkWell(
          onTap: () => setState(() => _selectedChannelId = channel.id),
          mouseCursor: draggable ? SystemMouseCursors.grab : null,
          child: _ChannelHoverHandle(
            enabled: draggable,
            tooltip: l10n.channelReorderHandleTooltip,
            child: Padding(
              // ……行内容原样不动……
            ),
          ),
        ),
```

## Repo conventions to follow

- 动效令牌在 `lib/core/design_tokens.dart:403`。`AppMotion.hover` = 120ms,
  `AppMotion.enter` = `Curves.easeOutCubic`,`AppMotion.durationOf(context, token)`
  是**每一处 `duration:` 都必须经过的入口**(见该文件 441-457 行的说明)。
  `models_screen.dart:8` 已经 import 了 `design_tokens.dart`,无需新增 import。
- 行内悬停状态的样板:`lib/screens/workbench/widgets/image_card.dart:230-270`。
- 本文件的私有 widget 放在文件顶部:`_ChannelLongPressDragListener` 在第 39–52 行。
- 注释风格:解释**为什么**,不解释做了什么(参见本文件既有注释)。

## Steps

1. 打开 `lib/screens/models/models_screen.dart`。
2. 在第 52 行(`_ChannelLongPressDragListener` 的收尾 `}`)之后、第 54 行
   `class ModelsScreen extends StatefulWidget {` 之前,插入上面 Target 节给出的
   `_ChannelHoverHandle` / `_ChannelHoverHandleState` 两个类,原样照抄。
3. 删除第 76 行的字段:
   ```dart
     int? _hoveredChannelId;
   ```
4. 删除下面这一行局部变量(插入新类后行号会下移,按内容定位;原第 385 行):
   ```dart
       final showHandle = draggable && _hoveredChannelId == channel.id;
   ```
5. 在 `_buildChannelRow` 里,删除 `InkWell` 的 `onHover` 参数——即原第 400–404 行
   这五行(注释 `// Hover both reveals...` 连同 `onHover: draggable ? ... : null,`)。
   保留 `onTap:` 与 `mouseCursor:`。
6. 把原第 406–434 行——从 `child: Stack(` 起,到闭合那个 `Positioned(` 的 `),` 为止
   (即紧接在 `Padding(` 之前的那一行)——整段替换为三行:
   ```dart
          child: _ChannelHoverHandle(
            enabled: draggable,
            tooltip: l10n.channelReorderHandleTooltip,
   ```
   `Padding(` 及其后的行内容**一个字都不要动**(包括它现有的、与父级对不齐的缩进)。
7. 把原第 488–489 行这两行:
   ```dart
            ],
          ),
   ```
   替换为一行(它现在只需闭合 `_ChannelHoverHandle(`):
   ```dart
          ),
   ```
8. 运行 `flutter analyze`。若报 `colorScheme` 或 `l10n` 未使用,说明第 5–7 步删多了,
   回退重做——`_buildChannelRow` 里这两个局部变量在行内容中仍有大量使用。

## Boundaries

- **只改 `lib/screens/models/models_screen.dart`。**
- 不要动 `_buildChannelRow` 里 `Padding(` 之后的任何行内容、任何颜色、任何文案。
- 不要动 `models_screen.dart:527` 的 `Curves.easeOutCubic.transform(animation.value)`
  ——那是拖拽代理 `_channelDragProxy` 手动采样 `ReorderableListView` 自己的 animation,
  不是一个 `duration:`,判定为正确。
- 不要顺手去改 `models_screen.dart:893` 的急切构建或 `:902` 的 `IntrinsicHeight`——
  它们的注释记录了为什么不能换成固定 extent 的 `GridView`,是结构取舍,不在本计划内。
  本计划只把**触发**重建的频率从「每次悬停」降到「从不」。
- 不要新增依赖,不要新建文件。
- 若第 3–7 步引用的代码与实际不符(自 `07906de` 起有漂移),**停下来报告**。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `flutter test test/channel_ordering_test.dart` → 全部通过(渠道拖拽排序的既有覆盖)
  - `flutter test test/screenshots` → 全部通过,无新增 overflow
  - `grep -n "_hoveredChannelId" lib/screens/models/models_screen.dart` → 无输出
  - `grep -n "Curves.linear" lib/screens/models/models_screen.dart` → 无输出
- **Feel check**:`flutter run --release` → 「模型」屏(桌面宽度),选一个模型较多的渠道:
  - 鼠标缓慢划过左栏每一行:12px 把手在指针下的那一行淡入,离开淡出;**头像、名称、
    副行不得有任何一个像素的位移**。
  - 快速上下扫过整列渠道:把手的淡入淡出必须连续跟手,不出现卡顿或成批闪烁;右栏
    模型卡在整个过程中**不应有任何视觉变化**。
  - 悬停后立刻按下拖拽:把手已在位,拖拽照常工作(桌面按下即拖,触摸设备长按)。
  - 在系统设置里打开「减少动态效果」(Windows:显示动画;macOS:减弱动态效果),
    重启应用,重复第一条:把手应当**瞬间**出现/消失,而不是 120ms 淡入。这一条是
    修复前做不到的。
- **Done when**:上面两个 `grep` 均无输出,`flutter analyze` 零问题,且悬停时右栏无重绘。
