# 《Joycai 设计规范》逐项核对报告

对照 claude.ai/design 项目 `925a4d48-684e-4733-bca2-1aa808b7e18f` 的 `Joycai 设计规范.dc.html`。

设计稿三章：**标准组件**（10a light / 10b dark）、**主要页面**（10c–10i）、**对话框**（10j–10l）。

本轮范围：审计全部三章 + 落地令牌层 + 对齐「标准组件」章。主要页面最初只核对不改；10c–10e 的逐项核对与补完见 §二。

多主题色适配规则见 [`docs/architecture/design-tokens.md`](../architecture/design-tokens.md)。

---

## 一、标准组件（10a / 10b）

图例：✅ 符合 · ◐ 结构对、数值漂移 · ✗ 不符 · ⚖️ 与代码中已有明确理由的决策冲突

| 组件 | 设计稿 | 改前 | 结论 | 现状 |
|---|---|---|---|---|
| 主操作按钮 | 高 34 · 圆角 8 · 主色渐变 · 彩色投影 | 高 38 · 圆角 10 · 纯色 · `elevation:2`+同色阴影 | ◐ | 已改几何。渐变不做（见偏离表） |
| 次级操作按钮 | 圆角 8 · 1px 描边 · surface 底 · 灰字 | `FilledButton.tonal`（`secondaryContainer` 实底） | ✗ | **已改为 `OutlinedButton`**（18 处调用点，无需改调用代码） |
| 危险操作按钮 | 描边 `rgba(danger,.4)` + danger 文字 | `error` 描边 @0.5 + error 文字 | ✅ | 0.5 换成 `AppAlpha.edge` 令牌 |
| 静默操作按钮 | 透明底 · **次级文字灰** | Material 默认主色前景 | ⚖️ | **保留现状**——见偏离表 |
| 图标按钮 | 32×32 · 圆角 8 · 1px 描边 · 图标 16 | 38×38 · 圆角 10 · `outline@0.45` · 图标 ≈18 | ✗ | 已改 32 / 圆角 8 / 图标 16 / `outlineVariant` |
| 分段控件 | 轨道 pad 3 圆角 9；选中片**浮起 surface** + 主色深文字 | 轨道 pad 4 圆角 12；选中片主色 15% 底 + 主色 60% 描边 | ⚖️ ◐ | 轨道 pad 3 / 圆角 10；15%→`accentTint`，60%→`accentRing`，选中文字→`onAccentTint`。**选中样式保留 `tinted`** |
| 工具页签 | 圆角 8 · 激活 = 主色 12% 底 + 主色深字 | `AppToolButton`：已是主色 12% 底，但前景是 `primary` | ◐ | 前景改 `onAccentTint`，底改 `accentTint` |
| 导航项 | 圆角 10 · 激活 = 主色 12% 底 + 主色深前景 | `withAlpha(28)`≈11% 底 + `primary` 前景；抽屉里另有一份 `withAlpha(24)` | ◐ | 两处都改 `accentTint` / `onAccentTint` |
| 输入框 | 高 32 · 圆角 8 · **1px 描边 + surface 底**；聚焦 1.5px 主色 + 3px 光晕 | `AppTextField` 填充无边框——但**全应用只有 1 处调用**；真实输入是 **42 处裸 `TextField`**（25 文件）+ 56 处手写 `InputDecoration` | ✗ | **加了 `inputDecorationTheme`**（描边式，一次覆盖 42 处裸调用）+ `AppTextField` 改描边并补光晕环 |
| 开关 | 36×20 · 滑块 16 白 · 开=主色 | 24 处裸 `Switch`，Material 默认 52×32 | ✗ | **加了 `switchTheme`**——颜色到位，几何到不了（见偏离表） |
| 复选框 | 18×18 · 圆角 5 · 主色实底 · 1.5px 描边 | 裸 `Checkbox`，Material 默认圆角 2 | ◐ | **加了 `checkboxTheme`**，圆角/描边/填充全部到位 |
| 状态徽标 | 胶囊 · 执行中/待处理/已完成/失败 四态 | `task_queue_screen.dart:28` 硬编码 `Colors.green`，各页自绘 | ✗ | **新建 `AppStatusBadge`** |
| 计数徽标 | 19px 圆 · 实底红 · 白字 | 无统一实现，nav rail 里手写 15px | ⚖️ | **新建 `AppCountBadge`**，几何采纳、颜色不采纳（见偏离表） |
| 日志条 | 圆角 8 · 高一阶底色 · 等宽 11.5 | `log_console.dart:236-242` 8 个硬编码 hex + 手写 isDark 分支 | ✗ | 级别色改读 `AppSemanticColors` |
| 分组小标题 | 600/11 · 字距 .1em · 三级文字 | 无对应槽 | ◐ | 组件全景图里用 `labelMedium` + `letterSpacing: 1.1` 表达；未抽成共享组件 |
| 对话框外壳 | 圆角 14 · 44px 图标底板 · 关闭按钮 · 头尾分隔线 · 底部按钮高 36 | 圆角 12 · 22px 裸图标 · 无底板/关闭键/分隔线 | ✗ | 圆角→14；`icon` 自动升级为 44px 底板；新增可选 `onClose` / `divided`（默认开）。**52 处调用点全部无需改动** |

## 二、主要页面（10c–10i）——只核对

| 页面 | 设计稿自陈 | 结论 |
|---|---|---|
| 10f 图像下载器 · 10g 文件浏览器 · 10h 任务队列 · 10i 提示词库 | 「由深色稿转换 · **布局不变**」 | 布局本就与现状一致。差异集中在选中态表达与语义色——`accentTint`/`accentRing` 与 `AppSemanticColors` 落地后已自动收敛。**无需页面级改动** |
| 10c 工作台 · 10d 提示词助手 · 10e 裁剪与缩放 | 「定稿 · 原 7a/8a/9a 方案」 | **不是新方案，22 项里 17 项早已落地**——初版报告只看了设计稿上「定稿」这个标签就断言「需要页面级重排」，没有对代码，与 10l 那次是同一个错误。逐项核对见下 |

### 10c–10e 逐项核对

三页的原始提案（`Joycai 页面重设计.dc.html` 的 7a / 8a / 9a）各自附了改进说明；10c–10e 就是这三份的定稿，内容一字未改。工作台那份自陈「**布局不动**，只调层次与一致性」——所以「页面重排」这个说法从一开始就不成立。

**10c 工作台（8 项）**

| # | 设计稿 | 结论 |
|---|---|---|
| 1 | 标题栏并入浅色主题 | **不适用**：应用不绘制自定义标题栏，用的是系统窗口装饰 |
| 2 | 工具按钮统一为静默样式 | 已做（`AppToolButton`） |
| 3 | 文件名移出画面、改卡片页脚 | 已做（`image_card.dart` 的 `Column` + `_buildFooter`） |
| 4 | 选中态主色描边 + 序号角标，**与右栏参考图顺序一一对应** | 网格侧早已做；**右栏那半边缺序号**——而序号存在的理由正是两边对上。已补 |
| 5 | 悬停操作收进胶囊 | 已做（`_buildHoverActions`） |
| 6 | 「添加文件夹」降为 tonal | 已做 |
| 7 | 右栏分组卡片化 | 已做（三块 `AppCard(outlined)`，「发送到提示词助手」已在编辑器页脚） |
| 8 | 灰阶与主题色解耦 + 底栏迷你进度条 | 已做（PR #74 / `app_run_console.dart` 的 44px 进度条） |

**10d 提示词助手（7 项）**

| # | 设计稿 | 结论 |
|---|---|---|
| 1 | 设置面板落进固定右栏 | 已做（`OptimizerConfigPanel` 走 `rightPanelBuilder`） |
| 2 | Agent 过程折叠成时间线卡 | 已做（`_buildAgentTimeline`） |
| 3 | 结果卡片头部常驻操作 + 长文折叠 | 已做（`_buildPromptCard`） |
| 4 | 参考图卡片 + 文件名页脚 + 序号；**红色 ✕ 降为中性小圆钮** | 卡片/页脚/序号已做；**✕ 仍是 `error` 色**。已改为中性圆钮——移出列表随时可以再选回来，没有任何东西被销毁，一列红叉把整个面板读成一排警告 |
| 5 | 「应用到工作台」为唯一实心主色 | 已做 |
| 6 | 知识库状态可视化；**长路径尾部截断（保留末级目录）** | 状态点 / 文档数 / 更新时间 / 打开目录 / 本轮引用都已做；**路径是 `TextOverflow.ellipsis`，砍掉的恰好是末级目录**。已改为按路径分段丢头部（`_ElidedPath`） |
| 7 | 输入框升级为编排器：**白卡＋边框**替代灰色圆角块 | 上下文提示 / 快捷键 / 圆形发送钮都已做；**底仍是 `surfaceContainerHigh` 无边框**——全应用最后一个还穿着旧填充的输入框。已改 |

**10e 裁剪与缩放（7 项）**

| # | 设计稿 | 结论 |
|---|---|---|
| 1 | 保存动作文字化、分主次 | 已做（PR #76） |
| 2 | 比例收进分段控件、工具栏按「比例→尺寸→输出」分组 | 已做 |
| 3 | 自定义比例并入分段末位 | 已做（`_RatioPreset.custom`） |
| 4 | **尺寸输入显示实际值** + 锁链联动 | 标签与 px 单位已做、锁链已做；**值是空的**——`宽度 [    ] px` 立在一张尺寸早已知道的图上。已改为跟随选区，用户一旦手输就交出控制权（`_sizeIsUserSet`） |
| 5 | 裁剪框就地信息 + 8 手柄 + **三分线** + **遮罩浓度降一档** | 8 手柄与就地徽标已做；**三分线 extended_image 只在按住时画**，松手即消失，而构图恰恰是松手时判断的；**遮罩用的是 `scaffoldBackgroundColor` @0.8**，浅色主题下把黑底画布外的画面洗成近白。已各自覆写 |
| 6 | 输出预览条 | 已做（`_OutputPreviewBar`） |
| 7 | 底栏定位信息（文件名 / 原始尺寸 / 缩放控件）+ 系统消息归入日志 | 已做（`_CanvasLabel` / `_ZoomPill` / 工具栏 `_buildFileInfo`） |

> 一处仍未做：选区角上的实时徽标（`_CropBadge`）要等编辑器发出变更事件才出现，打开时看不到。静止态的尺寸由输出预览条回答，拖动态由徽标回答，暂不重复。

## 三、对话框（10j–10l）

| | 结论 |
|---|---|
| 10j 添加费率组 / 10k 编辑费率组 | 逐项核对见下 |
### 10j / 10k 逐项核对

初版报告说这两页需要「字段级重设计」。**大半也早就在了**——`floatingLabelBehavior: always` 画出来的正是设计稿那个 fieldset 浮起图例，图例色早已取自 `metric_palette`。差的是三处：

| 设计稿 | 结论 |
|---|---|
| 46px 图标底板 · 圆角 13 | 44 / 12（`AppDialog` 的标准值，源自 10a 标准组件章）。**刻意不跟**：同一个弹窗外壳不能因为出现在第 3 章就换个尺寸 |
| 标题 700/20 + 副标 13 + 34px 关闭钮 | 已做 |
| 分组小标题 600/12 · 字距 .08em · **主色深** | ✗ 是本文件里私有的第三份 `_sectionHeader`，`titleSmall` w700 + `primary`，无字距。→ 见下「分组小标题」 |
| 名称字段：描边 + 占位「分组名称」 | 已做 |
| 计费模式两段式 | 已做（`AppSegmentedControl` expand） |
| 价格字段 fieldset 浮起图例 + 值 600/20 monospace + 单位 500/13 | 已做 |
| 输入/输出/缓存/请求 图例各自颜色 | 已做（`metric_palette`） |
| 缓存留空提示 | 已做 |
| **请求单价下的说明**「按每次成功请求计费，与 Token 用量无关」 | ✗ **缺**。按次计费那一支只有一个数字，没有任何东西说它是按什么算的——而它和按 Token 的费率差六个数量级。→ 补 `requestPriceHint`（四语言） |

外加一处只有渲染才看得见的：`contentPadding` 只给了水平内距，最后一行帮助文字直接压在页脚分隔线上，读起来像按钮行的装饰而不是缓存规则的说明。→ 补下内距。

### 分组小标题

初版报告写「目前只在组件全景图里表达，未抽成共享组件」。**也不准确**——共享组件一直在，叫 `ConfigSectionHeader`，只是关在 `screens/workbench/widgets/` 里，所以弹窗够不着、只好自己再写一份。加上组件全景图里的 `_Label`，同一个东西**共三份**，三种字重、三种颜色。

设计稿里它其实有两种语气，此前没人分清：

| 出处 | 颜色 |
|---|---|
| 10j / 10k 弹窗内的「基本信息 / 计费模式 / 价格配置」 | **主色深** |
| 10i 提示词库页面上的「分类管理」 | 三级文字灰 |

而全景图里那批 `.1em` / 11px / 灰的「色板」「按钮」「输入」，是**设计文档自己的图注**，不是应用里的组件——初版报告把图注当成了规范。

→ 提为 `widgets/app_section_label.dart`，两种语气（`accent` / `neutral`），三处调用点合一。颜色从 `primary` 改成 **`onAccentTint`**：`primary` 是调给「填充」用的，11.5px 半粗放在 `surface` 上偏薄，Orange / Green 两个种子色下贴着 4.5:1 的地板；`onAccentTint` 按构造在七个种子色下都过。`design_tokens_test.dart` 补了这一对的断言。

| 10l 覆盖原图确认 | **设计稿标注「新增」，但应用里其实早就有**（`crop_resize_toolbar.dart`，三个按钮与尺寸行俱全）。本报告初版照搬了设计稿的标注而没查代码，是错的。已按 10l 重做外观：危险色图标底板、副标题、关闭按钮、带边框的文件行（含 尺寸→尺寸 箭头，新尺寸用 `error` 色）、提示改存副本的信息框 |

## 四、顺带修掉的既有缺陷

| 位置 | 问题 |
|---|---|
| `app_theme.dart` filledButtonTheme | **`styleFrom` 的 `elevation` 在所有状态生效，包括禁用**。配上主色 `shadowColor`，一个禁用按钮会投出满强度的主题色光晕——暗色下看起来像按钮周围套了个发光环，让唯一不能点的控件成了整行最抢眼的东西。已改为禁用时 `elevation: 0` |
| `application_section.dart:122,140,187,224`、`about_section.dart:63,72` | `Colors.grey.shade300` 描边，暗色模式下必错 → `outlineVariant` |
| `color_picker_widget.dart:92` | `Colors.black` 选中环，暗色下不可见 → `onSurface`；同文件 `Colors.grey` 标签 → `onSurfaceVariant` |
| `main.dart:391` | `Color(0xFFB794F6)` 固定紫与 `colorScheme.primary` 组渐变，与 7 个种子色中的 6 个打架 → `primaryContainer` |
| `log_console.dart` ↔ `task_log_dialog.dart` ↔ `app_snackbar.dart` | 同一组日志级别 / 警告色抄了三份，各带手写 isDark 分支 → 统一读 `AppSemanticColors` |
| `constants.dart:68-78` | 9 个零调用点的死令牌（`cardRadius` / `smallRadius` / `defaultPadding` / `opacityLow`…）→ 删除，几何统一到 `design_tokens.dart` |
| 计费口径 5 色 | `usage_summary.dart` 声明为公开常量、注释写着「与费率组价格药丸共用」，`pricing_group_manager.dart` 却又**私有地重抄了 4 个**、注释写着「刻意用与用量页相同的色」——共用的意图一直都在，只是被复制而非导入。→ 抽出 `core/metric_palette.dart` |
| 模型类型 5 色 | `models_screen.dart` 与 `discovery_dialog.dart` 各有一份**逐字节相同**的 `switch`，`model_edit_dialog.dart` 第三份写成元组表。→ 抽出 `core/model_kind_palette.dart` |
| 6 处搜索框 | 每个需要过滤的列表各写一个，没有两个一致：圆角 8 / 10 / 12 / 18，图标 14 / 16 / 18 / 20，同一个色调三种填充透明度，外加 5 份只为「该不该显示清除按钮」而存在的状态。→ 抽出 `widgets/app_search_field.dart`。**填充去掉了**——设计稿 10a 的搜索框是描边式，`inputDecorationTheme` 已经把这个给了所有裸 `TextField`，这个组件只加搜索图标与清除键，其余全部继承。（早先的报告把这里记成「9 处填充式搜索框」，那个 9 是 `filled:` 的总数，混进了一个多行文本域、一个回答框、下拉、模型选择器和 Markdown 编辑器。实际是 6 处搜索框，其中 4 处填充。）|
| `data_section.dart` ↔ `wizard_import.dart` | 导入选项的移动端 sheet / 桌面 dialog / 开关行三个函数**各存一份**，且已开始漂移（一边 `AppButtonSize.large`+`fullWidth`、另一边 `SizedBox` 裹默认尺寸；一边问 `Responsive`、另一边硬写 `MediaQuery…< 600`）。→ 抽出 `widgets/dialogs/import_options_dialog.dart`，两份 `Colors.grey` / `Colors.grey[400]` 一并换成主题角色 |
| 模型类型 chip 容器 | 颜色已共用，但容器一个圆角 8 带描边、一个圆角 6 无描边，同一个 chip 在两屏长得不一样。→ 抽出 `widgets/models/model_tag_chip.dart`，取带描边那版，圆角走 `AppRadius.control` |
| 覆盖原图写入 PNG 字节到 `.jpg` | `_runImageProcess` 恒用 `img.encodePng`，覆盖 `.jpg` 会把 PNG 字节写进 `.jpg`。→ 改用 `img.encodeNamedImage(targetPath)` 按扩展名选编码器；无编码器的格式（app 能打开但写不了的 **avif**）**明确抛异常**而非静默回落 PNG，UI 给出可操作的提示。`test/image_encoding_test.dart` 从字节而非文件名去验证格式 |
| `settings_screen.dart` | 已有 `_categoryColor()`，但移动端列表把同样的 5 个色值又内联写了一遍，绕过了那个函数。→ 由 `_buildCategoryTile` 内部统一取色 |
| `crop_resize_view.dart:447` | 输出条宣称副本存到 `临时工作区 / crop_photo.jpg`，实际写的是 `<temp>/joycai/processed/crop_photo_<时间戳>.png`——文件名、扩展名、目录三处都不符。→ 抽出 `ImageProcessingService.resolveCropCopyTarget()`，输出条 / 覆盖弹窗 / 实际写入共用同一个解析器，命名改为确定性的 `<name>_crop.png`（冲突时加数字后缀） |
| `image_processing_service.dart` `saveImage()` | 裸 `writeAsBytes`，复制和覆盖走同一行、只差调用方拼出的路径字符串。→ 新增必填的 `allowOverwrite`，为 false 且目标已存在时抛异常。破坏性操作在 UI 与 service 两层都要拦 |

## 五、已知未做

| 项 | 说明 |
|---|---|
| 仍在自绘的输入框装饰 | 冗余的那批已删（见 §四）。**剩下的是刻意的**：聊天输入框、Markdown 正文、裁剪工具栏的内联数字输入三处 `InputBorder.none`，下载器的地址栏，以及 `AppDropdown` / `ChatModelSelector` / `PricingGroupManager` 自己的描边逻辑。这些**不该**被主题收编 |
| 裁剪选区的静止态徽标 | 见 §二 末尾 |
| 费率组弹窗的移动端 sheet | 桌面走 `AppDialog`，移动端自绘 grabber + header + footer。表单本身是同一个 `_buildForm`，只有外壳分叉——**没有合并**：sheet 的分隔线要分开的是拖拽条，dialog 的是标题，两者不是同一条线 |

**三章逐项核对至此结束。** 设计稿里剩下的每一处差异都记在 [`design-tokens.md` §4「与设计稿的已知偏离」](../architecture/design-tokens.md#4--与设计稿的已知偏离)，是有理由的偏离而不是待办。

## 验证方式

```bash
flutter analyze
flutter test
flutter test test/screenshots/component_gallery_test.dart
flutter test test/screenshots/app_screens_test.dart --plain-name "workbench ·"
```

`build/ui-screenshots/gallery_<seed>_<brightness>.png` —— 7 个种子色 × 明暗，一页放下全部标准组件，用来确认结构在换色后不塌。判读要点见 [`design-tokens.md`](../architecture/design-tokens.md#验证)。

`workbench_desktop_<brightness>_{selection,crop,assistant}.png` —— 工作台是八个页面共用一个导航项，而截图矩阵此前只拍 tab 0。**10c–10e 里剩下的 5 项，没有一项是读代码看出来的**：三分线、空的尺寸框、灰底输入框，都是把这三个 tab 摆到镜头前才现形的，其中尺寸框那条还要拍两遍才发现「填上了但输出条仍写 → –」。改这三页之前先跑这一条。

`usage_desktop_<brightness>_{add,addRequest,edit}.png` —— 10j / 10k。这个弹窗藏在用量页自己的 State 里的一个 tab 索引后面，`AppState` 够不着，所以只能像用户那样点进去。帮助文字压在分隔线上那条就是这样看出来的。（一个坑：`按次计费` 既是弹窗里的分段项、又是背后卡片上的模式徽标，不限定范围的 `find.text(...).first` 会点到卡片——那一下点在遮罩外，把要拍的弹窗关掉了。`tapText` 的 `of:` 参数就是为这个。）
