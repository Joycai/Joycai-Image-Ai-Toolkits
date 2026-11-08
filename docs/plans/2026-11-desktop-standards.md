# Flutter 与桌面平台体验修复计划

创建：2026-11-08。状态：DESK-01、DESK-02 已开始实现，完整原生验收尚未完成；其他阶段待实施。
审查基线：`4ab5bd4a`，应用 4.31.8。PR #409 从计划扩展为 DESK-01 和 DESK-02 的分批实现。

## 目标与边界

让用户能通过读屏、键盘、系统菜单及标准窗口操作完成图片浏览和生成工作流，
同时保留现有暖石灰表面、配对强调色、控制层玻璃及响应式布局。
Flutter 工程分层整体合理；本轮不更换状态管理框架，不重做视觉系统。

按仓库 `joycai-ui-design`、[UI 工作流](../architecture/ui-design-workflow.md)、
[设计令牌](../architecture/design-tokens.md)及[快捷键约定](../architecture/keyboard-shortcuts.md)
执行。已记录的全平台弹性滚动、动画例外继续遵守[动效台账](../../plans/README.md)。
原始设计稿不可用，设计依据是维护中的规格、组件及实际 Flutter 渲染。

与 [Windows Store 计划](2026-11-windows-store.md)共用原生验收证据，不替代其安装、
WACK、发布身份或安全验收。该计划通过不代表商店发布就绪，也不授权合并或发布。

## 已发现的问题与证据边界

| 编号 | 优先级 | 发现与入口 | 证据性质 |
|---|---|---|---|
| DESK-01 | 高 | `lib/main.dart` 的 Windows `ExcludeSemantics`；`windows/runner/flutter_window.cpp` 两处拦截 `WM_GETOBJECT` | 源码确认全局禁用；现用 SDK 是否仍有原始崩溃待复现 |
| DESK-02 | 高 | `lib/widgets/ui/focus_pane.dart` 的 `skipTraversal`；工作台图片卡和浏览器网格缺少完整方向键导航 | 源码确认；既有快捷键台账已登记，不重复建设另一套导航 |
| DESK-03 | 中 | `macos/Runner/Base.lproj/MainMenu.xib` 的 Preferences 无 action，应用命令未完整接入原生菜单 | 源码确认；菜单实际状态和快捷键冲突待 macOS 验证 |
| DESK-04 | 中 | `lib/widgets/shell/app_window_frame.dart` 自绘最大化按钮没有配套 `HTMAXBUTTON` 命中测试 | 已检查 runner 和当前 window_manager 插件；Snap 悬停缺失为源码推断，非原生实测 |
| DESK-05 | 中 | `MaterialApp` 未配置高对比度主题，未发现系统高对比度适配 | 配置缺口已确认；实际系统信号、颜色和可读性待验证 |
| DESK-06 | 后续 | `lib/state/app_state.dart` 根状态为全局单例，部分界面直接发起有副作用服务调用 | 维护性改进；不作为前五项修复的前置条件 |

审查时 `flutter analyze` 无问题；架构、core、ui 和 shell 定向测试 494 项通过；
工作台截图测试 23 项通过，日志未发现 overflow/exception。目视检查了 390/834/1024/1440
浅色及 1440 深色工作台。以上不是全量测试、全屏幕检查或 macOS/Windows 原生验收；
后续实现不能复用这些数字作为变更后的通过证据。

## 分阶段实施与验收

### DESK-01 恢复 Windows 无障碍桥接

首批实现与证据见 [Windows 无障碍验证记录](../windows-accessibility-validation.md)。
已移除 Dart 全局语义屏蔽及 runner 两处拦截，并隔离 Navigator 的语义边界，防止
路由屏障把标题栏导航一起隐藏。原生复现确认 MenuAnchor 内嵌 tooltip 仍会损坏 AXTree；
通过 `AppMenuAnchor` 局部语义边界修复并迁移 14 个调用点，保留 tooltip 和菜单语义。
后续批次补齐 `AppSegmentedControl` 的名称、按钮角色、选中/禁用状态与选中项焦点，
并消除标题栏导航的重复 tooltip 名称；任务页的排序和提交模式控件由此受益。
独立的任务状态胶囊、其他自绘控件及完整 Narrator 流程仍待审计。
该改动尚不能视为本阶段完成或允许发布：上游问题仍开放，
需要在 CI 固定的 SDK 上补原生验收，并完成 Narrator 的真实应用工作流检查。

先建立最小原生复现：读屏启用时反复打开/关闭 dropdown、tooltip、dialog，调整窗口大小，
切换屏幕和主题，覆盖原注释提到的 overlay 退场和 AXTree 更新。记录实际 SDK、Windows
版本及崩溃日志，重新核对 flutter/flutter#182444、#100610 的适用范围与修复状态。

- 在隔离开发分支同时恢复 Dart semantics 与 runner 两层 `WM_GETOBJECT` 处理，不能只改一层。
- 优先采用已验证的引擎修复或局部生命周期修复。若需要升级 SDK，单独提交并同步 CI。
- 原问题仍可复现时保留明确未完成状态，记录最小复现及后续方案；不把全局关闭读屏当成验收通过。
- 为主要控件补齐名称、角色、值、选中/禁用状态，避免重复朗读；Dart 测试验证语义行为。

验收：Windows Release 实际运行时 Narrator 能识别并操作导航、输入、菜单、对话框和任务；
上述压力场景不崩溃；窗口和 Flutter 内容都能通过原生无障碍检查工具读取。
单元测试不能替代这一原生验收。完成后删除过期的全局规避注释并记录 SDK 证据。

### DESK-02 图片网格键盘导航与焦点

首批已实现工作台画廊的单一 Tab 入口、逻辑活动项、方向键/扩选/保留选区移动/Space、
Enter 打开活动项、分组几何滚动及删除/排序/换列后的身份维护。已解除画廊局部语义排除，
四语言快捷键说明随注册表提供。图片选区仍用于模型参考输入，因此视频只参与焦点和预览。
验证记录见 [画廊键盘验证](../gallery-keyboard-validation.md)。浏览器网格/列表接入、跨栏流程、
视频原生播放和 Narrator/VoiceOver 验收仍待完成，本阶段保持未勾选。

可先开发，与 DESK-01 在 Windows 读屏验收时汇合。覆盖工作台图片/视频画廊、浏览器网格及
与树、暂存栏、工具栏之间的焦点转移，沿用 L0/L1/L2 与 `AppShortcuts` 单一注册表。

- 定义当前可见排序为导航顺序；左右按项，上下按当前列数；跨分组跳过标题，边界不绕回。
- Tab 进入/离开一个网格区域，方向键移动逻辑活动项，不让每张卡占一个 Tab 停靠点。
- 将逻辑焦点与选区分开；普通方向键单选，Shift 扩选，平台主修饰键移动保留选区，Space
  切换活动项选择；Enter 打开，Escape 保持既有层级语义。实现前核查这些绑定与文本编辑无冲突。
- 活动项滚入可视区；删除、过滤、排序、刷新、分组折叠、列数改变后保留稳定身份或回落至邻项。
- 空网格可进入且有空状态说明；加载/错误/禁用状态不留下失效焦点；关闭菜单和预览后恢复来源。
- 使用现有令牌绘制焦点，并提供项目名称、位置及选中状态语义。复用 pane 节点或虚拟焦点，
  不给所有离屏项目长期分配节点。文本输入保护与现有 Delete/F2 作用域必须保持。

验收：无需鼠标即可从导航进入网格，定位并扩选、打开、删除项目后继续操作；在 Windows
与 macOS 分别检查 Narrator/VoiceOver。测试跨组、过滤后焦点、空列表、响应式换列及大列表
滚动；渲染浅/深色焦点和非活动选区，确认屏幕级快捷键无回归。更新快捷键架构与已有欠账。

### DESK-03 macOS 原生菜单接入

先盘点 App/Edit/View/Window/Help 菜单与现有动作，建立菜单项→动作→启用条件→快捷键映射。
优先使用 Flutter `PlatformMenuBar`；确需 Swift 桥接时只承担平台动作，业务留在 state/service。

- 将 Settings…/⌘, 接入现有设置导航；About 与应用信息一致，应用内主要命令可从菜单发现。
- 系统管理的 Quit、Hide、Services、窗口命令保留原生行为；编辑命令服从当前文本输入焦点。
- 原生菜单与现有 HardwareKeyboard handler 不能重复执行同一动作；选择相关操作只作用于活动区域。
- 模态对话框、无选区、忙碌和不可用屏幕时正确禁用对应菜单项，不提供无作用的命令。
- 用户可见文本通过 `joycai-l10n` 更新 en/zh/zh_Hant/ja；菜单与应用语言同步。

验收：在 macOS 原生 Release 中逐项点击并使用快捷键，特别检查文本框中的复制/撤销、
⌘,、⌘Q、菜单禁用态、对话框焦点与四语言。真实菜单截图及操作记录必需；Flutter PNG 不算证据。

### DESK-04 Windows 标题栏与 Snap

先在当前二进制复现最大化按钮悬停、Win+Z、拖动吸附、双击最大化和多显示器行为。
评估保留现有外观并接入原生命中测试，或保留系统 caption buttons，记录选择理由。

- 若继续自绘，将实际最大化按钮区域转换为正确的窗口坐标，处理 `WM_NCHITTEST` 的
  `HTMAXBUTTON` 和对应非客户区鼠标消息，避免悬停可用但点击失效或执行两次。
- 覆盖 100%/150%/200% DPI、跨显示器、最大化/还原、窄窗口和全屏；导航与拖动区域不重叠。
- 验证 Alt+Space、Alt+F4、拖动、边缘缩放及标题栏右键菜单，修复本轮自绘 chrome 导致的缺失。
- 保留 macOS traffic lights 和移动平台行为；窗口平台逻辑不混入业务状态。

验收：Windows 11 悬停最大化按钮显示 Snap 布局，点击布局与普通最大化/还原均正常；
Windows 10 基础窗口操作无回归。记录 OS/DPI/显示器组合与实际操作结果，不以代码搜索替代验收。

### DESK-05 系统高对比度与可读性

先实测 Flutter 在 Windows 对比度主题与 macOS Increase Contrast 下收到的信号；不足时
在 system 服务与原生适配层补最小桥接，涵盖启动读取和运行中切换，不假定跨平台信号相同。

- 为主题构建提供独立高对比度策略并接入 `highContrastTheme`/`highContrastDarkTheme`。
  Windows 需核查系统指定颜色，不能只简单提亮当前品牌色。
- 区分高对比度、减少动画与减少透明度；系统要求减少透明度时使用现有不透明回退，
  不依赖用户先找到应用设置。常规模式继续保留现有视觉契约。
- 用边框、形状、文字或图标表达焦点、选中、错误与状态，不能仅靠颜色；保留媒体真实颜色。
- 验证文字缩放 100%/150%/200%，菜单、对话框底部动作和固定高度标题栏的可达性；
  覆盖空/加载/错误/禁用/选中态及四语言长文本。

验收：八个强调色×浅/深色组件图，四宽度×浅/深色受影响屏幕图，以及系统高对比度原生检查；
逐张检查而非只看 harness 退出码。为正常文字 4.5:1、大文字及必要非文本控件 3:1 建立适用
状态的对比度断言，禁用态单列评审。退出系统模式后恢复用户原先主题，更新令牌契约文档。

### DESK-06 后续 Flutter 可测试性整理

独立后续 PR，不阻塞 DESK-01～05。先盘点根状态单例和 UI 发起副作用的调用路径，
遵循现有分层，不批量引入新的框架或无用途的抽象。

- 先让 `AppState` 注册的全局日志监听可解除，验证 dispose，避免为了测试多实例而泄漏。
- 再提供明确的数据库注入构造入口，让根状态测试使用 `openTestDatabase()`，保留现有应用入口兼容性。
- 按实际用户流程把网络/文件副作用下沉至 state 或可注入的屏幕 controller，避免简单转发层。

验收：两个独立测试实例不共享数据库、日志监听或可变状态；销毁后无事件回调；
迁移的流程覆盖成功、失败、取消及视图销毁后完成，现有布局/依赖扫描保持通过。

## 交付顺序与共同完成条件

建议每个 DESK 编号独立实现 PR：先 DESK-01 复现/修复和 DESK-02，再 DESK-03/04，
接着 DESK-05，最后按维护需求推进 DESK-06。DESK-03/04 不依赖无障碍引擎问题解决，
但最终桌面验收必须覆盖它们与读屏/键盘的组合。SDK 升级如需独立 PR，应先合入再验收后续实现。

- [ ] DESK-01：Windows 语义树与原生桥接恢复，崩溃回归及 Narrator 实测通过。
- [ ] DESK-02：键盘完整工作流、焦点和双平台读屏通过，更新原快捷键欠账。
- [ ] DESK-03：macOS 原生菜单、快捷键和四语言通过。
- [ ] DESK-04：Windows Snap、DPI 与标准窗口交互通过。
- [ ] DESK-05：系统高对比度、缩放及视觉矩阵通过。
- [ ] DESK-06：根状态隔离、监听生命周期与选定副作用流程通过。

每个代码 PR 提交前依次运行 `dart format lib test tool`、`flutter analyze` 和
`flutter test -x screenshots`，全部通过；UI 变更另跑对应截图并目视检查。
文案变更先合并四语言源 ARB，再生成 l10n；不直接修改生成文件。原生代码变更必须构建目标平台。
性能相关的焦点/布局/玻璃改动使用现有 probe，在同次会话测量前后，不靠截图或推理宣称性能改善。

验收记录包含 commit、SDK、OS、构建模式、测试命令与结果、截图和未完成项。
缺少原生主机或工具时可继续独立实现，但保留原生验收未勾选，不能宣称完成。
全部执行后把长期决定写入 architecture、证据和剩余限制写入台账，再按仓库惯例删除施工正文。

## 对照资料

- [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)：建议应按项目调整，并非唯一架构标准。
- [Flutter accessibility](https://docs.flutter.dev/ui/accessibility)：语义、读屏与发布检查。
- [Apple menus](https://developer.apple.com/design/human-interface-guidelines/menus)：原生菜单命令与发现性。
- [Windows Snap layouts](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-snap-layout-menu)：自绘按钮的命中测试与窗口尺寸。

以上用于解释审查标准；实施时重新核对 SDK/API 和上游问题状态，避免把旧规避措施或文档当成当前事实。
