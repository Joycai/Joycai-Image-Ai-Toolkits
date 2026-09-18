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
| `2026-09-ui-rewrite-feature-inventory.md` + `-liquid-glass-design-prompt.md` | 液态玻璃翻新的功能对照表与出稿 brief（PR #219 已合入） | `architecture/design-tokens.md`。功能清单拍的是翻新**之前**的 v3.33.0，翻新之后它描述的界面已不存在 |
| `2026-09-multi-directory-nav-outline.md` + `-design-prompt.md` | 多目录导航条（设计稿 `A1b`）：画廊与文件浏览器勾选多目录后的 chip 索引、scroll-spy、四级宽度降级；浏览器补「按文件夹分组」；排序菜单改玻璃 Float（PR #248、#249） | 偏移表与 spy 在 `core/folder_outline_geometry.dart` / `folder_outline_spy.dart`（跳转靠算不靠量，视口外的 sliver 没有 RenderObject）；chip 条 `widgets/files/folder_outline_bar.dart`；分组 `FileBrowserState.groupByFolder / folderSections`；玻璃菜单的单选 / 复选 / 说明行 `AppGlassMenuItem.checked / radio / hint`。与稿的两处出入：跳转落点是组标题顶边贴判定线（标题自带 10px 上留白即稿子的 +12）；折叠 chip 的菜单行无路径副行 |
| `2026-09-spec-based-billing.md` + `-design-prompt.md` | 计费组第三种模式「按规格」：单位（张 / 秒 / 条）× 档位表（尺寸 · 质量 · 时长三个可选条件 + 单价，填得最多的行优先，全空行兜底）；请求的规格从工作台参数读、OpenAI Images 回显的实际尺寸优先；单价与数量快照进用量行，读时算钱 | 非 UI 部分已落地：v42 迁移（`fee_groups.output_unit / output_rates`、`token_usage.output_*` 四列）、`models/spec_rate.dart`、`services/llm/output_spec.dart`（归一化）、`services/billing/spec_billing.dart`（匹配与计价）、`LLMService.specUsageFor`（三条记录路径共用的纯函数）、`usage_stats.dart` 的 `spec` 部分与 `usageRowUnmatched`。视频仍在提交时计费（同按次）。UI 按 D2b 稿落地：`widgets/models/spec_rate_table.dart`（单位 chip + 档位表 + 校验）、`widgets/models/fee_group_summary.dart`（三种模式同一格式的摘要）、`services/billing/spec_known_values.dart`（条件取值 = 家族参数表 ∪ 协议参数表 ∪ `VeoResolution`）；用量页分组行数量列、未匹配提示与「去补档位」、明细「规格」列。与稿的出入见下面「还欠的」 |
| 2026-09-14 LLM 层对照 `ai-agent-architecture` skill 审计（无方案文件；五路只读审计 → 六个分支） | 修：chat wire 完整性（内容拦截一律抛、截断/空 200/半截工具调用不再当成功、`<think>` 只认开头、③ 调用 id 唯一、回传载体按模型作用域）#265；计费与媒体（计费面接受后不重试、视频任务 id 落库并跨重启续轮询、下载校验与不给签名链接带 key、`LLMConfigException`）#263；助手运行时（恢复时修配对、压缩失败不动历史、KB 应用前复核磁盘、收尾轮撤工具）#266。补：Gemini `thinkingConfig` 与 raw parts 回传、百炼 ① 面 `enable_thinking` / `enable_search` #268；Retry-After、可中止请求、上下文预检、日志脱敏与关联 #267；OpenAI Responses 协议面 #269 | `architecture/llm-three-layer.md`（chat wire 完整性、Responses 两节）、`architecture/assistant-context.md`（不变量 10–11）、`api/responses.md`、`ai-agent-playbook/`（与 skill 同步，#264）。欠的并入下面「还欠的」 |
| D2 `用量统计` 稿 1d–1h（无方案文件，直接按稿施工） | 费用组页面：头行 + 桌面双栏 / 平板单栏 / 手机全屏页，拖拽排序（v43 `fee_groups.sort_order`） | `widgets/models/pricing_group_manager.dart` 与 `widgets/models/fee_group_*.dart`；与稿的出入见下面「还欠的」 |
| `2026-09-large-file-split.md`（八片，分支 `claude/split-*`，一片一个 PR） | 1500 行以上的八个文件拆开：`prompt_optimizer_agent` 4207→1352 · `prompt_optimizer_view` 2759→595 · `video_config_panel` 1947→573 · `openai_chat_protocol` 1784→796 · `anthropic_chat_protocol` 1670→420 · `directory_tree_item` 1593→701 · `ai_rename_dialog` 1510→477 · `model_edit_dialog` 1497→290。两种手法：并列的顶层单元拆成独立库（两个协议、`widgets/files/folder_drop_feedback.dart`、`folder_tree_row.dart`）；一个大类或大 State 用 `part` 拆，私有 static 变库私有顶层声明、State 的 builder 变 State 上的具名 extension —— **元素树一个节点不变**，所以没有把卡片改成独立 widget。顺带：`browser` 不再横向引 `workbench`；问答卡的虚线用回共享节奏；**AI 重命名的冲突逻辑下沉到 `services/tasks/ai_rename_review.dart` 并第一次有了测试，由此找到并修掉一个会删用户照片的 bug**（两行重名时点「改名」原样还回同名、「覆盖」删掉另一行刚放好的文件；现在 review 与 executor 两层都拒绝，UI 上禁用并说明）。**`llm_dispatcher.dart`（1586 行）刻意没拆：它是唯一路由表，拆开就违反那条不变量 —— 按行数扫到它不要立项。** | ④ 的文件 ↔ 不变量对照在 `architecture/llm-three-layer.md` ④ 一节；助手七个文件在 `architecture/assistant-context.md`「Where it lives」；CLAUDE.md 的 map。拆分手法与各片的坑（插值里补类名会静默编译通过、extension 里库作用域优先于 `this`、截图要比像素不比字节）在上面 `git show` 的方案原文里 |
| `2026-09-assistant-output-cap.md` + `-execution.md`（八片，分支 `claude/assistant-output-cap`，一片一个 commit） | 提示词助手输出截断：模型级「最大输出」（v44 `llm_models.max_output_tokens`、协议唯一读口 `outputCapFor`、① 字段名按 `VendorProfile.outputCapField` 声明、④ 的 8192 退为兜底、编辑器区块 + 卡片 chip、发现时按键形预填上下文窗口——上限刻意不预填）；截断对策（`length` 的半截调用一个不跑、配有指向的 `output_truncated` 结果、连续两次即停并跳到模型设置，子代理同款）；压缩摘要由 App 附最新提示词而不再让模型重抄（跨次压缩接力）；四个模式提示加「交付前不写散文」；子代理 note 限长；`write_knowledge_file` 按节写入（`replace_section` / `append`，拼好后仍 stage 整文件） | `architecture/llm-three-layer.md`「输出上限」、`architecture/assistant-context.md`「The output side」与不变量 12–13、`api/usage.md` §3；设计稿链接在前者。方案原文 `git show 2e7f443:docs/plans/2026-09-assistant-output-cap.md`。欠的并入下面「还欠的」 |
| `2026-09-debt-sweep-execution.md`（二十二片 + 四次 review，分支 `claude/debt-sweep-4.9`，v4.9.0） | 清「还欠的」里用户点名的三组。① 代码：state 换新列表（视频参考图 / 文件夹切换 / 下载器日志）；视频面板头部放不下时整栏单滚动；AI 重命名「覆盖」禁用态的测试口子；截断标记与 `modelDbId` 跨重启（`LLMMessage` 上的宿主簿记字段）；按节写入的卡片标出节名、hunk 头带所在标题；九个协议的「200 里什么都没有」改抛 `LLMApiException`、`fromJson` 拒收未知 role；`VendorProfile.webSearchOn` 让编辑器与三个 payload 同答，百炼 ④ 面不再带 `web_search`。② 动效：「还欠的」七条全做（见 `plans/README.md` 第四轮）。④ 决策项：S1 / S3 走「明说 + 文件权限 + 生命周期」不上钥匙串（理由见执行文档「决策记录」）；`runTurn` 拆出四个 helper；助手一次 session 通知 1,122 → 29 次 build（`ListenableSelector`）；D2a 三条；十五个 1000–1500 行文件拆分。**与台账不符的两条**：视频 / MJ 请求早已走 `sendJsonRequest`；timeout 取证的「① 累积器」早已落地 | `architecture/assistant-context.md`（Where it lives 九个文件、截断标记持久化）、`architecture/llm-three-layer.md`（联网搜索同一答案、`llm_errors.dart`、`model_capability_tables.dart`）、`architecture/design-tokens.md`（`accentRule`、`AppMotion.sceneFor`）、`plans/README.md`、CLAUDE.md map。执行文档原文 `git show 99b2784:docs/plans/2026-09-debt-sweep-execution.md`（施工记录里有每片的偏离与量出来的数字）。欠的并入下面「还欠的」 |
| `2026-09-seedream-execution.md`（七片 + 两次 review，分支 `claude/seedream-image-model-support-f4e87c`，v4.10.0） | 火山方舟 Seedream 生图：`Vendors.volcengineArk`（按量 `/api/v3` · 套餐 `/api/plan/v3` 两个同类型变体）+ `WireProtocol.arkImages` + `ModelFamily.seedreamImage` 按版本出表（5.0 pro · 5.0 lite · 4.5 · 4.0 · 3.0 + 兜底）；尺寸 = 档位 + 比例查表；水印明发默认关；5.0 pro「任务」三段（生成 / 拆图层 / 透明编辑）；中转上认得出的 Seedream 走方舟 body；组图放宽超时。顺带：变体按地址回读、同族变体卡印路径、按规格选单收 id 表。设计稿 Claude Design `D1e`。套餐端点实机出图验证 | `architecture/llm-three-layer.md`「火山方舟 · Seedream」、`api/volcengine-ark.md`（含 §7 实测）。执行清单原文 `git show 294432d:docs/plans/2026-09-seedream-execution.md`（决策记录 13 条、施工记录每片的偏离）。欠的并入下面「还欠的」 |
| `2026-09-channel-route-model.md` + `-execution.md`（十六片 + 三次评审，分支 `claude/channel-route-model-*`，PR #304 · #305 · 本轮） | 渠道 × 线路 × 模型：一份密钥一个渠道，渠道下每个协议族一条线路（v45 `llm_channels.routes` 内嵌文档、`llm_models.active_route / route_params`，读时迁移、请求逐字节不变——真实发请求比对），模型选当前线路、每条线路独立参数、切线路空白起步；改主线路先钉住跟随者；同密钥旧渠道只检测、逐组确认合并（加「请求不变」闸）；界面按 D1f：渠道栏平台 + 线路徽标、渠道编辑线路表与实际地址、向导平台优先建全部线路、模型编辑线路条与差异卡、合并审阅 | `architecture/llm-three-layer.md`「渠道 × 线路 × 模型」与红线表；代码 `services/llm/{channel_routes,model_routes}.dart`、`vendors/platforms.dart`、`services/catalogue/{route_switching,channel_merge,channel_merge_executor}.dart`。原文 `git show 9e90547:docs/plans/2026-09-channel-route-model{,-execution}.md`（执行清单的施工记录有每条偏离的理由）。欠的并入下面「还欠的」 |
| `2026-09-ark-image-stream-execution.md`（四片 + 一次 review，分支 `claude/ark-live-tests`，与套餐实测文档同一 PR） | Seedream 流式出图：方舟自家渠道上 5.0 lite / 4.5 / 4.0 发 `stream: true`，逐张下载推出；空闲守卫按单图期限计；执行器边到边存。中转与 5.0 pro 照旧同步。顺带：套餐实测补了 chat 面思考开关（不需要方言）、流式事件形状、拆图层响应形状 | `architecture/llm-three-layer.md`「火山方舟 · Seedream」流式一条、`api/volcengine-ark.md` §5 · §7 · §7.1。执行清单原文 `git show a305018:docs/plans/2026-09-ark-image-stream-execution.md` |
| `2026-09-channel-route-followups-execution.md`（八片 + 两次评审，分支 `claude/channel-route-followups`） | 渠道 × 线路欠账清零：合并连助手对话里的模型链接一起改写（库里的行与打开着的会话）、合并审阅把已选模型 / 用量记录 / 对话链接分开计数；换预设与向导同源建平台全部线路；路径「主机本身」一态（自定义平台给「用主机本身」）；联网矩阵「未实测」第三态（画像声明 `untestedWebSearch`）；向导每条线路的私有能力一词；作用域灰字紧跟标题（`AppSectionLabel.suffix`）、手机线路条横向滚动。渠道栏副行不显示渠道标签维持设计 ① 原意 | `architecture/llm-three-layer.md`「渠道 × 线路 × 模型」。原文 `git show 8285ca7:docs/plans/2026-09-channel-route-followups-execution.md`（裁定表与施工记录） |

三份审计报告（`code-review-report-20260613.md` v2.3.0、`api-standards-audit.md`
基线 `d03047e`、`2026-08-ai-capability-review.md` 基线 `6a4920d`）都是带完整
`file:line` 的快照，三层重构与液态玻璃翻新之后每一个行号都已失效。前两份自己就
带着「⚠️ 历史文档」抬头。要重新体检跑一次 `/code-review` 或 `/security-review`，
不要照着旧快照改。

## 还欠的（2026-09-12 对照 main 逐条复核过；2026-09-16 欠账清扫后更新）

### 火山方舟 · Seedream（2026-09-18）

| 条 | 为什么没做 / 要验什么 |
|---|---|
| 拆图层的 `bounding_box` / `z_index` / `name` 落库与画布还原 | 现在底图 + 图层按叠放次序逐张落盘，位置信息只写日志。响应形状已实测（`api/volcengine-ark.md` §7），解析无需改 |
| Seedance 视频面 | 同一 vendor 的另一条 surface，本轮只做生图。套餐 key 打不到（全部 `404 UnsupportedModel`，§7.1），要按量 key 才能做 |
| 按量 base 的 `GET /api/v3/models` 与 4.5 / 4.0 实机 | 手上只有套餐 key：按量 base 是否有列表、4.x 的档位映射都未实测 |
| 中转站透传方舟 body 的实机 | 按路径同形推断（New API 的火山渠道），未拿中转 key 验证 |

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
- `modelKindIcon` 在 `widgets/ui/model_tag_chip.dart` 与 `widgets/models/model_edit_controls.dart` 各声明一份（拆分时发现，未合并）。

### 需要真实 key 才能定论（来自端点审计第 3 节）

跑完一条就把日期与端点写回 [`../api/`](../api/) 对应文件。

| 条 | 要验什么 | 怎么看 | 为什么静默 |
|---|---|---|---|
| #2 | wan2.7 顶层 `messages` vs `input.messages` | 各发一次，看状态码 | 会响（400），但不试就不知道这条路通不通。与 dashscope 方案 §7.3 是同一条 |
| #9 | wan2.7 收不收 `prompt_extend` | 发 `prompt_extend:false` | 可能被忽略 |
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
