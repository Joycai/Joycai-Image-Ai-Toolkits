# 04 · 结构化输出与降级链

> 本篇解决的问题：让"要求模型输出一个符合 schema 的 JSON"在四个协议族、官方与兼容端点、思考型与非思考型模型上都能拿到可解析的结果——靠一条明确的降级链，而不是祈祷。
> 不读会踩的坑：把 `response_format` 发给 Anthropic 硬 400；OpenAI `json_object` 在 prompt 不含 "JSON" 字面量时报错或输出无限空白流；用裸子串 "does not support" 判定回退，把无关的上游错误也吞进回退——翻倍花钱 + 掩盖真实错误；回退路径退成零约束纯散文，恰好落在最不容易吐干净 JSON 的思考型模型上。

出处：simple-ai-writer `src/lib/ai/jsonMode.ts`、`src/lib/ai/json.ts`、`src/lib/agent/structured.ts`。

目录：
- §1 四种强度与本方案的两级组合
- §2 JSON mode 的每族形状：jsonModeShaping（含 ④ 的 `output_config.format` schema 模式（只有严格档、五个型号、与思考 / 工具同用、关键字限制）、schema 强制是真的（四族实测）、按模型守不守 schema、中转站上两族旋钮被无视、同台 GPT 的对照指引）
- §3 强制工具 → JSON mode 的回退链：runStructuredTask
- §4 与被砍档 tool_choice 方言的联动降级（千问、智谱、中转站翻译层三种变体）
- §5 ② Responses 族：`text.format` 与 `text.verbosity`（§5.1 不发 `strict` 键，含中转站 GPT 上游对照 · §5.2 verbosity）

---

## 1. 四种强度与本方案的两级组合

结构化输出手段按约束强度排序：

```
prompt 描述  <  JSON mode  <  json_schema 严格模式  <  强制工具调用
```

规范采用**两级组合**：**首选强制 pseudo-tool（schema 即工具 parameters），失败退回 JSON mode + 提示词**。

为什么**默认**不用 `json_schema` 严格模式（已知支持的模型按模型 id 表抬升到 json_schema 档，见 §5.1）：

- schema 要求 `additionalProperties: false` + 全字段 required，对天然有可选字段的领域模型不友好；
- DeepSeek 等兼容层不支持；支持的也常按模型代砍（千问 DashScope 只有最新两三代商业款支持，`json_object` 却全线可用）；
- 强制工具调用是四族官方都有的机制，**可移植性最好的 schema 手段**。

## 2. JSON mode 的每族形状：jsonModeShaping

JSON mode 的开启方式三族三样，应当收口在一处，产出「要并进 body 的字段」+「要追加到提示词的 cue」两样：

| 族 | 并进 body | 追加 cue（「只输出 JSON」一句） |
| --- | --- | --- |
| ③ Gemini | `{"generationConfig":{"responseMimeType":"application/json"}}` | 总是——有模型静默无视 mimeType |
| ④ Anthropic | 无 JSON mode 参数（发 `response_format` 是硬 400）；**只有** schema 模式 `output_config.format`，见本节末 | 不发 schema 时总是（cue 是全部机制）；发 schema 时不发 |
| ① OpenAI 系 | `{"response_format":{"type":"json_object"}}` | 仅当上下文里没有 "JSON" 字样（前置条件，见规则 3） |

三条规则：

1. **Anthropic 无 JSON mode 参数，cue（提示词追加）是 JSON mode 的全部机制。**（schema 严格模式是另一回事：`output_config.format`，见本节末「④ 的 schema 模式」，【2026-09-26 更正】旧版本篇说 ④ 只有 cue。）发 `response_format` 是硬 400。为此参考实现做了双保险：Anthropic 适配器干脆不 spread `extraBody`（见第 1 篇 `extraBody` 语义）。历史教训：散落的 `standard === "gemini"` 二元三目让**除 Gemini 外的一切**（包括 Anthropic）都被发了 `response_format`；收口成按族 switch 后，"第三家被二元判断误伤"的 bug 结构性消失。
2. **Gemini 双保险**：`responseMimeType` 照发，cue 也发——有模型静默无视 mimeType。
3. **`mentionsJson` 不是风格检查，是文档明载的前置条件**：OpenAI `json_object` 在上下文找不到 "JSON" 字面量时报错（否则"模型可能生成无限空白流"），DeepSeek 同款要求，千问 DashScope 也原样继承（400：`'messages' must contain the word 'json'`）。这个条件平时"恰好总成立"（prompt 通常提到 JSON），直到某次作者改写 prompt 删掉那个词——**prompt 可编辑的系统不能把它当既成事实**，必须检测、缺则追加 cue。同时 cue 在 OpenAI 路径上是**条件追加**：原生 enforcement 已在，cue 只为补前置条件；无条件加 = 每请求白花 token 复述 prompt 已说的话。

**不是所有 ① 族兼容端都执行规则 3 的前置条件，也不是都认 `json_schema`**（智谱 BigModel，【实测 2026-09-19】）：
`json_object` 在提示词里没有 "json" 字样时照常出合法 JSON（Kimi / MiniMax 同样不查）；`response_format:{type:"json_schema",…}`
**200 但静默无视**——回的是包在 ```json 代码块里、不合 schema 的文本。所以 `json_schema` 只能对**实测过**的端点放开，
不能因为「它是 ① 族兼容端」就推定支持。

**同一个端点，按模型决定守不守 schema**（火山方舟套餐，【实测 2026-09-23】）。测法：schema 让 `answer` 只能是 `enum:[7]`、不许额外字段，
prompt 却要真实结果并多要一个 `reason`——只有真被约束才会守住（合法 JSON 不能证明 schema 生效）：

| 模型 | ① `json_schema` + `strict:true` | ① 不带 `strict` | ② `text.format`（不带 `strict`，§5.1） |
| --- | --- | --- | --- |
| doubao-seed-2.1-turbo | 2/2 守住 | 1/2 越过 | 2/2 守住 |
| doubao-seed-2.0-lite | **不守**（答真实值 + 多出字段），200 | — | **不守**，200 |
| doubao-seed-2.0-mini | 守住 | — | 值守住、多出字段 |

- 所以能力按**模型前缀**放行（这里只放 2.1 系），同平台的其余模型留在 `json_object`；「平台支持 json_schema」这句话本身不成立。
- strict 的常见预处理（可选字段改写成 `type:["string","null"]` 并列入 `required`）①（strict）② 都收下，200、两键齐全。
- ① 的 `strict` 键要发：不带时 2.1-turbo 也会越过；② 保持不发（§5.1），实测照样守住。

**两族的 JSON 旋钮在同一个端点上都被静默无视**（New API 中转站 Kiro 渠道的 Claude，【实测 2026-09-23】，landscape.md §7 第十五个样本；背景见第 1 篇 §9.2）。
用同一个「schema 把 `answer` 锁死为 `7`」的测法：

| 面 | 发送 | 结果 |
| --- | --- | --- |
| ① | `response_format:{type:"json_object"}` / `{type:"json_schema", json_schema:{…, strict:true}}` | 都 200、都被忽略：回 json 围栏代码块，键名自拟（`result`，不是被 enum 锁死的 `answer: 7`） |
| ④ | `output_config.format`（GA 写法）/ `output_format` + beta 头 | 都 200、都被忽略：模型照答 `2`，外面包 markdown |

- 这种端点上「发了 JSON mode」比「没发」更糟：① 的 cue 是**条件追加**（规则 3），实现以为原生约束在位就不补「只输出 JSON」，
  结果只剩 prompt 自己的措辞在起作用。
- 做法：把这个模型的结构化能力判「不发」，**解析成 cue-only**——JSON 模式降到 `off`，恒发 cue，靠 `extractJsonObject`（§3 路径二）
  抠围栏，与 ④ 官方路径同一套机制。参考实现按模型 id 点名（第 1 篇 §9.2 的 `KIRO_CLAUDE`），`resolveStructuredOutput` 查表时带上模型 id。
  （只点了 Kiro；按下面的更正，① 面应扩到整台中转站的 Claude【未实现】。）
- 200 不报错，靠「失败再降级」学不到；验证只能用上面那种 schema 与 prompt 冲突的用例，看结果合不合 schema，不能只看能否解析。

**更正与渠道对照（2026-09-23，landscape.md §7 第十六个样本）**：上表 ① 行**不是 Kiro 特有**——同一台上 CC / anti / AWSb 的 Claude 走 ① 面，
`response_format` 全部被丢，**连 ④ 面真会执行 schema 的 AWSb 也一样**：是 New API 的 ①→④ 转换不转这个字段。④ `output_config.format` 才随渠道：

| Kiro | CC | anti | AWSb（Bedrock 正向） |
| --- | --- | --- | --- |
| 无视 | opus-4-6 无视（散文）、opus-5 执行（各 2/2） | 无视 | ✅ 执行 |

- 同一渠道、同一模型，**结构化输出随面不同**（AWSb：④ 有、① 无）。能力格必须按面分：① 面按「平台的转换层」判（这台 New API 上所有 Claude 不发），
  ④ 面才按渠道点名；CC 这种同渠道按模型不同的，点名要细到模型。

**④ 的 schema 模式：`output_config.format`**（【实测 2026-09-26】，Sonnet 5 经 OrcaRouter，回包 Anthropic 原样，第 1 篇 §9.5）：
`output_config: { format: { type: "json_schema", schema } }`（与 `output_config.effort` 同一个对象）回的就是合 schema 的纯 JSON（`{"color":"red","n":7}`），没有围栏。
- **型号与组合**（【实测 2026-09-26 补测】，同一网关的 Anthropic 原样线路）：
  - 官方支持表从 Claude 4.5 起；实测 Sonnet 5 / 4.6、Opus 5.5 / 4.5、Fable 5.1 都守住 enum（下表）。
  - 与 adaptive 思考、`budget_tokens` 思考同用：thinking block 在前、JSON text 在后（Opus 5.5 的思考摘要里明说「yellow 不在 enum 里」）。
  - 与工具同用：第一轮照常 `tool_use`，回灌结果后第二轮给合 schema 的 JSON；与强制 `tool_choice`（`any` / 指名，含 adaptive）同用照常强制出 `tool_use`，不冲突。
  - 流式：JSON 走普通 `text_delta`，没有新块类型。
- **只有严格档，没有「任意 JSON 对象」**。把三档阶梯（schema → json_object → off）照搬到 ④ 会造出一个不存在的中间档：自动档与被拒降级都只能在 `json_schema` 与 `off`（cue）之间走；被拒后「将发送」之类的显示也要显示成 off，而不是一个线上没发的 json_object。
- **schema 限制**（官方）：对象必须 `additionalProperties:false`；不支持 `minimum` / `maximum` / `multipleOf`、`minLength` / `maxLength` / `pattern`、`minItems` 只收 0 / 1、不支持递归与外部 `$ref`；官方 SDK 发送前剥掉它们。适配层同样在 strictify 之后剥（`oneOf` 写成 `anyOf`；同一节点 `anyOf` 与 `oneOf` 并存时拆成 `allOf` 里的两个 `anyOf`，别合并放宽）。经网关发这些关键字、非法 `type`、递归、缺 `schema` 都是 200——请求侧结论只对网关成立，**官方的拒绝报文至今没有样本**，降级判据按「报文以字段路径开头」推为 `output_config.format`。
- **与 effort 共用 `output_config`**：思考档位写 `output_config.effort`，schema 写 `output_config.format`——合并进同一个对象，平铺展开会让后写的一方盖掉先写的。适配器仍只取 `extraBody` 里的这一个字段，其余（OpenAI 形）不展开。
- 自动档按 id 名单放开时，**两种拼法都列**：官方连字符 `claude-opus-4-5`、中转站点号 `claude-opus-4.5`（前缀表对另一种静默不命中）。
- 经翻译层的中转站可能无视它（上文 Kiro / anti 两行、CC 按模型）——能力按（平台, 面, 渠道, 模型）记，不从「这是 Claude」推出；没测过的平台只在作者声明时发。

**schema 强制是真的**（【实测 2026-09-26】，经 OrcaRouter；测法同上：prompt 要 `yellow`，enum 只有 red / green / blue）：

| 面 · 模型 | 发送 | 结果 |
| --- | --- | --- |
| ① `gpt-6-luna`（OpenRouter 形态线路） | `response_format` strict `json_schema` | 守住 enum |
| ② `gpt-6-luna` | strict `text.format` | 守住 |
| ③ Gemini 3.8 Flash（Vertex） | `generationConfig.responseJsonSchema`（标准 JSON Schema，含 `additionalProperties:false`） | 守住，回 `red` |
| ③ 同上 | 旧 `responseSchema`（OpenAPI 方言，大写类型） | 守住 |
| ④ Sonnet 5 / Sonnet 4.6 / Opus 4.5（`thinking: disabled`）、Opus 5.5 / Fable 5.1（默认思考） | `output_config.format` | 守住；去掉 enum 的对照组答 `yellow` |

- ③ 两个字段在 3.8 Flash 上**都**生效（互斥：只发一个）；把 schema 做成 strict 风格（`additionalProperties:false`、类型联合）后发 `responseJsonSchema` 也 200。

**同一台上的 GPT**（【实测 2026-09-24】，第十七个样本）：① `response_format` 不是被整台丢——GPT 走的是 ①→② 翻译，账号池 `[Plus]` / `[特价Pro]` 与网关都执行 strict `json_schema`，
只有 `[Pro]` 一档丢（① ② 都丢）。对照表在 §5.1「中转站上游对照」。

## 3. 强制工具 → JSON mode 的回退链：runStructuredTask

出处：simple-ai-writer `src/lib/agent/structured.ts`。

分清两件事：**本节是任务层的路径选择**（强制工具没调用 / 能力错误 → 改走 JSON）；**端点 400 了某一档之后逐档降、记住、重发**是学习，
【2026-09-28 起】只在统一入口的执行器里做一次（第 6 篇 §9）——调用方只说「这次要 JSON、schema 是 X」，不再各自包一层「JSON 被拒再试」。
任务层判断「强制有没有真的发出」读请求计划里**发出的**强制，不读请求了什么（06 §9.1）；cue 由执行器接在最后一条 user 消息里（06 §9.3）。

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
- 产出用 `extractJsonObject` 抠（出处：`src/lib/ai/json.ts`）：优先 ```json 围栏，否则取最外层 `{...}` span——思考型模型爱在 JSON 周围包散文。

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

条件放宽（如「方言声明即降级」）白白放弃默认关思考模型的强制档，收紧（漏降）多付一趟必败请求——回退链兜住两个方向的误差，安全论证与上面共享。

### 砍档的第三种变体：文档砍档、实测无视或笼统 400（智谱）

智谱文档写 `tool_choice`「默认且仅支持 `auto`」，【实测 2026-09-19】的真实行为按模型三样：

| 模型 | `required` | 具名 `{type:"function",…}` | `none` |
| --- | --- | --- | --- |
| glm-5.x（含 5.3-flash） | 200，**不强制** | 200，**不强制** | 5.3-flash 照调工具（无视） |
| glm-4.7 / 4.6 / 4.5 | 200，不强制 | 思考开时 **400 `1210 API 调用参数有误`**；关时 200 不强制 | 生效 |
| glm-4.5-air | 200，**真强制** | 200，真强制 | 生效 |

两个推论：

- **「从 400 里学习降级」在这里失效**：那个 400 是笼统的「参数有误」，不提 `tool_choice`。按错误文案里的参数名识别「强制被拒」
  的学习机制（DeepSeek V4 用得上）认不出它，请求直接失败。
- 因此降级条件放在**平台**上、无条件：这个平台上 forced 一律发 `auto`。它与思考开关无关（4.7 关思考时也不强制），所以不能挂在
  思考方言 / 类目上。代价是 4.5-air 失去它唯一真生效的强制档——回退链兜得住，符合上文「只省一次必败请求才静默降级」。

### 砍档的第四种变体：只在非流式路径上实现（中转站翻译层，Kiro 渠道的 Claude）

【实测 2026-09-23】（landscape.md §7 第十五个样本；背景见第 1 篇 §9.2）。中转站把请求翻给非 Anthropic 的后端，强制 `tool_choice`
**只在非流式的转换路径上实现了**：

| | ④ `{type:"any"}` / `{type:"tool", name}` | ① `"required"` / 具名 `{type:"function",…}` |
| --- | --- | --- |
| 流式 | **被无视**：每模型 × 思考开关 × 两种写法各 4 次，32 次里 1 次调用（另一轮 adapter 实测关思考 6 次里 2 次，都像模型自己想调） | **被无视**：4 次 0 次调用；具名那条模型甚至复述「你要我调用 get_weather」，但没调用 |
| 非流式 | 关思考 16/16 生效；开思考 `tool` 0/8、`any` 6/8 | 生效（拿「讲个笑话」也调用了 `get_weather`） |

- 同一请求流式报 `prompt_tokens` 301、非流式 102——两条路径的转换不是同一套，这就是它们行为不同的根源。
- 不报错，模型只回一段散文。**用 curl 非流式先摸形状的人会得出「支持」**，而永远流式的应用里它从不生效（探测纪律见第 6 篇 §8）。
- 降级条件按**模型 id** 放（渠道只在 id 里看得出，第 1 篇 §9.2）：被点名的 id 上 forced 一律发 `auto`（① `"auto"`、④ `{type:"auto"}`）。
  ④ 适配器以前根本不查这一格，要补上。安全论证与本节开头相同：`runStructuredTask` 把「没调工具」当回退信号，最坏是回退早一轮。
- 按「是否流式」分条件降级也行得通，但应用只走流式时它等于无条件降；分条件只在同时有非流式调用点时才值得。

**复测与同台别的渠道（2026-09-23 晚些时候，landscape.md §7 第十五个样本复测 + 第十六个样本）**：

- Kiro 复测：带思考仍 0 次（④ 非流式 4 次、流式 5 次）；不带思考、流式这次 5 次 3 次（第一轮 16 次 1 次）——这一格随时间变，不能当成稳定的「行 / 不行」。
  带思考那一格稳定失败，而 `claude-adaptive` 总带 thinking，所以「改发 `auto`」不变。
- 别的渠道（④ 面；① 面同形）：

| | 不带思考（非流式 / 流式） | 带 adaptive 思考 |
| --- | --- | --- |
| Kiro | 全调用 / 时好时坏 | 0 |
| CC | 全调用 / 全调用 | 非流式 3/8、流式 4/8——**时好时坏** |
| anti | **0 / 0**（① 非流式 5 次 1 次、流式 0） | 0 |
| AWSb（Bedrock 正向） | 全调用 / 全调用 | ✅ 全调用 |

- **anti 是第五种变体：两条路径都不实现强制。**
- CC 的「时好时坏」**不宜判不发**：关掉等于把不带思考时 100% 的那部分也丢了，回退链本来就兜得住「没调」。只有稳定失败的格子（anti、Kiro 带思考）才值得降成 `auto`。

## 5. ② Responses 族：`text.format` 与 `text.verbosity`

出处：simple-ai-writer `src/lib/ai/jsonMode.ts` 的 `case "responses"`、`src/lib/ai/responses.ts` 的 `text` 合并。

### 5.1 `text.format`：json_schema **不发 `strict` 键**

```jsonc
// json_schema 档（按模型 id 表自动抬升，与 ① 族共用同一批模型）；schema 已按 strict 规则整理
{ "text": { "format": { "type": "json_schema", "name": "…", "schema": { … } } } }
// json_object 档；上下文缺 "json" 字样时追加 cue（与 ① 同一前置条件）
{ "text": { "format": { "type": "json_object" } } }
```

- 与 ① 族 `response_format.json_schema` 的区别：`name` / `schema` 与 `type` 同级，**没有 `json_schema` 包装层**。
- **`strict` 键刻意省略**：省略时官方端点自动升 `strict: true`（回显 `true`）——正是要的约束；而**显式 `strict: true` 会被 New API 中转站整个丢掉 `format`**（回显 `{type:"text"}`，输出不按 schema，200 无报错）。省略它，官方拿到 strict、中转站保住 schema。
  > **被扩展（【实测 2026-09-24】，landscape.md §7 第十七个样本，另一台 New API）**：上面「显式 `strict` 才丢」是第八个样本 `[Pro]` 档当时的结论，保留。
  > 这一次同一个 `[Pro]` 前缀（ChatGPT 账号池）**省略 `strict` 与显式 `strict:true` 各 4 次全部被丢**，① `response_format: json_schema` 也 4/4 被丢，`json_object` 回显 `text`；
  > 同台 `[Plus]` / `[特价Pro]` 两种写法都执行（`[Plus]` 上第八个样本那条也没复现），网关上游 ① ② 都执行。「省略 `strict`」仍是对的——它在能执行的上游上保住 schema，
  > 只是**救不了**这种整个丢 format 的上游。见下文「中转站上游对照」。
- **schema 仍然 `strictify`**：既然端点会按 strict 规则执法（全必填、`additionalProperties:false`），发出去的 schema 就得符合，与请求里有没有 `strict` 这个词无关。
- 这一条与工具定义**方向相反**（第 2 篇 §7.1：工具要显式 `strict:false`）——同一个自动 strict 事实，结构化输出要它、自由工具不要它。
- `json_object` 缺 "json" 字样同样 400（与 ① 族同一条隐藏前置），cue 规则照搬。
- 千问 Responses 面文档没有 `text` 字段；它是报错还是忽略未验，回退靠"学 400"的通用机制兜。

**中转站上游对照（【实测 2026-09-24】，同一个 `gpt-5.6-sol`，schema 把 `answer` 锁成 `7`，§2 的冲突测法；上游分类见第 1 篇 §9.2「同一个 GPT，两类上游」）**：

| 上游 | ② `text.format: json_schema`（省略 / 显式 `strict`） | ② `json_object` | ① `response_format: json_schema`（strict） |
| --- | --- | --- | --- |
| `[特价Pro]`（账号池） | ✅ / ✅ | ✅ | ✅ |
| `[Plus]`（账号池） | ✅ / ✅ | ✅ | ✅ |
| `[Pro]`（账号池） | ❌ / ❌：回显 `{type:"text"}`，模型答 `{"answer":2}` | 回显 `text`，碰巧输出 JSON | ❌（4/4） |
| `[Azure]`（网关，terra） | ✅ / ✅ | ✅ | ✅ |

- 丢 format 的那一档，提示语仍要求 JSON，所以**回的仍是合法 JSON**，只是不受 schema 约束——「能解析」不能证明 schema 生效，只能用冲突用例验。
- 同一种上游（三档都是账号池）测出两种结果，能力格写不下：参考实现没给账号池写 `structuredOutput: false`（会让另两档白丢实测可用的 JSON 模式），
  只在模型抽屉的上游说明里告知（第 1 篇 §9.2「上游画像扩到 GPT」）。能在运行时发现它的办法是回显比对：发了 `json_schema`、终止响应回显 `{type:"text"}`（第 6 篇 §4.1）【未实现】。

### 5.2 `text.verbosity`：L3 模型字段，与 format 合并而非覆盖

- GPT-5.x 的 `verbosity: low/medium/high` 实测生效（同题回答确实变短）。【实测 2026-09-24】同一台中转站四个上游的 ② `text.verbosity` 都生效（同题输出 token low / high：106 / 244、85 / 174、53 / 79、136 / 176）；
  ① 面的顶层 `verbosity` 四个上游都**看不出效果**——`textVerbosity` 只在 ② 族声明，① 上不发。做成**模型级声明** `textVerbosity?`，只在 ② 族模型抽屉出现；未设不发（"未声明 = 字节不变"）。按分层它是 L3 字段，进 `ConnOptions` 一处。
- `text` 对象有**两个写者**：模型的 verbosity 与结构化任务经 extraBody 带来的 `text.format`。拼 body 时必须合并：
  `text = extraBody.text 的全部键 + {verbosity}（若声明）`，然后**在并入 extraBody 之后**再写回 body。
  最终 body 形如 `{"text":{"format":{…},"verbosity":"low"}}`。

陷阱：extraBody 最后 spread 是惯例（第 1 篇 §6），但它的 `text` 会整个覆盖掉 verbosity；反过来先写 verbosity 再 spread extraBody 也一样丢。合并后的 `text` 要放在 extraBody **之后**。

---

## 本篇检查清单

- [ ] 结构化输出走"强制 pseudo-tool → JSON mode"两级链，不依赖单一机制。
- [ ] 默认不用 `json_schema` 严格模式，只对模型 id 表里已知支持的模型抬升（或有明确的可移植性豁免记录）。
- [ ] JSON mode 形状收口在单一 `jsonModeShaping` 按族 switch 中，grep 不到散落的 `standard === "gemini"` 式二元判断。
- [ ] Anthropic 路径没有任何 `response_format`，适配器不 spread extraBody 双保险在位；④ schema 模式发 `output_config.format:{type:"json_schema", schema}`，与 `output_config.effort` 合并而非覆盖；只有 schema / off 两档；schema 先剥掉不支持的关键字；型号名单两种拼法都列。
- [ ] Gemini 路径 mimeType + cue 双发。
- [ ] OpenAI 路径实现了 `mentionsJson` 检测，cue 条件追加。
- [ ] 结构化请求显式关闭 serverTools。
- [ ] 回退判定正则要求能力词与否定措辞同现；有针对"无关上游错误不触发回退"的测试用例。
- [ ] 回退路径仍携带 JSON mode 原生参数（extraBody），不是纯散文请求。
- [ ] 「被拒逐档降」只在统一入口的执行器里（06 §9）；调用方只传意图，没有各自的 JSON 被拒重试包装；cue 接在最后一条 user 消息里，不另起一条。
- [ ] `extractJsonObject` 支持围栏与最外层 span 两种抠法。
- [ ] JSON 解析失败的错误报告携带 stop reason / truncated，能区分"截断"与"格式错"。
- [ ] 已知砍档方言的 forced tool_choice 降级为 auto，且降级的安全性有书面论证。
- [ ] 降级触发条件与砍档条件同形：常态砍档无条件降，随思考开关砍的（千问）按「本次是否真的发出 enable_thinking: true」判定。
- [ ] ② 族 `text.format` 的 json_schema **不发 `strict` 键**（中转站遇显式 `strict:true` 整个丢 format），schema 仍 strictify；有测试钉住请求体里没有 `strict`。
- [ ] 经中转站的 GPT 按上游用冲突 schema 验过 ① ② 两种写法：有上游（`[Pro]` 类账号档）不论写不写 `strict` 都整个丢 format，省略 `strict` 救不了；这类丢弃靠说明或回显比对告知，不靠「能解析」判断生效。
- [ ] `text.verbosity` 是 L3 模型声明、未设不发；与 `text.format` 合并写入，不互相覆盖，合并结果放在 extraBody 之后。
- [ ] 端点静默无视 JSON 旋钮（200、不合 schema）的模型，结构化能力判「不发」、解析成 cue-only（恒发 cue + 抠围栏）；强制 `tool_choice` 只在非流式生效的端点，按应用实际走的流式结果判定，forced 降 auto——两者都按模型 id 查表，查表点带 id。
