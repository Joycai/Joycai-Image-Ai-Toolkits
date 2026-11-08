# DESK-02 工作台画廊键盘验证

日期：2026-11-08。PR #409；基线 `f41609e3`。本批为 DESK-02 的工作台实现，
不代表浏览器接入或双平台原生读屏验收已经完成。

## 行为与设计依据

依据维护中的 UI 规格和实际 Flutter 渲染；未取得历史设计服务原稿。
保留网格尺寸、暖石灰表面、图片选区外环与现有鼠标选择规则。新的逻辑焦点用现有
强调色和控制圆角画 2px 内描边，区别于选区外环。只保留一个可 Tab 到达的 pane 节点，
不新增每卡一个 FocusNode；`ListenableSelector` 只重建焦点状态变化的可见包装层。

- 左右按显示顺序，上下按实际分组行，跨组跳过标题且不绕回。
- 普通方向键单选，Shift 扩选/收缩，Ctrl/⌘ 只移动焦点，Space 切换活动图片选择。
- Enter 打开活动项，不依赖是否已选中；视频仍不能加入模型参考图片选区。
- 虚拟化离屏卡片按分组几何滚入可视区域；排序/换列保留路径，移除后回落旧序号附近。
- 解除画廊局部 ExcludeSemantics，卡片提供文件名、按钮角色、选中/焦点状态、索引和打开动作。
- 新绑定只作用于工作台 grid，文本输入保护继续生效，浏览器暂不声明这些绑定。

四语言源 ARB 已做递归重复键检查和语言键集比较，再运行 merge_l10n 与 gen-l10n。
检查发现既有 `removeFromList`、`filterAll`、`moveToTrash` 跨模块重复；删除较早模块的
被覆盖副本，保留原合并顺序中最终生效的译文。生成文件中的词条位置因此调整，既有译文不变。

## 自动化与证据边界

环境：本机 Flutter 3.47.9 / Dart 3.13.7，Windows；CI 固定的 Flutter 3.47.8 未作原生复测。

新增 `grid_cursor_test` 验证分组短行、边界、范围收缩、排序/换列身份、移除回落和空列表。
`gallery_keyboard_test` 在真实 Gallery 上验证 Tab、编辑保护、范围选区、仅移焦、Space、
离屏滚动、Delete 后继续选择、空状态、预览退出、响应式换列和重复按键；另验证鼠标双击
预览退出后 Space 操作来源项目。新导航动作只在 pane 直接持焦时认领，内部控件持焦时不抢键。
既有工作台快捷键、重建范围、注册表及四语言标签定向测试共 46 项通过。

提交前门禁：格式检查 948 文件零改动；`flutter analyze --no-pub` 为 No issues found；
`flutter test -x screenshots --concurrency=2 --reporter expanded --no-pub` 最终为 3560 通过、
6 跳过，耗时约 4 分 16 秒。日志为 `build/desk02-analyze-final.log`、`build/desk02-tests-final.log`。
此前完整测试为 3559 通过；双击来源焦点修正及其新增用例后重新运行了完整门禁。

新增焦点渲染已检查 390/834/1024/1440 × 浅/深色共八张，焦点内描边、选区外环、
工具栏和底部选择栏未见新增溢出。渲染文件为
`build/ui-screenshots/workbench_{mobile,tablet,ipad,desktop}_{light,dark}_keyboardFocus.png`。
修改前已有工作台图保存在 `build/desk02-baseline/`，并目视检查桌面浅色基线。
截图是在桌面主机上的响应式 Flutter 渲染，不代表原生手机键盘或系统读屏。

常规工作台/任务/设置及首轮焦点渲染共 149 项通过，日志
`build/desk02-screenshots.log` 未发现 overflow/exception。最后的焦点回调修正后，四项
画廊行为测试与十二项焦点/语言渲染共 16 项通过（`build/desk02-focus-final.log`）。
四语言说明再按正确滚动位置重拍四项通过（`build/desk02-shortcut-screenshots.log`），
已查看 `settings_mobile_light_galleryKeys_{en,zh,zh-Hant,ja}.png` 中的新增四行，未见溢出。
曾因新增渲染测试遗漏 Locale 导入而编译失败，补齐导入后通过；未计入有效验收结果。

原生热重载工具已尝试，但 DTD 未发现运行中的调试应用，未成功执行热重载。
本批未启动原生应用、未检查原生语义树、未播放视频、未运行 Narrator/VoiceOver；
Flutter 语义断言不能替代这些验收。DESK-01 的旧原生记录不能作为本批解除画廊语义排除后的证据。

## 后续

1. 浏览器网格与列表及跨栏焦点已在后续批次实现，见 [浏览器键盘验证](browser-keyboard-validation.md)。
2. 在 Windows 与 macOS 运行完整跨栏键盘流程和读屏，包含视频预览、菜单退场、长列表滚动。
3. 补 CI 固定 SDK 的原生语义压力验证；DESK-01、DESK-02 均保持未完成状态。
