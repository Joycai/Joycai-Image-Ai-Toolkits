# 03 · 思考/推理的统一处理

> 本篇解决的问题：把各家"thinking / reasoning"支持拆解成三件可以独立设计的事——**强度**（请求怎么说"想多久"）、**思维链取回**（响应怎么给你看）、**回传义务**（下一轮要不要还回去），并给出每一件的三族实现规范。
> 不读会踩的坑：回传义务是唯一会让请求被拒的一件，却最少被文档放在显眼处——Anthropic 不回传 thinking block 是**静默**关闭思考（无任何报错）；Gemini 丢 thoughtSignature 是 HTTP 200 + 特殊 finishReason；DeepSeek 系不回传直接 400。三种失败模式完全不同，排查方式也不同。另外：`<think>` 标签混进正文、`display` 默认 omitted 付全额思考费拿不到一个字、换模型不剥 thinking block 静默计费。

参考实现：simple-ai-writer `src/lib/ai/reasoning.ts`（词汇、翻译表、切分器）、三个适配器的接线、设计文档 `docs/reasoning-plan.md` / `docs/anthropic-plan.md` / `docs/gemini-plan.md`。

---

## 1. 三分法：强度 / 取回 / 回传义务

规范的第一条是概念拆分。三件事各自独立变化，混在一个"thinking 开关"里必然顾此失彼：

| | 问题 | 谁定义 | 失败方式 |
| --- | --- | --- | --- |
| 强度 | 请求体里怎么表达"想多久" | 每族一套字段与枚举 | 发了对面不认的档位 → 400 |
| 取回 | 思维链在响应流的哪里 | 每族一个读取位置 | 读不到（少看一段），或混进正文（严重） |
| 回传义务 | 工具轮历史要不要携带思考物 | 每族一种载体 | **三族三种**：400 / 特殊 finishReason / 静默降级 |

## 2. 强度：自有六档词汇 + 每族翻译表

```ts
// 参考实现：simple-ai-writer src/lib/ai/reasoning.ts
export type ReasoningEffort = "default" | "off" | "low" | "medium" | "high" | "max";
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
- 私有方言开关（如 DeepSeek 的 `thinking:{type}`）**故意不发**——OpenAI 官方端点对未知顶层字段直接拒绝，为一家的方言破坏官方路径不值。

## 3. ThinkingDialect：代次差异由作者声明，不猜

④ 族（形状上也覆盖 ③ 2.5 代）的思考参数**换代改形**，且**代次无法从模型 id 恢复**——中继上模型 id 是作者输入的自由文本（如 `特价kiro | claude-opus-4-6-thinking`）。因此方言做成 **L3 模型字段由作者声明**，不做探测、不做猜测启发式：

```ts
// 参考实现：simple-ai-writer src/lib/ai/reasoning.ts
export type ThinkingDialect = "adaptive" | "extended" | "switch" | "none";

export function thinkingBody(dialect, budgetTokens, effort?) {
  switch (dialect) {
    case "adaptive": return { thinking: { type: "adaptive", display: "summarized" } };
    case "extended": return { thinking: { type: "enabled", budget_tokens: budgetTokens, display: "summarized" } };
    case "switch":   return { thinking: { type: effort === "off" ? "disabled" : "adaptive" } };
    case "none":     return undefined;
  }
}
```

四种方言的语义：

- **`adaptive`**（Claude 4.6+）：`display:"summarized"` **必须显式发**——当前代默认 `"omitted"`，返回的 thinking block 文本为空串但**照全额计费**（omitted 省的是延迟不是钱）。
- **`extended`**（Claude ≤4.5；Gemini 2.5 同形）：固定 token 预算。预算钳制：`Math.max(1024, Math.min(16384, maxTokens/2))`——budget 必须 < max_tokens（二者共享一个上限，预算贴顶 = 正文没地方存在）。
- **`switch`**（为 MiniMax-M3 的 `/anthropic/v1/messages` 这类精简兼容层建）：只有 `{type:"adaptive"|"disabled"}` 开关，无 `display`、无 `output_config`。声明此方言同时意味着"该端点没有深度拨盘"——`reasoningBody` 对它返回 undefined，effort 唯一的用途是 off→disabled。该端点思考**默认关**，不发开关就永不思考。另注意：schema 没有的字段（如 display）不发——兼容层"忽略未知键"与"400 未知键"一样常见，文档没写的不发。
- **`none`**：不发任何 thinking 字段。

**缺省方言的猜测规则**：anthropic 族猜 `adaptive`，其他族 `none`。乐观猜的理由：对支持范围（4.6+）全对；错的方式是旧模型 400 且报出字段名——比默认"不思考"让作者纳闷"我的推理模型怎么从不推理"好得多。原则：**乐观猜测只在"错的方式会响"时使用**。

## 4. 思维链的流式暴露：三族三种读法，统一产出 `{reasoning}` chunk

| 族 | 读哪里 |
| --- | --- |
| ① | `delta.reasoning_content` / `delta.reasoning`（候选字段表 `REASONING_CONTENT_FIELDS`，按序试；**非字符串值忽略不强转**——有端点在旁边发结构化 `reasoning_details` 数组，`String()` 会给用户看 `[object Object]`）+ 内联 `<think>` 切分（见 §6） |
| ③ | `part.thought === true` 的文本 part |
| ④ | `thinking_delta.thinking` 事件（仅当请求发了 `display:"summarized"` 才会有） |

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
2. **`_thinkingBlocks` 带 `modelId`**：thinking block 与产出它的模型绑定。允许会话中途换模型的应用，换了就整组丢弃（`thinkingBlocksFor` 比对 modelId）——别的模型不会拒绝，会**静默忽略且照 input 计费**，最坏的组合。
3. **三个 `_` 字段并存是刻意选择，不要泛化承载**：④ 的载体是有序数组、成员可能只有不透明 payload、顺序受完整性校验，无法复用 `{field,text}`；泛化载体会把 modelId 特例变成所有人的负担。真正泛化的是**剥除**（`_` 前缀丢弃，见第 1 篇），不是承载。
4. **`redacted_thinking` 块必须回传**：它只有不透明 `data` 字段。按 `type === "thinking"` 过滤内容块的代码会静默丢掉它——过滤条件应当是"是思考类块"而不是精确类型匹配。

## 6. `<think>` 标签兜底切分器

部分 ① 族中继（MiniMax 等）不分离思维链，直接把 `<think>…</think>\n\n正文` 塞进 `delta.content`。不切分则思考散文会进用户稿子。

参考实现：simple-ai-writer `src/lib/ai/reasoning.ts` 的 `createThinkTagSplitter()`。状态机三阶段（start / thinking / body），两条安全性质是规范的核心：

1. **只认响应最开头的 `<think>`**（允许前导空白）。正文中途出现的 `<think>` 视为作者/模型自己的文本。理由：对内容生产类应用，静默吃掉一段正文比留一个标签在稿子里严重得多——切分器宁可漏切不可误切。
2. **跨 chunk 标签拼接**：`<thi` + `nk>` 分两片到达是常态。用 `danglingPrefix`（缓冲区尾部"是标签真前缀的最长后缀"）扣住可能成为标签的尾巴不发；下一片到达后拼接再判。流结束时未闭合的块按 reasoning flush——被截断的思考不是作者要的散文。

第三条规则：**切出来的 reasoning 只展示、不并入 `_reasoning` 回传**——它没有自己的 wire 字段名，编一个名字 = 往下一个请求塞没人认识的键。

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
- [ ] ① 族思维链读取走 `REASONING_CONTENT_FIELDS` 候选表；非字符串值忽略不强转；新拼写 = 表加一项。
- [ ] 三个回传载体（`_reasoning` / `_geminiModelParts` / `_thinkingBlocks`）只挂在带 tool_calls 的 assistant 消息上。
- [ ] `_thinkingBlocks` 带 modelId，换模型整组丢弃。
- [ ] `redacted_thinking` 不会被内容过滤丢掉。
- [ ] `<think>` 切分器只认响应开头、有 danglingPrefix 跨片处理、流末未闭合按 reasoning flush。
- [ ] 切分出的 reasoning 不进回传载体。
- [ ] 有一条验证手段确认 Anthropic 多轮工具会话中 thinking block 仍然出现（静默降级的唯一判据）。
