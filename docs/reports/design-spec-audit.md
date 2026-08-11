# 《Joycai 设计规范》逐项核对报告

对照 claude.ai/design 项目 `925a4d48-684e-4733-bca2-1aa808b7e18f` 的 `Joycai 设计规范.dc.html`。

设计稿三章：**标准组件**（10a light / 10b dark）、**主要页面**（10c–10i）、**对话框**（10j–10l）。

本轮范围：审计全部三章 + 落地令牌层 + 对齐「标准组件」章。**主要页面的布局只核对、不改代码。**

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
| 10c 工作台 · 10d 提示词助手 · 10e 裁剪与缩放 | 「定稿 · 原 7a/8a/9a 方案」 | 是**新方案**，需要页面级重排（列宽、面板层级、工具栏分组均与现状不同）。超出本轮范围，建议单独一批推进 |

## 三、对话框（10j–10l）

| | 结论 |
|---|---|
| 10j 添加费率组 / 10k 编辑费率组 | 设计稿是 `PricingGroupManager` 的**重设计**：fieldset 式浮起图例标签、46px 图标底板、11px 字段框。`AppDialog` 的新外壳（底板 / 分隔线 / 圆角）已把骨架对齐；字段级重设计未做 |
| 10l 覆盖原图确认 | 标注「**新增**」——应用中尚不存在这个确认弹窗。未实现。`AppDialog(icon:, iconColor: colorScheme.error, onClose:, divided:)` 已经能直接搭出设计稿的形状，实现成本很低 |

## 四、顺带修掉的既有缺陷

| 位置 | 问题 |
|---|---|
| `app_theme.dart` filledButtonTheme | **`styleFrom` 的 `elevation` 在所有状态生效，包括禁用**。配上主色 `shadowColor`，一个禁用按钮会投出满强度的主题色光晕——暗色下看起来像按钮周围套了个发光环，让唯一不能点的控件成了整行最抢眼的东西。已改为禁用时 `elevation: 0` |
| `application_section.dart:122,140,187,224`、`about_section.dart:63,72` | `Colors.grey.shade300` 描边，暗色模式下必错 → `outlineVariant` |
| `color_picker_widget.dart:92` | `Colors.black` 选中环，暗色下不可见 → `onSurface`；同文件 `Colors.grey` 标签 → `onSurfaceVariant` |
| `main.dart:391` | `Color(0xFFB794F6)` 固定紫与 `colorScheme.primary` 组渐变，与 7 个种子色中的 6 个打架 → `primaryContainer` |
| `log_console.dart` ↔ `task_log_dialog.dart` ↔ `app_snackbar.dart` | 同一组日志级别 / 警告色抄了三份，各带手写 isDark 分支 → 统一读 `AppSemanticColors` |
| `constants.dart:68-78` | 9 个零调用点的死令牌（`cardRadius` / `smallRadius` / `defaultPadding` / `opacityLow`…）→ 删除，几何统一到 `design_tokens.dart` |

## 五、已知未做

| 项 | 说明 |
|---|---|
| 42 处裸 `TextField` 的手写 `InputDecoration` | `inputDecorationTheme` 已给出描边式基线，但调用点自己写了 `border:`/`filled:` 的会局部覆盖主题。逐个清掉是 25 个文件的机械改动，建议按屏单独推进 |
| 身份色去重 | `usage_summary.dart` ↔ `pricing_group_manager.dart`（计费口径 5 色）、`models_screen.dart` ↔ `discovery_dialog.dart` ↔ `model_edit_dialog.dart`（模型类型 5 色）仍各自硬编码。它们是身份色不是语义色，应仿 `core/fee_group_palette.dart` 各抽一个调色板模块 |
| `data_section.dart:319-407` ↔ `wizard_import.dart:97-187` | 近乎逐行重复，含各自的 `Colors.grey` |
| 10c–10e 页面重排、10l 新弹窗、10j/10k 字段级重设计 | 见上 |
| 分组小标题组件 | 目前只在组件全景图里表达，未抽成共享组件 |

## 验证方式

```bash
flutter analyze
flutter test
flutter test test/screenshots/component_gallery_test.dart
```

`build/ui-screenshots/gallery_<seed>_<brightness>.png` —— 7 个种子色 × 明暗，一页放下全部标准组件，用来确认结构在换色后不塌。判读要点见 [`design-tokens.md`](../architecture/design-tokens.md#验证)。
