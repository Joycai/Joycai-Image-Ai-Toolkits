# Windows 无障碍恢复验证记录

2026-11-08，PR #409，DESK-01 首批实现；完整验收未完成。

## 实现边界

- `lib/main.dart` 不再用 Windows 全局 `ExcludeSemantics` 隐藏应用。
- Windows runner 不再替换 Flutter view 的 WndProc，也不拦截顶层 `WM_GETOBJECT`；
  由 Flutter 原生桥接处理请求。
- `AppWindowFrame` 为 Navigator 内容建立独立 `Semantics(container: true)` 边界。
  在实际根节点测试中，仅解除全局屏蔽仍找不到设置导航；增加边界后导航按钮出现在树中。
  标题栏在视觉上本来就位于 Navigator 外，语义边界应与之匹配。
- `test/app/widget_test.dart` 检查真实应用根语义树中的设置按钮，防止只验证可见布局。
- `AppMenuAnchor` 在菜单 builder 与内层 tooltip 之间建立局部语义边界，避免两个
  overlay 的 traversal parent 标识合并。应用内 14 个菜单锚点统一使用它。
  `app_menu_anchor_test.dart` 验证每个 overlay 恰有一个语义父节点、菜单标签仍存在，
  并覆盖退场中间帧与重复开关。负对照临时移除边界时该测试失败，恢复后通过。
- `tool/windows_accessibility_probe.dart` 使用生产 runner，但不初始化业务状态、数据库或网络。
  它用于复现引擎问题，不打包进正常 `lib/main.dart` 入口。

本批没有修改 SDK、主题、文案或键盘绑定，也没有声称全部自绘控件已经完成语义审计。

## 工程门禁

- `dart format lib test tool`：944 个文件。
- `flutter analyze`：No issues found。
- `flutter build windows --release`：成功（43.7 秒），构建正常 `lib/main.dart` 入口。
- `flutter test -x screenshots --concurrency=2 --reporter expanded`：最终菜单修复版本
  **3552 通过、6 跳过**（4 分 28 秒）。
  首轮默认并发有一个目录 watcher 的 Windows SocketException（拒绝访问）；降低并发后
  完整重跑通过，并非只跳过失败文件。并行原生构建/截图曾因测试占用 `sqlite3.dll` 失败，
  后续这些操作按顺序执行。该环境问题没有通过修改业务逻辑掩盖。
- 五组受影响屏幕截图文件共 **266 项**完成；查看了工作台四宽度浅色、桌面深色，
  窄屏任务菜单、桌面模型编辑及上下文菜单，未见这些已检查画面的新增布局问题。
  截图 harness 会吞掉异常，不能把退出码当作完整视觉通过：用量页 390px 报告
  `ListenableBuilder` 在 build 中更新；模型编辑 390px 的 harness 实际拍到了任务页。
  两项分别串行重跑，并临时使用 `HEAD`（计划提交 `2fb6dfee`）的原始 Dart 源码对照，
  均可复现；对照结束逐字节恢复当前源码。这两项是既有问题，本批保留为待修项，
  不把这些截图列为有效的用量页/窄屏编辑器验收证据。

## 上游与本机

- 本机 Flutter **3.47.9**，framework `c197ca5199e9ee5661e865596c9c07294dfab51c`，
  engine `89c39edfdfae2949f6806e4a315c0c08522238b7`，Dart **3.13.7**。
- Windows 内核版本 **10.0.26300.0**；下述原生探针使用 **Release**。
- CI 仍固定 Flutter **3.47.8**；本机结果不能代替该版本的原生验证。
- [#100610](https://github.com/flutter/flutter/issues/100610) 已关闭并标记 solved；
  [#182444](https://github.com/flutter/flutter/issues/182444) 仍开放，包含 Release 崩溃报告。
  [#190344](https://github.com/flutter/flutter/pull/190344) 页面显示 Closed，不能据此推断已合入。
  因此本记录只陈述实际观察，不宣称引擎问题已被上游修复。

## 原生探针复现步骤

```text
flutter run -d windows --release -t tool/windows_accessibility_probe.dart
```

1. 先用原生无障碍检查器或 Narrator 连接窗口，确认树中出现 Run probe、Target 0/1。
2. 点击 Run probe，等待 Completed cycles 60。循环交替显示 ListView 的两个 tooltip 与
   MenuAnchor 内嵌 tooltip，在退场时调整窗口，交替主题，每五轮开关一次带输入框的对话框。
3. 检查进程仍存活、树仍能读取；检查运行日志中的 `AXTree`、异常和崩溃。
4. Tab 到下拉菜单，Enter 打开，检查两个选项；Escape 关闭并检查焦点。

负对照命令是在上述命令后加 `--dart-define=PROBE_RAW_MENU=true`，仅该隔离工具有此选项，
正常应用没有关闭无障碍或切回损坏语义树的开关。

观察结果：Windows Computer Use 的原生无障碍接口能读取按钮名称/角色和 tooltip。
首轮仅 ListView tooltip 的 60 轮没有 AXTree 错误。加入原始 MenuAnchor 后出现连续
`Failed to update ui::AXTree`，随后原生树只剩空组，证明本机 3.47.9 仍受影响。
加入 AppMenuAnchor 边界后，相同菜单场景 60 轮完成，循环结束仍能读取完整树，未出现
AXTree 错误；该次有一条 frame-time clamping 日志，不将其隐瞒为“零错误日志”。
首轮下拉菜单可用 Tab/Enter
打开，树显示 First option/Second option，Escape 返回 First option 焦点。
这是自动化接口的验证，**不是 Narrator 的语音与完整操作验收**。
计数到 60 本身也不是通过条件，必须同时核对桥接已激活、语义树及日志。

真实应用 Release 另复制至独立 `.portable` 目录启动，未读取现有用户数据库。
原生接口可读取欢迎向导、八个标题栏导航、工作台提示词编辑框、复选框和菜单；
展开工作台菜单后仍能读取内容，鼠标切换至任务页后仍能读取任务计数和空状态。
这只证明桥接和基础页面切换，不包含任务执行或 Narrator 操作。
实际树中仍可见某些控件的名称与 tooltip 重复，任务过滤项角色也需进一步审计，
不将“树能读取”写成全部控件语义完善。

## 2026-11-08 后续批次：分段控件与导航名称

- `AppSegmentedControl` 为每个选项显式提供名称、按钮角色、选中与禁用状态。
  图标模式不再依赖 tooltip 充当名称，文字/图标子节点和视觉 tooltip 不重复贡献名称。
  这覆盖任务页排序、提交模式及所有复用该原语的界面，不等于独立任务状态胶囊已修复。
- 选中项仍可获得键盘焦点和读屏激活；再次激活不重复调用 `onChanged`。
  禁用项无激活动作且不能获得键盘焦点。保留原有尺寸、主题和指示器动画。
- `NavLensGroup` 的语义名称只提供一次，快捷键单独作为 hint，视觉 tooltip 原样保留。
- 新增两种布局的语义状态/激活/Tab/Enter 回归测试；真实应用根测试另外检查设置导航
  没有重复 tooltip 且保留快捷键提示。原生隔离探针增加相应两种分段布局。
- SDK、Windows 版本与首批相同；本批不升级 CI 固定的 Flutter 版本。

工程验证：格式化 944 文件零改动，analyze 无问题，完整非截图回归 **3554 通过、6 跳过**。
首轮在 `setup_wizard_channel_test.dart` 的 setUpAll 出现一次失败，日志没有保留具体异常；
不能据此断定与首批 watcher 错误同因。独立重跑该文件通过，再完整重跑通过（4 分 27 秒）。
截图两组共 **83 项**完成，日志未发现 overflow/exception；查看了八主题明暗分段控件区域，
以及任务页四宽度浅色和桌面深色，未见新增布局问题。截图基线保留在本地
`build/desk01-followup-baseline/`。未新增窄屏深色矩阵，不将此结果称为所有尺寸/主题全覆盖。

Windows **Debug** 隔离探针构建成功（50 秒），热重启成功（1099ms）。原生控件树可读取
两种布局的 All / Running / Unavailable 按钮名称；Tab 可聚焦选中项，Enter 切换至 Running
后焦点保留，下一次 Tab 跳过禁用项进入图标布局，图标布局的选中 Running 也可聚焦。
观察到两条分段指示器同步切换。原生检查工具输出不含选中/禁用属性详情，因此这些属性
由 Flutter 语义测试断言，不能把原生名称/焦点检查写成属性或语音全部验收通过。
本次未观察到 AXTree 错误，有一条 frame-time clamping 日志。探针随后关闭。
本批未重新运行首批 60 轮压力测试，也未重新构建正常应用 Release；首批证据不冒充本批结果。

## 2026-11-08 后续批次：任务状态筛选与置顶开关

- 独立状态胶囊提供已有四语言名称、任务数 value、button/selected/enabled 状态；
  排除装饰文字的重复语义。选中项保留 Tab 入口，Enter、Space 和语义激活均不会重复应用筛选。
- 置顶开关由现有 Switch 承担焦点、状态与动作；外层标签仍可鼠标点击，但不再有第二个
  Tab 停靠点。标签隐藏为 tooltip 时仍有独立语义名称，tooltip 不重复朗读。
- 沿用暖石灰表面、原胶囊填色/轮廓、尺寸、InkWell 焦点高亮和滚动布局；不增加文案、
  颜色令牌或新快捷键。参考维护中的规格和真实渲染，未访问原始设计稿。
- 新增真实任务页测试：四语言 × 390/1440 的名称/计数、前后 Tab、Enter、Space、
  语义激活、选中项幂等与可见范围；834/1440 的置顶开关名称/状态、切换与前后遍历。
  置顶持久化操作在 real async 执行；既有任务行外观测试保持通过。
- 最终格式检查 953 文件零改动；analyze `No issues found!`；完整非截图测试
  **3576 通过、6 跳过**（concurrency=2，4 分 35 秒，`build/task-controls-tests-final.log`）。
  新增 10 项行为测试及既有 6 项任务行测试通过；最终焦点截图 **16 项通过**（20 秒），
  `build/task-controls-render-final.log` 无 overflow/框架异常。
- 已逐张检查 390/834/1024/1440 × 浅深色 × 已选/未选焦点共 16 张；基线保存于
  `build/task-controls-baseline/`。输出为 `tasks_*_filterSelectedFocus.png` 和
  `tasks_*_filterFocus.png`：保持原布局，InkWell 高亮区分焦点，窄屏沿用水平滚动与边缘淡出。
  本批没有修改共享颜色、玻璃或动画规则，未重跑八强调色组件矩阵或性能基准；
  四语言由行为测试覆盖，截图为中文，不将窄桌面截图视为原生移动端验收。
- 测试调试记录：运行中任务有持续动画，最初 `pumpAndSettle` 超时，改用 harness 的有限帧
  settle 后对实际状态断言；语义句柄在测试体的 finally 释放。截图初次按“失败”文本定位
  同时命中筛选和任务行，改为首个筛选标签并断言主焦点；最终截图按真实 Tab 路径逐帧取焦。
- 本机 Windows，Flutter 3.47.9 / Dart 3.13.7；CI 的 3.47.8 未变。DTD 未发现运行中的
  调试应用，热重载尝试失败；本批未启动原生应用、构建 Release 或验证 Narrator/VoiceOver。
  历史探针证据不作为本批原生验收。DESK-01 保持未勾选。

## 尚需完成

- CI 固定 Flutter 3.47.8 的同样原生复现；若选择升级，另行同步 CI 并补版本证据。
- 真实应用 Release + Narrator 的导航、输入、菜单、对话框、任务状态及屏幕/主题切换。
- 更长时间的 hover/overlay、窗口缩放与 ReorderableList 场景；出现错误时保留最小复现，
  优先修复局部生命周期或引擎，不以再次全局关闭语义作为验收。
- 自绘控件的名称、角色、值、选择/禁用状态及重复朗读审计。

上述项目完成前，DESK-01 保持未勾选；本 PR 不应作为无障碍发布验收通过的依据。
