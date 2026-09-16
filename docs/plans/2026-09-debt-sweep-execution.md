# 执行文档：欠账清扫（2026-09-16）

> 施工中的对照表。来源是 [`README.md`](README.md)「还欠的」与 [`../../plans/README.md`](../../plans/README.md)
> 「还欠的」，按用户点的三组（① 直接可修的代码问题、② 动效、④ 需要先决策的）排。分支
> `claude/debt-sweep-4.9`，**一片一个 commit**，commit 正文带片号；每期结束跑一次 code review
> 再进下一期；最后 bump version（minor，4.9.0）并开 PR。执行完毕本文件退役，结论回写
> 架构文档与两本台账。

## 不变量（施工时逐条对照，偏离即停）

1. 每片：`flutter analyze` 零问题，`flutter test -x screenshots` 绿；涉及 l10n 的片四语同改并
   `dart tool/merge_l10n.dart && flutter gen-l10n`。
2. 分层照 `test/source_layout_test.dart`：services 不读 AppState；`widgets/{ui,glass,drag}` 只引
   core / l10n / 自己；共享 widget 不引 screen。
3. state 改列表一律换新实例再 `notifyListeners()`（`LogState` 是写明理由的例外，不动）。
4. 动效时长一律经 `AppMotion.durationOf` / `sceneOf`，档位照 `design-tokens.md` §4。
5. 拆文件只搬家：元素树一个节点不变，私有 static 变库私有顶层，State 的 builder 变具名
   extension；**`llm_dispatcher.dart` 不拆**（唯一路由表）。
6. LLM 层：不在协议里比较 `vendor.id`；需要按 vendor 分的地方读 `VendorProfile` 的声明或
   `LLMDispatcher` 的谓词。
7. 不对 `dart format` 整个文件——只格式化自己写的块，免得 diff 被重排淹没。

## 与台账不符、施工前已核实的

- 「视频提交、Midjourney 提交与各轮询 GET 未走 `sendJsonRequest`」**已经不成立**：六个协议的提交与
  轮询全部经 `sendJsonRequest`（OpenAI 视频的 multipart 提交走 `AbortableMultipartRequest`，同样可中止）。
  只在收尾片里改台账。
- `docs/plans/2026-08-assistant-timeout.md` 第 5 节「① 的累积器」仍是 ⬜，实际已由
  `protocols/streaming_tool_calls.dart` 落地；收尾片改勾。
- Cookie 除了 `downloader_cookies`，还随下载任务的 `parameters` 落进 `tasks` 表，而「重置数据」
  刻意保留 `tasks`——S3 一并处理。

## 决策记录

- **S1（API key 明文）走「明说 + 收紧文件权限」，不上系统钥匙串。** 理由：macOS 构建是 ad-hoc
  签名（`project.pbxproj` 的 `"-"`），`flutter_secure_storage` 在 macOS 默认用 data-protection
  keychain，没有 `keychain-access-groups` 权限会直接失败，退回旧 keychain 则每次重签都弹授权；
  Linux 构建没装 `libsecret`，最小桌面上也常无 keyring 守护进程；便携模式（`.portable`）下数据库跟着
  exe 走、钥匙串不会。三处都得回退到明文，等于只在 Windows/移动端生效却多一个原生依赖。
  台账本身给了「要么换钥匙串，要么首次配置时明说」两条路，这里取后者，并把能做的物理防护做掉：
  数据库文件与数据目录在 macOS/Linux 上收紧到仅属主可读写；现有「本地保存、不上传」的文案改成
  如实说明「未加密保存在本机数据库、不进备份」。另：代理密码 `proxy_password` 同为明文，导出时
  一并置空。
- **S3 同理不做加密**，做生命周期：保留期设置（不记住 / 7 天 / 30 天默认 / 一直）、历史里逐条删除、
  设置「数据」里「清除 Cookie 历史」、下载任务落库前剥掉 `cookies` 参数。
- **D2a 三条**：设计稿这轮读不到（DesignSync 未授权），按 `design-tokens.md` 的规则实现——引导线
  静止 `outlineVariant`、父开关开时补间到 `primary`（M2）；选中项 check 用 `onAccentTint`、底用
  `accentTint`（阶梯上没有 10%，12% 是最近的一档）；点单态协议值用 `accentText`。数值未对照稿复核，
  已在台账注明。

## 分片

### 第一期：直接可修的代码问题

| 片 | 内容 | 涉及文件 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | state 换新列表：视频参考图增删、`GalleryState.toggleDirectory`、下载器日志 | `state/workbench_ui_state.dart` · `state/gallery_state.dart` · `state/downloader_state.dart` | `test/state_list_identity_test.dart` | ✅ |
| 2 | 视频面板桌面分栏：头部内容放不下时整栏单滚动，不再把参考图卡裁成一条 | `screens/workbench/widgets/video_config_panel.dart` | 1440 截图参考图区完整；`test/video_panel_head_fit_test.dart` | ✅ |
| 3 | AI 重命名「覆盖」禁用态的测试：给 `AiRenameDialog` 留 `@visibleForTesting` 初始行入口 | `screens/browser/ai_rename_dialog.dart` · 新测试 | `test/ai_rename_overwrite_ui_test.dart`（去掉禁用即失败） | ✅ |
| 4 | 截断标记跨重启：`LLMMessage` JSON 带可选 `truncated` / `modelDbId`，恢复时读回 | `llm_types.dart` · `prompt_optimizer_session.dart` · `prompt_optimizer_agent.dart` | `optimizer_truncation_test.dart` 两条：重启往返、旧行无键 | ✅ |
| 5 | 按节写入的预览标明位置：条目带 `KbEditScope` + 节标题，卡片头下一行写「替换小节 / 追加到小节 / 追加到文件末尾」，每个 hunk 头带所在标题（`@@ -a +b @@ ## 节`） | `prompt_optimizer_session.dart` · `assistant_tool_calls.dart` · `knowledge_base_service.dart`（`headingAbove`）· `optimizer_kb_edit_card.dart` · l10n workbench | `optimizer_kb_section_scope_test.dart`；卡片两条；`headingAbove` 一条 | ✅ |
| 6 | ① 「no choices」等裸 `Exception` 改 `LLMApiException`；`LLMMessage.fromJson` 未知 role 抛 `FormatException` | 九个协议里的 `throw Exception(`（Midjourney 提交被拒标 `isEnvelope`）· `llm_types.dart` · `assistant_session_repository.dart`（注释） | `test/llm_typed_failures_test.dart` | ✅ |
| 7 | 非 Anthropic vendor 的 ④ 面不发 `web_search`：`VendorProfile.webSearchOn(face)` 成为编辑器（经 `serverWebSearch`）与三个 payload 的同一个答案 | `vendor_profile.dart` · `llm_dispatcher.dart` · `anthropic_payload.dart` · `openai_chat_payload.dart` · `dashscope_chat_protocol.dart` | `server_web_search_test.dart` ④ 组（去掉闸门即失败） | ✅ |
| R1 | 第一期 code review，修 CONFIRMED 项 | `optimizer_kb_edit_card.dart` | 1 条：只删行的 hunk 头标成了下一节 → 从缺口前一行找标题；测试一条 | ✅ |

### 第二期：动效

| 片 | 内容 | 涉及文件 | 验收 | 状态 |
|---|---|---|---|---|
| 8 | 加载 → 网格：网格接替占位时淡入（M2），网格常驻时不重播 | `screens/workbench/gallery.dart` | `test/gallery_reveal_test.dart` | ✅ |
| 9 | 两棵树的展开箭头改旋转（`AnimatedRotation` + M2） | 新原语 `widgets/ui/app_disclosure_chevron.dart` · `folder_tree_row.dart` · `knowledge_tree_panel.dart` | `test/app_disclosure_chevron_test.dart` | ✅ |
| 10 | `ScrollEdgeFade` 两端强度补间（M1）；顺带：子组件用 GlobalKey 跨「无遮罩 / 有遮罩」两种结构，列表不再在开始溢出时被重建 | `widgets/ui/scroll_edge_fade.dart` | `scroll_edge_fade_test.dart` 加两条（去掉 key 即失败） | ✅ |
| 11 | 胶囊内容区 `AnimatedSize`：用户点开 / 收起仍 M3（与宽度同步），其余（运行数跨 0）降到 M2 | `widgets/tasks/task_capsule_monitor.dart` | `task_capsule_bounds_test.dart` 加一条 | ✅ |
| 12 | 选择栏退场：滑动与淡出同一时钟（新 `AppMotion.sceneFor(entering:)`） | `design_tokens.dart` · `browser_selection_bar.dart` · `gallery_selection_bar.dart` | `test/selection_bar_exit_clock_test.dart` | ✅ |
| 13 | 渠道向导步骤切换带方向（前进右入、后退左入，位移 5% 宽，M2） | `channel_wizard_dialog.dart` | `channel_wizard_dialog_test.dart` 加一条 | ✅ |
| 14 | 用量比例条 0 → 值生长（M3）；换区间时从旧值滑到新值（同一个 tween，未单独区分） | `usage_chrome.dart`（`UsageShareGrow`）· `usage_summary.dart` · `usage_group_costs.dart` | 两个测试的 pump 改 settle；新增生长一条 | ✅ |
| R2 | 第二期 code review | `task_capsule_monitor.dart` · `knowledge_tree_panel.dart` · `channel_wizard_dialog.dart` | 3 条：胶囊逐帧重判时长会在展开途中换曲线 → 计时器保持 M3 整段；知识库树行无 key，箭头转到没点的文件夹上 → 按路径 key；向导快速前进又后退时两个同 key 副本同向 → 每次切换一个序号、按序号记方向。各一条测试（去掉修复即失败） | ✅ |

### 第三期：需要先决策的

| 片 | 内容 | 涉及文件 | 验收 | 状态 |
|---|---|---|---|---|
| 15 | S1：文案如实（向导、渠道编辑框、首次配置三处）、数据库 600 与数据目录 700（macOS/Linux，便携模式只收紧文件）、导出置空代理密码且恢复时保留本机的 | `database_service.dart` · `channel_edit_dialog.dart` · `setup_wizard.dart` · l10n models | `test/data_secrets_test.dart`（五条） | ✅ |
| 16 | S3：新 `CookieRepository`（保留期 不记住 / 7 天 / 30 天默认 / 直到清除，读时裁剪；逐条删除；清空）；历史面板加保留期分段与每行移除、全部清除；设置「数据」加「清除 Cookie 历史」；任务行落库剥掉 `cookies`、启动时清洗旧行，重启后恢复的下载按页面 host 回查历史 | `repositories/cookie_repository.dart` · `task_repository.dart` · `database_service.dart` · `task_executors.dart` · `downloader_state.dart` · `downloader_advanced_dialog.dart` · `data_section.dart` · l10n downloader / settings | `cookie_retention_test.dart`（八条）· `downloader_cookie_history_ui_test.dart`（390 / 1280） | ✅ |
| 17 | `runTurn` 拆出系统提示、前导、单个调用分派三个私有方法（控制流不变） | `prompt_optimizer_agent.dart` 及 part | 助手全部测试绿 | ☐ |
| 18 | 先用 `render_probe` 量助手视图；把知识库编辑卡抽成独立 widget（diff 按条目缓存） | `optimizer_kb_edit_card.dart` · `prompt_optimizer_view.dart` · `render_probe.dart` | 量前量后数字写进施工记录 | ☐ |
| 19 | D2a 三条：引导线与缩进、菜单选中 check、点单态值用主色深 | `model_edit_controls.dart` · `model_edit_capabilities.dart` · `model_protocol_section.dart` · `model_edit_identity.dart` | 组件画廊 / 编辑器截图 | ☐ |
| 20+ | 1000–1500 行文件拆分，一文件一片（有接缝的才拆；单张表 / 注册表记理由不拆） | 见施工记录 | 搬家不改行为，截图像素一致 | ☐ |
| R3 | 第三期 code review | — | — | ☐ |

### 收尾

| 片 | 内容 | 状态 |
|---|---|---|
| 21 | 台账改写（两本）、架构文档、CLAUDE.md map；本文件退役 | ☐ |
| 22 | bump version 4.9.0，推送，开 PR | ☐ |

## 施工记录

（偏离计划处与量出来的数字记在这里。）

- 片 5：`TextDiff.unified` 本来就只出变动的 hunk（上下各 2 行），台账说的「整文件 diff」并不是把整个文件摊开；
  长文件里真正缺的是「这是哪一节」。所以没有改成只 diff 节的片段（那样 hunk 行号会与文件对不上，
  应用路径看到的也仍是整文件），改为在卡片与 hunk 头上标出位置。
- 片 7：原计划「编辑器保存时不支持即清零」没做。线上闸门已经让存着的开关无害，而百炼同一个模型在
  ①/原生面上这个开关是有效的——在 ④ 与 ① 之间来回切协议时清掉它，会悄悄丢掉用户的选择。
