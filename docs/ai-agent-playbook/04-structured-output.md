# 04 · 结构化输出与降级链

> 本篇解决的问题：让"要求模型输出一个符合 schema 的 JSON"在四个协议族、官方与兼容端点、思考型与非思考型模型上都能拿到可解析的结果——靠一条明确的降级链，而不是祈祷。
> 不读会踩的坑：把 `response_format` 发给 Anthropic 硬 400；OpenAI `json_object` 在 prompt 不含 "JSON" 字面量时报错或输出无限空白流；用裸子串 "does not support" 判定回退，把无关的上游错误也吞进回退——翻倍花钱 + 掩盖真实错误；回退路径退成零约束纯散文，恰好落在最不容易吐干净 JSON 的思考型模型上。

参考实现：simple-ai-writer `src/lib/ai/jsonMode.ts`、`src/lib/ai/json.ts`、`src/lib/agent/structured.ts`。

---

## 1. 四种强度与本方案的两级组合

结构化输出手段按约束强度排序：

```
prompt 描述  <  JSON mode  <  json_schema 严格模式  <  强制工具调用
```

规范采用**两级组合**：**首选强制 pseudo-tool（schema 即工具 parameters），失败退回 JSON mode + 提示词**。

为什么不用 `json_schema` 严格模式：

- schema 要求 `additionalProperties: false` + 全字段 required，对天然有可选字段的领域模型不友好；
- DeepSeek 等兼容层不支持；支持的也常按模型代砍（千问 DashScope 只有最新两三代商业款支持，`json_object` 却全线可用）；
- 强制工具调用是四族官方都有的机制，**可移植性最好的 schema 手段**。

## 2. JSON mode 的每族形状：jsonModeShaping

JSON mode 的开启方式三族三样，必须收口在一个函数里，返回 `{ extraBody?, cue? }`：

```ts
// 参考实现：simple-ai-writer src/lib/ai/jsonMode.ts
case "gemini":    // responseMimeType + cue 双保险（有模型静默无视 mimeType）
  return { extraBody: { generationConfig: { responseMimeType: "application/json" } },
           cue: JSON_ONLY_CUE };
case "anthropic": // 无此参数，发 response_format 是硬 400 —— cue 是全部机制
  return { cue: JSON_ONLY_CUE };
default:          // OpenAI 系
  return { extraBody: { response_format: { type: "json_object" } },
           ...(mentionsJson(promptText) ? {} : { cue: JSON_ONLY_CUE }) };
```

三条规则：

1. **Anthropic 无 JSON mode 参数，cue（提示词追加）是全部机制。** 发 `response_format` 是硬 400。为此参考实现做了双保险：Anthropic 适配器干脆不 spread `extraBody`（见第 1 篇 `extraBody` 语义）。历史教训：这个决定曾是散落两处的 `standard === "gemini"` 二元三目——于是**除 Gemini 外的一切**（包括 Anthropic）都被发了 `response_format`。收口成按族 switch 的单一函数后，这类"第三家被二元判断误伤"的 bug 结构性消失。
2. **Gemini 双保险**：`responseMimeType` 照发，cue 也发——有模型静默无视 mimeType。
3. **`mentionsJson` 不是风格检查，是文档明载的前置条件**：OpenAI `json_object` 在上下文找不到 "JSON" 字面量时报错（否则"模型可能生成无限空白流"），DeepSeek 同款要求，千问 DashScope 也原样继承（400：`'messages' must contain the word 'json'`）。这个条件平时"恰好总成立"（prompt 通常提到 JSON），直到某次作者改写 prompt 删掉那个词——**prompt 可编辑的系统不能把它当既成事实**，必须检测、缺则追加 cue。同时 cue 在 OpenAI 路径上是**条件追加**：原生 enforcement 已在，cue 只为补前置条件；无条件加 = 每请求白花 token 复述 prompt 已说的话。

## 3. 强制工具 → JSON mode 的回退链：runStructuredTask

参考实现：simple-ai-writer `src/lib/agent/structured.ts`。

### 路径一：强制 pseudo-tool

- 声明单个 pseudo-tool，`parameters` = 输出 schema；`toolChoice: {type:"function", function:{name}}` 强制调用；读 toolCalls 的 arguments 即结果。
- **`serverTools` 显式置 undefined**——结构化任务不上网。否则一个"唯一允许的工具调用是输出 schema"的请求里，模型可能跑去搜网页。
- 空 arguments 抛 `EMPTY_TOOL_CALL`（进入回退判定）。

### 回退判定：TOOL_CAPABILITY_ERROR 正则

**只对能力类错误回退。** 正则要求能力词（function / tool call…）与"不支持"措辞**同现**。

反面教训（必须写进代码注释）：早期用裸子串 `"does not support"` 判定，真实上游错误（如 "does not support streaming for this region"）也触发回退，把整个请求静默重发成另一形状——**翻倍花钱 + 掩盖真实错误**。回退是重发钱包，判定条件必须窄。

### 路径二：JSON mode + 抠取

- 用 `jsonModeShaping` 的 extraBody + cue + prose 指令重发。
- **关键：回退路径必须仍带 JSON mode 原生参数。** 触发回退的恰是思考型模型（拒绝 forced tool_choice 的那种），在最不容易吐干净 JSON 的模型上退成零约束纯散文是反的。
- 产出用 `extractJsonObject` 抠（参考实现：`src/lib/ai/json.ts`）：优先 ```json 围栏，否则取最外层 `{...}` span——思考型模型爱在 JSON 周围包散文。

### 截断的鉴别

JSON 输出场景对 `max_tokens` 截断尤其敏感：截断的 JSON 解析失败，看起来像"模型不听话"。**结束原因是唯一能区分二者的信息**——`length`/`max_tokens` 调上限，格式错改 prompt。解析失败时必须连同 `truncated`/`stopReason`（第 1 篇 done chunk）一起上报。

## 4. 与被砍档 tool_choice 方言的联动降级

有的兼容端点把 tool_choice 枚举砍到只剩 `auto|none`（实例：MiniMax `switch` 方言端点，见第 3 篇）——**强制档不存在**。

规则：适配器的 `toolChoiceBody` 对已知砍档的方言把 forced **降级为 auto**，而不是发出去等 400。

降级安全的论证（这类"预判降级"必须论证，否则宁可让它 400）：唯一使用强制档的调用方（runStructuredTask）本来就把"模型没调工具"当回退信号——最坏结果是回退早触发一轮；不降级则是"保证失败的请求 + 同一个回退"，多付一趟。**降级不改变任何调用方的语义，只省掉一次必败请求时，才允许静默降级。**

### 砍档的动态变体：跟着砍档条件降（千问 DashScope）

砍档不总是端点常态——千问文档明载 **thinking 开启时** `tool_choice` 只接受
`auto|none`，思考关着时 forced 完全合法。规则随之细化：**预判降级的触发条件要与
砍档条件同形。** 常态砍档（MiniMax）就无条件降；随开关砍就按请求判定，① 族适配器
的判据精确到「本次请求真的发出 `enable_thinking: true`」：

- `switch` 方言声明 **且** 力度非 `off` 非 `default` → 降级（此时 wire 上有
  `enable_thinking: true`）。
- 力度 `off` 发的是 `enable_thinking: false`，`default` 什么字段都不发——而声明
  `switch` 方言的模型思考**默认关**（这正是它们需要开关的原因）——两种情况
  forced 都合法，**不降**。

条件放宽（如「方言声明即降级」）不是错误但要付代价：默认关思考的模型上白白放弃
了强制档的可靠性。条件收紧（漏降）则是必败请求 + 回退，多付一趟。安全论证与上面
共享，因为回退链兜住了两个方向的误差——这也是为什么这条降级敢做得这么细。

## 5. ② Responses 族：`text.format` 与 `text.verbosity`

参考实现：simple-ai-writer `src/lib/ai/jsonMode.ts` 的 `case "responses"`、`src/lib/ai/responses.ts` 的 `text` 合并。

### 5.1 `text.format`：json_schema **不发 `strict` 键**

```ts
// json_schema 档（按模型 id 表自动抬升，与 ① 族共用 OpenAI 行——同一批模型）
{ text: { format: { type: "json_schema", name, schema: strictify(parameters) } } }
// json_object 档
{ text: { format: { type: "json_object" } } }  // + mentionsJson 缺则追加 cue（与 ① 同一前置条件）
```

- 与 ① 族 `response_format.json_schema` 的区别：`name` / `schema` 与 `type` 同级，**没有 `json_schema` 包装层**。
- **`strict` 键刻意省略**：省略时官方端点自动升 `strict: true`（回显 `true`）——正是要的约束；而**显式 `strict: true` 会被 New API 中转站整个丢掉 `format`**（回显 `{type:"text"}`，输出不按 schema，200 无报错）。省略它，官方拿到 strict、中转站保住 schema。
- **schema 仍然 `strictify`**：既然端点会按 strict 规则执法（全必填、`additionalProperties:false`），发出去的 schema 就得符合，与请求里有没有 `strict` 这个词无关。
- 这一条与工具定义**方向相反**（第 2 篇 §7.1：工具要显式 `strict:false`）——同一个自动 strict 事实，结构化输出要它、自由工具不要它。
- `json_object` 缺 "json" 字样同样 400（与 ① 族同一条隐藏前置），cue 规则照搬。
- 千问 Responses 面文档没有 `text` 字段；它是报错还是忽略未验，回退靠"学 400"的通用机制兜。

### 5.2 `text.verbosity`：L3 模型字段，与 format 合并而非覆盖

- GPT-5.x 的 `verbosity: low/medium/high` 实测生效（同题回答确实变短）。做成**模型级声明** `textVerbosity?`，只在 ② 族模型抽屉出现；未设不发（"未声明 = 字节不变"）。按分层它是 L3 字段，进 `ConnOptions` 一处。
- `text` 对象有**两个写者**：模型的 verbosity 与结构化任务经 extraBody 带来的 `text.format`。拼 body 时必须合并：

```ts
const extraText = opts.extraBody?.text;
const text = opts.textVerbosity || extraText
  ? { ...extraText, ...(opts.textVerbosity ? { verbosity: opts.textVerbosity } : {}) }
  : undefined;
// body = { …, ...opts.extraBody, ...(text ? { text } : {}) }   ← text 在 extraBody 之后写回
```

陷阱：extraBody 最后 spread 是惯例（第 1 篇 §6），但它的 `text` 会整个覆盖掉 verbosity；反过来先写 verbosity 再 spread extraBody 也一样丢。合并后的 `text` 要放在 extraBody **之后**。

---

## 本篇检查清单

- [ ] 结构化输出走"强制 pseudo-tool → JSON mode"两级链，不依赖单一机制。
- [ ] 没有使用 `response_format: json_schema` 严格模式（或有明确的可移植性豁免记录）。
- [ ] JSON mode 形状收口在单一 `jsonModeShaping` 按族 switch 中，grep 不到散落的 `standard === "gemini"` 式二元判断。
- [ ] Anthropic 路径只有 cue，没有任何 `response_format`；适配器不 spread extraBody 双保险在位。
- [ ] Gemini 路径 mimeType + cue 双发。
- [ ] OpenAI 路径实现了 `mentionsJson` 检测，cue 条件追加。
- [ ] 结构化请求显式关闭 serverTools。
- [ ] 回退判定正则要求能力词与否定措辞同现；有针对"无关上游错误不触发回退"的测试用例。
- [ ] 回退路径仍携带 JSON mode 原生参数（extraBody），不是纯散文请求。
- [ ] `extractJsonObject` 支持围栏与最外层 span 两种抠法。
- [ ] JSON 解析失败的错误报告携带 stop reason / truncated，能区分"截断"与"格式错"。
- [ ] 已知砍档方言的 forced tool_choice 降级为 auto，且降级的安全性有书面论证。
- [ ] 降级触发条件与砍档条件同形：常态砍档无条件降，随思考开关砍的（千问）按「本次是否真的发出 enable_thinking: true」判定。
- [ ] ② 族 `text.format` 的 json_schema **不发 `strict` 键**（中转站遇显式 `strict:true` 整个丢 format），schema 仍 strictify；有测试钉住请求体里没有 `strict`。
- [ ] `text.verbosity` 是 L3 模型声明、未设不发；与 `text.format` 合并写入，不互相覆盖，合并结果放在 extraBody 之后。
