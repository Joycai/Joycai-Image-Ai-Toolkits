# 10 · 长会话上下文管理：任务工作区、压缩与会话持久化

> 本篇解决的问题：agent 的 wire history 是唯一记忆时，长任务必然走向「灌满 → 破坏性裁剪 → 丢结论 → 重做」的循环，长会话必然走向超窗，崩溃则丢掉一切。本篇给出三套互相咬合的机制：**任务工作区**（把任务事实落盘，让裁剪从破坏性变成可恢复）、**上下文压缩**（四层防线管住对话本身）、**会话持久化**（让会话活过重启且不被旧数据打崩）。工作区管「查到什么、做到哪」，压缩管「聊过什么」——两者平行，互不替代。

参考实现：simple-ai-writer `src/lib/agent/taskWorkspace.ts`、`scratchpadTools.ts`、`compact.ts`、`compactRun.ts`、`chatRefs.ts`、`transcriptFold.ts`、`chatSession.ts`。

---

## 1. 任务工作区

### 1.1 目录结构与归属

```
<projectPath>/.ai-writer/tasks/
  └── 20260814-163000-a1b2c3/        ← taskId = YYYYMMDD-HHmmss-6位随机（时间序 + 唯一）
        ├── task.md                   ← 机器元数据(注释头) + 人可读可手改的 markdown
        └── notes/
              ├── search-xxx.md       ← 中间结论：搜索/识图/长读/子代理产出
              └── ...
```

归属规则：

- 不进用户内容目录、不出现在文件树、不参与导出；
- **进项目备份**——tmp 是 scratch 所以排除，tasks 是可恢复状态所以包含。这条应当写进备份模块注释，防止后人「顺手清理」。

### 1.2 懒创建句柄 `TaskWorkspaceHandle`

绝大多数 run 是短任务，不该凭空产生任务目录。核心抽象：

```ts
export interface TaskWorkspaceHandle {
  readonly taskId: string | null;   // null = 这次运行还没用到工作区
  ensure(title: string): Promise<{ taskId: string; dir: string }>;  // 首次创建/复用
}
```

两个工厂：`createTaskWorkspace(projectPath, modelId)`（懒句柄，首次 `ensure` 才建目录写 task.md，然后异步 `void gcTasks(projectPath, keepId)`）与 `existingWorkspace(projectPath, taskId)`（恢复用）。

**生命周期归属由 surface（调用方）决定，不由工作区自己决定：**

- 单次编辑器任务 **per-run**——一个任务一个工作区，run 开始时置空上一个的；
- 会话式 chat **per-session**——turn 3 存的 note 在 turn 9 还要能读，这正是落盘的意义；新对话时置空（「新对话不该继承上一个话题的笔记」）；
- 无工作区的 surface（弹窗类小工具）不传 handle，scratchpad 工具返回统一错误文案。

### 1.3 task.md 格式：单一事实源

```markdown
<!-- ai-writer-task
{"taskId":"...","status":"in_progress","modelId":"mdl-7","createdAt":"...","updatedAt":"...","sourceRefs":[{"path":"writing/第03卷/第45章.md","hash":"3f8a9b1c"}]}
-->

# 调查东境贵族世系与魔法起源

## 步骤 <!-- ai-writer-task-steps -->

- [x] 检索东境三大家族设定
- [/] 分析初代家主与禁忌魔法关联
- [ ] 起草补充设定并更新词条

## 进度记录 <!-- ai-writer-task-log -->

- 16:32 家族关系网比对完成，见 `notes/search-east-nobles.md`
```

设计决策逐条（每条都是踩过坑的）：

1. **不变量：JSON 注释头只放机器状态**（`TaskMeta`：taskId/status/modelId/createdAt/updatedAt/sourceRefs），**步骤的标题与状态只存在于正文的复选框列表里，JSON 里一个都不放**。工具按 **1 基序号**寻址步骤，连 step.id 都不需要。用户手改 `- [ ]` 为 `- [x]` 就是真的改了状态——不存在两份数据打架。这是「人可编辑文件 + 机器状态」共存的标准解法。第一版 JSON 和正文各存一份步骤，用户手改正文后即打架。
2. **复选框字形即状态**：`[ ]` pending · `[/]` in_progress · `[x]` done · `[-]` skipped。**缩进的复选框也算一步**（STEP_RE 允许前导空白）：用户照渲染后的列表数序号，解析器漏一条会让其后每个序号错位、勾错行。
3. **小节靠语言无关锚点注释定位**（`<!-- ai-writer-task-steps -->` / `<!-- ai-writer-task-log -->`），标题文本走 i18n（用户要读这个文件）。**陷阱**：按标题文本找小节，第一次切换应用语言就会把进度记录写到别处。
4. 解析要宽容：`parseTaskDoc` 对损坏元数据返回 null 不抛；`taskTitle` 找不到 H1 返回 null（正文用户可任意编辑）。
5. 小工细节：`appendLogToBody` 插到**小节末尾而非文件末尾**（用户在下面加了自己的小节后，追加到文件尾会把日志记到别人的标题下）；`withSteps` 替换整段时连空行一起换、每侧只写一个分隔（否则每次 re-plan 文件多长一个空行）。

### 1.4 任务状态机

```ts
export type TaskStatus = "in_progress" | "paused" | "completed" | "failed";
```

```
(无) --task_plan / 首次 write_note--> in_progress --步骤全部 done/skipped--> completed
                                        │  撞轮上限选「存盘暂停」
                                        ▼
                                     paused --UI「继续」(resumeTask)--> in_progress
                                        │  运行异常 / 恢复失败
                                        ▼
                                     failed
```

- `completed` 由 `task_progress` 自动判定：改完后 `parseSteps` 全部 done/skipped 且当前 `in_progress` ⇒ 置 completed。
- `paused` 由调用方在 `runAgent` 返回 `outcome === "paused"` 后写（`markTaskPaused`：置状态 + 追加一条进度日志）。
- **陷阱（僵尸任务）**：`markTaskResumed` 在恢复时**乐观**置回 in_progress；若恢复的发送根本没跑起来（报错），必须再 `markTaskPaused` 回去——「不留一个声称在跑的任务」。

### 1.5 存盘暂停：round-limit 的第三个出口

runtime 撞轮上限的回调契约不能是 `Promise<number>`——一个数表达不了「暂停」。应当用判别联合：

```ts
export type RoundLimitDecision =
  | { action: "extend"; rounds: number }
  | { action: "finish" }     // 撤工具、强制成文
  | { action: "pause" };     // 不再发请求，直接收工

// AgentRunResult 增 outcome: "completed" | "paused"
```

- **暂停必须发生在轮首**（进入 force-text 最后一轮前、且 round > 1、preset 有工具、调用方给了 onRoundLimit 时阻塞询问；选 pause 就地 return `outcome: "paused"`）。轮首暂停是干净的：上一轮的 tool_calls 全部已配对，history 合法，不需要 repair。
- UI 卡片三个按钮：就此收尾 / 存盘并暂停 / 继续（再 N 轮）。
- **陷阱（按钮出现在错误的 surface）**：「存盘并暂停」的可见性由 `PendingRoundLimit.canPause` 决定，**由发起 run 的一方在撞上限那一刻求值 `!!tw.taskId`**——不是 run 开始时（模型三轮前建的工作区也算）；也不能让共享的卡片组件自己去读会话状态，否则按钮会出现在没处理 paused 的一侧，「点下去整轮工作无声消失」。**每一个**处理 run 结果的调用方都必须处理 `outcome === "paused"`：`markTaskPaused` + `recordSourceRef`（当前文档路径 + FNV-1a 哈希），不再强跑成文轮。

### 1.6 恢复：`buildResumeSeed`——恢复状态，不重放对话

**陷阱（根病）**：恢复时重放旧 wire history，历史里用户的 `continue`、`重试` 会被当成新指令，agent 自我强化地继续。「继续」必须从**重放对话**变成**读取状态**：

1. `loadTaskDoc` 读 task.md；
2. **参考文件新鲜度**：逐条比对 `meta.sourceRefs` 的 FNV-1a 哈希，产出 `- path（已删除/已修改/无法读取）` 清单。sourceRefs 的**唯一写入方是暂停时刻**（recordSourceRef）——恢复要比对的正是「任务挂起时的那个状态」；给模型读过的每个文件都算哈希则要多一次整文件读。**准则：字段必须真有写入方——只声明而无人填，检查就永远不会触发。**
3. notes 索引**只给标题 + 路径 + 字符数，不给正文**；
4. 拼一条全新 user turn（模板含 task.md 正文 + 笔记索引 + 过期清单 + 「用 read_note 读详情」的指令），**不带任何旧 wire history**。

恢复流程（参考实现 `resumeTask`）：停掉当前 → buildResumeSeed → markTaskResumed → **清空整个会话状态**（turns/history/meta/sessionId 全 null）但把工作区设为 `existingWorkspace(taskId)` → 发送种子（转录里显示友好的「恢复任务：xxx」而非整段种子，`displayText` 参数）。

### 1.7 GC：排序淘汰，不豁免

`MAX_SAVED_TASKS = 20`。排序规则：**已收尾（completed/failed）排前、优先淘汰**，同组内 updatedAt 旧的先删；只删超额部分；**绝不删当前 run 持有的 keepTaskId**；损坏目录按 failed 处理。

**陷阱**：「未完成的优先留下，但**不豁免**」——第一版「未完成不清理」会让一串永不收尾的任务无界增长。触发点在 `ensure()` 建目录之后异步执行，失败只 warn。

---

## 2. Scratchpad 工具

### 2.1 五个工具

注册进同一个工具注册表，追加在主 agent 的 preset 工具表末尾：

| 工具 | access | 参数 | 行为 |
|---|---|---|---|
| `task_plan` | write-auto | `{title, steps: string[]}` | 建立/重写标题与步骤表；**保留**进度记录小节与用户手写内容（re-plan 是正常动作，不能抹掉已做记录）；两参数都必填非空 |
| `task_progress` | write-auto | `{action: "check"\|"start"\|"skip"\|"add_step"\|"log", step?, text?}` | 增量改一行；step 是 1 基序号，越界返回可读 error（含当前步数）；全部 done/skipped 自动置 completed |
| `write_note` | write-auto | `{slug, title, content, sources?}` | 写 `notes/<slug>.md`，自动补 H1 标题 + 来源引用块；返回相对路径与字符数；撞名自动 `-2`/`-3` 后缀并**告知真实文件名**（renamedFrom） |
| `read_note` | read | `{path\|slug, start_line?}` | 行号分页回读，单页 4000 字符按行边界切，回报 `[lines a-b of N]` 与下一个 start_line |
| `list_notes` | read | `{}` | 列出 slug/标题/路径/字符数，**不给正文**；按 slug 排序（readDir 顺序不稳定，同一会话两次列表要长一样） |

### 2.2 六条关键不变式

1. **谁能创建工作区**：只有 `task_plan`（用真实标题——标题即计划主题）与 `write_note`（checkpoint 提示点名要它，拒绝会让提示变死路；但用**中性标题**建仓——「任务叫什么归 task_plan 管，让碰巧第一个落盘的笔记命名整个任务是抽彩票」）。`task_progress` **不创建**（`requireTaskId` 拒绝）。
   **陷阱**：从 progress `ensure()` 会创建任务并顺带满足「要求先有计划」的检查，导致「先调 task_plan」的分支永远走不到，留下一个以空为题的工作区。另外新工作区**零占位步骤**——伪造「- [ ] 开始任务」会被 parseSteps 数进去，模型还会去勾一条它没写过的步骤。
2. **路径沙箱靠 Unicode slug 清洗**：`sanitizeSlug` 用 `/[^\p{L}\p{N}-]/gu`——**保留任何文字系统的字母数字**。
   **陷阱**：不能写 ASCII 白名单——纯中文 slug（「搜索结果」「第一章分析」）会全被清空、回落到同一个 `note.md` 互相覆盖，「正是工作区要防的那种丢失」。清洗后不可能含 `/` `\` `.`，拼进 notes 目录天然出不去，无须再叠路径包含检查。按**码点**截 60 字符（UTF-16 单位截断会切开代理对）。读侧 `noteSlugFromReference` 接受相对路径 / `<slug>.md` / 裸 slug 三种形态（前两种来自本应用自己的工具输出——拒绝良性输入报 security error，模型读到 "access denied" 倾向于原样重试而非改格式）；指向**别的任务**返回 null（「读一篇没被要求的 note 比找不到更糟」）。
3. **绝不覆盖**（撞名加后缀）：静默覆盖等于丢数据，而模型没有任何办法察觉它发生过。
4. **大小熔断**：note ≤ 100,000 字符、task.md ≤ 20,000 字符；超限返回 tool error **而非截断**（截断会让模型以为写成功了）。
5. **不备份、不过审批门**：write-auto 在别处意味着「自动应用 + 写前备份」，但工作区是 agent 自己的草稿纸——备份无恢复价值只翻倍磁盘；审批门是为「改用户的内容」设的，「加门只会让模型在自己的笔记本上也要请示」。
6. **写入串行化**：模型同轮可发多个 tool call，两个 task_progress 并发读改写会丢更新。所有 task.md 写入过 `serializeTaskWrite`（模块级 `writeChain: Promise` 链）。
   **注意**：串行链应当放在**工作区模块**而不是工具文件——工具不是唯一写者，暂停/恢复/recordSourceRef 都在读改写同一文件，只覆盖工具的链会让它们与工具竞态。

### 2.3 主/子 agent 的交接：单向、经文件

子代理自己没有 scratchpad 工具（ctx 无 workspace），它的全部产出 = 最终成文文本 → delegate 执行器代写成一篇 note → 主模型拿到「摘要 + 路径」 → 需要细节时 `read_note` 分页读。主模型自己则用 `task_plan`/`task_progress` 维护计划、用 `write_note` 在裁剪来临前抢救结论。**没有共享内存、没有双向通信——「总线」就是 notes 目录。**

### 2.4 checkpoint 注入：让模型真的用起来

光有工具不够，模型不会主动用。preset 应当有三档 `scratchpad: "off" | "offered" | "required"`（默认 off ⇒ 整套机制可整体回退；主助手 preset 用 required）。required 时，轮循环顶部、裁剪逻辑**之前**：

- 触发条件：`estimateMessagesTokens(history) > inputCeilingTokens * 0.85`（`CHECKPOINT_RATIO`，**必须早于**裁剪的 `> ceiling` 触发点——提醒发出时内容不能已经被删了）且 `!checkpointArmed`；
- 注入一条 user 提示（「上下文接近上限即将裁剪，请用 write_note 把关键结论写进笔记」），**发出即撤**：finally 里按对象身份 splice 掉。
  **陷阱**：一次性话术留在持久 history 里会变成「之后每一轮的常驻命令」——这正是「agent 不停告诉自己用户要求继续」那类故障的成因；
- `checkpointArmed` 在裁剪**真正丢了内容**（dropped > 0）后重新置 false——只提醒一次的话，长任务后段照样丢。

闭环由此成立：**接近上限 → 提醒落盘 → 裁剪（破坏的只是上下文里的拷贝）→ 需要时 read_note 取回。** 裁剪从破坏性变成非破坏性。

---

## 3. 上下文压缩

压缩是**与工作区平行的另一层**：工作区管「查到什么、做到哪」（任务事实），压缩管「聊过什么」（对话）。互不替代。完整体系四层防线：

| 层 | 时机 | 单位 | 性质 |
|---|---|---|---|
| ① compact（轮间折叠） | 每个 chat turn 开始前 | 整轮（turn） | 摘要化，非破坏（信息进 rolling summary） |
| ② trimHistory（轮内裁剪） | 每个 round 请求前 | 单条工具结果/图片 | 破坏性兜底（配合 scratchpad 变可恢复） |
| ③ checkpoint 注入 | 裁剪将至（85%） | —— | 提醒模型落盘 |
| ④ transcriptFold | 渲染层 | 显示条目 | 纯展示折叠，不碰 wire history |

### 3.1 触发与预算常量

```ts
COMPACT_TRIGGER = 0.7        // history 估算 token 超过输入上限的 70% 触发
RETAIN_TARGET  = 0.45        // 折叠后目标降到 45%
MIN_KEEP_TURNS = 2           // 无论多超，最近 2 轮永远原文保留
SUMMARY_BUDGET_TOKENS = 1000 // rolling summary 的软上限
FOLD_RESULT_CLIP = 200       // 喂给摘要器时每条工具结果截 200 字符
FOLD_TEXT_CLIP   = 2000      // user/assistant 正文截 2000
```

**陷阱（prompt cache 被压缩杀死）**：trigger(0.7) 与 target(0.45) 之间必须留宽间隙。一个多工具轮能长几千 token，间隙太窄会**每轮都压**——每次都作废 prompt-cache 前缀。

### 3.2 两个根本不变式

1. **轮边界按消息对象身份记录，不按索引。** history 会被不知道「轮」概念的各方原地改：配对修复逻辑会 splice 插桩（索引全移位），裁剪换的是既有对象的 `content`（身份不变）。会话元数据的 `turnStarts: StreamMessage[]` 存的是**用户提问消息对象本身**，对两种改动都免疫。
2. **折叠单位是整轮。** `role: "tool"` 回复必须紧跟发起它的 assistant 消息——主流 provider 都拒绝拆开的 pair，而坏掉的 history 是永久的（它就是会话本身）。user+assistant+tools 整轮一起折，永远不会撕开配对。

### 3.3 折叠计划（planFold）

`segmentHistory` 按 turnStarts 切出 prelude（system + seed + summary）与 turns → 未超 trigger 或可折轮数 ≤ 0 返回 null → 从最大折叠量倒着走，「有余量就多留一轮原文」，直到留存投影贴近 target（summary 按预算上限的最坏值计入）；就算最大折叠也够不到 target 仍返回 best effort（「释放大部分空间好过一点不放」）。首次折叠顺带丢 seed context（`dropSeed`）。

### 3.4 摘要请求与重建

- 时机：**每个 turn 的用户消息入 history 之前**（发送入口处），不是轮内。
- 摘要 prompt：system 用专用指令模板；user = 已有摘要（**以纯文本传入**，不从 wire 消息剥块头）+ 折叠轮的降采样渲染。渲染格式是语言中立的数据行：`[user] ...` / `[assistant] ...` / `[tool call] name args截200` / `[tool result] 截200` / 图片替换为 `[image]`。摘要指令里应当要求「保留提到过的 notes/ 路径」，防止折叠吃掉 note 引用。
- 摘要器就是**会话自己的模型**跑一次无工具 completion（独立函数，便于将来换专用摘要模型）。
- **不变量（失败原子性）**：summarize 失败或返回空 ⇒ 返回 null，history 和 meta **一个字不动**，本轮不压缩继续跑（裁剪层仍兜底），下一轮阈值会再触发；只有 AbortError 上抛（那是用户取消了整次发送）。「压缩绝不能把一次网络抖动变成受损会话。」空摘要视为失败——「拿上下文换一行空白」不可接受。`buildCompactedHistory` 返回**新数组**，调用方在摘要成功后才换入。
- 重建后的 history：`[prelude(去掉 seed 与旧 summary)] + [summary 消息(role: user, 【历史摘要】块)] + [保留轮原文]`。**summary 紧贴 system 之后**——让稳定前缀最大化，保 prompt caching。同时更新 meta：turnStarts 换成保留轮的 start；注入台账按 carrier 是否还活着逐出（见 §3.6）。

### 3.5 @引用注入：三道预算与顺序渲染

用户显式 `@` 的引用应当**内联而非只报名**——「作者已经决定助手该看它，让这变成模型可跳过的建议是赌博，还多花一次往返」。预算三道（参考实现 `chatRefs.ts`）：

- `REF_CHAR_CAP = 6000`：单个引用最多内联 6000 字符，超出部分截断并注明「`用 read_file 于 <path> 读全文`」（**绝不静默截断**）；
- `REF_TOTAL_CHAR_BUDGET = 18_000`：一条消息全部引用的总预算。**顺序渲染而非 Promise.all**——每个引用的额度取决于前面用了多少，「前几个完整到达、尾部退化成指针」，好过全部被均匀截成残段；预算耗尽的引用只报名 + 路径；
- `MAX_MESSAGE_IMAGES = 4`：单消息图片数上限（与裁剪层的会话级图片上限分立——那是管累计，这是管「必须先成功的那一个请求体」）。

消息拼装顺序：【选中内容】→【引用资料】→【附图】（带编号文件名——parts 数组不带文件名，「第二张图里的外套」要能解析）→ 未发送图片告示 → **用户原话放最后**（最新读到的东西；上面全是执行材料）。图片 parts 排在文本后。

### 3.6 注入台账：version 指纹 + carrier 逐出

自动检索注入的知识块（如 lore 实体）需要会话级去重台账：

- `meta.injected: Map<dirPath, { version, carrier }>`：version 是内容指纹（元数据 JSON 的哈希，不读文件）；carrier 是**携带它入会话的那条消息对象**。
- 每轮检索时：台账里且版本未变的实体**跳过不再注入**；实体被编辑过（指纹变了）会重新匹配、重新注入、覆盖台账条目。
- 折叠时 carrier 消息**整条跳过不进摘要**（「检索块是可复现数据，摘要预算不该花在索引本来就知道的东西上」）；重建后 carrier 不在新 history 里的条目被逐出台账——「那个实体已不在会话里，之后再提到必须重新注入」。
- 模型**自己用工具读的**内容刻意不入台账：「那是它的工作记忆——折掉即忘，它随时可以再读」。

### 3.7 transcriptFold：显示层折叠

与 wire 完全无关的第四层：`FOLD_KEEP_ENTRIES = 8`（最近 8 条 user/assistant 恒显示），`FOLD_MIN_HIDDEN = 4`（藏不满 4 条就不出折叠条——「两条消息藏在控件后面比两条消息更糟」）。`foldBoundary` 的切点**向回走到 user 条目**——可见转录必须以问题开头，「一个问题被藏起来的回答读起来像在回复虚空」。折叠逻辑应当抽成纯函数单独成文件以便测试（组件文件常拖着测试环境加载不了的宿主 import）。

---

## 4. 会话持久化

一个会话 = 显示轮（turns）+ wire history + 会话元数据 + 累计用量，压成**一个 JSON blob** 存一行（参考实现 `MAX_CHAT_SESSIONS = 5`，写入路径 GC）。每个 turn 结束（成功或失败）都 `void persistChat()`——「丢会话的崩溃从不提前打招呼」。

### 4.1 对象身份的序列化：身份 → 索引

这是本模块拥有的那个非显然问题：会话元数据按**对象身份**引用 history 消息（turnStarts、seed、summary、每个注入 carrier），而 JSON 没有身份。规范：

- 序列化把每个引用转成 **history 索引**（`indexOf`，-1 表示 null；injected 存 `[dirPath, version, carrierIndex]` 三元组）；
- 反序列化把索引重新连回新解析出的对象；
- 解析不到的引用（损坏行、越界索引）**丢弃而非猜测**。

### 4.2 图片剥离

`withoutImageData` 把 history 里的 base64 换成占位文案（「图片未保存在会话里——需要就再读一次」）。一张图 1–12MB data URL、blob 每轮重写一次；恢复的会话也用不上像素（问题已答完，路径都在转录里，模型可再读一次）。**不变量：拷贝不改原对象、顺序 1:1 保留**——meta 的索引是对原数组算的。

### 4.3 偏执反序列化

`v !== 1`、任何形状不对 ⇒ 返回 null，调用方开新会话。「恢复不了是不便，半恢复的 history 是之后每一轮的协议错误。」

### 4.4 事件格式迁移

会话 blob 比写它的代码活得久——**持久化的事件载荷实际上是 wire format**。参考实现的真实事故：round-limit 事件从 `granted: number` 改成 `decision` 判别联合后，一条旧行到达渲染层读 `event.decision.action` 把整个 AI 面板打穿 error boundary。规范：

- 给旧格式写迁移函数（`migrateLogEvent`：`granted > 0` 映射为 `{action: "extend", rounds}`、否则 `{action: "finish"}`）；
- 认不出的条目返回 null 被丢弃——「丢一行日志值得，丢一个会话不值得」。

### 4.5 其余要点

- **`maxTurnId`**：turn 计数器随应用重启归零，恢复会话时必须抬高计数器，否则会铸出与屏上已有 turn 撞号的 id——React key 静默复用错误子树。
- **persist 竞态防护**：写完只在会话没被换掉时（`get().chatHistory === chatHistory`）采纳返回的行 id。
- 明确「尚未持久化」的项要写下来：参考实现的 `chatTaskWorkspace` 不进 blob（重开旧会话开新工作区，标注为后续工作）；会话级子代理开关也不进（「临时开关不值得为它改格式」）。

---

## 本篇检查清单

- [ ] `TaskWorkspaceHandle { taskId: string | null; ensure(title) }` 懒创建；生命周期归属由 surface 决定（单次任务 per-run，会话 per-session）；备份包含 tasks 目录并写明理由。
- [ ] task.md：JSON 注释头只放机器状态；步骤只存在于正文复选框（`[ ]`/`[/]`/`[x]`/`[-]`，1 基序号，缩进也算）；小节用语言无关锚点注释定位；损坏元数据返回 null 不抛。
- [ ] 五个 scratchpad 工具齐全，六条不变式逐条落实：只有 task_plan（真标题）与 write_note（中性标题）建仓、Unicode slug 清洗按码点截断、绝不覆盖（后缀 + renamedFrom）、超限报错不截断、不备份不过审批门、写入串行链放在工作区层。
- [ ] checkpoint 注入：三档开关默认 off；85% 阈值早于裁剪阈值；提示**发出即撤**（finally splice）；裁剪真丢内容后重新武装。
- [ ] `onRoundLimit` 返回判别联合 `{extend | finish | pause}`；pause 在轮首退出（history 天然配对完整）；`canPause` 由发起方在撞墙时刻求值 `!!tw.taskId`；每个调用方都处理 `outcome === "paused"`（markTaskPaused + sourceRefs 哈希）；恢复失败回滚 paused。
- [ ] `buildResumeSeed` = task.md 正文 + notes 索引（只标题/路径/字符数）+ sourceRefs 过期清单 ⇒ 一条全新 user turn，**不重放旧 wire history**。
- [ ] 排序 GC：已收尾优先淘汰、未完成不豁免、绝不删当前 keepTaskId。
- [ ] 压缩两不变式：轮边界按消息对象身份、折叠单位是整轮；0.7/0.45 宽间隙；摘要失败返回 null 一字不动（原子性），summary 紧贴 system 保 prompt cache。
- [ ] 注入台账 `Map<key, {version, carrier}>`：未变不重注、变了重注、carrier 折掉即逐出、模型自读的不入账；@引用三道预算顺序分配，绝不静默截断。
- [ ] 持久化：身份→索引序列化（解析不到就丢弃）、图片剥离不改原数组、版本不对返回 null 开新会话、旧事件格式有迁移函数、恢复时抬高 `maxTurnId`、persist 带换会话竞态防护。
