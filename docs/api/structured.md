# 结构化输出：让模型只吐 JSON

> 边界见 [`README.md`](README.md)：只写协议事实。族的编号沿用
> [`landscape.md`](landscape.md)：① Chat Completions ② Responses ③ Google GenAI
> ④ Anthropic Messages。

约束输出有**四种强度**，从弱到强：

| # | 手段 | 保证什么 | 代价 |
| --- | --- | --- | --- |
| 0 | **只在 prompt 里描述** | 什么都不保证 | 免费，但要自己从散文里抠 JSON |
| 1 | **JSON 模式**（`json_object` / `responseMimeType`） | 输出是**合法 JSON** | 不保证**形状** |
| 2 | **JSON Schema 严格模式** | 合法且**符合 schema** | schema 要满足一堆限制，且不是每族都有 |
| 3 | **强制工具调用** | 同上，schema 即工具的 `parameters` | 与思考模式冲突（见 §4） |

## 1. 四族支持情况

| | ① Chat Completions | ② Responses | ③ Google GenAI | ④ Anthropic |
| --- | --- | --- | --- | --- |
| **JSON 模式** | `response_format:{type:"json_object"}` | `text.format` | `generationConfig.responseMimeType:"application/json"` | **无此参数**，发了是 400 |
| **Schema 严格模式** | `response_format:{type:"json_schema", json_schema:{name,schema,strict:true}}` | `text.format.type:"json_schema"` | `generationConfig.responseSchema` | 无 |
| **强制工具调用** | `tool_choice:{type:"function",function:{name}}` | 同形 | `functionCallingConfig.mode:"ANY"` | `tool_choice:{type:"tool",name}` |

**Anthropic 没有 JSON 模式**，只有工具调用一条路。给它发 `response_format`
会因为"未知顶层字段"直接 400 —— 这是跨族移植时最常见的一次踩坑。

## 2. `json_object` 的隐藏前置条件

**① 和它的兼容层都要求上下文里出现字面量 "json"。**

- OpenAI：未包含显式指令时"模型可能生成无限的空白字符流"，**API 在上下文中
  找不到 "JSON" 字符串时会抛出错误**。
- DeepSeek 说得更具体：*"用户传入的 system 或 user prompt 中必须含有 `json`
  字样，并给出希望模型输出的 JSON 格式的样例"*。

这条容易被忽略，因为**大多数 prompt 恰好会提到 JSON**，于是它看起来永远成立
——直到某次 prompt 改写把那个词删掉。任何允许用户/作者编辑 prompt 的系统都
不能把它当作既成事实。

**该前置条件只适用于 `json_object`，`json_schema` 不需要。**

## 3. `json_schema` 严格模式的 schema 限制（①）

`strict: true` 换来保证，代价是 schema 必须满足：

- **`additionalProperties` 必须为 `false`**
- **所有字段必须列入 `required`** —— 可选字段只能用"与 `null` 的联合类型"模拟
- 嵌套深度 ≤ 10 层，属性总数 ≤ 5000
- 所有属性名 / 定义名 / 枚举值的总长度 ≤ 120,000 字符，单个枚举 ≤ 1000 项

"所有字段必须 required" 这条对**天然有可选字段的领域模型很不友好**，是选它
还是选强制工具调用时的主要权衡点。

**DeepSeek 不支持 `json_schema`**，只有 `json_object`。所以在同一个协议族里，
"用 schema 严格模式"这件事对官方端点成立、对兼容端点不成立——一个无法从
协议族推断、只能逐端点确认的差异。

## 4. 强制工具调用与思考模式冲突

强制工具调用是**四族的官方端点都有**的 schema 强制手段，因此也是可移植性最好
的一种 —— 但"官方"这个限定词是必要的：**兼容层可能只实现 `auto`/`none`**，把
强制档整个砍掉（实例见 [`landscape.md`](landscape.md) §7 的 MiniMax ④ 族端点）。

它还与思考模式相冲：

- **Anthropic**：手动 thinking（`type:"enabled"`）下强制 `tool_choice` 会被拒。
- **① 的若干端点**：推理模型会返回形如 *"does not support tool_choice in
  thinking mode"* 的错误，或返回一个空的工具调用。

推论：**推理模型往往拿不到最强的那档约束**。一个健壮的实现需要"强制工具调用
失败 → 退回 JSON 模式"的降级路径，而**降级后的那条路仍应带上 JSON 模式的原生
参数**——否则恰恰是在最不容易吐干净 JSON 的模型上，退成了零约束的纯散文。

## 5. 其余实践要点

- **`max_tokens` 截断**：DeepSeek 明确提醒要合理设置，防止 JSON 字符串被中途
  截断。截断的表现是"解析失败"，与"模型不听话"难以区分——四族都会在结束原因
  里说明（`finish_reason:"length"` / `finishReason:"MAX_TOKENS"` /
  `stop_reason:"max_tokens"`），值得据此区分报错。
- **空 content**：DeepSeek 记录了一个已知问题——*"在使用 JSON Output 功能时，
  API 有概率会返回空的 content"*，建议改 prompt 缓解。
- **JSON 模式与工具循环互斥**：JSON 模式要求整个回复是一个 JSON 值，而工具
  调用需要模型发出工具消息。同一次请求不要既开 JSON 模式又给工具。
