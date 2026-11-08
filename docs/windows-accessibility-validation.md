# Windows 无障碍恢复验证记录

2026-11-08，PR #409，DESK-01 分批实现；完整验收未完成。

**最新结论：Windows 原生验收未通过。** 当前代码 `64190dca` 在 CI 固定的 Flutter 3.47.8
Release 下，标题栏导航 tooltip 可触发 AXTree 更新失败，随后控件树可能停留在旧页面。
隔离菜单探针通过不代表真实应用通过；详见本文「固定 SDK 原生验收」及后续修复顺序。

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

## 2026-11-08 后续批次：剩余自绘控件

- 分类审计与边界见[自绘控件审计](custom-controls-accessibility-audit.md)。补齐玻璃按钮、
  shell、浏览器筛选、工作台独立动作、目录操作、颜色控件和分隔条的名称、状态及键盘入口。
  单动作共用 AppActionTarget；复合开关只保留 Switch 一个焦点入口；视觉 tooltip 保留但不重复朗读。
- 移除媒体预览/视频控制条的整块语义排除；补齐控制名称、键盘聚焦显示和读屏模式显示策略。
  分隔条新增四语言方向动作，沿用原有范围与持久化；没有新增全局快捷键。
- 新增 11 项行为测试：玻璃控件、名称与动作同节点、设置开关、色相、横纵分隔条、
  真实应用预览关闭及焦点恢复。完整结果见下方最终门禁记录。
- 渲染五屏 × 四宽度 × 浅深色 40 张，并运行八强调色明暗组件及 Markdown 矩阵 32 项。
  检查五屏矩阵和 16 张组件图；工作台焦点截图限定可见按钮，并断言主焦点和前景轮廓。
  最初取首个按钮会取到宽屏隐藏布局内的控件，已修正截图定位；不将隐藏控件主焦点视为可见焦点证据。
- 调试记录：早期 TooltipTheme 排除语义导致既有 tooltip 定位测试失败，改用显式 Tooltip，
  保留视觉提示；费用组测试改从公开 AppIconButton 判断禁用状态。首轮预览标签合并失败，
  通过单动作 MergeSemantics 修复。中间完整回归 3587 通过、6 跳过；随后补充语义合并并重跑。
  一次完整测试启动与截图进程重叠，sqlite3.dll 被占用而未运行；待截图退出后顺序重跑。
- 本机仍为 Flutter 3.47.9 / Dart 3.13.7，未修改 CI 3.47.8。DTD 无运行中的调试应用，
  热重载尝试失败；未启动原生应用或构建 Release。未实测 Narrator、VoiceOver 或真实视频插件。
  连续画布编辑的完整无鼠标替代不属于本批独立控件修复，详见审计边界。
- 最终门禁：format **962 文件零改动**；analyze **No issues found!**；完整非截图测试
  **3587 通过、6 跳过**，日志 `build/desk01-custom-tests-complete.log`。最终页面截图
  **40 项通过**（`build/desk01-focus-render-complete.log`），组件/Markdown 与页面联合渲染
  **72 项通过**（`build/desk01-custom-render-final.log`）；渲染日志未发现 overflow/框架异常。
  已逐张复查最终工作台八张焦点图；其他四屏及八强调色组件使用矩阵图审阅。未测性能改进，
  既有重建范围测试随完整回归通过。

## 2026-11-08 固定 SDK 原生验收：未通过

### 环境与产物

- 被测提交：`64190dca6343c95a647c90939b727b750183665e`；本轮仅记录验证结果，没有修改应用代码。
- Windows `10.0.26300.0`，Flutter **3.47.8**，framework
  `737ba8f885dc774b53b442759999a312c9461e4e`，engine
  `cf636b1dfb818dd6a3ff16e390e93b1a036969c8`，Dart **3.13.7**。
  SDK 从本机 Flutter 仓库的 3.47.8 标签建立独立 checkout，位于 `build/sdk/flutter-3.47.8/`；
  下载对应引擎产物，未替换日常 3.47.9 SDK，也未修改 CI。
- 探针 Release 构建成功（49.9 秒），真实 `lib/main.dart` Release 构建成功（42.4 秒）。
  真实应用完整复制到 `build/desk01-win-3478-app/`，启动前创建 `.portable`，确认在该目录
  生成独立 `joycai_workbench.db`。没有读取现有用户数据库、添加 API 凭据或调用生成服务。
- 真实应用 `data/app.so` SHA-256：
  `0663EE1AA07FE5195DC4CB87CDC19362ABF5C1062657B4008FEE81B3CA0CB022`；
  `flutter_windows.dll` SHA-256：
  `ECA1F8C9B1537BD585BBBCC62362DF9CA7E69FAA7D4E895688108AF63CCEA157`。

### 已观察到的通过项

- 使用 Windows Computer Use 原生接口连接后，隔离探针完成 **60 轮** tooltip、菜单、对话框、
  主题交替与窗口缩放。结束时仍可读取 Completed cycles 60、分段按钮和菜单；日志没有 AXTree
  错误或崩溃，有 **2 条 frame-time clamping** 提示，不能称为无错误日志。
- 循环后下拉菜单可打开，Escape 退场后焦点返回 First option，Enter 再次打开，Down
  将原生焦点移至 Second option。
- 真实应用初始原生树可读取欢迎向导、标题栏导航，以及跳过向导后的工作台按钮、开关、
  输入框和“调整面板大小”名称。一次 Tab 后裁剪按钮获得可见焦点轮廓。
  这些是有限入口检查，不是整个键盘顺序、开关状态或分隔条动作验收。

### 阻塞：标题栏导航 tooltip 使原生树失效

首轮跳过向导、检查工作台后切换到文件浏览器：视觉界面已进入文件浏览器，原生树仍显示
工作台控件和裁剪焦点；运行日志出现多条 AXTree 错误。重启时鼠标仍停在标题栏导航上，
仅显示该导航的 tooltip、尚未进入文件浏览器就再次报错。

进一步对照复现步骤（无需点击导航或切换页面）：

1. 关闭隔离应用，把鼠标移到窗口内容区空白位置，再启动同一 Release 产物。
2. 用原生无障碍接口读取欢迎向导；此时日志没有 AXTree 错误。
3. 把鼠标移到标题栏“文件浏览器”图标，等待 `文件浏览器 · Ctrl+2` tooltip 出现。
4. 日志新增两条同类错误：

   ```text
   Failed to update ui::AXTree, error: 99 will not be in the tree and is not the new root
   ```

节点编号随运行变化，首轮也出现 101、138、133；不能把编号当作稳定定位依据。
该对照将触发范围缩小到真实 shell 的导航 tooltip 生命周期。`NavLensGroup` 的
`MergeSemantics → Semantics → Tooltip → AppActionTarget` 与外层 Overlay 的交互是下一步
调查对象；**尚未用最小组件对照证明根因，也未证明是本批引入还是固定 SDK 的既有问题**。
不以升级 SDK、隐藏全部语义或忽略日志绕过验收。

本机证据（均在忽略的 build 目录，测试窗口已关闭）：

- `desk01-win-sdk.log`、`desk01-win-3478-app-build.log`：版本与构建。
- `desk01-win-3478-probe.log`、`desk01-win-3478-probe-cycle60.txt`、
  `desk01-win-3478-probe-menu.txt`：探针、完整树及键盘焦点。
- `desk01-win-3478-app-runtime.log`、`desk01-win-3478-app-stale-tree.txt`：首轮失败。
- `desk01-win-3478-app-repro.log`：重启时已有导航悬浮提示的复现。
- `desk01-win-3478-app-clean.log`、`desk01-win-3478-clean-before.txt`、
  `desk01-win-3478-clean-hover.txt`：鼠标移开启动与仅悬浮的对照。

### 后续顺序与未验收项

先为真实 shell 的导航 tooltip 建立组件/原生最小复现，修复合并语义与 overlay 的边界，
再在同一 3.47.8 Release 中重复以上对照及完整应用导航。随后继续开关、颜色调整、分隔条、
预览关闭焦点、重排和窄窗测试。必要时补前一提交的同 SDK 对照以判断回归来源。

本轮没有启动 Narrator，工具只提供控件树、焦点和画面，未验证实际语音、朗读顺序及
完整读屏工作流；原生树失效后的其他控件检查无效，未继续记为通过。macOS/VoiceOver、
真实视频播放也未验证。没有应用代码变更，因此未重跑 Dart 门禁；前批 3587 项测试通过
仍只代表 Flutter 层回归，**不抵消此次原生验收失败**。

## 尚需完成

- 修复上述已在 CI 固定 Flutter 3.47.8 复现的导航 tooltip / AXTree 阻塞，再重新验收；
  若选择升级，另行同步 CI 并补版本证据。
- 真实应用 Release + Narrator 的导航、输入、菜单、对话框、任务状态及屏幕/主题切换。
- 更长时间的 hover/overlay、窗口缩放与 ReorderableList 场景；出现错误时保留最小复现，
  优先修复局部生命周期或引擎，不以再次全局关闭语义作为验收。
- 在原生读屏器核验本批自绘控件的名称、角色、值、选择/禁用状态及朗读顺序；源码与 Flutter 语义审计已完成。

上述项目完成前，DESK-01 保持未勾选；本 PR 不应作为无障碍发布验收通过的依据。
