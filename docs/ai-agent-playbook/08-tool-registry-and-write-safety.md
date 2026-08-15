# 08 · 工具注册、权限分级与写入安全

> 本篇解决的问题：agent 拿到写盘能力的那一刻，「模型幻觉」就从答错话升级成数据事故。本篇规定工具体系的三根支柱：**注册表**（工具的定义、权限声明与执行器同址存放，白名单分发）、**三级权限**（只读 / 领域数据 L1 自动写 / 用户核心内容 L2 审批写）、**审批通道**（Promise 挂起 + 队列 + runId 作用域）。tool loop 本体见第 07 篇。
>
> 参考实现：simple-ai-writer `src/lib/agent/registry.ts` / `tools.ts` / `writeTools.ts` / `backup.ts` / `plan.ts`，及 `src/stores/agentStore.ts`。

---

## 1. 工具注册表

### 1.1 结构

```ts
export type ToolAccess = "read" | "write-auto" | "write-approval";

export interface RegisteredTool {
  definition: ToolDefinition;      // OpenAI function schema：{type:"function", function:{name, description, parameters}}
  access: ToolAccess;
  execute: (call: ToolCall, ctx: ToolContext) => Promise<ToolResult>;
  profileCategoryParams?: readonly string[];  // 需要在下发时按当前应用配置填 enum 的参数名
}

// ToolCall  = { id, name, arguments: string /* 原始 JSON */ }
// ToolResult = { toolCallId, content: string, imageDataUrls?: string[] }

const REGISTRY: Record<ToolId, RegisteredTool> = { … };
```

**规范：`ToolId` 必须是字面量联合类型**（参考实现是 28 个字面量的联合）。`Record<ToolId, RegisteredTool>` 使「加了工具名却漏了注册」成为**编译错误**，而不是运行时的 `Unknown tool`。

### 1.2 ToolContext：执行器可用的全部钩子

```ts
export interface ToolContext {
  projectPath: string;
  loreIndex: LoreIndex;            // 领域数据索引——运行开始时的快照（陷阱见 §3.4）
  multimodal: boolean;             // 当前模型能否收图（控制图片类载荷）
  onLoreChanged?: () => void;      // L1 写完通知应用重扫（更新 UI，不更新本 ctx 的快照）
  onMemoryChanged?: () => void;
  requestApproval?: (proposal: Proposal) => Promise<ApprovalDecision>;   // L2 阻塞通道；缺席 → 工具报错
  requestPlanApproval?: (plan: LorePlan) => Promise<PlanDecision>;       // 方案门控通道
  lorePlan?: PlanGate;             // 本次运行的已批方案记录
  taskWorkspace?: TaskWorkspaceHandle;   // 磁盘工作区句柄（惰性 ensure）
  signal?: AbortSignal;            // 嵌套运行（delegate）必须共享同一 signal
  onNestedEvent?: (event: AgentEvent) => void;   // 子代理事件转发（带 parentStep）
  resolveSubAgent?: (kind) => Promise<AiConn | { error: string }>;  // 由调用方注入，避免 lib→store 反向依赖
}
```

**设计准则：能力以「通道在不在」表达。**没有 `requestApproval` 的界面（批量运行、无审批区的 modal），L2 工具直接返回形如 `"Error: this surface cannot review manuscript changes — do not call propose_edit here."` 的文本——同一份注册表在不同界面**自动降级**，无需按界面维护 preset 变体。方案门控同理：`requestPlanApproval` 或 `lorePlan` 缺任何一个，领域写工具**拒绝而非无门放行**。`resolveSubAgent` 由 store 注入而非在 lib 里 import store——打破循环依赖的标准手法。

### 1.3 分发与错误处理

```ts
export async function executeRegisteredTool(call, allowed, ctx): Promise<ToolResult> {
  const isAllowed = (name): name is ToolId => (allowed as readonly string[]).includes(name);
  const tool = isAllowed(call.name) ? REGISTRY[call.name] : undefined;
  if (!tool) return { toolCallId: call.id, content: `Unknown tool: ${call.name}` };
  try { return await tool.execute(call, ctx); }
  catch (e) { return { toolCallId: call.id, content: `Error: ${String(e)}` }; }
}
```

三条规范：

1. **白名单是类型收窄（type guard），不是断言。**模型给出的 name 是任意字符串；写成双重 cast 会把 `undefined` 当 `RegisteredTool` 使用。
2. **永不 throw。**任何执行错误捕获后转成 `Error: ...` 文本结果回给模型；runtime 以 `content.startsWith("Error") || startsWith("Unknown tool")` 判定日志行状态。坏调用是模型可纠正的信息，不是运行的死刑。
3. **错误文案必须写成下一步动作指引。**如「Re-read the file and copy the target text exactly」「Call list_lore_entities first」。光拒绝不指路，模型会原样重试同一个坏调用（参考实现 plan.ts 的注释明确记载了这一点）。

结果截断的分层：**日志层**截断（argumentSummary 保持合法 JSON 头以便提取标识参数；resultSummary 截头部若干字符）；**给模型的 content** 由各工具自己限幅（如 read_file 每次 4000 字符、search 40 行封顶）。两层各管各的，不要用日志截断值去喂模型。

### 1.4 应用配置参数的下发时拷贝注入

陷阱：REGISTRY 是模块级常量，import 时求值一次；而某些参数的合法值（如领域数据的分类枚举）由**当前应用配置**决定。把它们烤进定义，就冻结在最先加载的配置上——上一个项目的分类会留给下一个项目。

规范：schema 里 enum 留空（`enum: []`），描述里放 `{{categories}}` 占位符；`getToolDefinitions` 每次下发时**拷贝**定义（绝不 mutate 共享常量）并按当前配置补齐 enum 与描述。**描述文字里的枚举和 enum 字段一样重要**——描述写着 "characters, world…" 会引导模型请求实际不存在的分类。

---

## 2. 工具清单（分组规范样例）

以下为参考实现的完整清单，作为「一套成熟工具集长什么样」的样板。关键实现点列是规范的一部分——每条都对应一次事故或一个安全边界。

### 2.1 只读（read）

| 工具 | 关键实现点 |
|---|---|
| `list_lore_entities` | 直接 format ctx 快照：`[category]` + `- name: summary` |
| `read_lore_entity` | 条目全文 + 全部子文件；**图库只给文件名 + 文字描述，绝不附图**（历史事故：一次 5 图 ~35MB 请求超时）；multimodal 与否只改提示语 |
| `read_lore_image` | 按需取**一张**图为 dataUrl（走 imageDataUrls 通道）；text-only 模型直接报错；超单图字节上限拒绝 |
| `read_image` | 项目内任意图片；包含校验对**项目根**（图片泄密面小，收窄反而破坏正常用例）；**`projectPath === ""` 直接拒绝——空前缀包含一切绝对路径**；尝试原样与 percent-decode 两种拼写 |
| `list_files` | 递归列用户内容目录，`ls -R` 式分组输出（几百个文件不重复长前缀，省数千 token）；上限 300 条并提示分页；folder 参数过 `isPathWithin` 防 `../` |
| `read_file` | 4000 字符/次、**按行边界切**、回报 `lines a-b of N` 与下一个 start_line；行号坐标与 search_text 输出直接衔接；限定用户内容目录（被 prompt 注入的模型不能借它读配置或领域数据源文件） |
| `search_text` | 字面匹配、大小写不敏感、**明确不支持正则**（模型给的病态正则会卡死 UI 线程且无法中断）；全局 40 命中 / 单文件 8 命中封顶；长行按命中位置开窗 |
| `read_memory` | 滚动记忆分段索引（segment i: chars from–to + summary），update_memory 的前置 |
| `read_note` / `list_notes` | 工作区笔记读取/列表，行分页同 read_file 风格 |

**只读工具三铁律：模型可控的路径参数一律做包含校验（`isPathWithin` 式前缀测试，注意空前缀陷阱）；输出限幅 + 分页；错误写成指引。**

### 2.2 L1 自动写（write-auto）

`create_lore_entity`、`update_lore_file`、`update_facet_meta`、`delete_lore_file`、`move_lore_entity`、`delete_lore_entity`、`update_memory`、`task_plan`、`task_progress`、`write_note`。

即：**领域数据**（结构化的辅助知识，如设定条目）、**滚动记忆**、**scratchpad 三件套**（task_plan / task_progress / write_note——agent 私有草稿，无备份无门控）。详见 §3。

### 2.3 L2 审批写（write-approval）

`propose_lore_plan`、`propose_edit`、`create_chapter`、`move_chapter`、`delete_chapter`、`generate_image`、`edit_image`。

即：**用户核心内容**（正文文档）的内容与结构操作、**花钱的操作**（图片生成）。详见 §3.5–§3.6。

**特殊：**`delegate`（access: "read"）——分派子代理，本身不写任何东西，见第 09 篇。

---

## 3. 写入安全体系

### 3.1 三级权限的实际语义

| 级别 | 适用对象 | 机制 |
|---|---|---|
| **L0 read** | 只读工具 | 路径包含校验 + 输出限幅，无写入 |
| **L1 write-auto** | 领域数据 / 记忆 / scratchpad | 立即落盘；**写前自动备份**；落盘前结构校验；领域数据类**另加方案门控**；写后回调（onLoreChanged 等）刷新 UI |
| **L2 write-approval** | 用户核心内容的结构与内容、图片生成 | 只产生 Proposal，Promise 阻塞在用户卡片上；批准后由**审批方**应用（先备份）；拒绝理由原文回模型 |

**为什么用户核心内容是 L2 而领域数据是 L1**（划线原则，按你的领域重演这个判断）：用户对核心内容（正文）的所有权感远强于辅助数据（设定），删一章的破坏性远大于改一个设定文件。且 L2 结构操作**不设方案门**——每操作一张卡，大改结构就是好几张卡，换来的是每步可见、可单独拒绝；「用户真觉得烦了再加门，比加了门再拆容易」。

### 3.2 备份：「备份失败 = 写入失败」

参考实现：simple-ai-writer `src/lib/agent/backup.ts`。

```ts
export async function backupFile(projectPath: string, absPath: string): Promise<string | null>
```

- 源不存在返回 null（新建文件无需备份）；**读/写失败直接 throw——调用方必须把失败的备份当失败的写入，绝不能照写。**所有 L1 工具都是「先 backup 再 write」的顺序，throw 会被注册表兜住变成模型可见错误，写入根本不会发生。
- 备份目录：单一**扁平**目录（如 `.ai-writer/backups/`），一个地方装所有可恢复物。命名：`agent-<epoch毫秒>-<相对路径打平（/ → -）>`——打平让目录一眼可读，不复刻源目录树。
- 文本用 read + write 复制。**二进制救不了**——所以删除整个含二进制资产的实体时不用 backupFile，而是**整个目录 `rename` 进备份区**（如 `backups/deleted-<ts>-<category>-<id>`）：二进制一并保住，一次 rename 也不存在半删除状态。删除用户核心文档同理：批准后移入备份区而非 unlink。
- 删除类工具的细节：备份返回 null（源不存在）时**报错而不是静默成功**——备份就是删除操作的恢复路径；让模型报告一个用户永远无法检查的删除是不可接受的。

### 3.3 L1 落盘前的结构校验

原则：**坏载荷在落盘前拦下，转成模型可读的错误**；静默接受再让下游扫描器还原/丢弃，等于数据丢失。参考实现的契约清单（`writeTools.ts` 头注释）：

- 写条目主文件：必须有可解析 frontmatter 且含 `name`；**禁改 category**——目录位置才是扫描器信任的真相，只改 frontmatter 下次重扫会被还原，换分类只能走 move 工具。
- 现为结构化子文件（facet）的文件必须写完仍是合法结构（parse 通过），否则拒绝。
- 应用托管的特殊文件（如图库清单）拒写；文件名参数一律 `/^[^/\\]+\.md$/ && !includes("..")`——模型可控参数不允许任何路径导航。
- 元数据工具只重写 frontmatter，body 经 parse **原样带过**——「说好只改关键词，顺手把正文改写了」的漂移风险从机制上消除；未传字段保持原值；配置成「永远不会生效」的组合要在成功结果里明确警告。
- 该类工具**从磁盘读当前状态而非运行快照**——同一次运行里刚创建的文件不在快照里（快照陷阱见 §3.4）。
- 滚动记忆只能走既有的分段重写协议（段范围/哈希不可破坏，只换摘要文本）。

### 3.4 运行快照 vs 磁盘现实（陷阱）

`ctx.loreIndex` 是运行开始时的快照。三个后果与对策：

- move/delete 成功后，同一运行的下一个调用会解析到已不存在的路径 → 工具成功后**手工修正快照**（`relocateInSnapshot` 式；`onLoreChanged` 触发的应用侧重扫到不了这个 ctx 对象）。
- 本轮刚创建的子文件不在快照里 → 细粒度工具改为**从磁盘读当前状态**，写完再回填/剔除快照条目。
- 对话场景每轮重建 toolContext 时，快照取应用 store 的**最新**索引——轮 N 写的数据轮 N+1 必须可见。

### 3.5 方案门控：审批提前到「方案」层

参考实现：simple-ai-writer `src/lib/agent/plan.ts` + `propose_lore_plan` 工具。

问题：领域数据写如果升到 L2，批量整理十个条目就要弹十次卡。解法：**一张卡审一份方案，之后的 L1 写入必须逐条对得上方案。**

```ts
interface LorePlanStep { action: "create" | "update" | "move" | "delete"; entity: string; file?: string; detail: string; }
interface PlanGate { steps: LorePlanStep[]; fulfilled: Set<number>; asked: boolean; }
```

机制全貌：

- **`propose_lore_plan`（write-approval）**：校验每步（action 合法、entity/detail 非空——**detail 是用户据以决策的文本，必须具体**），`await ctx.requestPlanApproval(plan)` 阻塞。拒绝 → 拒绝理由 + 「不许在此期间写任何领域数据」回模型。批准 → 步骤**追加**进 `ctx.lorePlan.steps`——**不是替换**：运行中批的第二份方案不能悄悄撤销用户已签的第一份；返回文本里附「先前尚未兑现的步骤」清单以免被遗忘。
- **每个 L1 领域写工具落盘前过 `checkPlan(gate, index, action, entity, file)`**：
  - gate 不存在 → 「此界面无法审方案，报告你想改什么即可」；
  - steps 为空 → 「先 propose_lore_plan」；若 `asked === true` 追加「上一份未获批，修改后重提」；
  - 找覆盖步骤：action 相同 + `sameEntity`——**实体名经索引解析后比对**（方案写 "Ava"、写入用别名 "阿瓦" 不能误拒；create 尚无落盘实体，退回小写字符串比对）+ **file 规则：步骤声明了 file 就钉死那个 file；未声明则该实体下任意文件放行；file-scoped 步骤绝不放行无 file 的调用。**
  - 命中 → `fulfilled.add(idx)`，返回步骤；未命中 → 错误文本附**已批步骤全清单** + 「要改就重提方案」。
- **门控按运行/按轮存活**：会话场景每轮 `lorePlan: createPlanGate()` 新建——这一轮批的方案不悄悄授权下一轮。
- 门控能核验「哪个实体、哪个文件、什么动作」，核验不了措辞——所以命中步骤的 `detail` 回写进工具成功结果（`Plan step: ${step.detail}`），用户在执行日志里能把「说要改什么」与「实际改了什么」并排看。
- **门控时机在结构校验之后**（"Gated last"）：写入真的会发生，步骤才算兑现——被校验拦下的调用不该消耗方案额度。

陷阱（真实越权洞）：文件匹配曾写成 `!s.file || !file || 同名`——步骤「delete Ava / armor.md」（删一个子文件）能授权删掉整个 Ava 实体（调用不带 file 时误命中）。修正即上面的黑体规则：**步骤声明了 file，调用就必须给出同一个 file**；删单个子文件与删整个条目从此是两条互不越权的步骤，审批卡上分别显示。

### 3.6 L2 propose_edit 全链路（同步阻塞审批的标准样板)

**工具侧**（参考实现：`writeTools.ts` 的 proposeEditTool）：

1. 校验 path 在用户内容目录内、find/replace 是字符串、`ctx.requestApproval` 存在。
2. **提案前预检**：读文件数 `find` 出现次数——0 次 → 「重读文件并精确复制目标文本」；>1 次 → 「加长上下文使其唯一」。保证卡片上的提案**至少在此刻可应用**。
3. `const decision = await ctx.requestApproval({ kind:"edit", id:`edit-${++counter}`, path, find, replace, reason })` ——**tool loop 在此挂起**。
4. 拒绝 → `The user REJECTED this edit — reason: …. Do not retry the same change; adjust per the reason or move on.`；批准 → `Edit approved and applied. Previous version backed up to <path>.`

**审批侧**（参考实现：`src/stores/agentStore.ts` 的 approve → applyEdit）：

- 先 `backupFile`。
- **apply 时重新定位 find，不信提案时刻的位置**——卡片挂着的时候用户可能一直在编辑。定位规则：`indexOf < 0` → throw「Document changed — the target text no longer matches.」；`indexOf !== lastIndexOf` → throw「appears more than once — too ambiguous to apply automatically.」（草稿里重复行很平常，取第一个命中会改写用户从未批准的文字）。
- **活动文档走编辑器 buffer**（编辑器 store 的 setContent）——保住未保存内容、改动立即可见并触发自动保存；非活动文档才直接读盘/写盘。
- **`applyProposal` 的任何 throw 都被 approve 捕获并 `resolve({ approved:false, reason:`apply failed: ${e}` })`**——失败以拒绝形式回到模型，模型知道内容未动；绝不吞错报成功。

其余 L2 工具的预检同样前置：create 类归一化扩展名并拒绝已存在路径；move 类源必须存在、目标不得存在（rename 永不覆盖）、拒绝移入自己的子树；delete 类**强制要 reason**（「用户只凭这一行做决定」）、**拒绝目录**（删除整个目录的爆炸半径应当是用户自己在 UI 里做的决定，不该运行中一张卡批掉）。多个 L2 工具共享一个入口函数（`manuscriptTarget()` 式）统一做 path 校验 + 审批通道存在性检查。

---

## 4. Proposal 判别联合与 ApprovalDecision

```ts
export type Proposal = EditProposal | CreateProposal | MoveProposal
                     | DeleteProposal | IllustrateProposal;
// 共同基底：{ id, path, reason? }
// edit:   { kind:"edit", find, replace }          — find 必须在文件中恰好出现一次
// create: { kind:"create", content }
// move:   { kind:"move", newPath, isDir }
// delete: { kind:"delete", chars }                — 提案时的字符数，卡片展示「删多少」
// illustrate: { kind:"illustrate", prompt, destination, dest, note,
//               modelId, modelName, costUsd, aspect?, sourcePath? }  — 唯一花钱的 kind

export type ApprovalDecision =
  | { approved: true; backupPath?: string | null }
  | { approved: false; reason?: string };
```

两条规范：

- **按 kind 打标签，不用一个宽对象。**审批卡渲染与落盘 switch 都靠判别收窄；TS 穷尽检查保证「加了 kind 却漏了卡片 body 或落盘分支」是**编译错误**。
- **花钱的提案把价签带在身上**：`illustrate` 携带模型名/单价/预估费用——卡片必须展示「批准 = 花这笔钱」，且生成发生在**批准之后**（拒绝零成本）。

---

## 5. 审批队列与会话 store

参考实现：simple-ai-writer `src/stores/agentStore.ts`。

### 5.1 三条队列 + runId 作用域

```ts
pending: PendingApproval[]               // { proposal, resolve, runId, turnId?, signal? }
pendingPlans: PendingPlan[]              // { plan, resolve, runId }
pendingRoundLimits: PendingRoundLimit[]  // { id, roundsUsed, extension, canPause, resolve, runId }
```

- **入队模式统一**：`requestApproval / requestPlanApproval / requestRoundExtension` 都是 `new Promise(resolve => set(入队 {…, resolve, runId}))` ——**resolve 函数就存在队列元素里**。UI 卡片按队列渲染；用户点击时找到元素、出队、调用 resolve，被阻塞的 tool loop 就地恢复。
- **RunId = 每次运行自己的 AbortController 对象**（`type RunId = unknown`，store 只做 `===` 比对）。为什么必须有作用域：面板任务和对话轮可以**同时**各有 pending 卡片，一个结束时的清扫不能误杀另一个的。
- **不变量：`rejectAll(reason, runId)` 在每次运行的 finally 和 stop 里都必须调用。**按 runId 过滤三条队列并全部 resolve（approval/plan → `{approved:false, reason}`；roundLimit → `{action:"finish"}`，紧接着 runtime 会重查 aborted 信号）。悬挂的 Promise 会永久卡死后续运行——这是队列体系的头号生存法则。
- **`turnId` / `signal` 在请求审批时显式绑定进队列元素**，不能在 apply 完成时用「当前轮是谁」推断。陷阱（真实事故）：批准生成图片后用户按停止，图画完了却丢了——批准瞬时、生成漫长，apply 可以活得比 run 长；停止早已清掉了「当前轮」标识，靠身份比对把用户已付费的产物丢掉了。`signal` 同理随绑定传入，让「已批准但很慢的 apply」可被取消。

### 5.2 chatHistory 与 turns 双层结构

- **`chatHistory: StreamMessage[]`（wire 层）**：与 runtime 原地 mutate 的是**同一个数组**。轮 N 的工具调用与结果留在上下文里供轮 N+1 指代（「把刚才那条也改了」）——这是真会话与重复单发的分水岭。
- **`turns: ChatTurn[]`（展示层）**：`{ id, role, text, log: AgentEvent[], at, quote?, images? }`。每个 assistant 轮内嵌自己的执行日志；`text` 由 onOutputText 快照赋值（工具轮撤回叙述才成为可能）；`images` 由**审批方**以 turnId 填入——模型对「应用已把图放进转录」一无所知，靠模型自述会产出「抱歉我无法展示图片」。
- **分层理由（规范）**：wire 数组要满足协议（tool_call 配对、顺序、压缩折叠），展示层要满足阅读（每轮日志、引用块、displayText 替身——resume 时发给模型的是整份任务文档，屏幕上只显示一行「继续任务 X」）。两者形状需求根本不同，硬用一个结构必然两头受伤。
- **`chatMeta` 全部按消息对象身份记录，不用索引**：哪条是种子上下文、哪条是滚动摘要、每轮从哪条 user 消息开始、注入台账（条目 → {version, carrier 消息对象}）。原因：`repairToolCallPairing` 会 splice（索引位移），trimHistory 只换 content（对象身份存活）——索引在这套体系里没有稳定语义。
- 配套细节：history 被原地 push 时数组引用不变，响应式 selector 看不见变化——凡历史构成变化的点都要 bump 一个版本号（`chatContextVersion`）。会话持久化每轮 finally 里 best-effort 执行（「丢会话的崩溃从不提前打招呼」），**序列化时剥离全部图片 base64**（路径留在转录里，可再读取）；持久化失败只降级为「不能跨重启」，绝不弄坏进行中的对话。

### 5.3 sendChat 一轮的完整时序

1. 解析模型/供应商/密钥；**一次性原子读取**当前文档焦点，整轮持有（不在轮中反复读取——用户可能正在编辑）。
2. 组装本轮 wire 消息（引用段 + @引用素材前置；附图由模型 multimodal 能力与 vision 子代理可用性共同决定）。
3. **首轮**：RAG 组装 → 产出**三条消息**（system / 种子上下文 / 问题——分开是为了日后压缩能只丢种子不丢问题）；建 meta、记轮起点、把种子携带的领域条目记入注入台账（否则轮 2 检索会重复注入刚给过的东西）；发 `context-seeded` 事件。**agent 行为指令拼进 system 层**而非首轮 user 层——陷阱：拼在首轮 user 里，轮 2 起只追加裸 user 消息，指令活不过第一轮，助手退化成「只给方案不动手」。
4. **后续轮**：`repairToolCallPairing` → 超过触发线则轮间 compaction（best-effort，失败继续用未压缩历史）→ per-turn 注入（重跑检索，减去台账里已在场且未变的条目）→ push 问题消息。
5. `routeTools` 生成有效 preset → `runAgent({ …, toolContext: { loreIndex: 最新索引, lorePlan: createPlanGate()（每轮新门）, taskWorkspace: 会话级句柄, requestApproval / requestPlanApproval → store 队列, … }, onRoundLimit → 队列, onEvent → patch 本轮 log + bump 版本号, onOutputText → patch 本轮 text })`。
6. `outcome === "paused"` → 标记任务暂停 + 记录来源文档 hash（resume 时校验引用新鲜度）。
7. 记账（usage 累计、run-done 事件、持久化用量）。
8. **finally：`rejectAll("task ended", controller)`（只清本轮的）→ 清 running 态 → 持久化会话。**

`resumeTask` 概述：**不回放旧对话**——读任务文档 + 笔记索引 + 来源引用哈希比对（改过/删了/读不了逐条标注），拼成一条干净的 user 指令重新开轮；展示层只显示一行「继续任务 X」（displayText 替身）。

---

## 6. 本篇检查清单

- [ ] `ToolId` 是字面量联合，`REGISTRY: Record<ToolId, RegisteredTool>` 使漏注册成为编译错误；定义、access、执行器 collocate 在注册表一处。
- [ ] `executeRegisteredTool`：白名单用类型收窄（type guard）而非 cast；永不 throw；错误文案写成下一步动作指引。
- [ ] 需要按运行时配置变化的 schema 参数（enum 等）在 `getToolDefinitions` 下发时**拷贝后**注入，绝不 mutate 模块级常量；描述文字与 enum 同步。
- [ ] 模型可控的路径参数全部过包含校验；`projectPath === ""` 显式拒绝（空前缀包含一切绝对路径）；文件名参数禁 `/`、`\`、`..`。
- [ ] 界面能力以 ToolContext 通道的在/不在表达：无 `requestApproval` 的界面 L2 工具自动拒绝；无方案通道或无 gate 的界面领域写工具拒绝。
- [ ] 所有 L1 写工具遵循「参数校验 → 结构校验 → 门控 → backup → write → 修快照 → 变更回调 → 带备份路径的成功回执」顺序；**备份 throw 时写入不发生**。
- [ ] 含二进制资产的删除走整目录 rename 进备份区，不走文本复制；删除操作在备份缺席时报错而非静默成功。
- [ ] 方案门控：批准是**追加**不是替换；file-scoped 步骤绝不放行无 file 的调用；实体名经索引解析比对；gate 按运行/按轮新建。
- [ ] L2 propose_edit：提案前预检唯一性；apply 时重新定位（不见了/多于一处都转拒绝）；活动文档走编辑器 buffer；apply 失败以 `{approved:false, reason}` 回模型，绝不吞错报成功。
- [ ] Proposal 是按 kind 的判别联合，穷尽检查覆盖卡片与落盘分支；花钱的 kind 把模型名与预估费用带在提案上，生成发生在批准之后。
- [ ] 三条审批队列的元素内嵌 resolve；runId = 本次运行的 AbortController；**每次运行 finally 必调 `rejectAll(reason, runId)`**；产物归属的 turnId/signal 在请求审批时绑定。
- [ ] wire 历史与展示层 turns 分层；meta 按消息对象身份记录（不用索引）；序列化剥离图片 base64；持久化 best-effort、失败不破坏会话。
