# 工具调用（function calling）

> 边界见 [`README.md`](README.md)：只写协议事实。族的编号沿用
> [`landscape.md`](landscape.md)：① Chat Completions ② Responses ③ Google GenAI
> ④ Anthropic Messages。

一次工具调用横跨四件事，四族在每一件上都不同：**怎么声明工具**、**模型怎么
发起调用**、**结果怎么送回去**、**怎么强制或禁止调用**。

## 1. 对照

| | ① Chat Completions | ② Responses | ③ Google GenAI | ④ Anthropic |
| --- | --- | --- | --- | --- |
| **声明** | `tools[].function.{name,description,parameters}`（**嵌套**在 `function` 下） | `tools[].{type,name,description,parameters}`（**扁平**） | `tools[].functionDeclarations[]` | `tools[].{name,description,input_schema}` |
| **schema 字段名** | `parameters` | `parameters` | `parameters` | **`input_schema`** |
| **模型发起** | `assistant.tool_calls[]` | output item `type:"function_call"` | `parts[].functionCall` | content block `type:"tool_use"` |
| **调用 id** | `id` | `call_id` | **无** | `id` |
| **参数载体** | `function.arguments`（**JSON 字符串**） | `arguments`（**JSON 字符串**） | `args`（**已解析的对象**） | `input`（**已解析的对象**） |
| **结果消息** | `role:"tool"` | input item `type:"function_call_output"` | `role:"user"` 的 `parts[].functionResponse` | `role:"user"` 的 `tool_result` block |
| **结果关联** | `tool_call_id` | `call_id` | **靠函数名 `name`** | `tool_use_id` |
| **选择策略** | `tool_choice`：`none`/`auto`/`required`/`{type:"function",function:{name}}` | `tool_choice` 同形 | `toolConfig.functionCallingConfig.mode`：`AUTO`/`ANY`/`NONE`（+`allowed_function_names`） | `tool_choice.type`：`auto`/`any`/`tool`(+`name`)/`none` |
| **流式装配** | 按 `index` **分片拼接** `arguments` | `response.function_call_arguments.delta` 累积 | **整个 `functionCall` 一次给全**，不分片 | `input_json_delta` 累积 |

## 2. 三个跨族移植时会静默出错的点

**① Gemini 的工具结果没有 id。** `functionResponse` 靠 `name` 回指，所以同一轮里
并行调用同一个函数两次，"哪个结果对应哪次调用"在协议层就是不可表达的。从别族
移植过来时必须自己维护 `id → name` 的映射，并接受这个信息损失。

**② 参数是字符串还是对象，两族一半一半。** ①② 给 JSON **字符串**（要自己
`JSON.parse`，且模型可能吐出非法 JSON）；③④ 给**已解析的对象**。写一个跨族的
适配层时，这是最容易漏掉的类型分歧。

**③ 工具结果不是独立角色，只有 ① 是。** ③④ 都把结果塞进 `role:"user"` 的消息里，
② 是一个独立的 input item。按 ① 的心智模型去写 ③④ 会得到一个被拒绝的请求。

## 3. 配对是硬要求，且违反的后果是永久的

**每一个 `tool_calls`/`tool_use`/`functionCall` 都必须有对应的结果消息**，四族
一致。OpenAI 的报错原话是 "An assistant message with 'tool_calls' must be
followed by tool messages responding to each tool_call_id"，Gemini 与 Anthropic
同样拒绝。

危险之处在于**这个错误不会自愈**：会话历史是累加的，一次缺失的结果会留在历史里，
之后每一轮都带着它重发，于是整段对话从此不可用。任何可能中途退出的实现
（用户中止、异常、超时）都必须保证：要么两条消息都不写进历史，要么写进去的
调用一定配上一条结果——哪怕内容是"未执行"。

## 4. ① Chat Completions（及其兼容层）

```jsonc
// 声明
"tools": [{ "type": "function", "function": {
  "name": "get_weather", "description": "…",
  "parameters": { "type": "object", "properties": { "location": { "type": "string" } },
                  "required": ["location"] }
}}],
"tool_choice": "auto"

// 模型发起 → 结果送回
{ "role": "assistant", "content": null,
  "tool_calls": [{ "id": "call_1", "type": "function",
                   "function": { "name": "get_weather", "arguments": "{\"location\":\"Hangzhou\"}" } }] },
{ "role": "tool", "tool_call_id": "call_1", "content": "24℃" }
```

细节：

- **assistant 的 `content` 是 `nullable` 但 required** —— 字段必须存在，值可以是
  `null`。省略整个字段与发 `null` 不是一回事。
- **`tool` 消息的 `content` 是字符串**，不是对象。要送结构化结果就自己序列化。
- **流式下 `arguments` 是分片的**，按 `delta.tool_calls[].index` 拼接。同一轮的
  多个调用交错到达，`index` 是唯一可靠的分组键（`id` 也可能分片）。
- **`tools` 上限 128 个**（DeepSeek 文档明示；OpenAI 同量级）。
- `function.strict` 是可选的严格 schema 模式，兼容层普遍不实现。

### DeepSeek 的差异（截至 2026-08）

拼接流程与 OpenAI **完全一致**——官方示例就是 `messages.append(response.choices[0].message)`
再 append 一条 `{"role":"tool","tool_call_id":…,"content":…}`。`tool_choice` 的
四种取值、128 上限、`stream_options.include_usage` 都对得上。

**唯一的实质差异来自思考模式**：模型进行了工具调用时，assistant 消息里的
`reasoning_content` 必须一起回传，否则 API 返回 400。详见
[`reasoning.md`](reasoning.md) §3——这条是工具调用与思考模式的交界，
只读工具调用那一页文档不会看到它。

## 5. ③ Google GenAI

```jsonc
"tools": [{ "functionDeclarations": [{ "name": "f", "description": "…", "parameters": { /* … */ } }] }],
"toolConfig": { "function_calling_config": { "mode": "AUTO" } }

// 模型发起（role: "model"）        → 结果（role: "user"）
{ "parts": [{ "functionCall": { "name": "f", "args": {} } }] }
{ "parts": [{ "functionResponse": { "name": "f", "response": { /* … */ } } }] }
```

- `mode` 取 `ANY` 时可用 `allowed_function_names` 限定到具体函数集。
- **思考模型返回的 part 带 `thoughtSignature`，后续回合必须原样回传**，否则多轮
  工具调用失效。这意味着适配层不能把 part 归一化成自己的结构后丢弃原始对象。

## 6. ④ Anthropic Messages

```jsonc
"tools": [{ "name": "f", "description": "…", "input_schema": { /* JSON Schema */ } }],
"tool_choice": { "type": "auto" }

{ "role": "assistant", "content": [{ "type": "tool_use", "id": "toolu_1", "name": "f", "input": {} }] },
{ "role": "user",      "content": [{ "type": "tool_result", "tool_use_id": "toolu_1", "content": "…" }] }
```

- schema 字段叫 **`input_schema`**，是四族里唯一不叫 `parameters` 的。
- `tool_choice.type` 的 `any` 相当于别族的 `required`；指定单个工具用
  `{type:"tool", name}`。
- **强制工具选择只与「手动」思考模式冲突**：`thinking:{type:"enabled"}` 下用
  `tool_choice: any` 或 `tool` 会报错；**adaptive 思考支持强制工具调用**。
  这条区分很容易记反，见 [`reasoning.md`](reasoning.md) §3.1。
- **一次工具循环 = 一个 assistant 回合**，整个回合跑在同一个思考配置下，中途
  不能切换。
- 工具轮必须带上该轮的 thinking block 及其 `signature`，同 ③ 的
  `thoughtSignature`。

## 7. ② Responses

```jsonc
"tools": [{ "type": "function", "name": "f", "parameters": { /* … */ } }],   // 扁平，无 function 包装

// output 里
{ "type": "function_call", "call_id": "call_1", "name": "f", "arguments": "{…}" }
// 送回时作为 input item
{ "type": "function_call_output", "call_id": "call_1", "output": "…" }
```

工具与消息在同一个 item 流里并列，没有"assistant 消息挂一个旁路字段"这一层。
`tools` 里还可以混入服务端内置工具（`file_search`、`web_search`、`computer` 等），
它们的调用/结果也是 item 类型。
