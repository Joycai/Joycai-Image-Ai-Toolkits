# 思考模式：强度、思维链、以及回传义务

> 边界见 [`README.md`](README.md)：只写协议事实。族的编号沿用
> [`landscape.md`](landscape.md)：① Chat Completions ② Responses ③ Google GenAI
> ④ Anthropic Messages。

思考模式在协议层是**三件独立的事**，很容易被当成一件：

1. **强度** —— 请求里怎么说"想多久"。
2. **思维链** —— 响应里怎么把想的内容给你（很多端点根本不给）。
3. **回传义务** —— 下一轮要不要把上一轮想的东西还回去。**这一件才是会让请求
   被直接拒绝的那一件**，也是最少被文档放在显眼处的一件。

---

## 1. 强度

| 协议 | 参数位置 | 档位 | 默认 | 关闭 |
| --- | --- | --- | --- | --- |
| **①** | 顶层 `reasoning_effort` | `none/minimal/low/medium/high/xhigh/max`，**每个模型只支持子集** | 模型自定 | `reasoning_effort:"none"` |
| **② Responses** | `reasoning:{effort, summary}` | 同上 | 同上 | 同上 |
| **③ Gemini 3+** | `thinking_level`（Interactions）；经典 surface 上的位置**文档已不给**，见 §1.5 | `minimal/low/medium/high` | **按模型分三种**，见 §1.4 | **不可关**，`minimal` 也只是「最少」 |
| **③ 2.5 代** | `generationConfig.thinkingConfig.thinkingBudget` | `-1` 动态 / `0` 关 / 具体 token 数 | `-1` | `0`，但 2.5 Pro 拒绝 |
| **④ 新代**（4.6+/5） | `thinking:{type:"adaptive"}` 开关 + `output_config:{effort}` 深度 | `low/medium/high/xhigh/max` | 见 §1.3 —— **按模型不同，不是统一的** | `thinking:{type:"disabled"}`，**部分模型拒绝** |
| **④ 旧代**（4.5 及更早） | `thinking:{type:"enabled", budget_tokens:N}` | **数值预算**，≥1024 且 < `max_tokens` | 关闭 | 省略该字段 |

### 1.1 档位名相同不等于语义相同

`low/medium/high` 是四族的最大公约数，但：

- **DeepSeek 只有三个真实档位**：`medium`/`xhigh` 被映射成 `high`，只有
  `low`/`high`/`max` 会得到不同的行为。
- **①/② 的 `minimal`、`none` 只有部分模型支持**，④ 的 `xhigh`/`max` 也是。
  "不是每个模型支持每个值"这条规则总是先在边缘档位上应验。
- **④ 的 effort 影响的是整个回复的 token 消耗**（包括工具调用次数与解释文字），
  不只是思考深度。别族的 effort 只管思考。

### 1.2 ④ 的默认值按模型分两派（最容易想当然的一条）

"Claude 默认会思考" 只对一半的模型成立：

| 模型 | 默认 | 要什么 |
| --- | --- | --- |
| Opus 5 / Sonnet 5 / Fable 5 / Mythos 5 | **思考已开**，无需配置 | 想看见思考文本要额外开 `display` |
| Opus 4.8 / 4.7 / 4.6 / Sonnet 4.6 | **思考关闭** | 必须显式 `thinking:{type:"adaptive"}` |
| 4.5 及更早 | 只支持手动模式 | `thinking:{type:"enabled", budget_tokens:N}` |

所以"省略 `thinking` 字段"在前一派是"用默认（开）"，在后一派是"关着"。
**同一段代码在两代模型上得到相反的行为，且都不报错。**

### 1.3 关闭的三种拒绝方式

- **Fable 5 / Mythos 5 / Mythos Preview**：无条件拒绝 `thinking:{type:"disabled"}`
  —— 思考关不掉。
- **Opus 5**：`high` 及以下可关；`xhigh`/`max` effort 下发送 disabled **返回 400**。
- **Opus 5 关闭思考后**的副作用：官方明示它"偶尔会把工具调用当作纯文本吐出，
  或在可见输出里混入内部 XML 标签"。

### 1.4 ③ Gemini 3+ 的档位与默认

| 模型 | 支持档位 | 默认 |
| --- | --- | --- |
| Gemini 3.1 Pro | `low/medium/high` —— **没有 `minimal`** | `high` |
| Gemini 3 Flash / 3.6 Flash | `minimal/low/medium/high` | `high` / `medium` |
| Gemini 3.1 Flash-Lite | `minimal/low/medium/high` | `minimal` |

两条要点：

- **默认值按模型分三种**（`high` / `medium` / `minimal`），与 ④ 族「默认值分
  两派」是同一类陷阱：省略字段得到的行为，取决于对面是哪个模型。
- **`minimal` 不等于关闭。** 文档原话：*"`minimal` does not guarantee that
  thinking is off"*。③ 族**没有关闭思考的手段**，这比 ④ 族更彻底（④ 至少部分
  模型接受 `disabled`）。

### 1.5 ③ 族在经典 surface 上的完整配置（API 参考原文）

指南页只给 Interactions 示例，但 **API 参考里定义齐全**
（`generate-content.md.txt`）：

```jsonc
// generationConfig.thinkingConfig
{
  "includeThoughts": boolean,   // 是否在响应里返回思考
  "thinkingBudget": integer,    // 思考 token 数
  "thinkingLevel": enum         // MINIMAL | LOW | MEDIUM | HIGH
}
```

逐条原文：

- **`thinkingConfig` 在 `generationConfig` 之下**，与 `speechConfig`/`imageConfig`
  并列。*"An error will be returned if this field is set for models that don't
  support thinking."*
- **`thinkingLevel`** —— *"Controls the maximum depth of the model's internal
  reasoning process… The default value is model-dependent. **Recommended for
  Gemini 3 or later models. Use with earlier models results in an error.**"*
  枚举值是 `THINKING_LEVEL_UNSPECIFIED` / `MINIMAL` / `LOW` / `MEDIUM` / `HIGH`
  —— **全大写**，不是指南页里那个小写的 `thinking_level`。
- **`includeThoughts`** —— *"Indicates whether to include thoughts in the
  response. If true, thoughts are returned only when available."*
  **默认不返回**，与 ④ 族 `display: "omitted"` 是同一类陷阱。
- **`thinkingBudget`** 仍在，与 `thinkingLevel` 并列。**两代的字段并存于同一个
  对象**，靠"用错模型会报错"来区分，而不是靠不同的对象形状。

### 1.6 ③ 族：签名缺失是一个 `finishReason`

`finishReason` 枚举里有一项：

| 值 | 原文 |
| --- | --- |
| `MISSING_THOUGHT_SIGNATURE` | *"Request has at least one thought signature missing."* |

**这让 ③ 族的回传失败既不是 400 也不是静默降级，而是第三种形态**：请求成功、
响应回来了、但以这个原因终止。只认 HTTP 状态码或只认 `SAFETY` 的客户端会把它
当成一次正常的短回复。

同组还有两个工具相关的：`UNEXPECTED_TOOL_CALL`（模型调了工具但请求没开工具）、
`TOO_MANY_TOOL_CALLS`（连续调用过多被系统中断）。

### 1.7 「关闭」不是通用能力

- Gemini 2.5 Pro 关不掉；新代多数模型最低只能到 `minimal`。
- Claude Opus 5 在 `xhigh`/`max` effort 下收到 `thinking:{type:"disabled"}` 会
  返回 400。
- ④ 的手动 thinking（`type:"enabled"`）与**强制 `tool_choice` 冲突**：需要强制
  单个工具的结构化输出场景，必须显式关掉思考。

### 1.8 ④ 的新旧代互斥，且代次不可从模型名判断

4.7 及以后的模型收到 `thinking:{type:"enabled"}` **直接 400**；4.5 及更早不认
`output_config`。在第三方兼容端点上模型名是自由文本，猜代次不可靠——只能默认
不发，或发了失败再降级。

### 1.9 强度与采样参数互斥

**①：思考模式不支持 `temperature`、`top_p`、`presence_penalty`、
`frequency_penalty`**（DeepSeek 文档明示，OpenAI 推理模型同样不支持
`temperature`）。任何同时提供"温度"与"思考强度"两个设置的界面，都会在推理模型
上让二者互相打架。

---

## 2. 思维链的取回

| 协议 | 流式字段 | 备注 |
| --- | --- | --- |
| **① OpenAI 官方** | **没有内容**，只有 `usage.completion_tokens_details.reasoning_tokens` 计数 | 想看思维链，官方 Chat Completions 这条路是不通的 |
| **① 兼容层扩展** | `delta.reasoning_content`（DeepSeek）/ `delta.reasoning`（OpenRouter 等）/ 部分中继内联 `<think>…</think>` | **字段名没有标准**，见 §2.1 |
| **②** | `reasoning.summary`（需 opt-in `summary: auto/concise/detailed`）+ 无状态时的 `encrypted_content` | 是摘要不是原文 |
| **③** | 经典 surface：`part.thought === true` 的文本 part + `thoughtSignature`。Interactions：`steps[]` 里 `type:"thought"` 的 step，含 `signature` 与 `summary` | 摘要；Interactions 需 `thinking_summaries: "auto"` 开启 |
| **④** | `content_block_delta` → `thinking_delta.thinking` + `signature_delta.signature` | 摘要；**且默认可能一个字都不给**，见 §2.3 |

### 2.1 ① 的字段名分歧

同一个协议族里至少三种写法在流通：`reasoning_content`、`reasoning`、以及把
思维链混进正文的 `<think>…</think>`。**没有任何一方是"标准"** —— OpenAI 官方
不返回思维链，所以这里没有可依据的原始定义，各家各自扩展。

实践含义：读取端应当把它当作一张**候选字段名表**去试，而不是认准一个名字；
写回端应当**用收到时的那个名字写回去**（见 §3）。

### 2.2 ④ 的 `display`：默认拿不到思考文本

`thinking.display` 有两个取值，**默认值按模型不同**：

- `"summarized"` —— 返回可读的思考摘要。Opus 4.6 / Sonnet 4.6 及更早的默认。
- `"omitted"` —— 返回的 `thinking` block **`thinking` 字段为空字符串**，只有
  `signature` 有值。**Fable 5 / Mythos 5 / Opus 5 / Sonnet 5 / Opus 4.8 / 4.7
  的默认。**

也就是说：**在当前这一代模型上，不显式设 `display: "summarized"` 就一个字也
拿不到** —— 但仍然照全额思考 token 计费。`omitted` 省的是延迟（服务端跳过流式
传输思考 token，正文更早开始），不是钱。

三个连带事实：

- 流式下 `display: "omitted"` 不会发出任何 `thinking_delta` 事件。
- 回传时，往 omitted block 的空 `thinking` 字段里塞文本会被**忽略**（不是报错）
  —— 这是"修改 thinking block 一律 400"的唯一例外。
- `signature` 在两种 display 下完全相同，且中途切换 display 是允许的。

另外，**没有任何 display 设置能拿到原始思维链**。`summarized` 给的是由另一个
模型生成的摘要，且计费按原始思考 token 而非摘要 token —— 账单上的输出 token
数与你看到的文本对不上是正常的。Fable 5 / Mythos 5 更进一步：原始思维链永不返回。

### 2.3 token 计数

四族都把思考 token 计入**输出**侧，但报的地方不同：

- **①/②**：`completion_tokens` / `output_tokens` 已包含，`*_details.reasoning_tokens`
  是其中的明细。
- **③**：`candidatesTokenCount` **不含**思考，思考在 `thoughtsTokenCount` 里 ——
  只读前者会把一次思考 5k、回答 500 的请求记成 500。
- **④**：`output_tokens` 已包含；`usage.output_tokens_details.thinking_tokens`
  是明细，流式下只在最后的 `message_delta` 出现。

---

## 3. 回传义务（最容易被漏掉的一件）

**规则不是"要不要显示"，而是"下一个请求会不会被拒"。**

| 协议 | 要求 | 违反后果 |
| --- | --- | --- |
| **① 官方** | 无（本来就没有内容） | — |
| **① DeepSeek** | 两个 user 消息之间**如果模型进行了工具调用**，中间 assistant 的 `reasoning_content` 必须参与拼接，且"在后续所有 user 交互轮次中必须回传"；**没有**工具调用时无需回传（传了会被忽略） | 文档原文：**"若您的代码中未正确回传 `reasoning_content`，API 会返回 400 报错"** |
| **②** | 无状态模式（`store:false`）下回传 reasoning item 的 `encrypted_content` | 丢失推理上下文 |
| **③** | 无状态模式下**必须**原样回传带签名的思考块；有状态模式（Interactions 的 `store`/`previous_interaction_id`）由服务端管 | 多轮推理连续性断裂 |
| **④** | 工具轮必须原样带回该轮的 thinking block（含 `signature`）与 `redacted_thinking` block | **分两种，见 §3.3**：缺失 → 静默降级；改动 → 400 |

四条的共同形状：**思考模型把"自己上一轮想了什么"视为这一轮上下文的一部分**，
而这份内容是它自己产出的、带签名或带完整性校验的，所以只能原样奉还，不能重写、
摘要或省略。

### 3.1 ④ 的回传规则（四族里最细的一套）

官方把要求分成三档，措辞值得原样记住：

- **必须（Required）**：工具使用回合之内，thinking block 必须传回。
- **推荐（Recommended）**：跨回合全部传回。
- **允许（Allowed）**：工具使用之外，可以省略此前回合的 thinking。

理由不是形式主义：**一次工具循环在模型看来是"一个 assistant 回合"**。模型调用
工具时是暂停了自己回复的构造去等外部信息，工具结果回来后它继续构造**同一条**
回复——所以那段推理必须还在。

#### 缺失与改动是两种不同的后果

这一点极易混淆，也是与 DeepSeek 最大的不同：

- **缺失 → 静默降级，不报错。** 官方原话：中途切换思考配置时 "the API doesn't
  error. Instead, it silently disables thinking for that request"，并且 "may
  strip thinking blocks that would create an invalid turn structure, or disable
  thinking when the conversation history is incompatible"。想确认这一轮到底有没有
  思考，**只能看响应里有没有 thinking block**。
- **改动 → 400。** 最新一条 assistant 消息里连续的 thinking block 序列必须与
  模型原本生成的完全一致：不能重排、编辑或部分丢弃。

对实现的含义很直接：**一个从不回传 thinking 的客户端不会看到任何错误，只会
悄悄失去思考。** 这与 DeepSeek 那种"不回传就 400"正好相反——后者会逼你修，
前者不会。

#### `redacted_thinking` 是同一个协议的一部分

安全红线触发时，部分推理会以 `redacted_thinking` block 返回，只有一个不透明的
加密 `data` 字段、没有可读文本。它**也必须原样回传**。官方专门提示：按
`block.type == "thinking"` 过滤内容块会静默丢掉它，从而打破回传协议。

#### signature 是加密后的完整思维链

`signature` 里装的是加密的完整思考内容，服务端用它验证 block 确实由 Claude 生成。
它是不透明的，不要解析；跨平台（Claude API / Bedrock / Vertex）通用；流式下作为
`signature_delta` 在 `content_block_stop` 之前到达。

这解释了为什么 `display: "omitted"` 仍能维持多轮连续性：**文本没给你，但加密的
原文在 signature 里，服务端解密后重建提示词。**

#### 旧 block 不需要自己修剪，但换模型时必须剪

传回全部 thinking block 即可，API 会自动过滤，并且**只对实际喂给模型的那些计
输入费**。保留策略按模型分两派：

- **保留全部历史回合**：Opus 4.5 及更新的 Opus、Sonnet 4.6 及更新的 Sonnet、
  Fable 5、Mythos 5。
- **只保留最后一回合**：更早的 Opus/Sonnet，以及包括 Haiku 4.5 在内的全部 Haiku。
  传回更旧的会被自动剥离。

**唯一必须自己动手的场景：对话中途换模型。** thinking block 与产出它的模型绑定，
换模型时必须剥掉此前回合的 `thinking` 与 `redacted_thinking`。别的模型不会拒绝，
只会静默忽略——**但仍然按输入 token 计费**。

#### 一次工具循环内不能切换思考配置

整个回合跑在同一个思考模式下，包括工具循环中间。要改配置，等这一回合结束。
手动模式还额外要求：思考启用的请求，其最后一个 assistant 回合必须以 thinking
block 开头（adaptive 模式取消了这条限制）。

### 3.2 ③ 族：无状态才需要自己回传

Gemini 把这件事分成两种模式：

- **有状态**（Interactions API 的 `store` + `previous_interaction_id`）：
  *"server automatically manages the conversation state, including all thought
  blocks and signatures."* 客户端什么都不用做。
- **无状态**（经典 `generateContent`，以及不开 `store` 的 Interactions）：
  *"you must include thought blocks with their signatures in subsequent requests
  to validate authenticity."* 文档还有一句更强的：*"You **MUST** always resend
  all `thought` blocks exactly as they were received from the model."*

这是四族里唯一一个**可以用服务端状态把回传义务整个免掉**的 —— 代价是历史存在
服务端（与 ② Responses 的 `store` 同构）。

对经典 surface 的实现而言，义务与 ④ 族一样是"原样、完整、不可重排"。

### 3.3 DeepSeek 的完整拼接示例

官方示例的做法是把整条响应消息直接 append 回去：

```python
messages.append(response.choices[0].message)   # 含 content / reasoning_content / tool_calls
messages.append({"role": "tool", "tool_call_id": tool.id, "content": "24℃"})
```

即：**assistant 消息上同时带 `tool_calls` 与 `reasoning_content`**，二者一起构成
那一轮。后续每一轮 user 交互都要继续带着它。

### 3.4 一个可移植的实现规则

由于 §2.1 的字段名分歧，"记住是哪个字段名 + 原样写回那个字段名"比"认准
`reasoning_content`"更耐用：**收到什么名字，就用什么名字还回去**。这条规则不需要
知道对面是哪一家，因此也不会因为下一家换了第三个名字而失效。

同理，只在**带工具调用的 assistant 消息**上回传：无工具时那些端点本就忽略它，
回传纯属多付 token。

---

## 4. DeepSeek 文档的两处自相矛盾（截至 2026-08）

记录下来，因为两处都影响实现选择，且只能靠实测定论：

**① `reasoning_effort` 在顶层还是 `thinking` 内部。**
[API 参考](https://api-docs.deepseek.com/zh-cn/api/create-chat-completion/)的顶层
参数清单里**没有** `reasoning_effort`，它被列为 `thinking:{type, reasoning_effort}`
的子字段，枚举只有 `low`/`high`/`max`。但
[思考模式指南](https://api-docs.deepseek.com/zh-cn/guides/thinking_mode)的可运行
示例把 `reasoning_effort="high"` 作为 OpenAI SDK 的具名参数传入——那会序列化到
**顶层**。合理推断是两种都收（顶层为 OpenAI 兼容别名）。

**② `reasoning_content` 的用途。** API 参考称它是"(Beta) 用于思考模式下在对话
前缀续写功能下，作为最后一条 assistant 思维链内容的输入"；思考模式指南则要求
工具调用轮必须回传否则 400。两处描述的场景不同，后者更贴近工具调用场景。

**连带的缺口**：`thinking.reasoning_effort` 的枚举里没有 `none`，而 DeepSeek 的
关闭开关是 `thinking:{type:"disabled"}` —— 一个 OpenAI 官方端点会拒绝的字段。
所以"用一个字段同时表达四族的关闭"在 ① 这一族内部就做不到。

---

## 5. 一句话小结

- 想控制**强度**：四族都有，档位名像但语义不像，且"关闭"不保证可用。
- 想拿到**思维链**：OpenAI 官方拿不到；其余三族给的是摘要；① 的兼容层字段名
  没有标准。
- **必须处理回传**：这是唯一会让请求直接失败的一件，且在工具调用场景下才触发
  —— 只读"工具调用"那一页文档的人不会看到它。
