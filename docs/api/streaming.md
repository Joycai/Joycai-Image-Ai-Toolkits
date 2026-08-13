# 流式：四族的机制，以及失败长什么样

> 边界见 [`README.md`](README.md)：只写协议事实。族的编号沿用
> [`landscape.md`](landscape.md)：① Chat Completions ② Responses ③ Google GenAI
> ④ Anthropic Messages。

流式这件事，四族在**两个层面**不同：增量怎么表达（§1），以及**失败怎么送达**
（§3）。第二个层面才是真正吃亏的地方——它决定了"没出错"这个判断能不能信。

## 1. 增量机制

| | ① Chat Completions | ② Responses | ③ Google GenAI | ④ Anthropic |
| --- | --- | --- | --- | --- |
| **传输** | SSE | SSE | SSE（`?alt=sse`） | SSE |
| **事件形态** | 匿名 chunk | **类型化事件** `response.*` | 匿名 chunk | **类型化事件** |
| **单个 chunk 是** | 增量（`choices[0].delta`） | 增量，事件名说明是什么的增量 | **完整响应对象** | 增量，带 block 索引 |
| **文本增量** | `delta.content` | `response.output_text.delta` | `candidates[0].content.parts[].text` | `content_block_delta` → `text_delta` |
| **工具参数** | `delta.tool_calls[].function.arguments`，**按 `index` 分片拼接** | `response.function_call_arguments.delta` | **一次给全**，不分片 | `input_json_delta` 累积 |
| **收尾** | `data: [DONE]` | `response.completed` | 流自然结束 | `message_stop` |
| **usage 何时到** | 最后一个 chunk，**且须开 `stream_options.include_usage`** | 完成事件 | 每个 chunk 都带 `usageMetadata` | 分两次：`message_start` 给输入，`message_delta` 给输出 |

### ③ 那一列容易读错

Gemini 的每个 chunk 是一个**完整的 `GenerateContentResponse`**，不是增量。
按"拼接 delta"的思路处理会重复累加。它的 `parts` 是这一片的全部内容，直接追加
即可。

### ① 的三个实现细节

- **SSE 行会被网络切开。** 一个 `data:` 行可能跨两次 read 到达，解析半行会
  静默丢掉 token 或 usage。必须把最后一个不完整行留到下次。
- **`tool_calls` 的分组键是 `index`，不是 `id`** —— `id` 本身也可能分片到达。
- **`stream_options.include_usage` 是很多兼容层没实现的第一个东西。** 不实现
  的表现不是报错，是 usage 全为 0。

## 2. 结束原因

| | 正常 | 达到上限 | 被拦 | 工具调用 |
| --- | --- | --- | --- | --- |
| **①** | `finish_reason:"stop"` | `"length"` | `"content_filter"` | `"tool_calls"` |
| **②** | `status:"completed"` | `incomplete_details.reason:"max_output_tokens"` | `…:"content_filter"` | — |
| **③** | `finishReason:"STOP"` | `"MAX_TOKENS"` | `"SAFETY"` / `"RECITATION"` / `"PROHIBITED_CONTENT"` | — |
| **④** | `stop_reason:"end_turn"` | `"max_tokens"` | `"refusal"` | `"tool_use"` |

**"达到上限"必须与"模型不听话"区分开。** 一个被截断的 JSON 回复和一个格式
错误的 JSON 回复，解析时报的是同一个错，但原因和修法完全不同（前者调高输出
上限，后者改提示词）。结束原因是唯一能区分它们的信息。

## 3. 失败怎么送达 —— 这一节是重点

**HTTP 状态码不足以判断成功。** 已知至少四种"看起来成功"的失败：

### 3.1 HTTP 200 + SSE 体内的 `error` 字段

```jsonc
data: {"error": {"message": "insufficient credits", "type": "…", "code": "…"}}
```

审核拦截、上游故障、余额耗尽都可能这样送达。不处理的话，流就在这里结束，
之前到达的部分文本与 usage 被当成一次正常的短回复。

### 3.2 HTTP 200 + `base_resp.status_code`

**同一件事的第二种拼法。** `0` 为成功，非零是失败：

```jsonc
{"base_resp": {"status_code": 1004, "status_msg": "invalid api key"}}
```

只认 `error` 字段的客户端会把**过期密钥读成一次正常的空回复**。已知 MiniMax
用这种（1004 鉴权失败、1008 余额不足、1002 限流、1039 token 超限）。

**推论：兼容层的错误通道不止一条，且没有统一约定。** 一个健壮的解析器必须把
"200 且没有任何内容"当作可疑而非成功。

### 3.3 内容拦截在文本已经开始之后到达

③ 的 `SAFETY`/`RECITATION` 与 ④ 的 `refusal` 都可能出现在**已经吐出部分文本
之后**。这意味着拦截不能只在流开始时检查——已经交给上层的文本可能需要作废。

③ 还有请求级的 `promptFeedback.blockReason`，与响应级的 `finishReason` 是两个
不同的位置。

### 3.4 静默截断输入

本地栈（ollama 等）在提示词超出上下文时**从头部丢弃**，返回 200 和一个看起来
正常的回复——而被丢掉的通常正是 system 指令。没有任何字段会说明这件事发生过。
唯一的防御是发送前自己估算并拦截。

## 4. ① 兼容层的其余已知差异

同一族内，第三方端点与官方端点的实际差异清单（截至 2026-08）：

| 差异 | 表现 |
| --- | --- |
| **思维链字段名不统一** | `delta.reasoning_content` / `delta.reasoning` / 内联 `<think>…</think>` 三种都在流通，没有一种是"标准" |
| **内联思维链会分片** | `<thi` + `nk>` 跨两个 chunk 到达是正常情况，标签匹配必须跨片 |
| **`stream_options` 未实现** | usage 全为 0，不报错 |
| **`/models` 不可信** | 返回空、返回全量目录、或返回该 key 无权访问的模型 |
| **工具调用降级** | 声明支持但不返回 `tool_calls`，或 `arguments` 不是合法 JSON |
| **枚举是子集** | 如 `reasoning_effort` 只接受官方枚举的一部分 |
| **无鉴权的本地端点** | 需要**省略** `Authorization` 头，而不是发一个空 Bearer |

## 5. 一句话小结

四族的增量机制差异是**工程量**问题，照着写就行；失败通道的差异是**正确性**
问题——因为它决定了"这次调用成功了吗"这个判断本身，而默认答案（HTTP 200 =
成功）在兼容层上是错的。
