# UI 翻新 · 全量功能清单（2026-09-11，v3.33.0）

配套 brief：[2026-09-ui-rewrite-liquid-glass-design-prompt.md](2026-09-ui-rewrite-liquid-glass-design-prompt.md)。
用途：作为 Claude Design 的附件，也是翻新分支 `feat/ui-rewrite-liquid-glass` 验收「功能一件不丢」的对照表。从 `lib/main.dart`、`lib/screens/**`、`lib/widgets/**`、`lib/state/**` 与 `lib/l10n/src/en/*.arb` 整理，未含代码。

断点定义（`lib/core/responsive.dart`）：手机 `<600`、平板 `600–999`、桌面 `≥1000`。`isNarrow = <1000`（平板+手机合并分支）。工作台内部另按"内容区宽度"（窗口宽 − 导航栏 64/72px）自行判定，不用窗口宽。

---

## 1. 全局壳层

### 1.1 导航目的地（`lib/main.dart`，顺序即快捷键顺序）

| # | 标签 | 图标 | 屏幕 | 移动端 |
|---|---|---|---|---|
| 1 | Workbench 工作台 | dashboard | WorkbenchScreen | 显示 |
| 2 | File Browser 文件浏览器 | folder_open | FileBrowserScreen | **隐藏**（仅桌面/平板） |
| 3 | Tasks 批量任务队列 | checklist | TaskQueueScreen | 显示（带角标） |
| 4 | Downloader 图片下载器 | cloud_download | ImageDownloaderScreen | **隐藏**（仅桌面/平板） |
| 5 | Prompts 提示词库 | auto_awesome | PromptsScreen | 显示 |
| 6 | Models 模型与渠道 | memory | ModelsScreen | 显示 |
| 7 | Usage 用量统计 | analytics | TokenUsageScreen | 显示 |
| 8 | Settings 设置 | settings | SettingsScreen | 显示（固定底部） |

- 键盘：`Ctrl/⌘ + 1…8` 跳转对应目的地；仅当主屏为最前路由（对话框/向导之上不响应）；仅桌面平台。Tooltip 追加 `· Ctrl+N` 作为唯一的快捷键提示入口。
- 切屏**无过渡动画**（刻意）。
- 桌面（≥1000）：左侧竖排导航栏，宽 72px，图标 + 文字标签。
- 平板（600–999）：同一导航栏收窄至 64px，**仅图标、无标签**。
- 手机（<600）：底部 `NavigationBar`，前 4 项 + 第 5 格「More 更多」；More 打开左侧抽屉（宽 270），抽屉含 Logo 头部 + 其余目的地 + 底部固定「设置」。
- 「Tasks」项带计数角标 = pending + processing 数；角标用中性色不用红（红=失败）。
- 导航栏选中态：`navBackground/navForeground` 强调色薄底 + 12px 圆角。

### 1.2 自定义标题栏（`app_window_frame.dart`，仅桌面）

- 隐藏系统原生标题栏；`AppTitleBar` 高 `kTitleBarHeight`（36），半透明毛玻璃（`_TitleBarFrost`，饱和度矩阵），底部 0.5 透明发丝线。
- 左：16px 渐变圆角 App Mark（macOS 下省略，改留 78px 给红绿灯）+ 窗口标题「Joycai Image AI Toolkits vX.Y.Z」。
- 中：整条可拖拽移动窗口 + 双击最大化/还原（`_DragAndMaximise`）。
- 右（非 macOS）：Minimize / Maximize·Restore（图标随窗口状态切换）/ Close 三枚按钮。
- `AppWindowBackdrop`：窗体背景网格纹理，工作台画廊列与文件浏览器网格刻意透出它。
- 窗口标题栏颜色随主题同步给 OS（`WindowChromeService.applyTheme`）。

### 1.3 全局浮层

- **任务胶囊 `TaskCapsuleMonitor`**：置于所有屏幕之上的可拖拽浮层。
  - 显隐条件：(pending>0 或 running>0) **且** 当前不在工作台/任务队列 —— 那两屏已有执行控制台，二选一。淡入淡出，不硬卸载。
  - 折叠态宽 196，展开态 300；手机满宽（屏宽−32）。以**底边**为锚点向上生长。
  - 折叠内容：状态点、`{n} running` 或 `{n} planned`、平均进度百分比（等宽字体）、上/下箭头、3px 线性进度条。
  - 展开内容：分隔线 + 最多 3 条运行中任务行（任务类型图标 + 模型名 mono + 每任务环形进度）+「View All 查看全部」跳转任务队列。
  - 拖拽：1:1 跟手，越界 24px 余量，释放按动量投影滑行并吸附；边距 16px。
- **执行控制台 `AppRunConsole`**（工作台、文件浏览器、下载器、任务队列的底部栏）：
  - 收起态状态条：桌面高 32 / 手机高 40。内容：状态点（运行中脉冲 / 有错误变色）、「EXECUTION LOGS 执行日志」、任务摘要（running/planned/平均进度）、最后一条日志单行预览（仅桌面且无任务在跑时）、展开箭头。
  - 点击：桌面展开/收起日志面板；手机改为弹出任务队列 BottomSheet。
  - 展开后为 `LogConsoleWidget`：等级筛选、搜索框（可展开）、自动滚动到底（滚离底部自动关闭）、复制。高度可拖拽，持久化。
- **Snackbar `AppSnackBar`**：四种 success / error / warning / info，可带一个行动按钮（如「Models」跳转模型页）。
- **媒体预览 `showMediaPreview`**（全屏 Dialog，黑底）：
  - 顶栏：返回、文件名（mono）、`i / n` 位置、Save 保存、Share 分享。渐变遮罩，可整体淡入淡出。
  - 中部：`PageView` 翻页；图片可缩放/平移（失败显示 broken_image），视频有播放/暂停、进度条、音量/静音、Space 播放暂停、错误态。
  - 与网格缩略图之间有 Hero 过渡（工作台 / 文件浏览器各一套）。
  - 底部缩略图条（高 110）。
  - 左右大箭头翻页：**仅平板/桌面**（手机靠滑动）。
  - 快捷键：`Esc` 关闭、`←/→` 翻页、`Home/End` 首末、`Space` 显隐控制层。
- **侧面板 `AppSidePanel.show`**：窄屏下把桌面侧栏改成右侧滑出面板（文件浏览器的暂存区用它）。
- **对话框 `AppDialog`**：全局统一壳（标题 / 副标题 / 内容 / 底部按钮组）。
- **权限占位 `PermissionPlaceholder`**：锁形图标 + 平台相关权限错误文案 + 说明 + 「重新授权」按钮（macOS 沙箱目录失效时出现在画廊）。

### 1.4 首次运行向导（`SetupWizard`，5 步，全屏路由）

- 顶栏：「Welcome Setup 欢迎设置」+「Skip 跳过」；下方线性进度条 `(step+1)/5`。
- 步骤 0 欢迎：Logo、欢迎语、「Import Settings 导入设置」入口（从备份恢复）。
- 步骤 1 Storage 存储：`Portable Mode 便携模式`开关（+重启提示对话框「Restart Required」/「Exit」）、`Output Directory 输出目录`选择、`Filename Prefix 文件名前缀`。目录为空时「下一步」禁用。
- 步骤 2 Intelligence(API) 渠道：`Provider preset 供应商预设`下拉（OpenAI REST / New API OpenAI / New API Gemini / xAI / DeepSeek / MiniMax / Anthropic REST / New API Anthropic / MiniMax Anthropic / DashScope / DashScope Native / Midjourney Proxy）、`Display Name`、`Endpoint URL`（附端点提示文案）、`API Key`。Key 为空时按钮文案变「Skip」。
- 步骤 3 Model 模型：`Model ID`、「Fetch Models 拉取模型」（打开模型选择器）、`Display Name`、`Tag`。可选。
- 步骤 4 完成：完成语 +「Get Started 开始使用」。
- 底部：Back（步骤>0 且非完成步）/ Next / Get Started。
- 可从 设置 → 数据管理 →「Run Setup Wizard 运行设置向导」重新触发。

---

## 2. 逐屏清单

## 2.1 工作台 Workbench

三栏骨架 `WorkbenchLayout`：左面板 + 拖拽分隔条 + 中央列 + 拖拽分隔条 + 右面板；底部执行控制台；顶部工具条。

- 尺寸约束：中央列最小 400px；左面板 200–500px（宽度持久化，与其他屏共用 sidebarWidth）；右面板最小 250、最大 min(行宽×40%, 600)，宽度持久化。挤压顺序：先压右面板 → 再压左面板 → 最后左面板退化为抽屉。拖拽允许越界 24px，松手回弹。
- **桌面（内容区 ≥1000）**：三栏内联。
- **平板（600–999）**：两侧面板一律进抽屉（左 Drawer 200–300，右 EndDrawer 280–350），顶栏出现对应打开按钮（汉堡 / tune）。
- **手机（<600）**：单列；左面板为 Drawer（屏宽 80%，200–300）；右面板变 FAB 唤起的可拖拽 BottomSheet（初始 60%，30%–95%）。FAB 图标按模式：图像=tune、对比器=info、提示词助手=auto_awesome、视频=tune，其余无 FAB。
- 中央列默认无底色（透出窗体背景），仅提示词助手模式给 `surface` 凹底。

### 顶部工具条 `WorkbenchTopBar`

- 左：侧栏开关（内联时 menu/menu_open 切换；抽屉态变为打开抽屉按钮），36×36。
- 中：主模式两段 —— **Image 图像** / **Video 视频**；竖分隔线；工具按钮组 —— **Comparator 对比器** / **Mask Editor 蒙版编辑器** / **Crop & Resize 裁剪与缩放** / **Prompt Assistant 提示词助手**。整行可横向滚动。
  - 桌面：工具按钮带文字标签；平板：仅图标；手机：四个工具折叠进一个「Tools 工具」下拉菜单（激活时按钮染强调色）。
- 右：手机显示 `⋮` 更多菜单（Concurrency Limit 并发上限滑杆对话框 / Refresh 刷新）；平板右面板在抽屉时显示 tune 打开按钮。
- 底部 1px 分隔线。

### 左面板（图像/视频模式）：`UnifiedSidebar` → `FolderList`

- 顶部「Add Folder 添加文件夹」轮廓按钮。iOS/Android 上改为沙箱提示卡：`iOS Sandbox Active` / `Mobile Storage Restriction` + 说明。
- 分组树：
  - **SOURCES 来源**（带数量）：固定节点「All Sources 全部来源」（计数）+ 各来源根目录（可展开子目录、右键菜单、重命名内联编辑、新建子文件夹、拖拽移动/复制文件夹）。空态行内提示「No folders added」。
  - **RESULTS 结果**（带数量）：固定节点「All Results 全部结果」+ 结果根目录树。空态「No results yet」。
  - **WORKSPACE 工作区**：固定节点「Temp Workspace 临时工作区」（计数）。
- 移除文件夹确认对话框：`Remove Folder?`。

### 模式 — Image 图像处理

**中央列 = 画廊工具条 + 画廊网格**

画廊工具条 `GalleryToolbar`（按**自身可用宽度**度量文本后决定内联或折叠，不按断点）：
- 左：视图分段开关「All Sources 全部来源 / All Results 全部结果」（永不让位，极窄时横向滚动）。
- 选中数量 Chip（`{n} selected`；极窄时只显数字；有选中时染强调色）。
- 右（内联态）：Select All 全选、Deselect 清除选择（无选中时禁用）、【仅工作区视图】Clear Workspace 清空工作区（破坏性 + 确认对话框，说明文件本身不删）、缩略图尺寸滑杆（80–400，持久化）、缩略图填充切换（Fit 整图 / Fill 裁切）、Refresh 刷新、Import from Gallery 从相册导入。
- 触摸平台额外常驻「Take Photo 拍照」相机按钮。
- 折叠态：以上全部进 `⋮` 溢出菜单（缩略图尺寸变为对话框；填充模式为勾选项）。

画廊 `Gallery`：
- 网格 `ImageCard`，尺寸由缩略图滑杆决定。卡片元素：缩略图（视频取帧）、尺寸元信息角标、选择序号角标（**表示送入模型的顺序**）、提示词版本角标 `v{n}`（该图由助手第几版提示词生成）、悬停操作条（对比器 / 蒙版 / 裁剪 / Feedback to assistant 回馈助手）。
- 交互：单击切换选中、双击打开预览、右键/长按打开上下文菜单。
- 拖放：整个画廊是投放区，拖入受支持文件 → 加入临时工作区并切到工作区视图；拖拽悬停时整面强调色遮罩 +「Drop images here…」。
- 空态三分支：① 权限不可达 → 权限占位（重新授权）② 扫描中 → 圆形进度 ③ 空 → 图标 + 「Drop files here」(工作区) / 「No results yet」(结果) / 「No images found」(来源)。

图像卡片上下文菜单（视频文件只保留首项与通用项）：
`Open in Preview 打开预览` ｜ `Draw Mask 绘制蒙版` ｜ `Crop & Resize 裁剪与缩放` ｜ — ｜ `Add to / Remove from Selection` ｜ `Set as Before (RAW)` ｜ `Set as After (Result)` ｜ — ｜ `Set as First Frame (Video)` ｜ `Set as Last Frame (Video)` ｜ `Add to Video References` ｜ `Send to Prompt Assistant 发送到提示词助手`（多选时整批发送） ｜ — ｜ `Rename 重命名` ｜ `Copy Filename 复制文件名` ｜ `Open in Folder 在文件夹中打开` ｜ — ｜ `Save to Photos/Gallery 保存到相册` ｜ `Share 分享 / Share selected items (n)` ｜ — ｜【仅工作区视图】`Remove from Workspace 移出工作区` ｜ `Delete 删除`（红色，确认对话框；Windows 走回收站「Move to Trash」，其他平台「Permanently Delete」）。

**右面板 = `WorkbenchConfigPanel` 生成配置**

自上而下：
1. 选中预览：未选时 16:9 虚位卡「No images selected」；已选时标题 `{n} selected` + Clear 清除 + 可横向拖拽重排的 100px 缩略图条（序号即送模型顺序）。
2. 参考图能力提示：模型不支持参考图 / 最多 n 张。
3. `ModelSelectionSection`（可折叠卡）：Channel 渠道可搜索选择器、Model 模型可搜索选择器；下方按模型能力动态渲染参数：Aspect Ratio 宽高比、Resolution 分辨率、Size 尺寸（打开尺寸对话框）、Quality 质量（Auto/Low/Medium/High）、Prompt rewrite 提示词改写（On/Off）、MJ 专属 Version / Mode / Stylize / Chaos。Gemini 渠道另有 `SafetySettingsSection`（4 类别 × 5 阈值）。
4. 开关卡：`Use Streaming 使用流式`、`Compress Reference Images 压缩参考图`（>3MB 重编码为 JPEG）。
5. Prompt 提示词区（桌面为弹性填充，始终占满剩余高度）：标签行右侧带「Prompt History 提示词历史」按钮 + 「Library 提示词库」按钮（库为空时禁用）；`MarkdownEditor`（Markdown 开关、预览切换、展开编辑器）；卡片底部页脚「Send to Prompt Assistant」文字按钮 + 队列设置齿轮。
6. 底部固定行动条：主按钮 `Process Prompt 处理提示词`（无选中）/ `Process {n} Images 处理 n 张图`。提示词为空时禁用；无模型时弹警告 Snackbar 带「Models」跳转；提交后 Snackbar「Task submitted to queue」。
- 手机 BottomSheet 版：Process 按钮**置顶固定**，其余内容滚动。

关联对话框：
- `Prompt History 提示词历史`：列表（相对时间）、Preview 预览、Use This Prompt 使用（警告将覆盖编辑器内容）、Clear History 清空（确认）；空态「No recent prompts」。
- `PromptLibrarySheet 提示词库`：搜索过滤、按分类筛选、Apply 应用（覆盖）/ Add 追加。
- `Image Size 图像尺寸`：Auto 自动 / Presets 预设 / Custom 自定义（Ratio 比例 + Long edge 长边 + Calculate 计算，Width/Height 手填）；规则校验行：两边为 16 倍数、长边 ≤3840、宽高比 ≤3:1、总像素 0.66–8.29 MP；提示「提交时两边吸附到 16 的倍数」。
- `Queue Settings 队列设置`：Concurrency Limit 并发上限滑杆、Retry Count 重试次数滑杆、Filename Prefix 文件名前缀输入。

### 模式 — Video 视频生成

- 中央列：同一套画廊工具条 + 画廊，上叠 `VideoWorkbenchOverlay`（最近一次生成的视频内嵌播放器，标题「Process Results」，含 `Open in System Player 用系统播放器打开`，文件不存在/解码失败有错误态）。
- 左面板：同图像模式的文件夹树。
- 右面板 `VideoConfigPanel`：
  - Model Selection（Channel + Model）+ 动态参数：Duration 时长、Quality（Standard / High）、Aspect Ratio、Resolution、Video Resolution、Video Aspect Ratio。
  - Prompt 提示词编辑器（同 MarkdownEditor，带历史）。
  - 开关：Compress Reference Images。
  - `Frames 帧`：First Frame 首帧 / Last Frame 尾帧 两个投放槽（拖入提示；点击可选；可清除）。
  - `Reference Images 参考图`：多图投放区。
  - 底部：`Generate Video 生成视频` 主按钮 + 队列设置齿轮。无模型时警告 Snackbar。

### 模式 — Comparator 对比器（左面板自动隐藏）

- 工具条：布局分段 `Side by Side 并排` / `Stacked 上下` / `Slider 滑块帘`；`Sync Zoom & Pan 同步缩放平移` 开关；`Clear 清除`；右侧 `Metadata 元数据` 开关（桌面切右面板，窄屏打开抽屉）。
- 视图：
  - 两个窗格带角标 `RAW` / `AFTER`；每格有「Select from Library 从库中选择」入口。
  - 底部状态：`Zoom {p}% · Synced` / `Zoom {p}% · Independent`。
  - Slider 模式为可拖拽窗帘分割线。
  - 空态：compare 图标 +「Send to Comparator」+ 说明 + 两张卡片 `Choose Before 选择原图` / `Choose Result 选择结果`。
- 右面板 `MetadataInspector`：RAW / AFTER 两段，各列 Width、Height、Aspect Ratio、File Size；底部差值 `Size reduced {p}` / `Size increased {p}`。无选中时「No image metadata selected」。

### 模式 — Mask Editor 蒙版编辑器（两侧面板均隐藏）

- 工具条：
  - 宽屏：Brush Size 笔刷大小滑杆、Mask Opacity 蒙版透明度滑杆、Mask Color 蒙版颜色（White / Black / Red / Green 圆点，非二值模式才有红绿）、源图信息 `Mask {w}×{h}`、Undo 撤销、Binary Mode 二值模式切换、Clear 清空（红）、`Save Mask 保存蒙版` / `Save Composite 保存合成`（副标题「to Workspace 到工作区」）。
  - 窄屏：仅保留 Undo + 两个滑杆的紧凑读数 + `⋮` 菜单（Brush Size / Mask Opacity / Binary Mode / Save Composite / Clear）+ 主按钮 Save Mask。
- 视图：画布（`DrawingCanvas`），笔刷预览圆随指针移动；角标 `{color} brush · {n} px`；二值模式时角标变 `Binary mode active — background hidden for clean mask export`；输出预览卡：`Output` + `Mask {w}×{h} · PNG (black & white)` 或 `Composite {w}×{h} · PNG` + `Mask will save to Temporary Workspace`。
- 空态：「No images selected」+「Go to Gallery 去画廊」；图片加载失败「Failed to load image」。
- 保存：写入临时目录 `masks/`，加入临时工作区，成功 Snackbar「Mask saved to workspace」。iOS 另存相册。

### 模式 — Crop & Resize 裁剪与缩放（两侧面板均隐藏）

- 工具条（**宽屏一行、窄屏分步**）：
  - 宽屏：原图信息 `Original {w}×{h} · {size}`；比例分段 `Free 自由` / 预设比例 / `Custom 自定义`；Width / Height 输入 + `Maintain Aspect Ratio 保持宽高比` 链接切换；`Resample 重采样`（采样方法，默认 lanczos）；Reset 重置；Overwrite Original 覆盖原图（红）；Save Copy 保存副本（副标题「to Workspace」）。
  - 窄屏：改为 Back / Aspect Ratio / Resize / Save 四个分步按钮，各自弹对话框：比例选择表、Resize 对话框（Width/Height + Maintain Aspect Ratio）、Save 菜单（Save to Workspace / Overwrite Original 红 / Reset）。
  - 现有实现按 TextPainter 度量逐级折叠（先装饰再标签），**不是像素阈值**，翻新后须保留这条规则。
- 视图：可拖拽裁剪框画布 + 角标 `{name} (Original Preview)`；输出预览卡：`OUTPUT PREVIEW` + `{原尺寸} → {输出尺寸} · {Crop|Crop + Scale n%} · {采样}` + `Copy will save to {path}`。
- 空态：「No images selected」+「Go to Gallery」。
- 覆盖确认对话框：标题 `Overwrite Original File?`、副标题 `This action cannot be undone.`、正文 + 保留原图提示 + 副本落点；按钮 Cancel / `Save Copy Instead 改为保存副本` / `Overwrite Original`。不支持写回的格式弹提示。
- 成功 Snackbar：`Image saved to temporary workspace` / `Original file updated`。

### 模式 — Prompt Assistant 提示词助手

三栏，中央列有独立凹底色。桌面显示左右面板；窄屏两侧均收起（右面板走抽屉/FAB）。

**工具条**：标题「Prompt Assistant」+ 模式徽章 `{mode} · Agent`；运行中显示 `Running` / `Running · step {n}`；右侧 Conversation History 历史、New Conversation 新对话、待写入 KB 变更时出现 `Discard all 全部丢弃` / `Write file|Write {n} changes`、`Apply to Workbench 应用到工作台`（窄屏简写 `Apply`）。手机把历史/新建折进菜单。

**中央列（对话）**：
- 空态：发一段草稿开始；AI 按需查看参考图；可多轮细化。
- 消息类型：user 用户、assistant 助手、tool 工具、prompt 提示词版本、error 错误、notice 通知、kbEdit 知识库改写、askUser 提问卡、resultFeedback 结果反馈、kbDistill 蒸馏请求。
- Agent 过程卡：`Agent process · {n} steps` / `Agent process · running`，摘要 `viewed {n} reference images` `read {n} documents`，可 `Show all {n} steps` / `Collapse steps`，运行中末行 `Working on the next step...`。工具行文案：`Checked the reference image list`、`Viewed reference image: {name}`、`Browsed knowledge base files`、`Read knowledge: {name}`、`Proposed knowledge update: {name}`。
- 提示词版本卡：标题 `Optimized Prompt`、Copy 复制、`Apply 应用`、长文可 `Show full text` / `Collapse`。
- 知识库改写卡：徽章 `New file` / `Update file`、`Show content ({n} chars)` / `Hide content`、内容大幅缩短时警告、按钮 `Write file 写入` / `Discard 丢弃`；结果态 `Written to disk` / `Discarded` / `Write failed`；无变化时 `This proposal changes nothing in the file.`。
- 提问卡 `The assistant has a question`：单/多选项（多选提示 `Select all that apply`）、`Other / add details...` 自由文本、`Send answers 发送答案`；已答 `Answered`，被自由文本顶掉 `Continued in chat`。
- 通知条：历史已压缩为摘要、部分参考图已不存在、README.md 占窗口过大。
- 错误态：`Retry 重试` 按钮。
- 结果反馈条目：标签 `Result feedback`。
- 蒸馏条目：`Distill session lessons` 请求 → 完成卡 `Lessons written to the knowledge base`，并提供 `Save final prompt to library 保存最终提示词到库`。
- 输入区：多行文本框（hint `Describe your idea or paste a rough prompt...`；忙碌时 `The agent is working — you can type again when it finishes...`）；底部提示 `Enter to send · Shift+Enter for a new line`，运行中变 `Esc to stop`；`{n} reference images sent with the message`；蒸馏 Chip（`{versions} versions · {feedbacks} feedback`，无版本时禁用）；运行中显示 `{s}s elapsed` / `{m}m {s}s elapsed` 和 `Stop 中断` 按钮；发送按钮 tooltip `Send (Ctrl+Enter)`。
- 快捷键：`Enter` 发送、`Shift+Enter` 换行、`Esc` 中断当前回合。

**左面板（随模式二选一）**：
- 非 knowledgeEdit → `OptimizerReferencePanel`：`Reference Images 参考图` 列表（编号与提示词中引用的文件名对应）；每张带 `Viewed by AI 已被 AI 查看` 标记与 `Remove image` 删除；下半 `Results 结果` 区列出生成结果及其反馈（无反馈显示 `No feedback yet`）。空态：`No images selected` + 说明（右键画廊图片 →「Send to Prompt Assistant」）。
- knowledgeEdit → `KnowledgeTreePanel`：标题 `Knowledge Base`、`{n} docs`、搜索框 `Search documents...`、文件树（改写中的文件标 `edited` / `new`）、底部 `{n} changes awaiting confirmation`。空/错态：无文档 / 无匹配 / 无法读取文件夹 / 未配置。

**右面板 `OptimizerConfigPanel`**：
- `Refiner Model 精修模型` 选择器。
- 模式分段：`System Prompt 系统提示词` / `Knowledge Base 知识库` / `Edit KB 编辑知识库`。切换模式会新开会话，先弹确认。
- systemPrompt 模式：`Template 模板` 可搜索选择器、系统提示词多行编辑器、`{n} characters` + `~{n} tokens`、未保存徽章 `Unsaved`、`Save 保存` / `Reset 重置`（保存写回提示词库模板）。上下文卡附注「本模式不挂载知识工具」。
- 知识库模式：状态卡（`Ready` / 运行中 `Reading`）、路径、统计 `{files} documents · {dirs} folders`、`Content updated {time}`、`Rescan 重新扫描`、`Open in Folder`；未配置/无效/缺 README 时分别显示对应提示，并提供 `Initialize knowledge base 初始化知识库`（确认；结果成功 / 失败 / 已初始化）。
- `Cited this round 本轮引用`：引用文件列表；运行中 `{n} · in progress`；`All {n}` 全部；空 `Nothing cited yet`。
- `Iteration timeline 迭代时间线`：`{n} versions`，按版本/反馈节点列出（反馈节点前缀 `Feedback ·`）。
- `Context usage 上下文占用`：System prompt / Tool definitions / Conversation / Remaining 四段条形 + 数值；窗口未设置 `Window not set` / 无限 `Unlimited` / 假设默认时提示。
- `Write permissions 写入权限`（Edit KB 模式）：`Let the agent write to the knowledge base`、`Confirm each write`、`Keep a .bak copy before overwriting`；关闭确认时红字警告。
- `Pending changes 待写入变更`：`Write all` / `Discard all`。

**会话历史（BottomSheet）**：列出已保存会话（按模式图标），显示标题与更新时间，行内 Rename 重命名与 Delete 删除（确认），点击恢复会话。无历史时 Snackbar `No saved conversations yet`。

---

## 2.2 文件浏览器 File Browser（**桌面/平板专属**）

- **移动端**：整屏替换为占位页 —— AppBar「File Browser」+ 图标 + `Feature Limited on Mobile` + 说明 + iOS/Android 各自提示。

**布局**：左目录列（宽度可拖拽持久化）+ 分隔条 + 中央文件列 +（可选）右侧暂存区列；底部执行控制台。
- 窄屏（<1000）：左目录列变 Drawer（固定 260 宽），标题栏出现汉堡；暂存区列改为右侧滑出面板。

**左列**：紧凑标题行「DIRECTORIES」+ 目录计数徽章 + `Deselect all directories 取消全部目录选择`（无激活目录时禁用）+ `Add Folder`；下方纯目录树（无聚合节点）。空态：folder_off 图标 +「No folders added」+「Click "Add Folder" to start scanning for images.」

**中央列头部**（高 72）：文件夹图标块、标题「File Browser」、副行统计 `{n} files` + 有选中时 `{n} selected`（强调色）、搜索框（`Search files…`，最宽 460）、暂存区按钮（inbox 图标 + 数量圆形角标，选中态高亮）、视图分段（Grid 网格 / List 列表）、Refresh。

**过滤条**：类别分段 `All 全部` / `Images 图片` / `Videos 视频` / `Audio 音频` / `Text 文本` / `Others 其他`；`Sort by 排序` 菜单（Name / Modify Date / File Type + ASC/DESC）；**桌面独有**缩略图尺寸按钮（窄屏隐藏）。

**内容区**：
- 网格视图：`FileCard`（缩略图、文件名、选中态、`Staged` 暂存标记、可拖拽）。
- 列表视图：行（类型图标+色、文件名、副标题 `大小 | 修改时间 | 宽x高 (比例)`、右侧暂存 inbox 徽标 + 选中勾）。
- 空态：居中「No files found」。
- 浮动选择条（底部居中，有选中时出现）：`{n} selected`、`Select All`、`Clear`、`Add to Staging 加入暂存`（全部已暂存时切换态）、`AI Batch Rename AI 批量重命名`。

**选择模式与交互**：
- 单击切换单个文件选中；`Shift+单击` 从上一次普通点击处区间选择；双击 → 图片/视频进媒体预览，其他文件用系统默认程序打开。
- 拖拽：拖动选中集合内的卡片 = 拖整个选择；拖选择外的 = 只拖该文件。拖到左列文件夹上：`Move {n} · hold Ctrl to copy`（按住 Ctrl 转复制）。
- 文件夹也可拖拽移动/复制：`Move "{name}"` / `Copy "{name}"`。

**快捷键（屏幕级）**：`Ctrl/⌘+F` 聚焦搜索；`F5` / `Ctrl+R` 刷新；搜索框聚焦时 `Esc` 清空并失焦；`Ctrl/⌘+A` 全选；`Esc` 清除选择；`Enter` 预览第一个选中项；`F2` 重命名（仅单选）。

**文件右键菜单**（宽 230）：`Open in Preview`（提示 Enter，仅图片）｜`Open with System Default`（媒体/文本）｜—｜`Add to / Remove from Selection`｜`Add to Staging / Add to Staging - {n} / Remove from Staging`｜—｜`Rename`（提示 F2）｜`Copy Filename`｜—｜`Open in Folder`｜`Share / Share selected items (n)`。

**文件夹右键菜单**：`Show only this folder 只看此文件夹`｜`Deselect all directories`｜【有暂存时】`Move {n} here 移动到此` / `Copy {n} here 复制到此`｜`Show in system 在系统中显示`｜`New subfolder 新建子文件夹`｜`Rename`｜`Move to… 移动到…`（根目录时禁用并注 `Root folders cannot be moved`）｜`Remove from list 从列表移除`｜`Delete 删除`。

**文件夹删除对话框**：标题 `Delete folder?` / `Move to trash?`；空文件夹说明；非空时显示盘点：`Subfolders` / `Files` / `Size`（统计中显示 `Counting…`）；按钮 `Delete {n} items` / `Move {n} items to trash`；不可逆提示 `This cannot be undone` 或 `Can be restored from the system trash`。

**文件夹名校验（内联编辑器）**：`Name cannot be empty`、`Name cannot contain {chars}`、`This name is reserved by the system`、`A folder with this name already exists`、`This path is already in the list`。

**暂存区面板 `BrowserStagingPanel`**：
- 头：`Staging 暂存` + 统计行 `{n} items` `· {n} missing` `· {n} already there (skipped)` + `Clear 清空`。
- 空态：`Staging is empty` + 说明（只是记录、不移动文件；换文件夹/筛选/重启都不丢）。
- `DESTINATION 目标` 区：未设置显示 `Not set` + 提示（右键左列文件夹选"移动/复制到此"，或把文件拖到文件夹上）。
- 恢复提示：`Restored {n} from the last session`。
- 条目状态标记：`Already here - will be skipped`、`Missing`；`Remove missing ({n})` 一键清理；每条 `Remove from Staging`。
- 底部：`Move here 移动到此` 主按钮 + `Copy here 复制到此`。
- 自动展开：暂存区首次有内容时自动打开一次（用户手动关掉后不再自动开）。

**移动/复制流程**：
- 前置校验 Snackbar：`Pick a destination folder first`、`The destination folder no longer exists`、`Nothing to transfer`。
- 冲突对话框 `Name conflicts`：副标题 `{n} of {total} clash with names in {folder}`；每条显示 `Incoming · {size} · {date}` 与 `Already there · {size} · {date}`，三选一 `Skip 跳过` / `Overwrite 覆盖`（警告不可撤销）/ `Keep both 两者都留`；未决 `Undecided`；`Apply the same answer to the remaining {n}` 勾选；按钮 `Apply and continue`。冲突原因：`Already in the destination` / `Another staged file has this name` / `Already in this folder` / `Source file is gone`。
- 进度对话框：`Moving {n} items` / `Copying {n} items`、`{from} to {to}`、跨盘标记 `across drives` + 说明与回滚说明、`{done} / {total} items · {doneSize} / {totalSize}`、`Copying {name}`、`Run in background 后台运行`、Cancel。
- 完成对话框：`Move finished` / `Copy finished` / `Transfer cancelled`；`{n} items · {time}`；统计 `Transferred` / `Skipped (already there)` / `Failed`；「失败项仍留在暂存区」说明；`Retry 重试`、`Export log 导出日志`（`Log saved to {path}`）、Finish。

**文件夹移动流程**：进度对话框 `Moving folder {name}` / `Copying folder {name}`、`{n} items`、跨盘说明；取消结果卡：`Move cancelled` / `Copy cancelled`、`stopped at {done} / {total} items`、三行状态 `Copied to destination` / `Not started` / `Kept in source`、说明 + `Show destination in system` + `Got it`。校验失败 Snackbar：`A folder cannot be moved into itself`、`The folder is already there`、`The destination already has an entry with this name`。成功 Snackbar：`Created/Renamed/Deleted/Moved to trash/Moved/Copied {name}`。

**AI 批量重命名对话框 `AiRenameDialog`**（大型对话框，左配置 + 右预览）：
- 左列：`MODEL 模型` 选择器、`NAMING TEMPLATE 命名模板`（来自提示词库 rename 类型；空时 `No prompts saved`）、`EXTRA INSTRUCTIONS 附加说明`、批次预估 `{files} files · {size} per batch · {batches} batches`、`Generate Suggestions 生成建议` / `Stop generating 停止生成` / `Regenerate 重新生成`。
- 头部副标题：`{files} files from {dirs} folders`。
- 右列：过滤分段 `All` / `Conflicts 冲突` / `Skipped 跳过`；`Next conflict 下一个冲突`；每行：原名 → 新名（可内联编辑）、徽章 `Name taken` / `Skipped` / `Renamed`、行内动作 `Accept 接受` / `Skip 跳过` / `Edit name 编辑名称` / `Undo skip 撤销跳过` / `Rename 自动改名` / `Overwrite 覆盖`。
- 状态：生成中 `Generating suggestions` + `Batch {b} / {t} · {done} / {files} produced` + `Stop`；`{n} produced · reviewable now, applied once generation finishes`。
- 失败：`Batch {b} failed · {reason}` + 说明 + `Retry these 重试这些`。
- 底栏：`{n} suggestions` / `{n} skipped` / `{n} conflicts unresolved · they will not be applied`；Cancel + `Apply {n} renames`（窄时 `Apply {n}`）。
- 空态：`No suggestions yet` + 说明（分批生成、可边生成边审核）。
- 无模型态：`No chat model available` + 说明 + `Go to settings 去设置`。
- 未选模板校验 Snackbar：`Please select a rename template first.`；提交后 `Task submitted to queue`。

---

## 2.3 批量任务队列 Tasks

**桌面/平板（≥600）**：
- 头部：标题「Task Queue Manager」+ 五个计数（Processing / Pending / Completed / Failed / `{n} total`）+ `Cancel All Pending 取消全部待处理` + `Clear Completed 清除已完成`（另有 `Clear All` 及确认）。
- 过滤 + 排序行：左侧筛选胶囊 `All` / `Processing` / `Pending` / `Completed` / `Failed`（横向滚动，边缘渐隐）；右侧排序分段 `Newest first 最新在前` / `Oldest first 最早在前` + `Pin running & pending 置顶运行中与等待中` 开关（**仅"全部"筛选下出现**）。
- 列表：任务卡（按 id 保持展开状态跨排序移动）；置顶组与其余组之间有分隔 `Rest by creation time`。
- 底部执行控制台。

**手机（<600）**：AppBar 标题 + 缩写计数行（`run` / `wait` / `done` / `fail` / `{n} total`）+ 单个 `⋮` 菜单（Sort 排序区两个单选行、Pin 开关、`Cancel All Pending`、`Clear Completed`）；下方 58px 高筛选胶囊条（横向滚动，右缘渐隐）；任务卡列表更紧凑。

**任务卡**（可展开）：
- 折叠行：类型图标、模型名（mono）、渠道标签色、状态胶囊、事实行（`{n} files`、`#{p} in queue` 排队位、`Cancelled · manual`、`took {duration}`、`Retry Count: {n}`）、进度条、`Latest Log:` 单行、`⋮` 菜单。
- 展开：`Model` / `Created` / `Started` / `Finished` / `Elapsed` / `Config` / `Source files` / `Prompt` 事实表；`Request parameters 请求参数`；`Output files 输出文件`（可点开文件夹）；`EXECUTION LOGS` 区（`Copy all`；空 `This task has logged nothing yet`）。
- 失败态额外：`Retry 重试`、`Copy the error 复制错误`、`Open in Folder`、`Remove from list`。
- `⋮` 菜单：`View Log 查看日志`、`Cancel Task 取消任务`（红）、`Retry`、`Remove from list`、`Copy prompt 复制提示词`。
- 任务日志对话框：标题 `Task Log`、`Task ID: {id}`、运行中徽章 `Live`、`{n} lines`、`Copy logs`、Close；空态 `No log recorded for this task.` + 说明。

**空态**：
- 整体为空：checklist 图标 + `No tasks in queue` + `Submit a task from the Workbench to see it here.` + `Go to the workbench 去工作台`。
- 筛选后为空：`No running/pending/completed/failed tasks` + 说明（其余 n 条不受影响）+ `View all 查看全部`。

**通知**：系统通知 `Task Completed` / `Task Failed`（可在设置中关闭）。

---

## 2.4 图片下载器 Downloader（**桌面/平板专属**，移动端导航中隐藏）

单列结构：工具条 → （iOS 提示条）→ 选项条 → 日志面板 → 结果区 → 底部执行控制台。

- **工具条**：标题「Image Downloader」；`Website URL 网址`输入（hint `https://example.com`）；`What to find? 要找什么`输入（hint `e.g. all product gallery images`）；`Analysis Model 分析模型` 选择器；`Find Images 查找图片` 主按钮（运行中变 `Analyzing...`）；`Advanced Options 高级选项` 齿轮。
- **高级选项对话框**：`Filename Prefix 文件名前缀`；`Cookies (Raw or Netscape format)` 多行输入；`Import Cookie File 导入 Cookie 文件`（失败/成功提示）；`Cookie History Cookie 历史`（空 `No cookie history saved`）；Finish。
- **选项条**（高 40）：`Manual HTML Mode 手动 HTML 模式` 开关 + `Paste from Clipboard 从剪贴板粘贴` + Clear；`Save Origin HTML 保存源 HTML`；`Logs 日志` 开关。
- **日志面板**（高 196，动画展开）：终端图标 + `Logs` + 分析中细进度条 + `Copy logs` + Close。
- **结果区**：头行 `Select images to download 选择要下载的图片` + `({n} selected)` + `Select All` + `Add to Queue 加入队列`；网格图片卡（可勾选，右键 `Open Raw Image 打开原图`）；状态行 `{found} found · {selected} selected`。
- **空态引导**：`No images discovered yet.` + 三步卡：`1 · Enter a URL` / `2 · Describe what to find` / `3 · Pick & download`。
- **校验 Snackbar**：URL 无效、需求为空、手动模式未粘贴 HTML、`No models configured`（带「Settings」跳转）、`Please set output directory in settings first.`；成功 `Added {n} images to download queue.`
- iOS 上方常驻输出目录建议条。

---

## 2.5 提示词库 Prompts

三个数据视图：**User Prompts 用户提示词** / **System Templates 系统模板** / **Categories 分类**。

**桌面/平板（≥600）** 两栏：
- 左栏（宽度可拖拽持久化）：头行（图标块 +「Prompt Library」+ `Categories` 切换按钮）；下方 `PromptsSidebar` —— `All 全部`（总计数）+ 各分类行（带计数、颜色圆点）+ `Match: Any 任一 / All 全部` 匹配模式分段 + `Clear 清除`。
- 右栏：56px 头行 + 内容。头行（按**实测宽度**在 560px 处折叠，不按断点）：
  - 常态：`User Prompts / System Templates` 分段 + 搜索框（`Filter prompts...`）+ 导入/导出（宽时两个按钮，窄时合为 `⋮` 菜单）+ `New Prompt` / `New Template` / `Add Category` 主按钮。
  - 分类标签下：分类图标 + `Categories` + `Add Category`。
  - 选择模式下：关闭 ✕ + `{n} Selected` + `Categorize 分类` + `Delete 删除`（红）。
- 平板附加：在 User Prompts 标签下额外显示一条横向分类筛选条。

**手机（<600）**：`SliverAppBar`（标题 `Prompt Library` / 选择模式时 `Selection Mode`；actions：导入导出菜单 + `+`）；bottom 固定搜索框 + 三段 TabBar；User Prompts 下附横向分类筛选条；选择模式时底部居中浮动胶囊条（✕ + `{n} Selected` + 分类图标 + 删除图标）。

**列表项 `PromptCard`**：标题、内容摘要、分类标签芯片、选中态、`Move to Top 置顶` / `Move to Bottom 置底` 按钮，长按拖拽排序（有筛选或搜索时禁用并提示），点击复制标题 Snackbar `Copied: {text}`。
- System Templates 额外有类型分段 `Prompt Refiner 提示词优化` / `Batch Rename 批量重命名`，以及 `All` 筛选。

**空态**：`No prompts saved` + 说明 + `Create First Prompt` / `New Prompt`。

**对话框**：
- 新建/编辑提示词：`Title 标题`、`Tag (Category)` 多选芯片、`Prompt Content`（MarkdownEditor）；Cancel / Save·Update。
- 新建/编辑系统模板：`Title`、`Template Type`（Prompt Refiner / Batch Rename）、`Tag (Category)`、`Prompt Content`。
- 新建/编辑分类：`Name 名称` + 色相选择；删除提示 `Delete category "{name}"? Prompts will be moved to General.`
- 删除确认：`Delete Prompt?`；批量 `Delete {n} prompts?` + `This action cannot be undone.`
- 批量分类 `Bulk Categorize`：选择分类 + Apply。
- 导入模式 `Import Mode`：说明 → `Merge 合并` / `Replace All 全部替换` / Cancel；结果 Snackbar。

---

## 2.6 模型与渠道 Models

**桌面/平板（≥600）** 主从两栏：
- 左栏 Channels（宽度可拖拽持久化）：56px 头行 —— 「Channels」+ 副行 `{models} models · {channels} channels` + `Add Channel 添加渠道` 按钮；搜索框 `Search channel name or tag...`；渠道列表（头像色块、名称、标签、模型数、拖拽把手 `Drag to reorder`）；底部入口 `Fee Management 费用管理` + `{n} groups`。
- 右栏（选中渠道的模型）：
  - 头行：渠道名、`Fetch Models 获取模型`（**桌面显示文字、平板仅图标**）、`Edit 编辑`、`⋮`（`Delete` 红）。
  - 类型筛选芯片：`All` / `Chat` / `Image` / `Video` / `Multimodal`（各带对应色）。
  - 搜索框 `Filter models...` + `Add Model 添加模型`。
  - 模型卡：显示名、Model ID（mono）、类型标签、能力芯片 `Streaming` / `Standard requests` / `Reasoning · {level}` / `Web search` / `All ref images`、费用组名（无则 `No Fee Group`）、协议固定失效徽章 `Selection inactive`；行内 Edit / Delete。
  - 空态：`No models configured` / `Select a channel` / `No matches`。

**手机（<600）**：`SliverAppBar`「Model Manager」+ 两段 TabBar（Models / Channels），各自列表。

**添加渠道向导 `ChannelWizardDialog`**（分步）：
- 步骤 `Choose Provider 选择供应商`：搜索、统计 `{n} providers · {m} groups`、分组 `Vendors 厂商` / `Relays 中转` / `Custom 自定义` / `Local 本地`；每项标注 `Key only` / `Needs address` / `No key`、`{n} ways in` 多入口、`Deprecated` 弃用；无匹配提示。
- 变体选择（如 Google）：`Access method 接入方式` / `Interface 接口` / `Endpoint format 端点格式` + 说明。
- 步骤 `Endpoint & key` / `Connection & appearance`：`Endpoint URL`（预填 + 覆盖提示、`Restore preset value`、`Address edited` 徽章）、`API Key`（本地服务可留空；存储声明）、`Test connection 测试连接` → 结果 `Connected and authenticated` / `{n} models found` / 连接但无模型 / 鉴权失败 / 不是 API / 不可达 / 不支持 + `Retry`。
- `Tag & Appearance 标签与外观`：`Name`、`Tag`、`Tag Color 标签颜色` + `More colors` / `Custom color`、`List preview 列表预览` 卡片。
- `Enable Model Discovery 启用模型发现` 开关 + 说明。
- 步骤 `Preview 预览`：`Ready to add this channel?`；校验 Key/端点必填；Back / Next / Add。
- 编辑渠道 `ChannelEditDialog`：分区 `Basic Info` / `Configuration` / `Tag & Appearance` / `Billing`；`Provider preset 供应商预设`（一键填充、`Change preset` + 覆盖警告、无匹配提示）；`API protocol 接口协议`（OpenAI Compatible (REST) / Google GenAI (REST) / Anthropic Messages / Midjourney Proxy / xAI）。

**模型编辑对话框 `ModelEditDialog`**：
- `Model ID`、`Display Name`、`Channel`、`Tag`、`Fee Group 费用组`。
- `Capabilities 能力`：`Supports Streaming` / `Supports Standard Request`。
- `Context Window 上下文窗口`：`Not set` / `Specify`（`Max context` + `{n} tokens`）/ `Unlimited`；图像/视频模型有各自提示；用途说明。
- `Agent Behavior 代理行为`：`View all reference images 查看全部参考图`。
- `Reasoning Effort 推理强度`：Default / Off / Low / Medium / High / Max + 说明。
- `Extended thinking 扩展思考`（仅 Anthropic 格式）、`Host web search 供应商联网搜索`。
- `Request Method 请求方式` / `API Protocol 接口协议`：`Auto 自动`（`Auto · resolves to "{name}"`）或显式 —— OpenAI-compatible / Anthropic-compatible / DashScope native / Synchronous / Async task / Image via chat reply / Images API / Imagen / Videos API / Veo / xAI Images / xAI Video / MiniMax Images / MiniMax Video；附参数摘要 `Parameters` / 无专属参数 / 参考图上限；异常提示（无接口、对话出图不太可能、未识别按自动、流式被忽略）、`Back to Auto`。
- `Card preview 卡片预览`；保存校验提示。

**模型发现对话框 `DiscoveryDialog`**：`Discovering Models...`、`Select models to add`、搜索、`{n} models discovered`、已存在标 `Already Added`、`Select All` / `Deselect All`、`Add Selected ({n})`；空 `No new models found.`；失败提示。

**费用管理 `PricingGroupManager`**（对话框 / 用量页内嵌两种模式）：
- 列表：组名、`{n} models` 使用数、未使用标 `Not used by any model`；`Add Fee Group` / `Edit Fee Group` / 删除确认；空 `No fee groups created yet`。
- 编辑器：`Group Name`；`Billing Mode 计费模式` = `Per Million Tokens` / `Per Request`；Token 模式字段 `Input Price ($/M Tokens)`、`Cached Input Price`（留空则按输入价）、`Output Price`；按次模式 `Request Price ($/Req)`；价格标签行 `Input / Cache / Output / Request`。

---

## 2.7 用量统计 Usage

**手机（<600）**：AppBar「Token Usage Metrics」+ 两段 TabBar（Usage 用量 / Fee Groups 费用组）；Fee Groups 为内嵌费用管理。

**桌面/平板（≥600）**：画布上浮的下划线式标签（Usage / Fee Groups，故意放在卡片外，切换时不位移）+ 内容。
- **平板（600–999）**：Usage 走窄版卡片。
- **桌面（≥1000）**：滚动卡片流：
  1. 英雄卡：`Estimated Cost 预计花费`（大数）+ 区间标签 + `{n} Requests` + 三色 Token 统计 `Input Tokens` / `Cached Input` / `Output Tokens` + `Cache Hit Rate 缓存命中率`（tooltip）。
  2. 画布工具行：左侧解析出的日期区间（mono）；右侧区间分段 `Today` / `Last Week` / `Last Month` / `This Year`（加载中禁用）、Refresh、`Clear All`（红，确认）。
  3. `Usage by Group 按组统计`（有数据才显示）。
  4. 记录表：表头 `Model` / `Detail 明细` / `Time 时间` / `Cost 花费`；按日分组（`Today` / `Yesterday` / 日期 + `· {n} records`）；行内展开显示 `{n} items`、`Input Tokens: n`、`Cached Input: n`、`Output Tokens: n`；行尾 `Clear Model Data 清除该模型数据`（确认）；分页 `Load More 加载更多`（每页 100）。
- 加载态：卡片内居中圆形进度；空态：`No usage data in the selected range.`
- 价格输入校验：`Enter a valid non-negative number`。

---

## 2.8 设置 Settings

**手机（<600）**：`SliverAppBar.large`「Settings」+ 五行分类列表（各带彩色图标块与 `>`），点击 push 到详情页（AppBar 为分类名）。
**平板/桌面（≥600）**：两栏卡片 —— 左导航卡（平板宽 200 / 桌面宽 232）+ 右内容卡；左卡头行「Settings」；导航项选中态为强调色薄底 + 描边；右卡 56px 分类头行 + 滚动内容（最大宽 720，居中）。

**① Appearance 外观**
- `Appearance 主题模式` 分段：`Auto 自动` / `Light 浅色` / `Dark 深色`。
- `Theme Color 主题色`：双色卡/色点选择器（每个主题色含浅色与深色两档校准值，`Light {l} · Dark {d}`；长按查看数值；`Custom… 自定义`——**现为禁用占位**）+ 说明。
- `Font 字体`：`System Default 系统默认` + 可下载字体；未下载时弹 `Download Font` 对话框（含大小 MB）→ `Downloading font…` 进度 → 失败提示。
- `Language 语言`：Auto + 各语言卡片。
- `Reduce visual effects 降低视觉效果` 开关（关闭模糊）。

**② Connectivity 连接**
- `Proxy Settings 代理设置`：`Enable Global Proxy` 开关；`Proxy URL (host:port)`、`Proxy Username (Optional)`、`Proxy Password (Optional)`（可见性切换）。
- `MCP Server Settings MCP 服务器设置`：`Enable MCP Server` 开关 + `Port 端口`。

**③ Application 应用**
- `Enable System Notifications 启用系统通知` 开关。
- `Enable API Debug Logging 启用 API 调试日志` 开关 + 说明（含敏感数据警告）+ `Open Log Folder 打开日志文件夹`。
- `Portable Mode 便携模式` 开关 + 说明；切换后 `Restart Required` 对话框 + `Exit`。
- `Rendering GPU 渲染 GPU` 只读信息（无法确定时 `Could not be determined`）+ `Windows graphics settings`。
- `Output Directory 输出目录` 选择（未设 `Not set`；iOS 附建议）。
- `Knowledge Base Folder 知识库文件夹` 选择 + `Open Folder`；无效态 `Folder not found` / `README.md entry file not found in the folder`。
- `Assistant Summary Limit 助手摘要阈值` 滑杆 + 说明。
- `Knowledge Sub-agent 知识子代理` 开关 + 说明（实验性）；`Sub-agent Model 子代理模型` 选择器（`Follow session model` / 搜索模型；绑定模型消失时提示）。
- `Assistant Conversations to Keep 保留的助手对话数` + 说明（超出自动删除）。

**④ Data Management 数据管理**
- `Export Settings 导出设置` → `Export Options` 对话框：`Include Directory Config`、`Include Prompts`、`Include Usage Metrics` + `Export Now`；成功提示。
- `Import Settings 导入设置` → `Import Options` 对话框（同三项，备份中缺失项标 `Not available in backup file`）+ `Import Now`；确认 `Import Settings?` + `Import & Replace`；错误：仅提示词文件 / 不是备份 / 更新的 schema。
- `Open App Data Directory 打开应用数据目录`。
- `Clear Temporary Files 清理临时文件`：确认对话框（蒙版、裁剪副本、下载器缓存、视频缩略图；临时工作区中指向它们的条目一并移除）→ `Freed {size}.`
- `Run Setup Wizard 运行设置向导`。
- `Reset All Settings 重置全部设置`（红）：确认 + `Reset Everything`。

**⑤ About 关于**：App 图标 + `Joycai Image AI Toolkits` + `Version {v}` + `GitHub Repository` / `View source code and releases` + `License` / `Copyright © {year} {holder}. Released under the MIT License.`

---

## 3. UI 暴露的数据实体

### 3.1 任务 Task

- **5 种类型**：`imageProcess` 图像处理、`imageDownload` 图片下载、`promptRefine` 提示词精修（助手每一回合）、`aiRename` AI 批量重命名、`videoGenerate` 视频生成。每种在任务卡与胶囊中有独立图标。
- **5 种状态**：`pending` 等待（`Pending` / 缩写 `wait`）、`processing` 运行中（`run`）、`completed` 已完成（`done`）、`failed` 失败（`fail`）、`cancelled` 已取消（手动取消显示 `Cancelled · manual`）。
- 字段：id、type、源文件、请求参数（含 prompt 及助手溯源标签 sessionId / version）、模型显示名、渠道标签与颜色、useStream、日志、输出、创建/开始/结束时间、进度、重试次数、异步视频任务的下发通道。
- 事件流：文本增量、图像结果、进度、状态变更、错误。

### 3.2 提示词 / 标签 / 系统模板

- `Prompt` 用户提示词：id、title、content、sortOrder（可拖拽排序）、isMarkdown、tags[]。
- `SystemPrompt` 系统模板：同上 + `type` = `refiner`（供提示词助手）/ `rename`（供 AI 批量重命名）。
- `PromptTag` 分类：id、name、颜色（色相选择器）；删除分类时其提示词落回 General。
- 筛选：多标签 + `Match: Any / All` 模式；搜索按标题/内容。
- 导入导出：独立于全局备份，Merge / Replace All 两种模式。

### 3.3 模型 / 渠道 / 费用组

- `LLMChannel` 渠道：displayName、tag、tagColor、endpoint、apiKey、协议族（OpenAI REST / Google GenAI REST / Anthropic Messages / Midjourney Proxy / xAI）、provider preset、启用模型发现、排序位置。
- `LLMModel` 模型：modelId、displayName、channelId、类型标签 `chat` / `image` / `video` / `multimodal`、能力（streaming / standard request）、contextWindow（unset / specify / unlimited）、reasoningEffort、extended thinking、host web search、force view all images、pricing group、显式 wire protocol 固定值（可 Auto）。
- `PricingGroup` 费用组：名称、计费模式（token / request）、input / cachedInput / output 单价或 request 单价；显示被多少模型引用。

### 3.4 用量记录 Usage

- 单条：模型、时间、input_tokens、cached input tokens、output_tokens、request_count、计算花费。
- 聚合：按日分组、按费用组分组、区间统计（today / week / month / year）、缓存命中率、用量检查点（>500 条自动落盘）。
- 可按模型清除，或全量清除。

### 3.5 知识库 Knowledge Base

- 根目录（设置中指定）+ 入口文件 `README.md`；状态 = ok / notSet / missingDir / missingEntry。
- 文档树：文件与目录计数、内容更新时间、重新扫描。
- Agent 可读（list / read）与可写（write，需 `Write permissions` 三开关：允许写入 / 每次确认 / 写前保留 `.bak`）。
- 待处理改写状态 = pending / applied / rejected / failed；可逐条或 `Write all` / `Discard all`。
- 初始化脚手架：向空文件夹写入示例规则文件。
- 会话蒸馏：把本次会话的经验写回知识库。

### 3.6 会话 Session（提示词助手）

- 会话：id、title（可重命名）、模式 = systemPrompt / knowledgeBase / knowledgeEdit（模式随会话固定，切换即新会话）、消息历史、渲染条目、提示词版本数、最新成品、isRunning、是否已压缩、待答提问、写入策略。
- 持久化：会话元数据（id、mode、title、updatedAt、参考图路径列表）+ 消息（含摘要标记）；保留条数由设置控制，超出自动删除。
- 溯源：`result path → prompt version` 映射，驱动画廊卡片的 `v{n}` 角标与结果反馈的版本绑定。
- 参考图与结果图分列，结果图携带用户反馈文本。

---

### 附：跨屏共用组件（重设计时需统一）

`AppButton`（primary/secondary/text/destructive/destructiveText，normal/compact）、`AppIconButton`、`AppToolButton`、`AppSegmentedControl`（tinted / raised，compact / iconOnly）、`AppSwitch`、`AppDropdown`、`AppTextField` / `AppSearchField` / `ApiKeyField`、`AppLabelledField`、`AppCard` / `AppSection` / `AppSectionLabel` / `AppSettingRow` / `AppToggleRow` / `CollapsibleCard`、`AppStatusBadge`、`AppCountBadge`、`AppEmptyState`、`SearchablePickerField`（带搜索的选择器对话框）、`MarkdownEditor`、`PanelCard` / `PanelResizer`（列式分隔条，24px 拖拽余量）、`ScrollEdgeFade`（滚动边缘渐隐）、`SmoothProgress`、`ThumbnailFitToggle`、`ColorPickerWidget` / `ColorHuePicker` / `ThemeAccentPicker` / `DualToneSwatch`、`DashedBorder`（投放区）、`DrawingCanvas`。
