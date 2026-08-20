# 设计令牌与多主题色适配规则

《Joycai 设计规范》(`Joycai 设计规范.dc.html`) 用 blue `#4A72E8` **一种**主色画完了全部示例。本应用支持 **8 套种子色**（`AppConstants.presetThemes`：Blue / BlueGrey / Indigo / Teal / Green / Orange / DeepPurple / Rose），`#4A72E8` 是其中的默认值。

所以设计稿里的每一个**主色**十六进制值都**不能照抄**。这份文档记录的是把它们翻译成「主题角色 + 透明度」的规则——换种子色时结构不变、色相自动跟随。灰阶是例外，见 §0。

> 动本文件涉及的任何令牌前，先读这里。`test/design_tokens_test.dart` 把下面每一条都钉住了，`test/screenshots/component_gallery_test.dart` 在 8 个种子色 × 明暗下各出一张图。

### 读设计稿时的两个已知陷阱

改版把设计稿从 537 KB 重写到 93 KB，有两处没跟着改干净：

- **`10a` 色板的十六进制文字标签仍是旧的青色**（`#12897C` / `#0B6E64` …），但它**画出来**的色块已经是蓝色。以画出来的为准。
- **§1 表格写「按钮·输入·下拉 = 10px」，但 `10a` 帧和全部页面稿画的都是 8px。** 以帧为准，`AppRadius.control` 保持 8。
- **`10b`（暗色）整帧没有改版**：主色还是旧青色、灰阶还带绿。它唯一还能用的是表面阶梯 `#0E131F` / `#192132` / `#28354C`，那部分确实已经是新蓝调。暗色的其余部分是从 light 推导的，见 §0。

## 0 · 灰阶：一张固定的冷蓝表，与种子色无关

`ColorScheme.fromSeed` 会把种子色的色相染进**每一个**角色，灰阶也不例外——选青色，面板、描边、正文就全都泛青。两件事会坏掉：换种子色时灰阶在整个应用底下平移，任何针对某一个种子色调好的表面到下一个就不对了；而背景里已经有了强调色的色相，真正**是**强调色的元素（选中、聚焦、按下）就没什么可说的了。

改版前的做法是从一套 `monochrome` 方案里取中性角色——真灰、零彩度。那其实是两条规则叠在一起，只有一条是承重的：

- **承重的**：这张表不能随种子色移动。
- **不承重的**：这张表必须是中性灰。

新设计稿的灰阶是**刻意偏冷**的（画布 `#ECEFF8`、正文 `#171C3B`，都离中性有好几个点的蓝），那个偏色就是风格本身。所以 `app_theme.dart` 里的 `_Neutrals` 把它写死成两张常量表（light / dark），承重的那条规则原样保留：用户选橙色时，灰阶仍然是**一模一样**的那个蓝。

角色按**本应用给它的活**命名，不按 Material 的排序：

| 角色 | 活 | light | dark |
|---|---|---|---|
| `surfaceContainer` | **画布**——整屏的底 | `#ECEFF8` | `#0E131F` |
| `surface` | **面板**——浮在画布上的卡片 | `#F5F7FD` | `#192132` |
| `surfaceContainerHigh` | **面板上的卡片**（见 `AppCard`） | `#E6EAF5` | `#212B3F` |
| `surfaceContainerHighest` | **实底控件轨道**——输入框填充、开关关闭态 | `#DFE5F4` | `#28334A` |
| `outlineVariant` | 全应用的发丝线与输入框描边 | `#DBE0EF` | `#28354C` |
| `onSurface` / `onSurfaceVariant` | 正文 / 次级文字 | `#171C3B` / `#4D5470` | `#E6EAF5` / `#A3ABC2` |

⚠️ **面板在明暗两边都比画布亮。** Material 的暗色方案里 `surface` 比 `surfaceContainer` 暗，正好相反；设计稿 `10b` 画的是 背景 `#0E131F` 之上 表面 `#192132`，这里以设计稿为准。`app_color_scheme_test.dart` 有一条断言专门钉住它——除了那条测试没有别的东西拦着它被「修正」回 Material 的排序。

⚠️ **`outlineVariant` 取的是设计稿输入框的 `#DBE0EF`，不是图标按钮描边的 `#E4E8F4`。** 这个角色同时是全应用的分隔线；`#E4E8F4` 离它所在的面板只差一个半点，分隔线会直接消失。

## 令牌住在哪

| 文件 | 内容 |
|---|---|
| `lib/core/design_tokens.dart` | `AppRadius` / `AppSize` / `AppAlpha` 几何与透明度阶梯，`extension AppAccent on ColorScheme` |
| `lib/core/app_semantic_colors.dart` | `AppSemanticColors`（ThemeExtension）——成功 / 警告 / 信息 |
| `lib/core/app_theme.dart` | `_Neutrals` 冷灰阶常量表、`buildAppColorScheme` / `buildAppTheme`，以及各 Material 子主题 |

分工规则：**编译期不变量写成 `const double`；随明暗变化的颜色进 ThemeExtension 或 `AppAccent`。**

## 1 · 主色：三种形态，不是一个色值

设计稿从不把主色当成任意色号用。它只以三种形态出现，各自对应一个 `ColorScheme` 角色：

| 设计稿 | 形态 | 用 |
|---|---|---|
| 主色实底 | 主 CTA 填充 | `buttonFillScheme(seed).primary`（已有，light+vibrant，保证暗色下不发灰） |
| 主色描边 / 开关开 / 复选框选中 / 聚焦边 | 纯色 | `colorScheme.primary` |
| 主色 12% 底 | 选中态背景 | `colorScheme.accentTint` |
| 「主色深」——12% 底**上的文字/图标** | 文字色 | `colorScheme.onAccentTint` |

### `onAccentTint` 是这里唯一的难点

设计稿的「主色深」在 light 下比主色**暗**、dark 下比主色**亮**。Flutter 里没有单一角色两边都对，所以它是个分支：

```dart
Color get onAccentTint =>
    brightness == Brightness.light ? onPrimaryFixedVariant : onPrimaryContainer;
```

实测（`ColorScheme.fromSeed`，teal——这张表是改版前量的，改版没有动 `onAccentTint` 的推导方式，只是默认种子色换成了蓝）：

| | `primary` | `onPrimaryContainer` | `onPrimaryFixedVariant` | `primaryFixedDim` |
|---|---|---|---|---|
| light | `#006A60` | `#005048` | `#005048` | `#82D5C8` |
| dark | `#82D5C8` | `#9EF2E4` | `#005048` | `#82D5C8` |

- **dark 下 `primaryFixedDim` 恰好等于 `primary`**（7 个种子色全部如此）。用它 = 让文字和它脚下的底色同一个色调，正是要避免的失败。
- **light 下两个候选完全相同**。仍然取 `Fixed` 那个，因为它的色调是定义上钉死的；`onPrimaryContainer` 的色调是随明暗指派的，Material 历史上改过一次（曾是近黑的 tone 10，那样在 12% 底上就只是深色文字，不再是「主色」）。今天像素一致，改了也不塌。

**为什么 8 个种子色不用逐个调**：HCT 里 tone 就是 L\*，而 L\* 决定相对亮度，与色相无关。在 teal 上量到的对比度，在 orange 上是同一个数。

❌ **不要**用 `primary.withValues()` 手工调暗当「主色深」——teal 上看着对，Orange / Rose 上会失控。

## 2 · 透明度阶梯

设计稿用了 .08/.10/.11/.12/.14/.18/.30/.32/.40/.45/.50/.60 十一档，多数差异低于感知阈值。收敛成四档（`AppAlpha`）：

| 令牌 | 值 | 用途 |
|---|---|---|
| `tint` | 0.12 | 选中底：工具页签、导航项、状态徽标、对话框图标底板 |
| `ring` | 0.32 | 选中描边 / 输入框聚焦光晕 |
| `edge` | 0.50 | 描边式危险按钮的边、CTA 彩色投影 |
| `disabled` | 0.38 | Material 自己的禁用前景 |

> ⚠️ **`tint` 不要超过 0.14。** 暗色下这层底上放的是 `onAccentTint`：0.12 约 4.9:1，0.14 约 4.6:1，到 0.18 就跌破 4.5:1 不合规。**亮色下余量极大（约 8:1）不会报警**——事故只在暗色发生，而「让选中态更明显一点」正是最容易踩的一脚。

固定的 alpha 在明暗两边都成立，正是因为底色取 `primary`，而它的 tone 随明暗在 40↔80 翻转。**永远用 `primary` 打底，不要用某个固定角色。**

## 3 · 不跟随种子色的颜色

| | 归属 | 原因 |
|---|---|---|
| 危险 | `colorScheme.error` / `errorContainer` | `ColorScheme.fromSeed` 的 error 调色板本就与种子色无关。**不要**为它新建令牌 |
| 成功 / 警告 / 信息 | `AppSemanticColors` | Material 没有对应角色；最接近的 `tertiaryContainer` 由种子色推导，那样「警告」对一个用户是青色、对另一个是粉色，等于没有信号 |
| 身份色（计费口径、模型类型、标签、费率组） | 各自的调色板模块（见 `core/fee_group_palette.dart`） | 它们用色相**区分类别**，不是**陈述状态**。放进 `AppSemanticColors` 会让它变成杂物抽屉 |

`AppSemanticColors` 每色三个槽：`color`（实底/图标）、`container`（**不透明**的浅底）、`onContainer`（底上的文字）。容器刻意不用 alpha——徽标会落在卡片、面板和画布上，半透明在每种底上都是另一个颜色。

## 4 · 与设计稿的已知偏离

这些是**故意的**，不是漏改。改回去之前先读原因。

| 项 | 设计稿 | 本应用 | 原因 |
|---|---|---|---|
| 静默按钮标签 | 次级文字灰 | 主题色（Material 默认） | 应用已用两个组件解决了这个问题：`AppButton.text` 带主色（对话框的「取消」需要），`AppToolButton` 中性。比设计稿的一个组件更精确 |
| 分段控件选中态 | 浮起白片 | 主色 12% 底 + 描边（`tinted`） | `AppSegmentStyle` 区分了「选设置」用 `tinted`、「选视图」用 `raised`，比「一律浮起」更细。`raised` 仍可选 |
| 主 CTA | 主色渐变 | 纯色实底 + 同色投影 | `ButtonStyle` 表达不了渐变；套 `Ink(gradient:)` 会丢 Material 状态层与波纹。现有 `elevation:2 + shadowColor: fill.primary` 已复现设计稿彩色投影的意图 |
| 面板表面 | 半透明白 `rgba(255,255,255,.55)` 浮在画布上 | 不透明的 `#F5F7FD`（即该半透明层压在画布上的合成值） | 半透明表面在滚动内容上要每帧重新合成，而这些面板下面就是图库网格。像素一致，代价不一致 |
| 开关尺寸 | 36×20 | Material 默认 52×32 | `SwitchThemeData` 够不到轨道/滑块几何，只能改颜色。要到 36×20 得包 `Transform.scale` 或自建组件，是另一件事 |
| 计数徽标 | 实底红 | 主题色实底 | 本应用里红色已经表示「任务失败」，而这个数字统计的是**进行中**的工作。染红会让健康的忙碌队列看起来像坏了 |
| 状态徽标 · 失败 | 危险 10% 底 | `error` @ `tint` 底（非 `errorContainer`） | Material 暗色 `errorContainer` 是接近实心的深红，跟另外三个浅色底放一起不再像同一组状态，而像一条警报 |
| 成功文字色 | `#158046` | `#127843` | 前者在其容器上实测 4.40:1，差一点点不合规——最糟的位置。压暗一档过 4.5 |
| 字号 | 多处 12.5px | 类型阶梯的 12 / 13 | 半个像素不值得动 541 个 `textTheme` 引用。只采纳设计稿要求的**字重**。唯一跟着改版动了的槽是 `titleLarge`：18 → 16，对应设计稿的「页面标题 16/600」 |
| 等宽字 | 数值 / 代码 / 日志用 IBM Plex Mono，计量标签用 JetBrains Mono | 尚未实现 | 界面字体保持现状（系统 + 可下载中文字体），只补一个等宽角色，属于后续一步 |
| 弹窗图标底板 | 10a 章 44px 圆角 12；10j/10k 章 46px 圆角 13 | 一律 44 / 12 | 设计稿自己两章不一致。同一个 `AppDialog` 外壳不能因为出现在第 3 章就换尺寸，取标准组件章那一版 |
| 分组小标题 | 主色深 `#0f7d71` | `onAccentTint` | 同一个角色。`primary` 是调给**填充**用的，11.5px 半粗放在 `surface` 上偏薄，Orange / Green 下贴着 4.5:1 地板；`onAccentTint` 按构造七色全过。见 `AppSectionLabel` |
| 分组小标题字距 | `.08em`（12px 上即 0.96px） | `AppType.trackedLabelSpacing` = 1.0 | 应用的 `labelMedium` 是 11.5px，同比例是 0.92；这个尺寸上 1.0 与 0.92 读起来是同一件事 |
| 提示词助手 · 结果卡内「应用」 | 主色 10% 底 + 主色描边（tonal） | `AppButton.secondary`（中性描边） | 这一屏的实底主色已经花在页头的「应用到工作台」上。卡内再来一处主色染就是第 4 个用色位置，超出 §1 的三处（选中 / 主 CTA / 徽标），且与页头 CTA 争同一个语义。同理知识库卡的「重新索引」 |
| 提示词助手 · 「已初始化」徽标 | 主色胶囊 + 圆点 | `AppStatusBadge(kind: running)` | 取的就是设计稿那颗胶囊（`running` = `accentTint` + `onAccentTint` + 圆点）。语义上也成立：配好的知识库不是一件办完的事，而是 agent 每轮都在读的来源 |
| 提示词助手 · 面板固定宽 | 左 236 / 右 300 / 时间线卡 480 | 参考图卡 4:3、时间线卡 `maxWidth 520`、正文左右留白 16 | 设计稿画在一个定宽窗口上，而这三栏可拖拽（左 200–500、右 250–600、中栏下限 `kMinCenterWidth` = 400）。定高定宽在下限处会溢出 |
| 提示词助手 · 工具头高度 | 50px | `kToolHeaderHeight` = 58 | 这个头是对比器 / 蒙版 / 裁剪四个工具共用的。为一个工具改高度会让切页签时画布跳动，而设计稿那一页没有同级页签 |
| 提示词助手 · 上下文占用配色 | 青 / 蓝 `#3f8fbf` / 琥珀 `#d9963a` | `primary` / `semantic.info` / `semantic.warning` | 三段是**身份色**（区分整体的组成部分），按 §3 本该有自己的调色板模块；眼下只有这三段，且这两个是应用里仅有的与种子色无关的色相。加到第四段时再拆出 `context_usage_palette.dart` |

## 验证

```bash
flutter test test/design_tokens_test.dart          # 8 种子 × 明暗的对比度与角色断言
flutter test test/app_color_scheme_test.dart       # 灰阶不随种子色移动、面板浮于画布之上
flutter test test/screenshots/component_gallery_test.dart   # 16 张组件全景图
```

看 `build/ui-screenshots/gallery_*.png`，逐张确认：

- 灰阶在 8 张图里**完全一致**——面板/轨道/分隔线是同一个冷蓝，没有被种子色染上
- 每个选中态都用 `accentTint` / `accentRing`，强度一致
- 成功/警告/信息在 7 张图里**完全一致**
- 输入框聚焦光晕在每个种子色、明暗两边都看得见
- 分段控件选中项的标签在暗色下读得出
