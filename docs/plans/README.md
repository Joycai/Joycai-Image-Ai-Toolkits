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
| `2026-09-assistant-output-cap.md` + `-execution.md`（八片，分支 `claude/assistant-output-cap`，一片一个 commit） | 提示词助手输出截断：模型级「最大输出」（v44 `llm_models.max_output_tokens`、协议唯一读口 `outputCapFor`、① 字段名按 `VendorProfile.outputCapField` 声明、④ 的 8192 退为兜底、编辑器区块 + 卡片 chip、发现时按键形预填上下文窗口——上限刻意不预填）；截断对策（`length` 的半截调用一个不跑、配有指向的 `output_truncated` 结果、连续两次即停并跳到模型设置，子代理同款）；压缩摘要由 App 附最新提示词而不再让模型重抄（跨次压缩接力）；四个模式提示加「交付前不写散文」；子代理 note 限长；`write_knowledge_file` 按节写入（`replace_section` / `append`，拼好后仍 stage 整文件） | `architecture/llm-three-layer.md`「输出上限」、`architecture/assistant-context.md`「The output side」与不变量 12–13、`api/usage.md` §3；设计稿链接在前者。方案原文 `git show 671f987:docs/plans/2026-09-assistant-output-cap.md`。欠的并入下面「还欠的」 |

三份审计报告（`code-review-report-20260613.md` v2.3.0、`api-standards-audit.md`
基线 `d03047e`、`2026-08-ai-capability-review.md` 基线 `6a4920d`）都是带完整
`file:line` 的快照，三层重构与液态玻璃翻新之后每一个行号都已失效。前两份自己就
带着「⚠️ 历史文档」抬头。要重新体检跑一次 `/code-review` 或 `/security-review`，
不要照着旧快照改。

## 还欠的（2026-09-12 对照 main 逐条复核过）

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

- 截断标记（`OptimizerChatEntry.truncated` / `modelDbId`）只在内存里；重启后恢复的会话不再显示尾部标记与跳转（历史里没有 finish reason）。
- 按节写入的预览卡仍是整文件 diff；一节的改动在长文件里要滚着看。
- 按节写入在「逐条确认关闭」时：第一条写入落盘后 `knowledgeStaleAt` 让该文件的读失效，第二条同文件的节写入被要求先重读——与整文件模式一样，是先读后写护栏的既有行为，没有为节模式放宽。
- 发现时只预填新行的上下文窗口；上限不预填（列表报的是模型最大值，存进去就会随每次请求发出）；已存在的模型不会因为重新「拉取模型」而补上窗口（存量行是用户的）。
- `KbSectionNotFound` 列出的标题包括模型没读过的页；页级读护栏只拦改写，不拦「看见标题名」。

### 大文件拆分（2026-09-16，八片之后）

- **`runTurn` 仍是 541 行**（`prompt_optimizer_agent.dart`）。它是 tool loop 本体，拆它要动控制流，
  和「搬家」不是一类工作。
- **拆出来的卡片还是 State 上的 extension，不是独立 widget。** 要收窄 rebuild 范围（例如
  `PromptOptimizerChatView` 每次 session 通知都 `setState` 整个 view）得真的抽 widget —— 先用
  `render_probe` 量，再决定值不值。
- **AI 重命名的「覆盖」禁用态没有任何截图或 widget 测试。** harness 从不展示 review 行；要种出这些行
  得 stub 一次模型调用，`AiRenameDialog` 没有给测试留这个口子。
- **视频面板在 1440×900 下参考图区只露出一条**，缩略图被裁掉大半（`workbench_*_video_filled.png`，
  空态也一样）。没查是刻意的折叠还是布局问题。
- **`WorkbenchUIState.addVideoReferenceImage` / `removeVideoReferenceImage` 原地改列表再
  `notifyListeners()`**，与 CLAUDE.md「先建新实例」的规则不符；任何 `select` 这个列表的地方都看不到变化。
- **1000–1500 行之间还有 14 个文件**（`crop_resize_toolbar` 1472、`llm_service` 1431、
  `model_capabilities` 1330、`task_queue_card` 1294 领头）。这一轮只做了 1500 以上的。
- `buildAnthropicHistory` 没有直接测试，只经 payload 测试间接覆盖（拆分前就是如此）。

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

- 视频提交、Midjourney 提交与各轮询 GET 未走 `sendJsonRequest`，取消不能中止在途请求。
- ② Responses 未接 `text.format` 结构化输出、内置 web search、`previous_response_id`。（xAI 默认面已于 2026-09-15 切到 Responses；OpenAI / NewAPI 的渠道级 Responses 预设见 #271。）
- 百炼 ① 面按 vendor 声明走 `enable_thinking`，Qwen 3.7+ 因此失去强度档；要保留需要模型级方言列。
- ③ 协议类停止原因（`MISSING_THOUGHT_SIGNATURE` 等）有部分内容时仍按成功交付 + WARN。
- 旧存的 `enable_web_search` 标记在百炼 ④ 面上仍会发 `web_search` 工具（编辑器已不再提供该开关）。
- 结构化输出链（强制工具 → JSON mode）整体未接；目前没有调用方需要，`toolChoice` 选项协议侧已能读。
- ① 同步路径「no choices」仍抛裸 `Exception`；`LLMMessage.fromJson` 仍把未知 role 强转为 user（恢复时的修复已兜住后果）。

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

### 模型编辑框（D2a 稿，三条当轮明确留在范围外）

- **18a 右栏的 2px 引导线与下级缩进**：18a 时期就没实现，D2a 的「引导线补间到主色」
  依赖它；补上要重排能力 / 代理行为两个区块的结构，单开一轮。
- **菜单选中项的 check + 主色 10% 底**：`AppDropdown` 基于 Material `DropdownButton`，
  选中高亮是它自带的；自绘选中态要换组件。
- **点单态的协议字段值用主色深**：只换了描边与底两个 token，值仍是正文色。

### 安全（2026-06 审查里复核后仍成立的两条）

同批的 S2（备份导出带明文 key）、S4（拼接 SQL）、S5（AI 改名不消毒文件名）都已修
（`database_service.dart:373`、`prompt_repository.dart:62`、`ai_rename_agent.dart:297`）。
剩下这两条没有：

- **S1 · API Key 明文存于 SQLite**（`llm_channels.api_key TEXT NOT NULL`）。桌面上
  数据库就在应用数据目录里，本机任何进程可读。`pubspec.yaml` 至今没有
  `flutter_secure_storage`。要么换钥匙串存储，要么在首次配置时明说。
- **S3 · Cookie 明文存于 `downloader_cookies` 且无过期**。导出那一半已经修了
  （`database_service.dart:380` 同样置空），至今没有的是加密存储、会话生命周期
  选项，和一个「清除 Cookie 历史」的入口。

其余 66 条按 v2.3.0 的行号写成，未逐条复核。
