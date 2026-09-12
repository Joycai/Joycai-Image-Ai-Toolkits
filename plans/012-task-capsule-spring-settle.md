# 012 — 任务胶囊:甩出去的力道要算数,位移改走 transform

- **Status**: DONE(2026-09-12 执行,flutter analyze 零问题,1763 个测试全通过)
- **Commit**: 0b97136
- **Severity**: HIGH
- **Category**: 可中断性(4)/ 性能(5)
- **Estimated scope**: 2 个文件(1 个源文件约 +45/−10 行,1 个测试文件改 4 行)

## Problem

### 一、松手后的那段行程丢掉了刚测到的速度

`plans/README.md` 上一轮把这个胶囊列进了「判定正确、勿改」,理由是「松手用速度投影
决定停靠边」。那句话说的是**选边**,而选边确实是对的。本计划说的是**选完边之后的那
段路**——它把速度扔了:

```dart
// lib/widgets/task_capsule_monitor.dart:46-47 — 现状:算出这一甩能飞多远
  /// Where a flick would come to rest — (v/1000)·d/(1−d), d = 0.998.
  static double _project(double velocity) => velocity / 1000 * 0.998 / (1 - 0.998);
```

```dart
// lib/widgets/task_capsule_monitor.dart:134-151 — 现状:用它选边,然后丢掉
            onPanEnd: (details) {
              final v = details.velocity.pixelsPerSecond;
              final projected = Offset(
                _offset!.dx + _project(v.dx),
                _offset!.dy - _project(v.dy),
              );
              setState(() {
                _dragging = false;
                _dragOffset = null;
                final snapX = (projected.dx + capsuleWidth / 2) < screenSize.width / 2
                    ? _kEdgeInset
                    : maxX - _kEdgeInset;
                _offset = Offset(
                  v.distance < 100 ? _offset!.dx : snapX,
                  projected.dy.clamp(_kEdgeInset, maxY),
                );
              });
            },
```

```dart
// lib/widgets/task_capsule_monitor.dart:102-106 — 现状:不管怎么甩,都走 280ms 定长曲线
    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : AppMotion.sceneOf(context),
      curve: AppMotion.emphasized,
      left: _offset!.dx,
      bottom: _offset!.dy,
```

轻轻一推和狠狠一甩,飞过去的过程一模一样:`emphasized` 曲线从 0 速度起步,280ms 到位。
手上刚给出去的力道在松手的那一帧被清零了——这正是「扔出去的东西不在乎你扔得多用力」。

### 二、抓不住飞行中的胶囊

`AnimatedPositioned` 的插值不认手。飞行途中按住它,`onPanStart` 读的是 `_offset`
(**终点**),于是胶囊会瞬间跳到终点再跟手:

```dart
// lib/widgets/task_capsule_monitor.dart:114-117 — 现状
            onPanStart: (_) => setState(() {
              _dragging = true;
              _dragOffset = _offset;
            }),
```

### 三、每帧改 `left`/`bottom` 是布局,不是绘制

`AnimatedPositioned` 每帧改的是 Stack 的 parent data,于是整个飞行过程每帧都要让
`main.dart:355` 那个 Stack 重跑一次 `performLayout`。**诚实地说这笔开销是有界的**:
Stack 的另外两个孩子(整屏 `screen`、`PhoneDock`)约束没变,`RenderObject.layout` 会
提前返回,不会真的重排整屏;胶囊自己的子树同理。省下的是「每帧一次 Stack 布局 +
一路 markNeedsLayout」,换成纯重绘。量不大,但准则第 7 条说的就是这件事,而且改动与
第一、二两条是同一处代码,顺手做掉,不值得单独立项。

## Target

一条弹簧接手松手那一刻的速度;位移改由 `Transform.translate` 承担;抓取时从**当前
渲染位置**接管。

```dart
// lib/widgets/task_capsule_monitor.dart — 目标(状态字段)
class _TaskCapsuleMonitorState extends State<TaskCapsuleMonitor>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  Offset? _offset;

  /// Apple's `spring(duration:bounce:)` at the audit's recommended setting —
  /// a 0.2 bounce is a single, barely-seen overshoot of about 1.5% of the
  /// travel (6px on a 400px throw, well inside the 16px edge inset).
  ///
  /// Its 500ms is a *settling* time, not a transition duration: the capsule
  /// covers most of the distance in the first third, and unlike a 280ms curve
  /// it leaves at the speed it was thrown. The M-ladder's 300ms ceiling is a
  /// budget for transitions and does not apply.
  static final SpringDescription _kSettle =
      SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 500), bounce: 0.2);

  /// Unbounded: a spring overshoots past 1 before it settles.
  late final AnimationController _settle = AnimationController.unbounded(vsync: this);
  Offset? _settleFrom;
  Offset? _settleTo;

  /// Where the capsule actually is this frame — mid-flight, that is not
  /// [_offset], which is already the target.
  Offset get _renderOffset {
    final Offset? from = _settleFrom;
    final Offset? to = _settleTo;
    if (from == null || to == null || !_settle.isAnimating) return _offset!;
    return Offset.lerp(from, to, _settle.value)!;
  }

  /// Hands the throw to the spring: [target] is where it parks, [velocity] the
  /// gesture's own speed in logical pixels per second.
  void _settleAt(Offset target, Offset velocity) {
    final Offset from = _renderOffset;
    if (AppMotion.prefersReduced(context) || from == target) {
      setState(() {
        _offset = target;
        _settleFrom = null;
        _settleTo = null;
      });
      return;
    }
    final Offset travel = target - from;
    final double distance = travel.distance;
    // The simulation runs on t ∈ [0,1], so it wants the throw's component
    // along the travel expressed in travels per second. `dy` flips: the
    // gesture's y grows downward, [_offset]'s grows upward.
    final double v = (velocity.dx * travel.dx - velocity.dy * travel.dy) / (distance * distance);
    setState(() {
      _settleFrom = from;
      _settleTo = target;
      _offset = target;
    });
    _settle
      ..value = 0
      ..animateWith(SpringSimulation(_kSettle, 0, 1, v));
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }
```

```dart
// lib/widgets/task_capsule_monitor.dart — 目标(build 的头尾)
    final Widget capsule = IgnorePointer(
      ignoring: !visible,
      child: Listener(
        …一整棵子树原样不动…
      ),
    );

    return Positioned(
      left: 0,
      bottom: 0,
      // Paint, not layout: the capsule is laid out once and only moved.
      child: AnimatedBuilder(
        animation: _settle,
        child: capsule,
        builder: (context, child) {
          final Offset o = _renderOffset;
          return Transform.translate(offset: Offset(o.dx, -o.dy), child: child);
        },
      ),
    );
```

```dart
// lib/widgets/task_capsule_monitor.dart — 目标(两个手势回调)
            onPanStart: (_) => setState(() {
              // Grab it where it is: a capsule caught mid-flight must not jump
              // to its target under the finger.
              _offset = _renderOffset;
              _settle.stop();
              _settleFrom = null;
              _settleTo = null;
              _dragging = true;
              _dragOffset = _offset;
            }),
```

```dart
            onPanEnd: (details) {
              final v = details.velocity.pixelsPerSecond;
              final projected = Offset(
                _offset!.dx + _project(v.dx),
                _offset!.dy - _project(v.dy),
              );
              final double snapX = (projected.dx + capsuleWidth / 2) < screenSize.width / 2
                  ? _kEdgeInset
                  : maxX - _kEdgeInset;
              final Offset target = Offset(
                v.distance < 100 ? _offset!.dx : snapX,
                projected.dy.clamp(_kEdgeInset, maxY),
              );
              setState(() {
                _dragging = false;
                _dragOffset = null;
              });
              _settleAt(target, v);
            },
```

拖拽期间 `_settle` 不在跑,`_renderOffset` 直接返回 `_offset`,于是 1:1 跟手这件事
自动成立——`duration: _dragging ? Duration.zero : …` 那个补丁整行消失。

## Repo conventions to follow

- `AppMotion.prefersReduced(context)`(`lib/core/design_tokens.dart:352`)是全应用
  减弱动画的唯一入口;弹簧不是 `duration:`,走不了 `durationOf`,所以在
  `_settleAt` 开头显式判一次、直接落位。
- 已有的同类样板:`lib/widgets/drag/app_drop_zone.dart:227` 就是「手写
  `AnimationController` + 在 `didUpdateWidget` 里读 `prefersReduced`」的写法。
- 常量命名沿用本文件的 `_kEdgeInset` / `_kDragSlack` 风格,故用 `_kSettle`。
- **必须新增一行 import**:`SpringDescription` / `SpringSimulation` 在
  `package:flutter/physics.dart`,`material.dart` 不导出它。加在第 1 行
  `import 'package:flutter/material.dart';` 之下。

## Steps

1. `lib/widgets/task_capsule_monitor.dart` 第 2 行前后加
   `import 'package:flutter/physics.dart';`(与既有 import 分组保持一致:先 flutter,
   再 package,再相对路径)。
2. 第 30 行 `class _TaskCapsuleMonitorState extends State<TaskCapsuleMonitor> {` 改为
   `class _TaskCapsuleMonitorState extends State<TaskCapsuleMonitor>\n    with SingleTickerProviderStateMixin {`。
3. 在第 32 行 `Offset? _offset;` 之后,按 Target 节插入 `_kSettle`、`_settle`、
   `_settleFrom`、`_settleTo`、`_renderOffset`、`_settleAt`、`dispose`。
   `_kDragSlack` / `_dragOffset` / `_dragging` / `_pressed` / `_kEdgeInset` /
   `_collapsedWidth` / `_expandedWidth` / `_project` / `_initPosition` 全部保留原位。
4. 第 102-107 行:把
   ```dart
    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : AppMotion.sceneOf(context),
      curve: AppMotion.emphasized,
      left: _offset!.dx,
      bottom: _offset!.dy,
      child: IgnorePointer(
   ```
   改成
   ```dart
    final Widget capsule = IgnorePointer(
   ```
   并把这一行的缩进以及**其后整棵子树**的缩进减少 2 个空格(原来多了一层
   `AnimatedPositioned`)。
5. 文件末尾:原第 312-316 行是子树与 `AnimatedPositioned` 的收尾。删掉最外层那一对
   `      ),\n    );`,把 `capsule` 的声明用 `;` 收掉,然后按 Target 节写
   `return Positioned(… AnimatedBuilder …);`。改完 `build` 必须仍以
   `  }\n}` 结束。
6. 第 114-117 行 `onPanStart` 按 Target 节改写。
7. 第 134-151 行 `onPanEnd` 按 Target 节改写(注意:`snapX` / `target` 的计算移出了
   `setState`,`setState` 里只剩两个 drag 标志)。
8. `test/task_capsule_bounds_test.dart`:测量口径必须下移一层。改完后
   `find.byType(TaskCapsuleMonitor)` 的第一个 RenderBox 是 `RenderTransform`,
   而 `RenderTransform` **自己**的全局坐标不含它施加给孩子的位移——用它
   `getRect`/`tap` 会量错、点空。在该文件顶部加
   `import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass.dart';`,
   并加一个取代 `find.byType(TaskCapsuleMonitor)` 的 finder:
   ```dart
   /// The capsule's painted box. Not `find.byType(TaskCapsuleMonitor)`: that
   /// resolves to the `Transform` that moves it, whose own box does not carry
   /// the translation it applies to its child.
   final Finder capsuleBody = find.descendant(
     of: find.byType(TaskCapsuleMonitor),
     matching: find.byType(AppGlass),
   );
   ```
   把两个 test 里的 `tester.getRect(capsule)` 与 `tester.tap(capsule)` 全部换成
   `capsuleBody`;`expect(capsule, findsOneWidget)` 保留(它验证的是组件挂载),
   另加 `expect(capsuleBody, findsOneWidget)`。断言本身一个都不改。
9. `flutter analyze`。

## Boundaries

- **胶囊的内容一行都不要改。** 玻璃、呼吸点、进度条、展开的任务行、`_isExpanded` 的
  宽度/圆角切换、`AnimatedSize` / `AnimatedSlide` / `AnimatedOpacity` / `AnimatedContainer`
  那四处(第 157-198 行)全部原样保留——其中 `AnimatedSize` 的档位问题是**另一条
  发现**,不在本计划内,不要顺手改。
- 不要改 `_project`、`_initPosition`、`_kEdgeInset`、`_kDragSlack`,也不要改
  `v.distance < 100` 这条「慢速松手保持 x 不变」的规则、`snapX` 的选边逻辑、
  `projected.dy.clamp(...)` 的夹取。**停哪儿完全不变,只改怎么过去。**
- 不要给弹簧加「拖拽中也用弹簧跟手」之类的东西:拖拽必须保持 1:1。
- 不要动 `lib/main.dart:355` 的挂载方式。
- 不要改 `test/task_capsule_bounds_test.dart` 里的任何 `expect` 数值或 `reason`。
- 不要新增依赖(`package:flutter/physics.dart` 是 SDK 自带)。
- 若第 102-106 行、114-117 行或 134-151 行与上文引用的不符,**停下来报告**。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `flutter test test/task_capsule_bounds_test.dart` → 两个 test 都绿。
    注意:第一个 test 里 `expect(opened.height, greaterThan(collapsed.height))`
    正是「点空了没有」的哨兵——若 finder 没改对,它会**响亮地红**,不会静默放过。
  - `flutter test` → 全量通过
  - `flutter test test/screenshots` → 通过且无新增溢出(胶囊在多张截图里出现,
    静止渲染不应有任何变化)
  - `grep -n "AnimatedPositioned" lib/widgets/task_capsule_monitor.dart` → 无输出
- **Feel check**:`flutter run --release`,在「提示词」或「浏览器」屏(胶囊在工作台
  和任务屏是隐藏的)下派一批任务让胶囊出现:
  - **轻推**一下松手:胶囊慢慢滑到边;**狠甩**一下松手:它应该明显更快地冲过去,
    到边时几乎不减速再停住。两者的差别是本计划的全部意义——修复前这两下一模一样。
  - 甩出去之后**立刻按住它**:应该在它当时所在的位置被接住,不能瞬移到边上再跟手。
  - 贴边停住时盯住边缘:允许约 1.5% 行程的一次极轻微过冲再回落;若看到明显的弹跳
    或来回振荡,说明 `bounce` 写错了。
  - 拖着它绕窗口走一圈:必须仍然严丝合缝跟手,没有任何滞后(`_settle` 此时不该在跑)。
  - 打开系统「减少动态效果」后重启:松手应**瞬间**到位,没有任何飞行过程。
  - 展开/收起(点一下)不受本计划影响,应与修复前一致。
- **Done when**:甩的力道能看出快慢差别;飞行中能被接住且不跳;
  `grep AnimatedPositioned` 无输出;全量测试与截图测试通过。
