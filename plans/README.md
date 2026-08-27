# 动画改进计划

由 improve-animations 审计产出。首轮 001–005 基于 commit `b2d4b9c`(2026-08-22),
第二轮 006–010 基于 commit `07906de`(2026-08-27,v3.24.0)。审计范围:`lib/` 全部动画
与动效代码,八类标准(目的/频率、缓动/时长、物理性、可中断性、性能、无障碍、一致性、
错失机会)。每份计划自包含,可交给任何执行代理(含低成本模型)独立完成。

## 计划一览

| # | 标题 | 严重度 | 状态 |
|---|---|---|---|
| [001](001-remove-workbench-tab-dead-animation.md) | 移除工作台模式切换的 300ms 死区动画 | HIGH | DONE |
| [002](002-app-motion-tokens.md) | 建立 AppMotion 动效令牌,消灭 19 处 linear 默认曲线 | HIGH | DONE |
| [003](003-media-preview-keyboard-paging.md) | 媒体预览:键盘翻页去动画,远跳不再刷屏 | HIGH | DONE |
| [004](004-half-animated-disclosures.md) | 修复「半动画」展开控件(胶囊/提示词卡/下载器日志) | MEDIUM | DONE |
| [005](005-video-overlay-interruptible.md) | 视频播放覆盖层改为可中断的常驻淡入淡出 | MEDIUM | DONE |
| [006](006-remove-top-level-nav-crossfade.md) | 移除顶层导航的整屏交叉淡入(Ctrl+1..8 也走它) | HIGH | DONE |
| [007](007-channel-row-hover-scope.md) | 渠道行悬停:状态从整屏下沉到行内 | HIGH | DONE |
| [008](008-smooth-task-progress.md) | 进度条:把 2Hz 的阶跃换成连续推进 | MEDIUM | DONE |
| [009](009-snackbar-instant-replace.md) | Snackbar 连发不再「退场再进场」地闪 | MEDIUM | DONE |
| [010](010-model-dialog-token-drift.md) | 收回模型编辑对话框最后一处令牌漂移 | LOW | DONE |

> 001–005 已于 2026-08-22 全部执行完毕。`flutter analyze` 零问题,
> `flutter test test/screenshots` 87 个测试通过、无新增溢出。
>
> 006–010 已于 2026-08-27 全部执行完毕。`flutter analyze` 零问题,
> `flutter test` 1130 个测试通过、无新增溢出;改动仅落在 7 个 `lib/` 文件、
> 1 个新建组件与 1 个测试文件上。

## 执行时相对计划的两处偏离

1. **008 的新文件注释改用英文。** 计划的 Target 节把
   `lib/widgets/smooth_progress.dart` 的文档注释写成了中文,但 `lib/` 下没有一个文件
   是中文注释的。语言随文件走,内容与计划一致。
2. **009 的第 2 步(收紧既有测试)行不通,改为新增一个测试。** 既有测试的两次
   `AppSnackBar` 调用发生在**同一个回调里、任何一帧之前**,此时第一条 toast 的进场
   动画还停在 0,`hide` 与 `remove` 都是瞬间完成——把 `pumpAndSettle` 换成定量 pump
   之后它依然是绿的(已实测)。于是保留原测试(它覆盖的是"不排队"这个契约),另加
   `replacing a toast already on screen swaps it, it does not play an exit`:先让第一条
   完全进场,再触发第二条。该测试在 `hide` 下红、在 `remove` 下绿,两个方向都已验证。
   相应地,009 的 "Done when" 里那条
   `grep hideCurrentSnackBar → 无输出` 与它自己的 Boundaries 冲突——
   `app_snackbar.dart:21` 的类文档引用的是重构**之前**各调用点的写法,是史料,按
   Boundaries 保留了。判定标准应为"调用处不再是 `hide`"。

## 推荐执行顺序与依赖

**没有硬依赖,五份可任意顺序、甚至并行执行——它们不共享任何文件。** 按收益排:

1. **006**(1 个文件删 12 行,收益最大:全应用最高频动作)
2. **007**(1 个文件,新增一个私有 widget;修的是「模型」屏最贵的一次重建)
3. **008**(新建 1 个共享组件 + 6 个调用点;覆盖面最广)
4. **009**(1 行 + 1 个收紧的测试)
5. **010**(2 行)

文件冲突提示:007 与 010 都在「模型」相关代码里,但分属
`lib/screens/models/models_screen.dart` 与 `lib/widgets/models/model_edit_dialog.dart`,
互不重叠。008 触及 `task_capsule_monitor.dart` / `app_run_console.dart` /
`task_queue_screen.dart`,与其余四份均无交集。

## 上一轮遗留项的现状(2026-08-27 复核)

- ~~**无障碍缺口**:全库无 `MediaQuery.disableAnimations` 处理~~ → **已解决**。
  `AppMotion.prefersReduced` / `AppMotion.durationOf`
  (`lib/core/design_tokens.dart:429-457`)已成为全应用入口,并有
  `test/reduced_motion_test.dart` 钉住契约。剩两处漏网正由 007 与 010 收尾。
- ~~**孤儿 Hero**~~ → **已解决**。灯箱改成透明 `PageRoute`,缩略图与预览页配对飞行
  (`image_card.dart:315`、`file_card.dart:74`、`media_preview_dialog.dart:202`,
  含 `flightShuttleBuilder`)。这是本轮审计里做得最好的一处动效。
- ~~**控制台展开硬跳**~~ → **已解决**。`app_run_console.dart:214-220` 用了 `AnimatedSize`,
  并在拖拽期间把 duration 归零,让高度 1:1 跟手。
- **Snackbar 替换闪烁** → 立项为 **009**。

## 已审计、暂未立项的发现(按价值排序)

- **加载→网格硬切**:`lib/screens/workbench/gallery.dart:158-160` 扫描 spinner 在一帧内
  换成满屏图块。仍是全应用视觉上最猛的一次跳变,一段 `AppMotion.reveal` 的淡入即可消解。
  (上一轮就在这张单子上,至今未做——下一轮若无新的 HIGH,它应当优先立项。)
- **目录树 / 知识库树的展开是硬跳**:`lib/screens/workbench/directory_tree_item.dart:291`
  直接 `if (_isExpanded) ...` 插入子树,箭头则在 `:259` 用 `expand_less`/`expand_more`
  两个图标互换而非旋转;`lib/screens/workbench/widgets/knowledge_tree_panel.dart:376`
  同样是 `keyboard_arrow_down`/`keyboard_arrow_right` 互换。004 修的正是这类「半动画
  展开」,这两处是同一类里的漏网。箭头旋转(`AnimatedRotation` + `AppMotion.state`)是
  两处都能低成本拿下的部分;子树伸缩只有目录树能用 `AnimatedSize`,知识库树是扁平化过滤
  列表,要动就得换 `AnimatedList`,不划算。
- **ScrollEdgeFade 的边缘渐变 0/1 硬切**:`lib/widgets/scroll_edge_fade.dart:57-66` 用两个
  bool 决定渐变端点是白还是透明,于是滚动离开顶端的第一个像素就让 24px 渐变**满强度
  弹出**。用 `TweenAnimationBuilder<double>` 配 `AppMotion.hover` 把这两个 bool 补间成
  0..1,可以在不引入逐帧 setState 的前提下消掉这个 pop。
- **渠道向导步骤切换无方向感**:`channel_wizard_dialog.dart:1213` 纯淡入淡出,后退与
  前进看起来一样。现在只剩两步且有步点指示位置,优先级比上一轮更低。
- **用量比例条不生长**:`usage_summary.dart:288`、`usage_group_costs.dart:118` 的占比条
  首帧即到位。一次 `0 → 值` 的 `AppMotion.panel` 生长是标准的「稀有场景可以用愉悦预算」
  的位置。注意这两处有测试直接读取其 widget(见 008 的 Boundaries)。
- **性能(非动效本身)**:工作台分栏拖拽(`workbench_layout.dart`、`app_run_console.dart:188`)
  每个指针事件全行重布局;标题栏毛玻璃在任务运行期间随脉冲动画全程重绘。二者是架构级
  取舍,不属于动效修缮。

## 审计中判定「正确、勿改」的动画

- **Hero 灯箱**(`media_preview_dialog.dart:202`,`flightShuttleBuilder` 始终取网格侧
  缩略图,未配对的 tag 退化为路由淡入)——本应用最值得花愉悦预算的地方,花对了。
- **任务胶囊**(`task_capsule_monitor.dart:117-180`):拖拽时 duration 归零做到 1:1 跟手,
  松手用速度投影决定停靠边,按压 0.97 反馈——审计准则第 4 条的教科书实现。
- **对话框 materialize**(`app_dialog.dart:394-412`):0.96 起手、骑路由自身 animation
  所以出场自动反向、减弱动画时降为纯淡入。
- **呼吸圆点**(`app_run_console.dart:378-425`):生命周期正确,`stop` 而非 `reset`,
  减弱动画时直接停表。
- **滚动橡皮筋**(`main.dart:153-171`):`BouncingScrollPhysics` 覆盖全平台是 `7091ca5`
  记录在案的刻意取舍(「只在用户自己的手势下发生」),按规矩不再翻案。
- **主导航项的 160ms 底色过渡**(`main.dart:707`)、`app_side_panel` 抽屉滑入、
  `app_text_field` 焦点环(零布局位移)、`panel_resizer` 拖拽 1:1 跟手、
  `image_card` 悬停操作条不加动画(全应用最高频交互)、窗框按钮 90ms(贴合 Windows
  原生节奏)、`models_screen.dart:527` 拖拽代理手动采样 `ReorderableListView` 自己的
  animation。
