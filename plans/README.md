# 动效审计台账

由 improve-animations 审计产出。截至 2026-09-12，**三轮 14 份计划全部执行完毕并已合入
`main`**，计划正文（`001`–`014`）已删除——它们是一次性的施工说明书，落地之后真正的记录在
代码、测试和提交信息里。需要回看时在 git 历史里取：

```bash
git show 46d5a72:plans/                                    # 14 份在这个 commit 上是齐的
git show 46d5a72:plans/012-task-capsule-spring-settle.md
```

留在这份文件里的，是**不随代码走的那部分**：已修过什么（免得下一轮重复上报）、还欠什么、
哪些动效是刻意为之不要动、以及做动效测试时踩过的坑。

> **下一轮从 `015` 开始编号。** 目录空了不等于可以从 001 重新开始，那会和下面这张表撞号。

## 已修（不要重复上报）

| 轮次 | 基线 commit | 落地 commit | 修了什么 |
|---|---|---|---|
| 一（001–005） | `b2d4b9c` 2026-08-22 | `93919c9` | 工作台模式切换的死区动画、**AppMotion 令牌体系**（消灭 19 处 linear 默认曲线）、媒体预览键盘翻页去动画、半动画展开控件、视频覆盖层改可中断淡入淡出 |
| 二（006–010） | `07906de` 2026-08-27 v3.24.0 | `81e3cf2` | 顶层导航整屏交叉淡入（Ctrl+1..8 也走它）、渠道行悬停从整屏下沉到行内、进度条 2Hz 阶跃改连续推进、Snackbar 连发不再退场再进场、模型编辑对话框的令牌漂移 |
| 三（011–014） | `0b97136` 2026-09-12 v4.0.0 | `e3e4845` `6191279` `69e075b` | 玻璃菜单从触发它的角长出、任务胶囊弹簧归位（位移改走 transform）、对话框拿回 M 档时钟与回程曲线、侧边面板退场不再是入场倒放 |
| 四（无编号，欠账清扫 2026-09-16 v4.9.0，片 8–14 + R2） | `4a23e37` | 分支 `claude/debt-sweep-4.9` | 「还欠的」七条全部做完：网格接替占位时淡入（`gallery.dart`，只在占位 → 网格时，常驻不重播）；两棵树的箭头改旋转（新原语 `AppDisclosureChevron`；知识库树行按路径 key，否则箭头会转到没点的文件夹上）；`ScrollEdgeFade` 两端强度 M1 补间（顺带：子组件 GlobalKey 跨有无遮罩两种结构，列表开始溢出时不再重建）；胶囊内容区高度：点开 / 收起 M3（与宽度同步，计时器保持整段），运行数跨 0 降到 M2；选择栏滑动与淡出同一时钟（`AppMotion.sceneFor`）；渠道向导步骤带方向（每次切换一个序号、按序号记方向，快速前进又后退也不串）；用量比例条 0 → 值生长（`UsageShareGrow`，换区间时从旧值滑到新值）。每条都有测试 |

三轮合计触及约 30 个 `lib/` 文件；每轮结束时 `flutter analyze` 零问题，`flutter test` 全绿
（第三轮 1763 个测试），截图无新增溢出。

## 还欠的（2026-09-16 欠账清扫之后）

四轮之后动效本身没有欠账了。剩下的一条不是动效：

- **性能（非动效本身）**：工作台分栏拖拽每个指针事件全行重布局；标题栏毛玻璃在任务运行期间
  随脉冲动画全程重绘。二者是架构级取舍，不属于动效修缮。
- 下一轮若立项，编号仍从 `015` 开始（第四轮是欠账清扫的一部分，没有单独编号）。

## 判定「正确、勿改」的动效

- **Hero 灯箱**（`lib/screens/workbench/widgets/preview/media_preview_dialog.dart`，
  `flightShuttleBuilder` 始终取网格侧缩略图，未配对的 tag 退化为路由淡入）——本应用最值得花
  愉悦预算的地方，花对了。
- **任务胶囊的选边**（`task_capsule_monitor.dart`，`_project()` 用速度投影决定停靠边、按压 0.97
  反馈）。第三轮的 012 细化了它**选完边之后**的那段行程（原先定长 280ms 曲线把速度丢了），
  选边本身这条结论不变。
- **对话框 materialize 的机制**（`lib/widgets/ui/app_dialog.dart`：0.96 起手、骑路由自身 animation
  所以出场自动反向、减弱动画时降为纯淡入）。第三轮的 013 换掉的是它骑的那口钟，不是机制。
- **呼吸圆点**（`lib/widgets/ui/app_breathing_dot.dart`）：生命周期正确，`stop` 而非 `reset`，
  减弱动画时直接停表。
- **滚动橡皮筋**（`lib/main.dart:167`）：`BouncingScrollPhysics` 覆盖全平台是 `7091ca5` 记录在案的
  刻意取舍（「只在用户自己的手势下发生」），按规矩不再翻案。
- **对话框退场仍与入场等长**：`DialogRoute` 不接受 `AnimationStyle.reverseDuration`（已核对
  SDK），要缩短就得自抄一份 `showDialog`。这个限制写在 `appDialogAnimation` 的文档注释里，
  不要「顺手」修。
- 另：主导航项的底色过渡、`app_side_panel` 抽屉滑入、`app_text_field` 焦点环（零布局位移）、
  `panel_resizer` 拖拽 1:1 跟手、`image_card` 悬停操作条**不加**动画（全应用最高频交互）、
  窗框按钮 90ms（贴合 Windows 原生节奏）、`models_screen.dart` 拖拽代理手动采样
  `ReorderableListView` 自己的 animation。

## 无障碍契约

`AppMotion.prefersReduced` / `AppMotion.durationOf`（`lib/core/design_tokens.dart:352-362`）是全
应用唯一入口，`test/reduced_motion_test.dart` 钉住契约——包括侧边面板那条**刻意的例外**
（减弱动画时不归零，改为淡入，因为 450px 的面板在两帧之间出现读起来像换了屏）。新增任何
`duration:` 都要走令牌，不要直接写毫秒数。

## 做动效测试时踩过的坑

- **`TestGesture.moveBy` 的 `timeStamp` 默认是 `Duration.zero`。** 五个样本在 `VelocityTracker`
  眼里是同一瞬间发生的，估出来的速度恒为 0，和中间 pump 了多久无关。`startGesture` 则根本
  没有 `timeStamp` 参数。
- **`AnimationController` 的第一帧只用来对表**、不产生位移，所以 `up()` 之后必须先 `pump()`
  一次再采样。
- **`tester.fling` 在短行程上测不出速度差**：高速档 200px 只用两帧走完，样本不够，估出来的
  速度反而更小。
- **变异验证是必须的，不是可选的。** 胶囊甩动速度的第二版测试数值很漂亮（慢 7px / 快 162px），
  但把 `SpringSimulation` 的初速强行置 0 之后它**依然是绿的**——两次拖拽的松手位置不同，
  差异其实来自剩余行程而非速度。这是「绿得毫无意义」的典型。
  **结论：胶囊松手速度是否真的接上了，目前只由 012 的 feel check 保证，没有测试。** 下次再做
  从「手写 `TestGesture` 走完全相同的五个点、只改时间间隔」这一版继续，别从头试。
- **路由级过渡要用 `find.ancestor` 而不是 `find.descendant`。** `ScaleTransition` /
  `SlideTransition` 由路由的 `buildTransitions` 生成，是被测 widget 的**祖先**。
- **同一个 testWidgets 里第二次 `pumpWidget` 会保留 Navigator**：上一个面板还开着，finder 会
  命中它的路由。两次断言之间要 pop 掉并断言 `findsNothing`。
- **`AppSidePanel.show` 先判 `Responsive.isNarrow`**：默认 800×600 的测试窗口在 1000px 断点
  以下，不放大视口的话测到的是 `showModalBottomSheet` 的 250ms。
