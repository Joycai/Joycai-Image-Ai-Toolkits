# 设计令牌、多主题色与液态玻璃

设计源：Claude Design 项目 `925a4d48-684e-4733-bca2-1aa808b7e18f`，2026-09 界面翻新那一批文件——`00 设计系统`、`01 全局壳层`、`A1 工作台-图像` …。每个文件末尾有一段 mono 规格汇总，**以汇总为准**；帧号（`1c`、`1f` …）指向文件内的帧。旧的《Joycai 设计规范》（蓝色冷灰那一版）已废弃，不要再拿它的数字。

> 动本文件涉及的任何令牌前，先读这里。`test/design_tokens_test.dart`、`test/app_color_scheme_test.dart`、`test/app_theme_text_theme_test.dart` 把下面的规则钉住了；`test/screenshots/component_gallery_test.dart` 在 8 个预设 × 明暗下各出一张图，是唯一能看出一条颜色规则换了主题色是否还成立的办法。

## 令牌住在哪

| 文件 | 内容 |
|---|---|
| `lib/core/design_tokens.dart` | `AppRadius` / `AppSpace` / `AppSize` / `AppAlpha` / `AppType` / `AppMotion` 阶梯，`AppOverlay` 固定墨色，`extension AppAccent on ColorScheme`（主色三形态），`extension AppShadow` |
| `lib/core/app_theme.dart` | `_Neutrals` 暖石灰常量表、`_ErrorRoles`、`buildAppColorScheme` / `buildAppTheme`、各 Material 子主题、字号阶梯、`TextStyle.mono` / `metricsOnly` |
| `lib/core/app_semantic_colors.dart` | `AppSemanticColors`——成功 / 警告 / 信息 |
| `lib/core/theme_accent.dart` | `ThemeAccent`：主题色是一对（亮 / 暗） |
| `lib/core/app_effects.dart` | `AppEffects`：「减少视觉效果」开关，玻璃与场景动效读它 |
| `lib/widgets/glass/app_glass.dart` | `AppGlass`（三档玻璃）、`AppTintedGlass`（着色玻璃）、`GlassInk`、配方与调色 |
| `lib/widgets/glass/glass_controls.dart` | 玻璃条上的控件：`GlassSegmented`、`GlassIconButton`、`GlassDivider`、`GlassFab`、`measureGlassText` |

分工：**编译期不变量写成 `const`；随明暗变化的颜色是 `ColorScheme` 角色、ThemeExtension 或 `AppAccent` 上的派生。** 界面代码里不出现十六进制色值，不出现阶梯之外的数。

## 0 · 灰阶：一张固定的暖石灰表，与主题色无关

承重的规则从来只有一条：**灰阶不随主题色移动。** 用户选橙色时面板、描边、正文仍是一模一样的暖石灰；真正是主题色的东西（选中、聚焦、主按钮）才是屏幕上唯一带色相的东西。灰阶本身有色相（`00 · 1b`：暖石灰，色相约 40–60°），那是这张表的，不是种子的——`app_color_scheme_test` 用一支蓝色种子去测，每个灰阶角色都必须仍然落在暖色相里。

角色按**本应用给它的活**命名，不按 Material 的排序：

| 角色 | 活 | light | dark |
|---|---|---|---|
| `surfaceContainer` | **画布**——窗口底，aurora 画在它上面 | `#EBEAE6` | `#121210` |
| `surfaceContainerLow` | **列**——边到边的栏、栏头、执行日志条、对话框页脚、列内卡片里的输入填充 | `#F6F5F2` | `#191917` |
| `surface` | **面板**——列里的卡、对话框、sheet 内容区、助手对话列的底 | `#FCFBF9` | `#1F1F1C` |
| `surfaceContainerHigh` | **面板上的卡**、用户消息气泡 | `#F0EFEB` | `#292926` |
| `surfaceContainerHighest` | **轨道**——分段控件底、开关关、滑杆轨、禁用填充 | `#E3E1DC` | `#33322E` |
| `outlineVariant` | **发丝线**——分隔线、输入描边 | `#D8D6D0` | `#33322E` |
| `onSurface` / `onSurfaceVariant` / `outline` | 正文 / 次级 / 弱化（占位符、禁用字，仅非文字或 ≥14px） | `#1C1B18` `#625F58` `#8F8C84` | `#ECEAE4` `#A9A69E` `#79766E` |
| `scrim` | 遮罩 | ink @ .36 | `#000` @ .52 |

⚠️ **面板在明暗两边都比画布亮。** Material 暗色方案里 `surface` 比 `surfaceContainer` 暗，正好相反；这里以设计为准，`app_color_scheme_test` 钉着。

⚠️ **列、面板、面板上的卡不在一条单调阶梯上。** light 下列 `#F6F5F2` 比面板 `#FCFBF9` 暗、面板上的卡 `#F0EFEB` 比两者都暗。按活挑角色，别按亮度挑。

## 1 · 主色：三种形态，没有第四种

`00` 规定主色只以三种形态出现：

| 形态 | 用在 | 角色 |
|---|---|---|
| **实底** | 主按钮、计数角标、选择序号 | `primary` 下 `onPrimary`。站在玻璃条上时换成**着色玻璃** `AppTintedGlass`（`primary` @ .74 + 模糊），仍归实底，只换了材质；减少视觉效果时就是实底 |
| **纯色** | 描边、开关开、复选框、焦点环、选中图标 | `primary` |
| **12% 底 + 主色深** | 选中行、选中透镜的退化态、tonal 按钮（助手的「应用 / 写入文件 / 保存到库」） | `accentTint` 底，`onAccentTint` 字；描边用 `accentRing` |

**主色当文字一律是主色深**（`00`：文字按钮与链接也用主色深）：文本按钮、链接、分组小标题、运行中的状态字——`AppAccent.accentText` 就是 `onAccentTint`。`primary` 是调给填充的，拿去当文字，Orange 在亮色画布上只有 3.3:1；主色深按构造在列到卡的每一档上 ≥ 4.5:1，于是没有哪个预设需要特判。

### 主题色是一对

`AppConstants.presetThemes` 的值是 `ThemeAccent(light:, dark:)`：一个名字、两个成品色号，都原样画成 `primary`。色值只在 `presetThemes` 一处，这里不抄。

| 规则 | 亮色半 | 暗色半 |
|---|---|---|
| 明度 | `fromSeed` 落到 tone 44（Orange 例外：55，44 上是棕） | 提到至少 tone 62（绿 65） |
| `onPrimary` | 白字 ≥ 4.5:1 用白，否则同色相 tone 10 墨（Orange 亮 = 深墨） | 同色相 tone 10 墨，**不是白**（tone ~62 上白字只有 3:1） |
| 主色深 | 同色相、同彩度 tone 30（写进 `onPrimaryFixedVariant`） | tone 80（写进 `primaryFixedDim`） |

```dart
Color get onAccentTint =>
    brightness == Brightness.light ? onPrimaryFixedVariant : primaryFixedDim;
```

`buildAppColorScheme` 用 `vibrant` 变体长出调色板（`tonalSpot` 会把鲜色压成影子），但**只有主色角色活下来**：灰阶被上面那张表覆盖，容器角色（`primaryContainer` / `onPrimaryContainer`）被改写成主色自己彩度的对应 tone，界面代码不读它们——`design_tokens_test`「the container roles stay out of the UI」扫源码钉住，同时拦截手搓的 `primary.withValues(alpha: …)`：需要一个新的主色透明度，就在 `AppAccent` 上加一个有名字的派生（`accentGlassFill` / `accentGlow` 就是这么来的）。

**自定义主题色**（`00 · 1g`，设置页 `E1 · 1b`）走同一条路，派生在 `lib/core/custom_accent.dart`（纯函数，无状态）：亮色半取种子色相与彩度在 tone 44，琥珀到黄绿（HCT 48°–112°）与 Orange 预设同一例外改 tone 55；暗色半从 tone 62 起逐档上抬（至多 80），直到压暗色卡与自带暗墨都 ≥ 4.5:1。白字压不住时不单独特判——`ThemeAccent.onLight` 本来就会换成同色相深墨字。结果分通过 / 改深墨字 / 失败三态，附六项对比度。存储：`theme_accent` 写 `custom:#RRGGBB`，只存种子，加载时重新派生（`AppState.setCustomThemeAccent`）。

**门槛**（`design_tokens_test` 逐预设量）：暗色主色压 `surface`…`surfaceContainerHigh` ≥ 4.5:1；暗色 `onPrimary` 压主色 ≥ 4.5:1 且不是白；亮色 `onPrimary` 压主色 ≥ 4.5:1，白字的另要 ≥ 5.5；主色深压亮色每一档 ≥ 4.5:1；亮色主色当描边压画布以上每一档 ≥ 3:1；色相与种子差 < 4°、彩度不高于种子；两半色相差 < 30°。

## 2 · 透明度阶梯

| 令牌 | 值 | 用途 |
|---|---|---|
| `AppAlpha.tint` | 0.12 | 选中底 |
| `AppAlpha.ring` | 0.32 | 焦点环、选中描边 |
| `AppAlpha.edge` | 0.50 | 有语义的描边（危险描边按钮） |
| `AppAlpha.disabled` | 0.38 | 禁用前景 |

⚠️ **`tint` 不要超过 0.14。** 暗色下这层底上是主色深：0.12 约 4.9:1，0.18 跌破 4.5:1。亮色余量极大不会报警——事故只在暗色发生。固定 alpha 在明暗两边都成立，是因为底色永远取 `primary`（配对里为该明暗调好的那一半）。

## 3 · 不跟随主题色的颜色

| | 归属 |
|---|---|
| 危险 | `colorScheme.error` / `errorContainer` / `onErrorContainer`，由 `_ErrorRoles` 写入（`--err` / `--err-bg` / `--err-ink`）。危险**填充**用 `errorFillScheme()`：明暗两边都是亮色的红压白字——暗色 `--err` 是调给前景的，压白字只有 3:1 |
| 成功 / 警告 / 信息 | `AppSemanticColors`，容器**不透明** |
| 盖在应用之上的东西 | `AppOverlay.ink` / `onInk`（tooltip、减少视觉效果时的通知底），`AppOverlay.imagePlate` / `onImagePlate`（压在用户图片上的角标：尺寸、序号外的读数、RAW/AFTER、笔刷读数） |
| 身份色（费率组、模型类型、渠道标签） | 各自的调色板模块，不进 `AppSemanticColors` |

## 4 · 几何、字号、动效

**圆角 = 间距**（`00 · 1d`）：4 · 6 · 10 · 16 · 22 · 28，同心——外 = 内 + 6。

| `AppRadius` | 值 | 用在 |
|---|---|---|
| `xs` | 4 | 徽标、芯片、复选框、缩略图角标 |
| `sm` | 6 | 容器内的控件：分段项、菜单行、树行 |
| `control` / `md` | 10 | 按钮、输入、缩略图、分段轨道 |
| `lg` | 16 | 列里的卡、浮动玻璃条、弹出菜单、通知、胶囊折叠态 |
| `dialog` | 22 | 对话框、sheet 内容区、胶囊展开态 |
| `sheet` | 28 | 手机 dock、大 sheet 顶角 |

圆形（状态点、开关滑块、滑杆把手、单选）取自身 50%，不在阶梯上。

**控件高**（`AppSize`）：28 紧凑 · 32 标准（按钮、输入、图标按钮同高）· 40 触摸 / 列表行 / 面板主按钮 · 44 手机命中区下限。图标 14 · 16 · 20。

**字号只有七级**：28/600 · 20/600 · 16/600 · 14/500 · 13/400 · 12/400 · 11/500，另加 mono 12 / 11（`TextStyle.mono`，系统等宽栈 + 等宽数字，不打包字体）。槽位分配见 `_buildTextTheme` 的表。字距是**字号**的函数（`AppType.trackingFor`），分组小标题例外：`.06em`（`AppType.trackedLabelSpacing` = 0.66）。

**动效**（`00 · 1e`）：M1 100ms `quick` 管 hover / 选中 / 玻璃按下；M2 180ms `enter` 管分段透镜、开关、菜单、降级；M3 280ms `emphasized`、退场 ×0.6 管 sheet、浮动条出入、胶囊形变、对话框。切导航目的地无过渡；运行中状态点 1.6s 呼吸是唯一循环（`AppBreathingDot`）。平台「减少动态」→ 一切归零（`AppMotion.durationOf`）；应用「减少视觉效果」→ M3 降为 M2、呼吸停（`AppMotion.sceneOf` / `breathes`）。

## 5 · 液态玻璃

**玻璃只给控制层。** 标题栏、平板顶栏、手机顶部工具条、工作台浮动工具条、选中操作条、菜单、sheet 壳、任务胶囊、通知、dock 是玻璃；图片网格、卡片、表单、对话正文、输入框、对话框是不透明内容。

| 档 | blur | saturate | fill | 外阴影 | 用在 |
|---|---|---|---|---|---|
| `GlassGrade.bar`（G1） | 24 | 1.6 | .56 | 无（全宽贴边） | 每屏唯一的全宽层 |
| `GlassGrade.float`（G2） | 20 | 1.5 | .66 | 0 10 30 | 浮动件 |
| `GlassGrade.lens`（G3） | 12 | 1.3 | .42 | 无 | 选中透镜、按下态、缩略图上的操作条 |

配方：半透明填充（light 白 / dark `#1E1E1C`）+ `BackdropFilter`（`blur(r)` 与 `saturate(s)` 合成为一个滤镜，sigma = r/2）+ 1px 折射边（基色 + 左上高光到右下暗边的渐变）+ 顶部内高光。玻璃上的字和图标读 `GlassInk`（`gink` = 墨 @ .86，`gink2` = @ .60），不用纯黑纯白。按下：填充 ×0.6、高光边外扩、阴影加深。

**预算**：每屏全宽玻璃 ≤ 1，同屏可见玻璃 ≤ 3，玻璃只贴滚动区的边。一次全宽模糊在集显 4K 上约 19ms / 帧，这就是预算的来由。

**减少视觉效果**（`AppEffects`，`00 · 1c` / `01 · 1k`）：同一个盒子变不透明——bar 取列色，float / lens 取面板色，色调与主题相反的层（深色通知）取 `AppOverlay.ink`；发丝线代替折射边；模糊、饱和、内高光全去掉；布局、尺寸、圆角一个像素不变。选中透镜退化为 12% 底（中性的视图切换例外：退化为浮起的面板片，`A1 · 1h`）；着色玻璃退化为 `primary` 实底；aurora 退化为画布纯色。

**色调是声明的，不是采样的。** 设计要求玻璃按背后内容的明暗自动切换亮 / 暗玻璃。Flutter 里每帧回读背景像素的代价不可接受，所以 `GlassTone` 默认跟随主题明暗，已知压在深色内容上的层自己声明 `GlassTone.dark`（通知、缩略图操作条、媒体预览顶栏）。这是与设计的已知偏离。

**窗口背景 aurora**（`AuroraBackdrop`）：安静的材质墙，本身不带纹理。玻璃要折射的是内容（缩略图、视频帧、文件网格）；背景上的规则图案会和内容抢透出感，模糊之后网格线还会变成一团脏灰。深浅只来自极大半径的光晕，自下而上四层：画布色（`surfaceContainer`）→ 左上角外侧一团 `primary` 6% 径向光晕（衰减到 0.6）→ 右下角外侧一团 `primary` 4%（到 0.62）→ 顶部 `surface` 55% 提亮（到 0.42）。光晕取主色，换主题色时墙的冷暖跟着走，灰阶不动。两团光晕的透明度写在 `AuroraBackdrop` 里，不进 `AppAccent`：它们只属于这面墙，而且必须远低于 12%——到那个量级就和选中底一样深，选中态会读不出来。它不滚动不动画，重绘边界里画一次；减少视觉效果时只剩画布色。

## 5b · 拖放与落点（`00d`）

拖放只有三类落点，每类五态：静息 · 可放（已起拖、指针不在上方）· 悬停 · 拒绝（带原因）· 确认。组件都在 `lib/widgets/drag/`，界面代码不自己画落点。

- **插入位置（重排）**：`AppReorderGap` 包住框架的 `ReorderableListView`。落点是「空位即落点」：框架拖起一项时，会在原位留一个等高的空盒，把中间的项平移一个项高，但不给钩子画进这个空位。所以每一项经 `gap.item(...)` 套一个探针，报告自己画在哪、被列表平移了多少；拖拽的每一帧里，项槽内没被任何项盖住的那段就是空位，画成 `--tint` 底 + 1px `--p` 虚线 + r10 +「放到第 N 位」。动画中合拢的空位和张开的空位按当下尺寸各画一块，就是设计的「空位开合」。探针必须跳过悬浮代理里那份拷贝：它和原位同一个 index，却不在列表里。放下且位置变了，新位置的项亮 600ms `--ring` 细边（减少动效 1.2s），并朗读「第 N 位，共 M 位」。`test/app_reorder_gap_test.dart` 钉住它依赖的框架行为。
- **投放进容器（槽 / 区 / 整面）**：`AppDropZoneFrame` 按 `AppDropZoneState` 画底与虚线：静息 `--col` + 1px 发丝虚线 → 可放 1px `--p` → 悬停 2px `--p` + `--tint` → 拒绝 2px `--err` + err 底 → 已满 2px warn + warn 底。已放图片的槽只画边（`ground: false`），`--tint` 永远不压图像。整面投放用 `AppDropSurfaceOverlay`：`--scrim` + 内缩 2px 虚线，不用玻璃。确认是 `AppDropConfirmRing`（600ms ok 环）加 `AppDropNote`，不弹 toast。
- **投放到对象（目录树文件夹行）**：命中行 `--tint` 底 + 2px 实线 `--p` 环；复制时环换 ok；拒绝换 err 并在行尾挂原因。
- **可放态从哪来**：指针还没到的落点收不到 `DragTarget` 回调，所以应用内的 `Draggable` 起拖时报给 `AppDragSession`，落点监听它。系统拖入的文件（`desktop_drop`）只在指针进入时才知道，没有可放态。
- **被拖项与跟随件**：抬起态统一为 `appReorderLiftDecorator`（面板底 + 1px `--p` + `0 12 28` + scale 1.02，不降透明度；减少动效改 2px 环、不缩放）。同容器重排原位直接变空位；跨容器拖出原件留 .5 残影。跟随件 `AppDragFollower` / `AppImageDragFollower` 是不透明面板 + 1px 边，**不是玻璃**：它跟指针高速移动，模糊会拖影、在深浅内容间反复换色调，也因此不计入玻璃预算。
- **复制键**：`AppCopyModifier`，Ctrl，macOS 上是 ⌥；拖拽中途按下 / 松开实时切换跟随件与命中行。
- **触屏**：长按 300ms 起拖（`AppLongPressDragStartListener`）；到时 medium、落点每变一次 selection、放下 light，拒绝不给触觉。

## 6 · 与设计的已知偏离

这些是**故意的**。改回去之前先读原因。

| 项 | 设计 | 本应用 | 原因 |
|---|---|---|---|
| 玻璃色调 | 按背后内容亮度自动切换 | 声明式，默认随主题 | 见 §5 |
| 折射 | 真实折射 | 渐变描边 + 内高光近似 | Flutter 没有折射；配方写死在 `_GlassEdgePainter` |
| 危险填充的暗色 | `--err` 暗色 `#F0655F` 压白字 | 明暗都用亮色 `#C2312F` 压白字 | 暗色那支压白字只有 ~3:1 |
| 弹出菜单 | 玻璃二 | 右键与 ⋮ 菜单统一走 `AppGlassMenu`（`lib/widgets/glass/app_glass_menu.dart`）；工作台工具条的 `MenuAnchor` 与任务队列手机顶栏的 ⋮ 菜单仍是不透明面板 r16 + 发丝线 | Material 的菜单路由在自己的裁剪后面挂不上背景滤镜，所以玻璃菜单是自建路由；`popupMenuTheme` 保留为退化形态。那两处留在 `MenuAnchor`，是因为里面有滑杆、单选行与开关，不是一列动作 |
| 工作台卡片的文件名 | 只显示尺寸角标 | 另有一枚文件名角标，尺寸角标带文件大小 | 这两项在卡片上别无出处；网格包在 `ExcludeSemantics` 里、没有 tooltip |
| 视频卡时长角标 | 右上 mono 时长 | 无 | `AppImage` 与缩略图服务都不提供时长 |
| 手机上缩略图操作条 | 不画 | 选中的卡上显示，且不模糊 | 「回馈助手」只在这条上；满屏卡片各开一次模糊是每帧的代价 |
| 重排让位动画 | M2 180ms | 250ms easeInOut | 时长写死在框架的 `_ReorderableItemState` 里，不 fork 改不了 |
| 重排边缘自动滚动 | 48 触发带，240 → 900 px/s 线性 | 框架 `EdgeDraggingAutoScroller` 的默认速度；48 带只用来显示「继续拖动以滚动」胶囊 | 速度曲线同样在框架内部 |
| 长按起拖 | 300ms 环形进度沿指针 | 300ms，没有进度环 | 触觉在到时给出；进度环要自绘一层跟随指针的浮层，收益小 |
| 移动的跟随件图标 | `content_copy` | `drive_file_move_outline`（复制时 `file_copy_outlined`） | 复制图标放在"移动"上读起来就是复制 |
| 目录树复制态 | 只换环色 | 环换 ok，行底也换 ok 容器 | 按 1d 的复制行样式；只换环色时复制与移动在暗色上难分 |
| 目录树落点文案 | 树下方一条说明 | 命中行行尾芯片（测宽，名字优先） | 说明条离指针太远；芯片跟着命中行走 |
| 视频首帧 / 尾帧槽高度 | 132 | 92 / 96 / 104（按宽度） | 132 是按 210 宽的槽画的；两个槽并排在约 280 宽的列里，132 会变成近方形并把提示词卡往下推 40 |
| 复制键 | Ctrl（macOS ⌥） | 同设计；此前是 Ctrl 或 Cmd | macOS 上 Cmd 不再触发复制，与 Finder 一致 |
| 筛选中的渠道栏菜单 | ⋮ 菜单是唯一的排序途径 | 菜单与 Ctrl / Alt+↑↓ 在搜索中可用，按完整顺序移动 | 渠道可能越过被搜索隐藏的邻居；这是"筛选中仍能排序"的代价 |
| 工作台安全设置行 | 模型卡里一行摘要 | 仍在队列设置对话框 | 能力描述里没有「用这组设置」这一项，按模型家族判断会在界面层嗅探模型 id，违反分层规则 |
| 工作台工具条的工具页签 | 提示词助手的头部不画工具页签 | 所有工具页签都带返回 + 工具切换 | 四个工具共用一条头；只有助手少一段会让切页签时控件跳位 |

## 验证

```bash
flutter test test/design_tokens_test.dart          # 8 预设 × 明暗的对比度与角色断言、源码扫描
flutter test test/app_color_scheme_test.dart       # 灰阶不随主题色移动、面板浮于画布之上
flutter test test/app_theme_text_theme_test.dart   # 七级字号、字距随字号
flutter test test/workbench_glass_toolbar_test.dart # 工作台工具条的降级顺序
flutter test test/screenshots/component_gallery_test.dart   # 16 张组件全景图
flutter test test/screenshots                      # 全部屏幕 × 三宽度 × 明暗
```

看 `build/ui-screenshots/gallery_*.png`，逐张确认：灰阶在 8 张图里完全一致；每个选中态都是同一个 12% 底；成功 / 警告 / 信息在 8 张图里完全一致；玻璃层在亮暗两边都读得出上面的字。
