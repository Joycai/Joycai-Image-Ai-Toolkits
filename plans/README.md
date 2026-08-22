# 动画改进计划

由 improve-animations 审计产出(commit `b2d4b9c`,2026-08-22)。审计范围:`lib/` 全部
动画与动效代码,八类标准(目的/频率、缓动/时长、物理性、可中断性、性能、无障碍、
一致性、错失机会)。每份计划自包含,可交给任何执行代理(含低成本模型)独立完成。

## 计划一览

| # | 标题 | 严重度 | 状态 |
|---|---|---|---|
| [001](001-remove-workbench-tab-dead-animation.md) | 移除工作台模式切换的 300ms 死区动画 | HIGH | DONE |
| [002](002-app-motion-tokens.md) | 建立 AppMotion 动效令牌,消灭 19 处 linear 默认曲线 | HIGH | DONE |
| [003](003-media-preview-keyboard-paging.md) | 媒体预览:键盘翻页去动画,远跳不再刷屏 | HIGH | DONE |
| [004](004-half-animated-disclosures.md) | 修复"半动画"展开控件(胶囊/提示词卡/下载器日志) | MEDIUM | DONE |
| [005](005-video-overlay-interruptible.md) | 视频播放覆盖层改为可中断的常驻淡入淡出 | MEDIUM | DONE |

> 全部 5 份于 2026-08-22 执行完毕(commit `b2d4b9c` 之上的工作区改动,未提交)。每份的
> diff 均经主导代理逐行/抽查审查,`flutter analyze` 零问题,`flutter test test/screenshots`
> 87 个测试通过、无新增溢出。剩余人工感受验证项见各计划的 Verification 节。

## 推荐执行顺序与依赖

1. **001**(独立,10 分钟量级,收益最大)
2. **002**(独立;建立令牌后,003/004/005 可引用令牌)
3. **003 / 004 / 005**(相互独立,可并行;每份计划内都写明了"002 已落地用令牌、
   未落地用等价字面值"的双轨写法,故顺序不是硬依赖)

文件冲突提示:002 与 004 都触及 `prompt_card.dart`(002 改 :103 箭头的 curve,004 改
:70-71 的内容区结构),先后执行均可,但不要并行改同一文件。002 明确把
`task_capsule_monitor.dart`、`image_downloader_screen.dart`、`media_preview_dialog.dart`、
`video_workbench_view.dart:240` 划给了 003/004/005,不会重叠。

## 已审计、暂未立项的发现(按价值排序)

- **无障碍缺口**:全库无任何 `MediaQuery.disableAnimations` 处理;应用自己的
  "减少视觉效果"开关(PR #129)目前只关标题栏毛玻璃、不管任何动效。合理方向:002 的
  AppMotion 增加一个 `of(context)` 形态,在 OS 减弱动画或应用开关开启时把移动类动画
  降为纯淡入。规模不小,值得单独立项。
- **Snackbar 替换闪烁**:`lib/widgets/app_snackbar.dart:86` 用 `hideCurrentSnackBar()`
  (播放完整退场)再进场;批量失败连发时改 `removeCurrentSnackBar()` 即时换内容。一行改动。
- **孤儿 Hero**:`lib/screens/workbench/widgets/preview/image_preview_handler.dart:19`
  是全库唯一的 `Hero`,没有配对端,从不飞行。要么删除,要么在 `image_card.dart` 补配对
  做成真正的共享元素过渡(后者是全应用最值得花"愉悦预算"的地方)。
- **渠道向导步骤切换无方向感**:`channel_wizard_dialog.dart:990` 纯淡入淡出,后退与
  前进看起来一样;可加 ±0.05 横向偏移的方向线索。
- **控制台展开硬跳**:`app_run_console.dart:183-188` 点状态栏瞬间插入最高 600px;
  可仿 004 的 AnimatedSize 方案。
- **性能(非动效本身)**:工作台分栏拖拽(`workbench_layout.dart:223`、
  `app_run_console.dart:166`)每个指针事件全行重布局(含图片网格);标题栏毛玻璃
  (自测 4K iGPU 约 19ms/帧)在任何任务运行期间随脉冲动画全程重绘。二者是架构级
  取舍,不属于动效修缮。
- **加载→网格硬切**:`lib/screens/workbench/gallery.dart:159` 扫描 spinner 一帧内换成
  满屏图块;一段 150ms 淡入可消解全应用视觉上最猛的一次跳变。

## 审计中判定"正确、勿改"的动画

`app_side_panel` 的抽屉滑入(300ms easeOutCubic,从所在边缘进入)、`app_run_console`
的呼吸圆点(生命周期正确、stop 不 reset)、`browser_selection_bar` 的结构(双腿参数在
002 统一)、`app_text_field` 焦点环(零布局位移)、主导航硬切换(`main.dart:355`,
高频操作不加动画是对的)、`panel_resizer` 拖拽 1:1 跟手、`image_card` 悬停操作条不加
动画(全应用最高频交互)、窗框按钮 90ms(贴合 Windows 原生节奏)。
