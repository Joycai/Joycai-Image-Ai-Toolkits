# 09 · 子代理机制（Delegation / Sub-agent）

> 本篇解决的问题：当 agent 需要联网搜索、读图、通读长文档这类**上下文密集**或**能力特定**的工作时，如何把它交给独立模型上的子代理去做，而不让原始材料（网页正文、图片 base64、长文切片）灌爆主模型的上下文。本篇给出 delegate 工具的完整契约、子代理的配置模型、确定性的能力路由规则，以及执行层的沙箱与记账规范。前置阅读：`10-context-management.md`（任务工作区）——**没有工作区，子代理机制不成立**。

参考实现：simple-ai-writer `src/lib/agent/subagent.ts`、`routing.ts`、`registry.ts`、`presets.ts`。

---

## 1. 动机与总体设计

### 1.1 四个现象，一个根因

引入子代理之前，应当先确认你面对的是同一类病。典型观测（来自参考实现接入服务端 `web_search` 后的真实数据）：

- 一次带搜索的任务 8 次搜索 / **123k input token**——网页正文、图片 base64、长文切片全部灌进主模型上下文；
- 历史裁剪（trimHistory）为避免超窗把旧工具结果替换成 `[earlier tool result dropped…]`（破坏性裁剪），模型丢失中间结论后**再搜一遍**，又填满；
- 撞 `maxRounds` 只有「继续加轮 / 强制收尾」两个出口，无法存档；
- 重跑时历史里作者的 `continue`、`重试` 被当成新指令，agent 自我强化地继续。

**根因只有一个：runtime 只有一种记忆——wire history。** 它落不了盘、挑不出重点，满了只能删（破坏性）或压（只服务轮间摘要）。子代理机制不是「多智能体框架」，而是给 runtime 补第二种记忆（落盘的 note）之后的自然延伸。

### 1.2 四条设计目标

1. **记忆落盘**——任务工作区（如 `.ai-writer/tasks/<taskId>/`），见 `10-context-management.md`；
2. **状态化断点续跑**——恢复「任务状态」而非「对话记录」；
3. **单层单向委托**——一个 `delegate` 工具，子代理独立模型 + 独立上下文，主模型只收「摘要 + 路径」；
4. **确定性能力路由**——在**工具集层**而非提示词层做能力隔离。

### 1.3 架构判断：「工作区是总线，子代理是设备」

这是整套设计的核心判断（参考实现 HLD §2 原话）：子代理的产出**不整块塞回主上下文**——那只是把堆叠换个地方堆——而是落盘成 note，回给主模型「一段摘要 + 一个路径」。没有工作区，子代理只会把今天的问题复制到主 agent 身上。

由此推出一条硬规则：**没有工作区的 surface 根本拿不到 `delegate` 工具**（由路由层落实，见 §4）。

整套体系一句话概括：

> **「记忆落盘 + 单层单向委托 + 工具集级能力路由 + 轮间折叠压缩」，四件事各管一段，互不越界。**

---

## 2. `delegate` 工具契约

### 2.1 工具定义与 JSON schema

工具名应当是 **`delegate`**（而非 spawn_subagent 之类），访问级别 `access: "read"`——它本身不写作者的任何东西，子代理只写自己的 notes。注册表定义（参考实现 `registry.ts` 原文）：

```ts
delegate: {
  access: "read",
  definition: { type: "function", function: {
    name: "delegate",
    description:
      "Hand a context-heavy or capability-specific job to a specialist subagent " +
      "running on its own model. The subagent works in a separate context, writes " +
      "its full findings to a note file, and returns only a short summary plus the " +
      "note path — so its raw material never enters this conversation. Use it for " +
      "web research, reading images, and digesting long documents.",
    parameters: {
      type: "object",
      properties: {
        kind: { type: "string", enum: ["search", "vision", "longread"],
          description: "search — look things up on the web; vision — describe or analyse images; longread — read long documents and report what matters." },
        task: { type: "string",
          description: "A complete, self-contained instruction. The subagent cannot see this conversation, so state everything it needs to know." },
        refs: { type: "array", items: { type: "string" },
          description: "Paths the subagent should work on (documents or images)." },
      },
      required: ["kind", "task"],
    },
  }},
  execute: executeDelegate,
},
```

三个值得照抄的细节：

1. **`task` 的 description 直接教模型写法**——「子代理看不到这段对话，把它需要知道的都写进来」。任务传递就靠这一段文本，没有任何隐式上下文继承。
2. **工具描述用领域中性词汇**——参考实现刻意用 `documents` 而不是「章节」：工具描述对所有 workspace profile 通用（跑团/文案项目不该读到小说词汇）。你的项目同理：工具描述不应泄漏某一种业务的词表。
3. **`refs` 是路径数组**，是主模型「点名材料」的唯一通道（文档或图片路径）。

### 2.2 任务下发：两条消息，零上下文渗透

子代理拿到的应当是**现场构造的两条消息**，不继承主会话任何内容：

```ts
const messages: StreamMessage[] = [
  { role: "system", content: i18n.t(`ai.instructions.subagent.${kind}`) },
  { role: "user", content: refs.length
      ? i18n.t("ai.instructions.subagentTaskWithRefs", { task, refs: refs.map(r => `- ${r}`).join("\n") })
      : i18n.t("ai.instructions.subagentTask", { task }) },
];
```

**不变量：有 refs / 无 refs 必须是两个模板键，不是一个键插空串。** 原因：带 refs 的模板自带「参考资源」小节标题，复用它插空串等于给子代理一条「去查这些来源」的指令而来源不存在。i18n 的 `defaultValue` 分叉也不行——键存在时 defaultValue 根本不会被采用。（参考实现 `delegateShape.test.ts` 对此有回归测试。）

### 2.3 产出捕获：只能经 `onOutputText` 回调

**陷阱：事后翻 `messages` 找最后一条 assistant 文本必然拿到空。** 可重入 runtime 的常见实现是成文轮直接 return，最终文本从不进 history（参考实现 `runtime.ts` 469-477 行）。所以子代理产出必须经 `onOutputText` 回调捕获（`output = text`，**累积快照赋值而非拼接**）。

### 2.4 返回契约：落盘 note + 摘要 + read_note 指针

成功路径应当是：

1. 产出落盘：`writeTaskNote(projectPath, taskId, { slug, title, content: output, sources: refs })`。
   - slug 只取指令前 **20 个码点**（`SLUG_HINT_CHARS`，如 `` `${kind}-${[...task].slice(0, 20).join("")}` ``）——「文件名是文件名，完整指令留在 note 首行标题里」；
   - title 取 `task.slice(0, 80)`。
2. 回给主模型的 tool result（content 是纯文本）：

```
The ${kind} subagent finished. Full findings saved to: ${note.path}
Call read_note with that path when you need the detail.

Summary:
${clip(output, 800)}    // DELEGATE_SUMMARY_CHARS = 800
```

800 字符这个数的判据（参考实现注释原话）：「够判断『要不要展开读』，不够顺手替代读 note」——逼主模型在需要细节时走 `read_note` **分页**读，而不是把子代理原始产出全量吞回上下文。

3. **空产出**（`!output.trim()`）直接返回 `Error: the ${kind} subagent returned nothing. Try a narrower task, or do it yourself.`，**不建 note**——不写空文件。

### 2.5 错误与中止

- 失败路径一律返回 `Error: ...` 前缀的 tool result——模型可读、可自纠；
- **唯一例外：`AbortError` 必须重抛**，不得转成 tool error。转成 tool error 会让主模型把作者按的「停止」读成「搜索失败」并重试，作者的停止键失效。

### 2.6 记账：独立 usage 行 + 带 `parentStep` 的嵌套事件

- 每次子跑写**一行独立的 token_usage**：`persistUsage(projectPath, conn.model.id, in, out, cost, \`subagent:${kind}\`, cached)`——`model_id` 是**子代理的**模型；task 字段打 `subagent:search` 这类标签，用量面板可按 `task LIKE 'subagent:%'` 聚合。
- 除 DB 行外，执行器还应当**手动发一条带 `parentStep` 的嵌套 `run-done` 事件**：`ctx.onNestedEvent({ kind: "run-done", inputTokens, outputTokens, parentStep: call.id, at })`。理由：DB 是永久账本但要打开设置页才看得见，而委托恰恰是作者**当下**要拍板花不花钱的那一步；`parentStep` 同时把这条事件排除在主 run 自身的 token 汇总之外（主 run 汇总只算主模型）。
- 记账工具函数应当放在 lib 层（如 `lib/ai/usage.ts`），**lib 层不反向 import store**。
- 解析连接就失败的 delegate **不发 run-done**——没花钱就不报花钱。

---

## 3. 子代理的配置与种类

### 3.1 数据模型

```ts
export type SubAgentKind = "search" | "vision" | "longread";
export const SUBAGENT_KINDS: readonly SubAgentKind[] = ["search", "vision", "longread"];

export interface SubAgentConfig {
  kind: SubAgentKind;
  modelId: string | null;   // Model.id（配置行主键），null = 未绑定
  enabled: boolean;
}
```

**设计准则：内置种类，不做任意自定义。** 每个 kind 决定三件事——preset（工具集 + 轮数）、输入形状、产出形状——「它们是代码而不是配置」。用户能配的只有「这个种类用哪个模型、开不开」。**没有自定义 system prompt**：子代理的 system prompt 是代码资产（i18n 键 `ai.instructions.subagent.{kind}`）。

### 3.2 每个 kind 的 preset（`SUB_PRESETS`）

| kind | 定位 | tools | maxRounds | serverTools | 产出 note |
|---|---|---|---|---|---|
| `search` | 联网检索查证 | `[]`（无本地工具，搜索发生在端点内部） | **2** | `"always"` | `notes/search-*.md`（要求带原始 URL） |
| `vision` | 图像理解 | `["read_image", "read_lore_image"]` | **3** | `"off"` | `notes/vision-*.md` |
| `longread` | 长文精读提要 | `["read_file", "search_text", "list_files"]` | **4** | `"off"` | `notes/read-*.md` |

三者一律 `finishPolicy: "force-text"`——子代理必须以文本收尾，那段文本就是产出。

**陷阱：`serverTools` 必须是独立于「收尾轮撤工具」的概念。** 若 runtime 用 `preset.tools.length === 0 || 收尾轮` 一并撤掉服务端工具，则本地工具恒为空的 search 子代理**永远不联网**。应当把「没有本地工具」和「该收尾了」拆成两个概念：`TaskPreset.serverTools: "final-round-off"(默认) | "off" | "always"`，search 用 `always`。默认值使既有 preset 行为逐字不变，可整体回退。

**边界：花钱且须逐次审批的动作（例：生图）有意不做成子代理。** 它必须走审批链路（提案 + 审批卡），与「子代理默默干活再交报告」的形态相反；塞进 delegate 只会绕过审批卡。

### 3.3 持久化与悬空绑定清理

- 配置应当是**应用级偏好**，不进项目目录——「它描述的是用户买了什么账号，不是这个项目的内容」。参考实现是 6 个 pref 键：`ai:subagent:{kind}:modelId` / `ai:subagent:{kind}:enabled`。
- store 暴露 `subAgents: Record<SubAgentKind, SubAgentConfig>` + `setSubAgent(kind, patch)`。
- **三处清理逻辑**保证绑定不会指向已删除的模型行：
  1. `loadConfig`——配置刷新后逐一验 modelId 是否还在模型表；
  2. `removeProvider`——删供应商连带清其模型的绑定；
  3. `removeModel`——删单个模型清绑定。
  这与「按用途绑一个模型」的其他偏好（如 memoryModelId/imageModelId）同一套模式。

### 3.4 设置面板：警告但不阻止

设置面板刻意做薄：每个 kind 只有**开关 + 模型下拉**。

- 下拉候选过滤掉不能对话的模型（如 `models.filter(m => m.enabled && m.type !== "image")`）。
- `warningFor(kind, model)` 就地内联警告：search 绑了无 `serverTools: ["web_search"]` 的模型、vision 绑了非 multimodal 模型时立即提示——「等运行时才报，作者已经白等一个往返，被告知一件这个界面早就知道的事」。
- **警告但不阻止保存**（用户可能配到一半）。因此下游一律必须用 `subAgentModel()` 再验（见 §4.2）——面板的宽容以下游的严格为前提。

### 3.5 会话级 chips：只减不增

对话输入框上方渲染**可用**子代理的 chips，可单次点掉（参考实现 `SubAgentChips.tsx`）：

- 显示条件是 `subAgentModel(k, models, subAgents) !== null`——「可用，不只是启用」；不可用的 kind 连 chip 都不出现（一个改变不了任何行为的开关不该展示）。
- 覆盖状态存会话 store（如 `agentStore.disabledSubAgents: SubAgentKind[]`），**不落偏好**——它是「这次对话」的意思，不是设置。
- **只减不增**：`withSessionOverrides(subs, disabled)` 把 disabled 里的 kind 强制 `enabled: false`，返回新对象。chip 只能关掉设置里已启用的，不能临时打开一个没绑模型的——「就这一次用一下」需要一个用户从未做过的绑定。
- 对话变化时**全部清掉**：新建对话、切换会话、切换项目都置空。只清一处，用户在对话 A 关的联网会跟进从历史打开的对话 B。

---

## 4. 能力路由

### 4.1 核心原则：路由 = 改工具集，不是改提示词

规则是「主模型也支持、子代理也支持时，**优先子代理**」。落实方式：「**改主模型看得见的工具集，而不是在提示词里写一条偏好。偏好靠模型自觉，工具集是硬保证。**」

`routeTools` 全文很短，应当整段照抄（参考实现 `routing.ts`）：

```ts
export interface RoutedTools {
  tools: ToolId[];
  serverTools: "final-round-off" | "off" | "always";
}

export function routeTools(
  preset: TaskPreset,
  subs: Record<SubAgentKind, SubAgentConfig>,
  workspace: TaskWorkspaceHandle | undefined,   // 是句柄不是 boolean，见下
  models: Model[],
): RoutedTools {
  let tools = [...preset.tools];
  const live = (k: SubAgentKind) => subAgentModel(k, models, subs) !== null;  // 可用，不只是启用

  // vision 接管看图：从主模型工具集里拿掉图片工具
  if (live("vision")) tools = tools.filter((t) => t !== "read_image" && t !== "read_lore_image");

  // 任一子代理可用 + 有工作区 ⇒ 追加 delegate
  if (SUBAGENT_KINDS.some(live) && workspace && !tools.includes("delegate")) tools.push("delegate");

  // search 接管联网：主模型不再持有端点搜索
  const serverToolsPolicy = live("search") ? "off" : (preset.serverTools ?? "final-round-off");
  return { tools, serverTools: serverToolsPolicy };
}
```

四条要点：

1. **longread 不接管 `read_file`**——主模型读一小段正文是日常工作，全部委托反而多一次往返；longread 是「通读一大摞」的加法，不是替代。接管应当只针对「主模型做会造成上下文灾难」的能力。
2. **search 启用 ⇒ 主模型 `serverTools: "off"`**。这不只是优先级——更是把服务端搜索那套 `pause_turn`/续跑/`tool id not found` 的续跑复杂度**关进子跑里**：主 history 从此见不到 `web_search_tool_result` 这类块。
3. **delegate 需要工作区**（子代理产出必须落盘），无工作区的 surface 不会莫名多出一个用不了的工具。
   **陷阱（假守卫）**：参数不要收 `hasWorkspace: boolean`——若调用方总是无条件构造 handle，`Boolean(handle)` 恒真，「看起来像守卫的守卫从没守过任何东西」。应当传**句柄本身**（`TaskWorkspaceHandle | undefined`），`undefined` 才是真的「没有」。守卫参数要传能真正为空的东西。
4. 模型幻觉调用被拿掉的工具（比如仍调 `read_image`）→ 注册表白名单返回 `Unknown tool: read_image`，模型可自纠。**不加特例映射**——「路由一旦按名字打补丁，就得为每一对『被谁接管』维护映射表」。

### 4.2 「启用 ≠ 可用」：单一判断函数

`subAgentModel(kind, models, subs)` 应当是可用性的唯一答案：

```ts
if (!cfg?.enabled || !cfg.modelId) return null;          // 开关 + 绑定
const model = models.find((m) => m.id === cfg.modelId);
if (!model) return null;                                  // 模型还在
if (kind === "vision" && model.type !== "multimodal") return null;          // kind 前置条件
if (kind === "search" && !model.serverTools?.includes("web_search")) return null;
return model;
```

`routeTools`、chips、`chainCanSeeImages`、`resolveVisionConn`——所有 surface 全走它。不这么做的代价不止是多一个死按钮：**routeTools 见到 search 被启用就会关掉主模型自己的联网**——若那个子代理其实不能上网，用户「既失去主模型的联网，又什么都没换回来」（参考实现 `routing.test.ts` 对这条有专门用例）。

### 4.3 连接解析：`resolveSubAgentConn`，无 fallback 链

子代理**不继承主模型连接**，独立解析：`subs[kind]` → 查 Model 行 → 查 Provider 行 → `loadKey(provider.id)` 取密钥。四步任何一步失败返回判别联合 `{ error: string }`，错误文案都是「告诉用户去哪儿修」的形态。

- **没有 fallback 链**——绑定失效就是 error，不会静默退回主模型。
- **陷阱：密钥缺失不得降级成空串。** `loadKey() ?? ""` 会发一个无钥请求，401 回来被包装成「子代理坏了」，而真正的修法是去粘一个 key（参考实现测试注释：「`?? ""` here produced a 401 the author had to reverse-engineer」）。密钥缺失是**配置错误**，应当在解析层就返回指路的 error（「去 Settings → Providers 粘 key」）。
- **依赖方向**：解析函数以**回调**形式注入 `ToolContext`（调用方 store 里构造 `(k) => resolveSubAgentConn(k, models, providers, subs, loadApiKey)`），不是让 lib 层读 store——避免 agent lib 成为 store 的下游。

### 4.4 直接 UI 动作走同一优先级

不经 agent 的直接 UI 动作（例：知识库词条的「AI 描述」按图生成）也应当是「vision 子代理可用就优先它，哪怕主模型自己也能看图」（参考实现 `resolveVisionConn`）。理由不是省事：`routeTools` 已在工具集层把图片工具从主模型手里拿走，若 UI 动作反过来优先主模型，**同一个开关在两处表示相反的事**——且对多模态主模型的用户，那个开关将永远无效。代价是多一跳，收益是「谁在这里读图」只有一个答案。

### 4.5 两个能力概念分立：`chainCanSeeImages` vs `multimodal`

- `chainCanSeeImages(mainModel, subs, models)`：主模型多模态 **或** 有可用 vision 子代理 ⇒ true。**只给 UI 灰显判断用。**
- `ToolContext.multimodal`：「能否把 base64 塞进**当前这个模型**的请求」。

**不变量：绝不用前者改后者的语义。** 改成「链路上有人能看图」会让纯文本主模型收到读不了的图片（烧 token 且可能被端点 400）。两个概念，两个名字，语义井水不犯河水。

配套（引用注入侧）：图片附件的 UI 入口按 `chainCanSeeImages` 放宽后，发不出去的图片改为**列出路径**，并在有 vision 子代理时把告示从道歉改成指令——「用 `delegate(kind:"vision", refs:[路径])` 让它读」。只给文件名时，「模型看得见缺了什么，却没有任何办法去取」。

---

## 5. 执行细节

### 5.1 复用同一个 runtime loop

子代理**就是一次嵌套的 `runAgent` 调用**——同一个函数、同一个 tool loop，换一份连接参数（ConnOptions）+ 换一个 preset + 全新 2 条消息的 history。前提是 runtime 天然可重入：`messages`/`signal`/`onEvent` 全由调用方传入，无模块级状态。**机制上不存在任何「子代理框架」**，子代理只是一个工具的执行器。

### 5.2 沙箱：四道闸

子跑的 `toolContext` 现场构造，只给最小字段集：

```ts
toolContext: {
  projectPath: ctx.projectPath,
  loreIndex: ctx.loreIndex,
  multimodal: conn.model.type === "multimodal",   // 子代理自己的能力，与主模型无关
  taskWorkspace: undefined,                        // 沙箱
  signal: ctx.signal,
},
```

| 约束 | 落实处 | 机制 |
|---|---|---|
| **深度 1（防递归）** | `SUB_PRESETS[kind].tools` 不含 `"delegate"` + 注册表按 `allowed` 白名单查表 | 双保险：不在名单直接 `Unknown tool` |
| **只读** | 不传 `requestApproval` / `requestPlanApproval` / `lorePlan` / `taskWorkspace` | 高危写工具缺审批通道自报错；计划门挡知识库写工具；工具集本身是第三道 |
| **零上下文渗透** | messages 只有 2 条，现场构造 | —— |
| **共享 signal** | `ctx.signal` 透传给 `runAgent`；`AbortError` 重抛不转 tool error | 用户点停止 ⇒ 子代理立即停，不后台烧钱 |

注意 `taskWorkspace: undefined` 的连带效果：子代理调不动任何 scratchpad 工具（它们都要求 `ctx.taskWorkspace`）——子代理的产出由 `executeDelegate` 代为落盘，它自己不直接写 note。

### 5.3 前置校验在 delegate 里做，零副作用

`executeDelegate` 应当在发任何请求前检查：

- ctx 四件套齐不齐（`taskWorkspace`/`signal`/`onNestedEvent`/`resolveSubAgent`，缺任一 → "this surface cannot run subagents"）；
- kind 合法、task 非空；
- 连接可解析；
- **kind 前置条件**：search 模型必须有 web_search、vision 模型必须 multimodal。

理由：绑错模型的子代理「要烧一整个往返才报告，而且报出来的形态是『子代理失败』而不是『配置不对』」。

**不变量：前置校验失败零副作用。** 参考实现 `delegateShape.test.ts` 断言拒绝时 `sent.length === 0`（没发请求）且文件系统为空（**没建工作区**）。

### 5.4 轮上限与收尾

- 子跑**不传 `onRoundLimit`**：撞上限就按默认行为最后一轮撤工具、强制成文，「不去打扰作者」。round-limit 交互卡片只属于主 run。
- `finishPolicy: "force-text"` 保证子跑总以文本结束；文本经 `onOutputText` 捕获（§2.3）。

### 5.5 事件冒泡与去重

- runtime 执行每个工具前把 `signal` 和 `onNestedEvent: opts.onEvent` 浅合并进 `ToolContext`，所以 delegate 拿到的 `onNestedEvent` 就是主 run 的 `onEvent`。
- delegate 转发子跑事件时打作用域标记：`onEvent: (e) => ctx.onNestedEvent!({ ...e, parentStep: call.id })`——**`parentStep` = 这次 delegate 工具调用的 toolCallId**。
- 事件类型用交叉类型加作用域字段：`AgentEvent = AgentEventScope & (成员联合)`——交叉类型分配到每个成员，不破坏 `kind` 判别收窄（事件联合没有公共基接口时给全体加字段的最小改法）。
- **陷阱：去重键必须带 `parentStep`。** tool-step 按 `parentStep + toolCallId + name`，reasoning 按 `parentStep + round`。否则子跑的 round-1 reasoning 会顶掉主 run 第 1 轮的 reasoning 行（子跑轮次也从 1 开始）。
- 日志 UI 从截断的参数摘要里抠字段（如 kind/task）应当用**正则不用 JSON.parse**：参数常被截断（参考实现截 400 字符），delegate 的 task 按设计是一整段话，JSON 常态性断在字符串中间 parse 不出来。

### 5.6 串行执行，无并发编排

机制上模型可以在一轮发多个 tool call，但 runtime 的工具执行循环应当 `for...of` **串行 await**——同轮多个 delegate 也是顺序执行。设计边界明说：**无子代理间通信、无并行编排、无递归。**

---

## 6. 测试应当锁定的契约（精选）

以下契约值得在新项目里写成回归测试（参考实现 `subagent.test.ts` / `routing.test.ts` / `delegateShape.test.ts`）：

**能力判断**
- `chainCanSeeImages`：vision 子代理绑 **text 模型 ⇒ false**（设置面板允许错误绑定存在，信标志位就会点亮图片控件然后把图发给读不了的模型）；主模型可为 undefined。
- `resolveVisionConn`：主模型自己是多模态时**仍优先子代理**；子代理绑 text 模型**穿透**回主模型；什么都不能看时返回**带原因的 error 而非 null**；密钥为 null 报「配置问题」而非发空钥请求吃 401。

**路由**
- 无子代理 ⇒ tools/serverTools 原样（默认 `final-round-off`）。
- workspace 为 undefined ⇒ **无 delegate**。
- 「启用≠可用」三连：search 绑不能上网的模型 ⇒ serverTools **不动**且无 delegate；vision 绑 text 模型 ⇒ read_image **留在**主模型手里；绑定的模型已删除 ⇒ 无 delegate。
- 会话覆盖关掉某 kind 后**路由随之回退**（联网还给主模型、图片工具还回来、delegate 消失）——composer 与 resolver 必须读同一份生效配置；覆盖只减不增（对本就 off 的 kind 是 no-op 不是 toggle）。

**delegate 形状**
- 工作区标题**不是**委托指令（命名归 task_plan）；note 文件名是文件名不是句子，完整指令作为 note 首行标题存活。
- 无 refs 时 user 消息**完全不含**「参考资源」小节；有 refs 时含路径。
- 前置校验失败 ⇒ 没发请求、没建工作区（零副作用）。
- 成功路径：usage 行的 model_id 是子代理的、task 打 `subagent:<kind>` 标签；tool result 含 note 路径与摘要；嵌套 run-done 事件带 `parentStep: call.id`；解析失败的 delegate 不发 run-done。

---

## 7. 「始终不做」边界清单

边界即设计。以下各项**有意不做**，新项目不应「顺手补上」：

- **子代理间通信**——总线就是 notes 目录，单向、经文件。
- **并行编排**——工具循环串行 await，同轮多个 delegate 顺序执行。
- **递归委托**——子代理工具集不含 delegate，注册表白名单双保险。
- **子代理写用户内容**——子代理只读 + 产出由执行器代写 note。
- **把「要花钱须审批」的动作塞进静默委托**（例：生图）——那会绕过审批卡。
- **自定义子代理种类 / 自定义 system prompt**——kind 是代码，配置只有「哪个模型、开不开」。
- **fallback 链**——绑定失效就是指路的 error，不静默退回主模型。
- **用工作区替代压缩，或用压缩替代工作区**——工作区管「查到什么、做到哪」（任务事实），压缩管「聊过什么」（对话），见 `10-context-management.md`。

---

## 本篇检查清单

- [ ] runtime 可重入（messages/signal/onEvent/onOutputText 全由调用方传入，无模块级状态），子代理只是「嵌套调一次 runAgent 的工具执行器」，没有独立框架。
- [ ] `delegate` schema 的 `task` description 明确写出「子代理看不到这段对话」；有/无 refs 是**两个**模板键；工具描述用领域中性词汇。
- [ ] 子代理产出经 `onOutputText` 回调捕获（不是翻 history）；落盘 note 后 tool result = 路径 + ≤800 字符摘要 + read_note 指引；空产出报错不建 note。
- [ ] `AbortError` 是唯一重抛的异常，其余全部转 `Error: ...` 前缀的 tool result。
- [ ] 沙箱四道闸齐全：白名单防递归、不传审批/计划门/工作区、两条现场消息、共享 signal。
- [ ] 前置校验（ctx 四件套、kind/task、连接、kind 前置条件）全部在 delegate 里做，失败时零副作用（无请求、无工作区目录）。
- [ ] 可用性判断只有一个函数 `subAgentModel`（开关 + 绑定 + 模型存在 + kind 前置条件），routeTools/chips/UI 动作/连接解析全走它；设置面板警告但不阻止，下游必须再验。
- [ ] `routeTools` 改的是工具集不是提示词：vision 接管删图片工具、search 接管关服务端搜索、delegate 依赖**真正可为 undefined** 的工作区句柄。
- [ ] 记账：每子跑一行独立 usage（model_id 是子代理的，task 打 `subagent:<kind>`）+ 一条带 `parentStep` 的嵌套 run-done；事件去重键带 `parentStep`。
- [ ] 「始终不做」清单（§7）逐条确认没有被「顺手实现」。
