# 07 · Agent Runtime：preset 驱动的 tool loop 与事件系统

> 本篇解决的问题：一个应用里往往有多种 AI 任务——续写、结构化提取、对话助手、子代理调查——如果每种任务各写一个循环，工具协议不变量（tool_call 配对、abort 配平、上下文裁剪）就会被复制 N 份并各自腐坏。本篇规定一种**唯一的 tool loop 实现**（runtime），由纯数据的 **TaskPreset** 驱动其行为差异，并通过结构化 **AgentEvent** 流向 UI 汇报进展。工具注册、权限分级与写入安全见第 08 篇；工具动态路由与子代理见第 09 篇；结构化输出双路径详见第 04 篇。
>
> 参考实现：simple-ai-writer `src/lib/agent/runtime.ts` / `presets.ts` / `events.ts` / `logModel.ts`。

---

## 1. 总体架构与五条核心设计决策

分层骨架（自上而下）：

```
UI 层（各任务面板 / 对话界面 / 各类 modal）
   │ 以 TaskPreset 启动，注入回调（onEvent / onOutputText / requestApproval…）
   ▼
会话与审批 store        ← 审批队列（pending / pendingPlans / pendingRoundLimits）
                          + 对话会话（wire 历史数组 + 展示层 turns）
   ▼
runtime.ts              ← runAgent：多轮 tool loop、trimHistory、round-limit、abort
registry.ts             ← REGISTRY: Record<ToolId, RegisteredTool>（定义 + access + 执行器）
presets.ts              ← TaskPreset（tools / maxRounds / finishPolicy / scratchpad / serverTools）
plan.ts / backup.ts     ← 领域数据写入的方案门控、写前备份（见第 08 篇）
   ▼
流式客户端（streamCompletion 多协议 SSE；ConnOptions 作为传输配置的唯一切面）
```

迁移到任何新项目时，以下五条决策是**必须保留的骨架**，不是可选风格：

1. **runtime 只做循环，不做策略。**哪些工具可用、跑几轮、怎么收尾，全部由 preset 数据决定；工具执行一律查注册表分发，runtime 内**绝不允许出现 `switch(toolName)` 硬编码**。加任务 = 加一个 preset 常量；加工具 = 在注册表登记一项。
2. **权限不在 runtime 里执行，在工具执行器里执行。**runtime 无差别调用 `executeRegisteredTool`；L1 自动写的备份、L2 审批写的阻塞、方案门控，全部在各工具的 `execute` 内部完成。`access` 字段更多是声明/文档/UI 用途，不是 runtime 的分支依据。
3. **审批 = Promise 挂起。**L2 工具在 execute 内 `await ctx.requestApproval(proposal)`，整个 tool loop 同步阻塞在这里，直到用户在 UI 卡片上批准/拒绝。批准后的落盘由**审批方**（store）完成，工具本身永不直接写用户核心内容。
4. **错误全部回给模型。**执行器不 throw（注册表捕获后转成 `Error: ...` 文本结果）：坏调用变成模型下一轮可读、可纠正的信息，单次坏调用不杀死整个运行。
5. **history 即会话。**runtime **原地 mutate** 调用者持有的 messages 数组；对话场景把同一数组跨轮复用，上一轮的 tool 调用与结果留在上下文里供下一轮指代。因此协议完整性（每个 tool_call 必须有配对回复）是**生死攸关的不变量**——历史一旦畸形，此后每一轮都会被 provider 拒绝，会话永久报废。

---

## 2. runtime 契约（输入 / 输出）

参考实现：simple-ai-writer `src/lib/agent/runtime.ts`。

```ts
export interface AgentRuntimeOptions extends ConnOptions {
  // 传输层字段全部来自 ConnOptions（baseUrl / apiKey / standard / modelId /
  // contextSize / maxOutput / reasoningEffort / thinkingDialect / serverTools…），
  // 用 connOptions(conn) 构造。新增传输字段只改 ConnOptions 一处。
  inputCeilingTokens?: number;              // 上下文预算规划器给出的输入上限
  extraBody?: Record<string, unknown>;      // 额外顶层请求字段（如 JSON mode 的 response_format）
  preset: TaskPreset;
  messages: StreamMessage[];                // 种子历史：system + 首个 user；被原地追加
  toolContext: ToolContext;
  signal: AbortSignal;
  onEvent: (event: AgentEvent) => void;
  onRoundLimit?: (roundsUsed: number) => Promise<RoundLimitDecision>;  // 轮次上限时阻塞询问
  onOutputText: (fullText: string) => void; // 快照式全量输出：调用方赋值，而非追加
}

export interface AgentRunResult {
  rounds: number;
  inputTokens: number; outputTokens: number; cachedTokens: number;
  outcome: "completed" | "paused";   // paused = 用户在轮次上限选择了「存盘暂停」
}
```

两个关键契约，应当写进接口文档并在 code review 中守住：

- **不变量：messages 原地 mutate。**调用者持有的数组就是完整成绩单。会话场景直接把它当持久历史存起来，下一轮继续传入。runtime 不复制、不返回新数组。
- **不变量：onOutputText 是快照，不是增量。**只有 runtime 知道某一轮的文本最终「不算输出」——模型在调工具前说的「我先去找文件列表。」是自言自语，不是答案。文本照常流式显示，但一旦该轮以工具调用结束，整段回滚（`onOutputText(committedText)`，即撤回到上一次已确认的全文）。快照式接口是唯一能自然表达「撤回」的形式；增量接口做不到。被丢弃那一轮做了什么由执行日志记录，信息不丢失。
  - 陷阱：若用增量接口，「工具轮的自言自语」会被插进用户文档（实际事故：一句「我先去找文件列表。」混进了正文）。

---

## 3. round 循环完整骨架

以下伪代码是**可照抄的实现规范**（参考实现：simple-ai-writer `src/lib/agent/runtime.ts` 的 `runAgent`）：

```
for round in 1..maxRounds:                         // maxRounds 可被 onRoundLimit 中途扩大
  if signal.aborted: throw AbortError
  isLastRound = round === maxRounds

  ── 轮次上限询问（仅 force-text + 有工具 + round>1 + 提供了 onRoundLimit）──
  if isLastRound && …:
      decision = await opts.onRoundLimit(round - 1)   // 阻塞（如同审批）
      pause  → return { …, outcome: "paused" }        // 干净退出点：轮首，历史必然配对完整
      extend → maxRounds += decision.rounds; isLastRound = false
      finish → 继续走强制成文

  ── 强制成文与工具撤除 ──
  withholdTools = tools为空 || (isLastRound && finishPolicy === "force-text")
  若强制成文：push 一条临时 user 消息（轮次上限提示），请求发出后 splice 移除

  ── checkpoint 提示（scratchpad: "required" 且历史 > ceiling*0.85）──
  push 临时 user 消息：「上下文接近上限即将裁剪，用 write_note 把关键结论写进笔记」
  同样在 finally 中撤回；checkpointArmed 防重复，trim 发生后重新武装

  ── 裁剪 ──
  dropped = trimHistory(history, inputCeilingTokens)
  dropped > 0 → emit {kind:"context-trimmed", count}

  emit {kind:"round-start", round, maxRounds, estInputTokens}

  ── 一次流式请求 ──
  await streamCompletion({ ...pickConnOptions(opts), messages: history,
      extraBody, tools: withholdTools ? undefined : toolDefinitions,
      serverTools: withholdServerTools ? undefined : opts.serverTools,
      signal, onChunk })
  onChunk 分支：
    reasoning   → 累积 + 反复 emit 同一条 {kind:"reasoning", round, text, done:false}
    turnResumed → emit {kind:"turn-resumed"}（端点分腿续传可见化）
    serverTool  → emit 日志行（端点自跑的工具，绝不进 roundToolCalls）
    text        → roundText += chunk; onOutputText(committedText + roundText)
    toolCalls   → 记录 roundToolCalls + thinking 回传字段
    done        → 累计 tokens；chunk.truncated → emit {kind:"output-truncated"}

  ── 收尾判定 ──
  if roundToolCalls.length === 0:
      committedText += roundText
      return { rounds: round, …, outcome: "completed" }    // 出散文即结束

  // 工具轮：回滚展示文本
  if roundText: onOutputText(committedText)

  // 追加 assistant tool_calls 消息（带 thinking 回传字段）
  history.push({ role:"assistant", content:null, tool_calls:[…],
                 _geminiModelParts, _reasoning, _thinkingBlocks })

  ── 逐个执行工具调用 ──
  for tc of roundToolCalls:
      if abortedMidRound || signal.aborted:
          history.push({role:"tool", tool_call_id: tc.id, content: ABORTED_TOOL_RESULT})
          continue                                          // 仍要配平！
      emit tool-step running
      result = await executeRegisteredTool(tc, preset.tools, {…toolContext, signal, onNestedEvent})
      emit tool-step done/error（resultSummary 截取头部）
      history.push({role:"tool", tool_call_id: tc.id, content: result.content})
      if result.imageDataUrls:                              // 图片走后续 user 消息
          history.push({role:"user", content:[{text}, …image_url parts]})
  if abortedMidRound: throw AbortError                      // 配平完成后才抛
```

### 3.1 唯一终止条件：「出散文即完成」

**不变量：无工具调用的轮 = 答案。**这是 tool loop 唯一的正常终止条件。跑满 `maxRounds` 落出循环只是防御性返回（`force-text` 策略下最后一轮已撤除工具，理论上不会发生），且不得丢弃已累计的 token usage。不要发明第二种终止条件（如「模型说 DONE」「输出某个标记」）——它们全都依赖模型服从性，而「这一轮没调工具」是协议层面的客观事实。

### 3.2 abort 配平不变量与 repairToolCallPairing

**不变量：中断也必须配平。**abort 信号到达在一轮多个 tool call 中间时，剩余的调用一律以桩回复（如 `"[not run — the user stopped the task]"`）填入 history，**配平完成后才抛 AbortError**。原因：assistant 的 `tool_calls` 消息已经进了 history，而 history 就是会话历史；k < N 的 tool 回复会让后续每一轮都被 provider 拒绝，会话永久报废、唯一出路是新建对话。

配套要求：

- **每个 tool call 前都要重查 `signal.aborted`**，不只每轮查一次——审批队列 `rejectAll` 解决被阻塞的 Promise 的瞬间就可能伴随 abort 到来。
- **提供并导出 `repairToolCallPairing(history)`**：在「裤带」（abort 补桩）之外再系一条「背带」。它扫描历史，为所有缺失回复的 tool_call 倒序 splice 补桩（先补后面的不影响前面索引）。会话 store 应在**每个后续轮追加新消息之前**调用它——覆盖第二次运行共享数组、两次 push 之间崩溃、从磁盘恢复历史等场景。

### 3.3 thinking 回传字段随消息存放

**规范：thinking 模型的续轮字段必须挂在 assistant 消息本体上**，随历史存续，而非事后重建。典型字段：`_geminiModelParts`（Gemini thought signatures）、`_reasoning` / `_thinkingBlocks`（OpenAI 兼容 / Anthropic 思考回传）。丢了它们的后果不是「答案变差」，而是**下一轮请求直接失败**——所以它们的生命周期必须与消息一致，trimHistory 只换 content 不删消息的策略（见 §3.6）也顺带保住了它们。

### 3.4 serverTools 三态

端点侧工具（provider 在**一次请求内部**自己运行的工具，如内建 web_search）与本地工具是两套独立控制：

```ts
serverTools?: "final-round-off" | "off" | "always";
// final-round-off（默认）：强制成文那一轮撤下，避免收尾轮又跑去搜索
// off：本任务永不放行
// always：每轮都放行（典型：search 子代理——没有本地工具，但每轮都需要端点搜索）
```

陷阱：流中出现 `serverTool` chunk 时**只记日志，绝不能当作 tool_call 去回复**——端点已经自己消化了这次调用，本地再补一条 tool 回复反而破坏配对。

另：`extraBody` 用于透传顶层请求字段（如 JSON mode 的 `response_format`）。**JSON mode 与 tool 调用在多家 provider 互斥**——使用 extraBody 做结构化输出的 preset 应保持 `tools: []`。

### 3.5 临时提示：发出即撤

**不变量：任何一次性的引导消息（强制成文提示、checkpoint 催写提示）都必须在请求发出后从 history 中 splice 撤回（放在 finally 里保证执行）。**

陷阱（实际事故）：「本轮别再调工具了」的 user 提示留在了持久历史里，成为常任禁令——轮次上限那轮之后，助手在后续所有轮都不再读文件/执行操作，且屏幕上毫无解释。凡是「只对这一次请求说的话」，生命周期就只能是这一次请求。

### 3.6 trimHistory：两段式轮内裁剪

```ts
export function trimHistory(history: StreamMessage[], ceilingTokens?: number): number
// 返回被裁的消息数，供 emit context-trimmed
```

1. **图片先裁，且无条件裁。**只保留最新 N 张图（参考值 `MAX_IMAGE_RESULTS = 3`；模型工具读的图和用户附带的图**同等计数**——wire 上都是 base64，只盯一种，另一种就能绕过帽子）。为什么无条件：token 估算对图片按 provider 计费口径记平价，但 payload 是 base64、以 MB 计且跨轮存续——只靠 token 检查，一个读图会话会长出没有任何端点接受的请求体，而估算值还显示宽裕。被裁的消息**保留文字部分**，图片部分替换为占位文本。
2. **超过 ceilingTokens 后，最老的 tool 结果先走。**它们既是体积增长的主体，又最不可能仍然有用。关键规范：**消息壳保留，只替换 content** 为形如 `"[earlier tool result dropped to stay within the model's context window]"` 的占位——删掉消息会制造无配对回复的 tool_call，在 OpenAI 与 Gemini 都是协议错误。逐条替换、每次替换后重估 token，达标即停。**system 与首轮种子文本永不触碰**：如果它们本身超限，那是上游预算规划的 bug，应当由 pre-flight 检查报出来，而不是在这里悄悄掩盖。

分工（对话场景）：trimHistory 是**轮内**的第二道防线；轮与轮之间由 compaction（把整段旧轮折叠成滚动摘要）负责。trim 专门处理压缩管不到的两类增长：一轮之内的增长（折叠单位「完整轮」尚未成形），以及根本没有轮间时刻的一次性任务。

### 3.7 checkpoint 机制（防裁剪失忆）

对 `scratchpad: "required"` 的 preset：历史逼近上限的 85%（`CHECKPOINT_RATIO = 0.85`）时，插入一条一次性提示，催模型用 `write_note` 把已获结论写进磁盘笔记，**赶在** trimHistory 抹掉旧工具结果之前。三条配套规则：提示消息发完即撤（§3.5）；`checkpointArmed` 标志防止连轮重复提醒；真的发生裁剪后解除武装，下次再逼近时重新提醒一次。

### 3.8 round limit：三出口与轮首暂停的干净性

触发条件苛刻而精确：进入 `force-text` 任务的**最后一轮**、且 `round > 1`（单轮 preset 的一轮就是全部）、且有工具、且调用方提供了 `onRoundLimit`。此时模型前面每一轮都在调工具——正在干活中，强行成文等于拦腰砍断。

**规范：询问点必须在强制成文之前（轮首），不能在之后**——工具一撤、文一写，运行已经结束，无从恢复。

```ts
// RoundLimitDecision 定义在 events.ts，runtime re-export——避免 import 环
type RoundLimitDecision =
  | { action: "extend"; rounds: number }   // maxRounds += rounds，继续
  | { action: "finish" }                    // 走原有强制成文
  | { action: "pause" };                    // 立即 return outcome: "paused"
```

- **pause 的干净性靠位置保证**：在轮首询问，上一轮的 tool_call 已全部配平，无需任何修补即是合法历史，可直接持久化、日后 resume。
- **`onRoundLimit` 必须可选**：不是每个界面都能渲染这张卡片（无审批区的 modal、批量运行）。在渲染不了卡片的界面上阻塞 = 挂死在没人看得见的地方。不能渲染的界面保持硬停（不传 onRoundLimit）。
- 「能否暂停」（canPause）应按**本次运行**评估（是否已有磁盘工作区），且在**到达上限那一刻**评估而非运行开始时——三轮前才建立的工作区也算数。

---

## 4. Preset 系统

参考实现：simple-ai-writer `src/lib/agent/presets.ts`。

```ts
export interface TaskPreset {
  id: string;
  tools: readonly ToolId[];        // 空数组 = 纯单发流式，不进 tool loop
  maxRounds: number;               // 模型↔工具轮数上限
  finishPolicy: "force-text" | "allow-tool-end";
  scratchpad?: "off" | "offered" | "required";  // 磁盘工作区：无 / 可用 / 可用 + checkpoint 催写
  serverTools?: "final-round-off" | "off" | "always";
}
```

### 4.1 preset 应当刻意薄

**设计准则：preset 只管「循环怎么跑」，不管「说什么」。**没有 systemPrompt、温度、seedContext 字段——prompt 组装依赖大量应用侧状态（领域配置、i18n、检索注入），留在调用方更干净。新项目可以按需把 prompt 收进 preset，但参考实现的经验是：计划书里原本设计了 `systemPrompt(ctx)` / `seedContext(ctx)` / `output` 字段，落地时全部回到了调用方。

### 4.2 preset 如何驱动 runtime

- `getToolDefinitions(preset.tools)` 解析 wire 定义（保序）；
- `executeRegisteredTool(call, preset.tools, ctx)` 以 `preset.tools` 为**白名单**——模型编造出不在名单里的工具名，得到 `Unknown tool` 文本结果而非崩溃；
- `finishPolicy` + `tools.length` 决定最后一轮是否撤除工具；
- `scratchpad` 决定是否启用 checkpoint 提示；
- `serverTools` 决定端点侧工具何时放行。

### 4.3 各预设一览（参考实现的完整清单，作示例）

| preset | tools | maxRounds | 特点 |
|---|---|---|---|
| `CONTINUE_PRESET`（续写） | 7 个只读（列表/读领域条目、读图、列文件、读文件、搜文本） | 8 | force-text；`presetForTools("read")` 的落点 |
| `LORE_IMPROVE_PRESET` | 3 个领域数据只读 | 4 | 改条目前可自查其它条目；落盘仍走 modal 人审 |
| `FACET_ASSIST_PRESET` | 同上 | 4 | 单特征扩写/重构 |
| `LORE_GENERATE_PRESET` | **[]** | 1 | JSON 结构化提取；JSON mode 与 tool 互斥所以单发，serverTools:"off" |
| `LORE_SPLIT_PRESET` | **[]** | 1 | 同上，逐字拆分 |
| `AGENT_ASSIST_PRESET` | **全家桶 27 个**（读 + L1 领域写 + L2 propose_* + 图片 + scratchpad） | **20** | force-text，scratchpad:"required"；对话助手与面板 Agent 模式共用 |
| `SUB_PRESETS.search` | [] | 2 | serverTools:"always"（唯一每轮放行端点搜索的） |
| `SUB_PRESETS.vision` | read_image、read_lore_image | 3 | 看图子代理 |
| `SUB_PRESETS.longread` | read_file、search_text、list_files | 4 | 长文阅读子代理 |

`maxRounds` 的取值经验（值得抄录的注释）：全量整理领域数据是「一个 list + 每实体一个 read，然后一轮 plan，才开始写」——轮数中途用尽在用户看来等于「agent 拒绝干活」。参考实现曾因此把 12 提到 20，并再补 onRoundLimit 卡片把硬停变成用户选择。**给 agentic preset 定上限时，按最重的真实任务的调用序列算一遍。**

### 4.4 presetForTools：应用配置到 preset 的解耦映射

```ts
presetForTools(tools: "none" | "read" | "full"): TaskPreset | null
```

应用配置层（如按项目类型声明的工具档位）不直接依赖 agent 层类型，只声明档位字符串；由这个映射函数落到 preset 对象。**`"none"` 必须返回 null 而非空工具 preset**——null 是调用方「走简单流式路径、根本别进循环」的信号，两者语义不同。

### 4.5 routeTools：每轮动态改写（概述）

会话场景每轮以 `routeTools(basePreset, subAgents, workspace, models)` 生成**有效 preset 副本**：vision 子代理可用则从主模型剥掉读图工具；任一子代理可用且有工作区则追加 `delegate`；search 子代理可用则主模型自己的 serverTools 置 "off"。判定必须用「enabled + 绑定 + **能力核验**」（vision 必须 multimodal、search 必须带 web_search）——「已启用」≠「可用」；只看开关，绑错模型的 search 子代理会把主模型自己的搜索拿走，却什么都还不回来。详细路由规则与子代理体系见第 09 篇。

---

## 5. 事件系统

参考实现：simple-ai-writer `src/lib/agent/events.ts` / `logModel.ts`。

### 5.1 AgentEvent 全集

```ts
type AgentEvent = AgentEventScope & (
  | { kind:"run-start"; task; modelName; agentic; at }      // 调用方发（只有它知道任务种类/展示名）
  | { kind:"round-start"; round; maxRounds; estInputTokens; at }
  | { kind:"tool-step"; step: ToolStep; at }                // 每次调用发两次：running → done/error
  | { kind:"context-seeded"; documentName; recentChars; memoryChars; loreEntities; loreChars; at }
  | { kind:"context-trimmed"; count; at }                   // trimHistory 抹了几条
  | { kind:"context-compacted"; foldedTurns; fromTokens; toTokens; summary; at }
  | { kind:"round-limit"; roundsUsed; decision; at }
  | { kind:"reasoning"; round; text; done; elapsedMs?; at } // 同轮反复重发（流式增长）
  | { kind:"turn-resumed"; round; leg; final; at }          // 端点分腿续传（一轮=多请求）可见化
  | { kind:"output-truncated"; round; stopReason?; at }     // max_tokens 截断——最易误读的静默故障
  | { kind:"run-done"; inputTokens; outputTokens; at }      // 调用方发
  | { kind:"run-error"; message; at })                      // 调用方发
```

**所有权划分（规范）**：runtime 只发它才看得见的事件（round / tool-step / trim / reasoning / truncated / round-limit / turn-resumed）；启动运行的**调用方**负责包上 bracket 事件 run-start / run-done / run-error——任务种类、模型展示名、最终成本只有它知道。**非 agentic 的单发任务也要发 bracket 事件**——所有任务都进执行日志，不只 tool-using 的。

reasoning 事件的计时细节（三个都是踩过的坑）：

- 起点取**第一个 reasoning fragment 到达**而非轮开始——读完工具结果才思考的模型不应被记上等待时间；
- `done` 在答案文本开始流出时翻转——否则散文都在流了，日志还显示「思考中」；
- finally 里兜底翻转——工具轮没有散文、或半途失败，都不能让日志里永远留一行转圈。

### 5.2 scope 机制：parentStep

```ts
type AgentEventScope = { parentStep?: string };
```

子代理（delegate）子运行的每个事件经 `ctx.onNestedEvent!({...e, parentStep: call.id})` 转发进父日志，`parentStep` = 那次 delegate 调用的 toolCallId。子代理结束时额外发一条**带 parentStep 的 `run-done`**——子代理花的是自己模型的钱，usage 统计按 parentStep 分桶（主运行 input/output vs 子代理 subInput/subOutput），不能混记。

### 5.3 append 语义：原位替换

```ts
appendAgentEventTo(log: AgentEvent[], event: AgentEvent): AgentEvent[]
```

不可变追加，但两类事件**原位替换**而非追加新行：

- `tool-step` 按 `(parentStep, toolCallId, name)` 匹配——running → done/error 是同一行的状态更新；
- `reasoning` 按 `(parentStep, round)` 匹配——流式增长会重发无数次，日志只应显示一行。

server-tool 日志行需要有状态工厂（query 随 call chunk 来、结果随 result chunk 来，中间用 Map 记住 query）——否则完成行只见结果不见问题。

### 5.4 logModel：展示层折叠

事件流是扁平时序（一次运行几十行对等事件），阅读需要的是三问分答：`summary + current`（一行现状）、`rounds: RoundGroup[]`（按 round-start 切段）、`subagents: SubAgentRun[]`（delegate 卡片 + 各自嵌套日志）。**规范：折叠逻辑做成纯函数（`buildLogModel(events, isRunning)`），同步、可脱离渲染器测试。**

防坑细节（每条都对应真实故障）：

- **`isRunning` 由调用方传入**（store 的活性标志），不能从「还没见到 run-done」推断——被关窗杀掉的运行没有终止事件，误读会让死轮永远转圈。
- **delegate 参数用正则容错提取**而非 `JSON.parse`——日志层参数被 400 字符截断后 JSON 不完整。
- 磁盘工作区文档（task.md）的重读信号数「已 settle」的 task_plan / task_progress 调用——计划本体在磁盘不在流里（参数会被截断，一份六步中文计划活不过 400 字符的截断线）。

---

## 6. 结构化输出在 agent 层的位置（简述）

`runStructuredTask`（参考实现：simple-ai-writer `src/lib/agent/structured.ts`）是与 tool loop 并列的**单发**路径：主路径用强制 `tool_choice` 的伪工具拿结构（参数 schema 即输出 schema），失败时按**收紧过的能力错误判据**回退到「原生 JSON mode + prose 指令 + extractJsonObject」。三条与 runtime 相关的边界规范：

- **单发是设计而非局限**：JSON mode / 强制 tool_choice 与自由工具循环在多家 provider 互斥。需要「调查 → 结构化产出」时，先跑 agent loop 收集材料，再把发现喂给 structured 调用（两段式）。
- `serverTools` 显式置 undefined——结构化任务不上网；它作为模型级配置藏在 ConnOptions 里会搭车进来，不删掉的话强制 tool_choice 的请求会中途跑去 web 搜索。
- 返回**未 parse 的 JSON 字符串**，schema 校验归调用方。

回退判据、双路径完整细节见第 04 篇。

---

## 7. 本篇检查清单

- [ ] runtime 内没有任何 `switch(toolName)`；工具执行全部经注册表分发，任务差异全部由 preset 数据表达。
- [ ] `onOutputText` 是快照语义；工具轮结束时以 `committedText` 回滚，模型的过程性叙述不可能进入最终输出。
- [ ] 唯一正常终止条件是「本轮无工具调用」；跑满上限的返回不丢 usage。
- [ ] abort 到达在工具序列中间时，剩余 tool_call 全部补桩回复后才抛 AbortError；每个 tool call 前重查 `signal.aborted`。
- [ ] 导出 `repairToolCallPairing`，且会话层在每次追加新轮之前调用它。
- [ ] thinking 回传字段（`_reasoning` / `_thinkingBlocks` / thought signatures 等）随 assistant 消息存放，trim 时不丢失。
- [ ] 一次性引导消息（强制成文提示、checkpoint 提示）在请求发出后 finally 中 splice 撤回。
- [ ] trimHistory：图片无条件保最新 N 张；超限只替换旧 tool 结果的 content，消息壳保留；system 与种子永不触碰。
- [ ] round limit 询问发生在轮首（强制成文之前）；`onRoundLimit` 可选，渲染不了卡片的界面不传、保持硬停。
- [ ] 事件所有权正确：runtime 发轮内事件，调用方发 run-start / run-done / run-error；tool-step 与 reasoning 在日志中原位替换；子代理事件带 parentStep 且 usage 分桶。
