# 03 · 思考/推理的统一处理

> 本篇解决的问题：把各家"thinking / reasoning"支持拆解成三件可以独立设计的事——**强度**（请求怎么说"想多久"）、**思维链取回**（响应怎么给你看）、**回传义务**（下一轮要不要还回去），并给出每一件的三族实现规范。
> 不读会踩的坑：回传义务是唯一会让请求被拒的一件，却最少被文档放在显眼处——Anthropic 不回传 thinking block 是**静默**关闭思考（无任何报错）；Gemini 丢 thoughtSignature 是 HTTP 200 + 特殊 finishReason；DeepSeek 系不回传直接 400。三种失败模式完全不同，排查方式也不同。另外：`<think>` 标签混进正文、`display` 默认 omitted 付全额思考费拿不到一个字、换模型不剥 thinking block 静默计费。

出处：simple-ai-writer `src/lib/ai/reasoning.ts`（词汇、翻译表、切分器）、三个适配器的接线、设计文档 `docs/api/reasoning-plan.md` / `docs/api/anthropic-plan.md` / `docs/api/gemini-plan.md`。

---

## 1. 三分法：强度 / 取回 / 回传义务

规范的第一条是概念拆分。三件事各自独立变化，混在一个"thinking 开关"里必然顾此失彼：

| | 问题 | 谁定义 | 失败方式 |
| --- | --- | --- | --- |
| 强度 | 请求体里怎么表达"想多久" | 每族一套字段与枚举 | 发了对面不认的档位 → 400 |
| 取回 | 思维链在响应流的哪里 | 每族一个读取位置 | 读不到（少看一段），或混进正文（严重） |
| 回传义务 | 工具轮历史要不要携带思考物 | 每族一种载体 | **三族三种**：400 / 特殊 finishReason / 静默降级 |

## 2. 强度：自有六档词汇 + 每族翻译表

```text
ReasoningEffort = default | off | low | medium | high | max
```

核心原则：**配置层存储的是本项目自己的词汇，绝不让某一家的拼写进配置层。** 各家档位名"像但语义不像"是陷阱：DeepSeek 的 medium 被折进 high；`minimal`/`none` 有的模型 400；Gemini 要 token 预算/level 不要档位名。

`"default"`/缺省的语义是 **一个字段都不发**，让端点用自己的默认——"任何主动发出的字段都是某个中继可以拒绝的字段"。

翻译表（`reasoningBody(standard, effort, dialect)`）：

| 本项目档位 | ① OpenAI 系 `reasoning_effort` | ③ Gemini `generationConfig.thinkingConfig.thinkingLevel` | ④ Anthropic `output_config.effort` |
| --- | --- | --- | --- |
| off | `"none"` | `"MINIMAL"`（③ 关不掉，诚实降级为"最少"） | `"low"`（disabled 会被多款模型 400，官方也建议降 effort 而非关） |
| low/medium/high | 同名 | `LOW/MEDIUM/HIGH`（**全大写**！小写 `thinking_level` 属于另一个 surface：Interactions API） | 同名 |
| max | `"max"` | `"HIGH"`（枚举到头） | `"max"` |

必须写进实现的细节：

- ③ 发 level 时**强制搭配 `includeThoughts: true`**——思考横竖在跑、横竖计费，这个开关只决定你能不能看见；只调深度不开显示等于"付钱买看不见的思考"。
- ③ 的旧字段 `thinkingBudget` 与新字段 `thinkingLevel` 并存于同一对象，靠"用错模型报错"区分。规则：**只发一代字段**，选目标支持范围对应的那代（参考实现支持 Gemini 3 起，只发 level）。
- ④ 的 `output_config.effort` 管的是**整个回复**（正文 + 工具调用 + 思考），不只思考深度。UI 上仍然只放一个拨盘，变的是标签——因为没有任何端点把"回复深度"与"思考深度"作为两个独立输入暴露，两个拨盘 = 两个控件写一个值。
- **① 的 off = `"none"` 不是全族通用的关闭**：DeepSeek 的档位表没有 `none`，发了被无视、照想照计费，只有顶层 `thinking:{type:"disabled"}` 关得掉【文档 2026-08；Joycai 2026-09-05 按文档修复，未实测】；GLM 各代见 §3.1，火山方舟见 §3.2（在那里 `none` 实测关得掉）。所以「关」是按厂商声明的方言，不是一个族级常量。
- 私有方言开关（DeepSeek 的 `thinking:{type}`、千问的 `enable_thinking`）**默认不发**——OpenAI 官方端点对未知顶层字段直接拒绝，为一家的方言破坏官方路径不值。唯一的例外是作者在模型上**声明了 `switch` 方言**（见 §3）：那时该字段就是这个端点的思考词汇，改发它并停发 `reasoning_effort`。未声明方言的默认路径必须一个字节不变。

## 3. ThinkingDialect：代次差异由作者声明，不猜

思考参数**换代改形、换厂改拼**，且**代次无法从模型 id 恢复**——中继上模型 id 是作者输入的自由文本（如 `特价kiro | claude-opus-4-6-thinking`）。因此方言做成 **L3 模型字段由作者声明**，不做探测、不做猜测启发式。

关键的建模决定：**方言值是跨族的"参数形状"词汇，族决定拼法**。`extended` 同时描述 Claude ≤4.5 与 Gemini 2.5；`switch` 同时描述 MiniMax-M3 的 ④ 族端点与千问 DashScope 的 ① 族端点——写侧函数先按族分派、再看方言，同一个值在不同族拼出不同字段。这让"支持下一家的开关型端点"不需要新增枚举值、不动 parse 白名单、不动存储列：

ThinkingDialect = `adaptive | extended | switch | none`，各族发出的 body 片段：

| 方言 | ④ Anthropic 发出 | ① OpenAI 系发出 |
| --- | --- | --- |
| `adaptive` | `{"thinking":{"type":"adaptive","display":"summarized"}}` | `{"reasoning_effort": …}` |
| `extended` | `{"thinking":{"type":"enabled","budget_tokens":N,"display":"summarized"}}` | `{"reasoning_effort": …}` |
| `switch` | 关：`{"thinking":{"type":"disabled"}}`；其余：`{"thinking":{"type":"adaptive"}}` | `{"enable_thinking": effort ≠ off}`，**且不发** `reasoning_effort` |
| `none` / 未声明 | 不发 `thinking` | `{"reasoning_effort": …}`，与未引入方言时逐字节相同 |

四种方言的语义：

- **`adaptive`**（Claude 4.6+）：`display:"summarized"` **必须显式发**——当前代默认 `"omitted"`，返回的 thinking block 文本为空串但**照全额计费**（omitted 省的是延迟不是钱）。
- **`extended`**（Claude ≤4.5；Gemini 2.5 同形）：固定 token 预算。预算钳制：`Math.max(1024, Math.min(16384, maxTokens/2))`——budget 必须 < max_tokens（二者共享一个上限，预算贴顶 = 正文没地方存在）。
- **`switch`**（为"只有纯开关"的端点建，每族一种拼法）：声明此方言同时意味着"该端点没有深度拨盘"——effort 唯一的用途是区分「关」与「其余」（其余一律开）。两个真实样本：
  - **④ 族拼法**（MiniMax-M3 的 `/anthropic/v1/messages`）：只有 `{type:"adaptive"|"disabled"}`，无 `display`、无 `output_config`——`reasoningBody` 对它返回 undefined。schema 没有的字段（如 display）不发——兼容层"忽略未知键"与"400 未知键"一样常见，文档没写的不发。
  - **① 族拼法**（千问 DashScope compatible-mode）：顶层 `enable_thinking: bool`（官方 SDK 示例写在 `extra_body`，那只是 OpenAI SDK 的透传机制——落到 wire 就是 body 顶层字段）。声明后**停发 `reasoning_effort`**：千问文档写明它与 `thinking_budget` 互斥，且"声明 switch"本身就是"此端点没有深度档"的陈述。`thinking_budget` 刻意不接——没有 UI 载体的字段只会变成噪音（与 ③ 的 thinkingBudget 同一判断）。另一条联动：千问文档明载**思考开启时 `tool_choice` 只接受 `auto|none`**，forced 的降级条件见 04 篇 §4。
  - 两个样本共同的动机：这些端点上思考对相当一部分模型**默认关**（MiniMax-M3 全部；千问的 Qwen3-Max/Plus 等商业款——Qwen3.5+/3.7+ 则默认开），不发开关就永不思考。千问的附加事实：新款 Qwen3.7+ 直接接受标准 `reasoning_effort`（与 budget 互斥），**不必声明方言**；部分开源模型思考模式强制 `stream: true`。同一端点、两代模型、两套控制字段——"默认值要按模型代问"的又一实例。
- **`none`**：不发任何 thinking 字段。

**缺省方言的猜测规则**：anthropic 族猜 `adaptive`，其他族 `none`。乐观猜的理由：对支持范围（4.6+）全对；错的方式是旧模型 400 且报出字段名——比默认"不思考"让作者纳闷"我的推理模型怎么从不推理"好得多。原则：**乐观猜测只在"错的方式会响"时使用**。注意 ① 族的缺省语义不是"不发"：openai 分支对未声明方言的模型照走标准 `reasoning_effort` 路径——所以 ① 族适配器把**作者声明的原值**传给写侧函数即可，不要先过缺省替换。

### 3.1 一家三代三种控制：智谱 GLM（2026-09-19 实测全部 11 款）

同一个 ① 族端点、同一家的模型，思考控制分三种，而且三种都**默认开**。按族默认发 `reasoning_effort` 在每一代上都错：

| 代 | 关 | 深度 | 陷阱 |
| --- | --- | --- | --- |
| glm-5.3 / 5.3-flash / 5.3-flashx | **不能关**：`thinking:{type:"disabled"}` 400 | `reasoning_effort` 只收 `low/high/max`，真分档（同一道题 ~30 / 50 / ~120 推理 token） | 其余值（含 `none`、`medium`）400，文案一律是「不支持关闭思考」，不指向出错的值 |
| glm-5.2 | `thinking:{type:"disabled"}` | 七值都收（乱写 400）；`low/medium` 折成 high、`xhigh` 折成 max——实有两档，`max` 多想 ~35% | **`reasoning_effort:"none"` 关不掉**（与 `low` 想得一样多），文档却说 none 放弃思考 |
| glm-4.5 / 4.5-air / 4.6 / 4.7 / 5 / 5-turbo / 5.1 | `thinking:{type:"disabled"}` | **没有**：`reasoning_effort` 任何值（含乱写的）都 200、照常思考——静默丢弃 | 给这几款一个档位菜单 = 三个效果完全相同的假控件 |

- 开关字段是**顶层** `thinking:{type:"enabled"|"disabled"}`（与 DeepSeek 同形）；`reasoning_effort:"high"` 与 `disabled` 同发**不报错**（豆包会 400）。
- 另有 `thinking.clear_thinking`（默认 `true`，丢弃历史轮的 `reasoning_content`）；`false` = 「保留式思考」，要求跨轮原样回传全部历史推理，
  厂商推荐 5.3-flash 用 `false`。缺 `type` 只发 `{clear_thinking:false}` 在智谱自家端点 200（经千问转发时在非 GLM 模型上 400）。
- 推理从 `reasoning_content` 流出；工具轮回传被接受（交错思考，文档要求回传）。`usage.completion_tokens_details.reasoning_tokens`
  4.5-air 从不给，glm-5 / 4.6 / 4.5 关思考时缺席（不是 0）。
- **同一个模型换一个面，默认值就变**：glm-4.7 在 ④ `/api/anthropic` 上默认**不**思考（只回 text 块），在 ① 上默认思考——
  「默认值要按模型 × 面问」（第 1 篇 §8）。
- 对实现的推论：参数形状由「模型 id → 控制方式」查表预填（关不掉 / 关 + 两档 / 只有开关三类），作者可改；
  「开关」类在未设置时应显示为**开**，因为不发字段 = 端点默认在想。

### 3.2 火山方舟对话（豆包 Seed）：① 的 `reasoning_effort` 就是开关，别家的开关被静默无视（2026-09-18 实测）

来源：Joycai Image AI Toolkits，订阅套餐 base `…/api/plan/v3/chat/completions`，`doubao-seed-2.0-pro` 与别名 `ark-code-latest` 结果一致；
经应用的 dispatcher 真发一遍复核（默认 66、关 0、低 68、最高 145 个 reasoning token）。

| 发送 | `usage…reasoning_tokens` |
| --- | --- |
| 不发（默认） | 60–67（默认在想） |
| `reasoning_effort:"none"` / `"minimal"` | **0** |
| `"low"` / `"medium"` / `"high"` / `"max"` / `"xhigh"` | 60–145（真分档） |
| `thinking:{type:"disabled"}` | 0 |
| `thinking:{type:"enabled"}` | 66 |
| `thinking:{type:"auto"}` | `400 InvalidParameter`（本模型不支持 auto） |
| `thinking:disabled` + `reasoning_effort:"high"` | `400`（组合非法；GLM 同发不报错，§3.1） |
| `thinking:enabled` + `reasoning_effort:"none"` | 0（effort 说了算） |
| `enable_thinking:false`（千问的拼法） | **照想**——未知字段静默忽略，不报错（坑 114） |

- 推论：方舟**不需要声明任何方言**，① 的默认写法（关 = `"none"`）就关得掉。反过来，把为千问声明的 `switch` 方言挂到方舟模型上，
  「关」不报错、只是失效——方言按厂商声明，不能因为「都是 ① 兼容」就复用。
- 回包 `message` 里除 `reasoning_content` 外还有 `encrypted_content`（加密推理）；Joycai 不读也不回传，多轮未见报错，是否影响质量未测。
- 套餐 base 上服务的对话模型：`doubao-seed-2.0-pro`、`ark-code-latest` 可用；`doubao-seed-1-6-250615`、`doubao-seed-1.6`、`doubao-seed-code`
  回 `404 UnsupportedModel`（「does not support the agent plan feature」）。`max_tokens` 照收。

## 4. 思维链的流式暴露：三族三种读法，统一产出 `{reasoning}` chunk

| 族 | 读哪里 |
| --- | --- |
| ① | `delta.reasoning_content` / `delta.reasoning`（候选字段表 `REASONING_CONTENT_FIELDS`，按序试；**非字符串值忽略不强转**——有端点在旁边发结构化 `reasoning_details` 数组，`String()` 会给用户看 `[object Object]`）+ 内联 `<think>` 切分（见 §6） |
| ③ | `part.thought === true` 的文本 part |
| ④ | `thinking_delta.thinking` 事件（仅当请求发了 `display:"summarized"` 才会有） |

**候选字段按「有非空文本」取，不按「字段存在」取**：有中转同时发 `reasoning_content:""` 与非空的 `reasoning`，`a ?? b` 式的取法拿到空串——思考文本丢失，且回传时记住了错误的字段名【实测 2026-09-14，中转流量；坑 107】。按序试，第一个非空字符串连同它的字段名一起留下。

扩展规则：支持一家新端点的思维链拼写 = 往 `REASONING_CONTENT_FIELDS` 加一个字符串。**刻意设计成永远不会变成 per-vendor 分支**——候选字段表是数据，分支是代码。

产出侧统一为 `{reasoning: string}` chunk（与 `{text}` 是不同变体，见第 1 篇）：思维链绝不能混进正文流。

## 5. 回传义务：三族三种载体、三种失败模式

**心法：跨轮要回传的东西必须整块留存原物，不能归一化后重建。**"理解后重建"恰好丢掉的就是完整性校验依赖的那部分（signature、encrypted payload、字段拼写、块顺序）。

| 族 | 不回传的后果 | 载体 |
| --- | --- | --- |
| ① DeepSeek 系 | **400**（会响，逼你修） | `_reasoning: {field, text}`——收到什么字段名就用什么名字还回去，无需知道对面是谁 |
| ③ Gemini | 多轮工具失效；HTTP 200 + `finishReason: MISSING_THOUGHT_SIGNATURE`（第三种形态：不是 400 也不是静默） | `_geminiModelParts: unknown[]`——整组原始 parts 原样回传（含 thought parts 与 thoughtSignature） |
| ④ Anthropic | **静默降级**：API 不报错，直接关掉这轮思考（最危险——唯一验证手段是看响应里还有没有 thinking block）；**改动/重排/部分丢弃才是 400** | `_thinkingBlocks: {modelId, blocks}`——有序块数组原样回传（`redacted_thinking` 只有不透明 data 也要回） |

实现规则：

1. **只在带 tool_calls 的 assistant 消息上携带**（三个载体一致）：这些端点把"调用工具前的思考"视为同一条回复的一部分（工具调用是模型暂停自己回复的构造，去等外部信息）；普通轮次端点自己会过滤，带上 = 白付 token。

   ⚠️ **DeepSeek 的回传义务是分场景的，两个方向都会 400，别只记住一半**：
   - **有工具调用的轮次**：该轮 assistant 消息的 `reasoning_content` **必须回传**——官方文档原文"若您的代码中未正确回传 `reasoning_content`，API 会返回 400 报错"。
   - **没有工具调用的轮次**：**不要携带**——官方文档（另一处，历史更久）规定输入 messages 含 `reasoning_content` 直接 400（新版端点部分改为忽略，但不可依赖）。
   本条"只在带 tool_calls 的消息上携带"的规则**同时满足两侧约束**，这正是它的由来。诊断线索：多轮工具调用第二轮 400 → 缺回传；400 body 出现 "reasoning_content is not allowed in the input messages" → 无工具轮误携带。两种症状同一条规则修复。
2. **`_thinkingBlocks` 带 `modelId`**：thinking block 与产出它的模型绑定。允许会话中途换模型的应用，换了就整组丢弃（`thinkingBlocksFor` 比对 modelId）——别的模型不会拒绝，会**静默忽略且照 input 计费**，最坏的组合。
3. **三个 `_` 字段并存是刻意选择，不要泛化承载**：④ 的载体是有序数组、成员可能只有不透明 payload、顺序受完整性校验，无法复用 `{field,text}`；泛化载体会把 modelId 特例变成所有人的负担。真正泛化的是**剥除**（`_` 前缀丢弃，见第 1 篇），不是承载。
4. **`redacted_thinking` 块必须回传**：它只有不透明 `data` 字段。按 `type === "thinking"` 过滤内容块的代码会静默丢掉它——过滤条件应当是"是思考类块"而不是精确类型匹配。

## 6. `<think>` 标签兜底切分器

部分 ① 族中继（MiniMax 等）不分离思维链，直接把 `<think>…</think>\n\n正文` 塞进 `delta.content`。不切分则思考散文会进用户稿子。

出处：simple-ai-writer `src/lib/ai/reasoning.ts` 的 `createThinkTagSplitter()`。状态机三阶段（start / thinking / body），两条安全性质是规范的核心：

1. **只认响应最开头的 `<think>`**（允许前导空白）。正文中途出现的 `<think>` 视为作者/模型自己的文本。理由：对内容生产类应用，静默吃掉一段正文比留一个标签在稿子里严重得多——切分器宁可漏切不可误切。
2. **跨 chunk 标签拼接**：`<thi` + `nk>` 分两片到达是常态。用 `danglingPrefix`（缓冲区尾部"是标签真前缀的最长后缀"）扣住可能成为标签的尾巴不发；下一片到达后拼接再判。流结束时未闭合的块按 reasoning flush——被截断的思考不是作者要的散文。

第三条规则：**切出来的 reasoning 只展示、不并入 `_reasoning` 回传**——它没有自己的 wire 字段名，编一个名字 = 往下一个请求塞没人认识的键。

## 7. ② Responses 族：强度 / 取回 / 回传

出处：simple-ai-writer `src/lib/ai/reasoning.ts`（思考类目 `responses-effort`）、`src/lib/ai/responses.ts`；事实见 `docs/api/responses.md` §2.1、§5、§10 与 `landscape.md` 第十一个样本。

### 7.1 强度：嵌套对象，复用 ① 族词表

| 本项目档位 | ② wire |
| --- | --- |
| default / 未设 | 一个字段都不发（各模型默认不同：5.4 `none`，5.5/5.6 `medium`，Grok 4.5/4.6 `high`——"未设"不能拼成其中任何一个） |
| off | `reasoning: { effort: "none" }`（无 summary） |
| low / medium / high / xhigh / max | `reasoning: { effort: <同名>, summary: "auto" }` |

- 端点枚举是 `none/minimal/low/medium/high/xhigh/max` 七档，菜单取其中六档（去掉 `minimal`）。
- **`summary: "auto"` 随非 off 档位一起发**：不发就没有任何摘要事件（与 Gemini 的 `includeThoughts` 同理——付了思考钱却看不见）；`auto` 回显 `detailed`。
- **按模型的上限不同，但菜单不按型号裁剪**：GPT-5.4 到 `xhigh`（`max` → 400 且报文列出合法值）；5.5 / 5.6 收 `max`；Grok 4.5/4.6 **拒 `none`**、全系拒 `max`。越界 400 就是端点自己的声明——按 id 猜上限会在中转站别名、新型号上错；这与 ① 族各类目一致。代价要写进 UI 提示：Grok 4.5/4.6 上「关闭」芯片必然 400，而这两款本来就关不掉思考。
- `reasoning.mode:"pro"`、`reasoning.context` 不接：前者两台中转站都回显 `standard`、无从确认生效；后者默认 `all_turns` 恰是回传想要的效果。

### 7.2 取回

`response.reasoning_summary_text.delta` 与 `response.reasoning_text.delta` 都产出 `{reasoning}` chunk（后者在 GPT-5.x 上从未出现，千问的 Responses 面文档里有）。模型没真推理（`reasoning_tokens: 0`）时即使发了 summary 也没有 reasoning 条目——同一请求可能一次有一次没有，不是 bug。

### 7.3 回传

载体是 `_responseItems: {modelId, items}`（第 2 篇 §7.3）：reasoning 条目连同 **`encrypted_content` 原样**放回 `input`，不解释内容。事实边界：

- OpenAI（经中转站）：`store:false` 时 reasoning 条目自带 `encrypted_content`，不需要 `include`。
- xAI：**必须**发 `include:["reasoning.encrypted_content"]` 才有；不带它回传第二轮照样 200——缺的只是推理延续。
- 千问 Responses 面：没有 `encrypted_content`，回传的是明文 `summary`。

所以载体设计成"不解释、整组带回"才能同时装下三家；回传缺失在此族**不报错**，与 ④ 族一样只能靠日志对照验证。官方端点不发 `include` 是否丢加密推理**未经官方 key 验证**，参考实现暂不发。

---

## 本篇检查清单

- [ ] 思考支持在设计文档里拆成了强度/取回/回传三节，各自有三族对照。
- [ ] 配置层存自有六档词汇（含 `default`/`off`/`max`），任何一家的拼写都没有进入存储。
- [ ] `default` 档一个字段都不发。
- [ ] Gemini 翻译用全大写 `thinkingLevel` 枚举，且发 level 必带 `includeThoughts: true`；只发一代字段。
- [ ] Anthropic `off` 翻译为降 effort 而不是 disabled。
- [ ] `ThinkingDialect` 是作者声明的 L3 字段，没有任何"从模型 id 猜代次"的启发式。
- [ ] `adaptive`/`extended` 恒发 `display:"summarized"`；`switch` 方言不发 display。
- [ ] `extended` 的 budget 钳在 `[1024, min(16384, maxTokens/2)]`。
- [ ] 缺省方言的猜测方向满足"错的方式会响"。
- [ ] ① 族的 `switch` 方言发 `enable_thinking` 且**停发** `reasoning_effort`（互斥）；未声明方言的请求与实现前逐字节相同。
- [ ] 方言选择 UI 的选项**按族给**：给 ① 族显示 `adaptive`/`extended` 是"按了没反应的控件"（写侧对它们无映射）。
- [ ] ① 族思维链读取走 `REASONING_CONTENT_FIELDS` 候选表；非字符串值忽略不强转；新拼写 = 表加一项。
- [ ] 三个回传载体（`_reasoning` / `_geminiModelParts` / `_thinkingBlocks`）只挂在带 tool_calls 的 assistant 消息上。
- [ ] `_thinkingBlocks` 带 modelId，换模型整组丢弃。
- [ ] `redacted_thinking` 不会被内容过滤丢掉。
- [ ] `<think>` 切分器只认响应开头、有 danglingPrefix 跨片处理、流末未闭合按 reasoning flush。
- [ ] 切分出的 reasoning 不进回传载体。
- [ ] 有一条验证手段确认 Anthropic 多轮工具会话中 thinking block 仍然出现（静默降级的唯一判据）。
- [ ] ② 族：`reasoning:{effort, summary:"auto"}`，off → `{effort:"none"}`，default 不发；菜单不按型号裁剪，越界交给端点 400，UI 提示写明 Grok 4.5/4.6 关不掉思考。
- [ ] ② 族 `reasoning_summary_text.delta` 与 `reasoning_text.delta` 都进 `{reasoning}`；无 reasoning 条目不当错误。
- [ ] ② 族回传的 reasoning 条目（含 `encrypted_content`）原样整组带回，载体带 modelId。
