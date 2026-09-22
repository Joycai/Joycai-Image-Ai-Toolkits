# 05 · 工具协议与 server tools

> 本篇解决的问题：本地工具（客户端执行）在各族上的定义转换、tool_choice 翻译、流式参数拼接，以及 server tools（端点自己执行的工具，如 web_search）带来的一整类新问题——包括「一次调用 = 多次 HTTP 请求」的续跑循环。
> 不读会踩的坑：tool_call 与结果消息的配对是硬要求且**违约不自愈**——一次缺失永远留在会话历史里每轮重发，整段对话从此不可用；把 `server_tool_use` 当成欠结果的调用去回 tool_result 是协议错误；不设 `max_uses` 的服务端搜索是无上限花费；兼容层可能"响应侧抄全了、请求侧没抄"，协议规定的续跑方式恰好是它唯一不收的形状。

出处：simple-ai-writer `src/lib/ai/serverTools.ts`、三个适配器的工具接线（`openai.ts` / `gemini.ts` / `anthropic.ts`，尤其 anthropic.ts 的续跑循环）；协议事实见其 `docs/api/tools.md`。

目录：
- §1 工具定义的统一形状与三家转换
- §2 toolChoice 翻译
- §3 流式参数拼接：三家三样
- §4 配对是硬要求，且违约不自愈（维护见 agent-runtime-architecture 07 §3.2）
- §5 Server tools：端点自己跑的工具
  - 三原则 · 同一个 id，两种拼法 · ② Responses 族：可见的内置工具
  - 代码解释器：按模型 id 放行、按请求丢弃（千问 DashScope）
  - wire 形状与 max_uses 刹车（④ 族） · 响应流的防御读取
  - 服务端工具归平台，不归模型；「应用执行」的联网端点（智谱）
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

② 族的 tool_choice 见第 2 篇 §7.1（规则 4：命名形态扁平、只随函数工具发、不做预判降级）。

## 3. 流式参数拼接：三家三样

| 族 | 拼接方式 |
| --- | --- |
| ① | 按 `delta.tool_calls[].index` 分片拼 `arguments` 字符串——**分组键必须是 index 不是 id，id 自身也可能分片**（`entry.id += partial.id`） |
| ③ | 整个 `functionCall` 一次到齐（对象、无 id、适配器自造 id） |
| ④ | 按块索引拼 `input_json_delta.partial_json`；空参数调用不会流任何 delta，`""` 必须转 `"{}"` |

② 族按 `output_index` 分组、参数以 `.done` 整串为准，见第 2 篇 §7.2。

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

**成本形态（写进设置抽屉说明）**：搜回/抓回的正文**按输入 token 计**（OpenAI 一次搜索回答实测 45.7K 输入、112 s；xAI 一次 6,851），
另按次计费（`tool_usage.web_search.num_requests` / xAI `server_side_tool_usage_details`）；首个事件可晚到 54 s。
流看门狗的首块等待需高于此，且每个 `web_search_call` 的 added 事件都应算作存活信号。

### wire 形状与 max_uses 刹车（④ 族）

```json
{ "type": "web_search_20250305", "name": "web_search", "max_uses": 10 }
```

- 与本地工具同处一个 `tools` 数组（两种条目形状并存）。
- 类型按日期版本化。**id → wire type 的映射表集中一处**——版本升级 = 一处编辑，不是存进每行模型数据里永远冻着旧版本。
- **`max_uses` 是唯一的刹车**：服务端工具不问就跑、按次计费（官方 $10/1000）+ 结果按 input token 计；一个研究型问题实测一轮 8 次搜索。即使中继文档没列这个字段也照发——这是对"只发中继文档写了的字段"规则的**刻意例外**，因为省略它的下行风险是无上限花费。

### 响应流的防御读取

- `server_tool_use` 块：query 按 `input_json_delta` 分片到达，**也有端点在 start 块整个给全——两种形状都要收**。
- `web_search_tool_result` 块：整块到达无 delta。`content` 正常是结果数组、出错时是单个 error 对象——**读取端对容器形状全防御：认不出 = 零结果，而不是抛异常炸掉已完成的响应**。
- 对外表达为两阶段 `ServerToolEvent`（`phase: "call" | "result"`），靠 `server_tool_use` 的 id 与结果块的 `tool_use_id` 配对。call 在 `content_block_stop` 时上报（此刻 query 才完整）——让执行日志在结果到达前就能显示"正在搜什么"。

### 服务端工具归平台，不归模型；「应用执行」的联网端点（智谱）

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
