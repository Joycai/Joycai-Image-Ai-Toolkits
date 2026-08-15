# 12 · 分阶段落地路线图（按依赖顺序的最小实现清单）

把整套体系搬进新项目的推荐顺序。模块名沿用参考实现（simple-ai-writer）的命名，接口
签名可直接照抄。标 ★ 的是「没有它其他都白搭」的正确性核心。每个阶段可独立交付、
独立回退。

## 阶段 0 · 协议层类型与词汇（无依赖）

- [ ] `types.ts`：`ApiStandard`（族 × official/compat）、`familyOf()` ★、`AuthMode` +
      `authModesFor()`、`ContentPart`/`MessageContent`、`ToolDefinition`/
      `AssistantToolCall`/`AccumulatedToolCall`、`StreamMessage`（OpenAI 形状 + `_` 前缀
      载体字段）★、`StreamChunk`（key 判别变体联合）★、`StreamOptions`、
      `ContextSizeError`、`applyPrefix()`。
- [ ] `reasoning.ts`：六档强度自有词汇 ★、`ThinkingDialect`、三族翻译表 +
      `reasoningBody()`/`thinkingBody()`、`NativeReasoning`（原名奉还载体）★、
      `REASONING_CONTENT_FIELDS` 候选表、`createThinkTagSplitter()` ★。
- [ ] `urls.ts`：三族默认 base 常量、不对称归一化（`trimBase`/`anthropicRoot`）★、
      各族 URL 拼接、读取时幂等迁移。

## 阶段 1 · 协议适配器（依赖阶段 0 + 一个 fetch 包装）

- [ ] `openai.ts`：SSE 行缓冲 ★、`_` 前缀剥除 + `_reasoning` 原名回写 ★、index 键
      tool_calls 累积 ★、`json.error` + `base_resp` 双错误通道 ★、content_filter/length
      处理、think-tag 切分接入、`stream_options.include_usage`。
- [ ] `gemini.ts`：消息转换（id→name 表、`_geminiModelParts` 原样回传 ★）、
      systemInstruction hoist、「chunk 是完整对象不是 delta」★、thought part 分流、
      三层错误（promptFeedback / blocked finishReason / request-fault 集合）★、
      `candidatesTokenCount + thoughtsTokenCount` ★、自造 functionCall id。
- [ ] `anthropic.ts`（最重）：交替律修补 + tool 消息合并 + labelAuthorText ★、三模式
      鉴权 + pinned 版本头、`max_tokens` 兜底 ★、thinking 方言与 toolChoice 降级、
      类型化事件解析（块整存）★、usage 三桶求和 ★、refusal/pause_turn；续跑循环
      （verbatim + transcript）可后补，先把 pause_turn 当已知未完成态报警。
- [ ] `serverTools.ts`（可选）：版本化 wire type 表、`max_uses` 刹车、两阶段事件、
      防御读取、纯文本渲染兜底。

**只接 OpenAI 系兼容层时，第一天就要有的三样**：SSE 行缓冲、双错误通道、`<think>`
切分——它们对应的失败全是静默的。

## 阶段 2 · 统一入口与横切（依赖阶段 1）

- [ ] `index.ts`：`streamCompletion` = familyOf 分发 ★ + prefix 合并 + ContextSizeError
      预检 + 日志接线。
- [ ] `jsonMode.ts`：`jsonModeShaping()` ★（Anthropic 无参数只有 cue）、`mentionsJson`
      前置条件、`extractJsonObject`。
- [ ] `structured.ts`：强制 pseudo-tool → 收紧正则判定 → JSON mode 回退（仍带原生参数）★。
- [ ] `apiLog.ts`：JSONL 日志（request / request-body 带 leg / response / error），key
      永不落盘、图片裁剪、写串行化。**强烈建议第一批做**——后续所有兼容层坑都靠它定位。
- [ ] `conn.ts`：`ConnOptions`/`connOptions()`/`pickConnOptions()`/`resolveConn()` ★
      （调用点 ≥3 个时就该收口，别等 16 个）。

## 阶段 3 · 配置与探测（产品层，可后补）

- [ ] Provider/Model 两张表（L2/L3）+ authMode 列（default 存 NULL）+ 读取时幂等迁移。
- [ ] `providerProbe.ts`：/models 优先 + compat 降级 completion probe（不可能模型名 +
      错误形状判定）★。
- [ ] `usage.ts`：persistUsage（best-effort 永不抛）+ rollup 读侧（total 从明细派生）。
- [ ] `modelHealth.ts`：safety-block 粘性标记。
- [ ] `endpointProbe.ts` + `probeAnalysis.ts`：四步递进探测；判断逻辑与 HTTP 管线分文件
      （前者无网络可单测）；探测前告知预估成本。

## 阶段 4 · Agent runtime（依赖阶段 0–2）

- [ ] `events.ts`：AgentEvent 联合 + `appendAgentEventTo`（tool-step/reasoning 原位替换）
      + `AgentEventScope.parentStep`；`RoundLimitDecision` 放这里（避免 import 环）。
- [ ] `registry.ts`：`ToolAccess`、`ToolId` 字面量联合、`RegisteredTool`、`ToolContext`
      （审批/门控/工作区全部**可选通道**）、`Proposal` 判别联合、`getToolDefinitions`
      （拷贝式动态注入）、`executeRegisteredTool`（白名单类型收窄 + 错误转文本）★。
      先实现 3–4 个只读工具即可跑通全链路；每个工具：路径包含校验、输出限幅+分页、
      错误写成下一步指引。
- [ ] `presets.ts`：`TaskPreset { id, tools, maxRounds, finishPolicy, scratchpad?,
      serverTools? }` + `presetForTools`（"none" → null 走单发路径）。
- [ ] `runtime.ts`：`runAgent` 循环 + `trimHistory` + `repairToolCallPairing`。必守
      五不变量：① 每个 tool_call 必有回复（abort 补桩后才抛）★ ② 无工具调用即完成
      ③ force-text 最后一轮撤工具 + 临时提示请求后撤回 ④ onOutputText 快照 + 工具轮
      回滚 ⑤ thinking 回传字段随 assistant 消息保存 ★。

## 阶段 5 · 写入安全（依赖阶段 4）

- [ ] `backup.ts`：写前快照进单一扁平备份目录；**throw = 写入不发生** ★；二进制/整目录
      删除用 rename-into-backups。
- [ ] L1 工具模板：参数校验 → 结构校验 → （门控）→ backup → write → 修快照 →
      onChanged 回调 → 带备份路径的成功回执。
- [ ] L2 工具模板：可行性预检 → 构造 Proposal → `await ctx.requestApproval` → 决定转
      结果文本（拒绝理由原样回 + 「勿原样重试」）。
- [ ] `plan.ts`（若有「批量自动写」域）：PlanGate + checkPlan（实体经索引解析比对；
      file-scoped 步骤不放行无 file 调用 ★）+ 追加式批准 + 按轮存活。
- [ ] 审批 store：三队列 + `new Promise(resolve => 入队)` + runId(=AbortController)
      作用域 + **finally 必 rejectAll** ★；approve = 备份 → apply（find 重定位 ★，
      活动文档走编辑器 buffer）→ 失败 resolve 成拒绝；turnId/signal 请求时绑定。
- [ ] 会话双层：chatHistory（wire，交给 runtime 原地长）+ turns（展示）；meta 按消息
      对象身份记录；每轮 finally best-effort 持久化（序列化剥图片）。

## 阶段 6 · 任务工作区（可独立交付，解掉大半长任务问题）

- [ ] `TaskWorkspaceHandle { taskId: string|null; ensure(title) }` 懒创建句柄；生命周期
      归属由 surface 决定（单次任务 per-run，会话 per-session）。
- [ ] `task.md`：JSON 注释头只放机器状态；步骤只在正文复选框（1 基序号）★；小节用
      语言无关锚点注释。
- [ ] 5 个工具：task_plan / task_progress / write_note / read_note（行分页）/ list_notes
      （只给索引）。不变式：只有 plan 与 note 能建仓、Unicode slug 清洗、绝不覆盖、
      超限报错不截断、写入串行化（链放 workspace 层）、不备份不过审批门。
- [ ] checkpoint 注入：85% 阈值早于裁剪阈值、**发出即撤** ★、裁剪真发生后重新武装。
- [ ] 排序 GC（已收尾先淘汰、未完成不豁免、保当前）。

## 阶段 7 · 存盘暂停与恢复（依赖阶段 6）

- [ ] `onRoundLimit` 返回判别联合 `{extend|finish|pause}`；pause 在**轮首**退出
      （history 天然配对完整）★；`AgentRunResult.outcome`。
- [ ] `canPause` 由发起方在撞上限那一刻求值；每个调用方都处理 paused（置状态 +
      记 sourceRefs 哈希）。
- [ ] `buildResumeSeed`：task.md + notes 索引（只标题路径）+ sourceRefs 过期清单 ⇒
      一条全新 user turn，**不重放旧 history** ★。
- [ ] 持久化过事件/会话的：写旧格式迁移函数（认不出的丢弃）。

## 阶段 8 · 子代理（依赖阶段 6）

- [ ] `delegate(kind, task, refs?)` 一个工具；kind 内置枚举（preset 是代码，配置只有
      「哪个模型、开不开」）。
- [ ] 每 kind 一个 SUB_PRESET（小轮数、force-text、最小工具集）；执行器 = 嵌套
      runAgent：全新 2 条消息、独立连接、子 ctx 不传审批/门控/工作区（沙箱）★、
      共享 signal、AbortError 重抛 ★。
- [ ] 产出经 `onOutputText` 捕获 ★ → 落盘 note → tool result = 路径 + ≤800 字符摘要 +
      「细节用 read_note」★；空产出报错不建 note。
- [ ] 前置校验全在 delegate 里（ctx 齐全、能力条件），失败零副作用；密钥缺失是配置
      错误不是空串。
- [ ] 记账：每子跑一行独立 usage（task 打 `subagent:<kind>` 标签）+ 带 parentStep 的
      嵌套 run-done 事件；事件去重键带 parentStep ★。
- [ ] `routeTools`：可用性判断走单一函数（开关+绑定+存在+能力前置）★；vision 接管 ⇒
      删主模型图片工具；search 接管 ⇒ 关主模型服务端搜索；有可用子代理且有工作区 ⇒
      加 delegate。**改工具集，不写提示词偏好。**
- [ ] 配置面：每 kind 开关+模型下拉+就地警告（警告不阻止，下游再验）；三处悬空绑定
      清理；会话 chips 只减不增。

## 阶段 9 · 长会话压缩（与 6–8 正交，可先可后）

- [ ] 轮边界按**消息对象身份**记录 ★；折叠单位是**整轮**（不拆 tool-call 配对）★。
- [ ] planFold：0.7 触发 / 0.45 目标（宽间隙保 prompt cache）/ 最近 2 轮永不折 /
      best effort。
- [ ] 摘要失败返回 null 一字不动 ★；summary 消息紧贴 system。
- [ ] 注入台账：`Map<key, {version 指纹, carrier 消息对象}>`——未变不重注、变了重注、
      carrier 折掉即逐出；模型自读的不入账。
- [ ] @引用内联三预算（单条上限 / 总预算顺序分配 / 图片条数），超预算退化成
      「名字+路径+读取指令」，绝不静默截断。
- [ ] 持久化：身份→索引序列化、图片剥离、偏执反序列化（坏了返回 null 开新会话）、
      事件格式迁移。

## 始终不做（边界即设计）

子代理间通信、并行编排、递归委托、子代理写用户内容、把「要花钱须审批」的动作（如
生图）塞进静默委托、用工作区替代压缩或用压缩替代工作区、`DeepSeekProvider extends
OpenAIProvider` 式的供应商子类。

## 迁移时最容易忽略、代价最大的七件事

1. tool_call 配对不变量（含 abort 路径的补桩）。
2. 每次运行 finally 里的 `rejectAll(runId)`。
3. 备份失败 = 写入失败。
4. 审批 apply 时的 find 重定位与失败转拒绝。
5. 模型可控路径参数的包含校验（含空前缀陷阱）。
6. thinking/签名类载体的原物整存与按 modelId 剥离。
7. 一次性提示的「发出即撤」。
