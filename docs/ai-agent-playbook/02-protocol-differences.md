# 02 · 四族协议差异对照

> 本篇解决的问题：把 OpenAI Chat Completions（①）、OpenAI Responses（②）、Google GenAI generateContent（③）、Anthropic Messages（④）四族的 wire 差异一次性列全——消息容器、角色、工具、流式机制、鉴权、URL 约定——并给出适配器里必须做的结构性修补；② OpenAI Responses 族单列在 §7。
> 不读会踩的坑：Anthropic 的交替律 400、连续 tool 消息拆开发送被拒、Gemini 把 SSE chunk 当 delta 拼接导致内容重复、baseURL 归一化"修复对称"后中继路由全断、Gemini key 走查询串泄进代理日志。

出处：simple-ai-writer `src/lib/ai/openai.ts`、`gemini.ts`、`anthropic.ts`、`urls.ts`、`http.ts`；协议事实见其 `docs/api/landscape.md`。

目录：
- [§1 总对照表](#1-总对照表)（四族 × 功能维度的转置表，原 21 篇 §2 并入；表后：形状被接受 ≠ 内容送到了模型——中转站按渠道丢 PDF / URL 图片；回包原样的网关上 PDF 四面都读到与其计费；视频输入 `video_url` 是厂商扩展，六个端点的实测与按平台放行；④ 面兼容层对未知字段／非法思考值四家四种）
  - [§1.1 非对话面与私有扩展一览](#11-非对话面与私有扩展一览)（Ⓓ DashScope 私有、火山三面、智谱私有 REST、Bedrock 上的 Claude、🖼 出图 route 家族、🎬 视频、🎤 ASR 三种线格式：只有判定标准 + 端点 + 指针）
- [§2 消息转换的结构性修补](#2-消息转换的结构性修补)（§2.1 Anthropic · §2.2 Gemini）
- [§3 流式解析：共同骨架 + 三家差异](#3-流式解析共同骨架--三家差异)（§3.1 共同骨架 · §3.2 各族差异）
- [§4 baseURL 的不对称归一化](#4-baseurl-的不对称归一化)
- [§5 鉴权矩阵](#5-鉴权矩阵)
- [§6 CORS / 浏览器直连](#6-cors--浏览器直连)
- [§7 ② OpenAI Responses 族](#7--openai-responses-族)（§7.1 请求骨架 · §7.2 流式事件与读取 · §7.3 回传）
- [本篇检查清单](#本篇检查清单)

---

## 1. 总对照表

行 = 功能维度，列 = 四族（① OpenAI Chat Completions ／ ② OpenAI Responses ／ ③ Gemini generateContent ／ ④ Anthropic Messages）。每格只放结论记号 + 关键字段名；报文片段、词表翻译在本篇 §2–§7 与 03–06 对应小节，平台／渠道／模型级的差异只在「详见」指过去（那是 20、22、23 篇的事）。没有证据的格子写 `—`，不从相邻族类推。

记号（全库通用，见 SKILL.md）：✅ 实测生效 ／ ❌ 实测拒绝且**会响**（括号里写状态码或原文）／ 🔇 **静默失败**（收下 200 但不生效／被丢／被改写）／ 🔀 被中转站改写或劫持 ／ 📄 只有文档口径 ／ ⚠ 来源标注为推断或含糊 ／ — 未测。证据记法：【实测 YYYY-MM-DD】【文档 YYYY-MM】【中继源码】【实现】（参考实现代码里已在真实端点上跑的形状）。

| 功能维度 | ① Chat Completions | ② Responses | ③ Gemini | ④ Anthropic | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 端点 | `POST {base}/chat/completions` | `POST {base}/responses`（base 与 ① 同） | `POST {base}/models/{id}:streamGenerateContent?alt=sse`（模型名在 URL！） | `POST {root}/v1/messages` | 【实现】 | §4、§7.1 | — |
| baseURL 归一化 | ✅ base 自带 `/v1`，直接拼 path，**不补 `/v1`**（中继路由在 `/v1` 之下，补了就断） | ✅ 同 ① | ✅ base 自带 `/v1beta`；额外剥尾部 `/models` | ✅ base 是根地址；`anthropicRoot` 剥 `/messages`、`/v1` 再拼 `root + "/v1" + path`；旧 bug 只拼 `/messages` → 照第三方文档粘贴一律 404 | 【实现】 | §4 | — |
| 鉴权头 | ✅ `Authorization: Bearer`；无 key 省略整个头；无 compat 模式；Azure `api-key` 不做 | ✅ Bearer（同 ①） | ✅ `x-goog-api-key`；compat `bearer`／`both`；`?key=` 不实现 | ✅ `x-api-key` + `anthropic-version: 2023-06-01` + `anthropic-dangerous-direct-browser-access: true`；compat `bearer`／`both`（`both` 官方端点拒双凭证） | 【实现】 | §5 | — |
| CORS／浏览器直连 | ✅ 打包版原生 HTTP 无 preflight；本地 Ollama Windows 打包版 403 → http 层按「URL 指向本机」覆盖 `Origin` | — | — | ✅ `anthropic-dangerous-direct-browser-access` 打包版是 no-op，为 dev 浏览器环境而带；不带则官方拒绝浏览器 origin | 【实现】 | §6 | — |
| system 放哪 | ✅ `messages[0].role="system"` | ✅ 顶层 `instructions`（全部 system hoist、`\n\n` join，**恒发哪怕空串**）；上游判不收时改为 `input` 开头 `{role:"developer"}` | ✅ 顶层 `systemInstruction:{parts:[{text}]}`（camelCase） | ✅ 顶层 `system` 字符串（多条 `\n\n` join；`ContentPart[]` 须拍平，否则 `[object Object]`）；消息数组内**无** system 角色 | 【实现】【实测 2026-09-24】 | §2.1、§7.1 | — |
| 消息角色与内容块 | ✅ 容器 `messages[]`；模型侧 `assistant`；`content` 字符串或 part 数组；允许连续同角色；tool 结果 `role:"tool"` + `tool_call_id` | ✅ 容器 `input[]`；user `{role, content:[{type:"input_text"}…]}`；调用 `{type:"function_call", call_id, name, arguments}`；结果 `{type:"function_call_output", call_id, output}` | ✅ 容器 `contents[]`；模型侧 **`model`**；`parts[].text`；结果是 `role:"user"` 的 `parts[].functionResponse` | ✅ 容器 `messages[]`；模型侧 `assistant`；**交替律**：首条 user、相邻交替，连续 tool 合成一条 user；工具轮 content 顺序 `[thinking…, tool_use…]` | 【实现】 | §2、§7.1 | —（坑 21 在 agent-runtime-architecture skill） |
| 文本载体 | ✅ `content` 字符串或 part 数组（兼容层可能镜像 part 数组，§3.2） | ✅ `content:[{type:"input_text", text}]` | ✅ `parts[].text` | ✅ `content` 字符串或 block 数组 | 【实现】 | §2、§3.2、§7.1 | — |
| 图片输入 | ✅ `{type:"image_url", image_url:{url: dataURL}}`（标准） | ✅ `{type:"input_image", image_url:"data:…", detail?}`（**`detail` 与 `image_url` 并列**；标准） | ✅ `{inlineData:{mimeType,data}}`（标准；Google 两种拼写都收，New API Gemini 面 snake_case 🔇 丢图） | ✅ `{type:"image", source:{type:"base64",media_type,data}}` 或 `source:{type:"url"}`（标准） | 【实现】【实测 2026-09-05／23／26】 | §1 表后、§2.2、§7.1 | 111 |
| PDF 输入 | ✅ `{type:"file", file:{file_data: dataURL, filename}}`（base64 形态 **filename 必带**；标准）；DashScope 镜像此形状，仅 qwen3.8-max；火山方舟豆包同形可读，扁平的 `{type:"file", file_data}` ❌ 400 `missing messages.content.file`【实测 2026-09-18】；火山另收 `file:{file_url}`（公网 URL，厂商写仅 ②、① 实测也收）与 `file:{file_id}`（Files API，套餐 key 无上传入口）【实测 2026-09-23】，见第 1 篇 §9.3 | ✅ `{type:"input_file", filename, file_data}` 或 `file_url`（标准） | ✅ 同 `inlineData` + `application/pdf`（标准；3.8 Flash 一页按图像计 520 token） | ✅ `{type:"document", source:{type:"base64",media_type,data}}` 或 `source.type:"url"`；纯文本 `document` + `citations.enabled`（标准） | 【实现】【实测 2026-09-18／23／26】 | §1 表后、§7.1 | — |
| 视频输入 | ⚠ `{type:"video_url", video_url:{url: dataURL}}` **是厂商扩展不是族片段**（千问首创；`fps` 百炼在片段旁、方舟文档在 `video_url.fps`）；按平台放行 | — 来源未提及 | — 来源未提及（Gemini 本身读视频，经 OrcaRouter ① 翻译层 🔇 丢） | — 来源未提及 | 【实测 2026-09-28】 | §1 表后 | — |
| 音频输入 | ⚠ 仅 ASR 篇：小米 MiMo 走 ① 族 `input_audio` 内容块（【实现】）；02–06 篇未提及 | — | — | — | 【实现】 | 16 §10.2 | — |
| 流式事件骨架 | ✅ SSE 匿名 chunk，客户端拼 `delta`，`data: [DONE]` 收尾；`content` 可能是 part 数组 | ✅ 类型化事件 `response.created → output_item.added → *.delta → *.done → output_item.done → response.completed`；只读 `data:` 行；容忍 `[DONE]`；无视 `obfuscation` | ✅ SSE，**每 chunk 是完整响应对象**（parts 追加，不是 delta）；流末光秃秃 `{text:""}` | ✅ 类型化 `message_start → content_block_start → content_block_delta → content_block_stop → message_delta → message_stop`；只认 `data:` 行 | 【实现】【实测 2026-08-14／2026-09-26】 | §3、§7.2 | 108 |
| 流式终止与 usage 位置 | ✅ `finish_reason: stop／length／tool_calls／content_filter`；usage **须开 `stream_options:{include_usage:true}`**，随末 chunk 到且 `choices:[]` | ✅ `response.completed{response.usage}`／`incomplete{incomplete_details.reason}`／`failed`／`error`；无终止事件的流照样 finish（usage 记 0） | ✅ `finishReason: STOP／MAX_TOKENS／SAFETY／RECITATION／MISSING_THOUGHT_SIGNATURE…`；【文档】每 chunk 带 `usageMetadata`；【实测】Vertex 只末块带 → 取最后见到的值，不累加 | ✅ `stop_reason: end_turn／tool_use／max_tokens／refusal／pause_turn`；usage 分两次：`message_start` 给 input，`message_delta` 给 output + stop_reason | 【实现】【实测 2026-09-26】 | §3.2、§7.2；06 §1 | 108、109 |
| 思考强度字段与词表 | ✅ 顶层 `reasoning_effort`；六档 → off=`"none"`、low／medium／high 同名、max=`"max"`；**`"none"` 不是族级关闭**（DeepSeek 需 `thinking:{type:"disabled"}`） | ✅ 嵌套 `reasoning:{effort, summary:"auto"}`；端点七档 `none／minimal／low／medium／high／xhigh／max`，菜单取六档；off → `{effort:"none"}` 无 summary | ✅ `generationConfig.thinkingConfig.thinkingLevel: LOW／MEDIUM／HIGH`（**全大写**）+ 必带 `includeThoughts:true`；off → `"LOW"`（关不掉；旧 `MINIMAL` 3.8 Flash 400 已推翻）；AI Studio 直连档位值小写 `"low"` 也收、枚举外 `"lowest"` ❌ 400【实测 2026-09-28】（03 §2） | ✅ `thinking:{type:"adaptive"／"enabled"／"disabled", budget_tokens?, display?}` + `output_config.effort: low／medium／high／max`；off → `effort:"low"`（`disabled` 多款 400）。第三方 ④ 兼容层的默认值与 `disabled` 结局按平台 × 模型：收下真关（DeepSeek、百炼千问、智谱 4.6、MiniMax-M3）／拒绝会响（智谱 5.3 系 1210、百炼托管 M2.5／glm-5.3 点名 `enable_thinking`）／收下照想 🔇（MiniMax-M2.7、百炼 kimi-k2-thinking），见 03 §3.5 | 【实现】【实测 2026-09-26】【实测 2026-09-28】【文档 2026-08】 | 03 §2、§3、§3.5、§7.1 | 114、147、217、222 |
| 思考取回位置 | ✅ `delta.reasoning_content`／`delta.reasoning`（候选表按「有非空文本」取）+ `<think>` 兜底切分；方舟 2.1 起 `reasoning_content` 只是摘要、密文在 `delta.encrypted_content` | ✅ `response.reasoning_summary_text.delta`（`reasoning_text.delta` GPT-5.x 未出现、千问文档有）；`reasoning_tokens:0` 时无 reasoning 条目 | ✅ `part.thought === true` 的文本 part（3.8 Flash 一整段给出，流式不逐字）；`thoughtSignature` 挂在正文 text part 上 | ✅ `thinking_delta.thinking`（仅发了 `display:"summarized"` 才有）；流形 `content_block_start` 带 `signature:""` → `thinking_delta`×N → `signature_delta` | 【实测 2026-09-14／23／26】 | 03 §4、§6、§7.2 | 107 |
| 思考回传载体与缺失后果 | ✅ `_reasoning:{field,text}` 原字段名回传（方舟旁加 `encrypted:{modelId,value}`）；只挂带 tool_calls 的 assistant；缺失：DeepSeek ❌ 400、方舟 🔇 降级、GLM 接受 | ✅ `_responseItems:{modelId,items}` 收自 `output_item.done` 整组放回 `input`；缺失**不报错**（四种都 200） | ✅ `_geminiModelParts` 整组原样（含 thought parts 与 `thoughtSignature`；剔除流末 `{text:""}`）；缺失：200 + `finishReason: MISSING_THOUGHT_SIGNATURE`，3.8 Flash ❌ 400 | ✅ `_thinkingBlocks:{modelId,blocks}` 有序原样（含 `redacted_thinking`）；缺失 🔇 静默关掉这轮思考；改 `signature` ❌ 400 | 【文档 2026-08】【实测 2026-09-23／26】 | 03 §5、§7.3；§7.3 | 137 |
| JSON mode 字段 | ✅ `response_format:{type:"json_object"}`；前置：上下文含 "JSON" 字样否则官方报错（千问 400），缺则**条件追加** cue | ✅ `text:{format:{type:"json_object"}}`；缺 "json" 同样 400 | ✅ `generationConfig.responseMimeType:"application/json"` + cue **总是双发**（有模型 🔇 无视） | ❌ **无 JSON mode 参数**（发 `response_format` 硬 400）；cue 是全部机制；档位只有 `json_schema`／`off` | 【文档】【实测 2026-09-19／26】 | 04 §2、§5.1 | — |
| JSON schema 字段与 strict | ✅ `response_format:{type:"json_schema", json_schema:{name, schema, strict:true}}`（**`strict` 要发**）；默认不用，按模型 id 表抬升 | ✅ `text:{format:{type:"json_schema", name, schema}}`（无 `json_schema` 包装层；**不发 `strict`**，官方自动升 true；New API `[Pro]` 档不论写不写都 🔇 丢 format——旧：显式 `strict:true` 才丢 → 新：2026-09-24 扩展，其余上游两种写法都执行，见 22 §3） | ✅ `generationConfig.responseJsonSchema`（标准 JSON Schema）或旧 `responseSchema`（OpenAPI 方言）**互斥只发一个** | ✅ `output_config:{format:{type:"json_schema", schema}}`（与 `effort` 同对象合并）；官方限制 `additionalProperties:false` 必须、不支持 `min/max*`、`pattern`、递归 `$ref` | 【实测 2026-09-23／24／26】 | 04 §2、§5.1 | — |
| 工具定义形状 | ✅ 嵌套 `{type:"function", function:{name, description, parameters}}` | ✅ 扁平 `{type:"function", name, description, parameters, strict:false}`（**`strict:false` 必须显式**） | ✅ `tools[0].functionDeclarations[{name, description, parameters}]` | ✅ `{name, description, input_schema}`（唯一改 schema 字段名） | 【实现】 | 05 §1；§7.1 | — |
| 模型发起调用（非流式形状） | ✅ `assistant.tool_calls[]`（带 id；arguments 是 **JSON 字符串**） | ✅ `output` 条目 `{type:"function_call", call_id, name, arguments}`（流式收自 `output_item.done`） | ✅ `parts[].functionCall`（旧型号**无 id**，3.8 Flash 起带 `id`【实测 2026-09-26】；args 是**已解析对象**） | ✅ block `type:"tool_use"`（带 id；input 是对象） | 【实现】【实测 2026-09-26】 | §3.2、§7.2；05 §3 | — |
| tool_choice 词表 | ✅ `"auto"／"none"／"required"／{type:"function", function:{name}}` | ✅ `"auto"／"none"／"required"／{type:"function", name}`（去 `function` 包装；只随函数工具发；无「思考中禁止强制」） | ✅ `toolConfig.functionCallingConfig.mode: AUTO／ANY／NONE`；具名 = `ANY` + `allowedFunctionNames:[name]` | ✅ `{type:"auto"／"any"／"tool"(+name)／"none"}`；**只在声明了本地工具时才发** | 【实现】 | 05 §2；§7.1 | — |
| 流式工具参数拼接 | ✅ 按 `delta.tool_calls[].index` 分组拼 `arguments` 字符串；**id 也可能分片**（`entry.id += partial.id`） | ✅ 按 `output_index` 分组；参数两次到达（delta + `function_call_arguments.done` 整串），**以整串为准** | ✅ `functionCall` 一次给全（已解析对象）；旧型号无 id 自造 `gtc_…`，3.8 Flash 起带 `id` | ✅ 按块索引拼 `input_json_delta.partial_json`；**空参数不流 delta，`""` → `"{}"`** | 【实现】【实测 2026-08-08／2026-09-26】 | 05 §3；§3.2 | 105、106 |
| 工具配对义务 | ✅ `tool_call_id` 配对；空串 id 按缺失处理（否则下一轮重复 id 400） | ✅ `call_id` 配对；`function_call_output` 回 `call_id` | ✅ 靠**函数名**匹配（旧型号）；带 id 时回 id 也收；同名并行调用对应关系在旧型号不可表达 | ✅ `tool_use_id` 配对；一轮所有 `tool_result` 须合在一条 user 里一起到达 | 【实现】【实测 2026-09-26】 | 05 §4；§2 | 106 |
| 服务端工具 wire 形状（web_search／code／fetch） | Ⓓ 顶层 `enable_search:true`、`search_options:{search_strategy:"agent_max"}`、`enable_code_interpreter:true`（只放行 compat）；OpenAI 形 `web_search_options`；**搜索无痕**无来源 | ✅ `tools:[{type:"web_search"}]`（OpenAI／xAI 同形）、千问 `web_extractor`／`web_search_image`／`image_search`／`code_interpreter`；事件 `web_search_call`、`code_interpreter_call` 等 | ✅ `tools[]` 独立项 `{googleSearch:{}}`／`{urlContext:{}}`／`{codeExecution:{}}` 与 `functionDeclarations` 并列；回报在 `groundingMetadata`、`executableCode`／`codeExecutionResult` | ✅ 版本化条目 `{type:"web_search_20250305", name:"web_search", max_uses:10}`（也见 `web_search_20260209`、`web_fetch_20250910`、`code_execution_20250825`）；响应 `server_tool_use → web_search_tool_result → citations` | 【实测 2026-09-17／18／26】 | 05 §5 | 10、192、193 |
| 服务端工具续跑 | — 来源未写 ① 官方续跑信号 | — 来源未写 | — 来源未写 | ✅ `stop_reason:"pause_turn"` → verbatim 续跑（`encrypted_content` 一字不改，重建块 400；`MAX_PAUSE_CONTINUATIONS = 4`）；兼容端（MiniMax）停在 `*_tool_result` 报 `end_turn` 且拒收自己的块 → transcript 纯文本续跑 | 【实测 2026-08】【实现】 | 05 §6 | — |
| 工具按需加载 | ❌ 无 | ✅ GPT-5.4+：`defer_loading:true`、`{type:"tool_search", execution:"server"／"client"}`、`{type:"namespace"}`、`{type:"additional_tools", role:"developer", tools}`；下一轮 `input` **必须**回 `tool_search_output`；xAI 规格有实测 403 | ❌ 请求带 `defer_loading` 整个被拒（第三方报告） | ✅ Claude 4.5+：`defer_loading`、`tool_search_tool_regex_*`／`_bm25_*`；至少一个非延迟工具否则 400；与 `cache_control` 同现 400 | 【文档 2026-09】【实测 xAI 403】 | 05 §7 | — |
| usage 字段与缓存字段 | ✅ `usage.prompt_tokens／completion_tokens`（含思考）、`prompt_tokens_details.cached_tokens`（input 子集）、`completion_tokens_details.reasoning_tokens`；DeepSeek 顶层 `prompt_cache_hit_tokens／miss` | ✅ `usage.input_tokens／output_tokens`、`input_tokens_details.cached_tokens`／`cache_write_tokens`、`output_tokens_details.reasoning_tokens`；`attribution.request_fields.instructions.input_tokens` | ✅ `usageMetadata.promptTokenCount／candidatesTokenCount／thoughtsTokenCount／toolUsePromptTokenCount／cachedContentTokenCount`；**思考不在 candidates 里**、toolUse 在 prompt 之外 | ✅ **三桶不重叠**：`input_tokens` + `cache_read_input_tokens` + `cache_creation_input_tokens`（**互不重叠，要相加**）；`output_tokens_details.thinking_tokens`（子集）；`server_tool_use.{web_search_requests,…}` | 【实现】【实测 2026-09-26】【文档；修复 2026-09-14】 | 06 §1 | 186 |
| 错误信封 | ✅ HTTP 4xx + body；智谱 `{"error":{"code":"1210","message"}}` 业务码是字符串；MiniMax `base_resp.status_code`（1004／1008／1002，0 成功）；SSE 体内 `data:{"error"}` | ✅ `response.failed`／`error` 事件／裸 `{error}`（无 `type`）；`response.incomplete.incomplete_details.reason` | ✅ 400 原文（Vertex）；OrcaRouter 改写成 `{"error":{"message","type":"invalid_argument","param":"","code":400}}`，路径 `***` | ✅ 400 带原文（``Invalid `signature` in `thinking` block``）；官方 `error.type`；OrcaRouter 改写成 `{"error":{"type":"<nil>",…},"type":"error"}`；第三方 ④ 兼容层各有信封：DeepSeek 422 反序列化文案、智谱 `{"type":"invalid_request_error","code":"1210","message":"[1210][…][<request id>]"}`、MiniMax `{"type":"invalid_request_error","message":"invalid params, … (2013)"}`、百炼透传上游 `<400> InternalError.Algo.InvalidParameter: … enable_thinking …`（点名别家协议字段）；MiniMax／DeepSeek 未知模型名不报错静默改映射（06 §2） | 【实测 2026-09-19／24／26／28】 | 06 §2；03 §3.5 | 112、219、221 |
| HTTP 200 里的失败形态 | 🔇 静默丢弃；`finish_reason: content_filter`／智谱 `sensitive`／`network_error`／`model_context_window_exceeded`；空 `content` + `stop` 与坏中转无法区分 | 🔇 流里 `response.failed`（千问 `Normal mode does not support Code interpreter…`）；`status:"completed"` 的空 message 条目是**正常结束** | 🔇 `promptFeedback.blockReason`；`finishReason ∈ {SAFETY, PROHIBITED_CONTENT, BLOCKLIST, RECITATION, SPII, IMAGE_SAFETY}`；`GEMINI_REQUEST_FAULTS`（`MISSING_THOUGHT_SIGNATURE`、`UNEXPECTED_TOOL_CALL`、`TOO_MANY_TOOL_CALLS`、`MALFORMED_RESPONSE`） | 🔇 `stop_reason:"refusal"`（必须 throw）；丢 thinking 块静默关思考；翻译层中转丢 PDF／URL 图片 | 【实测 2026-09-15／23】【文档 2026-09】 | 06 §2；§7.2 | 109 |
| 未知顶层字段的态度 | ❌ 官方端点直接拒绝（`enable_search` 等 400）；智谱一律放过；方舟 🔇 忽略 `enable_thinking` | ✅ 官方与 xAI 忽略（仍按最小公倍数发送） | — 来源未写官方口径；New API Gemini 面 🔇 无视未知键（snake_case 丢图） | ❌ 官方**未知键 400**；第三方 ④ 兼容层顶层未知字段**四家都 200 放过**，`thinking.type:"bogus"` 四家四种：MiniMax 🔇 200 且开思考、DeepSeek ❌ 422 点名枚举、智谱 ❌ 1210、百炼 ❌ 400 `Request body format invalid`（03 §3.5） | 【实测 2026-09-18／19／28】【实现】 | 03 §2、§3.5；§1 表后、§7.1 | 114、217、220 |
| max tokens 字段 | ✅ `max_tokens` → `max_completion_tokens`（选填；被拒自动换拼写重试一次） | ✅ `max_output_tokens`（账号池上游 🔇 无视且回显抓不到） | ✅ `generationConfig.maxOutputTokens`（选填） | ✅ `max_tokens` **必填、无服务端默认**；`budget_tokens` 必须 < `max_tokens` | 【实现】【实测 2026-09-24】 | 06 §5 | 65 |
| 温度与思考的关系 | — 来源未写族级约束（方舟 ① 面 `0／0.1／0.3` 都收敛） | ⚠ 官方口径未写；中转站账号池 `temperature:0.5` 🔀 回显 `1.0`，网关 500 | — 来源未写 | 📄 官方思考开着只收 `temperature:1`（别的 400）→ **在想就不发温度**；`switch` 类目关思考时按类目声明（方舟听、`0` 等于没发；MiniMax 不听） | 【文档】【实测 2026-09-24／28】 | 03 §3.4；06 §2 | — |

**表里的「图片」「整份文件」形状被接受 ≠ 内容送到了模型。** 经翻译层的中转站（New API 中转站 Kiro 渠道的 Claude，【实测 2026-09-23】，第 1 篇 §9.2）：
④ `document` 的 base64 与 `source.type:"url"` 两种、① 的 `file` 片段（PDF）都 200 但**静默丢弃**，模型答「没看到文档」，且那条请求要 33 s（别的 3 s）；
④ 图片 `source.type:"url"` 与 ① http `image_url` 也被丢，只有 base64 / data URL 图片送得到；纯文本 `document` + `citations.enabled` 内容读到了，
但响应里**没有 `citations` 字段**。验证用一个模型猜不出的内容（PDF 里写一句「The secret word is PELICAN 7342」、一张纯色图问颜色），
看答案对不对，不能只看是否 200。

同一台中转站上**别的渠道不一样**（【实测 2026-09-23】，landscape.md §7 第十六个样本，④ 面）：CC 与 AWSb（Bedrock 正向）PDF 都读到（AWSb 要 30 s）；
anti 丢 PDF，**连纯文本 `document` 也没读到**；只有 AWSb 返回 `citations`；URL 图片 Kiro / CC 丢、anti 500 `failed to decode base64 data`、
AWSb 400 `URL sources are not supported`。base64 图片四个渠道都送得到——**整台中转站可移植的只有内联 base64 图片**，文档能力按渠道（第 1 篇 §9.2）。

同一台上的 GPT-5.6（【实测 2026-09-24】，第十七个样本，① ② 两族、四个上游）：PDF（② `input_file` 的 `file_data` / `file_url`、① `file`）与 data / http 图片**全部读到**——
丢文档是 Claude 翻译层的事，不是这台中转站的通病。http 图片放在拒爬虫的主机上时四档各自失败（其中一档是中转站自己下载失败，整条 500），见第 6 篇 §2。

回包原样的网关上（OrcaRouter，【实测 2026-09-26】，第十八个样本「再补测」B，第 1 篇 §9.5）：① `file`、② `input_file`、④ `document`（Sonnet 5、Opus 5.5）、
③ `inlineData` + `application/pdf` **四面都读到**。计费两点：③ 把这一页 PDF **按图像计 520 token**（不是按抽出的文字）；④ Sonnet 5 那次请求**没带
`cache_control`** 却记了 1,630 个缓存写入 token（Opus 5.5 那次没有，原因未明）——与 `web_search` 的自动缓存（第 6 篇 §1）同一种现象，
`cache_creation` 不能当「我方打了断点」的判据。

**视频输入：`video_url` 不是 ① 族的片段，是厂商扩展——按平台放行，不按族。** 片段形状 `{type:"video_url", video_url:{url: dataURL}}`
（百炼的抽帧率 `fps` 写在片段旁边；火山方舟文档写在 `video_url.fps` 里）。Chat Completions 规范里没有它，是千问一族兼容端先加的；
「这是 ① 族端点」回答不了「收不收」，和千问私有的 `vl_high_resolution_images` 按族放行、漏到智谱是同一类错——拿协议族回答了平台的问题。
【实测 2026-09-28】（simple-ai-writer landscape.md §7 第十九个样本；一段 4 秒片段、前 2 秒纯红后 2 秒纯蓝、640×480、25 fps、5 KB，问「先后出现了哪两种颜色」，走真实 ① 适配器）：

| 端点 | 模型 | 结果 | 输入 token（不带 → 带片段 → 带 `fps: 1`） | 判定 |
| --- | --- | --- | --- | --- |
| 百炼（对照） | `qwen3-vl-plus` | 200，答对 | 34 → 1,241 → 641 | 收；`fps` 生效 |
| 火山方舟 Coding Plan（`/api/plan/v3`） | `doubao-seed-2.0-mini` | 200，答对 | 59 → 2,795 → 2,795 | 收；`fps` 不改这段片段的账单 |
| DeepSeek | `deepseek-flash` | 422 `unknown variant video_url, expected one of text, image_url, file` | — | 不收（明确拒绝） |
| xAI | `grok-4.3` | 400 `Empty content block` | — | 不收（片段被当成空块） |
| OrcaRouter ① | `google/gemini-3.8-flash` | **200，答错**（三次三种颜色组合） | 25 → 25 | **静默丢弃** |
| OrcaRouter ① | `openai/gpt-5-mini` | 400 `The upstream provider rejected this request` | — | 不收 |

- **OrcaRouter 的 Gemini 是最坏的一种**：Gemini 本身读视频，丢在网关的 ① 翻译层（第 1 篇 §9.5）；200、输入 token 与不带片段逐个相同，回答照着提示里的示例格式瞎编。作者看不出视频没到。
- **火山方舟的 `fps`**：两种拼法（片段旁边 / `video_url.fps`）、取 1 与 0.2，输入 token 都与不带时相同（原始请求对比 2,779）。4 秒片段可能在最少帧数之下，
  所以只能记「这段片段上不改账单」，不能记「方舟不认 `fps`」。智谱收 `video_url`、忽略 `fps`（更早的样本）。
- **百炼对片段本身挑剔**：同样两种纯色，320×240 / 10 fps 的版本回 400 `Invalid video file`；加一层噪点、或改成 640×480 就收。夹具先在对照端点上过一遍（06 §8 第 5 条同理）。
- 没量到的：OpenAI 官方、火山方舟按量付费（与 Coding Plan 同源，大概率同样收，但按规矩要样本）。
- **测法**：一段模型**猜不出来**的片段（先红后蓝），看三件事——HTTP 状态；答没答对（200 而答错 = 静默丢弃，按不收记）；输入 token 比同一问题不带片段时多了多少（没多 = 没读）。
  只看 200 或只看「回答里提到了视频」都会把静默丢弃判成支持。
- **做法**：视频输入做成平台格——实测收的平台点名 `true`，实测不收的写 `false`（与「没测过」分开：没测过落到「未列出」，不发）；
  中转站 / 自定义渠道背后可能正是百炼，判「未知」而不是「不收」。已声明视频、却落在不发上的旧模型行保留声明，界面说「已声明，不发送」。

**④ 面兼容层对未知字段／非法思考值：四家四种报法。**「④ 官方对未知顶层键 400」（§7.1 规则 5 与 §1 表「未知顶层字段的态度」行的族级口径）在第三方的 ④ 兼容层上**不成立**——顶层未知字段四家都 200 放过（① 族的 `reasoning_effort` 也放过）；
`thinking.type:"bogus"` 才分出四种【实测 2026-09-28，各家官方直连，每格一次；simple-ai-writer landscape.md 第四、六、十四、二十个样本】：
MiniMax 一律 200 静默吞下，`thinking.type:"bogus"` 反而**开启**思考；DeepSeek 422 反序列化报错并点名枚举（``unknown variant `bogus`, expected one of `adaptive`, `enabled`, `disabled` ``）；
智谱借用「关不掉」的 1210；百炼 400 `Request body format invalid`，不点名字段。报错原文、各家其它非法值（`top_p`、`temperature`、`budget_tokens`、未知模型名）与对「按 400 学降级」的影响见 03 §3.5；
不这样会怎样：拿「发个 bogus 看 400 不 400」当探测，在 MiniMax 上会把思考打开且不响（坑 217、220）。

### 1.1 非对话面与私有扩展一览

四族之外，从一条 base + 一份报文怎么认出它是什么面（「判定标准」）、端点在哪；细节一律在指向的正文篇（03／05 对话私有扩展；13 出图；14 视频；16 ASR），本节不展开。四族本身的判定标准见第 1 篇 §2 与上表「端点」「消息角色与内容块」「流式事件骨架」三行。面的编号：Ⓓ DashScope 私有 ／ 🖼 出图 ／ 🎬 视频 ／ 🎤 ASR。

| 面 | 判定标准 | 端点（鉴权） | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- |
| Ⓓ DashScope 私有扩展（挂在 ① compatible-mode 上） | ① 形状 + 顶层私有键：`enable_thinking`、`thinking_budget`、`enable_search`、`search_options`、`enable_code_interpreter`、`vl_high_resolution_images`、`video_url` 片段（发起者）；`enable_search` 等只放行 compat（api.openai.com 对未知顶层键 400） | 千问 compatible-mode（① 面）；另有千问 Responses 面（②）；Bearer（与 ① 同） | 【文档】【实测 2026-09-17／28】 | §1 表后；03 §3；05 §5 | 10、74、77、78 |
| 火山方舟豆包私有扩展（① ② ④ 三面并存） | ① 面顶层 `thinking:{type}`、`reasoning_effort` 七档、`delta.encrypted_content`；④ 面 `thinking:{type:"disabled"}` 真关 | Coding Plan 套餐 base `…/api/plan/v3/chat/completions`（① 面）；② 面；④ 面；Bearer（套餐 key） | 【实测 2026-09-18／23／28】 | 03 §3.2、§3.4；01 §9.3 | 114、137 |
| 智谱私有 REST（应用执行的联网端点，非对话协议） | 同一把 key、同一前缀下的独立端点，body 不含 messages | `POST /web_search` body `{search_query, search_engine, search_intent}`；`POST /reader` body `{url, return_format?, …}`；Bearer | 【实测 2026-09-19】 | 05 §5「服务端工具归平台」 | — |
| Bedrock 上的 Claude（经 New API AWSb 正向渠道，④ 形状；**不是** Bedrock Converse——Converse 是 camelCase + SigV4 的第五种 body，本库未接，见 01 §2） | 经 New API `/v1/messages` 暴露，④ 形状；区别只在校验会响：乱写 effort／思考时 `temperature:0.3`／篡改 `signature` 都 400 与官方同文 | New API `/v1/messages` → Bedrock 正向；鉴权由 New API 代管 | 【实测 2026-09-23】 | 03 §3.3；§1 表后 | — |
| 🖼 images-api | `POST /images/generations` JSON；编辑 `POST /images/edits` **multipart**，文件字段 1 张 `image`、多张 `image[]`；New API 式中继的 `/images/generations` **只认 Imagen** | `{base}/images/generations`、`/images/edits`；Bearer | 【实现】【实测 2026-09-05】 | 13 §2、§4.2、§6 | — |
| 🖼 chat 出图（chat-image） | 走 `POST /chat/completions`，模型被作者声明为出图模型（`isImageGenerator:true`）；纯文本消息也要发成单元素 part 数组 | `{base}/chat/completions`；Bearer | 【实测 2026-09-05】【实现】 | 13 §2、§6 | 110 |
| 🖼 gemini | `:generateContent` + `responseModalities:["TEXT","IMAGE"]` | `POST /models/{id}:generateContent`；`x-goog-api-key` | 【实现】 | 13 §2、§7 | — |
| 🖼 imagen | `:predict`（**不是** `:generateContent`）；无编辑、无 usage | `POST /models/{id}:predict`；`x-goog-api-key` | 【实现】 | 13 §2、§4.2、§7 | — |
| 🖼 dashscope 同步 | 原生 `/api/v1`（不走 compatible-mode）；body 两段式：顶层只有 `model` 与 `input`，旋钮全在 `parameters`；尺寸拼写 `宽*高` | `POST {原生base}/services/aigc/multimodal-generation/generation`（原生 base = 供应商行剥 `/compatible-mode/v1` 拼 `/api/v1`）；Bearer | 【实测 2026-09-19】【外部实测 2026-09-04】【文档 2026-08／09】 | 13 §3、§4 | 101、102 |
| 🖼 dashscope 异步 | 提交路径与同步不同、body 一致，头 `X-DashScope-Async: enable`；轮询 `GET /tasks/{id}` | `POST /services/aigc/image-generation/generation` → `GET /tasks/{id}`；Bearer | 【文档 2026-08】 | 13 §3、§4 异步任务流 | — |
| 🖼 ark（火山方舟 Seedream） | 与 OpenAI 同路径但 body 是超集且缺字段：无 `n`／`quality`，参考图走 JSON `image`，`watermark` 默认 true，档位 `1K`…`4K` 或 `WxH` 不可混用 | `POST {base}/images/generations`（按量／套餐两个 base）；Bearer | 【文档 2026-09-18／22】【实测 2026-09-18／23】 | 13 §4.1 | 83、127、130 |
| 🖼 xai-images | `/images/generations`；编辑 `/images/edits` 是 **JSON**（不是 multipart）；清晰度 `resolution: 1k／1.5k／2k`（不是 `size`）；`usage` 只有 `cost_in_usd_ticks` | `/images/generations`、`/images/edits`；`GET /v1/image-generation-models/{id}` 回价目；Bearer | 【文档 2026-09】【实测 2026-09-21／22】 | 13 §4.2、§7 | 123、124、125 |
| 🖼 minimax | `POST /v1/image_generation`（挂在 `/v1` 下但**不是** Images API）；`data.image_urls[]` + `base_resp` | `/v1/image_generation`；Bearer | 【实现／文档】 | 13 §2、§4.2、§7 | — |
| 🖼 midjourney | midjourney-proxy 的 `/mj/*`，异步 submit → fetch，参数改写成 `--ar/--v/--s/--c/--q` 拼进 prompt | `POST /mj/submit/imagine` → `GET /mj/task/{id}/fetch`；代理自定 | 【实现】 | 13 §2、§4.2 | — |
| 🎬 视频 · 千问 wan3.0 | submit/poll；提交带 `X-DashScope-Async: enable`；轮询端点与图片任务、ASR filetrans 共用 | `POST /api/v1/services/aigc/video-generation/video-synthesis` → `GET /api/v1/tasks/{id}`；Bearer | 【实测 2026-08-29】【文档 2026-08】 | 14 §2、§3 | — |
| 🎬 视频 · MiniMax v2 | submit/poll；`resolution` 与 `duration` **必填无默认**；创建响应只有 `{"task_id"}` | `POST /v2/video_generation` → `GET /v2/query/video_generation/{id}`（`api.minimaxi.com`）；Bearer | 【实测 2026-08-29】 | 14 §2、§3 | 113 |
| 🎬 视频 · xAI | submit/poll；pending 是 **HTTP 202**；报价只在 done 回包 `usage.cost_in_usd_ticks` | `POST /v1/videos/generations` → `GET /v1/videos/{request_id}`；Bearer | 【实测 2026-09-22】 | 14 §2、§3 第 8 条 | 129 |
| 🎬 视频 · OpenAI Sora | submit **multipart**；`/content` 是 API 端点下载**要带**认证头 | `POST /v1/videos` → `GET /v1/videos/{id}` + `/content`；Bearer | 📄【文档】⚠ 未标注实测 | 14 §2、§3 第 4 条 | — |
| 🎬 视频 · Google Veo | `:predictLongRunning` + operations `GET {done:bool}` | `:predictLongRunning` → operations `GET`；`x-goog-api-key` | 📄【文档】⚠ | 14 §2 | — |
| 🎬 视频 · 中继 openai-videos | 中继把 sora／grok-imagine／wan2.5／kling／hailuo 收敛到 OpenAI 式 `/v1/videos`；**同一模型 id 在官方与中继走不同协议** | `/v1/videos`；Bearer | 【实现】 | 14 §4 | — |
| 🎤 ⓐ OpenAI 兼容转写 | multipart 文件字段 `file`，`response_format=verbose_json` 给 `segments[].start/end`（**秒**） | `POST {base}/audio/transcriptions`；Bearer；本地无密钥时不发 | 【文档】【实现】（本库 ⓐ 无实测、无离线测试） | 16 §1、§3、§10.2 | — |
| 🎤 ⓑ 百炼同步识别 | base64 data URI 放 JSON body `input.messages[].content[{audio}]`；头 `X-DashScope-SSE: disable`；**无句级时间戳** | `POST {base}/services/aigc/multimodal-generation/generation`（默认 `https://dashscope.aliyuncs.com/api/v1`）；Bearer | 【实测 2026-09-13】 | 16 §1、§4 | — |
| 🎤 ⓒ 百炼录音文件转写（filetrans） | 模型名以 `-filetrans` 结尾；五步：取凭证 → OSS 表单上传（不带 Authorization）→ 异步提交 → 轮询 → 下载结果 JSON；句级 + 词级**毫秒** | `GET /uploads?action=getPolicy&model=…` → OSS → `POST /services/audio/asr/transcription`（头 `X-DashScope-Async: enable` + `X-DashScope-OssResourceResolve: enable`）→ `GET /tasks/{id}`；Bearer（上传与下载两步**不带**） | 【实测 2026-09-13】 | 16 §1、§5 | — |
| 🎤 附：私有 SDK／HTTP | 豆包 `X-Api-*` 头 + 响应头 `X-Api-Status-Code == 20000000` 判成败；Gemini transcribe 走 `interactions.create`；Deepgram／ElevenLabs／CAMB／Gladia 各自 SDK | 各家私有 | 【实现】（本库未独立复核报文） | 16 §10.2 | — |

出图 route 的请求／响应统一化要点、视频 submit/poll 不变量、ASR 三种线格式的对照表都在 13 §5–§7、14 §1／§3、16 §1；结论格在 23 §1.1／§2／§3.1。

## 2. 消息转换的结构性修补

内部消息是 OpenAI 形状（见第 1 篇），转换到 ③④ 时不是逐字段改名，而是要做**结构性修补**——这是适配器里真正的活。

### 2.1 Anthropic（最严格）

出处：simple-ai-writer `src/lib/ai/anthropic.ts` 的 `convertToAnthropicMessages` / `extractSystem`。

规则与修补，逐条：

1. **交替律**：首条必须是 `user`，相邻消息必须交替角色。OpenAI 形状允许连续同角色（agent 循环会自然产生 assistant+assistant）。转换器必须做三件事：
   - 丢弃开头的 assistant 消息；
   - 合并同角色相邻消息；
   - **把连续 tool 消息合并成一条 user 消息**——Anthropic 要求一轮的所有 `tool_result` 一起到达，拆开发既违反协议又破坏交替律。
2. **system hoist**：消息数组内没有 system 角色，全部 system 消息 hoist 到顶层 `system` 字段（多条用 `\n\n` join）。陷阱：内容若是 `ContentPart[]`，必须先用 `textOf` 拍平成字符串，否则序列化成 `[object Object]`。
3. **工具轮 assistant 消息的 content 顺序**：`[...thinkingBlocks, ...tool_use blocks]`——thinking 在前且原样（顺序即 400 红线，详见第 3 篇回传义务）。
4. **labelAuthorText**：tool_result 和作者（用户）的话都住在 `role:"user"` 里，合并可能产生 `[tool_result, "continue"]` 这种消息——作者的话被装进了模型当作工具输出读的信封。实测事故：作者的三次重试（continue/retry/重试）混进 `read_file` 结果、被后续 39 轮反复重发，模型读成常设指令（见第 11 篇坑 21）。修法：合并进带 tool_result 的消息的第一条文本前加 【…】 标签，标明这是作者发言，使其可归因。
5. **tool_use 的 `name` 兜底链**：`tc.function.name || toolCallIdToName.get(tc.id) || "unknown_function"`——id→name 表预先扫全量 messages 建好。历史里的 tool_calls 可能来自持久化或另一族转换，name 缺失不能让整条请求炸掉。

### 2.2 Gemini

出处：simple-ai-writer `src/lib/ai/gemini.ts` 的 `convertToGeminiContents`。

1. `assistant` → `model` 角色。
2. tool 消息 → `role:"user"` 的 `functionResponse` parts。**旧型号的 Gemini 协议层没有调用 id**，靠预建的 id→name 表查函数名回填。推论：同名函数的并行调用，其结果对应关系在协议上**不可表达**——只能接受这个信息损失，不要试图发明私有配对机制。
   【2026-09-26 补】Gemini 3.8 Flash（Vertex）的 `functionCall` 带 `id`，`functionResponse` 带不带 `id` 都收——有 id 就回 id，上面的信息损失在这代型号上消失（第 5 篇 §3）。
3. **请求键一律 camelCase**（`inlineData` / `mimeType` / `systemInstruction`）：Google 两种拼写都收，但转 ③ 形状的中转（New API 的 Gemini 面）
   只认 camelCase、无视未知键——snake_case 的请求 **200 照回，图片和系统提示被静默丢弃**【实测 2026-09-05；坑 111】。用测试遍历整个
   payload，断言没有带下划线的结构键。Google 本身两种都收：【实测 2026-09-26】3.8 Flash（Vertex，经 OrcaRouter）`inlineData` 与 `inline_data` 都看得见图；
   一张 16×16 的 PNG 记 **1,098** 个 prompt token（默认媒体分辨率）。
4. 工具轮 assistant 若带 `_geminiModelParts`，**原样整组回传**而不重建——为保住 `thoughtSignature`（第 3 篇详述）。规则：能原样回传的历史，永远不要"理解后重建"。
   唯一例外：流末光秃秃的 `{text:""}`（无签名、无数据）剔除，否则第二轮可能 400（第 5 篇 §3）。

## 3. 流式解析：共同骨架 + 三家差异

### 3.1 共同骨架（各族适配器共享同一 SSE 读法）

```
res.body.getReader() + TextDecoder({stream: true})
→ 按 "\n" split
→ 最后一个不完整行留到下次 read（行缓冲）
→ 流结束后再 flush 一次 buffer 尾巴
```

两条理由都来自真实事故：一个 `data:` 行可能跨两次网络 read 到达，**解析半行会静默丢 token/usage**；有的端点不发 `[DONE]`/`message_stop` 就断流，不 flush 尾巴就丢最后一段。

### 3.2 各族差异

**① OpenAI**：
- tool_calls 用 `Map<index, {id,name,args}>` 累积。**分组键是 `index` 不是 `id`——id 本身也可能分片到达**（参考实现里 `entry.id += partial.id`）。用 id 分组，流式下同轮多个交错调用会拼错。
- malformed SSE 行直接忽略，不抛错。**但「忽略」的 catch 不能罩住整个 chunk 的处理**：开了 `include_usage` 的末块是 `"choices": []`，
  空安全的 `choices?[0]` 挡不住**空列表**，抛越界异常，被形状容错的 catch 当成坏行吞掉——每一次 ① 流式请求的 usage 都这样静默丢失
  【实测 2026-08-14，Joycai 修复；坑 108】。取首个 choice 前先判空，usage 在 choices 之外单独读。
- **`content` 不一定是字符串**：前端是 Responses 或 Anthropic 形后端的兼容层会把 part 数组（`[{"type":"text","text":"…"}]`）原样镜像到
  `chat/completions`【实测 2026-08-14，中转流量】。按字符串强转会在解析器里抛类型错误，调用方只看到一个说不出原因的失败；两种形状都收，
  数组里只取 `text`。

**③ Gemini**：
- **不是 delta！** 每个 chunk 是完整响应对象，`parts` 直接追加。按 delta 逻辑拼会重复内容。
- `functionCall` 一次给全不分片。旧型号**没有 id**——适配器自造 `gtc_${Date.now()}_${n}` 补上，让上层的统一 tool 循环仍能用 id 关联；3.8 Flash 起带 `id`，有就用它（第 5 篇 §3）。
- 流以一个光秃秃的 `{text:""}` 收尾；流式时 `thoughtSignature` 落在最后一块 `{text:"", thoughtSignature}` 上——空文本块照样要留存（签名在它身上）【实测 2026-09-26】。

**④ Anthropic**：按事件类型 switch。
- `content_block_start` 建块：**浅拷贝后整块留存，包括不认识的类型**——paused turn 要原样回话，重建会丢 `encrypted_content`（见第 5 篇）。
- `input_json_delta` 按**块索引**累积。
- `thinking_delta` 流出去展示 + 累积进块；`signature_delta` 只累积不展示。
- `message_delta` 收 stop_reason 和 output usage。
- `event:` 行无 payload，只认 `data:` 行。
- **空参数工具调用不会流任何 `input_json_delta`**：累积出的 `""` 必须转成 `"{}"`，否则 agent 循环拿到一个解析不了的调用。
- 事件族谱：`message_start → content_block_start → content_block_delta → content_block_stop → message_delta → message_stop`；`content_block_delta` 细分 `text_delta`／`input_json_delta`／`thinking_delta`／`signature_delta` 四种（自 21 篇移入）。

## 4. baseURL 的不对称归一化

出处：simple-ai-writer `src/lib/ai/urls.ts`（`trimBase` / `anthropicRoot` / `migrateLegacyStandard`）。

三个生态对"base URL 是什么"的约定**不同**，归一化规则因此必须不对称——这是有依据的差异，不是随意：

- **OpenAI / Gemini 生态**：base **自带版本段**（`.../v1`、`.../v1beta`），照 `OPENAI_BASE_URL` 惯例，path 直接拼。**陷阱：不要"修复"这个不对称去给 OpenAI 补 `/v1`**——它的 base 本来就以 /v1 结尾，且中继合法地路由在 /v1 之下（如 `https://relay/openai`），补了就断。
- **Anthropic 生态**：base 是**根地址**（`ANTHROPIC_BASE_URL` 惯例，官方 SDK / Claude Code / 所有第三方文档都由客户端补 `/v1/messages`）。参考实现的历史 bug：曾只拼 `/messages`，于是照第三方文档粘贴的 base 一律 404——**你的 app 的约定若是全生态里唯一不同的那个，错的是你**。修法 `anthropicRoot`：先剥尾部 `/messages` 再剥 `/v1`，接受作者会粘贴的三种形状（根 / 根+`/v1` / 完整 curl 端点 URL），统一拼 `root + "/v1" + path`。
- **Gemini**：额外剥尾部 `/models`（把模型列表 URL 粘成 base 是易犯错误）。

官方端点存**空串** base（地址是厂商常量不是设置；域名变更 = 代码编辑而非数据迁移），适配器用 `baseUrl || DEFAULT_*` 兜底。

**读取时幂等迁移**：做 official/compat 拆分这类 schema 演进时，旧行的迁移放在读取时（base 非空且非官方地址 → 打 `_compat` 标），而非一次性 DB migration——因为导入旧版导出的配置也要走同一条规则；一处规则，两条路径不会漂移。

## 5. 鉴权矩阵

```text
AuthMode = default | bearer | both
可选鉴权模式：anthropic_compat、gemini_compat → [default, bearer, both]；其余 standard → 只有 [default]
```

| 族 | 默认（官方唯一方式） | compat 可选 | 不做的及原因 |
| --- | --- | --- | --- |
| OpenAI | `Authorization: Bearer`；**无 key 时整个头省略**（Ollama/LM Studio 收到空 Bearer 会拒） | 无 | Azure `api-key` 头：URL 形状（`/openai/deployments/{d}/...?api-version=`）与模型标识都不同，一个头救不了，要做是另一族不是 compat 选项 |
| Gemini | `x-goog-api-key` | `bearer` / `both` | `?key=` 查询串**故意不实现**：key 进代理日志/报错信息 = 泄漏 |
| Anthropic | `x-api-key` + `anthropic-version: 2023-06-01`（**pinned 不追 latest**——wire 形状按它版本化）+ `anthropic-dangerous-direct-browser-access: true` | `bearer` / `both` | — |

要点：

- **Anthropic 的 bearer 必须做**：生态里 `ANTHROPIC_API_KEY→x-api-key` 与 `ANTHROPIC_AUTH_TOKEN→Bearer` 是**两套一等约定**，大量网关只认后者且文档只写自己要的那个——读错头的网关看到的是未鉴权请求，401。
- **`both` 的存在理由**：给文档啥也不说的网关两个头都发。但**只在 compat 提供**——api.anthropic.com 对携带两种凭证的请求拒绝，在官方端点上提供这个选项 = 递给作者一个只能坏事的设置。
- 存储上 `default` 存 NULL（没碰过设置的行读回来逐字节不变），且**读取时按 standard 校验**——供应商从 compat 改回 official 时残留的 `bearer` 会失效而不是照发。
- 版本头 pin 死一个日期值，不追 latest：wire 形状按版本头版本化，追 latest 等于让服务端单方面改你的解析器契约。

## 6. CORS / 浏览器直连

桌面（Tauri/Electron 原生 HTTP）与浏览器环境的差异要显式处理：

- 打包版请求走原生 HTTP 栈（出处：Rust reqwest 经 Tauri IPC，`src/lib/http.ts` 的 fetch 包装），**没有 CORS preflight**，`anthropic-dangerous-direct-browser-access` 在打包版是 no-op。
- 带上它是为了 dev 模式纯浏览器环境（回落全局 fetch）也能连——不带则 Anthropic 直接拒绝浏览器 origin 的请求。
- 本地 Ollama 的 Windows 打包版 403 问题：靠 http 层覆盖 `Origin` 头修复。注意这个修复位于比 provider 枚举更底层的位置，拿不到枚举值，只能按"URL 指向本机"判断——这也是"Ollama 不做成枚举值"的理由之一（L2 数据能表达的就不进代码）。

## 7. ② OpenAI Responses 族

出处：simple-ai-writer `src/lib/ai/responses.ts`；协议事实 `docs/api/responses.md`（GPT-5.4/5.5/5.6 经中转站实测 + 官方文档，xAI 官方实测）。

### 7.1 请求骨架

```jsonc
POST {base}/responses          // base 与 ① 同，Bearer
{
  "model": "…",
  "instructions": "…",         // 全部 system 消息 hoist 并 "\n\n" join；恒发，哪怕空串（上游判不收时改成 input 开头的 developer 消息，规则 2）
  "input": [ /* items */ ],
  "tools": [{ "type": "function", "name", "description", "parameters", "strict": false }],
  "tool_choice": "auto" | "none" | "required" | { "type": "function", "name": "f" },
  "reasoning": { "effort": "medium", "summary": "auto" },   // 见第 3 篇 §7
  "text": { "format": {…}, "verbosity": "low" },            // 见第 4 篇 §5
  "store": false,
  "stream": true
}
```

内部消息 → `input` 条目的转换：

| 内部（① 形状） | ② 条目 |
| --- | --- |
| system | 移出列表，进顶层 `instructions`（上游判 `instructionsField` 不收时：`input` 开头一条 `{role:"developer", content}`，不发 `instructions` 键） |
| user 文本 / 多模态 | `{role:"user", content:[{type:"input_text",text} \| {type:"input_image", image_url:"data:…", detail?} \| {type:"input_file", filename, file_data}]}`——**`detail` 与 `image_url` 并列**，不在其内 |
| 带 tool_calls 的 assistant | 有同模型 `_responseItems` → **整组原样条目**；否则裸 `{type:"function_call", call_id, name, arguments}` |
| tool 结果 | `{type:"function_call_output", call_id, output}` |

五条不可省的请求侧规则：

1. **`store: false` 恒发**：应用自己保存历史，服务端存一份没意义，零数据保留组织不发会被拒；也是让端点给 reasoning 条目附 `encrypted_content` 的前提。
2. **`instructions` 恒发**：中转站发现它缺失会注入自己的系统提示（实测一次 4.4K–9K token，第 1 篇 §9.2）。
   **例外按上游裁决，不是全局翻转**【实测 2026-09-24，实现同日】：有的网关上游见到 `instructions` 键（哪怕空串）就在后面追加约 1.2K token 的护栏，
   明文让模型拒写小说——这种线路把 system 改成 `input` 开头的 `developer` 消息、不发 `instructions`，护栏就不出现；
   而 ChatGPT 账号池上游反过来必须发，否则注入 4.4K。两者在同一台中转站、同一个模型 id 上并存（第 1 篇 §9.2「同一个 GPT，两类上游」）。
3. **工具定义扁平 + 显式 `strict: false`**：省略 `strict` 不是中性——官方端点会自动升成 strict，把所有带可选字段、未声明 `additionalProperties` 的 schema 改写成"全必填否则 400"的契约。① 族 schema 是非 strict 的，这个族上必须明说。
4. **`tool_choice` 命名形态去掉 `function` 包装**：`{type:"function", name}`。只在声明了函数工具时发（只有 server tools 的请求不带该字段）。此族**没有**"思考中禁止强制"，不做预判降级；个别端点拒绝仍由 400 学习兜底。
5. 未知顶层键在官方与 xAI 上被忽略（与 ④ 官方的"未知键 400"相反）——但仍按最小公倍数发送，不因此放宽。

### 7.2 流式事件与读取

```
response.created → response.in_progress
→ output_item.added {item:{type:"reasoning"|"message"|"function_call"|"web_search_call"…}}
→ reasoning_summary_text.delta ×N / output_text.delta ×N / function_call_arguments.delta ×N
→ function_call_arguments.done {arguments}     // 完整串
→ output_item.done {item: 完整条目，含 encrypted_content}
→ response.completed {response:{usage, reasoning, temperature, …}}
  | response.incomplete {response.incomplete_details.reason} | response.failed | error
```

适配器规则：

- **只读 `data:` 行**（`event:` 行冗余）；`[DONE]` 不属于此协议但要容忍（xAI 会发）。
- 文本 delta 旁带 `obfuscation` 随机填充字段——**只读 `delta`**；发 `include_obfuscation:false` 实测无效。
- 函数调用按 **`output_index`** 分组（部分中继的 delta 事件缺 `item_id`）；参数**两次到达**：delta 片段（只用于进度上报）+ `function_call_arguments.done` / `output_item.done` 的整串（**以整串为准**）。只发其中一种的端点也要能拼出完整调用。
- **回传物直接收集 `output_item.done` 的 `item`**（reasoning / function_call / message 三类），不从 delta 自己拼——它就是下一轮要原样放回 `input` 的条目，挂在 `toolCalls` chunk 的 `_responseItems: {modelId, items}` 上。服务端工具条目（`web_search_call` 等）不回传。
- 终止：`completed` → 读 usage（`input_tokens` / `output_tokens` / `input_tokens_details.cached_tokens`，cached 是 input 子集）；`incomplete` 且 reason=`max_output_tokens` → `truncated`，reason=`content_filter` → **throw**；`failed` / `error` 事件 → throw；data 行里裸 `{error}`（无 `type`）也 throw。
- **服务端标了 `status:"completed"` 的空 message 条目是正常结束**：工具结果交付之后，GPT-5.x（经中转的 gpt-5.6）以一个 `phase:"final_answer"`、
  文本为空、`status:"completed"` 的 message 条目收尾【实测 2026-09-15；坑 109】。只把非空文本 / 推理 / 调用算作输出的「空回复守卫」会把这一轮
  判为失败，而工具早已把结果交付了。判据：completed 的 message 条目算输出；真正坏掉的 200 一个条目都没有；没 completed 的照旧抛错。
  ① 族没有这个判据（空 `content` + `finish_reason:stop` 与坏中转无法区分），不要照搬。
- **流可能不带终止事件就结束**：flush 行缓冲尾巴后照样 `finish()`——代价是 usage 记 0、stopReason 缺失，但不能挂死或抛错。
- 回显比对在终止事件处做（第 6 篇 §4.1）。

### 7.3 回传：原样整组，缺失无现象

`store:false` 下工具轮 `input = 历史 + 上一轮 output 条目 + function_call_output`。实测（GPT-5.4/5.5/5.6、Grok）：原样回传、删 reasoning、删 `encrypted_content`、只回裸 function_call **四种都 200 且答对**——**回传缺失不报错**，与 ④ 族同属"无现象"类，代价只在质量（5.6 默认 `reasoning.context: all_turns` 会渲染往轮推理）。所以规则是按官方推荐原样回传，且：

- 载体带 `modelId`，换了模型退回裸 function_call（与 `_thinkingBlocks` 同一条"换模型整组剥离"）；
- 原样条目**替代**裸 function_call 映射，不并列发送。

---

## 本篇检查清单

- [ ] 三族各有一份对照表意识：容器名、模型侧角色、system 位置、工具字段名、流式机制、结束原因、usage 到达方式，写适配器前先对表。
- [ ] Anthropic 转换器实现了：丢头部 assistant、同角色合并、连续 tool 消息合并成单条 user、system hoist（ContentPart 拍平）、thinking 块在 tool_use 前。
- [ ] user 信封里混入作者文本时打了可归因标签（labelAuthorText）。
- [ ] tool_use name 有三级兜底（自带 → id→name 表 → `"unknown_function"`）。
- [ ] Gemini 转换：assistant→model、functionResponse 靠 id→name 表回填函数名、`_geminiModelParts` 原样整组回传。
- [ ] SSE 解析有行缓冲（半行留存）+ 流末 flush；malformed 行忽略不抛。
- [ ] OpenAI tool_calls 按 `index` 分组累积，id 用 `+=` 拼接。
- [ ] Gemini chunk 按完整对象处理（append，不是 delta 拼接）；自造 functionCall id。
- [ ] Anthropic 块整存（含不认识的块类型）；空参数工具调用 `""` → `"{}"`。
- [ ] baseURL 归一化不对称：OpenAI/Gemini 不补 `/v1`；Anthropic 走 `anthropicRoot`（剥 `/messages`、`/v1` 再统一拼）；Gemini 剥尾部 `/models`。
- [ ] 官方端点 base 存空串，适配器兜默认常量；旧配置走读取时幂等迁移。
- [ ] OpenAI 无 key 时省略整个 Authorization 头。
- [ ] Gemini 不实现 `?key=` 查询串鉴权。
- [ ] `both` 鉴权只对 compat 开放；authMode 读取时按 standard 校验残留值。
- [ ] anthropic-version pin 死，不追 latest。
- [ ] 视频片段 `video_url` 按平台放行（实测收的点名、实测不收的写 `false`、没测过的不发），不因「这是 ① 族」就发；验证用猜不出的片段 + 带与不带的输入 token 对比。
- [ ] ② 族：`instructions` 恒发（含空串；只有能力表判这条线不收时改发开头的 `developer` 消息）、`store:false` 恒发；工具扁平且显式 `strict:false`；命名 `tool_choice` 去掉 `function` 包装、只随函数工具发。
- [ ] ② 族流：只读 data 行、容忍 `[DONE]`、无视 `obfuscation`；函数调用按 `output_index` 分组，整串覆盖 delta 累积；回传物收集自 `output_item.done`。
- [ ] ② 族终止：`incomplete` 区分 `max_output_tokens`（truncated）与 `content_filter`（throw）；`failed` / `error` / 裸 `{error}` 都 throw；无终止事件的流照样 finish。
- [ ] `_responseItems` 带 modelId，同模型才原样回传，否则退回裸 function_call；不与裸映射并列发。
- [ ] 查某族的字段形状先看 §1 总对照表（行 = 功能维度，格 = 结论记号 + 关键字段名 + 证据 + 指针）；平台／渠道／模型级差异不在本表展开，按「详见」去 20／22／23；没有证据的格子写 `—`，不从相邻族类推。
- [ ] 非对话面（出图 route／视频 submit-poll／ASR 三种线格式）与厂商私有扩展按 §1.1 的判定标准分发到 13／14／16 与 03／05，不当作 ①–④ 的变体；Ⓓ 私有键（`enable_search`、`enable_thinking`、`video_url`…）按平台放行、只放行 compat，不因「这是 ① 族」就发。
- [ ] 新增／修正协议族通用事实：正文改 02–06 一处，§1 表对应格同步记号 + 证据 + 指针；推翻旧结论在格内写「旧：… → 新：…（日期）」不删（30 篇流程）。
