# 05 · 工具协议与 server tools

> 本篇解决的问题：本地工具（客户端执行）在三族上的定义转换、tool_choice 翻译、流式参数拼接，以及 server tools（端点自己执行的工具，如 web_search）带来的一整类新问题——包括「一次调用 = 多次 HTTP 请求」的续跑循环。
> 不读会踩的坑：tool_call 与结果消息的配对是硬要求且**违约不自愈**——一次缺失永远留在会话历史里每轮重发，整段对话从此不可用；把 `server_tool_use` 当成欠结果的调用去回 tool_result 是协议错误；不设 `max_uses` 的服务端搜索是无上限花费；兼容层可能"响应侧抄全了、请求侧没抄"，协议规定的续跑方式恰好是它唯一不收的形状。

参考实现：simple-ai-writer `src/lib/ai/serverTools.ts`、三个适配器的工具接线（`openai.ts` / `gemini.ts` / `anthropic.ts`，尤其 anthropic.ts 的续跑循环）；协议事实见其 `docs/api/tools.md`。

---

## 1. 工具定义的统一形状与三家转换

内部统一用 OpenAI 嵌套形状：

```ts
ToolDefinition = { type: "function", function: { name, description, parameters } }
// parameters 即 JSON Schema
```

转换规则：

- **Gemini**：`tools: [{ functionDeclarations: tools.map(t => ({name, description, parameters})) }]`——同 schema，换容器。
- **Anthropic**：`{ name, description, input_schema: t.function.parameters }`——**schema 字段唯一改名的一家**（`parameters` → `input_schema`）。

## 2. toolChoice 翻译

| 内部值 | Gemini | Anthropic |
| --- | --- | --- |
| `"required"` | `mode: "ANY"` | `{type: "any"}` |
| `{type:"function", function:{name}}` | `mode: "ANY"` + `allowedFunctionNames: [name]` | `{type: "tool", name}` |

限定规则：Anthropic 只在**自己声明了（本地）工具**时才发 tool_choice——请求里只有 server tools 时发 `{type:"auto"}` 等于对端点内部决策发表意见。已知砍档方言（枚举只有 `auto|none`）的 forced 降级见第 4 篇 §4。

## 3. 流式参数拼接：三家三样

| 族 | 拼接方式 |
| --- | --- |
| ① | 按 `delta.tool_calls[].index` 分片拼 `arguments` 字符串——**分组键必须是 index 不是 id，id 自身也可能分片**（`entry.id += partial.id`） |
| ③ | 整个 `functionCall` 一次到齐（对象、无 id、适配器自造 id） |
| ④ | 按块索引拼 `input_json_delta.partial_json`；空参数调用不会流任何 delta，`""` 必须转 `"{}"` |

**参数类型分歧**：① 给 JSON 字符串（要自己 parse，可能非法——`parseJsonArgs` 全员 try/catch 兜 `{}`），③④ 给已解析对象。内部统一存字符串形态时，回传给 Anthropic 要 `parseJsonArgs(tc.function.arguments)` 转回对象。

## 4. 配对是硬要求，且违约不自愈

**每个 tool_call 必须有对应的结果消息，四族一致拒绝缺失。**

危险之处在会话历史累加：一次缺失**永远留在历史里、每轮重发**——整段对话从此不可用，且报错发生在之后的每一轮而不是出错的那一轮。

规则：任何可中途退出的实现（中止 / 异常 / 超时 / 用户取消）必须保证二选一：

- 要么 tool_call 与结果**两条都不进历史**；
- 要么调用**一定配上结果**——哪怕内容是"未执行"。

这条规则属于 agent 循环层，但适配器层要为它兜底（如 Anthropic 转换器把孤儿 tool 消息合并、name 兜底链），因为持久化的历史可能已经带伤。

## 5. Server tools：端点自己跑的工具

参考实现：simple-ai-writer `src/lib/ai/serverTools.ts`（形状为 ④ 族的 `web_search`）。

### 三原则

1. **声明而非注册**：server tool 是请求体字段 + per-model 权限配置，**不进 agent 的工具注册表**。
2. **无可执行**：runtime 的工具循环**绝不能把 `server_tool_use` 当成欠一个结果的调用**——给已完成的调用回 tool_result 是协议错误。
3. **只读上报**：对上层只做执行日志展示（搜了什么、回了什么），没有任何回传义务。

### wire 形状与 max_uses 刹车

```ts
{ type: "web_search_20250305", name: "web_search", max_uses: 10 }
```

- 与本地工具同处一个 `tools` 数组（两种条目形状并存）。
- 类型按日期版本化。**id → wire type 的映射表集中一处**——版本升级 = 一处编辑，不是存进每行模型数据里永远冻着旧版本。
- **`max_uses` 是唯一的刹车**：服务端工具不问就跑、按次计费（官方 $10/1000）+ 结果按 input token 计；一个研究型问题实测一轮 8 次搜索。即使中继文档没列这个字段也照发——这是对"只发中继文档写了的字段"规则的**刻意例外**，因为省略它的下行风险是无上限花费。

### 响应流的防御读取

- `server_tool_use` 块：query 按 `input_json_delta` 分片到达，**也有端点在 start 块整个给全——两种形状都要收**。
- `web_search_tool_result` 块：整块到达无 delta。`content` 正常是结果数组、出错时是单个 error 对象——**读取端对容器形状全防御：认不出 = 零结果，而不是抛异常炸掉已完成的响应**。
- 对外表达为两阶段 `ServerToolEvent`（`phase: "call" | "result"`），靠 `server_tool_use` 的 id 与结果块的 `tool_use_id` 配对。call 在 `content_block_stop` 时上报（此刻 query 才完整）——让执行日志在结果到达前就能显示"正在搜什么"。

## 6. pause_turn 与「一次调用 = 多次请求」的续跑循环

**「一次请求装下一个完整回答」在 server tools 下不成立**，且"装不下"有两种说法，只有一种明说：

| 信号 | 谁 | 续跑方式 |
| --- | --- | --- |
| `stop_reason: "pause_turn"` | 官方 ④ | **verbatim**：整组 content block 原样作为 assistant 消息追加回去（`encrypted_content` 一字不改——服务端靠解密它恢复模型看到的搜索内容，重建块 = 400） |
| 停在 `*_tool_result` 块上、报 `end_turn` | 某些兼容端点（MiniMax，实测 2026-08） | **transcript**：把搜索结果渲染成纯文本，以"assistant 开场白 + user 结果文本"两条普通消息送回（交替律所致必须两条；空 assistant 消息也是 400，故有兜底文案） |

### spokeSinceSearch 判据

第二种信号**没有任何字段**——只能问"**结果之后模型还说话了吗**"。`spokeSinceSearch` 刻意做成**关于文本流的事实**而非检查最后一个块：块记录依赖 `content_block_start` 到过，缺一个事件就会把"完成的 turn"误判成"没说话"而重发重计费。

### 为什么兼容端点不能走 verbatim

实测：MiniMax **拒收自己发出来的块**——`400 invalid params, tool result's tool id(...) not found`。其请求侧校验器把一切 `*_tool_result` 当客户端工具结果去找同 id 的 tool_use（响应侧实现了、请求侧没有，beta 兼容层的典型形态）。**协议规定的续跑方式恰好是它唯一不收的形状。** 纯文本 transcript 是不依赖对方懂不懂 server tools 的可移植兜底（代价：丢掉 citation 机制）。

可移植教训：**兼容层可能"响应侧抄全了、请求侧没抄"——同一个数据结构，它发得出来、收不回去。** 任何"原样回话"的设计都要准备一条纯文本降级路径。

### 续跑循环的工程约束

- **`MAX_PAUSE_CONTINUATIONS = 4`**：每次续跑是一次全新计费请求、重发整个未完成 turn 含搜索结果——这个常数同时是成本上限与循环护栏。**触顶不是错误**，turn 就地结束。
- **最后一条腿的提示词明说"这是最后机会"**——否则模型会用它宣布下一步计划而不写正文（实测 16 次搜索只换来 69 字预告）。
- **usage 跨腿求和不覆盖**：每条腿报自己的 running total，只留最新 = 只计最后一条腿，而续跑腿才是贵的。
- **对上层只有一条连续文本流** + 一个 done + `turnResumed` 诊断 chunk——"一个回答花了几次 HTTP 是传输层的事"。
- **transcript 双层长度闸**：单条结果 600 字符、整份 12,000 字符，**按结果检查预算而非按 section**——防一个长 section 挤掉后续 query 的全部命中。
- **无结果可交时不续跑**——"让模型对着同样的空气再答一次，多付一趟"。

---

## 本篇检查清单

- [ ] 工具定义内部统一 OpenAI 嵌套形状；Gemini 换容器、Anthropic 改 `input_schema`，转换各在适配器内一处。
- [ ] toolChoice 三族翻译齐全；Anthropic 仅在声明了本地工具时发 tool_choice。
- [ ] ① 族参数拼接按 index 分组、id 累积拼接；④ 族空参数 `""` → `"{}"`；`parseJsonArgs` 全员 try/catch。
- [ ] agent 循环保证 tool_call/结果配对：中止/异常/超时路径下要么双双不入历史、要么补"未执行"结果。
- [ ] server tools 走声明而非注册，不在 agent 工具注册表里；工具循环对 `server_tool_use` 不回 tool_result。
- [ ] server tool 的 id→wire type 映射集中一处，type 按日期版本化。
- [ ] 每个 server tool 声明都带 `max_uses`。
- [ ] `server_tool_use` 的 query 同时支持 delta 分片与 start 块整给两种到达形状。
- [ ] 结果块读取全防御：认不出的容器形状 = 零结果，不抛异常。
- [ ] 实现了 pause_turn verbatim 续跑（块原样回话，encrypted_content 不动），或至少把 `pause_turn` 当已知未完成态报警。
- [ ] 有 transcript 纯文本降级路径，判据是"结果之后模型说话了吗"（文本流事实，非块记录）。
- [ ] 续跑有腿数上限；触顶按正常结束处理；usage 跨腿求和；最后一腿提示词声明"最后机会"。
- [ ] transcript 有单条 + 总量双层长度闸，按结果计预算。
- [ ] 上层只见一条文本流；`turnResumed` 仅诊断用。
