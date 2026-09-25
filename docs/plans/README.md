# 方案与审计台账

`docs/plans/` 放的是**一次性的施工说明书**：某轮改动开工前写的高层设计与分期计划。
落地之后真正的记录在代码、测试和提交信息里，正文留着只会随重构烂掉——2026-09-12
清理时，八份已执行完毕的方案与三份已过期的审计报告一并删除，`plans/README.md`
（动效台账）是同一套做法。

需要回看时从 git 里取，全部在 `f709059`（清理前的 main）上是齐的：

```bash
git show f709059:docs/plans/                                  # 九份方案
git show f709059:docs/plans/2026-09-llm-endpoint-audit.md
git show f709059:docs/reports/code-review-report-20260613.md  # 三份审计
git show f709059:docs/reports/api-standards-audit.md
git show f709059:docs/reviews/2026-08-ai-capability-review.md
git show 59e392c:docs/plans/2026-09-large-file-split.md          # 大文件拆分（八片，每片的做法与发现）
```

留在这份文件里的，是**不随代码走的那部分**：哪一轮做了什么、结论现在住在哪、
以及还欠什么。

## 还在这个目录里的

| 文件 | 为什么留着 |
|---|---|
| [`2026-08-assistant-timeout.md`](2026-08-assistant-timeout.md) | 不是施工说明书，是**一次真实故障的取证记录**（`api_logs/` 里七条日志的耗时还原）。`architecture/assistant-context.md` 直接引它作为「为什么要早elide」的证据。 |

## 已执行（不要重复立项）

| 方案 | 做了什么 | 结论现在住在哪 |
|---|---|---|
| `2026-08-ai-improvement-plan.md` + `2026-08-ai-capability-review.md` | M1 五个 P0 bug、M2 协议层四个共享机制（`LLMApiException` / `decodeJsonBody` / SSE 骨架 / 日志脱敏）与纪律清零、M3 三期子代理 | `architecture/llm-three-layer.md`、`architecture/assistant-context.md`；代码见 `protocols/protocol.dart`、`sub_agent_runner.dart`、`repositories/assistant_note_repository.dart`、`delegateToolFor` 的 `knowledge` / `draft` 两个 kind |
| `2026-08-vendor-protocol-model-refactor.md` | `WireProtocol` + 按 surface 解析协议、v36 `wire_protocol` 列、dashscope 三协议、模型编辑器四态 | `architecture/llm-three-layer.md`。文档最后的「未实现」两条（C 期 MiniMax 视频、`VideoJobProtocol.cancel`）**现在都已实现**（`minimax_video_protocol.dart`、`protocol.dart:150`），状态行本身已经过期 |
| `2026-08-dashscope-native-image.md` | qwen-image / wan 原生出图：一个 vendor + 一个 protocol，不新增 `ProtocolFamily` | `protocols/dashscope_images_async_protocol.dart`、`vendors/vendors.dart`。§7 的第 3 条并入下面「还欠的」 |
| `2026-09-llm-endpoint-audit.md` | 十二片 L1 全部落地（分支 `fix/llm-endpoint-audit`，一片一个 commit） | 协议事实回写进了 [`../api/`](../api/)。第 3 节的实机清单并入下面「还欠的」 |
| `2026-09-model-kind-protocol-pin.md` + `-design-prompt.md` | 模型类型声明 + 多媒体协议点单：中转站不再靠 id 猜 | `model_descriptor.dart`、`llm_dispatcher.dart`；三条没做的并入下面「还欠的」 |
| `2026-09-file-browser-folder-ops.md` | 文件浏览器目录树的新建 / 改名 / 删除 / 移动 | `services/files/folder_operations_service.dart`；与设计稿的偏离见 `architecture/design-tokens.md` §5b / §6 |
| `2026-09-file-browser-file-delete.md`（设计稿 `B1c 文件浏览器-删除文件`，`git show 7cf72e3:docs/plans/2026-09-file-browser-file-delete.md`） | 文件浏览器删除**文件**：右键菜单末组一行、选区悬浮条一枚红色字形、Delete / 退格；有废纸篓走废纸篓，没有才是永久删除 | `services/files/file_delete_service.dart`（执行时重新自证：目录 / 注册根 / 要废纸篓而本机没有，三条各自拒绝，单条失败不拖垮整批）、`screens/browser/widgets/file_delete_dialog.dart`、`core/text_editing_focus.dart`（文本框活着时，屏级快捷键整段让位：一个文本框没吃掉的键仍会上浮，而这个 handler 位于 `DefaultTextEditingShortcuts` **之下**，抢走就等于字段永远收不到——目录树的行内改名编辑器只处理 Escape，其余故意让上去。`test/screenshots/browser_shortcut_scope_test.dart` 在真实应用树上按 Cmd+A / 退格 / Delete / F2 钉住这条） |
| `2026-09-ui-rewrite-feature-inventory.md` + `-liquid-glass-design-prompt.md` | 液态玻璃翻新的功能对照表与出稿 brief（PR #219 已合入） | `architecture/design-tokens.md`。功能清单拍的是翻新**之前**的 v3.33.0，翻新之后它描述的界面已不存在 |
| `2026-09-multi-directory-nav-outline.md` + `-design-prompt.md` | 多目录导航条（设计稿 `A1b`）：画廊与文件浏览器勾选多目录后的 chip 索引、scroll-spy、四级宽度降级；浏览器补「按文件夹分组」；排序菜单改玻璃 Float（PR #248、#249） | 偏移表与 spy 在 `core/folder_outline_geometry.dart` / `folder_outline_spy.dart`（跳转靠算不靠量，视口外的 sliver 没有 RenderObject）；chip 条 `widgets/files/folder_outline_bar.dart`；分组 `FileBrowserState.groupByFolder / folderSections`；玻璃菜单的单选 / 复选 / 说明行 `AppGlassMenuItem.checked / radio / hint`。与稿的两处出入：跳转落点是组标题顶边贴判定线（标题自带 10px 上留白即稿子的 +12）；折叠 chip 的菜单行无路径副行 |
| `2026-09-spec-based-billing.md` + `-design-prompt.md` | 计费组第三种模式「按规格」：单位（张 / 秒 / 条）× 档位表（尺寸 · 质量 · 时长三个可选条件 + 单价，填得最多的行优先，全空行兜底）；请求的规格从工作台参数读、OpenAI Images 回显的实际尺寸优先；单价与数量快照进用量行，读时算钱 | 非 UI 部分已落地：v42 迁移（`fee_groups.output_unit / output_rates`、`token_usage.output_*` 四列）、`models/spec_rate.dart`、`services/llm/output_spec.dart`（归一化）、`services/billing/spec_billing.dart`（匹配与计价）、`LLMService.specUsageFor`（三条记录路径共用的纯函数）、`usage_stats.dart` 的 `spec` 部分与 `TokenUsage.unmatched`。视频仍在提交时计费（同按次）。UI 按 D2b 稿落地：`widgets/models/spec_rate_table.dart`（单位 chip + 档位表 + 校验）、`widgets/models/fee_group_summary.dart`（三种模式同一格式的摘要）、`services/billing/spec_known_values.dart`（条件取值 = 家族参数表 ∪ 协议参数表 ∪ `VeoResolution`）；用量页分组行数量列、未匹配提示与「去补档位」、明细「规格」列。与稿的出入见下面「还欠的」 |
| `2026-09-image-size-picker-design-prompt.md`（设计稿 `A1c 尺寸选择器`） | 一个尺寸选择器服务 gpt-image-2 / 2.5、qwen-image、wan2.7-image(-pro)：规则成数据（`ImageSizeRules`：网格 / 单边上下限 / 比例 / 面积）；提供成数据（`ImageSizeVocabulary`：比例 chip、档位、哨兵含义、万相官方表）；比例 × 档位两轴主控、宽高退到第三位、规则收成一行、违规只点名挡路那条并给一键修正、即时生效 + Esc 撤回、回落提示、计价档标签（只写档名、无计费组不出现）。桌面 / 平板为锚在字段右缘的玻璃浮层，手机在参数 sheet 内原地展开。按档计费行现按面积就近归档（`specRateTierOf`）。旧的 460 宽对话框删除 | `services/llm/image_size_rules.dart`、`image_size_vocabulary.dart`（纯函数，`test/services/llm/image_size_vocabulary_test.dart`）；`screens/workbench/widgets/size_picker/`（`test/screens/workbench/size_picker_test.dart`，截图 `test/screenshots/size_picker_shots_test.dart` 与 workbench `sizePicker`）。与稿的出入：手机键盘弹起时「摘要 + 宽高 + 提示」钉在键盘上方的 sticky footer 未做（sheet 整体滚动）；比例 chip 组 / 档位组内的 ← → 组内移动未做（Tab 逐个经过）；修正显形的旧值删除线改为句中写出旧值；平板浮层宽 = min(340, 字段宽 + 16)，不读抽屉宽 |
| 2026-09-14 LLM 层对照 `ai-agent-architecture` skill 审计（无方案文件；五路只读审计 → 六个分支） | 修：chat wire 完整性（内容拦截一律抛、截断/空 200/半截工具调用不再当成功、`<think>` 只认开头、③ 调用 id 唯一、回传载体按模型作用域）#265；计费与媒体（计费面接受后不重试、视频任务 id 落库并跨重启续轮询、下载校验与不给签名链接带 key、`LLMConfigException`）#263；助手运行时（恢复时修配对、压缩失败不动历史、KB 应用前复核磁盘、收尾轮撤工具）#266。补：Gemini `thinkingConfig` 与 raw parts 回传、百炼 ① 面 `enable_thinking` / `enable_search` #268；Retry-After、可中止请求、上下文预检、日志脱敏与关联 #267；OpenAI Responses 协议面 #269 | `architecture/llm-three-layer.md`（chat wire 完整性、Responses 两节）、`architecture/assistant-context.md`（不变量 10–11）、`api/responses.md`、`ai-agent-playbook/`（与 skill 同步，#264）。欠的并入下面「还欠的」 |
| D2 `用量统计` 稿 1d–1h（无方案文件，直接按稿施工） | 费用组页面：头行 + 桌面双栏 / 平板单栏 / 手机全屏页，拖拽排序（v43 `fee_groups.sort_order`） | `widgets/models/pricing_group_manager.dart` 与 `widgets/models/fee_group_*.dart`；与稿的出入见下面「还欠的」 |
| `2026-09-large-file-split.md`（八片，分支 `claude/split-*`，一片一个 PR） | 1500 行以上的八个文件拆开：`prompt_optimizer_agent` 4207→1352 · `prompt_optimizer_view` 2759→595 · `video_config_panel` 1947→573 · `openai_chat_protocol` 1784→796 · `anthropic_chat_protocol` 1670→420 · `directory_tree_item` 1593→701 · `ai_rename_dialog` 1510→477 · `model_edit_dialog` 1497→290。两种手法：并列的顶层单元拆成独立库（两个协议、`widgets/files/folder_drop_feedback.dart`、`folder_tree_row.dart`）；一个大类或大 State 用 `part` 拆，私有 static 变库私有顶层声明、State 的 builder 变 State 上的具名 extension —— **元素树一个节点不变**，所以没有把卡片改成独立 widget。顺带：`browser` 不再横向引 `workbench`；问答卡的虚线用回共享节奏；**AI 重命名的冲突逻辑下沉到 `services/tasks/ai_rename_review.dart` 并第一次有了测试，由此找到并修掉一个会删用户照片的 bug**（两行重名时点「改名」原样还回同名、「覆盖」删掉另一行刚放好的文件；现在 review 与 executor 两层都拒绝，UI 上禁用并说明）。**`llm_dispatcher.dart`（1586 行）刻意没拆：它是唯一路由表，拆开就违反那条不变量 —— 按行数扫到它不要立项。** | ④ 的文件 ↔ 不变量对照在 `architecture/llm-three-layer.md` ④ 一节；助手七个文件在 `architecture/assistant-context.md`「Where it lives」；CLAUDE.md 的 map。拆分手法与各片的坑（插值里补类名会静默编译通过、extension 里库作用域优先于 `this`、截图要比像素不比字节）在上面 `git show` 的方案原文里 |
| `2026-09-assistant-output-cap.md` + `-execution.md`（八片，分支 `claude/assistant-output-cap`，一片一个 commit） | 提示词助手输出截断：模型级「最大输出」（v44 `llm_models.max_output_tokens`、协议唯一读口 `outputCapFor`、① 字段名按 `VendorProfile.outputCapField` 声明、④ 的 8192 退为兜底、编辑器区块 + 卡片 chip、发现时按键形预填上下文窗口——上限刻意不预填）；截断对策（`length` 的半截调用一个不跑、配有指向的 `output_truncated` 结果、连续两次即停并跳到模型设置，子代理同款）；压缩摘要由 App 附最新提示词而不再让模型重抄（跨次压缩接力）；四个模式提示加「交付前不写散文」；子代理 note 限长；`write_knowledge_file` 按节写入（`replace_section` / `append`，拼好后仍 stage 整文件） | `architecture/llm-three-layer.md`「输出上限」、`architecture/assistant-context.md`「The output side」与不变量 12–13、`api/usage.md` §3；设计稿链接在前者。方案原文 `git show 2e7f443:docs/plans/2026-09-assistant-output-cap.md`。欠的并入下面「还欠的」 |
| `2026-09-debt-sweep-execution.md`（二十二片 + 四次 review，分支 `claude/debt-sweep-4.9`，v4.9.0） | 清「还欠的」里用户点名的三组。① 代码：state 换新列表（视频参考图 / 文件夹切换 / 下载器日志）；视频面板头部放不下时整栏单滚动；AI 重命名「覆盖」禁用态的测试口子；截断标记与 `modelDbId` 跨重启（`LLMMessage` 上的宿主簿记字段）；按节写入的卡片标出节名、hunk 头带所在标题；九个协议的「200 里什么都没有」改抛 `LLMApiException`、`fromJson` 拒收未知 role；`VendorProfile.webSearchOn` 让编辑器与三个 payload 同答，百炼 ④ 面不再带 `web_search`。② 动效：「还欠的」七条全做（见 `plans/README.md` 第四轮）。④ 决策项：S1 / S3 走「明说 + 文件权限 + 生命周期」不上钥匙串（理由见执行文档「决策记录」）；`runTurn` 拆出四个 helper；助手一次 session 通知 1,122 → 29 次 build（`ListenableSelector`）；D2a 三条；十五个 1000–1500 行文件拆分。**与台账不符的两条**：视频 / MJ 请求早已走 `sendJsonRequest`；timeout 取证的「① 累积器」早已落地 | `architecture/assistant-context.md`（Where it lives 九个文件、截断标记持久化）、`architecture/llm-three-layer.md`（联网搜索同一答案、`llm_errors.dart`、`model_capability_tables.dart`）、`architecture/design-tokens.md`（`accentRule`、`AppMotion.sceneFor`）、`plans/README.md`、CLAUDE.md map。执行文档原文 `git show 99b2784:docs/plans/2026-09-debt-sweep-execution.md`（施工记录里有每片的偏离与量出来的数字）。欠的并入下面「还欠的」 |
| `2026-09-seedream-execution.md`（七片 + 两次 review，分支 `claude/seedream-image-model-support-f4e87c`，v4.10.0） | 火山方舟 Seedream 生图：`Vendors.volcengineArk`（按量 `/api/v3` · 套餐 `/api/plan/v3` 两个同类型变体）+ `WireProtocol.arkImages` + `ModelFamily.seedreamImage` 按版本出表（5.0 pro · 5.0 lite · 4.5 · 4.0 · 3.0 + 兜底）；尺寸 = 档位 + 比例查表；水印明发默认关；5.0 pro「任务」三段（生成 / 拆图层 / 透明编辑）；中转上认得出的 Seedream 走方舟 body；组图放宽超时。顺带：变体按地址回读、同族变体卡印路径、按规格选单收 id 表。设计稿 Claude Design `D1e`。套餐端点实机出图验证 | `architecture/llm-three-layer.md`「火山方舟 · Seedream」、`api/volcengine-ark.md`（含 §7 实测）。执行清单原文 `git show 294432d:docs/plans/2026-09-seedream-execution.md`（决策记录 13 条、施工记录每片的偏离）。欠的并入下面「还欠的」 |
| `2026-09-channel-route-model.md` + `-execution.md`（十六片 + 三次评审，分支 `claude/channel-route-model-*`，PR #304 · #305 · 本轮） | 渠道 × 线路 × 模型：一份密钥一个渠道，渠道下每个协议族一条线路（v45 `llm_channels.routes` 内嵌文档、`llm_models.active_route / route_params`，读时迁移、请求逐字节不变——真实发请求比对），模型选当前线路、每条线路独立参数、切线路空白起步；改主线路先钉住跟随者；同密钥旧渠道只检测、逐组确认合并（加「请求不变」闸）；界面按 D1f：渠道栏平台 + 线路徽标、渠道编辑线路表与实际地址、向导平台优先建全部线路、模型编辑线路条与差异卡、合并审阅 | `architecture/llm-three-layer.md`「渠道 × 线路 × 模型」与红线表；代码 `services/llm/{channel_routes,model_routes}.dart`、`vendors/platforms.dart`、`services/catalogue/{route_switching,channel_merge,channel_merge_executor}.dart`。原文 `git show 9e90547:docs/plans/2026-09-channel-route-model{,-execution}.md`（执行清单的施工记录有每条偏离的理由）。欠的并入下面「还欠的」 |
| `2026-09-ark-image-stream-execution.md`（四片 + 一次 review，分支 `claude/ark-live-tests`，与套餐实测文档同一 PR） | Seedream 流式出图：方舟自家渠道上 5.0 lite / 4.5 / 4.0 发 `stream: true`，逐张下载推出；空闲守卫按单图期限计；执行器边到边存。中转与 5.0 pro 照旧同步。顺带：套餐实测补了 chat 面思考开关（不需要方言）、流式事件形状、拆图层响应形状 | `architecture/llm-three-layer.md`「火山方舟 · Seedream」流式一条、`api/volcengine-ark.md` §5 · §7 · §7.1。执行清单原文 `git show a305018:docs/plans/2026-09-ark-image-stream-execution.md` |
| `2026-09-channel-route-followups-execution.md`（八片 + 两次评审，分支 `claude/channel-route-followups`） | 渠道 × 线路欠账清零：合并连助手对话里的模型链接一起改写（库里的行与打开着的会话）、合并审阅把已选模型 / 用量记录 / 对话链接分开计数；换预设与向导同源建平台全部线路；路径「主机本身」一态（自定义平台给「用主机本身」）；联网矩阵「未实测」第三态（画像声明 `untestedWebSearch`）；向导每条线路的私有能力一词；作用域灰字紧跟标题（`AppSectionLabel.suffix`）、手机线路条横向滚动。渠道栏副行不显示渠道标签维持设计 ① 原意 | `architecture/llm-three-layer.md`「渠道 × 线路 × 模型」。原文 `git show 8285ca7:docs/plans/2026-09-channel-route-followups-execution.md`（裁定表与施工记录） |
| `2026-09-ark-layers-execution.md`（五片 + 一次 review，分支 `claude/ark-layers`，v4.15.0） | 拆图层落库与画布还原：`GeneratedImageLayer` 与图按位置对齐（`LLMResponse.imageLayers` / `LLMResponseChunk.imageLayer`，方舟逐项下载保对齐）；v46 `image_layers` 按路径存组、层号、名字、描述、框，应用内改名 / 移动带着走、覆盖时退掉旧行；全屏「图层画布」按框叠回底图、逐层显隐、点选描框、导出可见层合成图；入口是图片卡角标与右键一行。设计稿 Claude Design `A7 图层画布` | `architecture/llm-three-layer.md`「火山方舟 · Seedream」拆图层一条、`api/volcengine-ark.md` §6。执行清单原文 `git show 0ad48c6:docs/plans/2026-09-ark-layers-execution.md`（施工记录有与稿的四处出入） |
| `2026-09-capability-audit-fixes-execution.md`（十七片 + 五次 review，分支 `claude/model-capability-fixes`） | 2026-09-19 用 `ai-agent-architecture` skill 审模型能力支持（不含 Sora）后的修复。静默失败：出图 0 张判失败并带模型原话；① 流式内联图的文本闸门（不重复、不丢尾）；万相 usage 不再按 token 计费（`dashscope_usage`）；上下文压缩不带联网搜索（`llmNoServerToolsKey`）。协议：`requestStream` 续跑 `pause_turn`；MiniMax ① 思考方言 `openaiAdaptiveObject`（实测 2026-09-19）；③ 异常结束无输出按整段判失败、百炼私有面补空回复规则、GLM `sensitive` 归 `content_filter`。视频与计费：「继续原任务」续轮询 / 重下载不重新付费；按规格计费的视频行按上游回报时长改写（`video:<job id>` 行）；「与按次相同」提示只在单位为「条」时出现（按次本身不乘张数，裁定）。发送前：四条出图路由按模型尺寸控件校验（`optionsWithCheckedSize`）；④ base 自动补 `/v1`、去 `/messages`；Anthropic 思考方言只在拼写被拒时翻转。结构：Veo 分辨率 / 比例成为模型声明、面板无固定控件；视频选单与提交共用 `_videoSubmitRoute`；连接测试的补全探测保留线路；聊天线表穷举 | 代码与测试；MiniMax 实测写进 `api/minimax.md` §1。执行清单原文 `git show 5d0a825:docs/plans/2026-09-capability-audit-fixes-execution.md`（施工记录与每批 review 的发现）。欠的并入下面「还欠的」 |
| `2026-09-assistant-mode-regroup-execution.md`（五片 + 五次逐片 review + 一次整体 review，分支 `claude/prompt-assistant-design-review-39a2bd`；设计稿 Claude Design `A3d 提示词助手-模式重组`） | 提示词助手三段开关「系统提示词｜知识库｜库编辑」重组为两级「任务预设｜知识库 › 用它来：出词｜维护」——**枚举、持久化、历史图标不变**，只是三个旧值的另一种呈现。开关移到右栏顶部，未配置知识库时「知识库」段仍可点（落到状态卡），运行中两级锁定并说明；工具头徽标「任务预设 · 预设名」/「知识库 · 出词｜维护」。任务预设卡先任务后文本：编辑器默认折叠，内置「通用优化」成为选单首项（只读、可另存为预设），说明行由正文首段派生（不加库列），未保存时换预设先确认。三个模式各有空状态（预设砖 = 选中不发送；示例 = 填入不发送、接在草稿前）。维护左栏「文档｜参考图」分段。**出词⇄维护同会话切换**：`session.mode` 只在知识库对内可变，运行中 / 跨依据在 session 一层拒绝，被拒的切换不落到新会话，mode 随会话落库，暂存的改动切换后仍可应答、右栏仍列出 | `architecture/assistant-context.md`「What about a session may change」；代码 `prompt_optimizer_session.dart`（`switchKnowledgeUse`）、`optimizer_config_panel.dart` + `optimizer_config/{sys_prompt_card,preset_summary}.dart`、`optimizer/optimizer_empty_state.dart`、`optimizer_left_panel.dart`；测试 `assistant_kb_use_switch_test` · `optimizer_empty_state_test` · `optimizer_left_panel_test` · `preset_summary_test`。执行清单原文 `git show e999887:docs/plans/2026-09-assistant-mode-regroup-execution.md`（决策记录四条、每片与稿的出入与 review 处置）。欠的并入下面「还欠的」 |
| `2026-09-preset-output-kind.md`（七片，逐片 review + 一次两路独立的整体 review，分支 `claude/preset-output-kind`；设计稿 Claude Design `A3e 提示词助手-预设产出类型`） | 任务预设带一个**产出类型**（`PresetOutputKind`：提示词｜分析文本，`system_prompts.output_kind`，v47；只有 refiner 预设有，未知值回落提示词）。它是预设的属性，不是第三个模式：在提示词库的模板编辑框里选（「产出」分段 + 随选中项换字的说明，切到重命名时收起），面板不提供临时切换。类型与正文同路到 agent（`loadOptimizerPreset` → `optimizerTurnParameters` → `runTurn(outputKind:)`）；正文清空即内置预设，恒按提示词。分析类换一套框架（`_buildAnalysisSystemPrompt`）：用户消息是请求本身、完整结果写在正文、`submit_prompt` 降为可选、`ask_user` 放宽到范围不清时；**提示词类的框架由逐字副本的测试钉住**（`optimizer_output_kind_test.dart`）。分析轮里收尾的正文标 `LLMMessage.deliverable`（与 `truncated` 同样只在为真时进 JSON，恢复的会话仍认得；最后一轮的状态汇报、紧跟 `submit_prompt` 的那句、知识库会话都不标），界面只给它一行「复制」——不做卡片、版本、应用。分析轮里看完图的空回复不再算合法收尾。界面上只有少数派说话：分析类预设在库列表、选择器行、空对话磁贴上带中性标记 `AppNeutralMarker`（不跟种子色），预设卡里两种类型都有一行只读「产出」；载入分析类预设时空对话换标题 / 副标题 / 占位并给三条点名参考图编号的问法。顺带：模型不接受图片而会话带了参考图时，对话里落一张 warning 卡（原先只写任务日志），同模型同张数只说一次；助手面板的「保存」改为整行回写（原先手列字段，会把新列冲回默认）；模板编辑框的「模板用途」分段铺满整行（英文 390 宽原本溢出 95px）。 | `models/prompt.dart`、`assistant_system_prompts.dart`、`prompt_optimizer_agent.dart`（`_lastBatchSubmittedPrompt`、`_noteImagesNotOffered`）、`workbench_ui_state.dart`；`architecture/assistant-context.md` 记了 `deliverable`；方案全文 `git show 2cf3e8b:docs/plans/2026-09-preset-output-kind.md` |
| `2026-09-keyboard-shortcuts.md`（十一片 + 逐片 review，分支 `claude/workbench-file-manager-shortcuts-1e22c4`；设计稿 Claude Design `00f 键盘快捷键`） | 第一期键盘快捷键：应用级 + 工作台 + 文件浏览器。三层模型（L0 应用 / L1 屏幕 / L2 焦点区，认领从下往上）、一张注册表、两屏的文件操作同键同义。修掉两个开工前验证过的缺陷：点过目录树之后 `Delete`/`F2` 被文件夹永久抢走且点回网格也要不回来（选区类键从 L1 下放 L2，两屏各划焦点区，活动区画得出来）；改名途中按 `⌘F` 会提交半截名字（L1 让位闸门提到最前，闸门之上无例外）。前提是先把删除归一——工作台此前在 macOS/Linux 上是 `File.delete()` 永久删除，浏览器是废纸篓服务，同一批文件两种下场。新增 `⌘/` 面板、`⌘,`、`⌘\`/`⇧⌘\` 两栏开关（两屏都补了鼠标能点的回路）、`⌘⌥1…5` 工具直达、`⇧⌘C`/`⌥⌘R`/`⌘O`/`⇧⌘N`、画廊的 `Shift+点击` 区间选择；菜单 trailing 与设置页「键盘快捷键」一类全部从注册表取，不再有字面量。 | [`../architecture/keyboard-shortcuts.md`](../architecture/keyboard-shortcuts.md)（三条纪律 + 「会静默失效的几处」：屏级 handler 必须是 `FocusScope`、精确修饰键的代价、活动区认领按身份不按名字、面板读活动区的时机）；代码 `core/app_shortcuts.dart`、`widgets/ui/{focus_pane,app_key_label}.dart`、`widgets/shell/shortcut_{panel,labels}.dart`、`widgets/files/file_delete_dialog.dart`（从 `screens/browser/` 下沉，工作台才引得到）；测试 `app_shortcuts_test` · `shortcut_labels_test` · `screenshots/{browser,workbench}_shortcut_scope_test` · `screenshots/shortcut_panel_test` · `screenshots/workbench_delete_scope_test`。方案原文 `git show 4dba9b8:docs/plans/2026-09-keyboard-shortcuts.md`（§5 的裁定 D1–D8 与理由、§10 的坑）。第二、三期的登记（网格方向键与无障碍、编辑器 `⌘Z`、其余屏幕的屏级键、iPad 外接键盘、自定义键位、真剪贴板搬文件）并入下面「还欠的」 |
| `2026-09-architecture-audit.md`（无 A1–A6、A8 正文——做完一条删一条；A7 与基线：`git show 65c9190e:docs/plans/2026-09-architecture-audit.md`，八条齐全的初版：`git show 6521e52d:…`） | 对照 Flutter 架构手册在 `73aaa68` 上做的全仓审计，八条（A1–A8）全部做完。**A1（构造函数注入）已做**，分支 `refactor/state-di`：`DatabaseService.forDatabase` 是新的注入口（`_database` 从 static 改为实例字段，门面自己持有六个仓储），十个状态类 / 服务 / 仓储收可选的具名参数，`AppState` 把自己的那一个往下发给每个子状态与任务队列；测试侧新增 [`test/support/in_memory_database.dart`](../../test/support/in_memory_database.dart)，八个仓储现在收同一样东西（`db:`），三个文件（`llm_config_resolver` · `file_staging_state` · `cookie_retention`）已改成注入式并**不再需要** `private_data_dir.dart`（从 45 降到 42，余下可照此迁），两个助手仓储的 `dbProvider:` 一并并入同一个口子。**A2（用量与任务两个仓储传裸 map）已做**，分支 `refactor/usage-task-models`：新增 [`lib/models/token_usage.dart`](../../lib/models/token_usage.dart)（`TokenUsage` + `UsageBilling` 三态 + `UsageSpecBilling` / `UsageSpecSnapshot`，`output_spec` 的 JSON 在模型里解掉）与 [`usage_checkpoint.dart`](../../lib/models/usage_checkpoint.dart)；`token_usage` 的列名退回数据层（模型的 `toMap/fromMap` 与仓储的 WHERE），`screens/metrics/` 里一个都不剩，`usage_stats.dart` 里那组自由函数（`usageRowCostParts` / `calculateRowCost` / `usageRowSpec` / `usageRowUnmatched` / `usageRowSpecLabel`）变成 `TokenUsage` 上的 `costParts` / `cost` / `unmatched` / `specLabel`；视频结算从「按列名传 map」改成 `UsageRepository.updateSpecBilling(taskId, UsageSpecBilling)`；`TaskRepository` 收发 `TaskItem`，队列的历史改名走 `TaskItem.withModelId`。整库备份/导入按约定**仍走 map**。**A3（门面把模型绕着 map 转一圈）已做**，分支 `refactor/facade-takes-models`：`DatabaseService` 与 `AppState` 上十二个 add/update 方法直接收 `Prompt` / `SystemPrompt` / `PromptTag` / `LLMModel` / `LLMChannel` / `PricingGroup`，门面里的 `fromMap` 全删（`database_service.dart` 的 `Map<String, dynamic>` 42 → 30，剩下的只有备份/导入那一族与两个本来就返回裸行的读取）；工作台存回模板走新加的 `SystemPrompt.withContent`，计费组草稿 `toData()` → `toGroup()`。类型化当场翻出 map 一直藏着的三件事：测试里四处早已无列可写的 `'type'` 键；**编辑模型会把 `sort_order` 清零并抹掉 ETA 统计**、**编辑内置标签会抹掉 `is_system`**（表单没有的列经 `fromMap` 落回默认值再整行写回）——后两条已修，钉在 [`test/services/db/edit_keeps_unedited_columns_test.dart`](../../test/services/db/edit_keeps_unedited_columns_test.dart)。规矩：**有专属写入口的列，仓储的整行 update 不写它**——`ModelRepository.updateModel` 剥掉 `sort_order`（归 `updateModelOrder`）与 ETA 三列（归 `updateModelEstimation`），`PromptRepository` 的三个 update（提示词 / 预设 / 标签）同样剥掉 `sort_order`（归三个 `update…Order`），和 `LLMChannel.toMap` / `PricingGroup.toMap` 不含 `sort_order` 是同一个道理；这样编辑器开着时落地的一次重排或一次 ETA 更新也不会被保存盖回去。**没收掉的一处**：工作台把改过的预设存回模板时，写回的标题 / 类型 / 输出类型（出词｜分析）/ markdown 开关 / 标签仍是它这一会话里缓存的那份，期间在提示词库里改过名、换过输出类型都会被盖回去（`main` 上就是这样，修法是存之前重读该行）。没有专属写入口的（`is_system`）由编辑器从打开的那一行带过来。**A4 已做**：`models/` 不再导入 Flutter——`FileCategory.color` / `BrowserFile.color`（零引用、裸 Material 颜色）删掉，`icon` 与两个 `imageProvider`（`BrowserFile`、`AppImage`）成了 [`lib/widgets/files/file_visuals.dart`](../../lib/widgets/files/file_visuals.dart) 里的扩展，调用点只多一行 import；`FileImage(File(path))` 原样搬走，缓存键没变。台账当时漏了 `icon` 的第三个调用方 `TransferThumb`（在 `widgets/files/`），所以落点是 `widgets/files/` 而不是台账写的 `screens/browser/widgets/`。`test/source_layout_test.dart` 新增一条「models import no Flutter」钉住。**A5 已做（第一档）**：`TaskQueueService.queue` 交出去的是不可改的快照，而且**每次通知都换一个新列表**，不只是增删时——`TaskItem` 可变，任务开始 / 结束 / 取消时列表里没有任何东西可比，只换增删的身份仍会让返回 `queue`（或它的切片）的 `select` 静默不重建；500ms 的进度估计走 `progressTick`，不经过这里，所以多出来的只是每次通知拷一份引用——队列长度是用户级的（启动时至多载入 `reloadLimit` = 200 条）。测试与截图 harness 原来直接往交出去的列表里 `add` 来播种，改走 `setQueueForTest`。钉在 [`test/state/state_list_identity_test.dart`](../../test/state/state_list_identity_test.dart)。**第二档（`TaskItem` 转不可变 + `copyWith`）按台账的判断没做**：它牵动 `task_executors.dart` 里所有就地写进度 / 日志的路径，收益与风险不成比例；`TaskRepository.saveTask` 同步快照 `toMap()` 的写法因此继续有效，别删。**A6 已做**：268 个测试文件按 `lib/` 的分层镜像分目录——`test/core/` `test/models/` `test/state/`、`test/services/<domain>/` `test/widgets/<domain>/` `test/screens/<domain>/`（domain 与对应 `lib/` 子目录同名），另加 `test/app/`（整应用 / 导航级，归给哪一个屏幕都不对）与 `test/architecture/`（读源码而非跑某个模块的全仓审计）；`test/support/`、`test/screenshots/` 不动。分类按测试实际验证的东西（导入与断言）来，不按文件名——`optimizer_*_test.dart` 里纯逻辑的一半留在 [`test/services/assistant/`](../../test/services/assistant)，挂了 `screens/workbench/widgets/prompt_optimizer_view.dart` 之类界面的另一半去了 [`test/screens/workbench/`](../../test/screens/workbench)。纯 `git mv` + 65 个文件的相对导入（`support/...`、`screenshots/...`）按新深度补 `../` 或 `../../`，零逻辑改动。`test/source_layout_test.dart` 留在根下（约定的唯一入口），新增第十条：`test/` 根下、以及 `test/services/` `test/widgets/` `test/screens/` 各自根下都不留散文件；`test/` 下每个目录要么在 `lib/` 里有同路径的目录（任意深度），要么在约定的四个之下（`app` `architecture` `support` `screenshots`）。CI 的分片用 `find test -name '*_test.dart'`，本来就递归，没动。`flutter test -x screenshots` 用例总数迁移前后一致，加这条规则后多一条。**A8 已做**：四个屏幕（文件浏览器、模型、提示词库、工作台右栏）不再从 `initState` / 拖拽回调里直接 `DatabaseService().getSetting/saveSetting` 存面板宽度，改问 `AppState.uiPrefs`——[`lib/services/system/ui_prefs.dart`](../../lib/services/system/ui_prefs.dart) 一个文件：`UiPanel` 枚举带着四个 `settings` 键（用户盘上已有这些行，改名等于静默丢布局，键串在 `lib/` 里只许出现在这一处，[`test/architecture/panel_width_keys_scan_test.dart`](../../test/architecture/panel_width_keys_scan_test.dart) 钉住），`UiPrefs({database})` 由 `AppState` 用发给各子状态的同一个库构造；夹取（min/max）是布局事实，留在屏幕里。`grep -rl database_service.dart lib/screens lib/widgets` 16 → 12，没到台账估的「8 上下」：余下 12 个里 `usage_controller` 本来就是注入式，`backup_error_text` 只用异常类型，其余是台账判定可接受的真数据操作（备份 / 还原 / 重置 / 导入 / 清用量、首启写渠道与模型）、三个提示词列表的拖拽重排、设置页两个分区读写自己的设置行，以及 `ai_rename_dialog`（读改名模板 + 三个 `last_ai_rename_*`）——除最后这三个偏好行（形状与面板宽度相同，但挪走也摘不掉那个 import，没动）之外，再往下收就要给它们建仓储 / VM，本条明确不做。**A1 的服务层尾巴一并收掉**：`KnowledgeBaseService({database})`（不传仍是全应用那一个实例，30 个调用点不动）、`PromptOptimizerAgent.runTurn(database:)`（会话行、保留条数设置、委派笔记三样一起走注入的库——笔记带 `session_id`，只通一半会把一个会话劈在两个库里）、`ContextBudget.resolveWindow(database:)`（唯一的调用方是下载器的 `WebScraperService.discoverImages`，`DownloaderState` 把库传进去）、`AiRenameAgent.applyProposals(database:)`，前两样与最后一样由任务队列把自己的 `_db` 传下去；`WorkbenchUIState.requestKbDistill` 顺手把手里的仓储交给 `stageKbDistillRequest`。**没收的**：`services/files/` 里六处 `ImageLayerRepository()`（删除 / 移动 / 改名时带着图层行走，和 `ai_rename_agent` 同一形状）、`llm_service.dart` / `llm_usage_recording.dart` 两处挡在 `usage…Override` 测试缝后面的 `DatabaseService()`、`LLMService` 自己那个不带库的 `LLMConfigResolver()`（一轮助手对话里解析模型 / 渠道仍读单例，LLM 侧没有合上）、以及从界面直接调、手里没有库的 `applyStagedKbEdit`。`AppState` 是写死的单例，`uiPrefs` 的接线没法单测，靠初始化列表里那一行。**A7 已做**（workbench 过度集中，只切提示词助手这一刀）：先裁定了它**仍是工作台的一个页签**——`WorkbenchTab` 里的一档，四个文件还是 `workbench_screen.dart` 的 `part`、共用它的私有状态——所以落在 `lib/screens/workbench/assistant/` 而不是 `screens/assistant/`。原来散在三处的（`workbench_assistant/`、`widgets/optimizer/`、`widgets/optimizer_config/`）加上 `widgets/` 根下十个助手文件并进去，共 29 个；`result_feedback_dialog` 虽然从画廊的文件菜单打开，交出的 `ResultFeedback` 进的是助手会话，跟着助手走。`widgets/` 根下其余散文件收进 `video/`、`crop_resize/` 与新建的 `mask/`、`compare/`、`gallery/`、`config/`（图像与视频两块配置面板共用的三件，可独立 import；旁边的 `config_panel/` 是图像面板自己的两个 `part`，不是一回事）；根下只留两个确实跨域的：`canvas_overlays`（蒙版 + 裁剪）、`workbench_glass_toolbar`（画廊 / 布局 / 屏幕）。十四个助手测试跟到 `test/screens/workbench/assistant/`。纯移动：62 个文件 `git mv`，Dart 文件里变的只有 import / part 行，测试数不变，截图 harness 全过。`metadata_inspector` 名字像画廊的，实为对比视图的右栏，进 `compare/`。留给以后的：`result_tree_item` 是侧栏结果树，和根下的 `directory_tree_item` / `folder_tree_row` 是一家，哪天建 `sidebar/` 该跟过去；`test/screens/workbench/` 里非助手的测试（裁剪 / 选择条 / 视频 / 图层 / 尺寸）没有跟着建更深的镜像目录。没动的：workbench 根下十个文件、`preview/` `layers/` `size_picker/` `config_panel/`，以及图像 / 视频工作台、蒙版 / 裁剪、对比视图之间的切分——台账只要求这一刀。`feature_plan/prompt_assistant_implementation.md` 是历史方案，里面的旧路径没改。 | 各条点到的文件与测试；`CLAUDE.md` 的 *Layering* / *State and data* 两节；判定**不做**的手册条目在下面「架构审计判定不做的」。 |
| `2026-09-input-image-billing.md`（设计稿 `D2c 计费组-输入图计费`，`git show 0989998:docs/plans/2026-09-input-image-billing.md`，七片 + 六轮独立 review） | 按规格计费组补上「输入图」一侧：xAI grok-imagine-image-2.0（$0.01/张）与 Seedream 5.0 pro（0.02 元/张、首张免费）按张收参考图的钱，应用原先一分没记。计费组两个标量（单价 + 每次请求的免费张数），只有单位为「张」的组收；张数取协议**实际放进请求体**的条数（七个协议发布 `input_image_count`，方舟 5.0 pro 的 `usage.input_images` 优先，每个图片块也带）；v48：`fee_groups.input_unit_price / input_free_units`，`token_usage.input_images / input_units / input_unit_price`；视频结算只改写输出四列；编辑器「输入图」一行、摘要与列表标签、用量页规格列「2K · 输入 3 张」与展开处的输入 / 输出分列；`AppDropdown` 的 trailing 限宽 | `services/billing/spec_billing.dart`（`SpecUsage.price` 的输入一侧，判据在此）、`models/token_usage.dart`（`UsageSpecBilling` 的输入三列、`toOutputMap`）、`protocols/protocol.dart`（`capReferenceImages` / `sentInputImages`）、`output_spec.dart`（`inputImageCountKey`）；不变量在 `architecture/llm-three-layer.md`，定价与 `usage.input_images` 实测在 `api/usage.md` §5、`api/volcengine-ark.md` §4；与稿的出入回写在 `D2c` 稿末与下面「还欠的」 |
| `2026-09-xai-quality.md`（设计稿 `A1f 参数栏-xAI 质量档`，`git show 8d5a5cc:docs/plans/2026-09-xai-quality.md`，六片 + 四轮独立 review） | 给 `grok-imagine-image-2.0` 补质量控件与 1.5K 档：输出按分辨率 × 质量六格标价，应用原先只发分辨率、上游按 Medium 计，档位表写 `1K · low` 命不中。能力表分两张（`_xaiImage` 比例 → 质量 low \| medium（默认 medium）→ 尺寸 1k \| 1.5k \| 2k；`_xaiImageLegacy` 按 id 尾巴给初代，平价、拒 1.5k）；协议发 `quality`、尺寸过共用的 `optionsWithCheckedSize`；计费一行不改（`OutputSpec` 早读 `quality`，`1.5K` 档 Seedream 已铺）；`AppSegmentedControl` expand 轨道的水平内边距降为 4（半栏里英文 Medium 被截）。参数名、枚举与六格实测在 `api/usage.md` §5 | `llm/model_capability_tables.dart`（两张表）、`llm/model_capabilities.dart`（`forModel` 的尾巴分流）、`protocols/xai_images_protocol.dart`、`widgets/ui/app_segmented_control.dart` |
| `2026-09-xai-reported-cost.md`（设计稿 `D2d 用量-上游报价`，`git show e3941d9:docs/plans/2026-09-xai-reported-cost.md`，七片 + 六轮独立 review） | 直接读 xAI 回报的实扣金额：协议把 `usage.cost_in_usd_ticks`（1 tick = $10⁻¹⁰，含输入图）翻成中性键 `reported_cost_usd`，记账落 `token_usage.reported_cost`（v49，NULL = 没报），**压过三种计费模式的全部算式**；档位表快照照写在同一行（`snapshotCost`），用量页明细首对「上游报价 \| 档位估算」、表算值退为 outline、分组 tooltip 一行、报价行不计「档位表未覆盖」；费用格不带标记（D2d 裁决）。中转协议不翻。顺带补测 `n:2`：输入图按请求收一次 | `llm/output_spec.dart`（键与换算）、`protocols/xai_images_protocol.dart`、`models/token_usage.dart`（`costParts.reported` / `snapshotCost`）、`db/database_migrations.dart`（v49）、`screens/metrics/widgets/usage_list.dart` |
| `2026-09-input-images-all-modes.md`（设计稿 `D2e 计费组-输入图全模式`，`git show a7e4c8a:docs/plans/2026-09-input-images-all-modes.md`，七片 + 6 轮独立 review） | 输入图费不再只对单位为「张」的组：规格模式三种单位与**按次**都收（`PricingGroup.chargesInputImages` 不看单位，按 token 仍不收）；按次行只写输入三列（`SpecUsage.inputsOnly`），`costParts.request` 带 `spec.inputCost`。五个视频协议的 `submit` 返回 `VideoSubmission{requestId, inputImages}`（组完请求体之后数），票据带张数，提交行 metadata 有 `input_image_count`。xAI 视频终态轮询读 `video.duration`（秒数结算）与 `usage.cost_in_usd_ticks`（`videoDoneEnvelope(reportedCost:)`），`settleVideoUsage` 拆成两段独立尽力而为，报价经新的 `UsageRepository.updateReportedCost` **只写 `reported_cost` 一列**。编辑器输入图行抽成 `SpecInputImagesBlock`：规格模式三种单位常在（按秒 / 按条副题「首帧 / 尾帧 / 参考图」），按次模式放在提示句下；摘要 / 卡片 / 用量页按次行分输入 / 输出。付费实测：xAI `grok-imagine-video-1.5` 首帧 / 参考图 $0.01/张、线性，报价只在终态回包。**升级注意**：4.27 之前在按张下填过、后来切到按秒 / 按条 / 按次而「停放」的输入图单价，4.28 起开始生效（不做迁移，review ④） | `services/billing/spec_billing.dart`（`chargedInputImages` / `inputsOnly`）、`protocols/protocol.dart`（`VideoSubmission`、`videoDoneEnvelope`）、`protocols/xai_videos_protocol.dart`、`llm/llm_service.dart`（`requestInputBilling`、`settleVideoUsage`）、`db/repositories/usage_repository.dart`、`widgets/models/spec_rate_table.dart`；不变量在 `architecture/llm-three-layer.md`「视频的输入图与终态报价」，实测在 `api/usage.md` §5；出入见下面「还欠的」 |
| `2026-09-code-structure-audit.md`（六片 + 四轮 review，分支 `chore/code-structure-audit`） | 对照 Flutter / Effective Dart 审分包、组织与风格，能断言的都钉进闸门。**分包**：`widgets/` 里只被一个屏幕（沿 `widgets/` 向上传递）用到的 14 个文件归位到该屏幕（`screens/models/widgets/` 的渠道编辑 / 向导 / 发现 / 头像 / 线路表 / 探测卡，`screens/workbench/widgets/config/` 的 `prompt_library_sheet` / `prompt_history_sheet`，`workbench/widgets/gallery/permission_placeholder`，`screens/batch/task_log_dialog`），`widgets/placeholders/` 随之消失；`source_layout_test` 新增一条断言钉住（设计系统除外，`main.dart` 算外壳）。重复的 `modelKindIcon` 合一（「还欠的」旧条目销掉）。**风格**：全仓第一次 `dart format`（`formatter: page_width: 100`，与 flutter/flutter 的 `analysis_options_common.yaml` 相同；720 个文件，纯格式提交记在 `.git-blame-ignore-revs`），CI 加格式闸门，CLAUDE.md 闸门变三道；新开 `directives_ordering` `prefer_relative_imports` `unnecessary_lambdas` `prefer_final_in_for_each` `avoid_multiple_declarations_per_line` `prefer_const_*` `use_colored_box` `use_decorated_box` `unawaited_futures` `avoid_void_async` 并清掉存量——`unawaited_futures` 50 处全是有意不等，没有漏写的 `await`。**踩到的坑**：`use_decorated_box` 对带边框的 `Container` 不等价（`Container` 按边框宽度让出内缩），`dart fix` 照换不误，渠道向导的线路列表因此错位 1px，补 `Padding` 与位置用例、规则旁写了注释。**判定不做**：`omit_local_variable_types`（它的修复丢掉声明类型给初始化式的上下文，24 个编译错误，其余会静默变类型；框架自己走 `always_specify_types`）、行宽 80、`public_member_api_docs` 等非推荐集规则。去掉未用的 `cupertino_icons`；`sqflite` / `video_player_win` 无 import 但是插件实现，理由写在 `pubspec.yaml` | `analysis_options.yaml`（每条规则旁的理由）、`test/source_layout_test.dart`、CLAUDE.md 的 *Key Commands* 与 *Layering*。执行清单原文与四轮 review 的记录：`git show 6976e9c:docs/plans/2026-09-code-structure-audit.md` |
| 界面层的数据访问改走 state / service（2026-09-25，分支 `fix/ui-data-access-via-state`，四片 + 逐片 review + 整体 review；设计文档在 `.claude/tasks/ui-data-access-via-state/`，不入库） | 对照 Flutter 架构手册审出的唯一实质偏差：14 个界面文件自己 `DatabaseService()` / `XxxRepository()` 读写。现在界面只从 state 缓存字段、state 方法、注入了数据库的屏幕控制器（`UsageController`）或 service（`FileRenameService`）拿数据；`AppState.restoreBackup` / `resetAllSettings` 是「恢复后刷新哪些 state」唯一的一份。顺手修了两个不同步的 bug：向导新建的渠道 / 模型要重启才可见；向导导入备份后图库与浏览器的设置不刷新 | CLAUDE.md「Take the database, don't fetch it」的界面层一句；`test/architecture/ui_database_access_scan_test.dart` 钉住。欠的见下面「界面层的数据访问」 |

三份审计报告（`code-review-report-20260613.md` v2.3.0、`api-standards-audit.md`
基线 `d03047e`、`2026-08-ai-capability-review.md` 基线 `6a4920d`）都是带完整
`file:line` 的快照，三层重构与液态玻璃翻新之后每一个行号都已失效。前两份自己就
带着「⚠️ 历史文档」抬头。要重新体检跑一次 `/code-review` 或 `/security-review`，
不要照着旧快照改。

## 架构审计判定不做的（2026-09，不要重复立项）

对照 Flutter 架构手册审计时明确判定不做的手册条目。理由不随代码走，所以留在这里。

| 手册条目 | 为什么不做 |
|---|---|
| `freezed` / `built_value` 生成模型 | 手写模型已经不可变、`==`/`hashCode` 齐全。引入 `build_runner` 要给 CI 和每次改模型都加一道生成步骤，换来的是已经有的东西 |
| 声明式路由（`go_router`） | 全仓 `Navigator.push` 只有 6 处，导航是外壳 + 索引式目的地（`widgets/shell/app_destinations.dart`）。桌面工具这样是对的，换路由器等于为深链接重写外壳，而没有深链接的需求 |
| 拆 `llm_dispatcher.dart` | [`../architecture/llm-three-layer.md`](../architecture/llm-three-layer.md) 写明了它是**故意**做成唯一一张路由表；拆开就退回「分支到处散」的老问题。大文件拆分那一轮（`git show 59e392c:docs/plans/2026-09-large-file-split.md`）已经把它排除过一次 |
| 引入 `get_it` 之类的容器 | A1 做的是构造函数注入；要的就是它，不是再加一套查找规则 |
| 每个功能一套 ViewModel | 状态层是一组 `ChangeNotifier`，各自按屏幕/领域切，`app_state.dart` 里的注释记录了「子状态各自当 provider」这个决定的由来（合并广播导致全 app 重建的回归）。手册的 per-feature VM 在这里只会把同一件事再切一刀 |

## 还欠的（2026-09-12 对照 main 逐条复核过；2026-09-16 欠账清扫后更新）

### 界面层的数据访问（2026-09-25）

| 条 | 为什么没做 |
|---|---|
| 界面直接调用的其他有副作用的 service：`ChannelProbeService`、`ModelDiscoveryService`、`WebScraperService`、`KnowledgeBaseService`、`ImageMetadataService`、`ImageProcessingService`、`FilePermissionService`、`GpuInfoService` | 它们不碰数据库，扫描规则管不到；数量多，是另一种形状的问题（网络 / 文件 / 平台调用从 View 发起），要先定「屏幕控制器还是 state」再一起收 |
| `ImageLayerRepository.layeredPaths` 是进程级静态 `ValueNotifier` | 界面只读它、不构造 repository，不违反规则。挪进 `GalleryState` 要同时改 `services` 下 6 处 `ImageLayerRepository()` 和 `DatabaseService` 开库时的 `loadPaths()`，单开一轮 |
| `AppState` 在测试里跑内存库（`AppState.forDatabase`） | `AppState._internal` 往 `LLMService` 单例注册全局日志监听且不注销，多建实例就泄漏；先得把那个监听改成可注销的。经过 `AppState` 的界面测试继续用 `usePrivateDataDir` + `useRealAsyncAppState` |


### 键盘快捷键（`00f`，2026-09-20，第二 / 三期登记）

| 条 | 为什么没做 |
|---|---|
| 网格的方向键 / Tab 导航与无障碍焦点顺序 | 要先定「网格的逻辑顺序是什么」（分组视图下跨组怎么走），且该与读屏一起做。本轮只建了 pane 级焦点——它是方向键导航的地基（每张卡一个 `FocusNode` 是刻意没做的） |
| 编辑器的 `⌘Z` / `⇧⌘Z`（蒙版、绘制、裁剪、图层画布） | 撤销栈今天只有「撤一步」的按钮，要先有真正的栈 |
| 任务队列 / 下载器 / 提示词库 / 模型页的屏幕级键 | 第一期先把两屏的模型跑通；注册表的 `ShortcutScreen` 加值即可铺开 |
| iPad 外接键盘 | 移动平台一律不注册（D7）。外接键盘要单独想「没有 `⌘` 修饰键的物理键盘」 |
| 自定义键位 | 注册表已为它留了形状（设置页底部那行占位），但要先有冲突检测与持久化 |
| 真剪贴板搬文件（`⌘C`/`⌘X`/`⌘V`） | 浏览器已有「暂存 + 传输」这条完整的路，剪贴板是第二条；两条并存要先裁定它们的关系（暂存栏是不是剪贴板的 UI？跨应用粘贴算不算？）。本轮 `⇧⌘C` 只复制文件名 |
| 工作台的树没有焦点区节点 | 它的行本来就可获焦（点一行就把键盘从画廊拿走，这正是需要的安全性质），所以没有单独建 pane；但点树的**空白处**不会移交焦点 |
| `⌥` 在截图里是豆腐块 | harness 的字体是 Noto Sans SC，有 `⌘`/`⇧` 而无 `⌥`；应用用的系统字体三个都有。要让截图也对，得给 harness 补一个带这些字形的字体 |

### 提示词编辑器 · 放大态（A1d，2026-09-20）

放大框从「标题条 + 原样嵌进去的小编辑器」改成自己的布局：一层头、限宽无框正文、状态脚，外加分栏视图
（`lib/widgets/ui/markdown_editor_large.dart`，`markdown_editor.dart` 的 `part`；`test/widgets/ui/markdown_editor_large_test.dart`、
截图 `test/screenshots/large_editor_shots_test.dart`）。与稿的出入：

| 条 | 为什么没做 |
|---|---|
| ⌘/Ctrl+Enter、⌘/Ctrl+Shift+P 没有进 `core/app_shortcuts.dart` | 稿那边已补（`00f` 规格汇总「设置页「键盘」一节」下有这一行），注册表也随键盘快捷键第一期（#322）落了地——没进表是因为这两个键是放大框自己的 `CallbackShortcuts`，只在对话框打开时生效，既不是 L1 也不是 L2；要进表得先给注册表一个「对话框级」的层，那是第二期的事。于是它们今天也不出现在 `⌘/` 面板与设置页里 |

第一轮欠的另外四条已清（2026-09-20，#323）：Markdown 关掉即停语法高亮（`MarkdownTextEditingController.highlight`，由编辑器随开关同步；
公开的 setter 会通知，编辑器在 `initState` / `didUpdateWidget` 里走不通知的库内入口）；视图分段各段等宽、下限 56（手机 64），
长标签撑宽而不截断；手机 ⋮ 菜单换成 `AppGlassMenu`；小编辑器头部的勾选框换成 `AppSwitch`，
「开关在左、分段与放大贴右」作为裁定写进了 `A1d` 规格末尾，取代 `A1·1a` 的排布。

### Markdown 渲染 · 层级（A1e，2026-09-21）

五处各配半张样式表的 `MarkdownBody` 收进一个原语 `AppMarkdown`（`lib/widgets/ui/app_markdown.dart`，数值在
`core/design_tokens.dart` 的 `AppMarkdownMetrics`；`test/widgets/ui/app_markdown_test.dart`；样张 `component_gallery_test.dart` 的
`markdown_<种子>_<明暗>.png`）。执行清单：`git show 8aad2e6:docs/plans/2026-09-app-markdown.md`。

**为什么不是一张 `MarkdownStyleSheet`**：`flutter_markdown_plus` 只有一个 `blockSpacing`，标题、段落、列表项之间全用它，
拧不出「标题离上文远、贴自己的正文」。`AppMarkdown` 自己解析、自己排块，只把一段行内文字（段落、标题、表格单元）交给库。
要加元素时顺着这条线走，不要回去调样式表。

与稿的出入：

| 条 | 为什么 |
|---|---|
| 表格不横向滚动：等宽列铺满限宽、单元格折行 | 「窄则铺满、宽则自己横滚」要一个 `LayoutBuilder`，而工作台配置栏用 `IntrinsicHeight` 问小编辑器要高度，预览里出现一张表就会抛。有测试钉住「全部元素放进 `IntrinsicHeight` 不抛」——**这个文件里不要出现 `LayoutBuilder`** |
| 行内代码没有圆角与内距 | 库把一段行内文字合成一个 `RichText`，行内代码只能是 `TextStyle.backgroundColor`；换成 widget 会把段落劈成两个 `RichText`，断行就乱了 |
| 链接里的粗体 / 斜体不保留 | `a` 的 builder 以 `textContent` 重建一个无 recognizer 的 span；库自带的路径必带 recognizer，于是必带手形光标 |
| 引用 / 代码块 / 表格 / 图片占位的圆角是 6 不是 8 | 8 不在 4·6·10·16 的梯子上 |
| 助手回复的选区从逐块 `SelectableText` 变成整段 `SelectionArea` | `selectable` 只有一种实现；顺带可以跨块选 |

### 任务预设 · 产出类型（A3e，2026-09-20）

| 条 | 为什么没做 |
|---|---|
| 分析框架的措辞没有在真实模型上验证 | 只能靠真跑：一条识别预设 + 两张参考图，强模型与本地小模型各跑「识别参考图 1」「结合图 1、2 描述…」「补充以下信息…」三句。测试只钉住了框架里有什么、没有什么 |
| 「看不到图片」卡不写模型名，出口是「打开模型设置」 | 稿 5f 写的是模型名 + 「换一个模型」。对话视图手里没有模型表；模型字段是 `ChatModelSelector`，没有从外面打开它的口，而图片输入能力本身就在模型设置里 |
| 「看不到图片」卡不进 history | 与切换分隔线同一取舍：恢复的会话里不重现，下一轮再说一次 |
| `AppNeutralMarker` 与 `OptimizerTagBadge` 没有合并 | 整体 review 指出两者形状相近、内边距不同；后者在 screens 层，合并要先把它下沉成设计系统原语 |
| 截图 harness 只加了一帧 | `assistant_analysis`（结果 + 复制行 + 同会话的提示词卡）与画廊里的标记标本；编辑框的产出分段、分析类空对话、看不到图的卡只有 widget 测试 |

「本版导出的提示词 JSON 旧版导不进」已清（2026-09-21）。两头各修一处：

- **导出**：`SystemPrompt.toExportMap()`，`output_kind` 为默认值时不写这个键。`PresetOutputKind.parse`
  本来就把缺失读成 `prompt`，所以是零信息损失；于是一个没有分析类预设的库，4.20.0 之前的构建照样导得进。
  有分析类预设的仍然写——去掉它会导进去但悄悄换掉预设的行为，比读不进更糟。`toMap` 不动：它同时是入库的
  写路径，改类型时要写得回去。
- **两个写出方合并成一个** `promptLibraryExport`（`models/prompt.dart`）。提示词库文件（`exportPrompts`）
  与整库备份（`getPromptDataRaw`）原本各自拼这三张表的行，`toExportMap` 加进来时**只教会了其中一个**——
  备份那一头漏了，而备份文件同样能从提示词库的「导入」进来（那条路不看 `export_type`，也没有 schema 闸，
  `_validateBackup` 只守 设置 → 恢复）。现在两边都只是这个函数，后者再加两个键，没有各自的份可漏。
  这一条是 review 第二轮找出来的：第一版只修到一半。
- **导入**：`importPromptDataInto` 把每一行先滤成这个库真有的列再 `insert`（`_knownColumnsOnly`）。
  治的是以后：prompts-only 文件没有 `schema_version`（整库备份有，`_validateBackup` 直接拒），新版加一列，
  旧版的 `insert` 就在那一个键上失败，而失败发生在事务里——标签和用户提示词跟着一起回滚。现在只丢那一个键。

**仍然做不到的**，两条，冲着不同的构建去：

- **4.19.x 及更早**没有 `output_kind` 这个列（v47 落在 `98fd6d3`，那时 pubspec 还写着 4.19.1，头一个带它的发布
  是 4.20.0），所以**带分析类预设**的文件它们还是读不进，整库回滚。这条治不了：那些构建已经发出去了，而
  去掉这个键会让预设悄悄换一种行为。没有分析类预设的库现在导得进了，这是导出那一头救回来的部分。
- **4.20.0–4.22.0** 有这个列，今天的文件它们读得好好的；缺的是**滤列**。所以下一个新列对它们仍然是整库归零，
  滤列的好处要从本版之后的发布才开始兑现。

测试在 `backup_restore_test.dart` 的「prompt library import / export」两组。

### 提示词助手 · 模式重组（A3d，2026-09-20）

| 条 | 为什么没做 |
|---|---|
| 知识库未配置时输入框未禁用 | 稿 4d 写的是禁用；现状是发送时拦截并提示（原有行为），空状态示例也仍可点 |
| 未配置状态卡仍是单按钮 | 稿上是「选择文件夹… / 初始化起步文档」两个；现有 `_handleScaffoldKb` 一个流程里先问文件夹再初始化 |
| 预设卡展开态按面板 State 记 | 稿上是「按会话」；换会话不会自动折回 |
| 恢复的会话不重现「已切到维护 / 出词」分隔线 | 它不进 history（界面事实，不是对模型说的话），与 `kbEdit` 卡恢复成 chip 同一取舍 |
| 截图 harness 没有新 seed | 知识库两种空状态、切换分隔线、内置预设态只有 widget 测试，没有整屏截图 |

### 模型能力审查修复（2026-09-19）

| 条 | 为什么没做 / 要验什么 |
|---|---|
| Anthropic 4.7+ 拒收 `thinking.type: enabled` 的原文 | 方言翻转规则仍是「报文提到 effort 就不翻」。若官方拒收原文顺带建议 `output_config.effort`，翻转永远不会发生。手上没有 Anthropic key，未取到原文 |
| 视频上游时长字段 | 百炼 `usage.duration`、MiniMax `usage.output_seconds` 均为【文档】口径；Veo 的轮询不报时长（xAI 自 4.28.0 起读 `video.duration`）；Sora 已下线 |
| GLM `network_error` 结束原因 | 没有实测样本，未归类（仍按正常结束） |
| 「继续原任务」入口 | 用现有菜单项与按钮样式直接落地，未出设计稿；对上游已终态失败的任务也会显示（重跑轮询会再报一次失败，不计费） |
| l10n `videoResolution` / `videoAspectRatio` | Veo 固定控件删除后已无引用，四语未删 |

### 输入图计费（D2c，2026-09-21）

| 条 | 为什么没做 / 要验什么 |
|---|---|
| 聊天面的输入图张数 | 只有七个 images 协议（含 Midjourney）发布 `input_image_count`。中转站把按张收输入费的模型挂在聊天面（① 出图）上、又配了按规格计费组时，输入费静默记 0。没有真实用例，未做 |
| ~~视频的输入图~~ | 已做（`git show a7e4c8a:docs/plans/2026-09-input-images-all-modes.md`，v4.28.0，设计稿 `D2e`）：xAI `grok-imagine-video-1.5` 实测首帧 / 参考图 $0.01/张后两处一起开——五个视频协议报张数、判据不看单位、按次也收；xAI 视频终态的秒数与报价一并结算。剩的：720p / 1080p 是否加价未测（下表「输入图 4」）；其它视频面不报钱。Sora 与初代 `grok-imagine-video` 已下线（2026-09-22），它们的两条待办（Sora 终态 `seconds` 回显、初代是否收参考图）销掉 |
| 按 token 模式的图像输入单价 | GPT-Image-2 图像输入 $8/M、文本 $5/M，计费组只有一个输入价；`input_tokens_details.image_tokens` 已在回包里。差额很小，未立项 |
| 计费组币种 | 应用一律显示 `$`，Seedream 以人民币标价，用户只能自己换算后填。已有问题，这一轮没碰 |
| ~~xAI 的 `cost_in_usd_ticks`~~ | 已做（`git show e3941d9:docs/plans/2026-09-xai-reported-cost.md`，v4.27.0）：xAI images 协议发布 `reported_cost_usd`，落 `token_usage.reported_cost`（v49），压过三种模式；用量页按 `D2d` 显示「上游报价 \| 档位估算」。剩的：中转协议不翻这个键（中转有自己的价）；把 xAI vendor 指到原样转发 `usage` 的中转时报的是 xAI 收中转的价，不加开关；别家（方舟、OpenAI）不报钱 |
| ~~xAI 的质量参数~~ | 已做（`git show 8d5a5cc:docs/plans/2026-09-xai-quality.md`，v4.26.0）：2.0 发 `quality`（low / medium，默认 medium）与 `1.5k`；初代分到自己的表。剩一条：`auto` 由模型定档、不给；**250 最小面板宽下英文 Medium 仍会省略**（半栏 43px 对 46px），gpt-image-2 的四档轨道在同一宽度下同样——只在用户把栏拖到极限时出现，不做 |
| 明细展开处的版式 | 稿 22g 是六格三行；实现里「输入图」「输入金额」各占一整行——算式在平板半栏放不下（测试抓到 32px 溢出） |

### 火山方舟 · Seedream（2026-09-18）

| 条 | 为什么没做 / 要验什么 |
|---|---|
| Seedance 视频面 | 同一 vendor 的另一条 surface，本轮只做生图。套餐 key 打不到（全部 `404 UnsupportedModel`，§7.1），要按量 key 才能做 |
| 按量 base 的 `GET /api/v3/models` 与 4.5 / 4.0 实机 | 手上只有套餐 key：按量 base 是否有列表、4.x 的档位映射都未实测 |
| 中转站透传方舟 body 的实机 | 按路径同形推断（New API 的火山渠道），未拿中转 key 验证 |
| 「自动」尺寸的计费匹配 | 2026-09-23 给 5.0 pro 加了分辨率「自动」（拆图层够到上游 `auto`）与 `billed_image_count`。「自动」的请求没有尺寸：按档位写的计费组只能落到不写尺寸的行。方舟每项回显 `size`，却不发布 `output_size`；发了也不够——按面积就近归档，2.88 MP 会归到 1.5K（0.3 元），而上游按 261 万像素分界收 0.6 元；拆图层的底图与各层尺寸还各不相同。要么按像素阈值写计费行，要么逐张计价 |
| 链接全部下载失败时不记账 | 方舟已画已扣，协议却因「一张都没拿到」抛错，`LLMService` 的失败路径不写用量行。`billed_image_count` 只修了部分下载失败 |
| 审阅余项（2026-09-23） | 拆图层模式下比例控件仍可选、被静默丢弃（不 warn、不隐藏）；`_seedream30` 的表在 `volcengine-ark.md` 里没有出处；透明背景模式不在本地检查参考图有无透明通道（上游 400 会响，只是白传一遍） |

### 输出上限（2026-09-16）

**需要真实 key 实测**（全部是「写错了不报错」的那类）：

| 条 | 要验什么 | 判据 |
|---|---|---|
| ① 新名 | 官方 OpenAI GPT-5.x 发 `max_completion_tokens` | 200 且 `completion_tokens ≤ cap` |
| ① 旧名 | DeepSeek / 百炼 compatible / MiniMax 发 `max_tokens`（文档都写「已弃用仍接受」） | 仍 200 则声明不动；否则把该 vendor 翻成 `maxCompletionTokens` |
| 本地栈 | Ollama 发 `max_tokens: 65536` 而 `num_ctx` 4096 | 预期静默截短；看编辑器的「≥ 上下文大小」提示够不够 |
| ④ 大 cap | 中转 `max_tokens: 65536` 非流式（refine / rename 路径） | 中转是否要求流式；助手路径已流式 |
| ③ 共用 | Gemini 2.5 指定 8192 + thinking 开 | `MAX_TOKENS` 出现率是否上升 |

**明确留作后续的**：

- 按节写入在「逐条确认关闭」时：第一条写入落盘后 `knowledgeStaleAt` 让该文件的读失效，第二条同文件的节写入被要求先重读——与整文件模式一样，是先读后写护栏的既有行为，没有为节模式放宽。
- 发现时只预填新行的上下文窗口；上限不预填（列表报的是模型最大值，存进去就会随每次请求发出）；已存在的模型不会因为重新「拉取模型」而补上窗口（存量行是用户的）。
- `KbSectionNotFound` 列出的标题包括模型没读过的页；页级读护栏只拦改写，不拦「看见标题名」。

### 大文件拆分（2026-09-16 欠账清扫之后）

- `buildAnthropicHistory` 没有直接测试，只经 payload 测试间接覆盖（拆分前就是如此）。
- **`llm_dispatcher.dart` 仍在 1500 行以上，刻意不拆**（唯一路由表，见上面 `2026-09-large-file-split` 一行）。
  其余 1000–1500 行的文件这一轮拆过一遍（十五个），行数与留下的部分记在欠账清扫那一行指向的执行文档「施工记录」里。

### 需要真实 key 才能定论（来自端点审计第 3 节）

跑完一条就把日期与端点写回 [`../api/`](../api/) 对应文件。

| 条 | 要验什么 | 怎么看 | 为什么静默 |
|---|---|---|---|
| #9 | wan2.7 收不收 `prompt_extend` | 发 `prompt_extend:false` | 可能被忽略 |
| 尺寸 1 | 初代 `qwen-image` / `-plus` / `-max` 只收五个固定尺寸（`1328*1328` 等） | 发一个自由 `宽*高`，看是否 400 | 会响；但若其实收自由尺寸，这几个模型的下拉就是白白收窄了 |
| 尺寸 2 | `wan2.7-image-pro` 改图收不收 `4K` | 带参考图发 `size:"4K"` | 会响（400），或静默降档出图而按 4K 计费 |
| 尺寸 3 | 计费档位按面积就近归档（`spec_billing.dart` `_tierOf`）与百炼实际计价是否一致 | 对照账单：1696×960 是否按 1K 计、1536×1536 按哪档 | **不响**：归错档只会记错钱 |
| 输入图 1 | Seedream 5.0 pro「首张免费」是否按每次请求 | 对照账单：两次各带 1 张参考图的请求，输入费是否为 0 | **不响**：应用按每次请求扣一次，若上游按账期只免一张，每次改图少记 0.02 元 |
| ~~输入图 2~~ | 一次请求出多张（xAI `n>1`）时输入图收一次还是乘张数 | **已测（2026-09-22）**：`n:2` + 1 张参考图 + low → 900 000 000 ticks = 2 × $0.04 + **1** × $0.01，按请求收一次（`api/usage.md` §5） | 应用的「每次请求收一次」是对的 |
| 输入图 3 | xAI 请求失败 / 被审核拦下时是否仍收输入费 | 对照账单（失败的回包里有没有 `cost_in_usd_ticks` 也值得看一眼） | **不响**：应用在一张图都没交付时不记输入费 |
| 输入图 4 | xAI 视频 720p / 1080p 是否在 $0.08/s 之外加价 | 各发一次 1 s 看终态 `cost_in_usd_ticks`（约 $0.1 一次） | **不响**：档位表按用户填的算，报价在终态才压过；不测只是提交时的估算不准 |
| 片 4 | 官方 ④ `adaptive` 是否真的开出思考 | 响应 `content` 有无非空 `thinking` block | **配置不合法时静默关闭** |
| 片 5 | `pause_turn` 续跑；MiniMax `end_turn` 停在结果块 | 第二次请求是否 200、模型是否接着写 | MiniMax 变体无任何字段说明 |
| 片 9 | DeepSeek 官方 `thinking:{type:disabled}` 是否关掉 | 响应 `reasoning_content` 是否为空 | 不报错 |
| 片 7 | 中转 chat 路由回包形状 | 同一请求跑两次 | 形状随渠道轮换 |

### LLM 审计轮（2026-09-14，#263–#269）

**需要真实 key 实测**（全部是「写错了不报错」的那类，判据写在右列）：

| 条 | 要验什么 | 判据 |
|---|---|---|
| ④ 收尾轮 | 助手/子代理最后一轮撤掉 `tools`，但历史里还有 `tool_use`/`tool_result` | 官方 ④ 是否 200；若 400，改为带工具发 `tool_choice:none` |
| ③ thinking | Gemini 3 发 `thinkingLevel` + `includeThoughts` 是否回 thought parts；2.5 的 budget 档位 | 控制台有无思考文本；3.1 Pro / 2.5 Pro 的「关闭」应 400 |
| 百炼 ① | qwen3-max 发 `enable_thinking:true` 是否回 `reasoning_content`；`enable_search` 是否真搜 | 前者看字段；后者只能用时效性问题对比开关前后（该面无来源） |
| ② Responses | New API 上 GPT-5.x 点单 Responses：工具往返、输入 token 无注入系统提示；xAI 回 `encrypted_content` | 输入 token 量级；reasoning 条目字段 |
| ① system 行 | 恒发的中性 system 行在拒收 system 角色的模型（部分 Gemma 兼容面）上是否 400 | 状态码 |
| 视频续轮询 | 提交后退出 App 再开 | 同一 job id 续轮询、无第二次提交；百炼/MiniMax 下载不带鉴权头 |

**明确留作后续的**：

- ② Responses 未接 `text.format` 结构化输出、内置 web search、`previous_response_id`。（xAI 默认面已于 2026-09-15 切到 Responses；OpenAI / NewAPI 的渠道级 Responses 预设见 #271。）
- 百炼 ① 面按 vendor 声明走 `enable_thinking`，Qwen 3.7+ 因此失去强度档；要保留需要模型级方言列。
- ③ 协议类停止原因（`MISSING_THOUGHT_SIGNATURE` 等）有部分内容时仍按成功交付 + WARN。
- 结构化输出链（强制工具 → JSON mode）整体未接；目前没有调用方需要，`toolChoice` 选项协议侧已能读。

### 按规格计费（D2b 稿，已合入；三处与稿不同）

- **自定义取值的输入位置**：稿 21c 是在菜单底部就地变输入框；实现是菜单关闭后条件字段本身变成输入框（回车提交、Esc 退回、空 = 任意），归一提示放在字段 tooltip。玻璃菜单没有可编辑行，改组件不值得。
- **菜单选中项**：稿是 tint 底 + check；实现用行首 check 图标标记当前值，未做 tint 底（`AppGlassMenuItem` 的 checked 会画成复选框）。
- **记住过的自定义值**：稿说本地记住、下次出现在组尾；实现只把当前表里已有的自定义值列进菜单，不跨会话记忆。
- 用量页分组区图例行（输入 / 缓存 / 输出 / 按次·按规格）稿里有、现有页面本来就没有，未加。

### 费用组页面（D2 稿 1d–1h，已落地；与稿的六处出入）

落地的：头行（标题 + mono 计数 · 筛选 · 排序钮 · 新建组）、桌面双栏（左列表 / 右编辑卡或虚线占位卡，两栏位置不动）、组卡选中态、编辑卡下的「删除组」与保存置灰规则（组名非空 + 价格合法）、切组时未保存改动的确认、Esc 取消、排序（悬停把手 / 排序模式常显把手 / 右键菜单上移下移 / Alt+↑↓）、平板单栏（编辑卡插到组卡下方）、手机列表 + 全屏编辑页（底部玻璃栏保存、AppBar 删除、页尾列出使用它的模型、AppBar swap_vert 进入显式排序模式）。顺序存在 v43 的 `fee_groups.sort_order`，模型 / 渠道编辑框的费用组下拉跟着走。代码：`widgets/models/pricing_group_manager.dart`（宿主与布局）、`widgets/models/fee_group_{draft,editor_fields,row,edit_page,dialogs}.dart`。

- **卡片宽度**：稿是 1000 居中；实现通栏，与用量标签页的卡片流一致（那一页本来就不居中）。
- **落点指示**：稿是 2px 主色线横贯行间隙；实现沿用全应用的「空位即落点」（`00d`，`AppReorderGap` 的 tint 虚线空位 + 「放到第 n 位」）。
- **术语**：稿写「费用组」，代码与四种语言的文案一直是「费率组 / Fee Groups」，未改名。
- **按组统计的顺序**：稿的占位说明说顺序同步到用量页的按组统计；那一块按花费降序更有用，未改，占位文案只提模型 / 渠道编辑框的下拉。
- **筛选框**：只在桌面头行出现（稿 1h 的平板头行本就没有）；平板和对话框靠悬停把手与右键菜单排序。
- **保存之后**：稿 1f 说新组保存后保持选中；实际用下来「保存了却没关」像没保存，改成保存即关闭编辑卡（新组仍追加到末尾）。
- **名字里的括号**：稿没有；组名里成对的 `()` / `[]`（含全角）内容拆成名字旁的 badge（`parseFeeGroupName`），只在组卡上，编辑框和下拉仍显示原名。
- **桌面的滚动**：稿是整页滚动；实现改为卡片撑满标签页、头行固定、左列表和右编辑卡各自滚动（`PricingGroupManager.fill`）。整页滚时点下方的组，编辑卡被带到视口上方，每改一格都要来回滚。带着组进来（用量页「去补档位」）和 Alt+↑↓ 移动时列表会把选中行滚进视野。平板仍整页滚，编辑卡就插在被点的行下面。

### 模型编辑框（D2a 稿，欠账清扫之后）

三条已做（参数块引导线点单时补间到主色 35%、菜单选中行 check、点单态值用主色深）。与稿的出入：

- 设计稿这轮没读到（DesignSync 未授权），数值取自 `git show 6a4f358` 里的 D2a 简报；**没有对照稿复核**。
- 「能力 / 代理行为区块的下级缩进」没做：这两个区块没有受管辖的下级行，引导线只属于请求方式下的参数块。
- 共享 `AppDropdown` 的选中底仍是 Material 自带的；只加了 check。`ModelEditMenuField` 用的是 12% `accentTint`（阶梯上没有 10%）。

### 安全（2026-06 审查的 S1 / S3，欠账清扫里按「明说」处理）

同批的 S2、S4、S5 早已修。S1 与 S3 这一轮做了，**但没有做加密**，理由写在欠账清扫的执行文档
「决策记录」：本机构建是 ad-hoc 签名，`flutter_secure_storage` 在 macOS 上要么失败要么每次重签都弹授权；
Linux 构建没装 libsecret、最小桌面常无 keyring；便携模式下钥匙串不跟着数据库走。做了的：

- **S1**：三处填 key 的地方如实写明「明文存于本机数据库、只受系统账户的文件权限保护、不进备份」；macOS / Linux
  上数据库 600、数据目录 700（便携模式只收紧文件）；代理密码导出置空、恢复时保留本机的。
- **S3**：`CookieRepository` 的保留期（不记住 / 7 天 / 30 天默认 / 直到清除）、逐条删除、清空入口；
  任务行不再存 cookie（旧行启动时清洗，重启后恢复的下载按 host 回查历史）。

仍然成立的：key 与 cookie 在本机数据库里是明文，同一用户的其他进程可读。要真加密，前提是
正式签名的 macOS 构建（带 `keychain-access-groups`）和 Linux 的 libsecret 依赖，单开一轮。

其余 66 条按 v2.3.0 的行号写成，未逐条复核。
