# 12 · Agent 体系分阶段落地路线图（阶段 4–9）

阶段 0–3（协议层类型、协议适配器、统一入口、配置与探测）在 ai-agent-architecture skill 的
`references/12-migration-roadmap.md`；本篇从阶段 4 接着往下，依赖那边的阶段 0–2。
模块名沿用参考实现（simple-ai-writer，TypeScript）的命名，仅作定位用。

## 阶段 4 · Agent runtime（依赖阶段 0–2）

- [ ] `events.ts`：AgentEvent 联合 + `appendAgentEventTo`（tool-step/reasoning 原位替换）
      + `AgentEventScope.parentStep`；`RoundLimitDecision` 放这里（避免 import 环）。
- [ ] `registry.ts`：`ToolAccess`、`ToolId` 字面量联合、`RegisteredTool`、`ToolContext`
      （审批/门控/工作区全部**可选通道**）、`Proposal` 判别联合、`getToolDefinitions`
      （拷贝式动态注入）、`executeRegisteredTool`（白名单类型收窄 + 错误转文本）★。
      工具多到固定头部吃紧时：`ToolGroup` + 运行状态装载，白名单用 active 集 ★（07 篇 §4.6）。
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
      删主模型图片工具；search 接管 ⇒ 主模型只让出 web 类服务端工具（`"no-web"`，代码解释器保留）；有可用子代理且有工作区 ⇒
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

迁移时最容易忽略、代价最大的点，见本 skill 的 SKILL.md。
