# 05 · 工具协议与 server tools

> 本篇解决的问题：本地工具（客户端执行）在各族上的定义转换、tool_choice 翻译、流式参数拼接，以及 server tools（端点自己执行的工具，如 web_search）带来的一整类新问题——包括「一次调用 = 多次 HTTP 请求」的续跑循环。
> 不读会踩的坑：tool_call 与结果消息的配对是硬要求且**违约不自愈**——一次缺失永远留在会话历史里每轮重发，整段对话从此不可用；把 `server_tool_use` 当成欠结果的调用去回 tool_result 是协议错误；不设 `max_uses` 的服务端搜索是无上限花费；兼容层可能"响应侧抄全了、请求侧没抄"，协议规定的续跑方式恰好是它唯一不收的形状。

出处：simple-ai-writer `src/lib/ai/serverTools.ts`、三个适配器的工具接线（`openai.ts` / `gemini.ts` / `anthropic.ts`，尤其 anthropic.ts 的续跑循环）；协议事实见其 `docs/api/tools.md`。

目录：
- §1 工具定义的统一形状与三家转换
- §2 toolChoice 翻译
- §3 流式参数拼接：三家三样（含 ③ 的调用 id、并行签名、流末空 part 与回灌实测；④ `tool_use` 的 `caller`）
- §4 配对是硬要求，且违约不自愈（维护见 agent-runtime-architecture 07 §3.2）
- §5 Server tools：端点自己跑的工具
  - 三原则 · 同一个 id，两种拼法 · ② Responses 族：可见的内置工具
  - 代码解释器：按模型 id 放行、按请求丢弃（千问 DashScope）
  - wire 形状与 max_uses 刹车（④ 族，含无 beta 头的实测形状与 `usage.server_tool_use`） · 响应流的防御读取（含事件 id 跨请求唯一、内容会长的行固定 id 重发）
  - ③ Gemini 的内置工具：`googleSearch` / `codeExecution` / `urlContext` 的请求形状（`tools[]` 独立项）、同发组合、回报位置、按条计费、代码 part 回灌、app id 映射、日志 id 前缀
  - 服务端工具归平台，不归模型；「应用执行」的联网端点（智谱）
  - 中转站自己「做」服务端工具：劫持、真搜、丢弃三种情形，以及「假装执行」（New API · Kiro 渠道）；同台四个渠道四种答案
  - 中转站上的 GPT 内置工具随上游：账号池真搜、网关静默丢；① `web_search_options` 处处被忽略；代码解释器 / 文件搜索 / 出图的报法
- §6 pause_turn 与「一次调用 = 多次请求」的续跑循环
- §7 工具按需加载（deferred loading / tool search）的各族协议事实

---

## 1. 工具定义的统一形状与三家转换

内部统一用 OpenAI 嵌套形状：

```jsonc
{ "type": "function", "function": { "name": "…", "description": "…", "parameters": { /* JSON Schema */ } } }
```

转换规则：

- **Gemini**：`{"tools":[{"functionDeclarations":[{name, description, parameters}, …]}]}`——同 schema，换容器。
- **Anthropic**：`{ name, description, input_schema: t.function.parameters }`——**schema 字段唯一改名的一家**（`parameters` → `input_schema`）。
- **② Responses**：扁平 `{ type:"function", name, description, parameters, strict: false }`——去掉 `function` 包装，且 **`strict:false` 必须显式**（省略即自动 strict，见第 2 篇 §7.1）。命名 tool_choice 同样扁平：`{type:"function", name}`。

## 2. toolChoice 翻译

| 内部值 | Gemini | Anthropic |
| --- | --- | --- |
| `"required"` | `mode: "ANY"` | `{type: "any"}` |
| `{type:"function", function:{name}}` | `mode: "ANY"` + `allowedFunctionNames: [name]` | `{type: "tool", name}` |

限定规则：Anthropic 只在**自己声明了（本地）工具**时才发 tool_choice——请求里只有 server tools 时发 `{type:"auto"}` 等于对端点内部决策发表意见。已知砍档方言（枚举只有 `auto|none`）的 forced 降级见第 4 篇 §4。

forced 被接受 ≠ forced 生效：中转站的翻译层可能只在**非流式**路径上实现强制（Kiro 渠道的 Claude，① `required` / 具名与 ④ `any` / `tool` 都一样，
流式下 200 但被无视）【实测 2026-09-23】——数字与降级做法见第 4 篇 §4「第四种变体」。
同一台中转站别的渠道各不相同：anti 渠道非流式也不生效，CC 渠道带思考时时好时坏，Bedrock 正向全生效（同节「复测与同台别的渠道」）。

② 族的 tool_choice 见第 2 篇 §7.1（规则 4：命名形态扁平、只随函数工具发、不做预判降级）。

## 3. 流式参数拼接：三家三样

| 族 | 拼接方式 |
| --- | --- |
| ① | 按 `delta.tool_calls[].index` 分片拼 `arguments` 字符串——**分组键必须是 index 不是 id，id 自身也可能分片**（`entry.id += partial.id`） |
| ③ | 整个 `functionCall` 一次到齐（对象；旧型号无 id、适配器自造 id；**Gemini 3.8 起带 `id`**，见下） |
| ④ | 按块索引拼 `input_json_delta.partial_json`；空参数调用不会流任何 delta，`""` 必须转 `"{}"` |

② 族按 `output_index` 分组、参数以 `.done` 整串为准，见第 2 篇 §7.2。

**③ 的调用与回灌**（Gemini 3.8 Flash，Vertex 后端经 OrcaRouter，【实测 2026-09-26】；网关回包原样、请求侧会重新序列化，第 1 篇 §9.5）：

- **`functionCall` 带 `id`**（形如 `call_1626125`）。回灌时 `functionResponse` 带不带 `id` 都 200，两边都去掉 id 也 200，按顺序配对。
  所以：有 id 就用 id 配对（同名函数的并行调用从此可表达），没有 id 仍按函数名（第 2 篇 §2.2）。
- **并行调用时 `thoughtSignature` 只挂在第一个 `functionCall` part 上**；其余 part 没有签名是正常的，不要补、不要挪。
- **流以一个光秃秃的 `{text: ""}` part 收尾。** 把它原样回灌 → 400 `required oneof field 'data' must have one initialized field`；
  带签名的 `{text: "", thoughtSignature}`（流式时签名单独落在最后一块上）回灌 200。后者的形态提示可能是网关把空串当空值丢了、只剩 `{}`，
  未必是 Vertex 本身——但这个 part 什么都不带，**回灌时剔除它在哪都不亏**。
  规则：「整组原样回灌」（第 3 篇 §5）的唯一例外是**既无文本、也无签名 / 调用 / 其他数据的空 part**；带签名的空文本 part 保留。
  **读已存的历史时也要过滤**——修复前存下的会话里已经带着它，只改写侧的话，旧会话照样第二轮 400。
- 缺签名的回灌是 **HTTP 400** `Function call is missing a thought_signature in functionCall parts`（第 3 篇 §5）。
- 上面「会不会 400」的结论都是经网关得到的，只对网关成立；回包形状（`id`、签名位置、空 part）可当官方记。

**④ 的 `tool_use` 多了 `caller: {"type": "direct"}`**（程序化工具调用的来源标记，【实测 2026-09-26】，Sonnet 5 经 OrcaRouter，回包原样）：
整块原样存；回灌时去掉它经网关也 200。thinking + 并行工具的回灌规则（改签名 400）见第 3 篇 §5 ④ 行。流式时工具参数的第一条 `input_json_delta` 是空串。

**参数类型分歧**：① 给 JSON 字符串（要自己 parse，可能非法——`parseJsonArgs` 全员 try/catch 兜 `{}`），③④ 给已解析对象。内部统一存字符串形态时，回传给 Anthropic 要 `parseJsonArgs(tc.function.arguments)` 转回对象。

**① 族中转的两种畸形调用（Joycai 线上流量）**：

- **参数是背靠背拼接的多个 JSON 对象**，如 `{}{"id":1}`——经中转的 Claude 后端先吐一个空对象占位，再给真参数【实测 2026-08-08】。
  普通 JSON 解析因尾部多余数据失败，兜底成 `{}` 后工具以**空参数**执行，不报错。对策：解析失败时按括号深度（跳过字符串内的括号与转义）
  切出顶层对象，左到右合并（后者的键覆盖前者）；切不出两个以上对象才判非法（坑 105）。
- **调用 id 是空串 `""` 而不是缺失**：`id ?? "call_"+i` 式的兜底保留了空串，同一批两个调用共用空 id，**下一轮**请求因重复
  `tool_call_id` 被拒【实测 2026-08，中转流量】。错误出现在下一轮而不是这一轮，且历史是累积的——整段会话从此每轮都 400。空串按缺失处理（坑 106）。

## 4. 配对是硬要求，且违约不自愈

**每个 tool_call 必须有对应的结果消息，四族一致拒绝缺失。** 不变量的维护（abort 补桩、配对修复）属于 agent 循环层，见 agent-runtime-architecture 07 §3.2。
适配器层也要兜底（如 Anthropic 转换器把孤儿 tool 消息合并、name 兜底链），因为持久化的历史可能已经带伤。

## 5. Server tools：端点自己跑的工具

出处：simple-ai-writer `src/lib/ai/serverTools.ts`（④ 族的 `tools[]` 条目形状 + ① 族兼容层的 `enable_search` / `enable_code_interpreter` 形状 + ② 族内置工具，同一模块）。

### 三原则

1. **声明而非注册**：server tool 是请求体字段 + per-model 权限配置，**不进 agent 的工具注册表**。
2. **无可执行**：runtime 的工具循环**绝不能把 `server_tool_use` 当成欠一个结果的调用**——给已完成的调用回 tool_result 是协议错误。
3. **只读上报**：对上层只做执行日志展示（搜了什么、回了什么），没有任何回传义务。

### 同一个 id，两种拼法——族决定 spelling

app 层的 id 只有一个（如 `"web_search"`），因为它表达的意思只有一个：「这个模型
获准每次回答自行上网」。**能力路由、子代理资格判定读的都是这个 id**，与哪条 wire
无关。拼法交给按族的 shaping 函数，与 `jsonModeShaping` 同一收口思路：

- **④ 族**：`tools[]` 里的版本化条目（`anthropicServerTools`，下节）。
- **① 族兼容层（千问 DashScope）**：请求体**顶层** `enable_search: true`
  （`openaiServerToolsBody`；SDK 文档写在 `extra_body`，落 wire 即顶层字段）。
- **③ 族**：`tools[]` 里与 `functionDeclarations` 并列的独立项 `{googleSearch:{}}` / `{urlContext:{}}` / `{codeExecution:{}}`（`geminiServerTools`，下文「③ Gemini 的内置工具」）。

**官方/兼容的收窄方向在两族相反，而推理相同。** ④ 族的设置**不**收窄到 compat 半边
——官方 api.anthropic.com 真有同形状的 server tools，声明给官方端点是合法的。
① 族则必须**只放行 compat**：`enable_search` 是 DashScope 私有扩展，
api.openai.com 对未知顶层参数直接 400——同一条「设置只出现在适配器不会丢弃它的
地方」的规则，按各族事实给出相反答案。适配器侧再守一道（config 层拒存不够：
配置行会经导入/手改旅行）。

**① 族兼容层的诚实差别：搜索无痕。** 千问文档明载 Chat Completions 模式**不返回
搜索来源、不支持角标**——没有任何 `ServerToolEvent` 可解析，「不生效」完全无症状（见 11 篇坑 10）。
也没有 `max_uses` 等价物可发——DashScope 未文档化任何单请求搜索上限，但其
按次计价比 Anthropic 低三个数量级，缺这个刹车不构成同级风险。

### ② Responses 族：可见的内置工具，两家同名不同集

出处：`serverTools.ts` 的 `responsesServerTools` / `responsesServerToolEvent` / `supportsServerTool`；
实测见 `landscape.md` 第六个样本「联网搜索与网页抓取」「图片搜索」「代码解释器」、`responses.md` §10。

拼法：函数工具之后追加裸 `{type}` 条目，与函数工具同处 `tools[]`。**app 层 id 与该族 wire type 同名**，
但**每个 id 能到达哪条 wire 要按 standard 逐个过滤**（`supportsServerTool`），而不是信任配置行：

| app id | `openai_responses`（官方） | `openai_responses_compat`（千问 DashScope） | ① `openai_compat`（千问） |
| --- | --- | --- | --- |
| `web_search` | ✅ OpenAI 自家 | ✅ | `enable_search: true` |
| `web_extractor`（网页抓取） | ❌ 过滤掉 | ✅ 仅当 `web_search` 同在 | `search_options:{search_strategy:"agent_max"}`，**本轮带函数工具时不发**（只剩 `enable_search`） |
| `web_search_image`（以文搜图） | ❌ | ✅ 可单独 | ❌（猜的字段被静默忽略） |
| `image_search`（以图搜图） | ❌ | ✅ 可单独 | ❌ |
| `code_interpreter`（代码解释器） | ❌（OpenAI 同名工具要 `container`，不是这个工具） | ✅ **按模型 id 放行**；思考关闭时本轮不发 | `enable_code_interpreter: true`，**按模型 id 放行**；本轮带函数工具时不发 |

规则与理由：

- **抓取离不开搜索**：DashScope 三条线都拒单独的 `web_extractor`（② 面是 HTTP 200 后首个事件 `response.failed`）。
  所以它存成 `web_search` 的**附加档**，归一化时单独出现就丢弃（`normalizeServerTools`），发送前再归一化一次。
- **① 面 `agent_max` 按模型分**：qwen3.8-flash 400 `does not support the "agent" search strategy`，qwen3-max / qwen3.5-plus 收；
  不带策略的 `enable_search` 在 qwen3-max 上**根本没搜**（输入 29 token，凭记忆作答）。400 发生在流开始前、作者看得见，
  **不做降级重试**——那等于悄悄收回作者开的能力。
- **① 面 `agent_max` 与函数工具互斥**（2026-09-17 实测）：`agent_max` 是 DashScope 的「agent 模式」，
  和 `tools` 同发一律 400 `Agent mode does not support tools. You need to either avoid using enable_code_interpreter or avoid using the agent mode with enable_search.`
  这与上一条不同——是**请求形状**决定的必然失败，不是模型能力问题，所以适配器**按请求**丢掉策略：本轮带函数工具就只发
  `enable_search`（带工具的普通搜索实测正常），agent / 对话轮只搜不抓；不带函数工具的搜索子代理照常抓取。
  只测不带工具的请求会把这个坑藏住——它让每个 agent 运行第一轮就挂（见 11 篇坑 74）。
- **官方线只放 `web_search`**：其余三个是 DashScope 的名字，行经导入或换 standard 旅行到官方端点时由适配器滤掉。
- **图片搜索单独开关**：按次价是搜索的 6–12 倍，所以不挂在搜索下面；只声明不触发是安全的（纯文字请求不会调用），可以做成按模型常开。

响应侧——**可见**，这是 ② 面相对 ① 面搜索无痕的根本差别。按条目类型折成两阶段 `ServerToolEvent`（`output_item.added` → call，`output_item.done` → result），**这些条目不回传**：

| 条目 | call 阶段 input | result 阶段 |
| --- | --- | --- |
| `web_search_call`，`action.type:"search"` | `action.queries[]`；缺失时退回单数 `action.query`（OpenAI 有时只给单数） | `action.sources[{type:"url",url}]`，**无标题**（标题=URL）、去重 |
| `web_search_call`，`action.type:"open_page"` / `"find_in_page"`（OpenAI、xAI） | `{url}`（+ `pattern`），**没有 queries / sources** | `[{title:url, url}]` |
| `web_extractor_call` | `urls[]` + `goal` | `output`（端点按 goal 提炼的正文，非原始 HTML）；读不到页面不是错误 |
| `web_search_image_call` / `image_search_call` | `arguments` 是 **JSON 字符串**（`{queries}` / `{img_idx, bbox}`） | `output` 也是 **JSON 字符串** `[{title,url,index}]`；`"[]"` = 没搜到，不是错误 |
| `code_interpreter_call`（DashScope） | `code`（added 时已完整） | `outputs[{type:"logs",logs}]`，剥掉外层代码围栏；异常照样 `completed`；OpenAI 形态的 `{type:"image",url}` 当命中读 |

防御读取同 ④ 族：解析不了的 JSON 字符串 = 空对象 / 零结果，不炸已完成的回答；条目缺 `id` 用 `output_<index>` 兜底让两阶段配上。
不按 `open_page` 解析的后果是静默的：执行日志显示一个空查询、空结果。

OpenAI 官方 `web_search`（【实测 2026-09-26】，`gpt-6-luna` 经 OrcaRouter，两条线路，第 1 篇 §9.5）：事件 `web_search_call` 的 `in_progress` / `searching` / `completed` 齐全，
正文带 `url_citation` 注解；`action.sources` 要发 `include:["web_search_call.action.sources"]` 才有；原样线路的 `usage.input_tokens_details` 多一个
`cache_write_tokens`（一次 4,388，06 §1）。

（自 11 篇坑 70 移入）DashScope ② 面单独声明 `web_extractor` 的报错原文：HTTP 200 后首个事件 `response.failed`，message `must be executed with web_search tool`。

### 代码解释器：按模型 id 放行、按请求丢弃（千问 DashScope）

出处：`serverTools.ts` 的 `supportsCodeInterpreter` / `supportsServerToolFor` / `codeInterpreterEvent`；
实测见 `landscape.md` 第六个样本「代码解释器」（2026-09-17，逐个扫过 `/models` 里的候选 id）。

端点在自己的沙箱里写 Python、跑、再据输出作答；一次回答内可跑多次。它是这张表里**唯一不上网的 id**，
也是唯一**按模型**而非按 wire 判定的 id。

**两个面的条件各不相同**（文档说「与 function calling 互斥」，实测只在 ① 面成立）：

| | ① Chat Completions compat | ② Responses compat |
| --- | --- | --- |
| 声明 | 顶层 `enable_code_interpreter: true` | `tools:[{type:"code_interpreter"}]` |
| 非流式 | 400 `Non-streaming mode does not support Code interpreter.` | 可以 |
| 同时带函数工具 | **400**（`Agent mode does not support tools`，与 `agent_max` 同一条） | **可以**，同一对话里先调函数、下一轮再跑代码实测正常 |
| 思考关闭 | 照常跑（qwen3-max 也行，与文档不符） | HTTP 200 后 `response.failed`：`Normal mode does not support Code interpreter. Please set enable_thinking to true.` |
| 与搜索同开 | 可以（含 `agent_max`，前提是不带函数工具） | 可以 |
| 过程可见 | 无痕，只能看 prompt_tokens 从 ~30 涨到 700–1600 | 可见，见下表 |

规则与理由：

- **按模型 id 放行，而不是「开了试试」**。① 面上有的模型**静默忽略**这个字段（qwen-max、qwen3-max-preview：
  不报错、prompt 不变、答案没算过），作者毫无感知；有的 400（qwen3.8 全系在 ① 面不支持，② 面支持）。
  所以每条 wire 一张**实测过的 id 正则表**（qwen3-max 及日期版 / qwen3.5–3.7〔② 面到 3.8〕的 plus·max·flash /
  部分开源版 / ② 面的 deepseek-v4），锚定写死，防同前缀的 `qwen3.5-omni-plus`、`qwen3-vl-plus` 误中；
  下一代不预放行，实测后再加。设置 UI 只对匹配的 id 显示开关，适配器发送前再判一次（配置行会经导入/改 id 旅行）。
- **会必然失败的组合，按请求丢工具，不发请求**：① 面本轮有函数工具 → 不发（agent 的工具不能让，
  所以 ① 面上它只惠及不带工具的请求，agent 运行应走 ② 面）；② 面思考档位为「关」（`reasoning.effort:"none"`）→ 不发。
- **它不是 web 工具**：搜索子代理接管联网时，主模型只让出 web 类 id，代码解释器留在主模型上
  （agent 策略多一个 `"no-web"` 态，见 agent-runtime-architecture 07 §3.4、09 §4.1）。
- **app 自己发起的辅助请求一律不带服务端工具**（摘要、合集摘要、翻译、图片描述、结构化任务、历史压缩）：
  处理的是手头已有的文本/图片，无可查可算；代码解释器光说明就约 800 输入 token/请求，还会多轮推理。
  服务端工具是从模型配置行一路带进连接参数的，**每个非对话调用点都要显式覆盖为空**，并用测试钉住（坑 77）。

响应侧（② 面）：`output_item.added` 就带完整 `code`；随后 `response.code_interpreter_call.{in_progress,interpreting,completed}`
三个只有 `item_id` 的进度事件；`output_item.done` 补 `outputs:[{type:"logs", logs}]`，`logs` 外面包着一层 markdown 代码围栏，
读取时剥掉。用量在 `usage.x_tools.code_interpreter.count`。**Python 异常不是失败**：`1/0` 仍是 `status:"completed"`，
traceback 在 `logs` 里——执行日志结果列取输出最后一行，正好是异常那一行。**画图**时图片以 markdown 图片的形式写在 `logs` 里，
指向带签名的 OSS 地址，约 12 小时过期，且最终回答正文里不带——只当文本记日志，不存链接（坑 78）。
计费：限时免费，但多轮推理让 token 明显增加（qwen3.8-flash 一问约 1.1k，不开约 30）。

**成本形态（写进设置抽屉说明）**：搜回/抓回的正文**按输入 token 计**（OpenAI 一次搜索回答实测 45.7K 输入、112 s；2026-09-24 经账号池上游 6–10 s、8.5–14K 输入，见下文「中转站上的 GPT」；xAI 一次 6,851），
另按次计费（`tool_usage.web_search.num_requests` / xAI `server_side_tool_usage_details`）；首个事件可晚到 54 s。
流看门狗的首块等待需高于此，且每个 `web_search_call` 的 added 事件都应算作存活信号。

### wire 形状与 max_uses 刹车（④ 族）

```json
{ "type": "web_search_20250305", "name": "web_search", "max_uses": 10 }
```

- 与本地工具同处一个 `tools` 数组（两种条目形状并存）。
- 类型按日期版本化。**id → wire type 的映射表集中一处**——版本升级 = 一处编辑，不是存进每行模型数据里永远冻着旧版本。
- **实测形状**（【实测 2026-09-26】，Sonnet 5 经 OrcaRouter，回包 Anthropic 原样）：`web_search_20250305` **不需要 beta 头**；响应是 `server_tool_use` →
  `web_search_tool_result`（10 条结果，各带 `encrypted_content`）→ 带 `citations`（`web_search_result_location`）的 text；`usage.server_tool_use` 是
  `{web_search_requests: 1, web_fetch_requests: 0}`（按次计费的读数，06 §1）。**没发 `cache_control` 也记了 2,834 个 `cache_creation_input_tokens`**——
  搜索结果被服务端自动写缓存。这一请求合计 $0.051。
- **`max_uses` 是唯一的刹车**：服务端工具不问就跑、按次计费（官方 $10/1000）+ 结果按 input token 计；一个研究型问题实测一轮 8 次搜索。即使中继文档没列这个字段也照发——这是对"只发中继文档写了的字段"规则的**刻意例外**，因为省略它的下行风险是无上限花费。

### 响应流的防御读取

- `server_tool_use` 块：query 按 `input_json_delta` 分片到达，**也有端点在 start 块整个给全——两种形状都要收**。
- `web_search_tool_result` 块：整块到达无 delta。`content` 正常是结果数组、出错时是单个 error 对象——**读取端对容器形状全防御：认不出 = 零结果，而不是抛异常炸掉已完成的响应**。
- 对外表达为两阶段 `ServerToolEvent`（`phase: "call" | "result"`），靠 `server_tool_use` 的 id 与结果块的 `tool_use_id` 配对。call 在 `content_block_stop` 时上报（此刻 query 才完整）——让执行日志在结果到达前就能显示"正在搜什么"。
- **事件 id 在整份日志里要唯一，不只在一个回包里唯一**（【实现】simple-ai-writer 2026-09-26，review 找出）。执行日志常按 id 原地替换一行，而且比较时不带轮次；
  一份日志装着好几个请求（agent 多轮、同一上下文并发的多份草稿）。上游生成的 id（`srvtoolu_…`、`ws_…`）天然唯一；**由内容拼出的 id**
  （网址、搜索词、每个请求都从 1 数起的序号，以及没核实跨请求唯一性的上游序号）就会跨请求撞上：后一轮的同一网址覆盖前一轮那一行，前一次读取从日志里消失，
  按次计费的工具少记一次。对策：每个读取器创建时生成一个请求级前缀，发出去的 id = 前缀 + 内容键，本请求内的去重仍按内容键；测试钉住「两个读取器读同一块，id 不同」。
- **内容会长的行，固定 id、变了就重发**：一个请求一个搜索行（前缀 + `search`），搜索词或结果有变化就用同一个 id 再发一次，靠日志的原地替换更新；
  不用「这个阶段报过没有」来挡。否则结果分几块到达时，先到的空结果把后来的命中挡掉；搜索词逐块累加时 id 随之变化，多出一行、同一条搜索算两次。
  （实测 grounding 只在末块出现，但读取端不该依赖这一点。）

### ③ Gemini 的内置工具：`googleSearch` / `codeExecution` / `urlContext`

【实测 2026-09-26】，Gemini 3.8 Flash，Vertex 后端经 OrcaRouter（回包原样，第 1 篇 §9.5）；第二轮「再补测」按适配器真实会发的形态测（流式、思考 LOW、
每次都带一个函数工具），landscape.md §7 第十八个样本「再补测」D。

**请求形状**：每个内置工具是 `tools[]` 里**独立的一项**，与 `functionDeclarations` 并列，不塞进它里面；没有函数工具时照样发。

```json
"tools": [
  { "functionDeclarations": [ … ] },
  { "googleSearch": {} }, { "urlContext": {} }, { "codeExecution": {} }
]
```

**同发都 200**：三者都能与函数工具同发；再加 `toolConfig.functionCallingConfig.mode:"ANY"`（先搜两条，再按要求调函数）或
`responseMimeType:"application/json"` + `responseJsonSchema`（得到合 schema 的 JSON）也 200。搜索与函数调用可以在**同一块**里一起出现
（`functionCall` 带签名 + `groundingMetadata`）。所以在这条线上**不按请求丢**内置工具（与千问 DashScope 的 ① 面相反，本节「代码解释器」）。

**回报的位置各不相同**：

| 工具 | 流里的位置与形状 | 计费 |
| --- | --- | --- |
| `googleSearch` | **末块**（带 `finishReason` 的那块）candidate 上的 `groundingMetadata{webSearchQueries[], groundingChunks[{web:{uri, title, domain}}], searchEntryPoint, groundingSupports}`；`uri` 是 `vertexaisearch` 跳转链接，`title` 是网站域名，不是页面标题 | **按查询条数**，约 **$0.014 一条**；一次回答搜几条由模型定（一题 6 条、$0.084），**没有**像 ④ `max_uses` 那样的上限字段可发 |
| `codeExecution` | 独立的块：`executableCode{language, code, id}`（带签名）→ `codeExecutionResult{outcome:"OUTCOME_OK", output, id}`（`id` 配对）→ 之后才是文本 | 回填的输出记在 `usageMetadata.toolUsePromptTokenCount` |
| `urlContext` | **首块**就有 `urlContextMetadata.urlMetadata[{retrievedUrl, urlRetrievalStatus}]`；末块 `groundingMetadata.groundingChunks` 给出**真实** `uri` 与页面标题，但**没有** `webSearchQueries` | 读回的正文同样记在 `toolUsePromptTokenCount` |

- **`toolUsePromptTokenCount` 在 `promptTokenCount` 之外**（20 + 65 + 77 = 162），计进输入 token（06 §1 第 2 条）；花费都进了带头的 `costUsd`。
- 与 ④ 一样是「端点自己跑、本地无事可做」：`executableCode` / `codeExecutionResult` 不是欠结果的调用，不回 `functionResponse`（本节三原则）。
- **「搜没搜」只看 `webSearchQueries`**，不看正文，也不看 `groundingChunks`——读网页的回答也带 `groundingChunks`。把后者当搜索，只开读网页的请求也会被记成一次（按次计费的）搜索。
  搜索的引用链接是 Google 的跳转地址，不是原站（能用多久 ⚠ 未测）。
- **改口留痕**：本表此前写搜索「一次 $0.028」，是按请求记的；同日再补测按查询条数核对，改为约 $0.014 一条（06 §1）。
- **代码 part 的回灌**：`executableCode` / `codeExecutionResult` 随 model 轮原样放回 → 200，下一轮用得上上一轮算出的数；回灌时请求里**已经没有
  `codeExecution`**（作者中途关掉开关），甚至**没有任何工具**（收尾轮），也都 200。所以不需要把历史里的代码 part 改写成文本。
  代价：这些 part（以及可能带回的 `inlineData` 图表）会随整组 model parts 在之后每一轮回传——和思考签名同一套机制，若上下文估算与裁剪不计它们，
  估算会偏低【实现 simple-ai-writer，写成已知限制】。
- ① 面经 OrcaRouter 时这三个名字是**保留函数名**（发一个没有 parameters 的 function 工具，网关换成原生内置工具）【文档 2026-09】——这是网关的约定，不是 Gemini 的。

**接进 app 层的一个 id 一种意思**（【实现】simple-ai-writer `serverTools.ts` `geminiServerTools`，2026-09-26）：沿用已有的三个 app id，不新造——
`web_search` → `googleSearch`、`web_extractor` → `urlContext`、`code_interpreter` → `codeExecution`。`urlContext` 在 Gemini 上能单独用，但 app 里
「抓取」在别的线路上是搜索的附加档，这里也照样依附搜索：**一个 id 在各线路只有一种意思**，能力路由与子代理资格才不必按线路分叉。
能力格上只开测过的（OrcaRouter ③ 三项）；`googleSearch` 是协议自带，官方 google 与其他中转的 ③ 列按规则「未实测、照发」——
Gemini 2.x 在 AI Studio 上与函数工具同发的问题（review 提过、未测）是有意接受的风险，写进了文档而不是按型号分支。

**执行日志的 id 要带请求级前缀**：这三种事件没有上游生成的唯一 id（④ 的 `srvtoolu_…`、② 的 `ws_…` 有），只能由内容拼（网址、搜索、代码序号）；
而一份日志装着好几个请求（agent 多轮、多稿并发），按 id 原地替换的日志会让第 3 轮的同一网址覆盖第 1 轮那一行。见上文「响应流的防御读取」与坑 192、193。

### 服务端工具归平台，不归模型；「应用执行」的联网端点（智谱）

**火山方舟（套餐 key，【实测 2026-09-18】）**：厂商「联网搜索工具」页只列 Responses 与 Messages 两种接口，① 没有。
② `{type:"web_search"}` 三款都跑出 `web_search_call`，计数在 `usage.tool_usage_details.web_search.doubao`——文档要求豆包搜索写
`sources:["doubao"]`，套餐上**不写也记在 `doubao` 源下**；按量 key 上不写 `sources` 可能落到另开通、按次计费的「联网内容插件」【未验】。
④ 的版本化 `web_search_20250305` + `max_uses` 真跑（`server_tool_use` + `web_search_tool_result`，结果带 `encrypted_content`、`url` 为空串；
计数在 `usage.server_tool_use.web_search_requests`）。所以能力格子是 `(平台, 面)`：套餐 ②④ = 有，① = 无，按量 = 未知。

**同一个模型，有没有服务端工具取决于谁在服务它。** GLM 在千问百炼、火山方舟上由平台替它执行搜索；在智谱自家端点上，
没有可靠的服务端工具。所以「能不能联网」是 `(平台, 协议族)` 的属性，不能写在模型上，也不能从模型 id 推。【实测 2026-09-19】

智谱自家端点上两种联网形态，都不是千问那一类：

- **对话内工具**：`tools[]` 里一项 `{type:"web_search", web_search:{enable:true, search_engine, search_intent?, search_result?, count?, …}}`，
  不是顶层字段。结果在响应**顶层** `web_search[]`（`{title, link, content, media, icon, refer, publish_date}`）。两个静默问题：
  - **默认开着「搜索意图识别」，意图不够就不搜——而模型照样答「根据联网搜索结果……」**（prompt 22 token、响应无 `web_search` 字段）。
    必须 `search_intent:false` 才每次都搜。
  - **结果量控制不住**：`count` 无效，`search_pro` 一次往 prompt 灌 50 条 ≈24k token、`search_std` ≈6.7k。
- **独立端点（由应用执行）**：同一把 key、同一前缀下 `POST /web_search` 与 `POST /reader`，与对话无关。这是一类**应用自己
  发 HTTP、自己拿结果**的联网工具——它不受模型约束（任何模型都能借它联网），结果由应用截断后再交给模型：
  - `/web_search`：body `{search_query, search_engine, search_intent}` 必填；回 `{search_intent:[{query,intent,keywords}], search_result:[…]}`，
    **无 usage、按次计费**。这里 `search_intent` **默认 false**（与对话内工具相反）；设 true 时闲聊回 0 条、意图 `SEARCH_NONE`——
    没搜是看得见的。`count` 四个引擎都无视（std ~10、pro / sogou 恒 50、quark 10）；`search_domain_filter` 只在 `search_pro` /
    `search_pro_sogou` 生效、`search_std` 无视；`search_recency_filter` 三个引擎都无视；超 70 字的查询照搜。
  - `/reader`：body `{url, return_format?, retain_images?, …}`；回 `{model:"web-reader", reader_result:{title, description, url, content, metadata}}`。
    默认 markdown 正文完整；**`return_format:"text"` 有损**（一个门户首页只剩 108 字页脚）；`retain_images:false` 与
    `with_links_summary` 无效果。**目标 404 与主机不存在都回 500 `1234 网络错误…请稍后重试`**——分不出死链与平台故障。

对实现的推论：「应用执行的联网工具」是与服务端工具并列的另一类——要进 agent 的工具注册表（有调用、有结果、要配对），
要有调用上限与日志，结果要应用侧截断；它的死链错误要翻译成「这个页面读不到」，不能让模型当平台故障去重试。

### 中转站自己「做」服务端工具：劫持、真搜、丢弃三种情形（New API · Kiro 渠道）

【实测 2026-09-23】，simple-ai-writer `docs/api/landscape.md` §7 第十五个样本、`live.relay-kiro.test.ts`；背景见第 1 篇 §9.2。
后端（Kiro）不是 Anthropic API，④ 的 `web_search_20250305` / `_20260209` 由中转站的翻译层接到 Kiro 自己的联网搜索上——
**结果取决于同发了什么工具、流式与否**，三种情形三种结果：

| 情形 | 结果 |
| --- | --- |
| 1. 只挂 `web_search`、没有函数工具（流式与否一样） | **整条请求被劫持**：中转站把**第一条** user 消息原文当搜索词（多轮对话里搜的是开头的「Hi」），0.8–2 s 返回模板「I'll search for "…"」+ `server_tool_use` + `web_search_tool_result` +「Here are the search results for "…"」列表。**模型根本没跑**，请求里的写作指令没有任何回答 |
| 2. 与函数工具同发、流式 | ✅ **真的在搜**：模型自己拟搜索词（「latest stable Rust version 2024」），结果带 `title` / `url` / `page_age`，搜完接着思考、作答 |
| 3. 与函数工具同发、非流式 | `web_search` 被丢，模型说「我没有联网搜索工具，只有 get_weather」 |

- ① 面的 `web_search_options` 被中转站转成 ④ 的 `web_search` 后**同样被劫持**（返回「Here are the search results for "…"」，模型没跑）。
- **怎么认出劫持**：两款不同模型逐字相同的输出、`output_tokens` 固定（644 / 568 / 478）；结果块里 `encrypted_content` 其实是明文摘要、
  `page_age` 为 null；文本以「I'll search for "<第一条 user 消息>"」开头。任何「跨模型一模一样」的回答都说明模型没参与。
- **对实现的推论**：
  - 服务端工具能力是 `(平台, 面, 模型 id)` 的——同一台中转站别的渠道没这个问题，所以按 id 点名（第 1 篇 §9.2），不写平台画像。
  - 参考实现对**不带函数工具的请求也发服务端工具**（聊天的一问一答），恰好落进情形 1，所以对被点名的 id 把 ④ `web_search` 判「不发」。
    代价：agent 场景（永远流式、永远带函数工具）本来能用的真搜索（情形 2）也关了——同一个模型开关分不出两种场景。
    想留住情形 2 的做法是「只在本轮带函数工具时发」，按请求判定，与 §5「代码解释器」的按请求丢弃同形【未实现】。
  - 验证服务端工具要把三种组合（单独挂 / 与函数工具同发 × 流式 / 非流式）都跑一遍；只测其中一种，结论可能正好相反（第 6 篇 §8）。

**同一端点上，别的服务端工具被丢弃，模型「假装执行」**：`web_fetch_20250910`、`code_execution_20250825`、随便造的 `type` 全部 200、
静默丢弃，模型照样答得像跑过——给出 `<h1>Example Domain</h1>`（像是抓了页面）、一段从没执行过的 Python 和「输出」。
- 唯一的判据是**响应里有没有对应的 `server_tool_use` / `*_tool_result` 块**：没有块 = 没跑，不管正文怎么说。
- 所以执行日志、引用、计费只能凭块上报（§5「响应流的防御读取」），**绝不凭正文推断「工具已执行」**；
  服务端工具的 live 用例要断言块存在，不能只断言答案看起来合理。

**同一台上别的渠道**（【实测 2026-09-23】，landscape.md §7 第十六个样本，④ 面）——服务端工具最能看出渠道差异：

| | Kiro | CC | anti | AWSb（Bedrock 正向） |
| --- | --- | --- | --- | --- |
| `web_search` 单挂 | 劫持（上表情形 1） | ✅ 真搜：要求搜才搜（`server_tool_use` + 结果块，`usage.server_tool_use.web_search_requests: 1`）；改写句子的请求不触发、不劫持 | 丢：模型凭记忆答（「As of my latest information (July 2025)…」） | 400 `Input tag 'web_search_20250305' … does not match` |
| `web_search` + 函数工具（流式） | 真搜 | 真搜 | 丢 | 400 |
| `web_fetch_20250910` | 丢，假装抓了 | ✅ 有 `server_tool_use` 块 | 丢 | 400 |
| `code_execution_20250825` | 丢，假装跑了 | 丢，没有块 | 丢 | 400 |
| ① `web_search_options` | 劫持 | ✅ 答案引了搜索结果 | 无效 | 400 |

- 四个渠道四种答案：劫持、真做、静默丢、400。「这台中转站支持搜索吗」没有答案，只有「这个渠道支持吗」——服务端工具能力是（平台, 面, 渠道, 模型）的（第 1 篇 §9.2）。
- Bedrock 的 400 会响，但它让**整条请求**失败，不是只丢工具：一个对中转站默认发 `web_search` 的应用，在这个渠道上每个请求都挂。正向渠道也要点名。
- 同一渠道内也要逐工具测：CC 上 `web_fetch` 是真的，`code_execution` 却被丢。

### 中转站上的 GPT 内置工具：随上游（New API，2026-09-24）

【实测 2026-09-24】，simple-ai-writer `docs/api/landscape.md` §7 第十七个样本：同一台 New API、同一个 `gpt-5.6-sol`，三个 ChatGPT 账号档与一个网关上游
（网关用同档 terra 顶替；上游分类见第 1 篇 §9.2「同一个 GPT，两类上游」）。每项单挂与和函数工具同发都测过，默认流式。

② `/v1/responses`：

| 工具 | 特价Pro | Plus | Pro | 网关（`[Azure]`） |
| --- | --- | --- | --- | --- |
| `web_search` | ✅ **真搜**：1 次 `web_search_call` + `url_citation`，6–10 s，输入 8.5–14K（搜回的网页按输入计） | ✅ | ✅ | ❌ **静默丢弃**：没有 `web_search_call`，模型答「I can't perform a live web search」 |
| `code_interpreter` | 流式 `response.failed` | 502 | 400 `Unsupported tool type` | 500 |
| `file_search` | 流式 `response.failed` | 502 | 400 `Unsupported tool type` | 500 |
| `image_generation` | 403 `Image generation is not enabled for this group` | 403 | 403 | ✅ 能出图：83 s，`image_generation_call` 带约 911K 字符的 base64 |

① `/v1/chat/completions`：`web_search_options` **四个上游全部静默忽略**（模型答不出只有联网才知道的事），不报错。
这台中转站把 GPT 的 ① 翻成 ② 再发，翻译层不转这个字段——**GPT 的联网只能走 ② `web_search`**。

- 与第十个样本比（另一台、同类账号档，112 s）快了一个量级；搜索时延随上游与时间变，流看门狗仍按上文「成本形态」的 54 s 首事件留余量。
- **同一个工具名，四种结果**：真搜、静默丢、400、403。「这台中转站支持联网吗」没有答案，只有「这个上游支持吗」——与同台 Claude 的结论一样（上一小节），
  能力格按上游写：参考实现的 codex 画像 ② `web_search` ✓、azure ✗（第 1 篇 §9.2「上游画像扩到 GPT」）。
- 网关的丢弃最危险：请求 200，模型老实说自己搜不了——作者多半以为是模型的问题。判据同上一小节：**看有没有 `web_search_call` 条目**，不看正文。
- 不支持的工具报法各不相同（官方同文 400 / 502 / 流式 `response.failed` / 500），不能用一个正则把它们都学成「不支持」——502 与 500 看起来就是上游故障。
  它们会响，但让**整条请求**失败：一个默认挂 `code_interpreter` 的 ② 请求在这四个上游上一个都跑不通。别对中转站默认发这类工具。
- 网关能出图而账号池 403：出图能力也随上游；参考实现的 ② 对话路径本来不发 `image_generation`，只在说明里告知。

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

## 7. 工具按需加载（deferred loading / tool search）的各族协议事实

> 2026-09 读官方文档整理，形状未全部实测（xAI 的 403 是实测）。出处：simple-ai-writer
> `docs/api/tool-search.md`。「要不要用、怎么用」属于 agent 策略，见 agent-runtime-architecture 07 §4.6。

| | 原生 | 延迟标记 / 搜索工具 | 应用自己插入定义 | 回传义务 |
| --- | --- | --- | --- | --- |
| ② OpenAI Responses | ✅ GPT-5.4+ | `defer_loading: true`；`{type:"tool_search", execution:"server"\|"client"}`；`{type:"namespace", …}` 分组 | ✅ `{type:"additional_tools", role:"developer", tools}` 条目，不经模型 | 下一轮 `input` **必须**带 `tool_search_output`（及 `additional_tools`），否则工具不可用 |
| ④ Anthropic | ✅ 4.5+ | `defer_loading`；`tool_search_tool_regex_*` / `_bm25_*`；自带工具可在 `tool_result` 里返回 `tool_reference` | ❌（需经一次 tool_result） | 历史保留 `tool_search_tool_result` 块即可 |
| ② xAI | ⚠️ 规格有，**实测 403**（仅 alpha 用户） | 同 OpenAI 形 | 未见 | 未写 |
| ③ Gemini | ❌ | 请求带 `defer_loading` 字段**整个被拒**（第三方报告） | — | — |
| ① Chat Completions（全部） | ❌ | — | — | — |

语义差：OpenAI 的延迟函数模型仍看得到名字与描述（推迟的主要是参数 schema）；Anthropic 的延迟工具在搜到前完全不可见。

**原生为什么重要：缓存。** 原生实现把取回的定义放在上下文末尾（OpenAI）或原地展开（Anthropic），**工具表前缀不动**；
自己改 `tools` 参数则从工具表那一截起前缀缓存全部作废（OpenAI 另注明"换一批加载的工具会从那一点起破坏缓存"）。

**回传与约束（采用原生机制时必须满足）**：
- ② 族：只回传 reasoning / function_call / message 的实现，要把 `tool_search_call` / `tool_search_output` /
  `additional_tools` 加进回传名单，否则**加载过的工具下一轮静默消失**（回传缺失无现象）。
  应用自己插入定义用 `{type:"additional_tools", role:"developer", tools}` 条目——定义在上下文末尾、前缀不动。
- ④ 族：至少一个非延迟工具，否则 400；`defer_loading` 与 `cache_control` 同时出现 400。

## 本篇检查清单

- [ ] 工具定义内部统一 OpenAI 嵌套形状；Gemini 换容器、Anthropic 改 `input_schema`，转换各在适配器内一处。
- [ ] toolChoice 各族翻译齐全（② 见 02 §7.1）；Anthropic 仅在声明了本地工具时发 tool_choice。
- [ ] ① 族参数拼接按 index 分组、id 累积拼接；④ 族空参数 `""` → `"{}"`；`parseJsonArgs` 全员 try/catch。
- [ ] ③ 回灌模型 parts 时剔除光秃秃的 `{text:""}`（带签名的保留），写侧与读已存历史两处都做；有 `functionCall.id` 时用它配对，没有才按函数名；并行调用只有第一个 part 带签名，不补不挪。
- [ ] ③ 内置工具（`googleSearch` / `codeExecution` / `urlContext`）是 `tools[]` 里与 `functionDeclarations` 并列的独立项；结果不当欠结果的调用；检索按查询条数计费单列，不按 token 估；「搜过」只认 `webSearchQueries`；`toolUsePromptTokenCount` 计进输入。
- [ ] 服务端工具事件的 id 在整份执行日志里唯一：由内容拼的 id 带请求级前缀；内容会长的行用固定 id 重发、靠原地替换更新。
- [ ] agent 循环保证 tool_call/结果配对：中止/异常/超时路径下要么双双不入历史、要么补"未执行"结果。
- [ ] server tools 走声明而非注册，不在 agent 工具注册表里；工具循环对 `server_tool_use` 不回 tool_result。
- [ ] server tool 的 id→wire type 映射集中一处，type 按日期版本化；app 层 id 跨族唯一，拼法按族收口在 shaping 函数（④ `tools[]` 条目 / ① compat 顶层 `enable_search`）。
- [ ] ① 族的 `enable_search` 只对 compat 标准发；官方端点在 UI 与适配器两层都被挡（api.openai.com 对未知顶层参数 400）。
- [ ] 知道 ① 族兼容层搜索无痕：无来源无角标可解析，执行日志诚实留白，不伪造事件；「不生效无症状」列入实测清单。
- [ ] 每个 ④ 族 server tool 声明都带 `max_uses`。
- [ ] `server_tool_use` 的 query 同时支持 delta 分片与 start 块整给两种到达形状。
- [ ] 结果块读取全防御：认不出的容器形状 = 零结果，不抛异常。
- [ ] 实现了 pause_turn verbatim 续跑（块原样回话，encrypted_content 不动），或至少把 `pause_turn` 当已知未完成态报警。
- [ ] 有 transcript 纯文本降级路径，判据是"结果之后模型说话了吗"（文本流事实，非块记录）。
- [ ] 续跑有腿数上限；触顶按正常结束处理；usage 跨腿求和；最后一腿提示词声明"最后机会"。
- [ ] transcript 有单条 + 总量双层长度闸，按结果计预算。
- [ ] 上层只见一条文本流；`turnResumed` 仅诊断用。
- [ ] ② 族工具定义扁平 + 显式 `strict:false`；server tools 以裸 `{type}` 追加在函数工具之后，`tool_choice` 只随函数工具发。
- [ ] 每个 server tool id 按 standard 过滤（官方 Responses 只放 `web_search`）；`web_extractor` 只作为 `web_search` 的附加档存在，发送前再归一化。
- [ ] ② 族服务端工具条目解析覆盖 `search`（queries / 单数 query 兜底）、`open_page` / `find_in_page`（url）、`web_extractor_call`、JSON 字符串形态的图片搜索；这些条目不进回传。
- [ ] 能力按模型被拒（如 `agent_max` 400）时不静默降级重试；设置说明写清"抓回正文按输入 token 计 + 按次计费"。
- [ ] ① 面本轮带函数工具时，`agent_max` 与 `enable_code_interpreter` 都不发（请求形状必然 400）；有一条带工具的实测用例，而不只测不带工具的请求。
- [ ] 代码解释器按 wire × 模型 id 的实测正则表放行（UI 与适配器两层），正则锚定、不预放行下一代；② 面思考关闭时本轮不发。
- [ ] `code_interpreter_call` 解析：added 取 `code`、done 取 `logs` 并剥围栏；异常不算失败；图片链接只记文本不存。
- [ ] 搜索子代理接管时主模型只让出 web 类 id（`"no-web"`），非 web 的服务端工具保留（agent 侧，见 agent-runtime-architecture）。
- [ ] 用了原生工具按需加载：② 族回传名单含 `tool_search_*` / `additional_tools`；④ 族至少一个非延迟工具、`defer_loading` 不与 `cache_control` 同现；③ / ① 族不发 `defer_loading`。
- [ ] app 自己发起的辅助请求（摘要、翻译、图片描述、结构化、压缩）显式不带服务端工具，并有测试守住。
- [ ] 经中转站的服务端工具在「单独挂 / 与函数工具同发 × 流式 / 非流式」四种组合下都实测过：会不会被中转站劫持成一页模板搜索结果（模型没跑）、会不会被丢弃；执行日志只凭 `server_tool_use` / `*_tool_result` 块上报，不凭正文推断「已执行」。
- [ ] 经中转站的 GPT：联网只走 ② `web_search`（① `web_search_options` 被翻译层忽略）；`web_search` 能力按上游声明（账号池真搜、网关静默丢）；不对中转站默认发 `code_interpreter` / `file_search` / `image_generation`（各上游报 400 / 403 / 500 / 502 / 流式失败，整条请求挂）。
