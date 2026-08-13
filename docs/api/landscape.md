# 协议地图：四个族、部署变体、马甲层

> 边界见 [`README.md`](README.md)：本文只写协议事实。

## 1. 总览对照

| | ① Chat Completions | ② Responses | ③ Google GenAI | ④ Anthropic Messages |
| --- | --- | --- | --- | --- |
| **端点** | `POST /v1/chat/completions` | `POST /v1/responses` | `POST /v1beta/models/{m}:generateContent`<br>流式 `:streamGenerateContent?alt=sse` | `POST /v1/messages` |
| **鉴权** | `Authorization: Bearer` | 同左 | `x-goog-api-key` 头（或 `?key=`，会泄进日志） | `x-api-key` + `anthropic-version` 头 |
| **历史容器** | `messages[]` | `input[]`（或裸字符串） | `contents[]` | `messages[]` |
| **模型侧角色名** | `"assistant"` | 无角色，用 item `type` | `"model"` | `"assistant"` |
| **system 放法** | `messages[0].role = "system"`（新模型用 `"developer"`） | 顶层 `instructions` | 顶层 `systemInstruction` | 顶层 `system` |
| **文本载体** | `content` 为字符串或 part 数组 | 输入 `input_text` / 输出 `output_text` | `parts[].text` | `content` 为字符串或 block 数组 |
| **图片载体** | `{type:"image_url", image_url:{url}}` | `{type:"input_image"}` | `{inline_data:{mime_type,data}}` | `{type:"image", source:{type:"base64",media_type,data}}` |
| **工具定义** | `tools[].function.{name,description,parameters}`（**嵌套**） | `tools[].{type,name,description,parameters}`（**扁平**） | `tools[].functionDeclarations[]` | `tools[].{name,description,input_schema}` |
| **工具选择** | `tool_choice` | `tool_choice` | `toolConfig.functionCallingConfig.mode`<br>`AUTO`/`ANY`/`NONE` | `tool_choice.type`<br>`auto`/`any`/`tool`/`none` |
| **模型发起调用** | `assistant.tool_calls[]`（带 `id`） | output item `type:"function_call"`（带 `call_id`） | `parts[].functionCall`（**无 id**） | content block `type:"tool_use"`（带 `id`） |
| **结果回传** | `role:"tool"` + `tool_call_id` | input item `type:"function_call_output"` + `call_id` | `role:"user"` + `parts[].functionResponse`，**靠函数名匹配** | `role:"user"` + block `type:"tool_result"` + `tool_use_id` |
| **流式机制** | 匿名 chunk，客户端**拼接 delta**，`data: [DONE]` 收尾 | **类型化事件** `response.*` | 每个 chunk 是一个**完整响应对象**，parts 累加 | **类型化事件** `message_start` / `content_block_delta` / … |
| **结束信号** | `finish_reason`：`stop`/`length`/`tool_calls`/`content_filter` | `status` + `incomplete_details.reason` | `finishReason`：`STOP`/`MAX_TOKENS`/`SAFETY`/`RECITATION` | `stop_reason`：`end_turn`/`tool_use`/`max_tokens`/`refusal` |
| **输出上限字段** | `max_tokens` → `max_completion_tokens` | `max_output_tokens` | `generationConfig.maxOutputTokens` | `max_tokens`（**必填**，无服务端默认） |
| **usage 字段** | `prompt_tokens` / `completion_tokens` | `input_tokens` / `output_tokens` | `promptTokenCount` / `candidatesTokenCount` / `thoughtsTokenCount` | `input_tokens` / `output_tokens` + `cache_read_input_tokens` / `cache_creation_input_tokens` |
| **缓存计数口径** | cached 是 input 的**子集** | 同左 | 同左 | **三桶不重叠**，需相加才可比 |
| **服务端状态** | 无 | `store` + `previous_response_id` | 无 | 无 |

三处最容易在跨族移植时静默出错的地方：

1. **Gemini 的工具结果没有 id。** 靠函数名回指，所以同一轮里并行调用同一个函数
   两次，结果与调用的对应关系在协议层就是不可表达的。跨族适配时必须自己维护
   一张 `id → name` 表，且要接受这个信息损失。
2. **Anthropic 的 usage 三桶不重叠。** 其余三族的"cached"是 input 的子集，
   Anthropic 的 `input_tokens` 只是未命中缓存的余量。直接读 `input_tokens`
   会在长 prompt + 缓存命中时把输入量少报一个数量级。
3. **Gemini 流式每个 chunk 是完整响应对象**，不是增量。按"拼接 delta"的思路
   处理会重复累加。

## 2. ① OpenAI Chat Completions

**世界观**：一条扁平的消息数组，工具调用是 assistant 消息上的一个旁路字段。
最简单，也因此成了事实标准——几乎所有第三方"兼容 OpenAI"指的都是这一族。

```jsonc
POST /v1/chat/completions
{
  "model": "…",
  "messages": [
    { "role": "system", "content": "…" },
    { "role": "user",   "content": "…" },
    { "role": "assistant", "content": null,
      "tool_calls": [{ "id": "call_1", "type": "function",
                       "function": { "name": "f", "arguments": "{…}" } }] },
    { "role": "tool", "tool_call_id": "call_1", "content": "…" }
  ],
  "tools": [{ "type": "function",
              "function": { "name": "f", "description": "…", "parameters": { /* JSON Schema */ } }}],
  "tool_choice": "auto",
  "stream": true,
  "stream_options": { "include_usage": true }
}
```

流式：SSE，每行 `data:` 是一个匿名 chunk，`choices[0].delta` 携带增量，
**tool_calls 的 `arguments` 按 `index` 分片拼接**，最后 `data: [DONE]`。
usage 只在开了 `stream_options.include_usage` 时随最后一个 chunk 到达——
这个开关是很多兼容层没实现的第一个东西。

族内演化（同端点，不换 shape）：`max_tokens` → `max_completion_tokens`、
`function_call` → `tool_calls`、`role:"system"` → `role:"developer"`、
推理模型加 `reasoning_effort`。旧字段大多仍被接受。

## 3. ② OpenAI Responses

**世界观**：一条**条目（item）流**，而不是消息数组。推理、消息、工具调用是并列的
item 类型；服务端可以替你存住上一轮。

```jsonc
POST /v1/responses
{
  "model": "…",
  "instructions": "…",                 // system 在这里，不在 input 里
  "input": [
    { "role": "user", "content": [{ "type": "input_text", "text": "…" }] },
    { "type": "function_call_output", "call_id": "call_1", "output": "…" }
  ],
  "tools": [{ "type": "function", "name": "f", "parameters": { /* … */ } }],  // 扁平，无 function 包装
  "reasoning": { "effort": "medium", "summary": "auto" },
  "text": { "format": { "type": "json_schema", /* … */ } },
  "max_output_tokens": 4096,
  "store": false,
  "previous_response_id": "resp_…",
  "stream": true
}
```

响应的 `output[]` 是 item 数组，常见类型：`reasoning`（含 `summary[]`，无状态模式下
还有 `encrypted_content`）、`message`（`content[]` 里是 `output_text` 或 `refusal`）、
`function_call`（带 `call_id`）。

流式是**类型化命名事件**（`response.output_text.delta`、
`response.function_call_arguments.delta`、`response.completed` 等），
不需要客户端猜哪个字段是增量——这是它相对 Chat Completions 的主要工程改善，
也是两族无法合并的主要原因。

**有状态**是另一个分水岭：`store: true` + `previous_response_id` 让客户端不必
回传完整历史。代价是历史存在服务端，且这条路径在任何第三方兼容层都不存在。

## 4. ③ Google GenAI

**世界观**：`contents` 是回合数组，每回合由 `parts` 组成；**part 是唯一的内容单位**，
文本、图片、工具调用、工具结果都是 part。生成参数集中在 `generationConfig`。

```jsonc
POST /v1beta/models/{model}:streamGenerateContent?alt=sse
{
  "system_instruction": { "parts": [{ "text": "…" }] },
  "contents": [
    { "role": "user",  "parts": [{ "text": "…" }] },
    { "role": "model", "parts": [{ "functionCall": { "name": "f", "args": {} } }] },
    { "role": "user",  "parts": [{ "functionResponse": { "name": "f", "response": { "content": "…" } } }] }
  ],
  "tools": [{ "functionDeclarations": [{ "name": "f", "description": "…", "parameters": { /* … */ } }] }],
  "toolConfig": { "function_calling_config": { "mode": "AUTO" } },
  "generationConfig": { "maxOutputTokens": 4096, "thinkingConfig": { /* … */ } },
  "safetySettings": [ /* … */ ]
}
```

### 4.1 ③ 族有两套 surface（截至 2026-08）

Google 上线了 **Interactions API**，与经典 `generateContent` 并存：

| | 经典 `generateContent` | Interactions |
| --- | --- | --- |
| 端点 | `/v1beta/models/{m}:generateContent` | `POST /v1beta/interactions` |
| 输入 | `contents[]`（Content + Part） | `input` |
| 输出 | `candidates[0].content.parts[]` | `steps[].content[]` |
| 多轮 | 客户端回传完整历史 | `previous_interaction_id`，**服务端存状态** |
| 结构化输出 | `generationConfig.responseMimeType/Schema` | 顶层 `response_format[]` |
| 流式 | `:streamGenerateContent` | 同端点 + `stream=true` |
| 思考 | 见下 | `generation_config.thinking_level` / `thinking_summaries` |

官方定位：*"The Interactions API is now generally available. We recommend using
this API for access to all the latest features and models."* 但同时明确
**经典 surface 不弃用**：*"While `generateContent` remains fully supported, we
recommend the Interactions API for all new development."*

**这与 ② Responses 对 ① Chat Completions 的关系高度同构**：同一厂商的第二套
接口、结构不兼容、有服务端状态、官方推荐新项目使用、旧的继续支持。按
[`README.md`](README.md) 的分类法，它够格算独立的一族 —— 但本目录暂不拆分，
因为本项目尚未接入，且拆分会让每张对照表多一列空格。**接入时再拆。**

#### 一个实践后果：Gemini 3+ 的思考文档只讲 Interactions

`generateContent` 上如何为 Gemini 3 配置思考，官方文档已经不再给示例。文档
只承认两者不同：*"The Interactions API handles thoughts and signatures
differently than the `generateContent` API"*，并称在 `generateContent` 里
*"there are no dedicated thought blocks"* —— 签名改为附着在 `functionCall`
或最终响应等 part 上。

**所以"经典 surface 上 Gemini 3 的思考长什么样"目前只能靠实测确定**，这是本
目录里少数几处"官方文档给不出答案"的地方之一。

三个别族没有的东西：

- **`safetySettings`** 是请求级的安全阈值，且**默认会拦**。别族的安全策略不可配。
  被拦时可能是 `promptFeedback.blockReason`（请求级）或 `candidates[0].finishReason`
  为 `SAFETY`/`RECITATION`（响应级），后者可能在已经吐出部分文本之后才到。
- **thought signature** —— 思考模型返回的 part 带 `thoughtSignature`，后续回合
  **必须原样回传**，否则多轮工具调用会失效。这意味着适配层不能把 part 归一化成
  自己的结构后丢弃原始对象。
- **模型名在 URL 里**，不在 body 里。换模型换的是路径。

## 5. ④ Anthropic Messages

**世界观**：`content` 是 block 数组，block 有类型（`text` / `image` / `tool_use` /
`tool_result` / `thinking`）。`system` 独立于 `messages`。

```jsonc
POST /v1/messages
Headers: x-api-key: …, anthropic-version: 2023-06-01
{
  "model": "…",
  "max_tokens": 4096,                        // 必填
  "system": "…",                             // 或 block 数组（可挂缓存断点）
  "messages": [
    { "role": "user", "content": "…" },
    { "role": "assistant", "content": [{ "type": "tool_use", "id": "toolu_1", "name": "f", "input": {} }] },
    { "role": "user", "content": [{ "type": "tool_result", "tool_use_id": "toolu_1", "content": "…" }] }
  ],
  "tools": [{ "name": "f", "description": "…", "input_schema": { /* JSON Schema */ } }],
  "tool_choice": { "type": "auto" },
  "stream": true
}
```

流式是类型化事件：`message_start` → (`content_block_start` →
`content_block_delta`* → `content_block_stop`)* → `message_delta` → `message_stop`，
delta 类型包括 `text_delta`、`input_json_delta`（工具参数）、`thinking_delta` /
`signature_delta`（思维链）。usage 分两次到：`message_start` 给输入，
`message_delta` 给最终输出。

特有约束：

- **`max_tokens` 必填**且没有服务端默认值。适配层必须自带一个兜底常量。
- **工具结果放在 `role:"user"` 消息里**，不是独立角色。
- **prompt caching 是显式的**：在 system / tools / messages 上打 `cache_control`
  断点。别族的缓存是自动的、不可控的。
- **思维链 block 在工具调用轮必须原样回传**（含 `signature`），与 Gemini 的
  thought signature 是同一类要求。

## 6. 部署变体（body 同族，外壳不同）

| 部署 | 族 | 差异 |
| --- | --- | --- |
| **Azure OpenAI** | ① | `api-key` 头（非 Bearer）、`?api-version=` 查询串、URL 里是 **deployment 名**而非模型名 |
| **Gemini Developer API** | ③ | `x-goog-api-key`，模型名形如 `gemini-…` |
| **Vertex AI (Gemini)** | ③ | OAuth 令牌、区域化域名、路径含 `projects/{p}/locations/{l}/publishers/google/models/…` |
| **Vertex / Bedrock 上的 Claude** | ④ | body 里**没有 `model`**（在路径里），改用 `anthropic_version` 字段；鉴权走各云的体系 |

这一轴的判断方法：**能不能只改 URL 与鉴权头就跑通？** 能，就是部署变体；
不能，就是另一个族。

## 7. 马甲层：谁兼容了谁

事实标准是 ①。以下都提供 Chat Completions 兼容端点：

DeepSeek、xAI (Grok)、Mistral、Moonshot (Kimi)、智谱 GLM、MiniMax、
阿里 DashScope（另有原生格式）、OpenRouter、以及本地栈 Ollama / LM Studio /
vLLM / llama.cpp。Google 与 Anthropic 也各自提供了一层 OpenAI 兼容端点。

**兼容 ≠ 等价。** 实际差异集中在这几处：

| 差异 | 表现 |
| --- | --- |
| **私有扩展字段** | DeepSeek 加 `reasoning_content` + `thinking`；OpenRouter 加 `reasoning`、`provider` 路由与 `reasoning_details`；各家推理字段互不相同 |
| **usage 缺失** | 不认 `stream_options.include_usage`，或返回全零 usage |
| **`/models` 不可信** | 返回空、返回全量目录、或返回该 key 无权访问的模型 |
| **工具调用降级** | 声明支持但实际不返回 `tool_calls`，或 `arguments` 不是合法 JSON |
| **HTTP 200 + SSE 内错误** | 余额不足、上游故障、内容审核以 `data: {"error":…}` 事件送达，而非错误状态码 |
| **静默截断 prompt** | 本地栈（ollama 等）超出上下文时从头部丢弃，system 指令先没 |
| **`<think>` 内联** | 部分中继把思维链混进正文，用 `<think>…</think>` 包裹 |

**结论：对 ① 的适配必须按"最小公倍数发送、最大宽容接收"写。** 官方端点可以
乐观假设可选部分存在，兼容端点不行。

### 一个具体样本：New API（截至 2026-08）

自建中继里最常见的一种，值得记下来作为"兼容层长什么样"的标本。
[它的文档](https://www.newapi.ai/zh/docs/api/ai-model/chat/openai/createchatcompletion)
自称"兼容 OpenAI Chat Completions API"，实测对照下来：

- **body 形状与官方逐字相同**：同为 `POST /v1/chat/completions`、`Bearer` 鉴权、
  同一套字段。**没有任何结构性差异** —— 这正是兼容层的典型形态，也是"兼容层
  不配拥有独立协议族"的理由。
- **它列为"特有扩展"的四项全在响应侧**：`message.reasoning_content`（DeepSeek
  那一份扩展的传播结果）、`completion_tokens_details.reasoning_tokens`、
  以及 `usage` 里的 `audio_tokens` / `image_tokens`。
- **`reasoning_effort` 的取值只写了 `low`/`medium`/`high`** —— 官方枚举里的
  `none`/`minimal`/`xhigh`/`max` 都不在文档中。是中继只描述了公共子集，还是真
  只接受这三个，文档没说。
- **文档缺口**：流式响应格式整节缺失，`tools`/`tool_choice`/`response_format`/
  `stream_options` 的结构都只列了字段名不展开。

这四条合起来就是兼容层的典型知识形态：**结构上照抄，扩展在响应侧，枚举是子集，
而最需要确认的部分文档不写。** 只能实测。

### 另一个样本：MiniMax（截至 2026-08）

同样是 `POST /v1/chat/completions` + Bearer，body 形状与官方一致。但它暴露了
两个**兼容层普遍存在、而官方端点不会有**的行为，值得单独记：

- **思维链默认内联在 `content` 里**，形如
  `<think>…</think>\n\n正式回答`。流式下标签也是从 `delta.content` 分片到达
  的（`<thi` + `nk>` 属于正常情况）。它有 `reasoning_split: true` 可把思考拆到
  `reasoning_content` / `reasoning_details`，但那是私有字段。
  **含义**：任何把 `delta.content` 直接当作正文的消费者，都会把模型的思考过程
  一并收下。
- **失败用 `base_resp.status_code` 报告，HTTP 状态仍是 200。**
  `0` 为成功，`1004` 鉴权失败、`1008` 余额不足、`1002` 限流、`1039` token
  超限。这是"200 + 体内错误"的**第二种拼法**（第一种是 `error` 字段），一个只
  认 `error` 的客户端会把过期密钥读成一次正常的空回复。
- 思考开关是 `thinking: {type: "disabled"|"adaptive"}`（与 DeepSeek、Anthropic
  同形），**没有 `reasoning_effort`**。M2.x 系列的思考无法关闭。
- `max_tokens` 已弃用，改用 `max_completion_tokens`。
- 多模态多一个 `video_url` 内容块类型。

**这两条合起来说明一件事**：兼容层的差异往往不在请求体，而在**响应的解释方式**
——同一段 JSON，官方端点和兼容端点想让你读出不同的东西。

### 第三个样本：兼容层也做 ④ 族（截至 2026-08）

前两个样本（New API 的 OpenAI 格式、MiniMax）都是 ① 族。中继同样会提供
**Anthropic 原生格式**的端点，New API 的
[`POST /v1/messages`](https://www.newapi.ai/zh/docs/api/ai-model/chat/createmessage)
即是。对照官方：

- **鉴权两套都收**：`Authorization: Bearer` 与 `x-api-key` 都接受。这印证了
  ④ 族兼容端点需要一个鉴权方式开关——官方端点只认 `x-api-key`，而生态里
  `ANTHROPIC_AUTH_TOKEN → Bearer` 同样是一等约定，网关文档常常不说自己要哪个。
- **`anthropic-version` 请求头必填**，与官方一致。
- **`usage` 的四个桶齐全**（`input_tokens` / `output_tokens` /
  `cache_creation_input_tokens` / `cache_read_input_tokens`），说明它没有把
  Anthropic 那套"三桶不重叠"的口径压平成 OpenAI 的形状。
- **`thinking` 列在请求体里**，但 **`output_config` 没有** —— 而 4.6+ 的
  `effort` 就住在那里面。
- **`temperature` / `top_p` / `top_k` 被列为可用**，而官方 4.6+ 对这三个的
  非默认值**无条件 400**（与是否思考无关）。
- 响应的 content block 只画了 `{type, text}`：`thinking`、`redacted_thinking`、
  `signature` 一个都没提，流式事件也没写。

### 第四个样本：MiniMax 的 ④ 族端点（截至 2026-08）

同一家厂商**同时提供 ① 与 ④ 两种格式**（`/v1/chat/completions` 与
`/anthropic/v1/messages`），是"协议族与厂商正交"最直白的证据：选哪个族是调用方
的事，不是厂商的属性。

与官方 ④ 的差异：

- **端点带前缀**：`/anthropic/v1/messages`，不是 `/v1/messages`。
- **`anthropic-version` 不要求**（官方必填）。多发一个头无害，少发在官方会挂。
- **鉴权 Bearer 与 `x-api-key` 都收**，与 New API 一致 —— 两个 ④ 族兼容层
  样本都这样，可见这个开关不是个例需求。
- **`thinking: {type: "disabled" | "adaptive"}`**，**默认 `disabled`**。
  官方那边当前代默认开或需显式 adaptive，这里必须显式开才有思考。
  `display` 字段没有出现在文档里。
- **`tool_choice` 只有 `auto` / `none`** —— **没有 `any`，也没有 `tool`**。
  这是与官方差距最大的一条：**强制单个工具在这里做不到**，任何依赖
  forced tool 的结构化输出都得有退路。
- **没有 `output_config`**，所以 effort 无处安放（与 New API 相同）。
- **thinking block 带 `signature`，且文档明确"多轮续写必需"** —— 回传规则与
  官方一致，这一点是兼容的。
- usage 四个桶齐全；流式事件名与官方一致，多一个 `ping` 心跳。
- 扩展：`service_tier`（priority 1.5 倍价）、`metadata.user_id`、`system` 接受
  带 `cache_control` 的数组。

**最值得记住的一条**：④ 族兼容层可能**砍掉 `tool_choice` 的强制档**。官方的
`any` / `tool` 是结构化输出最可靠的手段（见
[`structured.md`](structured.md) §1），而这里没有 —— 于是"强制工具调用失败就
退回 JSON 模式"从一个防御性设计变成了必需品。

### 第五个样本：New API 的 ③ 族端点（截至 2026-08）

路径与官方一致（`/v1beta/models/{m}:generateContent`、
`:streamGenerateContent?alt=sse`），body 结构照抄。两处差异都会**静默失败**：

- **鉴权用 `Authorization: Bearer`，不是 `x-goog-api-key`。** 这是 401 ——
  唯一一个会响的。但它同时打到聊天、模型列表、能力探测与图像四条路径，
  只改一处会得到"能聊天但拉不到模型列表"这种难懂的半残状态。
- **文档只写 camelCase**（`inlineData` / `mimeType`）。Google 自己两种都收
  （proto3 JSON 允许），中继未必。**而未识别的键是被忽略而不是被拒绝的** ——
  发 `inline_data` 的后果不是报错，是图片压根没到模型那里。

第二条是本目录里"静默失败"的最纯粹形态：请求成功、响应正常、模型只是看不见
你发的图。

**由此得出一条可移植的规则：面向兼容层时，在"官方两种都收"的地方要选中继
文档写的那一种。** 官方的宽容不是中继的宽容。

### 兼容层文档的通用规律（五个样本的共同点）

1. **结构照抄，扩展在响应侧。**
2. **枚举是子集**（reasoning_effort 只写三档、content block 只写 text）。
3. **最需要确认的部分不写**（流式格式、错误通道、回传规则）。
4. **文档滞后于上游。** ④ 族尤其明显——Anthropic 的接口面近年动得快
   （adaptive thinking、`output_config`、采样参数从"思考时禁用"变成"无条件
   禁用"），中继文档描述的往往是一年前的样子。

**推论：不能把兼容层文档当作能力清单。** "没列"既可能是不支持，也可能只是
没跟上；两种都要按"未知、需实测"处理，而不是按"确认缺失"。
## 8. 仍存活的自有格式（不主流，但会撞上）

- **Ollama `/api/chat`** —— 自有 shape（`messages` + `options`），与它的
  OpenAI 兼容层并存。原生接口能拿到 `num_ctx` 之类的本地参数。
- **Cohere `/v2/chat`** —— 自有 shape。
- **阿里 DashScope 原生** —— `input.messages` + `parameters` 两段式。
- **AWS Bedrock Converse `POST /model/{id}/converse`** —— 实际上是第五种独立
  body：`system` 是独立数组、content 恒为 block 数组、camelCase 命名、
  `inferenceConfig` / `toolConfig` 分组、`additionalModelRequestFields` 兜住厂商
  私有参数、usage 为 `inputTokens`/`outputTokens`/`cacheReadInputTokens`。
  设计意图与 OpenAI 兼容层相同（一次对接跑所有模型），但需要 SigV4 签名，
  在纯前端环境里成本高。**本目录不展开。**
