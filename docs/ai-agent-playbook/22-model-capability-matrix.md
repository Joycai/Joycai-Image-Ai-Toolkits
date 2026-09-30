# 22 模型 × 平台 × 面 能力矩阵（对话模型）

本表回答：**这个模型在这个平台的这个面上，思考／结构化输出／函数工具／服务端工具／多模态输入／上限与采样各是什么行为，哪里会静默失败**。主键 = （模型家族／型号，平台·渠道·线路，面）。典型用例：「DeepSeek 在百炼支持 code_interpreter 而官方不支持」「同一个 Claude 在 New API 四个渠道四种答案」这类差异要一眼能看出。本表是结论表：每格 = 记号 + 关键值 + 证据 + 指针；报错原文、数值、事件序列、原因与对策在「详见」指向的正文篇。

图例：✅ 实测生效（发了有效果、回包有对应字段）；❌ 实测拒绝、**会响**（4xx/5xx 或流内 error，括号里写状态码或原文）；🔇 **静默失败**（收下 200 但不生效／被丢／被改写——最危险的一类）；🔀 被中转站改写或劫持（写清改成什么）；📄 只有文档口径，未实测；— 未测／来源没写；⚠ 来源标注为推断或含糊

面的编号：① OpenAI Chat Completions ／ ② OpenAI Responses ／ ③ Gemini generateContent ／ ④ Anthropic Messages ／ Ⓓ DashScope 私有 ／ 🖼 出图 ／ 🎬 视频 ／ 🎤 ASR。

维护：新增 / 修正按 `30-knowledge-ingestion.md` 的流程；本表每行必须带证据与指针，没有证据的格子写 `—`。证据记法沿用各篇：【实测 YYYY-MM-DD】【文档 YYYY-MM】【中继源码】【实现】⚠；被推翻的旧结论写「旧：… → 新：…」不删。

## 目录

- [§1 怎么查](#1-怎么查)
- [§2 总览表](#2-总览表)
- [§3 GPT](#3-gpt)
- [§4 Claude](#4-claude)
- [§5 Gemini](#5-gemini)
- [§6 Grok](#6-grok)
- [§7 DeepSeek](#7-deepseek)
- [§8 Qwen（千问）](#8-qwen千问)
- [§9 GLM（智谱）](#9-glm智谱)
- [§10 豆包 Seed（火山方舟）](#10-豆包-seed火山方舟)
- [§11 MiniMax](#11-minimax)
- [§12 本地模型](#12-本地模型)
- [§13 其他（Kimi、OpenRouter）](#13-其他kimiopenrouter)
- [§14 服务端工具 × 平台 × 模型 专表](#14-服务端工具--平台--模型-专表)

## 1 怎么查

三步：

1. **先定模型家族节**（§3–§13）。中转站上的 id 带档位前缀（`[Plus]gpt-5.6-terra`、`[特价kiro量]claude-opus-5`），按去前缀后的家族找；渠道前缀本身是主键的一部分（01 §9.2 第 1 条）。
2. **看该节「家族固有特性（跨平台一致）」**：思考控制方言与代次差异、`<think>` 内联、回传义务、结构化档位。这些在任何平台都成立；只在一个平台测过的特性不在这里，而在平台行里标「仅测于 X」。
3. **在该节「按平台 × 面」表里找 (平台·渠道·线路, 面) 那一行**。同一渠道多个型号行为一致合并成一行（型号列写「opus-4-6 ／ opus-5」），不一致分行。**找不到的行 = 未测**，按「未知、需核实」处理（20 §3 每平台节）：不从相邻平台类推，不从「这是 Claude」推出（05 §5、01 §9.2）。

看完行再看该节末「随平台变化的特性」小结——同一模型在不同平台的对比句，是用户最常问的问题。服务端工具逐个工具、逐个平台的行为在 §14 专表；家族表的「服务端」格只留记号摘要。

## 2 总览表

| 模型家族 | 已测过的 平台·面 组合 | 最典型的随平台变化的特性 | 证据（汇总） |
| --- | --- | --- | --- |
| GPT | OpenAI 官方 ①②（多为 📄）；New API `[特价Pro]`②①、`[Plus]`②①、`[Pro]`②①、`[Azure]`②①、`[官key]`／`[AWSb]`（503）；New API 另一台 `[Pro]`／`[Plus]` ②（第八、第十个样本）；OrcaRouter ①、② 默认线路、② 原样线路 | `web_search`：账号池真搜、`[Azure]` 网关静默丢、OrcaRouter 真跑；`instructions`：账号池不发就注入 4.4K、网关发了挂 1.2K 护栏；`text.format`：`[Pro]` 整个丢、其余执行；`effort:"none"`：② 四上游都改 `medium`，① 只在网关真关；`temperature`：账号池回显 1.0、网关 500 | 【实测 2026-09-24】【实测 2026-09-26】【文档】 |
| Claude | Anthropic 官方 ④（📄 + 经 OrcaRouter 原样实测 Sonnet 5／Opus 5.5／Fable 5.1／Sonnet 4.6／Opus 4.5）；OrcaRouter ①；New API · Kiro ④①、CC ④①、anti ④①、AWSb ④①、官key（502）；某中转 ①（畸形样本） | 思考是否存在／有文本（anti 不想、CC opus-5 空文本、Kiro 只两态）；签名是否校验（官方／AWSb 400，Kiro／CC 200）；`output_config.format` ④ 按渠道甚至按型号、① 整台 New API 都丢；PDF／URL 图是否送达；服务端工具：劫持／真做／丢／400 四种；`max_tokens` Kiro 无视、anti ① 无视 ④ 生效 | 【实测 2026-09-23】【实测 2026-09-26】【实测 2026-09-28】【文档】 |
| Gemini | Google AI Studio ③（📄 + 2026-09-28 直连实测档位大小写，gemini-3-flash-preview／3.8-flash）；OrcaRouter ③（Vertex 原样）、①；New API ③ 面 | 图片键 snake_case：官方两种都收、New API 只 camelCase；`video_url` 经 OrcaRouter ① 层静默丢；`:countTokens` 经 OrcaRouter 当生成计费；报价需 `X-OrcaRouter-Include-Cost` 头；AI Studio `thinkingLevel` 小写也收、`lowest` 400 | 【实测 2026-09-05】【实测 2026-09-26】【实测 2026-09-28】【文档】 |
| Grok | xAI 官方 ②、①（legacy） | 只测官方：② 拒 `none`、拒 `max`；① `video_url` 400；`tool_search` 403 | 【实测 2026-09】【实测 2026-09-28】 |
| DeepSeek | DeepSeek 官方 ①（📄 + `video_url` 实测）、④（deepseek-v4-pro／flash，2026-09-28）；DashScope 托管 ②、④（deepseek-v4-pro） | 服务端工具：官方无；DashScope ② 面 `code_interpreter` 放行 `deepseek-v4`；④ 官方默认开、`disabled` 真关、`bogus` 422 点名枚举——百炼 ④ 上 v4-pro 也收 `disabled` 真关 | 【文档 2026-08】【实测 2026-09-17】【实测 2026-09-28】 |
| Qwen | DashScope 百炼 ①、②、④（qwen3.8-flash／3.7-flash／3.5-plus／qwen-turbo，2026-09-28）、Ⓓ（Qwen-Audio ⚠） | 同一端点两代思考控制不同；`code_interpreter` ① 面按型号「跑／静默忽略／400」、② 面到 3.8 都跑；`agent_max` 3.8-flash 400、3-max／3.5-plus 收；④ 千问默认想、`disabled` 真关，qwen-turbo 从不想 | 【实测 2026-09-17】【实测 2026-09-28】【文档】 |
| GLM | 智谱按量 ①；智谱 Coding Plan ④（glm-4.7、5.3、5.3-flash、4.6）、①②（⚠）；百炼 ④（glm-5.3）；百炼／火山（平台执行搜索） | 联网搜索：自家端点靠对话内 `tools[]` + `search_intent:false`，在百炼／火山由平台执行；④ 面默认值按模型：4.7 不想、5.3 系想且关不掉（1210）、4.6 收 `disabled` 真关；百炼 ④ 上 glm-5.3 `disabled` 400 点名 `enable_thinking` | 【实测 2026-09-19】【实测 2026-09-28】 |
| 豆包 Seed | 火山方舟 · 套餐 ①②④；火山方舟 · 按量（对话面未测） | `json_schema` 按型号守不守（2.1-turbo 守、2.0-lite 不守、2.0-mini ② 多字段）；④ 2.0 系无 `signature`、2.1 有；服务端搜索 ②④ 有、① 无；套餐 vs 按量 key 不通用 | 【实测 2026-09-18】【实测 2026-09-23】【实测 2026-09-28】 |
| MiniMax | MiniMax 国内站 ④（M3、M2.7）、①（M3）；百炼 ④（MiniMax-M2.5） | ④ 面 M3 思考默认关且真关、M2.7 收下 `disabled` 照想，`thinking.type:"bogus"` 反而开思考、未知模型名静默改映射；① 面总在想且 `<think>` 内联、交错思考回传不强制；两面温度都不听；百炼 ④ 上 M2.5 `disabled` 400 点名 `enable_thinking` | 【实测 2026-08】【实测 2026-09-28】 |
| 本地模型 | Ollama ①；LM Studio／llama.cpp ① | 超窗静默从头部截断（Ollama `num_ctx`）；LM Studio 严格交替模板 | 【实测，日期未标】⚠ ⏳待复核【参考实现】 |
| 其他 | Kimi ①；百炼 ④（kimi-k2-thinking、kimi-k2.6）；OpenRouter ①（仅指纹经 OrcaRouter）；欠费中转（402） | 百炼 ④ 上 kimi-k2-thinking 收 `disabled` 照想、kimi-k2.6 开关都回空 thinking 块（显式 `enabled` 才有文本） | 【实测 2026-09-19】⚠【实测 2026-09-28】【文档】【实测 2026-09-03】 |

## 3 GPT

### 家族固有特性（跨平台一致）

- ② `reasoning:{effort, summary}` 七档，默认按型号，5.4 上限 `xhigh`。【实测，日期未标】⚠ ⏳待复核 03 §7.1、02 §7.3
- ② 回传缺失**不报错**，代价只在质量。【实测】02 §7.3、03 §7.3
- ② 工具结果后空文本 `completed` message 收尾 = 正常。【实测 2026-09-15】坑 109
- ② 省略 `strict` 端点自动升 strict → 工具显式 `strict:false`。【文档】【实测】坑 64；04 §5.1、02 §7.1
- `json_object` 须含 "JSON"。【文档】坑 14；04 §2
- `text.verbosity` 仅 ② 生效。【实测 2026-09-24】04 §5.2
- `web_search_call.action.type` 三种。【实测】坑 71；05 §5
- 5.4+ 工具按需加载，缺回传 `tool_search_output` 工具静默消失。【文档 2026-09】坑 68；05 §7
- o1-pro／codex 系／computer-use 是 Responses-only。【文档 2026-08】01 §8.1
- delta 旁带 `obfuscation`；`[DONE]` 要容忍。【实测】02 §7.2

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GPT（通用） | OpenAI 官方 | ① | 📄 顶层 `reasoning_effort`；未知顶层字段 400 | — | 📄 `json_object` 需 "JSON"；`json_schema` strict | 📄 全档 | 见 §14 | ① `video_url` 未量 ⚠ | — | `json_object` 缺 "JSON" 无限空白流 | 【文档】 | 03 §2、04 §2、05 §5 | 14 |
| GPT（通用） | OpenAI 官方 | ② | 📄 七档 | `store:false` 附 `encrypted_content`；不发 `include` 是否丢未验 ⚠ | ✅ `text.format`（省略 `strict` 自动升）；`text.verbosity` ✅ | 扁平具名；工具须 `strict:false` | 见 §14：📄 | 📄 `input_image`、`input_file` | `incomplete_details.reason` | 空文本 `completed` 收尾误判空回复 | 【文档】【实测，日期未标】⚠ ⏳待复核 | 02 §7、03 §7.1、04 §5、05 §5 | 64、71、109 |
| GPT-5.4+ | OpenAI 官方 | ② | 同上 | 回传须含 `tool_search_output`／`additional_tools` | — | 📄 `defer_loading`、`tool_search`、`namespace` | — | — | — | 缺回传 → 工具 🔇 消失 | 【文档 2026-09】 | 05 §7 | 68 |
| o1-pro ／ codex 系 ／ computer-use | OpenAI 官方 | ② only | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | 走 ① 失败（截至 2026-08） | 【文档 2026-08】 | 01 §8.1 | — |
| GPT-5.4 | 经中转站（未具名） | ② | 默认 `none`；上限 `xhigh`；`max` ❌ 400 | 回传缺失四种都 200 | — | — | — | — | — | — | 【实测，日期未标】⚠ ⏳待复核 | 03 §7.1、02 §7.3 | — |
| GPT-5.5 ／ 5.6 | 经中转站（未具名） | ② | 默认 `medium`；收 `max`；5.6 `context: all_turns` | 回传缺失都 200 | — | — | — | — | — | 空回复守卫误判 | 【实测 2026-09-15】 | 02 §7.2、§7.3、03 §7.1 | 109 |
| gpt-5.6-sol | New API · `[特价Pro]` ／ `[Plus]`（账号池，画像 codex） | ② | ✅ 真分档；`none` 🔇 回显 `medium`；`max` ✅；乱写 ❌；`mode:"pro"` 回显 `standard` | `store:false` 自带 `encrypted_content`；回传缺失 200 | ✅ json_schema（省略／显式 strict 都执行）；`json_object` ✅；`text.verbosity` ✅ | ✅ 全档 | 见 §14：search ✅ ／ code・file ❌ ／ image ❌ 403 | `input_image`／`input_file` ✅；拒爬主机 URL 图 → 流内 `error`+空答 | `max_output_tokens` 🔇；`temperature:0.5` 🔇 回显 `1.0` | 不带 `instructions` 注入 0–17K 不固定（读 `usage.attribution`） | 【实测 2026-09-24】 | 01 §9.2「同一个 GPT」、03 §7.4、04 §5.1、06 §4.1 | 61、62、65、161、162、165、167 |
| gpt-5.6-sol | New API · `[Pro]`（账号池，codex） | ② | 同上；乱写 ❌ **400 官方原文** | 同上 | ❌🔇 **整个丢 `text.format`**。旧：显式 `strict:true` 才丢（第八个样本）→ 新：不论写不写都丢（2026-09-24） | ✅ | 见 §14：search ✅ ／ code・file ❌ 400 ／ image ❌ 403 | ✅；拒爬主机 URL 图 ❌ 400 | 同上 | 校验同官方却唯一丢结构化；不带 `instructions` 不注入 | 【实测 2026-09-24】 | 01 §9.2「上游画像扩到 GPT」、04 §5.1、06 §8 | 63、160 |
| gpt-5.6-sol | New API · `[特价Pro]` ／ `[Plus]` ／ `[Pro]` | ① | `none` 🔇 关不掉；乱写 → 流内 error ／ 502 ／ 400 | `reasoning_content` 摘要 | ✅ json_schema；`[Pro]` ❌🔇 丢 | 具名 ✅（`[Pro]` 带具名注入 4.4K） | 见 §14：🔇 | ⚠ | `max_completion_tokens` 🔇 | 带 system 注入 4.4K；`[Pro]` 不注入；`verbosity` 无效 | 【实测 2026-09-24】 | 01 §9.2、03 §7.4、04 §5.1、05 §5 | 160、164、165 |
| gpt-5.6-terra（顶替 sol；sol 503） | New API · `[Azure]`（带护栏网关，**非 Azure OpenAI**；画像 azure） | ② | 分档弱；`none` 🔇 回显 `medium`；`max` ✅；乱写 ❌ 500；`mode:"pro"` 回显 `pro` ⚠ | 无 `attribution` | ✅ json_schema；`json_object` ✅；`text.verbosity` ✅ | ✅ 全档 | 见 §14：search 🔇 ／ code・file ❌ 500 ／ image ✅ | ✅；拒爬主机 URL 图 ❌ 500 `count_token_failed` | `max_output_tokens` ✅；`temperature≠1` ❌ 500；`store:true` ❌ 500 | 带 `instructions` 键（含空串）挂约 1.2K 护栏，创作题 6 拒 2 | 【实测 2026-09-24】 | 01 §9.2「同一个 GPT」、02 §7.1、03 §7.4、04 §5.1、06 §2 | 159、161、162、163、166、167、169 |
| gpt-5.6-terra | New API · `[Azure]` | ① | `reasoning_effort:"none"` ✅ **真关**；乱写 ❌ 500 | `reasoning_content` 摘要 | ✅ json_schema | 具名 ❌ 500；`required` ✅ | 见 §14：🔇 | ⚠ | `max_completion_tokens` → `length` 但仍多吐 | 不注入 | 【实测 2026-09-24】 | 01 §9.2、03 §7.4、06 §2 | 162、164 |
| gpt-5.6-sol | New API · `[官key]` ／ `[AWSb]` | ②① | — | — | — | — | — | — | — | ❌ 503 `No available channel`（目录里有 ≠ 有线路） | 【实测 2026-09-24】 | 01 §9.2、06 §5 | 166 |
| GPT-5.6-sol ／ -terra | New API 另一台 · `[Pro]`／`[Plus]`（第十个样本） | ② | 旧：sol 发 `max` 回显 `none` 且 0 推理 token → 2026-09-24 另一台四上游未复现（按「当时当档」理解）；terra 发 `none` 两次回显 `medium` 照想（全部复现） | — | — | — | 见 §14：✅ 但 112 s | — | 🔇 无视 `max_output_tokens`；`temperature` 🔀 回显 `1.0` | 不发 `instructions` 注入 4.4K–9K；一档背后多上游 | 【实测 2026-09】+【中继源码】 | 01 §9.2 第 1–4 条、03 §7.4、06 §4.1 | 61、62、65、107、108 |
| GPT-5.4 ／ 5.5 | New API 另一台 · `[Pro]`（第八个样本） | ② | — | — | 旧：显式 `strict:true` 才丢 `text.format` → 新：2026-09-24 同台 `[Pro]` 不论写不写都丢 | — | — | — | — | — | 【实测 2026-09】 | 01 §9.2「同一个 GPT」第 6 条、04 §5.1 | 63 |
| GPT 家族（`/gpt/`） | New API · codex 画像（参考实现落格） | ①／② | — | — | ② `textVerbosity` ✓ | 强制工具 ✓ | ② `web_search` ✓ | `pdfInput` ✓ | ② `temperature` ✗ | ② `instructionsField` ✓（恒发） | 【实现 2026-09-24】 | 01 §9.2「上游画像扩到 GPT」 | 168、169 |
| 同上 | New API · azure 画像 | ①／② | — | — | `structuredOutput` ✓ · ② `textVerbosity` ✓ | ① 强制工具 ✗；② ✓ | ② `web_search` ✗ | `pdfInput` ✓ | ② `temperature` ✗ | ② `instructionsField` ✗ → 系统提示作 `developer` 输入 | 【实现 2026-09-24】 | 01 §9.2 | 159、168、169 |
| GPT-6 luna ／ sol ／ astra；5.6-terra；gpt-5-mini | OrcaRouter · ① 线路（翻译层） | ① | `reasoning_effort` + `tools` 同发 200 | 只有 `reasoning_details[]`／`reasoning` 摘要 | ✅ strict `json_schema` 守 enum | 并行 ✅ | 见 §14：🔇 | `video_url` ❌ 400（gpt-5-mini） | 目录 1,050,000／128,000；`usage.cost` | `gen-…` id 等翻译层指纹 | 【实测 2026-09-26】；视频【实测 2026-09-28】 | 01 §9.5、04 §2、02 §1、06 §1 | 185、206 |
| GPT-6 luna ／ sol ／ astra | OrcaRouter · ② 默认线路（OpenRouter 形态） | ② | 六档 200；`minimal` 🔀 改 `low`；`bogus` ❌ 网关 `upstream_rejected_request` | reasoning item 只有 `encrypted_content`；`summary:"auto"` 回显 `"detailed"`；回灌义务测不出 | ✅ strict `text.format` 守 enum | 并行不交错；伪造 `msg_tmp_…` id | 见 §14：✅ | `input_file` PDF ✅ | 目录同上；`usage.cost`；`store` 恒 `false` | `minimal` 静默改写 | 【实测 2026-09-26】 | 01 §9.5、03 §7.1、04 §2、05 §5、06 §1 | 175、185 |
| GPT-5.6-terra | OrcaRouter · ② 默认线路 | ② | reasoning `format` 是 `azure-openai-responses-v1` | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | 目录同上 | — | 【实测 2026-09-26】 | 01 §9.5 | — |
| GPT-6（同上） | OrcaRouter · ② 原样线路（`store:true` 或 `include` 含 `action.sources`） | ② | `include`、`text.verbosity` 不触发分流 | OpenAI 原样：`resp_…` id、`billing` | ⚠ | ⚠ | 见 §14：✅ | ⚠ | **无花费字段**；`cache_write_tokens` | 同端点按 `store`／`include` 分流 | 【实测 2026-09-26】 | 01 §9.5、06 §1 | 175、186 |

### 随平台变化的特性

- **联网**：账号池三档 `web_search` 真搜、`[Azure]` 静默丢、OrcaRouter 真跑；① `web_search_options` 处处 🔇——GPT 联网只能走 ②。【实测 2026-09-24】【实测 2026-09-26】
- **系统提示**：账号池不发 `instructions` 注入 4.4K–17K，网关发了就挂 1.2K 护栏——按上游裁决。【实测 2026-09-24】坑 62、159、169
- **结构化**：`text.format` 与 ① `response_format` 都只在 `[Pro]` 丢。【实测 2026-09-24】坑 160
- **关思考**：② `none` 四上游都改 `medium`；① `none` 只在 `[Azure]` 真关。【实测 2026-09-24】坑 161
- **温度与上限**：账号池回显 `1.0`、上限无视；网关 `temperature≠1` 500、上限执行；OrcaRouter ② `minimal` 改 `low`。【实测 2026-09-24】【实测 2026-09-26】坑 65、162
- **URL 图片**：拒爬主机 http 图四档四种失败；PDF 与 data 图全读到。【实测 2026-09-24】坑 167

## 4 Claude

### 家族固有特性（跨平台一致）

- 思考方言按代：4.6+ `adaptive`，≤4.5 `extended`；`display` 默认 `"omitted"`——文本空但**全额计费**。【文档／参考实现】坑 4；03 §3
- Claude 5 系拒 `disabled` ❌ 400；「关闭」= adaptive + `effort:"low"`，真省要 off + 一句提示。【实测 2026-09-26】【实测 2026-09-28】坑 184、203、204；03 §2、§2.1
- 只发 `output_config.effort` 不发 `thinking` → 不想。【文档】【实测 2026-09-23】03 §3、§3.3
- 回传义务：**不回传 = 静默降级**；改动 → 400；换模型不剥 → 静默计费；签名**是否校验**随平台（见表）。【文档】【实测 2026-09-26】坑 1、3、137；03 §5
- 思考开着官方只收 `temperature:1`（Sonnet 5／Opus 5.5 未单测 ⚠）。【文档】03 §3.4
- 结构化只有 `output_config.format`（与 `effort` 平铺互盖 = 坑 181），无 `json_object`，`response_format` 400。旧：④ 只有 cue → 新：2026-09-26 更正。【文档】【实测 2026-09-26】坑 180–182；04 §2
- 工具 `{name, description, input_schema}`；`any`／`tool`；4.5+ `defer_loading`。【文档】【实测 2026-09-26】05 §2、§3、§7
- 服务端工具版本化条目 + `max_uses`；`pause_turn` verbatim 续跑。【文档】【实测 2026-09-26】05 §5、§6
- usage 三桶相加；`thinking_tokens` 是子集；自动写缓存不能当断点判据。【实测 2026-09-26】坑 18、179、197；06 §1
- `max_tokens` 必填；未知顶层键 400；`stop_reason:"refusal"` 必须 throw。【文档】02 §1、06 §2
- New API ①→④ 转换层（四渠道一致）：① `max`／`none`／乱写 = 不想；`response_format` 丢；`reasoning_tokens` 恒 0。【实测 2026-09-23】坑 140、142、147；01 §9.2、03 §3.3、04 §2

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Claude 4.6+（家族） | Anthropic 官方 | ④ | 📄 `adaptive`；`display` 默认 `omitted`；思考开只收 `temperature:1` | 📄 不回传 🔇；改签名 400 | 📄 `output_config.format`（4.5 起） | 📄 `any`／`tool`；`defer_loading` 4.5+ | 见 §14：📄 | 📄 image／document base64／url | `max_tokens` 必填 | display omitted 付费拿不到字 | 【文档】【参考实现】 | 03 §3、§5、04 §2、05 §2、§5–7 | 1、3、4、180–182 |
| Claude ≤4.5（家族） | Anthropic 官方 | ④ | 📄 `extended`：`enabled + budget_tokens` | 同上 | 📄 4.5 起（旧 `output_format` + beta 头） | 同上 | 同上 | 同上 | 同上 | 同上 | 【文档／参考实现】 | 03 §3、§3.3 | 1、4 |
| Claude Sonnet 5 | Anthropic 官方 · 经 OrcaRouter ④（回包原样） | ④ | 不发 `thinking` 也想、文本空只有签名；`display:"summarized"` 才有文本；关闭省约 2／3；`bogus` 200（网关重序列化） | `thinking_delta` → `signature_delta`；改 `signature` ❌ 400；整块丢 200 🔇 | ✅ 纯 JSON、守 enum；与思考／工具／流式同用 | 强制 ✅；`caller:{"type":"direct"}` | 见 §14：✅ 不需 beta 头 | PDF ✅；自动缓存写 1,630／2,834 | 目录 1,000,000／128,000；`cost_usd` 需 `X-OrcaRouter-Include-Cost`；`count_tokens` 301 | `cache_creation` 非断点判据；错误信封 `type:"<nil>"`；402 先于模型解析 | 【实测 2026-09-26】【实测 2026-09-28】；402【实测 2026-09-03】 | 03 §2.1、§3–§5；04 §2；05 §3、§5；06 §1、§2、§5 | 4、174、176、177、179、186、197、203、204 |
| Claude Opus 5.5 ／ Fable 5.1 | Anthropic 官方 · 经 OrcaRouter ④ | ④ | `disabled` ❌ 400（同一文案）；Opus 5.5 不发也想、Fable 那一题没思考 | 同 Sonnet 5 | ✅ 守 enum（与 `budget_tokens` 同用：thinking 在前 JSON 在后） | 强制与 schema 不冲突 | — | Opus 5.5 PDF ✅ 但那次**无**缓存写入 ⚠ | 目录同上 | `disabled` 会响 | 【实测 2026-09-26】 | 03 §2、§3；04 §2；02 §1 | 184、197 |
| Claude Sonnet 4.6 ／ Opus 4.5 | Anthropic 官方 · 经 OrcaRouter ④ | ④ | `disabled` 收（可关） | — | ✅ 守 enum；与工具同用两轮都合 schema；流式走 `text_delta` | 强制与 schema 不冲突 | — | — | — | 名单要列两种拼法（`claude-opus-4-5`／`claude-opus-4.5`） | 【实测 2026-09-26 补测】 | 04 §2 | 183 |
| Claude（同上五款） | OrcaRouter · ① 线路（翻译层） | ① | 思维链在 `reasoning_content` | — | ⚠ | ⚠ | ⚠ | PDF `file` 部件 ✅（推断） | 目录同上；`usage.cost` | — | 【实测 2026-09-26】 | 01 §9.5、02 §1 | — |
| claude-opus-4-6 ／ -5（两款一致） | New API · Kiro 渠道（`[kiro]`…`[特价kiro量]`；后端 Kiro 非 Anthropic API） | ④ | 三种 `thinking` 都照办；`display` 🔇；`effort` 只 `low` 有效；`bogus`／`budget ≥ max_tokens`／思考时温度 🔇 200 | 回传 ✅；**签名不校验**（篡改／删都 200 🔇） | 🔇 `output_config.format`／`output_format` 都无视 → cue-only | 强制只在**非流式**生效：流式 🔇；非流式带思考时好时坏 | 见 §14：search 🔀 劫持 ／ fetch・code 🔇 假装执行 | base64 图 ✅；URL 图 🔇；PDF 🔇；纯文本 `document` 无 `citations` | `max_tokens` 🔇；无 `anthropic-version` 也 200 | 不注入；`cache_control` 只写不读；usage 估算（流式 301 vs 非流式 102） | 【实测 2026-09-23】 | 01 §9.2；03 §3.3；04 §2、§4；05 §5；06 §1、§8 | 65、137、138–145 |
| Claude Sonnet（Kiro） | New API · Kiro 渠道 | ①④ | ⚠ 没测，按推断收进名单 | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | — | — | ⚠ 推断【实测 2026-09-23 仅 opus】 | 01 §9.2 第 5 条 | — |
| claude-opus-4-6 ／ -5 | New API · CC 渠道（`[CC量]`，推测 Claude Code 通道） | ④ | 思考 ✅（opus-5 **文本恒空**）；`display:"omitted"` ✅；`effort` 分不开；`bogus`／思考时温度 🔇 200 | 篡改 `signature` 200 🔇；回传 ✅ | opus-4-6 🔇 无视；opus-5 ✅ **执行** | 不带思考 ✅；带 adaptive 时好时坏 | 见 §14：search ✅ ／ fetch ✅ ／ code 🔇 | PDF ✅；URL 图 🔇；base64 ✅ | `max_tokens` ✅ | 缓存真；opus-5 按思考计费无文本 🔇 | 【实测 2026-09-23】 | 01 §9.2 第 5 条；03 §3.3；04 §2、§4；05 §5；06 §1 | 137、147、149、150 |
| claude-opus-4-6 ／ -5（含 `-thinking`） | New API · anti 渠道（`[anti量]`，推测 Antigravity） | ④ | ❌🔇 **任何思考参数都不想**；乱写 200 | 无 thinking 块 | 🔇 无视 | 强制两路径都 0 → 降 `auto` | 见 §14：全 🔇 丢 | PDF 🔇（纯文本也丢）；URL 图 ❌ 500；base64 ✅ | `max_tokens` ④ ✅ | 约 30 token 注入；无缓存字段 | 【实测 2026-09-23】 | 01 §9.2；03 §3.3；04 §2、§4；05 §5；06 §1 | 148、151 |
| claude-opus-4-6 ／ -5 | New API · AWSb 渠道（`[正向AWSb量]`，Bedrock 正向；id `msg_bdrk_`） | ④ | 思考 ✅ **真分档**；`display:"omitted"` ✅；乱写／思考时温度 ❌ 400 与官方同文 | 篡改 `signature` ❌ 400（校验）；回传 ✅ | ✅ 执行 | 强制 ✅ | 见 §14：❌ 各 400 整条 | PDF ✅ **返回 `citations`**（唯一）；URL 图 ❌ 400；base64 ✅ | `max_tokens` ✅ | 缓存真；唯一「按 400 学降级」生效的渠道 | 【实测 2026-09-23】 | 01 §9.2 第 4 条；03 §3.3；04 §2、§4；05 §5；06 §1 | 147、150 |
| claude-opus-4-6 ／ -5 | New API · Kiro ／ CC ／ anti ／ AWSb 四渠道 | ① | `max`／`none`／乱写 🔇 不想（转换层）；Kiro 顶层 `thinking` 🔇 | `reasoning_content`；`reasoning_tokens` 恒 0 | 🔇 `response_format` 丢（四渠道，含 ④ 执行 schema 的 AWSb） | Kiro 流式 🔇、非流式生效；anti 非流式 5 次 1 次、流式 0；AWSb ✅ | 见 §14：Kiro 🔀 ／ CC ✅ ／ anti 🔇 ／ AWSb ❌ 400 | PDF：Kiro 🔇、anti ✗、CC／AWSb ✓；Kiro http 图 🔇、data ✅ | `max_tokens`：Kiro／anti 🔇 无视 | ① cue 条件追加 → 实现不补 cue；anti 同渠道两面不同 | 【实测 2026-09-23】 | 01 §9.2；03 §3.3；04 §2、§4；05 §5 | 138–140、142、143、150、151 |
| claude-opus-4-6 ／ -5 | New API · 官key 渠道（`[官key量]`） | ④① | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ❌ 502 `Upstream request failed` | 【实测 2026-09-23】 | 01 §9.2「五个渠道」 | — |
| Claude（经中转） | 某中转（Joycai 线上流量，未具名） | ① | — | — | — | 畸形：`arguments` 背靠背多对象；调用 id 空串 → 下一轮重复 `tool_call_id` 400 | — | — | — | 工具以空参数执行 🔇 | 【实测 2026-08-08】【实测 2026-08】 | 05 §3；02 §3.2 | 105、106 |
| Claude opus-4.5（点号 id） | 任意中转 | ④ | — | — | 名单只写连字符 id 时 🔇 不命中 | — | — | — | — | 静默不命中 | 【实现】 | 04 §2 | 183 |

### 随平台变化的特性

- **思考有没有、有没有文本**：官方／OrcaRouter／AWSb／CC opus-4-6／Kiro 有文本；CC opus-5 恒空；anti 不想；Kiro `effort` 只两态，AWSb 真分档。【实测 2026-09-23】坑 141、148、149
- **签名校不校验**：官方与 AWSb 改签名 400；Kiro／CC 篡改、删都 200。【实测 2026-09-23】【实测 2026-09-26】坑 137
- **结构化 `output_config.format`**：官方五款守 enum、AWSb 执行、CC 按型号、Kiro／anti 无视；① `response_format` 整台 New API 都丢。【实测 2026-09-23】【实测 2026-09-26】坑 142、150
- **服务端工具四种答案**：Kiro 劫持／真搜／假装；CC 真搜真抓、code 丢；anti 全丢；AWSb 400；官方经 OrcaRouter 真搜。【实测 2026-09-23】【实测 2026-09-26】坑 139、144
- **PDF／URL 图片**：AWSb 读 PDF 且唯一返回 `citations`；CC 读 PDF；Kiro／anti 丢；可移植的只有 base64 图。【实测 2026-09-23】【实测 2026-09-26】坑 143
- **`max_tokens` 与计费**：Kiro 无视且缓存只写不读；anti ① 无视 ④ 生效、无缓存字段；CC／AWSb 生效且缓存真。【实测 2026-09-23】坑 145、151
- **「发 X 会不会 400」**：官方对未知键／`bogus`／非法 schema 400；经 OrcaRouter 全 200——乱写 200 不能判成反代。【实测 2026-09-26】坑 174、182

## 5 Gemini

### 家族固有特性（跨平台一致）

- 思考 `thinkingLevel: LOW／MEDIUM／HIGH`（小写也收、`"lowest"` 400【实测 2026-09-28，仅 AI Studio】）；必带 `includeThoughts: true`；`thinkingBudget` 与 `thinkingLevel` 只发一代。【文档】【参考实现】03 §2、§3
- `MINIMAL` 不是每个型号都有，缺时 400 非降级；「关闭」映射到 `LOW`。旧：2026-09-26 前 off → `MINIMAL` → 新：`LOW`。【实测 2026-09-26】【文档】坑 170；03 §2
- 回传义务：parts 原样回灌（含 `thoughtSignature`）；缺签名旧型号 200 + `MISSING_THOUGHT_SIGNATURE`、3.8 Flash 400。【参考实现】【实测 2026-09-26】坑 173；03 §5、05 §3
- 流：每 chunk 完整对象；旧型号 `functionCall` 无 id、3.8 Flash 起带 `id`。【文档】【实测 2026-09-26】02 §2.2、§3.2
- usage：`thoughtsTokenCount`、`toolUsePromptTokenCount` 在主计数之外；Vertex 流式只末块带。坑 18、191；06 §1
- 结构化：`responseMimeType` + cue 双发；`responseJsonSchema` 与 `responseSchema` 互斥。【实测／经验】04 §2
- 内置工具与函数并列；无 `max_uses`；按查询条数计费；「搜没搜」只认 `webSearchQueries`。【实测 2026-09-26 仅 Vertex 经 OrcaRouter】坑 178、190、194、195；05 §5
- `defer_loading` 整个被拒（第三方报告 ⚠）。坑 69；05 §7
- 三层错误：`promptFeedback`、拦截类 `finishReason`、请求缺陷。【文档】06 §2
- 请求键官方两种拼写都收；New API ③ 面只认 camelCase（见表）。

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Gemini 3.8 Flash（`google/gemini-3.8-flash`） | OrcaRouter · ③ 线路（**Vertex AI 原样**） | ③ | 三档 ✅ 单调；`MINIMAL`／`BOGUS` ❌ 400；`thinkingBudget: 0` 🔇 照想；不设与关闭分不开 | 摘要整段 `thought:true` part；`thoughtSignature` 挂 text part、流式末块；缺签名 ❌ 400；流末 `{text:""}` 回灌 ❌ 400 | ✅ `responseJsonSchema`／`responseSchema` 守住；与 `googleSearch` 同发 200 | `functionCall` 带 `id`；`mode:"ANY"` 与内置工具同发 200 | 见 §14：三者 ✅ | `inlineData`／`inline_data` 都收；PDF ✅ 一页 520 token | 目录 1,048,576／65,536；usage 只末块；`costUsd` 需 `X-OrcaRouter-Include-Cost` | `thinkingBudget:0` 不关；`:countTokens` 当生成计费；错误信封改 OpenAI 形 | 【实测 2026-09-26】【实测 2026-09-28】 | 03 §2、§2.1、§4、§5；02 §1–§3；04 §2；05 §3、§5；06 §1、§2 | 170–173、176、177、178、186、190–195、197、203、204 |
| Gemini 3.8 Flash | OrcaRouter · ① 线路（翻译层） | ① | 只报 `reasoning_tokens` | — | ⚠ | 无 `parameters` 的内置工具函数名 → 网关换成原生 📄 | 同左 📄 | `video_url` 🔇 **200 静默丢**（输入 token 不变） | 目录同上 | 视频静默丢（最坏一种） | 【实测 2026-09-26】【实测 2026-09-28】【文档 2026-09】 | 01 §9.5；02 §1；05 §5 | 205 |
| gemini-3-flash-preview ／ 3.8-flash | Google AI Studio 官方直连 | ③ | `thinkingLevel` 小写／大写都 ✅；3.8-flash usage **不带 `thoughtsTokenCount`**；`"lowest"` ❌ 400；`MINIMAL`、`thinkingBudget:0` 未测 | — | — | — | 见 §14：`googleSearch`「未实测、照发」 | — | — | 发小写不算错；缺 `thoughtsTokenCount` ≠ 没想 | 【实测 2026-09-28】——本库第一条 AI Studio 直连实测 | 03 §2；20 §3 Gemini 节 | 222 |
| Gemini 3.1 Pro ／ 2.5 系 ／ 2.x | Google 官方（AI Studio） | ③ | 📄 3.1 Pro 只有 `low／medium／high`；2.5 系 `extended`（`thinkingBudget`） | — | — | — | 见 §14：2.x 与函数工具同发 ⚠ 未测 | — | — | ⚠ | 【文档】【参考实现】【未测】 | 03 §2、§3；05 §5 | 170 |
| Gemini 旧型号（3.8 Flash 之前） | Google 官方 | ③ | — | `functionCall` 无 id、靠函数名匹配；丢签名 → 200 + `MISSING_THOUGHT_SIGNATURE` | 有模型 🔇 无视 `responseMimeType`（型号未给 ⚠） | 适配器自造 `gtc_…` id | — | — | `inputTokenLimit`／`outputTokenLimit` 端点直接给 | 缺签名不是 400 | 【参考实现】【实测／经验，日期未标】⚠ ⏳待复核 | 02 §1、§2.2、§3.2；03 §5；04 §2；06 §6 | 173 |
| Gemini（任意） | New API 中转站 · ③ 面 | ③ | — | — | — | — | — | 只认 camelCase：snake_case 🔇 **图片和系统提示静默丢** | — | snake_case 静默丢 | 【实测 2026-09-05】 | 02 §2.2 | 2、111 |

### 随平台变化的特性

- **请求键拼写**：官方（含 Vertex 经 OrcaRouter）两种都收；New API ③ 面只认 camelCase。【实测 2026-09-05】【实测 2026-09-26】坑 2、111
- **视频输入**：Gemini 本身读视频，经 OrcaRouter ① 翻译层静默丢；③ 线路未测。【实测 2026-09-28】坑 205
- **缺签名报法**：旧型号 200 + `MISSING_THOUGHT_SIGNATURE`；3.8 Flash（Vertex 经 OrcaRouter）HTTP 400。坑 173
- **网关特有**：`:countTokens` 当生成计费、`{text:""}` 回灌 400、`thinkingBudget:0` 关不掉、报价需请求头——只对 OrcaRouter 成立。【实测 2026-09-26】坑 171、172、176、186
- **AI Studio 直连 vs Vertex 经 OrcaRouter**：直连只证实档位不分大小写、`lowest` 400；网关上的 `MINIMAL` 400、缺签名 400、`thinkingBudget:0` 照想未直验。【实测 2026-09-28】坑 222；OQ-021

## 6 Grok

### 家族固有特性（跨平台一致，仅测于 xAI 官方）

- ② 默认 `high`；4.5／4.6 **拒 `none`**；4.3／4.5／4.6 拒 `max`（400）；未知顶层键忽略。【实测 2026-09】坑 66；03 §7.1、02 §7.2、01 §9.1
- 加密推理须 `include:["reasoning.encrypted_content"]`；缺了第二轮照样 200。【实测 2026-09】03 §7.3
- 图片总像素 ≥512、宽高 ≥8。【实测 2026-09】坑 67
- 推理模型上 `frequency_penalty` 实测 200（文档：报错）。【实测 2026-09】01 §9.1
- `tool_search`／`defer_loading` ❌ 403（仅 alpha）。【实测】05 §7
- ④ 官方标完全弃用；① 标 Deprecated。【文档】01 §9.1

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| grok-4.5 ／ 4.6 | xAI 官方 `https://api.x.ai/v1` | ② | 默认 `high`；`none` ❌ 400；`max` ❌ 400 | `include` 必发才有密文 | ⚠ | ⚠ | 见 §14：web_search ✅ ／ `tool_search` ❌ 403 | 图片 ≥512 像素 | `frequency_penalty` 200 | 「关闭」芯片必然 400 | 【实测 2026-09】【实测，日期未标】⚠ ⏳待复核 | 01 §9.1；03 §7.1、§7.3；05 §5、§7；06 §1 | 66、67 |
| grok-4.3 | xAI 官方 | ②；①（legacy） | ② `max` ❌ 400 | — | ⚠ | ⚠ | 同上 | ① `video_url` ❌ 400 `Empty content block` | ⚠ | 视频 400 会响 | 【实测 2026-09】；视频【实测 2026-09-28】 | 01 §9.1；02 §1 | 206 |

### 随平台变化的特性

- 只在 xAI 官方测过，无跨平台对比；Grok Imagine 出图／视频不在本表（🖼🎬 见 13、14 篇）。坑 123–129

## 7 DeepSeek

### 家族固有特性（跨平台一致）

- ① 档位表**没有 `none`**（🔇 照想）；只有 `thinking:{type:"disabled"}` 关得掉（① 未实测 ⚠；④ 已实测真关）；`medium` 折 `high`。【文档 2026-08】【实测 2026-09-28，④】03 §2、§3.5、§5
- ④ 面思考**默认开**（仅官方 ④）；`bogus` 官方 422 点名枚举、百炼 400（面级 ⚠）。【实测 2026-09-28】03 §3.5
- 回传义务**两个方向都 400**：有工具轮必回传、无工具轮不要携带。【文档 2026-08】坑 1（对比）；03 §5
- 结构化：`json_object` 需 "JSON"；**不支持 `json_schema`**。【文档】04 §2
- usage 顶层 `prompt_cache_hit_tokens`／`miss_tokens`，无标准 `cached_tokens`。【文档；Joycai 2026-09-14 修复】06 §1
- V4：按错误文案参数名识别「强制被拒」。【文档】04 §4

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DeepSeek 推理系（`deepseek-flash` 实测视频） | DeepSeek 官方 | ① | `none` 🔇；`disabled` 📄（未实测 ⚠）；`medium` 折 `high` | `reasoning_content`；两个方向漏回传都 ❌ 400 | 📄 `json_object`；`json_schema` 不支持 | 📄 错误文案点名参数 | 见 §14：无 | `video_url` ❌ 422 `unknown variant` | `prompt_cache_hit_tokens`／`miss_tokens` 顶层 | `none` 无症状；缓存命中按标准拼写读会全价 | 【文档 2026-08】；视频【实测 2026-09-28】 | 03 §2、§5；04 §2；06 §1；02 §1 | 206 |
| deepseek-v4-pro ／ deepseek-flash | DeepSeek 官方 `/anthropic/v1/messages` | ④ | **默认开**；`disabled` ✅ 真关（带温度也收）；`adaptive`／`enabled+budget` 都想；`bogus` ❌ 422 点名枚举 | — | — | — | — | — | 未知字段 200；`top_p`／`temperature` 范围 📄（03 §3.5） | 文档：`claude-*` 名映射到 v4-pro／flash，**未知模型名也 🔇 映射到 flash** 📄 | 【实测 2026-09-28，每条一次】 | 03 §3.5；06 §2；20 §3 DeepSeek 节 | 217、221 |
| deepseek-v4-pro（托管） | 阿里百炼 · ④ `/apps/anthropic` | ④ | `disabled` ✅ 真关；默认值未测 — | — | — | — | — | — | — | — | 【实测 2026-09-28，一次】 | 03 §3.5 | — |
| `deepseek-v4`（托管） | 阿里百炼 DashScope | ② | ⚠ | ⚠ | ⚠ | ⚠ | 见 §14：`code_interpreter` ✅ 放行 | ⚠ | ⚠ | — | 【实测 2026-09-17】 | 05 §5 | — |

### 随平台变化的特性

- **服务端工具**：官方无；同一 `deepseek-v4` 托管在百炼 ② 面 `code_interpreter` 放行——是 (平台, 面) 属性。【实测 2026-09-17】
- 官方 ① `video_url` 422 会响；其余平台未测。【实测 2026-09-28】坑 206
- **④ 面默认值与关闭结局**：官方 ④ 默认开、`disabled` 真关、非法值 422；百炼 ④ 上 v4-pro 也真关、非法值报百炼 400（面级 ⚠）、默认值未测。【实测 2026-09-28】坑 217

## 8 Qwen（千问）

### 家族固有特性（跨平台一致，仅测于 DashScope 百炼）

- 两代思考控制：商业款**默认关**（`enable_thinking`）；3.5+ **默认开**；3.7+ 收 `reasoning_effort`；部分开源版强制 `stream: true`。【文档／参考实现】坑 9；03 §3 `switch`
- 思考开时 `tool_choice` 只 `auto／none` → 降 `auto`。04 §4
- 结构化：`json_object` 全线（缺 "json" ❌ 400）；`json_schema` 只最新两三代。【文档】04 §2
- ① 私有顶层 `enable_search`（无痕）、`agent_max`、`enable_code_interpreter`；后两者与 `tools` 同发 ❌ 400；`enable_code_interpreter` 非流式 ❌ 400。【实测 2026-09-17】坑 10、74；05 §5
- ② 面 `web_search`／`web_extractor`／`web_search_image`／`code_interpreter`；无 `encrypted_content`，回传明文 `summary`；文档无 `text` 字段 ⚠。【文档】【实测 2026-09-17】坑 70、76；03 §7.2、§7.3、05 §5、04 §5.1
- 视频 `video_url` + `fps`（私有扩展）；`vl_high_resolution_images` 私有。【文档】02 §1
- 一把 key 三张 chat 脸：①、Ⓓ、④ `/apps/anthropic`（只服务模型子集；新旧 host 等价）。【文档 2026-09】【实测 2026-09-28】01 §8.1、03 §3.5
- ④ 面千问默认想、`disabled` 真关；`signature` 恒空串；qwen-turbo 从不想。【实测 2026-09-28】03 §3.5、§4.1

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Qwen（通用：商业款 ／ 3.5+ ／ 3.7+） | 阿里百炼 DashScope compatible-mode | ① | 📄 按代：商业款默认关、`enable_thinking`；3.5+ 默认开；3.7+ 收 `reasoning_effort` | `reasoning_content` | `json_object` ✅；缺 "json" ❌ 400；`json_schema` 只最新两三代 📄 | 思考开时只 `auto／none` 📄 | 见 §14：`enable_search` ✅ 无痕 ／ `agent_max` ✅ ／ `enable_code_interpreter` 按型号 | `video_url` ✅（见 qwen3-vl-plus）；PDF 仅 qwen3.8-max | 按次价低三个数量级；无上限字段 | 不发开关永不思考 🔇；辅助请求继承服务端工具多花钱 | 【文档／参考实现】+【实测 2026-09-17】 | 03 §3；04 §2、§4；05 §5 | 9、10、74、77 |
| Qwen（通用） | 阿里百炼 DashScope | ② | ⚠ | 文档 `reasoning_text.delta`；回传明文 `summary` 📄 | 文档无 `text` 字段 ⚠ | — | 见 §14：`web_search` ✅ ／ `web_extractor` 仅随搜索 ／ `code_interpreter` ✅ 按模型 id | 文档说不支持 PDF ⚠ | `usage.x_tools.code_interpreter.count` | `response.failed` 在 HTTP 200 里；画图链接约 12 小时过期 | 【文档】【实测 2026-09-17】第六个样本 | 03 §7.2、§7.3；04 §5.1；05 §5；01 §9.2 | 70、76、78 |
| `qwen3-vl-plus` | 阿里百炼 DashScope | ① | — | — | — | — | — | `video_url` ✅、**`fps` 生效**；小纯色片段 ❌ 400 | — | 夹具太小误判「不读视频」 | 【实测 2026-09-28】第十九个样本 | 02 §1；20 §3 百炼节 | 206–208 |
| `qwen3.8-max` | 阿里百炼 DashScope | ① | — | — | — | — | — | PDF `file` 部件 **仅此款** | — | — | 【文中陈述】⚠ | 02 §1 | — |
| `qwen3.8-flash` ／ qwen3.8 全系 | 阿里百炼 DashScope | ①／② | — | — | — | — | 见 §14：① `agent_max`／`enable_code_interpreter` ❌ 400 ／ ② `code_interpreter` ✅ | — | — | — | 【实测 2026-09-17】 | 05 §5 | 75、78 |
| `qwen3-max`（及日期版） ／ `qwen3.5-plus` | 阿里百炼 DashScope | ① | — | — | — | — | 见 §14：`agent_max` ✅；qwen3-max 不带策略的 `enable_search` 🔇 **没搜** | — | — | `enable_search` 不搜无症状 | 【实测 2026-09-17】 | 05 §5 | 10 |
| `qwen-max` ／ `qwen3-max-preview` | 阿里百炼 DashScope | ① | — | — | — | — | 见 §14：`enable_code_interpreter` 🔇 静默忽略 | — | — | 静默忽略 | 【实测 2026-09-17】 | 05 §5 | 75 |
| qwen3.5–3.7 plus／max／flash、部分开源版 | 阿里百炼 DashScope | ①／② | — | — | — | — | 代码解释器正则表放行（锚定；下一代不预放行） | — | — | — | 【实测 2026-09-17】 | 05 §5 | 75 |
| qwen3.8-flash ／ 3.7-flash ／ 3.5-plus | 阿里百炼 · ④ `/apps/anthropic`（新旧 host 等价） | ④ | **默认想**；`disabled` ✅ 真关；`adaptive` 也收；面级 400（模型未标 ⚠）：`bogus` ❌ 400 `Request body format invalid`；`budget_tokens` > `max_tokens` ❌ 400 | 有文本、`signature` 恒空串 | — | — | — | — | 温度 [0, 2)（`2.5` ❌ 400 ⚠）；未知字段 200 放过 | 未知模型 ❌ 400（面级） | 【实测 2026-09-28，每条一次】 | 03 §3.5、§4.1；06 §2；20 §3 百炼节 | 217、218 |
| qwen-turbo | 阿里百炼 · ④ `/apps/anthropic` | ④ | 从不想；`disabled` 未测 — | — | — | — | — | — | — | — | 【实测 2026-09-28，一次】 | 03 §3.5 | — |
| 旧行：Anthropic 面模型子集（具体哪些未给） | 阿里百炼 `/apps/anthropic/v1/messages` | ④ | 旧：⚠ → 新：见上两行与各家族节的「阿里百炼 · ④」行（MiniMax-M2.5 §11、glm-5.3 §9、kimi-k2-thinking／k2.6 §13、deepseek-v4-pro §7）；完整名单仍未枚举（OQ-030） | — | — | — | — | — | — | — | 【文档】→【实测 2026-09-28】 | 01 §8.1；03 §3.5 | — |
| Qwen-Audio | 阿里百炼 DashScope | Ⓓ 私有面 | — | — | — | — | — | 仅私有面可用 | ⚠ | — | 【文档】 | 01 §8.1 | — |
| Qwen（同步 ASR） | 阿里百炼 | 🎤 | — | — | — | — | — | 同步接口 🔇 忽略 `diarization_enabled`；无句级时间戳 | — | 分离只走 `-filetrans` | 【实测】 | 16 §4.1、§7 | 115、116 |

### 随平台变化的特性

- 千问只在百炼测过，「随平台变化」= **同一端点随面与型号**：`code_interpreter` ① 面按型号「跑／静默忽略／400」、② 面到 3.8 都跑；`agent_max` 3.8-flash 400、3-max／3.5-plus 收；`enable_search` 不带策略在 qwen3-max 没搜。【实测 2026-09-17】坑 10、75
- 思考控制按代：商业款要 `enable_thinking`，3.5+ 默认开，3.7+ 收 `reasoning_effort`——按模型 id 预填。坑 9
- 对比火山方舟：千问的 `enable_thinking:false` 挂到豆包被静默忽略（坑 114）；方舟 ① `none` 关得掉、千问要开关。
- **同一端点随面（① vs ④）**：④ 千问默认想、`disabled` 真关，qwen-turbo 从不想；④ 的关闭被翻成 ① `enable_thinking` 下发，拒绝时点名 ① 字段名；④ `bogus` 是百炼自己的 400。【实测 2026-09-28】坑 217、219

## 9 GLM（智谱）

### 家族固有特性（跨平台一致，仅测于智谱自家端点）

- 思考控制按代三种（① 面，全部默认开）：**5.3 代**不能关、只收 `low／high／max` 真分档；**5.2** 可关、实有两档、`none` 🔇 关不掉；**4.5–5.1** 可关、`reasoning_effort` 🔇 丢弃。按模型 id 预填。【实测 2026-09-19，11 款】坑 94、95；03 §3.1
- `thinking.clear_thinking` 默认 `true`，`false` = 保留式思考；缺 `type` 自家端点 200。【实测 2026-09-19】03 §3.1
- `reasoning_tokens` 4.5-air 从不给；glm-5／4.6／4.5 关思考时缺席。【实测 2026-09-19】03 §3.1
- 结构化：`json_object` 不查 "json"；`json_schema` 🔇 静默无视。【实测 2026-09-19】坑 98；04 §2
- tool_choice 砍档第三种变体：实测按代不同（见表）→ 平台级降 `auto`（1210 文案不提 tool_choice）。【实测 2026-09-19】坑 96、97；04 §4
- 对话内联网 `tools[]` `web_search` 项，结果在顶层 `web_search[]`；必须 `search_intent:false`。【实测 2026-09-19】坑 100；05 §5
- 错误：信封 `{"error":{"code":"1210"}}`；`finish_reason` `sensitive`／`network_error`／`model_context_window_exceeded`；未知顶层字段放过。【实测 2026-09-19】【文档 2026-09】坑 99；06 §2
- 多模态：只有 5.3-flash／flashx 读图；收 `video_url`、忽略 `fps`（日期未标 ⚠）。【实测 2026-09-19】【实测，日期未标】⏳待复核 01 §9.4、02 §1
- `max_tokens` 上界 400 生成前拒并报范围；上下文按代 128K–1M（见表）。【实测 2026-09-19】01 §9.4
- 服务端工具归平台：独立端点 `/web_search`、`/reader`（§14）；百炼／火山由平台执行。【实测 2026-09-19】05 §5

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| glm-5.3 ／ 5.3-flash ／ 5.3-flashx | 智谱 BigModel · 按量 `/api/paas/v4` | ① | 默认开；**不能关**（`disabled` ❌ 400）；`low／high／max` ✅ 真分档；`none`／`medium`／乱写 ❌ 400 | `reasoning_content`；工具轮回传接受 | `json_object` ✅；`json_schema` 🔇 | `required`／具名 🔇 不强制、`none` 🔇 5.3-flash 照调 | 见 §14：对话内 `web_search` ✅ | 5.3-flash／flashx 读图 ✅；5.3 `image_url` ❌ 400 | 上下文 1M；`max_tokens` ≤131,072 | json_schema 无视；不搜却说搜了 | 【实测 2026-09-19】 | 01 §9.4；03 §3.1；04 §2、§4；05 §5；06 §2 | 94、95、97、98、100 |
| glm-5.2 | 智谱 BigModel · 按量 | ① | 默认开；关 `disabled` ✅；七值都收但实有两档；`none` 🔇 关不掉 | 同上 | 同上 | 同 5.x（不强制） | 同上 | `image_url` ❌ 400 | 上下文 1M；`max_tokens` ≤131,072 | `none` 关不掉 | 【实测 2026-09-19】 | 03 §3.1；04 §4 | 94、95 |
| glm-5 ／ 5-turbo ／ 5.1 | 智谱 BigModel · 按量 | ① | 默认开；关 `disabled` ✅；`reasoning_effort` 任何值 🔇 丢弃；非法 effort 笼统 400 | glm-5 关思考时 `reasoning_tokens` 缺席 | 同上 | `required`／具名 🔇 不强制 | 同上 | `image_url` ❌ 400 | 上下文 5-turbo 204,800、5.1／5 200K；`max_tokens` ≤131,072 | 档位是假控件 | 【实测 2026-09-19】 | 03 §3.1；04 §4 | 94、95、97 |
| glm-4.7 ／ 4.6 ／ 4.5 | 智谱 BigModel · 按量 | ① | 同上行（开关型，档位丢弃） | 4.6／4.5 关思考时 `reasoning_tokens` 缺席 | 同上 | `required` 🔇；具名：思考开 ❌ 400 `1210`、关时 🔇；`none` ✅ | 同上 | `image_url` ❌ 400 | 上下文 4.7／4.6 200K、4.5 128K；`max_tokens` ≤131,072（4.5 文档 96K） | 具名 400 笼统，学降级失效 | 【实测 2026-09-19】 | 03 §3.1；04 §4；01 §9.4 | 94–97 |
| glm-4.5-air | 智谱 BigModel · 按量 | ① | 同上行 | `reasoning_tokens` 从不给 | 同上 | `required`／具名／`none` ✅ **真强制**——平台级降 `auto` 后失去 | 同上 | `image_url` ❌ 400 | 上下文 128K；`max_tokens` ≤98,304 | — | 【实测 2026-09-19】 | 03 §3.1；04 §4 | 95 |
| GLM（型号未标） | 智谱 BigModel · 按量 | ① | — | — | — | — | — | 收 `video_url`、`fps` 🔇 忽略 | — | `fps` 静默无效 | 【实测，日期未标】⚠ ⏳待复核 | 02 §1 表后 | 206、208 |
| glm-4.7 | 智谱 · Coding Plan `/api/anthropic` | ④ | 默认**不**思考——与 ① 面相反；`disabled` 未测 — | — | — | — | — | — | — | 默认值按「模型 × 面」问（只探两次） | 【实测 2026-09-19】 | 03 §3.1、§3.5；01 §9.4 | — |
| glm-5.3 ／ 5.3-flash | 智谱 · Coding Plan `/api/anthropic` | ④ | 默认**想**；`disabled` ❌ **400** 1210；`output_config:{effort:"low"}` ✅ **无 thinking 块**；`adaptive`／`enabled` 都想；`bogus` ❌ 同一句 1210 | 5.3-flash 块无 `signature`【实测 2026-09-19，只探两次】 | — | — | `usage` 带 `server_tool_use.web_search_requests`【实测 2026-09-19】 | — | 未知字段 200 | 文案不指向值 | 【实测 2026-09-28，每条一次】 | 03 §3.5；01 §9.4；20 §3 智谱 Coding Plan 节 | 217 |
| glm-4.6 | 智谱 · Coding Plan `/api/anthropic` | ④ | `disabled` ✅ 真关；默认值未测 — | — | — | — | — | — | — | — | 【实测 2026-09-28，一次】 | 03 §3.5 | — |
| glm-5.3（托管） | 阿里百炼 · ④ `/apps/anthropic` | ④ | `disabled` ❌ 400 `enable_thinking parameter is restricted to True`（透传，点名 ① 字段）；默认值未测 | — | — | — | — | — | — | 拒绝点名别家协议的字段 | 【实测 2026-09-28，一次】 | 03 §3.5；06 §2 | 219 |
| 11 款（同上） | 智谱 · Coding Plan ① `/api/coding/paas/v4`、④ `/api/anthropic`、② `/api/v1` | ①④② | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ② `/models` Codex CLI 目录形（3 个）；④ Anthropic 形 | 同一把按量 key 200 但**扣套餐**；路径决定扣哪笔钱 | 【实测 2026-09-19 + 文档】 | 01 §9.4 | — |
| GLM（托管） | 千问百炼 ／ 火山方舟 | 视平台 | — | — | — | — | 见 §14：由平台执行搜索 | — | — | — | 【实测 2026-09-19】 | 05 §5 | — |

### 随平台变化的特性

- **联网**：自家端点靠对话内 `tools[]` `web_search`（`search_intent:false`）或 `/web_search` 端点；托管在百炼／火山由平台执行。【实测 2026-09-19】
- **默认思考**：glm-4.7 ① 面默认想、Coding Plan ④ 面默认不想。【实测 2026-09-19】
- **④ 面默认值与关闭结局按模型**：4.7 不想；5.3 系想且 `disabled` 400（1210）；4.6 真关。glm-5.3 托管到百炼 ④ 也 400，报法换成透传的 `enable_thinking`。【实测 2026-09-28】坑 217、219
- **计费路径**：同一把 key 打 `/api/paas/v4` 扣余额、打 Coding Plan 三路径扣套餐，选错只换一笔钱。【实测 2026-09-19】

## 10 豆包 Seed（火山方舟）

### 家族固有特性（跨平台一致，仅测于火山方舟 · 套餐 base）

- ① 思考：默认开；`reasoning_effort` 七档 + 顶层 `thinking`（`auto` ❌ 400）；`none`／`minimal`／`disabled` **真关**；`high` + `disabled` ❌ 400；`enable_thinking:false` 🔇 照想。【实测 2026-09-18】坑 114；03 §3.2
- ② 思考：默认开；关 `reasoning:{effort:"none"}`；也认 `thinking:{type:"disabled"}`。【实测 2026-09-18】【实测 2026-09-23】03 §3.2
- ④ 思考：默认开；关 `disabled` 真关；`adaptive`／`enabled+budget` 都收；`output_config.effort` 不报错 ⚠。【实测 2026-09-18】【文档 2026-09】03 §3.2
- 取回／回传：① 摘要 + `encrypted_content` 同帧，密文优先，只回摘要 🔇；② 整条 `reasoning` item；④ thinking 块（签名按代，见表）；回传出错不响。【实测 2026-09-23】坑 133、137；03 §3.2、§5
- 强制 `tool_choice` 思考开时 200 但**推理 token 0**（🔇）。【实测 2026-09-18】03 §3.2、04 §4
- 结构化：① `json_schema` 要发 `strict:true`；守不守按型号（见表）。【实测 2026-09-23】坑 134；04 §2
- 多模态：PDF ①②④ 都读，`file_url` 三面都通——旧：「`file_url` 仅 ② 且只在按量 base」→ 新：三面都通（2026-09-23）；`file_id` 假 id 404；① 收 `video_url`（`fps` 不改账单 ⚠）。【实测 2026-09-18】【实测 2026-09-23】【实测 2026-09-28】坑 206、208；02 §1、01 §9.3
- ④ 关思考时听温度但 `0` 🔇 当未设；开思考带温度 200 不收敛；① `0` 生效。类目 `doubao-switch` 声明 `temperatureWhenOff:{zeroIsUnset:true}`。【实测 2026-09-28，每档 20 次】坑 198、201；03 §3.4
- 服务端搜索 ②④ 真跑、① **无**。【实测 2026-09-18】05 §5
- 套餐 `/api/plan/v3` 与按量 `/api/v3` 不通用；套餐无 Files API；挑模型（Seed 1.6 系 404）；上下文 256k。【实测 2026-09-18】【实测 2026-09-23】坑 80、81、135、136；01 §9.3

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| doubao-seed-2.0-pro（别名 `ark-code-latest`） | 火山方舟 · 套餐 `/api/plan/v3` | ① | 默认想；`none`／`minimal`／`disabled` ✅ 真关 0；`low`–`xhigh` 真分档；`auto` ❌ 400；`disabled`+`high` ❌ 400；`enable_thinking:false` 🔇 照想 | `reasoning_content` + `encrypted_content`；不回传多轮未报错 | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | 别家开关被静默无视 | 【实测 2026-09-18】 | 03 §3.2；01 §9.3 | 114 |
| doubao-seed-2.1-turbo ／ 2.0-lite ／ 2.0-mini | 火山方舟 · 套餐 | ① | 默认开；关 `disabled` 或 `none`／`minimal` ✅；七档收；`high`+`disabled` ❌ 400；强制 tool_choice 推理 0 🔇 | `reasoning_content` **只是摘要** + `encrypted_content` 同帧；密文优先；只回摘要 🔇 | `json_schema` + `strict:true`：2.1-turbo ✅ 守（不带 strict 🔇 越过）；2.0-lite 🔇 不守；2.0-mini ✅ 守 | 强制 200 但跳过思考 | 见 §14：① 无 | PDF `file_data`／`file_url` ✅；`file_id` 404；扁平 `file_data` ❌ 400；`video_url` ✅（`fps` 不改账单 ⚠） | 上下文 256k；`reasoning_tokens` 在末尾 `choices:[]` chunk；2.0-mini 温度 `0`–`0.3` 收敛、`1` 分散 | 只回摘要静默降级；2.0-lite 200 不守 schema | 【实测 2026-09-18】【实测 2026-09-23】【实测 2026-09-28】 | 03 §3.2、§3.4；04 §2；02 §1；01 §9.3 | 133、134、137、208 |
| doubao-seed-2.1-turbo ／ 2.0-lite ／ 2.0-mini | 火山方舟 · 套餐 `/api/plan/v3/responses` | ② | 默认开；关 `reasoning:{effort:"none"}` ✅ 0；也认 `thinking:{type:"disabled"}`；七档全收 | 整条 `reasoning` item 原样回传 | `text.format`（不带 strict）：2.1-turbo ✅；2.0-lite 🔇 不守；2.0-mini 值守、🔇 多出字段 | ⚠ | 见 §14：✅ 三款都跑 | `input_file.file_url` ✅、`file_id` 404；`input_image` ✅ | `reasoning_tokens` 在 `usage.output_tokens_details` | 打 `/api/plan/responses` 404（少 `/v3`） | 【实测 2026-09-18】【实测 2026-09-23】 | 03 §3.2；04 §2；05 §5；01 §9.3 | 134、135 |
| doubao-seed-2.0-lite ／ 2.0-mini ／ 2.1-turbo | 火山方舟 · 套餐 `/api/plan` + `/v1/messages`（`x-api-key` 与 Bearer 都收） | ④ | 默认开；关 `disabled` ✅ 真关；`adaptive`／`enabled+budget` 都收；强制 `{type:"tool"}` 推理 0 🔇 | 2.0 系块**无 `signature`**；2.1-turbo **有**但**不校验**（篡改／删都 200 🔇） | ⚠ | 强制跳过思考 | 见 §14：`web_search_20250305` + `max_uses` ✅ | `image` ✅；`document` base64／url ✅；`source.type:"file"` ❌ 400 | 关思考 + `0` 🔇 等于没发；`0.01`–`0.3` 收敛；开思考 + 温度 200 不收敛；`/v1/models` ❌ 401 | `0` 温度当未设；签名不校验 | 【实测 2026-09-18】【实测 2026-09-23】【实测 2026-09-28，2.0-mini 每档 20 次】 | 03 §3.2、§3.4、§5；05 §5；06 §5；01 §9.3 | 136、137、198、201 |
| Seed 1.6 系（doubao-seed-1-6-250615 ／ 1.6 ／ seed-code） | 火山方舟 · 套餐 | ① | — | — | — | — | — | — | — | ❌ 404 `UnsupportedModel` | 【实测 2026-09-18】【实测 2026-09-23】 | 01 §9.3；03 §3.2 | 81 |
| 豆包（对话） | 火山方舟 · 按量 `/api/v3` | ①②④ | ⚠ 对话面未实测（只有套餐 key）——记 `unknown`，不抄套餐 | ⚠ | ⚠ | ⚠ | 见 §14：未验 | `video_url` 没量到 ⚠ | ⚠ | 按量 key 上传文件能否被套餐 key 引用未验 ⚠ | 【未测 2026-09-28】【文档】 | 01 §9.3；02 §1；05 §5 | — |

### 随平台变化的特性

- 豆包只在**套餐 base** 测过，按量对话面全 `unknown`——「随平台变化」目前 = **套餐 vs 按量**：key 不通用、目录按套餐裁剪、套餐无 Files API 与 Seedance。【实测 2026-09-18】【实测 2026-09-23】坑 80、81
- **同一端点随面**：服务端搜索 ②④ 有、① 无；`json_schema` 2.0-lite ①② 不守、2.1-turbo 都守、2.0-mini ① 守 ② 多字段；④ 2.0 系无 `signature`、2.1 有但不校验；温度 ① `0` 生效、④ `0` 当未设。【实测 2026-09-23】【实测 2026-09-28】坑 134、137、198
- **对比千问**：方舟 `reasoning_effort:"none"` 真关、千问要 `enable_thinking`；把千问方言挂到方舟只是失效。坑 114
- **对比官方 Claude（④）**：方舟 `disabled` 真关（Claude 5 拒收）、篡改签名 200（官方 400）、开思考带温度 200（官方 400）。【实测 2026-09-23】【实测 2026-09-28】坑 137、201

## 11 MiniMax

### 家族固有特性（跨平台一致，仅测于 MiniMax 国内站）

- ① 面**总在想**且 `<think>` 塞进 `delta.content` → 需兜底切分器；`reasoning_tokens` 有值。【实测 2026-09-28】【参考实现】坑 15；03 §3.4、§6
- ① 面**交错思考回传不强制**（M3），保留时多计 26 prompt token。【实测 2026-09-28，样本量未标】03 §5
- ④ 面 `switch` 方言。旧：思考**默认关**、真关 → 新（2026-09-28）：**按型号**——M3 默认关且真关；M2.7 默认想、`disabled` 收下**照想**（🔇）。【实测 2026-09-28】03 §3、§3.5
- ④ 面**什么都收**：`bogus` 200 且**开始想**；未知模型名 🔇 改映射；唯一 400 是 `top_p:1.5`。【实测 2026-09-28】坑 220、221；03 §3.5、06 §2
- 温度**收下、不理会**；类目 `minimax` 不声明 `temperatureWhenOff`。【实测 2026-09-28，每档 20 次】坑 199、201；03 §3.4
- tool_choice 只 `auto／none` → 无条件降 `auto`。【实测 2026-08】04 §4
- `json_object` 不查 "json"。【实测 2026-08】04 §2
- 错误信封 `base_resp.status_code`——只认 `error` 会读成空回复；空 assistant 消息 400。【实测 2026-08】坑 6；06 §2
- ④ 兼容端点无 `pause_turn`；**拒收自己发出的块** ❌ 400 → 纯文本续跑。【实测 2026-08】坑 11；05 §6
- ①／④ 两张 chat 脸模型 id 一致。【文档 2026-08】01 §8.1

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MiniMax-M3 | MiniMax 国内站 `api.minimaxi.com/anthropic` | ④ | **默认关**；`disabled` ✅ 真关；无 `display`／`output_config`。型号未标（OQ-072）：`enabled+budget`、`adaptive`+`display` 都 200；`bogus` 🔇 **200 且开始想** | — | ⚠ | 强制降 `auto` | 见 MiniMax（通用）④ 行 | ⚠ | 温度收下不理会；`top_k:99999`、`temperature:2.5` 200；`top_p:1.5` ❌ 400 | 温度静默不理；`bogus` 开思考不响；未知模型名 🔇 改映射到 M3 | 【实测 2026-09-28，温度每档 20 次；其余每条一次】 | 03 §3、§3.4、§3.5；04 §4；06 §2；20 §3 MiniMax 节 | 199、201、202、217、220、221 |
| MiniMax-M2.7 | MiniMax 国内站 `api.minimaxi.com/anthropic` | ④ | 默认想；`disabled` 🔇 收下**照想**（与文档「M2.x 无法关闭」一致但不拒） | — | — | — | — | — | 「什么都收」型号未标（见 M3 行、OQ-072） | 关不掉且不响，只能看回复有无思考（03 §4.1） | 【实测 2026-09-28，每条一次】 | 03 §3.5 | 217 |
| MiniMax-M2.5（托管） | 阿里百炼 · ④ `/apps/anthropic` | ④ | 默认想；`disabled` ❌ 400 `enable_thinking parameter is restricted to True`（透传，点名 ① 字段） | — | — | — | — | — | — | 会响，但点名别家协议字段 | 【实测 2026-09-28，一次】 | 03 §3.5；06 §2 | 219 |
| MiniMax-M3 | MiniMax 国内站 `api.minimaxi.com/v1` | ① | 总在想；`<think>` 混进 `delta.content`；`reasoning_tokens` 有值 | 切出的只展示不回传；**回传不强制**：四种回法都 ✅ 200 | — | — | — | ⚠ | 看不出温度（不发也同答） | `<think>` 混进正文；回传缺失不响 | 【实测 2026-09-28】；【参考实现】 | 03 §3.4、§5、§6；06 §8 第 13 条 | 15、202 |
| MiniMax chat（通用，`switch` 端点） | MiniMax | ① | `<think>` 内联 | 同上 | `json_object` ✅ 不查 "json" | 只 `auto／none` → 无条件降 `auto` | — | ⚠ | 空 assistant 消息 ❌ 400 | `base_resp.status_code` 体内错误 🔇 读成空回复 | 【实测 2026-08】【文档 2026-08】 | 04 §2、§4；06 §2；01 §8.1 | 6、15 |
| MiniMax（通用） | MiniMax ④ 兼容端点 | ④ | 同 M3 ④ | — | — | — | 见 §14：停在 `*_tool_result` 报 `end_turn`；回灌自己的块 ❌ 400 → 纯文本续跑 | ⚠ | — | 响应侧实现了、请求侧没抄 | 【实测 2026-08】 | 05 §6 | 11 |

### 随平台变化的特性

- 自家国内站「随平台变化」= **同一 id 随面**：④ M3 默认关且真关（M2.7 照想），① 总在想且 `<think>` 内联；两面温度都不听。【实测 2026-09-28】坑 15、199、217
- **④ 默认值／关闭结局随平台**：自家 ④ M2.7 关不掉是**静默**；百炼 ④ M2.5 关不掉是**会响**（400 点名 `enable_thinking`）；`bogus` 自家 200 开思考、百炼 400（面级 ⚠）。【实测 2026-09-28】坑 217、219、220
- **对比 DeepSeek ④**：MiniMax ④ 默认不想、DeepSeek ④ 默认想——「省略 = 用默认」按平台 × 模型问。【实测 2026-09-28】
- **对比火山方舟 ④**（同 `switch` 拼法）：方舟关思考听温度（`0` 除外），MiniMax 不听。坑 200
- **对比 Anthropic 官方 ④**：MiniMax 无 `pause_turn`、拒收自己的 `*_tool_result`；官方 verbatim 续跑。坑 11

## 12 本地模型

### 家族固有特性（跨平台一致）

- 超窗**静默从头部丢弃**（先丢 system），200——只能事前 `contextSize` 估算拦截。【实测，日期未标】⚠ ⏳待复核 坑 5；01 §6
- 空 `Authorization: Bearer` 被拒 → 无 key 省略整个头；Windows 打包版 403 → 覆盖 `Origin`。【参考实现】02 §5、§6
- 严格交替模板上两条连续 user 报错（JSON cue 接在最后一条 user 末尾）。【参考实现】坑 211；06 §9.3

### 按平台 × 面

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 本地模型（任意） | Ollama `:11434` | ① 兼容 | — | — | — | — | — | — | `/api/show` 的 `model_info` 与 `parameters` 常差 30 倍，小的算数 | 超窗 🔇 从头部截断 200；空 Bearer 被拒 | 【实测，日期未标】⚠ ⏳待复核 | 01 §6；02 §5、§6；06 §6 | 5 |
| 本地模型（任意） | LM Studio ／ llama.cpp | ① 兼容 | — | — | — | 两条连续 user ❌（严格交替模板） | — | — | LM Studio `/models` `max_context_length`；llama.cpp `/props` | 超窗同上 🔇 | 【参考实现】【实测，日期未标】⚠ ⏳待复核 | 06 §6、§9.3；02 §5 | 5、211 |

### 随平台变化的特性

- Ollama 与 LM Studio／llama.cpp 差在**上限探测来源**与**模板严格度**；超窗静默截断是共性。坑 5、211

## 13 其他（Kimi、OpenRouter）

| 型号 | 平台·渠道 | 面 | 思考控制 | 取回／回传 | 结构化 | tool_choice | 服务端 | 多模态 | 上限／采样 | 静默要点 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Kimi | Kimi（Moonshot） | ① | — | — | `json_object` ✅ 不查 "json" | — | — | — | — | — | 【实测 2026-09-19】⚠（日期为推断） | 04 §2 | — |
| kimi-k2-thinking（托管） | 阿里百炼 · ④ `/apps/anthropic` | ④ | `disabled` 🔇 收下**照想**；默认值未测 —（文档：只有思考模式 📄） | — | — | — | — | — | — | 关不掉且不响（03 §4.1） | 【实测 2026-09-28，一次】 | 03 §3.5 | 217 |
| kimi-k2.6（托管） | 阿里百炼 · ④ `/apps/anthropic` | ④ | 不发与 `disabled` 都回**文本与签名都空**的 thinking 块；显式 `enabled` 才有文本（等不等于「默认关」待核实 OQ-074） | 空块要容忍 | — | — | — | — | — | 空块 ≠ 没想 ≠ 关不掉 | 【实测 2026-09-28，每条一次】 | 03 §3.5、§4.1 | 218 |
| 任意模型 | OpenRouter | ① | — | — | — | — | — | — | `/models` 带 `context_length`；`usage.cost`（未信任前不收） | SSE 体内 `data:{"error":…}` routinely；**指纹**（`gen-…`、`provider`、`native_finish_reason`）是经 OrcaRouter 看到的 ⚠ | 【文档；指纹经 OrcaRouter 实测 2026-09-26】 | 06 §1、§2、§6；20 §3 OpenRouter 节 | 185 |
| 任意模型 | 欠费中转 ／ OrcaRouter 余额为零 | 任意 | — | — | — | — | — | — | — | ❌ 402 `insufficient_user_quota` 对任何请求都回、先于模型名解析 | 【实测 2026-09-05】【实测 2026-09-03】 | 06 §5 | 112 |

## 14 服务端工具 × 平台 × 模型 专表

按工具查的入口；家族表的「服务端」格只留「见 §14」+ 记号摘要。报文、事件序列、计费细节在 05 §5、§6、§7 与 06 §1。

### web_search

| 工具 | 模型 | 平台·渠道 | 面 | 行为 | 计费 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| web_search（`web_search_20250305`） | Claude | Anthropic 官方（「8 次」平台与日期未标） | ④ | 📄 版本化条目 + `max_uses`；`server_tool_use` → `web_search_tool_result` → citations；`pause_turn` 续跑 | $10／1000 次 + 结果按输入 token；一题实测 8 次 | 【文档】+【实测，日期未标】⚠ ⏳待复核 | 05 §5、§6 | — |
| web_search（`web_search_20250305`） | Sonnet 5 | OrcaRouter · ④（Anthropic 原样） | ④ | ✅ 真搜，**不需 beta 头**；结果各带 `encrypted_content`；`usage.server_tool_use` 计数 | 一请求 $0.051；自动写缓存 2,834 | 【实测 2026-09-26】 | 05 §5；06 §1 | 179 |
| web_search（④）／ web_search_options（①） | claude-opus-4-6 ／ -5 | New API · Kiro 渠道 | ④／① | 单挂 🔀 **劫持**（首条 user 原文当搜索词、模板回复、模型没跑）；+函数工具流式 ✅ 真搜；+函数工具非流式 🔇 丢；① 转 ④ 后同样劫持 | `output_tokens` 固定 644／568／478（劫持指纹） | 【实测 2026-09-23】第十五个样本 | 05 §5 | 139 |
| web_search（④）／ web_search_options（①） | Claude | New API · CC 渠道 | ④／① | ④ ✅ 单挂真搜（要求搜才搜，改写句子不触发不劫持）；+函数工具流式 ✅；① ✅ 答案引了搜索结果 | `usage.server_tool_use.web_search_requests:1` | 【实测 2026-09-23】第十六个样本 | 05 §5 | — |
| web_search（④）／ web_search_options（①） | Claude | New API · anti 渠道 | ④／① | 🔇 全丢（凭记忆答「As of my latest information (July 2025)…」） | — | 【实测 2026-09-23】 | 05 §5 | — |
| web_search（④）／ web_search_options（①） | Claude | New API · AWSb 渠道（Bedrock 正向） | ④／① | ❌ 400 `Input tag 'web_search_20250305' … does not match`——整条请求失败 | — | 【实测 2026-09-23】 | 05 §5 | — |
| web_search | `gpt-6-luna` | OpenAI 官方 · 经 OrcaRouter ② 两条线路 | ② | ✅ 真搜：`web_search_call` 三事件齐全、`url_citation`；`action.sources` 需 `include`（触发分流到原样线路） | 原样线路 `cache_write_tokens` 4,388 | 【实测 2026-09-26】 | 05 §5；06 §1 | — |
| web_search | GPT sol | 经 New API 另一台（第十个样本） | ② | ✅ 一次搜索 45.7K 输入、112 s（比第十七个样本慢一个量级）；首事件可晚到 54 s；官方直连未测（OQ-027） | `tool_usage.web_search.num_requests` 按次 + 输入 token | 【实测，日期未标】⚠ ⏳待复核 | 05 §5 | 71 |
| web_search | `gpt-5.6-sol`／`gpt-5.6-terra` | New API · `[特价Pro]`／`[Plus]`／`[Pro]`（账号池）； `[Azure]`（网关） | ② | 账号池 ✅ 真搜（6–10 s）；`[Azure]` ❌🔇 **静默丢弃**：无 `web_search_call`，模型答搜不了 | 输入 8.5–14K | 【实测 2026-09-24】第十七个样本 | 05 §5 | 163 |
| web_search_options | `gpt-5.6-sol`；GPT-6 | New API · 四个上游全部；OrcaRouter · ① | ① | New API 🔇 静默忽略（①→② 翻译不转此字段 → GPT 联网只能走 ②）；OrcaRouter 🔇 200 但没有 `annotations` | — | 【实测 2026-09-24】【实测 2026-09-26】 | 05 §5；01 §9.5 | 164 |
| web_search（`open_page`／`find_in_page`） | Grok | xAI 官方 | ② | ✅ `action.type:"open_page"`／`"find_in_page"`，无 queries／sources | 一次 6,851 输入；`server_side_tool_usage_details` 按次 | 【实测，日期未标】⚠ ⏳待复核 | 05 §5 | 71 |
| web_search（① `enable_search:true` ／ ② `{type:"web_search"}`） | Qwen | 千问 DashScope | ①／② compat | ① ✅ 顶层字段、**无痕**、`qwen3-max` 不带策略 🔇 根本没搜；② ✅ | 按次价低三个数量级；无上限字段 | 【文档】+【实测 2026-09-17】第六个样本 | 05 §5 | 10 |
| web_search_image ／ image_search | Qwen | 千问 DashScope | ②／① compat | ② ✅ 可单独（`arguments`／`output` 都是 JSON 字符串，`"[]"` = 没搜到）；① ❌🔇 猜的字段静默忽略 | 按次价是搜索的 6–12 倍 | 【实测 2026-09-17】 | 05 §5 | — |
| web_search（② `{type:"web_search"}` ／ ④ `web_search_20250305` + `max_uses` ／ ①） | doubao-seed-2.1-turbo ／ 2.0-lite ／ 2.0-mini | 火山方舟 · 套餐；按量 | ②／④／① | ② ✅ 三款都跑（不写 `sources` 也记 `doubao`）；④ ✅ 真跑（`url` 为空串）；① **无**；按量 未知【未验】⚠ | ② `usage.tool_usage_details.web_search.doubao`；④ `usage.server_tool_use.web_search_requests` | 【实测 2026-09-18】 | 05 §5 | — |
| web_search（对话内 `tools[]` 项） | GLM | 智谱 BigModel 自家端点 | ① | ✅ 结果在顶层 `web_search[]`；默认意图识别不搜却照答 → 必须 `search_intent:false`；`count` 无效（`search_pro` ≈24k token） | 按 token 灌入 | 【实测 2026-09-19】 | 05 §5 | 100 |
| 平台搜索 | GLM | 千问百炼 ／ 火山方舟 | 视平台 | 由平台执行搜索（(平台, 协议族) 属性） | — | 【实测 2026-09-19】 | 05 §5 | — |
| googleSearch | Gemini 3.8 Flash | OrcaRouter · ③（Vertex 原样） | ③ | ✅ 真搜；末块 `groundingMetadata`；`uri` 是 `vertexaisearch` 跳转 ⚠；「搜没搜」只认 `webSearchQueries`；无 `max_uses`；与函数／`mode:"ANY"`／schema 同发 200 | 按查询条数约 $0.014／条（一题 6 条 $0.084）；旧：一次 $0.028 按请求 → 新：按条 | 【实测 2026-09-26】 | 05 §5；06 §1 | 178、190、192–194 |
| googleSearch | Gemini | Google AI Studio 官方 ／ 其他中转 | ③ | 📄「未实测、照发」；Gemini 2.x 与函数工具同发未测 ⚠ | — | 【未测】 | 05 §5 | — |
| googleSearch ／ urlContext ／ codeExecution（保留函数名） | Gemini | OrcaRouter · ① | ① | 📄 发无 `parameters` 的函数名，网关换成原生内置工具（网关约定） | — | 【文档 2026-09】 | 05 §5 | — |

### web_fetch · url_context · reader · web_extractor

| 工具 | 模型 | 平台·渠道 | 面 | 行为 | 计费 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| web_fetch（`web_fetch_20250910`） | Claude | New API · Kiro ／ CC ／ anti ／ AWSb 渠道 | ④ | Kiro 🔇 丢且**假装抓了** ／ CC ✅ 有 `server_tool_use` ／ anti 🔇 丢 ／ AWSb ❌ 400 整条 | — | 【实测 2026-09-23】 | 05 §5 | 144 |
| web_fetch（`web_fetch_20250910`） | Claude | Anthropic 官方 | ④ | 📄 版本化条目；`usage.server_tool_use.web_fetch_requests` | 📄 | 【文档】 | 05 §5 | — |
| web_extractor（`agent_max`） | Qwen | 千问 DashScope | ① compat | `qwen3.8-flash` ❌ 400；`qwen3-max`／`qwen3.5-plus` ✅；与 `tools` 同发 ❌ 400 → 带函数工具只发 `enable_search` | 抓回正文按输入 token | 【实测 2026-09-17】 | 05 §5 | 74 |
| web_extractor | Qwen | 千问 DashScope | ② compat | 仅当 `web_search` 同在 ✅；单独 → ❌ 200 后 `response.failed`；`urls[]`+`goal` → 按 goal 提炼正文 | 按输入 token | 【实测 2026-09-17】 | 05 §5 | 70 |
| urlContext | Gemini 3.8 Flash | OrcaRouter · ③（Vertex 原样） | ③ | ✅ 首块 `urlContextMetadata`；末块 `groundingChunks` 真实 uri、**无 `webSearchQueries`**（只读网页被当「搜过」= 坑 194） | 读回正文记 `toolUsePromptTokenCount` | 【实测 2026-09-26】 | 05 §5；06 §1 | 191、194 |
| `/reader`（应用执行独立端点） | 任意 | 智谱 BigModel | 私有 REST | `{url, return_format?}` → `reader_result`；`text` 有损；`retain_images` 无效；死链与主机不存在都 ❌ 500 `1234 网络错误` | 无 usage | 【实测 2026-09-19】 | 05 §5 | — |
| `/web_search`（应用执行独立端点） | 任意 | 智谱 BigModel | 私有 REST | `{search_query, search_engine, search_intent}` → `search_result[]`；`search_intent:true` 闲聊 `SEARCH_NONE`；`count` 无视；`search_domain_filter` 只 `search_pro` 系生效 | 无 usage、按次 | 【实测 2026-09-19】 | 05 §5 | — |

### code_interpreter · code_execution · codeExecution

| 工具 | 模型 | 平台·渠道 | 面 | 行为 | 计费 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| code_execution（`code_execution_20250825`） | Claude | New API · Kiro ／ CC ／ anti ／ AWSb 渠道 | ④ | Kiro 🔇 丢且**假装跑了**（乱造 `type` 同样 200 丢）／ CC 🔇 丢无块 ／ anti 🔇 丢 ／ AWSb ❌ 400 整条 | — | 【实测 2026-09-23】 | 05 §5 | 144 |
| code_interpreter ／ file_search ／ image_generation（OpenAI 自家） | GPT | OpenAI 官方 | ② | 📄 code_interpreter 要 `container`（不是 DashScope 那个工具，app 层对官方线过滤掉）；`{type:"file_search"}` 只放行官方线；`{type:"image_generation"}` → `image_generation_call`（base64） | — | 【文档】 | 05 §5 | — |
| code_interpreter ／ file_search | `gpt-5.6-sol` | New API · `[特价Pro]`／`[Plus]`／`[Pro]`／`[Azure]` | ② | ❌ 四档四种响：流式 `response.failed` ／ 502 ／ 400 `Unsupported tool type` ／ 500（file_search 同） | — | 【实测 2026-09-24】 | 05 §5；06 §2 | — |
| code_interpreter（`enable_code_interpreter:true`） | qwen3-max 等实测名单 | 千问 DashScope | ① compat | 按模型 id 放行；非流式 ❌ 400；带函数工具 ❌ 400；思考关闭照常跑；无痕；qwen-max／qwen3-max-preview 🔇 忽略；qwen3.8 全系 ❌ 400 | — | 【实测 2026-09-17】 | 05 §5 | 75、77 |
| code_interpreter（`tools:[{type:"code_interpreter"}]`） | qwen3-max、qwen3.5–3.8 系、部分开源版、deepseek-v4 | 千问 DashScope | ② compat | ✅ 按模型 id 放行；非流式／带函数工具可以；思考关闭 → ❌ 200 后 `response.failed`；Python 异常仍 `completed`；画图链接约 12 小时过期 | `usage.x_tools.code_interpreter.count`；限时免费；3.8-flash 一问约 1.1k token | 【实测 2026-09-17】 | 05 §5 | 76、78 |
| codeExecution | Gemini 3.8 Flash | OrcaRouter · ③（Vertex 原样） | ③ | ✅ `executableCode` → `codeExecutionResult` → 文本；代码 part 原样回灌 200；`inlineData` 图表随 parts 回传；代码 part 占上下文 | `toolUsePromptTokenCount`（在 prompt 之外） | 【实测 2026-09-26】 | 05 §5；06 §1 | 191、195 |


### image_generation

| 工具 | 模型 | 平台·渠道 | 面 | 行为 | 计费 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| image_generation | `gpt-5.6-sol`／`gpt-5.6-terra` | New API · `[特价Pro]`／`[Plus]`／`[Pro]`；`[Azure]` | ② | 账号池 ❌ 403 `Image generation is not enabled for this group`；`[Azure]` ✅ 出图 83 s（约 911K 字符 base64） | — | 【实测 2026-09-24】 | 05 §5 | — |

### 其他（工具按需加载、续跑、事件形状）

| 工具 | 模型 | 平台·渠道 | 面 | 行为 | 计费 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 工具按需加载（`tool_search`／`defer_loading`／`namespace`／`additional_tools`） | GPT-5.4+ | OpenAI 官方 | ② | 📄 原生；下一轮必须回传 `tool_search_output`／`additional_tools`，缺了 🔇 工具消失 | — | 【文档 2026-09】 | 05 §7 | 68 |
| tool_search ／ defer_loading | Grok | xAI 官方 | ② | ❌ 403（仅 alpha） | — | 【实测】 | 05 §7 | — |
| defer_loading ／ tool_search_tool_regex_* ／ _bm25_* | Claude 4.5+ | Anthropic 官方 | ④ | 📄 至少一个非延迟工具；与 `cache_control` 同现 400；`tool_result` 可回 `tool_reference` | — | 【文档】 | 05 §7 | — |
| defer_loading | Gemini | Google 官方 | ③ | ❌ 字段整个被拒（第三方报告 ⚠） | — | 【第三方报告】⚠ | 05 §7 | 69 |
| 服务端工具 verbatim 续跑 | MiniMax | MiniMax ④ 兼容 | ④ | 停在 `*_tool_result` 报 `end_turn`（无 `pause_turn`）；回灌自己的块 ❌ 400 → transcript 纯文本续跑（丢 citation） | 每次续跑全新计费 | 【实测 2026-08】 | 05 §6 | 11 |
| `pause_turn` verbatim 续跑 | Claude | Anthropic 官方 | ④ | 📄 `encrypted_content` 一字不改续跑（重建块 = 400）；`MAX_PAUSE_CONTINUATIONS = 4` | 每腿全新计费 | 【文档】【实现】 | 05 §6 | — |
| 结构化任务 ／ 辅助请求 | 任意 | 任意（DashScope 起） | ①② | 继承模型行的服务端工具 🔇 静默多花钱（代码解释器说明约 800 输入 token／请求）→ 每个非对话调用点显式覆盖为空 | 多花钱 | 【实测 2026-09-17】 | 04 §3；05 §5 | 77 |
