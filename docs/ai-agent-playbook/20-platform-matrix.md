# 20 · 平台表（平台 × 面 × 地址鉴权 × 目录 × 手脚 × 计费）

本表回答：「这个平台（含渠道／线路／套餐变体）有哪些面、地址与鉴权怎么写、目录可不可信、它会对请求做什么手脚、计费与 usage 怎么报」。主键 = 平台（渠道 / 线路 / 套餐变体各占一行，写作「New API · Kiro 渠道」「OrcaRouter · ② 默认线路」「火山方舟 · 套餐」「智谱 · Coding Plan」）。本表是结论表，报文细节与原因在 0x／1x 篇里，用「详见」列的指针链接过去；坑号指 `11-pitfalls.md`。原 `15-vendor-index.md`（厂商索引）已于 2026-09-28 并入本表：协议族的正文位置在 §0，每家厂商的正文位置在 §3 各节开头的「正文所在」行，模型级行为在 22。

图例：✅ 实测生效（发了有效果、回包有对应字段）；❌ 实测拒绝、**会响**（4xx/5xx 或流内 error，括号里写状态码或原文）；🔇 **静默失败**（收下 200 但不生效／被丢／被改写——最危险的一类）；🔀 被中转站改写或劫持（写清改成什么）；📄 只有文档口径，未实测；— 未测／来源没写；⚠ 来源标注为推断或含糊

「面」的编号：① OpenAI Chat Completions ／ ② OpenAI Responses ／ ③ Gemini generateContent ／ ④ Anthropic Messages ／ Ⓓ DashScope 私有 ／ 🖼 出图 ／ 🎬 视频 ／ 🎤 ASR。证据记法沿用原文：【实测 YYYY-MM-DD】【文档 YYYY-MM】【中继源码】【实现】；⏳待复核 = 日期距 2026-09-28 超过半年。

维护：新增 / 修正按 `30-knowledge-ingestion.md` 的流程；本表每行必须带证据与指针，没有证据的格子写 `—`。被推翻的旧结论在同一格里写「旧：… → 新：…（YYYY-MM-DD 推翻）」，不删。

## 目录

- [§0 按协议族找正文](#0-按协议族找正文)
- [§1 平台类型速览](#1-平台类型速览)
- [§2 主表](#2-主表)
- [§3 各平台展开](#3-各平台展开)
  - [3.1 官方直连](#31-官方直连) · [3.2 云部署变体](#32-云部署变体) · [3.3 聚合网关 OrcaRouter / OpenRouter](#33-聚合网关) · [3.4 自建中转 New API 类](#34-自建中转-new-api-类) · [3.5 本地运行时与 ASR 专营](#35-本地运行时与-asr-专营)
- [§4 本表尚未覆盖的平台](#4-本表尚未覆盖的平台)

---

## 0 按协议族找正文

原 15 篇「协议族（与厂商无关的底座）」表，2026-09-28 并入。先看协议族底座，再看 §3 的厂商节。

| 族 | 端点形状与差异 | 思考 | 结构化 | 工具 | 错误 / usage | 坑 |
| --- | --- | --- | --- | --- | --- | --- |
| ① Chat Completions | 02 §1、§3、§4、§5；视频片段 `video_url` 是厂商扩展、按平台放行（02 §1 表后） | 03 §2、§4–6 | 04 §2–4 | 05 §1–3 | 06 §1–2、§9（按 400 学降级） | A、B、AA、AB 组 |
| ② Responses | 02 §7（请求骨架 / 事件 / 回传；`instructions` 与 developer 消息按上游裁决）；01 §3.1 为什么独立成族 | 03 §7 | 04 §5 | 05 §1、§5「② Responses 族」、§7 | 06 §1（`attribution`）、§4.1 回显比对 | G、V 组 |
| ③ Gemini generateContent | 02 §1、§2.2、§3.2 | 03 §2–5（§2.1「关闭」只是 `LOW`） | 04 §2 | 05 §1–2 | 06 §2（三层错误） | A、B、Z 组 |
| ④ Anthropic Messages | 02 §1、§2.1、§3.2、§5 | 03 §2–5（§2.1「关闭」只是最低 effort；§3.4 开关型方言关思考时的温度） | 04 §2（JSON mode 只有 cue；schema 模式 `output_config.format`） | 05 §1–6（续跑循环） | 06 §1（三桶 usage） | A、B、Z 组 |

---

## 1 平台类型速览

| 类型 | 典型判据（怎么从回包认出它） | 通用对策 | 详见 |
| --- | --- | --- | --- |
| 官方直连（OpenAI／Anthropic／Gemini／xAI／DeepSeek／百炼／MiniMax／火山方舟／智谱） | 地址锁定或厂商 host；回包带官方专有字段：① `system_fingerprint`+`usage.*_details`、② `resp_…` id+`billing`／`tool_usage`、③ `responseId`／`modelVersion`、④ `msg_01…` id+长 base64 `signature`+`usage.cache_creation`；非法参数回官方原文 400；漏出上游响应头（`anthropic-ratelimit-*`、`openai-processing-ms`、`x-goog-*`） | official 契约：地址锁定、`/models` 缺失算错误、能力乐观；缺口会响，静默项是厂商自身特性（智谱 `json_schema` 无视、百炼 `enable_search` 无痕）按 §3 各节「正文所在」逐篇核 | 01 §3、§9.5 透传证据清单；§3 |
| 云部署变体（Azure OpenAI／Vertex／Bedrock） | 同 body 换鉴权与 URL；Vertex 回包带 `createTime`、`usageMetadata.trafficType:"ON_DEMAND"`、`responseId`／`modelVersion`／`thoughtSignature`；Bedrock 消息 id `msg_bdrk_`、任何 Anthropic 服务端工具 400、URL 图片 400；Azure `finish_reason:"content_filter"` 代替错误码 | 按官方族接，鉴权／URL 作 L2 数据；Bedrock Converse（camelCase、SigV4）是第五种 body，要么写第五个 adapter 要么明确不接；正向 ≠ 官方，服务端工具按平台点名；中转站里叫 `[Azure]` 的不等于 Azure OpenAI | 01 §2、§9.2 第 4 条；06 §2 |
| 聚合网关（OrcaRouter／OpenRouter） | 一把 key 四面同主机、模型 id 带厂商前缀、目录带 `supported_endpoint_types`；请求被重新序列化（非法枚举 200）；回包按面「原样」或「OpenRouter 形态」（`gen-…` id、`provider`、`native_finish_reason`、`usage.cost`／`is_byok`、`reasoning_details[]`）；402 `insufficient_user_quota` 先于模型解析；只有自有响应头 `x-orca-*` | 按面用透传证据判后端，原样的面记官方事实、「发 X 会不会 400」只记网关注记；花费字段按面各读各的，③④ 带 `X-OrcaRouter-Include-Cost: true`；不调计数端点；错误分类靠 HTTP 状态 + 关键字不靠 `error.type`；不按 `supported_endpoint_types` 开线路 | 01 §9.5；06 §1、§2、§5 |
| 自建中转（New API 类，按渠道） | 无可识别 host；渠道／档位写在模型 id 前缀 `[kiro]` `[CC量]` `[Plus]`；503 `No available channel for model … under group …`；错误信封 `type:"<nil>"`、路径 `***`；`usage.billing_usage.source`、`usage.attribution`；④ 发 `output_config.effort:"bogus"`（② 发 `reasoning.effort:"bogus"`）200 = 反代、400 官方原文 = 正向 | 能力主键是（平台, 面, 渠道, 模型）；同台至少测两个渠道分「转换层／渠道」；② 恒发 `instructions` + 终止事件回显比对；图片一律内联 base64；兼容 ④ 线路默认不发 `cache_control`；目录 `supported_endpoint_types` 不开线路；站主缩写不进代码、上游由作者声明 | 01 §9.2；06 §4.1、§5、§8 |
| 本地运行时（Ollama／LM Studio／llama.cpp） | URL 指向本机（`:11434`）；空 Bearer 被拒；超窗返回 200 不报错；`/api/show`／`/props`／`/models.max_context_length` 有免费元数据 | 无 key 时整个 `Authorization` 头省略；发送前 `contextSize` 估算拦截（`ContextSizeError`）；`num_ctx` 与 `model_info` 两键取小的；JSON cue 接在最后一条 user 末尾不另起消息 | 01 §6；02 §5–6；06 §6、§9.3 |

通用闸门（所有类型）：欠费中转对**任何**真实请求回完整协议形状的 402 JSON、先于模型名解析——探测任一步都报不可达，不报鉴权失败【实测 2026-09-05】（坑 112；06 §5）。

---

## 2 主表

列说明：面（逐个列出可用面，不可用的写 ❌ 并给状态码）｜base 与鉴权｜目录（`/models` 形态、可信度）｜对请求的手脚（重序列化 / 注入 / 改写 / 丢字段）｜计费与 usage 报法｜证据｜详见｜坑。每格只写结论，数值、原文与正文篇指针在「详见」列指向的 §3 节（开头「正文所在」行）。

| 平台／变体 | 面 | base 与鉴权 | 目录 | 对请求的手脚 | 计费与 usage 报法 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OpenAI 官方 | ① ✅；② ✅（o1-pro／codex 系／computer-use 只有 ②）；🖼 📄；🎬 📄；🎤 📄；③④Ⓓ — | `https://api.openai.com/v1`，Bearer（无 key 整个头省略）；① 未知顶层字段 400、② 忽略 | `GET /models` → `{data:[{id}]}`，② 同 | 无中转改写；模型级见 22 §3 | ① `prompt_tokens_details.cached_tokens`；② `input_tokens_details.*`；`tool_usage.web_search.num_requests` 按次 | 【文档】；【实测 2026-09 经中转】；web_search 实测日期未标 ⏳待复核 | §3.1 OpenAI 节；22 §3 | 14、64、68、71、109、116 |
| Anthropic 官方 | ④ ✅；其余 — | 地址锁定，根地址不带 `/v1`；`x-api-key` + `anthropic-version`；`max_tokens` 必填无服务端默认；未知顶层字段 400（`extraBody` 故意不 spread） | `GET /models` → `{data:[{id, display_name}]}`；per-model 端点给 `max_input_tokens`／`max_tokens` | 无改写；模型级见 22 §4 | 三桶不重叠相加（06 §1）；`thinking_tokens`；`web_search` 按次 $10/1000 | 【文档】；Claude 5 经 OrcaRouter【实测 2026-09-26】；思考回退【实测 2026-09-28】 | §3.1 Anthropic 节；22 §4 | 1、4、16、17、18、179–184 |
| Google Gemini 官方（AI Studio） | ③ ✅（同一 wire 也出图）；🖼 Imagen `:predict` 📄；🎬 Veo 📄；其余 — | 地址锁定；`x-goog-api-key`；Interactions 与 generateContent 同构 | `GET /models` → `{models:[{name:"models/x", displayName}]}`；per-model 给 token 上限（探测可省） | 图片字段两种拼写都收；直连 400 原文带完整字段路径；模型级见 22 §5 | `promptTokenCount`+`candidatesTokenCount`+`thoughtsTokenCount`+`toolUsePromptTokenCount`；流式只末块带计数 | 【文档】；AI Studio 直连【实测 2026-09-28，本库第一条】；3.8 Flash 其余事实经 OrcaRouter（Vertex）【实测 2026-09-26】 | §3.1 Gemini 节；22 §5 | 2、7、18、69、191、195、222 |
| xAI (Grok) 官方 | ② ✅ 推荐；① 📄 Deprecated；④ 📄 完全弃用；🖼 ✅；🎬 ✅；③Ⓓ🎤 — | `https://api.x.ai/v1`，Bearer；预设 `apiStandard: "openai_responses_compat"` | ⚠ `/models` 形态原文未说 | 图片 <512 像素 ❌；① `video_url` ❌ 400；模型级见 22 §6 | ② 流 `response.completed` 带 usage；`server_side_tool_usage_details` 按次；🖼 `cost_in_usd_ticks` 报实扣；🎬 按秒 | 【实测 2026-09】；出图／视频计费【实测 2026-09-22】；视频输入【实测 2026-09-28】；【文档】 | §3.1 xAI 节；22 §6 | 66、67、123–129、206 |
| DeepSeek 官方 | ① ✅；④ ✅；其余 — | ① —（来源未写）；④ `x-api-key` + `anthropic-version` | ④ 文档：`claude-*` 名映射到自家两款，**不认识的模型名也 🔇 映射不报错** 📄 | ④ `bogus` ❌ 422 点名枚举；① `video_url` ❌ 422；模型级见 22 §7 | 顶层 `prompt_cache_hit_tokens`／`_miss_tokens`（无标准拼写），`prompt_tokens` 已含命中；④ 不发 `thinking` 输入 11 → 90 | 【文档 2026-08】；④ 面与视频输入【实测 2026-09-28，每条一次】；缓存字段【Joycai 2026-09-14 修复】 | §3.1 DeepSeek 节；22 §7 | 206、217、221 |
| 阿里百炼（千问 DashScope） | ① ✅；Ⓓ 📄；④ ✅（旧：📄 模型子集 → 新：2026-09-28 实测千问四款 + 托管第三方五款）；② ✅；🖼 ✅；🎬 仅异步 ✅；🎤 ✅ | 一把 key 六条 wire，Bearer；④ `x-api-key`、新旧 host 等价；只认路径不认 host | ⚠ 原文未说；④ 未知模型 ❌ 400 | ④ 翻译层透传上游拒绝；① `enable_search` 🔇 无痕；模型级见 22 §8 | 标准 ① usage；`usage.x_tools.code_interpreter.count`；搜索按次；签名 URL 24h／12h 过期 | 【实测 2026-09-28 ④ 面（每条一次）与视频输入】【实测 2026-09-19 出图】【实测 2026-09-17 服务端工具】【实测 2026-09-13 ASR】【实测 2026-08-29 视频】【文档 2026-09】 | §3.1 百炼节；22 §8 | 9、10、13、56–59、70、74–78、101–104、115–121、206–208、217–219 |
| MiniMax（国内站） | ① ✅ `/v1`、④ ✅ `/anthropic`（同 host，模型 id 完全一致，分两行）；🖼 `image-01` ✅；🎬 `/v2/video_generation` ✅；其余 — | 视频面剥 `/v1` 或 `/anthropic/v1` → 拼 `/v2/…`；鉴权 — | ⚠；④ 未知模型名 🔇 静默改映射 | 错误在 HTTP 200 体内 `base_resp.status_code`；④ 什么都收（唯一 400 `top_p:1.5`）；模型级见 22 §11 | ⚠；续跑每腿全新计费；🖼 `success_count` 是字符串 `"0"` 也算「成功」 | 【实测 2026-09-28 ④ 温度、④ 关闭档与未知值（M3／M2.7，每条一次）、① 回传（M3）】；【实测 2026-08 ①／④ 续跑】；【实测 2026-08-29 视频】；【文档 2026-08】 | §3.1 MiniMax 节；22 §11 | 6、11、90、91、113、199、201、202、217、220、221 |
| 火山方舟 · 按量付费 base | ① 📄（对话面未实测，能力记 `unknown`）；②④ ⚠ 未验；🖼 ✅；Files API ⚠；🎬 Seedance 需按量 key（body 未覆盖） | `https://ark.cn-beijing.volces.com/api/v3`，Bearer；按量 key；套餐 key 打此 base ❌ 401；无 ④ 面文档 📄 | 静态目录带日期 id；⚠ `/models` 形态未说 | 对话面未测；🖼 手脚见 §3.1 | 🖼 `usage.input_images`、首张免费、失败免费；`output_tokens` = 像素/256 只是参考不是 token 计费 | 【文档】；出图实测均在套餐 base【实测 2026-09-18】【实测 2026-09-23】，按量 key 未实测 | §3.1 火山方舟按量节 | 79–85、87、88、130–132 |
| 火山方舟 · 订阅套餐 base（Agent／Coding Plan） | ①②④ ✅（三面路径见 §3.1）；🖼 同 base ✅；Files API ❌ 404；🎬 Seedance ❌ 404 | `https://ark.cn-beijing.volces.com/api/plan/v3`，Bearer；④ `x-api-key` 也收；`/api/coding` 前缀关系**未核实**（31 OQ-071） | ① `/models` ❌ 404 非 JSON；④ `/v1/models` ❌ 401；退回静态目录并再发最小补全定论 | 套餐按模型裁剪且挑拼写（❌ 404 `UnsupportedModel`）；④ 温度 `0` 🔇 当没发、签名不校验 🔇；① 2.1 `encrypted_content` 不回传；模型级见 22 §10 | `max_tokens` 上限按模型 ❌ 400；② `usage.tool_usage_details.web_search.doubao`；④ `server_tool_use.web_search_requests` | 【实测 2026-09-18】39 条全过；Files API／flash／透明背景【实测 2026-09-23】；④ 温度与视频输入【实测 2026-09-28】 | §3.1 火山方舟套餐节；22 §10 | 80、81、114、130–137、198、201、206、208 |
| 智谱 BigModel · 按量标准端点 | ① ✅；Ⓓ 独立 `/web_search`、`/reader` REST ✅；🎤 `glm-asr`【实现】；②③④ —（走 Coding Plan 行）；🖼🎬 — | `https://open.bigmodel.cn/api/paas/v4`，Bearer；错 key ❌ 401 | `/models` OpenAI 形 `{object:"list", data:[{id,…}]}`，连接测试直接可用 ✅ | `json_schema` 🔇 无视；`tool_choice` 🔇 不强制；不搜却说搜了 🔇；模型级见 22 §9 | `max_tokens` 上界 ❌ 400 生成前拒不计费（按模型）；对话内 `web_search` 结果按 token 灌入；独立端点无 usage、按次 | 【实测 2026-09-19】11 个对话模型 | §3.1 智谱按量节；22 §9 | 94–100、206 |
| 智谱 BigModel · Coding Plan 编程端点 | ① `/api/coding/paas/v4` ✅；④ `/api/anthropic` ✅；② `/api/v1` ✅（①② 只测到「按量 key 200」，完整实测未覆盖 ⚠） | 同 host、同一把按量 key 全通；**路径决定扣余额还是扣套餐** | ② `/api/v1/models` Codex CLI 目录形只列 3 个；④ `/v1/models` Anthropic 形 | 选错路径不失败只换一笔钱；套餐条款只许「指定工具」→ 必须分行；④ 思考默认值按模型；模型级见 22 §9 | 扣套餐；④ `usage` 带 `server_tool_use.web_search_requests` | 【实测 2026-09-19 + 文档】；④ 思考【实测 2026-09-28，每条一次】 | §3.1 智谱 Coding Plan 节；22 §9；§4 | 217 |
| Kimi（Moonshot） | ① ✅（仅一条实测）；其余 — | — | — | `json_object` 不查 "json" 字样 | — | 【实测 2026-09-19】（与智谱同批；日期按同批推断 ⚠） | 04 §2；§4；31 篇 §3 | — |
| Azure OpenAI（部署变体） | ①② 部署变体 📄；`api-version` 细节未覆盖 | `api-key` 头；URL `/openai/deployments/{d}/...?api-version=`，模型标识不同——另一族不是 compat 选项 | — | `finish_reason: "content_filter"` 代替错误码，必须 throw；**中转站里叫 `[Azure]` 的 ≠ Azure OpenAI** | ⚠ | 【文档】 | §3.2 Azure 节 | 7、159（辨识） |
| Vertex AI（Gemini／Claude 部署变体） | ③ ✅（经 OrcaRouter ③ 线路实测，回包 Vertex 原样）；Claude 部署变体 📄 | 经 OrcaRouter 时 Bearer；直连鉴权 — | — | 回包指纹见 §1；枚举由上游校验、非法档位 ❌ 400；缺签名 HTTP ❌ 400 | `trafficType`；`googleSearch` 按查询条数约 $0.014/条；`toolUsePromptTokenCount` 在 prompt 之外 | 【实测 2026-09-26 经 OrcaRouter】；【文档】 | §3.2 Vertex 节 | 170–173、178、190 |
| AWS Bedrock（Claude 正向部署） | ④ ✅（经 New API AWSb 渠道实测）；Bedrock Converse 第五种 body 未接；Anthropic 服务端工具 ❌ 400 | 经 New API 时同 New API；直连 SigV4 — | — | 消息 id `msg_bdrk_`；参数校验与官方同文 ❌ 400；URL 图片 ❌ 400；缺口会响不静默 | `cache_control` ✅ 真缓存；「Say OK.」10 token | 【实测 2026-09-23】经 New API AWSb 渠道 | §3.2 Bedrock 节 | —（渠道层坑见 AWSb 行） |
| OrcaRouter（网关共性） | ①②③④ 四面同一主机（各线路见下五行）；PDF 四面都读；🖼🎬🎤 — | `api.orcarouter.ai`，一把 key `Authorization: Bearer`；模型 id 带厂商前缀（`anthropic/claude-sonnet-5`） | `GET /v1/models` 按鉴权头回 OpenAI／Anthropic／Gemini 形（带 `supported_endpoint_types`、`context_length`），是建议不是限制 | 四面请求都被重新序列化（非法枚举常 200）；错误信封改写成 OpenAI 形；只有 `x-orca-*` 响应头；余额零 ❌ 402 先于模型解析 | 唯一声明「报的数 = 实扣」的平台；与 `GET /v1/generation?id=` 对账相等或差不到一个单位；花费字段按面不同（见各线路） | 【实测 2026-09-03】【实测 2026-09-26】【文档】 | §3.3 OrcaRouter 节 | 166、174–177、185、186、196 |
| OrcaRouter · ① 线路 | ① ✅（任何模型都能调的翻译层）；`video_url`：Gemini 🔇 200 静默丢、GPT ❌ 400 | `/v1/chat/completions`，Bearer | 同共性 | 🔀 回包 OpenRouter 形态；GPT 上游再走 Responses；无 parameters 的 `googleSearch` 等函数名 🔀 换成原生工具 | 末块 `usage.cost`、`is_byok`、`cost_details.upstream_inference_cost`；不需请求头 | 【文档 + 实测 2026-09-03／09-26】；视频输入【实测 2026-09-28】 | §3.3 ① 线路节 | 185、205、206 |
| OrcaRouter · ② 默认线路 | ② ✅ | `/v1/responses`，Bearer | `gpt-6-luna`／`-sol` 只声明 `openai`，打 `/v1/responses` 照样 200 | 🔀 OpenRouter 形态（伪造 item id、`store` 恒 `false`）；`minimal` 🔀 改 `low`；乱写 effort 回网关自己的错误 | `response.completed.response.usage.cost`（不需请求头） | 【实测 2026-09-26】 | §3.3 ② 默认线路节 | 175 |
| OrcaRouter · ② 原样线路 | ② ✅（`store:true` 或 `include` 含 `web_search_call.action.sources` 触发） | 同上 | 同上 | OpenAI 原样回包（默认 `store:true`）；`web_search`／`include reasoning`／`text.verbosity` 不触发分流 | ❌ 没有任何花费字段（请求头对 ② 无效）；`usage.input_tokens_details.cache_write_tokens` | 【实测 2026-09-26】 | §3.3 ② 原样线路节 | 175、186 |
| OrcaRouter · ③ 线路（Vertex） | ③ ✅（Vertex AI，不是 AI Studio）；`:countTokens` 🔀 被当 `generateContent` 执行并计费 | `/v1beta/models/{model}:generateContent`／`:streamGenerateContent`，Bearer；id 里斜杠原样进路径不编码 | `GET /v1beta/models` Gemini 形 | 回包 Vertex 原样；请求重序列化但枚举由上游校验；`thinkingBudget:0` 🔇 照想；错误 `***` 遮路径 | 带请求头才有末块 `usageMetadata.costUsd`，与账单相等；`googleSearch` 约 $0.014/条 | 【实测 2026-09-26】；思考回退／视频【实测 2026-09-28】 | §3.3 ③ 线路节 | 170–173、176–178、186、190–195、197、203、204 |
| OrcaRouter · ④ 线路 | ④ ✅（Anthropic 原样）；`/v1/messages/count_tokens` ❌ 301 | `/v1/messages`，Bearer | `x-api-key` 打 `/v1/models` 回 Anthropic 形（无 `supported_endpoint_types`） | 回包 Anthropic 原样；请求重序列化：未知字段、`bogus` 枚举全 200（官方 400）；错误信封 `type:"<nil>"` | 流式带请求头才有 `message_delta.usage.cost_usd`，与账单相等；`web_search_20250305` 自动写缓存 | 【实测 2026-09-26】；思考回退【实测 2026-09-28】；402【实测 2026-09-03】 | §3.3 ④ 线路节；22 §4 | 4、174、176、177、179、182、186、197、203、204 |
| OpenRouter | ① ✅ 📄；其余 — | host `openrouter.ai`；鉴权 — | `/models` 带 `context_length` | SSE 体内 `data:{"error":...}` routinely；「OpenRouter 形态」指纹是在 OrcaRouter 上看到的，非对 OpenRouter 本身的实测 ⚠ | ① 回 `usage.cost`／`is_byok`／`cost_details`（平台未受信前不收） | 【文档】；指纹经 OrcaRouter【实测 2026-09-26】 | §3.3 OpenRouter 节 | 6、185 |
| New API 类中转站（平台层／转换层，总览） | ①②③④ 形状都有（按渠道）；Claude ① 是 ①→④ 转换、GPT ① 是 ①→② 转换；`/mj/*` Midjourney | 自建、无可识别 host；Bearer；渠道／档位写在模型 id 前缀（`[Plus]gpt-5.6-terra`；旧：不加剥前缀规则 → 新：中转平台上按前缀表最长匹配去作者前缀、否则去开头 `[…]`、再去 `vendor/`，规范化 id 只用来查目录，平台格／上游格仍按原始 id，2026-09-27 实现，01 §9.2） | `supported_endpoint_types` 不可信；没线路／假模型同一 ❌ 503 `No available channel for model … under group …`；欠费 ❌ 402 | 转换层（四渠道一致）：Claude ① `response_format` 🔇 丢、`reasoning_effort` 极值 = 不想；GPT ① 翻成 ②、`web_search_options` 🔇；③ 只认 camelCase；URL 图片 ❌ 500 | 中转站估算 usage：总数可用、缓存分段不可信；`usage.attribution.request_fields.instructions.input_tokens` 读注入量 | 【实测 2026-09-23】【实测 2026-09-24】【中继源码】 | §3.4 New API 节；22 §3、§4 | 2、8、15、61–65、105–112、140、142、147、150、152–158、164、166–169、183 |
| New API · Kiro 渠道（Claude） | ① ✅（翻成 Messages）；④ ✅；②③ ❌ 500 `convert_request_failed`；`count_tokens` ❌ 404；`/v1/files` ❌ 401 | 同一台 New API；④ `x-api-key` 与 Bearer 都收；前缀 `[kiro]`… | `supported_endpoint_types` 一律 `null`；不存在模型 ❌ 503 `model_not_found` | 反代（`effort:"bogus"` 200）：`max_tokens`、两族 JSON 旋钮 🔇；思考只 low 有效；单挂 `web_search` 🔀 整条劫持；PDF／URL 图片 🔇 丢 | `usage.billing_usage.source:"claude_messages"`；`cache_control` 只写不读、缓存段是拼的 | 【实测 2026-09-23】（curl ≈200 次 + `live.relay-kiro.test.ts` 31 条全过） | §3.4 Kiro 节；22 §4 | 65、138–147 |
| New API · CC 渠道（Claude） | ①④ ✅ | 同一台、同一把 key；前缀 `[CC量]` | 同 Kiro（渠道写在 id） | 反代（一律 200）：思考 ✅ 但 opus-5 thinking 文本恒空；PDF ✅、URL 图片 🔇 丢；`web_search`／`web_fetch` ✅ | `cache_control` ✅ 真缓存；「Say OK.」9–10 token | 【实测 2026-09-23】curl（无 live adapter 文件） | §3.4 CC 节；22 §4 | 147、149、150、152、153 |
| New API · anti 渠道（Claude） | ①④ ✅ | 同上；前缀 `[anti量]` | 同上 | 反代：不思考；`max_tokens` ④ ✅、① 🔇；强制 0/0；两族 JSON 旋钮 🔇；PDF 🔇 丢；URL 图片 ❌ 500；服务端工具 🔇 全丢 | 没有任何缓存字段、两次都全价；「Say OK.」39 token（约 30 token 注入） | 【实测 2026-09-23】curl | §3.4 anti 节；22 §4 | 147、148、150、151、152 |
| New API · AWSb 渠道（Claude，Bedrock 正向） | ①④ ✅ | 同上；前缀 `[正向AWSb量]`；消息 id `msg_bdrk_` | 同上；`[AWSb]gpt-5.6-sol` 目录有但 ❌ 503 `No available channel` | 正向：`effort:"bogus"` ❌ 400 官方原文；服务端工具 ❌ 400 整条请求；URL 图片 ❌ 400；① `response_format` 仍 🔇 | `cache_control` ✅ 真缓存；「Say OK.」10 token | 【实测 2026-09-23】curl；GPT 503【实测 2026-09-24】 | §3.4 AWSb 节；§3.2 Bedrock 节；22 §4 | 147、150、152、166 |
| New API · 官key 渠道 | ⚠（①④ 两个端点当天全 ❌ 502 `Upstream request failed`，没测到）；GPT-5.6-sol ❌ 503 `No available channel` | 同上；前缀 `[官key量]`／`[官key]` | 同上；目录里有 ≠ 有线路 | ⚠ 没测到；画像 official 无格子，选它只表示「已分类」 | ⚠ | 【实测 2026-09-23】502；【实测 2026-09-24】503 | 01 §9.2「五个渠道」、「上游做成作者声明的数据」第 2 条；06 §5；§3.4 官key 节 | 166 |
| New API · `[特价Pro]` 档（GPT，ChatGPT 账号池／Codex） | ② ✅；① ✅（翻成 ②）；④ ❌ 明文拒；`image_generation` ❌ 403；`code_interpreter`／`file_search` ❌；`web_search` ✅ | 同一台同一把 key；画像 codex | 声明 `supported_endpoint_types` 含 `anthropic`／`gemini` 却不许——不可信 | 不带 `instructions` 注入时有时无、① 带 system 仍注入；`none` 🔀 `medium`；温度 🔀 `1.0`；`max_output_tokens` 🔇 | `usage.attribution.request_fields.instructions.input_tokens` 是注入读数；前缀缓存 `cached_tokens` 9,984 | 【实测 2026-09-24】（curl ≈560 次 + `live.openai-responses.test.ts` 45 条过 41） | §3.4 `[特价Pro]` 节；22 §3 | 61、62、65、161、162、164–167、169 |
| New API · `[Plus]` 档（GPT，账号池） | ②① ✅；④ ❌ 同上；`image_generation` ❌ 403；`code_interpreter`／`file_search` ❌ 502；`web_search` ✅ | 同上；画像 codex | 不可信（同上） | 不带 `instructions` 注入、① 带 system 仍注入；乱写 effort ❌ 502；`none` 🔀 `medium`；温度 🔀 `1.0`；`max_output_tokens` 🔇 | 同 `[特价Pro]` | 【实测 2026-09-24】 | §3.4 `[Plus]` 节；22 §3 | 61、62、65、161、162、164、165、169 |
| New API · `[Pro]` 档（GPT，账号池） | ②① ✅；④ ❌ 同上；`image_generation` ❌ 403；`code_interpreter`／`file_search` ❌ 400 `Unsupported tool type`；`web_search` ✅ | 同上；画像 codex | 不可信 | `text.format` json_schema 🔇 整个丢（旧：第八个样本「显式 `strict:true` 才丢」→ 新：不论写不写都丢，2026-09-24 扩展）；① `response_format` 🔇 丢；乱写 effort ❌ 400 官方原文 | 同 `[特价Pro]` | 【实测 2026-09-24】；旧【实测 2026-09 第八个样本】 | §3.4 `[Pro]` 节；22 §3 | 63、160、161、162、164、165 |
| New API · `[Azure]` 档（GPT，带护栏的网关，非 Azure OpenAI） | ②① ✅；④ ❌；sol ❌ 503 无线路（用 terra）；`image_generation` ✅；`code_interpreter`／`file_search` ❌ 500；`web_search` 🔇 静默丢 | 同上；画像 azure（正向） | 不可信；无 `attribution` 字段 | 带 `instructions`（含空串）🔀 追加护栏并可能拒创作（200 无 `refusal`）；`none` 🔀 `medium`（① 真关）；温度／`store:true`／① 具名 `tool_choice` ❌ 500 | 每请求 +1.2K 输入（多半命中缓存）；① 截断不精确 | 【实测 2026-09-24】 | §3.4 `[Azure]` 节；22 §3 | 159、161、162、163、164、166、167、169 |
| New API 中转站（另一台）· `[Pro]`／`[Plus]` 档（GPT-5.4／5.5／5.6，第八、第十个样本） | ① ✅、② ✅（① 翻成 ②） | ⚠ base 未给（自建）；Bearer；档位前缀 id | 档位前缀使按 id 前缀查表认不出——旧：不加剥前缀规则，让作者手动声明 → 新：中转平台上规范化 id 后查目录（2026-09-27，01 §9.2；坑 223） | 不发 `instructions` 注入 4.4K–9K（Chat 面同样）；sol `max` 🔀 `none`（另一台未复现）；terra `none` 🔀 `medium`；温度 🔀 `1.0`；一档多上游 | 注入直接体现为输入 token 4.4K–9K | 【实测 2026-09】+【中继源码】 | §3.4 另一台节；22 §3 | 61–65、107、108 |
| 未具名中转（Claude 后端，Joycai 线上流量） | ① | — | — | `arguments` 背靠背拼接多对象；调用 id 空串同批共用 → 下一轮重复 `tool_call_id` ❌ 400；空参数执行不报错 🔇 | — | 【实测 2026-08-08】【实测 2026-08】 | §3.4 未具名中转节；02 §3.2；05 §3 | 105、106 |
| Midjourney（midjourney-proxy／New API `/mj/*`） | 🖼 独立异步出图协议（`/mj/submit`）；其余 — | ⚠ | ⚠ | ⚠ | ⚠ | 【实现，日期未标】 ⏳待复核 | §3.4 Midjourney 节 | — |
| Ollama（本地） | ① 兼容 ✅；`/api/show` 元数据；其余 — | 本机 `:11434`；无 key 时整个 `Authorization` 头省略；Windows 打包版 ❌ 403 | ① 形 `/models`；`/api/show` 两键取小的 | 🔇 超窗从头部静默丢弃（先丢 system）返回 200；`num_ctx` 静默截断；JSON cue 另起 user 消息报 chat 模板错误 | ⚠（`stream_options.include_usage` 可能没实现，usage 全 0 当「没报」） | 【实测，日期未标】 ⏳待复核 | §3.5 Ollama 节 | 5、8、211 |
| LM Studio／llama.cpp（本地） | ① 兼容 ✅；其余 — | 本机；空 Bearer 被拒（同 Ollama） | LM Studio `/models` 带 `max_context_length`；llama.cpp `/props`；`max_model_len` 置 high | 两条连续 user 消息在严格交替 chat 模板上 ❌ 报错；超窗静默截断同本地栈 🔇 | ⚠ | 【实测，日期未标】 ⏳待复核 | §3.5 LM Studio 节 | 5、211 |
| Groq／硅基流动（仅 ASR） | 🎤 ⓐ OpenAI 兼容转写【实现】；chat 面未覆盖 | 地址在 16 §3；硅基流动 SenseVoice 语种 | — | ⚠ | ⚠ | 【实现】 | 16 §3；§3.5 | — |
| 火山引擎 openspeech（豆包录音识别极速版，与方舟 base 无关） | 🎤 私有 HTTP `openspeech.bytedance.com` | 独立鉴权头 `X-Api-App-Key`／`X-Api-Access-Key`／`X-Api-Resource-Id` | — | 🔇 成败在响应头 `X-Api-Status-Code == 20000000`，HTTP 恒 200，缺头按失败 | ⚠ | 【实现 2026-09，原 pyVideoTrans】 | 16 §10.2；23 §3.2；§3.5 | 122 |
| ASR 专营：Deepgram、ElevenLabs、CAMB AI、Gladia、小米 MiMo、302.AI | 🎤 各自 SDK／私有协议 | — | — | ⚠ | ⚠ | 【实现 2026-09，原 pyVideoTrans】 | 16 §10.2；§3.5 | — |

---

## 3 各平台展开

每节开头的「**正文所在**」行是原 `15-vendor-index.md` 厂商索引的「事实所在」列（2026-09-28 并入）：审查或接入某一家时，把列出的小节全部读一遍——一家的事实通常散在五六篇里，只读一篇就会漏掉别的维度。行末的证据是那几节里标注的最近来源，没标日期的按「文档口径、日期未知」对待。线路／渠道子节（OrcaRouter 各线路、New API 各渠道与各档等）沿用父节的「正文所在」行。本节只写**平台层面**的事实（地址／鉴权／目录／后端指纹／对请求的手脚／计费报法／错误信封／探测结论）；某个模型在该平台上的思考／结构化／工具／服务端工具／多模态行为，统一在 22 对应家族节的「按平台 × 面」行里，这里只留一句指针。

### 3.1 官方直连

### OpenAI 官方

- **正文所在**：01 §3.1、§8.1；02 §7；03 §7；04 §5；05 §5、§7；06 §1；13 §2、§4.2「images-api」；14 §2；16 §3、§10.2；坑 109。经中转站的 GPT-5.6 按上游对照：见 §3.4 New API 节「正文所在」（坑 159–169）。GPT-6 经 OrcaRouter（§3.3 各线路节）：01 §9.5、03 §7.1、04 §2、05 §5、06 §1。模型级行为：22 §3。【实测 2026-09 经中转 + 文档；上游对照 2026-09-24；GPT-6 经 OrcaRouter 2026-09-26】
- 面与路径：① `/v1/chat/completions`；② `/v1/responses`（adapter 自己拼）；o1-pro／codex 系／computer-use 只有 ②，走 ① 会失败（截至 2026-08）【文档 2026-08】；🖼 Images API；🎬 Sora；🎤 `/audio/transcriptions`（whisper／gpt-4o-transcribe／diarize；`gpt-4o-*-transcribe` 无 `segments`，坑 116）。
- 分辨后端指纹：见 §1 官方直连行；另 ② `reasoning.encrypted_content` 可回灌、`output_text` 带 `annotations`。
- 模型级行为（结构化、思考、工具按需加载、服务端工具、`text.verbosity`）见 22 §3 对应行。
- 计费：一次搜索回答 45.7K 输入、112 s，首个事件可晚到 54 s（流看门狗首块等待要高于此）——经 New API 第十个样本测得，官方直连未测（OQ-027、OQ-053）。
- 是否收 ① `video_url` 未量（§4）。

### Anthropic 官方

- **正文所在**：01 §2；02 §1、§2.1、§5；03 §3、§5；05 §5–7；06 §1；坑 1。Claude 5 系经 OrcaRouter 的原样回包（§3.3 ④ 线路节）：03 §2、§2.1、§3、§4、§5；04 §2；05 §3、§5；06 §1；02 §1 表后；坑 4、179、180–184、197、203、204。模型级行为：22 §4。【文档；Claude 5 经 OrcaRouter 实测 2026-09-26；思考回退 2026-09-28】
- 面：④ `/v1/messages`；base 约定与 OpenAI 相反（根地址 vs 自带版本段，坑 16）；鉴权 `x-api-key` 与 `Bearer` 两套约定、各有网关只认一种（坑 17）——compat 端点 default/bearer/both 三模式，官方只 default。
- 模型级行为（思考回传与档位、`output_config.format`、`refusal`／`pause_turn`、服务端工具、`defer_loading`）全部是 ④ 官方口径，见 22 §4 家族固有特性与对应行。
- 计费：三桶不重叠、`message_delta` 只报 output（06 §1，坑 18）；没发 `cache_control` 也有 `cache_creation_input_tokens`（`web_search` 结果服务端自动写缓存，坑 179）。
- 部署变体 Vertex／Bedrock 见 §3.2。

### Google Gemini 官方（AI Studio）

- **正文所在**：02 §2.2、§3.2；03 §2–5；06 §2；13 §2、§4.2「imagen」；14 §2。Gemini 3.8 Flash（Vertex 后端，经 OrcaRouter，§3.3 ③ 线路节）：03 §2、§2.1、§4、§5；02 §2.2、§1 表后；04 §2；05 §3、§5「③ Gemini 的内置工具」；06 §1；01 §9.5；坑 2、170–173、176、178、190–195、197、203–205。AI Studio 直连：03 §2；22 §5「Google AI Studio 官方直连」行；坑 222。模型级行为：22 §5。【文档；3.8 Flash 经 OrcaRouter 实测 2026-09-26；思考回退 / 视频 2026-09-28；AI Studio 直连 2026-09-28】
- 面：③ `generateContent`／`streamGenerateContent`（`alt=sse`）；同一 wire 也出图（`responseModalities`）；Imagen `:predict`、Veo（`predictLongRunning`／`operations`）只有【文档】。
- 模型级行为（结构化、流形、`functionCall` id 与签名、`defer_loading`、内置工具）见 22 §5 家族固有特性与对应行。
- 计费：四字段拼法与代码 part 占上下文见 06 §1（坑 191、195）；`googleSearch` 按查询条数计（经 Vertex 实测，§3.3 ③ 线路节，坑 190）。
- 参考实现在官方 google 上只「未实测、照发」`googleSearch`；3.8 Flash 的事实是 Vertex 后端（正文所在行），不直接照搬 AI Studio。
- AI Studio 直连【实测 2026-09-28，`generateContent`，gemini-3-flash-preview / gemini-3.8-flash】：本库第一条 AI Studio 直连实测，只测了 `thinkingLevel` 大小写（小写也收、枚举外 `"lowest"` 400），数值与报错原文见正文所在行所列。平台层面的结论：直连的 400 原文带完整字段路径 `generation_config.thinking_config.thinking_level`、`details[].fieldViolations[].field` 同名（不像 OrcaRouter 用 `***` 遮）；`MINIMAL` 400、`thinkingBudget:0`、内置工具在 AI Studio 上仍未直验（OQ-021）。

### xAI (Grok) 官方

- **正文所在**：01 §9.1；03 §7.1、§7.3；05 §5「② Responses 族」、§7；13 §4.2「xai-images」、§7；06 §1；14 §2「xAI 实测」、§3.8；02 §1 表后；坑 66–67、123–129、206。模型级行为：22 §6。【实测 2026-09-22 出图与视频计费；视频输入 2026-09-28；其余 2026-09】
- 面：② 推荐；① Deprecated 仍作 legacy（`grok-4.3` 上 `video_url` 400 `Empty content block`，坑 206）；④ `/v1/messages` 完全弃用；🖼 `grok-imagine-image-2.0`／初代 `grok-imagine-image`（参数差异见 13 §4.2，坑 125）；🎬 `grok-imagine-video-1.5`。
- 图片输入下限（平台层）：16×16 拒、32×32 过（总像素 ≥512，宽高各 ≥8）【实测 2026-09】（坑 67）。
- 模型级行为（思考档位、加密推理、`tool_search`／`defer_loading`、`web_search_call`）见 22 §6 对应行。
- 计费：流里 `response.completed` 带 usage + `[DONE]` 收尾（文档没写终止事件）；🖼 `usage.cost_in_usd_ticks` 报实扣（细则 13 §7，坑 123、124、127、128）；🎬 按秒 + 每张图加价、报价只在轮询 done 回包（14 §3，坑 129）。

### DeepSeek 官方

- **正文所在**：03 §2、§3.5、§5；04 §1–2；06 §1、§2；02 §1 表后；坑 206、217、221。模型级行为：22 §7。【文档 2026-08；视频输入实测 2026-09-28；④ 面实测 2026-09-28（每条一次）】
- 面：旧：① 只有一张脸 → 新：① 与 ④ 两张（2026-09-28）。① `deepseek-flash` 发 `video_url` 422 点名可接受的片段类型（坑 206）。④ `https://api.deepseek.com/anthropic/v1/messages`，`x-api-key` + `anthropic-version`，deepseek-v4-pro / deepseek-flash【实测 2026-09-28，每条一次】。
- ④ 模型名映射【文档 2026-09】：`claude-opus*` → deepseek-v4-pro，`claude-haiku*` / `claude-sonnet*` → deepseek-flash，**不认识的模型名也映射到 deepseek-flash 不报错**（坑 221）；顶层未知字段 200 放过；`thinking.type:"bogus"` 422 并点名枚举——四家 ④ 兼容层里唯一在请求形状上严格的一家（03 §3.5）。
- 模型级行为（两面思考默认与关闭、回传义务、结构化、错误文案）见 22 §7 对应行。
- 计费：顶层 `prompt_cache_hit_tokens`／`prompt_cache_miss_tokens`，`prompt_tokens` 已含命中——命中要补进标准拼写，否则每次命中按全价记【Joycai 2026-09-14 修复】；④ 不发 `thinking` 输入 token 11 → 90（思考模式带自己的前缀）。
- 另：`deepseek-v4` 托管在百炼时 ② 面代码解释器放行（见百炼行）。

### 阿里百炼（千问 DashScope）

- **正文所在**：01 §8.1、§8.4；03 §3、§3.5、§4.1、§7；04 §4、§5.1；05 §5「代码解释器」；06 §2；13 §4（含「自由尺寸的规则」）；14 §2；16 §4–§9；02 §1 表后；坑 9、10、13、56–59、70、74–78、101–104、115–121、206–208、217–219。模型级行为：22 §8 与各家族节的「阿里百炼 · ④」行（MiniMax-M2.5 §11、glm-5.3 §9、kimi §13、deepseek-v4-pro §7）。【实测 2026-09-28 ④ 面（每条一次）与视频输入；2026-09-19 出图；2026-09-17 服务端工具；2026-09-13 ASR；2026-08-29 视频；文档 2026-09】
- 六条 wire（同一把 key）：① `/compatible-mode/v1`；Ⓓ `/api/v1/services/aigc/text-generation/…`（Qwen-Audio 仅此面）；④ `/apps/anthropic/v1/messages`（旧：模型子集，具体未给 → 新：2026-09-28 实测到 qwen3.8-flash / 3.7-flash / 3.5-plus / qwen-turbo 与托管的 MiniMax-M2.5 / glm-5.3 / kimi-k2-thinking / kimi-k2.6 / deepseek-v4-pro；完整名单仍未枚举）；② DashScope Responses（文档无 `text` 字段、说不支持 PDF，都未验）；🖼 同步 + 异步（提交路径不同，不是 header 切换；型号归属见 13 §4）；🎬 仅异步；🎤 同步／`-filetrans` 异步（上传经 OSS，16 §4–9）。
- 路径推导：剥 `/compatible-mode/v1` 再拼，只认路径不认 host，幂等。
- ④ 面平台层【实测 2026-09-28，普通 `sk-` key 走 `x-api-key`，每条一次】：新旧 host（`{WorkspaceId}.cn-beijing.maas.aliyuncs.com` 与 `dashscope.aliyuncs.com`）同一把 key 等价；**翻译层把上游的拒绝原样传回**——④ 的 `thinking` 被翻成 ① 方言 `enable_thinking` 下发，托管的第三方模型拒绝时点名的是别家协议的字段（坑 219）；面级校验会响：`thinking.type:"bogus"`（不点名）、未知模型、`temperature:2.5`、`budget_tokens` ≥ `max_tokens` 各 400（原文见 06 §2、03 §3.5）；顶层未知字段与 ① 的 `reasoning_effort` 200 放过；`adaptive` 也收。各模型的默认值与关闭结局见 22 §8「阿里百炼 · ④」行及 §7 / §9 / §11 / §13 的托管行。
- 模型级行为（服务端工具放行规则、两代思考控制、`tool_choice`、结构化、视频输入）见 22 §8 对应行。
- 出图：统一信封 `{model,input:{messages},parameters}`、错误在顶层 `{code,message}`、尺寸 `宽*高`、省略 `size` 落 2K 档、签名 URL 24h——细则 13 §4（坑 56、58、59、101、102）。
- ASR：同步／filetrans／OSS 上传的坑见 16 §4–9（坑 115、116、118–120）。
- 计费：`usage.x_tools.code_interpreter.count`；代码解释器限时免费但多轮推理 token 增；搜索按次价比 Anthropic 低三个数量级、`web_search_image` 是搜索 6–12 倍；签名 URL 24h／代码解释器图 12h 过期；Files API 对套餐开放。

### MiniMax（国内站）

- **正文所在**：01 §8.1、§8.3–8.4；03 §3、§3.4、§3.5、§5、§6；05 §6；06 §2；13 §4.2「minimax」；14 §2；坑 6、11、90、91、113、199、201、202、217、220、221。模型级行为：22 §11。【实测 2026-09-28 ④ 温度、④ 关闭档与未知值（M3／M2.7，每条一次）、① 回传（M3）；2026-08-29 视频；其余文档 2026-08】
- 两张 chat 脸模型 id 完全一致（无模型耦合 → 分两行，视频槽位两行各一份）；视频面路径：剥 `/v1` 或 `/anthropic/v1` → 拼 `/v2/video_generation`。
- ④ 面平台层【实测 2026-09-28，国内站 `api.minimaxi.com/anthropic`，MiniMax-M3 / M2.7，每条一次】：请求校验极松、**什么都收**（未知字段、① 的 `reasoning_effort`、越界 `top_k`／`temperature` 都 200；`thinking.type:"bogus"` 也 200 **而且开始想**，坑 220）；**未知模型名静默改映射**（`MiniMax-M3.1-Flash-Preview` → 响应 `model` 是 `MiniMax-M3`，坑 221）；唯一撞出来的 400 是 `top_p:1.5`（原文见 06 §2）。各型号的思考默认与关闭结局（M3 真关、M2.7 照想）见 22 §11 对应行。
- 错误信封：`base_resp.status_code` 在 HTTP 200 体内（1004／1008／1002），只认 `error` 会把过期密钥读成正常空回复（坑 6）；空 assistant 消息 400。
- 模型级行为（思考与回传、`tool_choice`、结构化、④ 工具结果块、温度）见 22 §11 对应行。
- 出图 `image-01`：「成功」但零张、`success_count` 是字符串 `"0"`（坑 90）；`subject_reference` 是主体参考不是编辑（坑 91）。
- 视频：首尾帧要嵌套 `{"type":"image_url","image_url":{"url"},"role":"first_frame"}`，平铺 `url` 被当没附图照样计费（坑 113）。

### 火山方舟 · 按量付费 base（`/api/v3`）

- **正文所在**：01 §9.3；13 §4.1、§7、§8；14 §2；02 §1 表后；坑 79–85、87、88、130–132。【实测 2026-09-18；复测 2026-09-23；`/api/v3` 无 ④ 文档【文档 + 探测 2026-09-28】】
- 只有套餐 key 在手，对话面至今未实测——能力格记 `unknown`，不抄套餐的；是否收 ① `video_url` 未量；按量 key 上传文件能否被套餐 key 引用【未验】；② 不写 `sources` 是否落到按次「联网内容插件」【未验】。
- 出图（Seedream，`ark` route，路径 = Images API `{base}/images/generations`、body 不同）：`doubao-seedream-5.0-flash` 与 Seedream 4.5／4.0 只在按量；`watermark` 默认 true → 恒明发（坑 79）；其余（组图超时、`output_tokens` = 像素/256、单张审核 `data[]` 单项 `{error}`、流式首块 ≈27 s、`partial_failed`、拆图层、透明背景与透明编辑、改图输入上限）见 13 §4.1、§7、§8（坑 82–85、87、88、130–132）。计费：`usage.input_images`、首张免费、失败免费（13 §7）。
- Files API `/api/v3/files` 只对按量 key 开放；Seedance 视频需按量 key、body 未覆盖。
- 按量 `/api/v3` **没有 ④ 面文档**【文档 2026-09-28】；无 key 探测 `/api/v3/messages`、`/api/v3/v1/messages`、`/api/anthropic/v1/messages` 全回 401——鉴权先于路由，没有 key 探不出路径在不在（OQ-071）。
- Endpoint ID `ep-…` 从 id 看不出哪一代，分类失败是正常，让作者点单。

### 火山方舟 · 订阅套餐 base（`/api/plan/v3`，Agent／Coding Plan）

- **正文所在**：01 §9.3；02 §1、§1 表后；03 §3.2、§3.4、§4、§5；04 §2；05 §5；06 §5；13 §4.1、§7、§8；14 §2；16 §10.2（ASR，§3.5 openspeech 节）；坑 80、81、114、122、130–137、198–201、206、208。模型级行为：22 §10。【实测 2026-09-18；Files API / flash / 透明背景 2026-09-23；④ 温度与视频输入 2026-09-28；`/api/coding` 文档 + 探测 2026-09-28】
- 三面路径：① `/api/plan/v3/chat/completions`；② `/api/plan/v3/responses`（探测路径少 `/v3` 打 `/api/plan/responses` 404 被判「没有 Responses」，坑 135）；④ base `/api/plan` 下 `/v1/messages`，`x-api-key` 与 Bearer 都收。
- **另一条前缀 `/api/coding`**【文档 + 无 key 探测 2026-09-28；带 key 未测】：Coding Plan 接入文章给的是 `/api/coding`（④）、`/api/coding/v3`（①），本库实测的套餐前缀是 `/api/plan`（「Agent Plan 套餐概览」）；两者关系没有核实——**不要把 `/api/plan` 的实测结论套到 `/api/coding` 上**；无 key 探 401（鉴权先于路由）。地址与测法见 31 OQ-071。
- 变体回读：与按量同 channel type，只按 type 找变体会把套餐读成按量、编辑器「恢复」成必 401 的 base（坑 80）→ 类型匹配后比 endpoint 去尾斜杠。
- 目录：① `/models` 404 非 JSON、④ `/v1/models` 对有效 key 401（坑 136）→ `/models` 404/401/403 都再发最小补全定论（错 key 401、造的 id 404 `UnsupportedModel`）；退回静态目录，收两种拼写（`5-0` 与 `5.0` 同一代、六位日期不是次版本、lite 三种拼写）；非法 `size` 零成本探测（400 = 支持，404 = 不支持，坑 81）。
- 模型裁剪：对话只 `doubao-seed-2.0-pro`（别名 `ark-code-latest`）、2.0-lite／2.0-mini／2.1-turbo；Seed 1.6 系 404 `UnsupportedModel`；出图只服务 5.0 pro／lite：`doubao-seedream-5.0-pro`、`doubao-seedream-5.0-lite`（套餐文档写法）与带日期的 `…-5-0-pro-260628`、`…-5-0-lite-260128` 都收，**不带 `lite` 的** `doubao-seedream-5-0-260128`（按量文档里 lite 的正式 id）与 4.5／4.0 回 404 `UnsupportedModel`，5.0 flash 三种拼法也 404（只在按量 base【实测 2026-09-23】）——分类要认「`5-0` 与 `5.0` 同一代、六位日期不是次版本、lite 有三种拼写」。
- 模型级行为（思考开关与回传、签名、温度、结构化、服务端工具、读图／PDF／视频输入）见 22 §10 对应行（坑 114、133、134、137、198、201、206、208）；`file_url` 三面都通（推翻旧写法「`file_url` 仅 ② 只可能在按量 base 上用」）与 `file_id` 假 id 404 见下「无 Files API」条。
- 无 Files API【实测 2026-09-23，对照厂商「文件输入(Files API)」页复测】：`/api/plan/v3/files`、`/api/plan/files`、`/api/plan/v1/files` 列表／上传／检索／删除全 404（路由不存在）；同一把 key 打按量 `/api/v3/files` 是 401；Seedance 404。对话端点认 `file_id` 字段：①（`{type:"file",file:{file_id}}`）②（`input_file.file_id`）给假 id 回 404 `ResourceNotFound` 不是 400，只是套餐侧没有上传入口；④ `source.type:"file"` 400（支持值 `base64 / text / url / content`）。`file_url` 三面都通：② `input_file.file_url`、① `{type:"file",file:{file_url}}`、④ `document` + `source:{type:"url"}` 都读得出公网 PDF（厂商写「仅 ②」，① 实测也收）。
- 上限：上下文 256k；`max_tokens` 2.0-mini 两族 ≤ 131,072、2.1-turbo 收 262,144，超了 400 报上限（生成前拒）【实测 2026-09-18】【实测 2026-09-23】。
- 条款：文本模型「不可用于 API 调用，在非 AI 工具中使用……可能被识别为滥用」。

### 智谱 BigModel · 按量标准端点（`/api/paas/v4`）

- **正文所在**：01 §9.4；03 §3.1、§3.5；04 §2、§4；05 §5「服务端工具归平台」；06 §2；16 §10.2；02 §1 表后；坑 94–100、206、217、219。模型级行为：22 §9。【实测 2026-09-19，11 个对话模型；④ 面思考 2026-09-28（每条一次）】
- 11 个对话模型实测（glm-4.5／4.5-air／4.6／4.7／5／5-turbo／5.1／5.2／5.3／5.3-flash／5.3-flashx）【实测 2026-09-19】；`/models` OpenAI 形，连接测试直接可用；错 key 401 `令牌已过期或验证不正确`。
- 模型级行为（思考按代、tool_choice 砍档、结构化、对话内 `web_search`、读图、视频输入——后者型号与日期未标 ⚠ ⏳待复核，OQ-052）见 22 §9 家族固有特性与对应行（坑 94–100）。
- 独立服务端工具端点（应用执行，不受模型约束）：`POST /web_search`（`count`／`search_recency_filter` 多数引擎无视）与 `POST /reader`（`return_format:"text"` 有损；目标 404 与主机不存在都 500 `1234`）——参数与原文见 05 §5「服务端工具归平台」；无 usage、按次。对话内搜索结果按 token 灌入（`search_pro` ≈24k、`search_std` ≈6.7k）。
- 上限：`max_tokens` 上界 5.x／4.6／4.7 131,072、4.5-air 98,304、glm-4.5 实测 131,072（文档 96K）；上下文 5.3／5.3-flash(x)／5.2 1M、5-turbo 204,800、5.1／5／4.7／4.6 200K、4.5 系 128K。
- 错误：信封 `{"error":{"code":"1210","message":"…"}}`（业务码字符串、HTTP 状态另给）；`finish_reason` `sensitive`／`network_error` 必 throw、`model_context_window_exceeded` 按截断（坑 99）；「该模型始终思考，不支持关闭思考」覆盖 5.3 代所有非法思考参数；温度／`max_tokens` 越界 400 原文见 06 §2（上界生成前拒不计费）；未知顶层字段一律放过。
- 🎤 `glm-asr`：限流码（16 §10.2）【实现】。

### 智谱 BigModel · Coding Plan 编程端点

- **正文所在**：01 §9.4；03 §3.5；坑 217；①② 完整实测未覆盖见 §4、31 OQ-013。模型级行为：22 §9。
- 同 host、同一把按量 key 全通：① `/api/coding/paas/v4`、④ `/api/anthropic`、② `/api/v1`；路径决定扣余额还是扣套餐，选错不失败只换一笔钱 → 必须分行，不挂进按量行线路菜单。
- 目录：② `/api/v1/models` 是 Codex CLI 目录形（`slug`、`context_window`、`supported_reasoning_levels`、`input_modalities`），只列 3 个（哪三个未给）；④ `/v1/models` Anthropic 形。
- ④ `/api/anthropic` 平台层【实测 2026-09-28】：① 面那句 1210 在 ④ 面原样出现、外面多包一层 `{"type":"invalid_request_error","code":"1210","message":"[1210][…][<request id>]"}`；`thinking.type:"bogus"` 回的也是 1210 不是「非法值」；顶层未知字段 200 放过，与 ① 面一致；`usage` 带 `server_tool_use.web_search_requests`【2026-09-19，只探两次】。各模型默认值与关闭结局（5.3 系想且关不掉、4.6 真关、4.7 默认不想、`effort:"low"` 无 thinking 块）见 22 §9 对应行。

### Kimi（Moonshot）

- 输入里唯一事实：① `json_object` 不查 "json" 字样（与智谱同批实测）。其余按 §4「未知、需核实」。

### 3.2 云部署变体

### Azure OpenAI

- **正文所在**：01 §2；02 §5；06 §2。中转站里叫 `[Azure]` 的上游不等于 Azure OpenAI（01 §9.2、坑 159，§3.4 `[Azure]` 节）。【文档】
- 同 body、换鉴权（`api-key` 头）与 URL（`/openai/deployments/{d}/...?api-version=`），模型标识不同，一个头救不了——要做是另一族不是 compat 选项；`api-version` 细节未覆盖。
- `finish_reason: "content_filter"` 代替错误码（多家网关同），几乎不带文本，必须 throw（坑 7）。
- 辨识：New API 里 `[Azure]` 档是带护栏的网关（回显 `instructions` 里有「System integrity addendum」），不是 Azure OpenAI；OrcaRouter ② 默认线路上 terra 的 reasoning `format` 是 `azure-openai-responses-v1`（上游 Azure）。

### Vertex AI

- **正文所在**：01 §2、§9.5；03 §2、§5；05 §5；06 §1；Gemini 3.8 Flash 经 OrcaRouter ③ 线路的全部事实见 §3.3 ③ 线路节与 22 §5。
- 怎么认出它：见 §1 云部署变体行（经 OrcaRouter ③ 线路看到的即 Vertex 原样）。
- 网关重序列化后仍由 Vertex 校验枚举：非法档位 `BOGUS` 400 见 03 补遗；`MINIMAL` 400 `Thinking level MINIMAL is not supported`（3.8 Flash；3.1 Pro 亦无，坑 170）→「关闭」映射 `LOW`。
- 缺签名：HTTP 400（不是 200 + `MISSING_THOUGHT_SIGNATURE`，坑 173）；流末 `{text:""}` 回灌 400（是 Vertex 本身还是网关把空串丢成 `{}` 未定，坑 172）；原文见 03 §5 与 05 §3。
- 图片字段 snake_case／camelCase 两种都收（对比 New API ③ 面只认 camelCase）。
- Claude 部署变体只有【文档】。

### AWS Bedrock（Claude 正向）

- **正文所在**：01 §2、§9.2 第 4 条；05 §5；渠道层事实见 §3.4 AWSb 节与 22 §4 AWSb 行。【实测 2026-09-23 经 New API AWSb 渠道】
- 经 New API AWSb 渠道测得：消息 id `msg_bdrk_`；参数／签名校验与官方同文 400；任何 Anthropic 服务端工具（`web_search`／`web_fetch`／`code_execution`）400（原文见 05 §5）——整条请求失败 → 正向渠道也要点名；URL 图片 400；缺口会响不静默。
- Bedrock Converse（camelCase、SigV4）是第五种独立 body——接它是新族，body 未覆盖（§4）。

### 3.3 聚合网关

### OrcaRouter（网关共性）

- **正文所在**：01 §9.5；06 §1、§2、§5、§8 第 7、10、12 条；02 §1 表后；05 §5「③ Gemini 的内置工具」；03 §2.1；经它测得的厂商事实见 §3.1 Anthropic / Gemini / OpenAI 节；坑 170–179、185–197、203–206。【实测 2026-09-03 探测与免费档；付费四面 2026-09-26；流式花费 / PDF / Gemini 内置工具再补测 2026-09-26；思考回退 / 视频输入 2026-09-28】
- 一把 key、一份目录、四面同一主机：① `/v1/chat/completions`、② `/v1/responses`、③ `/v1beta/models/{model}:generateContent`／`:streamGenerateContent`、④ `/v1/messages`；一族一行，Bearer（`x-api-key`／`x-goog-api-key` 只在各自路径承诺）。
- 目录：`GET /v1/models` Bearer 回 OpenAI 形（203 条）、`x-api-key` 回 Anthropic 形、`/v1beta/models` 回 Gemini 形；标定值从目录抄（GPT-6／GPT-5.6-terra、Claude 5 系、Gemini 3.8 Flash 的上下文／输出上限见 22 各家族行）；八个 `input_modalities` 都含 `file`；只对测过的路径算实测，经 ① 翻译层的 PDF 只算推断。
- `supported_endpoint_types` 两方向证据：OrcaRouter 声明了没有却能打（`gpt-6-luna`／`-sol` 只声明 `openai`，② 200），New API 声明了却不许——不能当线路开关（坑 166）。
- 请求侧不是透传：解析成它认识的结构再重新序列化，未知字段与非法枚举常 200；06 §8 第 10 条「非法参数分类法」在此失灵（④ 乱写 200 却是 Anthropic 原样，坑 174）→ 按面用透传证据判后端；「发 X 会不会 400」只记网关注记。
- 错误信封全改写成 OpenAI 形，带 New API 指纹（④ `type:"<nil>"`、③ `type:"invalid_argument"`），路径 `***.***.content.0` 被遮；上游 5xx 改 `api_error` + `The upstream provider is temporarily unavailable`；文档说的 `claude_error`／`gemini_error` 一次没出现（坑 177）。
- 响应头只有 `x-orca-request-id`、`x-orca-version`、`x-orca-route: model=…; fallback=0`（文档没写），不漏任何上游头。
- 402 先于模型解析见 §1 通用闸门（【实测 2026-09-03】）；免费档具体模型／限制未给。
- 计费：唯一被声明为「报的数 = 实扣」的平台（06 §1 第四种口径），四个适配器带 `X-OrcaRouter-Include-Cost: true`；与 `GET /v1/generation?id=` `total_cost` 对过（④③ 相等，①② 差不到一个计价单位，按 1/500,000 美元取整；账单另有 New API 式 `quota` = 美元 × 500,000）；「贴受信网关标签却指向别的中转」用两道门（平台声明 + 请求地址推出的平台一致，坑 185）。
- 不做：不调计数端点、不按错误信封 `type` 判类（写注释不加分支）；起步模型钉线路要配守卫 `pinnableRoute`（坑 196）。

### OrcaRouter · ① 线路

- 翻译层（OpenRouter 形态）：`id:"gen-…"`、`provider:"OpenAI"`、`native_finish_reason`、`reasoning_details[]`（密文尾部解出 `endpoint_slug`）；GPT 上游再走 Responses——`reasoning_effort` + `tools` 同发 200 不能证伪「官方 ① 上 5.4+ 不能 effort + tools」。
- 手脚：发一个没有 parameters 的函数工具名 `googleSearch`／`urlContext`／`codeExecution` → 网关换成 Gemini 原生内置工具（网关约定）【文档 2026-09】；`video_url` Gemini 200 静默丢弃、输入 token 25→25（坑 205），GPT 400（坑 206）；PDF `file` 部件 ✅ 但读不读由网关翻译定，标定只算推断。
- 模型级行为（跨族思维链、结构化、`web_search_options`）见 22 §3／§4／§5 的「OrcaRouter · ① 线路」行。
- 计费：末块 `usage.cost`（`cost_usd ?? cost`；要 `include_usage`；流式没有 `cost_usd`，非流式两个都有）；`is_byok`、`cost_details.upstream_inference_cost`；不需请求头。

### OrcaRouter · ② 默认线路

- 同一 OpenRouter 形态层：`gen-…` id、伪造 `msg_tmp_…`／`fc_tmp_…` item id、`summary` 回显被改写（03 补遗）、`store` 恒 `false`；terra 的 reasoning `format` 是 `azure-openai-responses-v1`（上游 Azure）。
- 改写：`reasoning.effort` `minimal` → `low`（03 §7.1）；`"bogus"` 回网关自己的 `upstream_rejected_request`，原文被吞。
- 回灌义务测不出：`store:false` 下只回 id 的 reasoning item、篡改 `encrypted_content`、丢 reasoning item 全 200——网关多半改写了 `input`；官方规则不据此改口。
- 模型级行为（工具轮、结构化、`input_file` PDF、`web_search`）见 22 §3「OrcaRouter · ② 默认线路」行；流式 reasoning item 形状见 03 补遗。
- 计费：`response.completed.response.usage.cost`，不需请求头。

### OrcaRouter · ② 原样线路

- 触发：`store:true`，或 `include` 含 `web_search_call.action.sources`；`tools:[{type:"web_search"}]`、`include:["reasoning.encrypted_content"]`、`text.verbosity` 都不触发（坑 175）→ 不按 id 前缀或花费字段推断条目类型。
- 回包 OpenAI 原样：`resp_…` id、`billing`、`tool_usage`、`moderation`、`prompt_cache_retention:"24h"`、默认 `store:true`；`web_search_call` `in_progress`／`searching`／`completed` 齐全、`url_citation`。
- 没有任何花费字段，`X-OrcaRouter-Include-Cost` 头对 ② 无效 → 按表算；`usage.input_tokens_details.cache_write_tokens`（不是中转私有键，一次 `web_search` 4,388）。
- 其余能力（结构化、工具、思考回灌）在此线路未测。

### OrcaRouter · ③ 线路（Vertex）

- id 里斜杠原样进路径：`/v1beta/models/google/gemini-3.8-flash:generateContent`，不编码；不带 `alt=sse` 的 `:streamGenerateContent` 也回 SSE（官方是 JSON 数组）。
- 回包 Vertex 原样（见 3.2 Vertex）；请求重序列化：`generationConfig.fooBar` 200，枚举上游校验；`thinkingBudget:0` 想关、账单照样几百思考 token（可能网关把 0 丢了，坑 171）。
- 模型级行为（思考档位与回退、签名与回灌、工具轮、内置工具、结构化）见 22 §5「OrcaRouter · ③ 线路」行（坑 172、173、190–195、203、204）。
- `:countTokens` 被当 `generateContent` 执行并计费 $0.0028【实测 2026-09-26】（坑 176）。
- 错误信封改写：`{"error":{"message","type":"invalid_argument","param":"","code":400}}`，路径与 URL `***`。
- 计费：末块 `usageMetadata.costUsd` 需 `X-OrcaRouter-Include-Cost: true`（坑 186）；`googleSearch` 约 $0.014/条（一题 6 条 $0.084；改口自「一次 $0.028」，坑 178、190）；`toolUsePromptTokenCount` 在 prompt 之外（20+65+77=162）；PDF `inlineData`+`application/pdf` 一页按图计 520 token（坑 197）；16×16 图 1,098 token。

### OrcaRouter · ④ 线路

- 回包 Anthropic 原样（`msg_011C…`、不透明 base64 `signature`、`usage.cache_creation` 分项、`service_tier`、`inference_geo`、`stop_details`、`context_management`）——Claude 5 系事实以此为据记进 03–06。
- 请求重序列化：顶层 `foo:1`、`thinking.type:"bogus"`、`output_config.effort:"bogus"`、`output_config.foo` 全 200（官方 400）；同一 schema 官方 400 经此 200（坑 182）；整块丢 thinking block 200（与官方「缺失 → 静默降级」一致，是印证）；改签名 400。
- `/v1/messages/count_tokens` 301 到官网首页（坑 176）。
- 模型级行为（`tool_use.caller`、`output_config.format`、思考默认与关闭、`web_search_20250305` 事件形状）见 22 §4「经 OrcaRouter ④」各行。
- 计费：流式 `message_delta.usage.cost_usd` 需 `X-OrcaRouter-Include-Cost: true`，`message_start` 快照里没有（坑 186）；`web_search_20250305` 无 beta 头、`usage.server_tool_use:{web_search_requests:1, web_fetch_requests:0}`、没发 `cache_control` 也记 2,834 `cache_creation_input_tokens`（坑 179）、一请求合计 $0.051；`usage.output_tokens_details.thinking_tokens`（22 = 21+1）；PDF Sonnet 5 未打断点也记缓存写 1,630（Opus 5.5 无，坑 197）。

### OpenRouter

- **正文所在**：06 §2、§6；OpenRouter 形态的回包指纹见 01 §9.5 与本节 ① / ② 默认线路。【文档；指纹经 OrcaRouter 实测 2026-09-26】
- 本库只有【文档】：① 面；`/models` 带 `context_length`；SSE 体内 `data:{"error":...}` routinely（坑 6）；① 回 `usage.cost` 等（平台未受信前不收，坑 185）。
- 「OpenRouter 形态」指纹清单见 §3.3 ① 线路／② 默认线路节：都是在 OrcaRouter 上看到的，不是对 OpenRouter 本身的实测。

### 3.4 自建中转 New API 类

### New API 类中转站（平台层／转换层）

- **正文所在**：01 §9.2（四种静默行为、Kiro 渠道、五个渠道、「上游做成作者声明的数据」、「同一个 GPT，两类上游」、「上游画像扩到 GPT」、「规范化 id」）；02 §7.1 规则 2、§1 表后、§2.2、§3.2；03 §3.3、§4、§7.4；04 §2、§4「第四种变体」、§5.1；05 §3、§5「中转站自己做服务端工具」、§5「中转站上的 GPT」；06 §1「中转站估算的 usage」、§2、§4.1、§5、§8 第 7–11 条；13 §4.2「经 chat 出图的中继」、§6；14 §4；坑 61–65、105–112、138–169、223。模型级行为：22 §3（GPT 各档行）、§4（Claude 各渠道行）、§5（③ 面行）。【实测 2026-09 + 中继源码；Kiro 与五渠道对照 2026-09-23；上游画像实现 2026-09-23；GPT 四上游实测与 codex / azure 画像 2026-09-24；规范化 id 实现 2026-09-27】
- 怎么认出它：见 §1 自建中转行；两台样本只靠编号区分（第八 vs 第十／十五／十六／十七）；五渠道对照是同一把 key、同一套 curl 用例约 350 次请求（第十六个样本）。
- 转换层缺口（同台四渠道一致，按平台 × 面裁决，不进渠道画像）：Claude ① `response_format`（`json_object`／strict `json_schema`）被丢、`reasoning_effort:"max"`／`"none"` = 不想（坑 140、142；「扩到整台」【未实现】，参考实现只点名 Kiro）；GPT ① 四档响应 id 都是 `resp_…`、流里 `reasoning_content`、`web_search_options` 四档静默忽略（坑 164）、顶层 `verbosity` 无效。
- ③ 面只认 camelCase：snake_case 图片字段与系统提示被无视（坑 2、111）。
- 接收侧畸形（`arguments` 多对象拼接、空串调用 id、`reasoning_content:""` 盖住 `reasoning`、usage 末块 `choices:[]`、`content` 数组形；经 chat 出图的存图／路由／`image[]` 问题）见 02 §3.2、05 §3、13 §4.2（坑 92、93、105–108、110）。
- URL 图片：中转站计 token 前自己下载，拒爬主机 500 `count_token_failed`／400／流内 `error` + 空答（坑 167）→ 图片一律内联 base64。
- 探测判据与对策见 §1 自建中转行与通用闸门（坑 112、166）。
- 上游数据化（前缀是站主起的名字，产品名可推断、站主缩写永不推断只进作者的表；解析顺序 手选 > 前缀表 > 产品名推断；单一 `capabilityModelOf`）见 01 §9.2（坑 152–158、168）。
- 计费：中转站估算 usage 总数可用、缓存分段不可信；`usage.attribution.request_fields.instructions.input_tokens` 是注入读数（发 10 报 4,380）；无此字段时用「Say OK.」对照输入 token。
- 代码侧通用对策只有两条（② adapter 恒发 `instructions`、终止响应回显比对，坑 61；01 §9.2）；没有按中转站名的分支。旧：不加剥档位前缀规则 → 新：**规范化 id，只在中转平台上**（2026-09-27，【实现】）——前缀表最长匹配优先、否则去开头 `[…]`、再去 `vendor/`；只用来查目录，平台格与上游格仍按原始 id，「所有平台都去」已由金标 / 变异检查（离线）收回（01 §9.2；坑 223）。

### New API · Kiro 渠道（Claude）

- 前缀 `[kiro]` `[kiro1]`…`[kiro3]` `[kiro-200k]` `[特价kiro量]`；后端非 Anthropic API（Kiro 是 AWS 的 IDE 产品，中转站在两者之间翻译）；两款模型（opus-4-6／opus-5）每条一致、usage 逐字相同——从请求侧分不出背后是不是两个模型；Sonnet 按推断收进名单（有意例外）。
- 只开 ① 与 ④：`/v1/responses`、`/v1beta` 回 500 `convert_request_failed`「not implemented」；① 先翻成 Messages 再发（`usage.billing_usage.source:"claude_messages"`，所以 ④ 的缺口 ① 全有）；`/v1/messages/count_tokens` 404 `Invalid URL`；`/v1/files` 401；不带 `anthropic-version` 也 200；`x-api-key` 与 Bearer 都收。
- 目录：`supported_endpoint_types` 一律 `null`；回显去掉档位前缀；不存在的模型 503 `model_not_found`「No available channel for model … under group default」（不是 404）。
- 反代特征：`effort:"bogus"` 一律 200；无参数／签名校验；缺口几乎全 200 不报错。
- 对请求的手脚（结论，逐格数值见 22 §4 Kiro ④／① 两行）：`max_tokens`（① 还有 `max_completion_tokens`）无视、`stop_reason` 永不 `max_tokens`（坑 65）；思考只 low 有效、`display` 无视（坑 141）；两族 JSON 旋钮都 200 忽略（坑 142）；强制 `tool_choice` 只在非流式转换路径实现、且时好时坏（坑 138）→ 点名 id 上 forced 一律 `auto`；单挂 `web_search_20250305`／`_20260209` **整条劫持**（模型没跑，指纹与细节见坑 139；+ 函数工具 + 流式 → 真搜；+ 函数工具 + 非流式 → 丢）；`web_fetch_20250910`／`code_execution_20250825`／乱造 type → 200 丢弃且模型假装执行（坑 144）；① `web_search_options` 转成 ④ `web_search` 后同样劫持；PDF（④ `document`／① `file`）与 URL 图片丢、base64 图 ✅（坑 143）；不注入系统提示（不带 system 输入 ~70 token）。
- 劫持指纹：两款模型逐字相同、`output_tokens` 固定 644/568/478、`encrypted_content` 是明文摘要、`page_age` null。
- 计费：`cache_control` 只写不读、缓存段是拼的、打断点比不打更贵（数值见 06 §1，坑 145）；同一请求流式 `prompt_tokens` 301、非流式 102；「Say OK.」输入 7 + 拼的缓存段。
- 「只在本轮带函数工具时发 `web_search`」的按请求判定【未实现】。

### New API · CC 渠道（Claude）

- 前缀 `[CC量]`，推测 Claude Code 通道，未证实；证据等级 curl 实测（无 live adapter 文件）。
- 反代（无参数／签名校验一律 200）；对请求的手脚（结论）：① `response_format` 丢（转换层）；URL 图片丢；`code_execution_20250825` 丢、没有块；`web_search`（单挂 ✅ 真搜，要求搜才搜、改写句子请求不触发不劫持）／`web_fetch` ✅ 真做；PDF ✅。逐格（思考、强制工具、`output_config.format`）见 22 §4 CC 渠道各行（坑 147、149、150、152、153）。
- 计费：缓存是真的（第二次 `cache_read` = 前缀）；「Say OK.」9–10 token。

### New API · anti 渠道（Claude）

- 前缀 `[anti量]`，推测 Antigravity，未证实；curl 实测。
- 反代（无校验一律 200）；对请求的手脚（结论）：④ 不思考（`-thinking` 变体也不，坑 148）；`max_tokens` ④ 生效、① 无视（同渠道两面转换不同，坑 151）；强制 `tool_choice` 两条路径都不实现（第五种变体）→ 降 `auto`；两族 JSON 旋钮无视；PDF 与纯文本 document 都丢；URL 图片 500；`web_search`／`web_fetch`／`code_execution` 全丢、模型凭记忆答。逐格见 22 §4 anti 渠道两行。
- 计费：没有任何缓存字段、两次都全价；「Say OK.」不带 system 报 39（别的渠道 9–10）——渠道自己注入约 30 token 提示（坑 151）。

### New API · AWSb 渠道（Claude，Bedrock 正向）

- 前缀 `[正向AWSb量]`；消息 id `msg_bdrk_`；curl 实测。正向：`effort:"bogus"` 400 官方原文（原文见 03 补遗）、校验签名——但正向 ≠ 官方（缺口会响不静默）。
- 对请求的手脚（结论）：④ 任何 Anthropic 服务端工具与 ① `web_search_options` 整条 400；URL 图片 400；① `response_format` 照丢（④ 面执行 schema、① 丢——同渠道同模型结构化随面不同，坑 150）。逐格（思考、强制工具、`output_config.format`、PDF、`cache_control`）见 22 §4 AWSb 两行与 §3.2 Bedrock 节。
- 目录里 `[AWSb]gpt-5.6-sol` 503 `No available channel`（GPT 在此档无线路，坑 166）。

### New API · 官key 渠道

- 前缀 `[官key量]`；当天 ①④ 两个端点全部 502 `Upstream request failed`，没测到；画像 official 无任何格子，选它只表示「已分类」。
- `[官key]gpt-5.6-sol` 目录有但 503「No available channel」——是「当时没线路」，是否长期如此未知。

### New API · `[特价Pro]` 档（GPT）

- ChatGPT 账号池／Codex 后端（不发 `instructions` 会被注入 Codex／「coding assistant」提示，`usage` 带 `attribution`），画像 codex；与 `[Plus]`／`[Pro]`／`[Azure]` 同台同 key（第十七个样本）【实测 2026-09-24】。
- 目录声明 `supported_endpoint_types` 含 `anthropic`／`gemini`，打 `/v1/messages` 回「This group does not allow Anthropic Messages requests」——目录不可信。
- 注入与改写：② 带 `instructions` 「Say OK.」19 token 不注入；不带则时有时无（0 或 +11）；同一档注入量 0／11／296／4.4K／17K 五种，延迟 3 s 到超时——一档之内不是一个账号（坑 165）；① 带 system 仍注入 4,397（多数请求）；`effort:"none"` 关不掉（回显 `medium`，坑 161）；`temperature:0.5` 200 回显 `1.0`（坑 162）；`max_output_tokens`／`max_completion_tokens` 无视（坑 65）；乱写 effort → 流式 `response.failed`（`upstream_error`）、① 流里「Upstream service temporarily unavailable」；`image_generation` 403 `Image generation is not enabled for this group`；URL 图片拒爬主机流里 `error` 事件后接空答（200）。
- 模型级行为（思考分档、`reasoning.mode`、结构化、`web_search` 耗时与输入、`code_interpreter`／`file_search`、`store`、多模态）见 22 §3 `[特价Pro]` ②／① 两行。
- 计费：`usage.attribution.request_fields.instructions.input_tokens` 读注入量（作者没发却记 4,380）；前缀缓存 `cached_tokens` 9,984（同一 10K 前缀）。
- 画像 codex：② `instructionsField` ✓ 恒发（不发则注入 4.4K）、`temperature` ✗（回显 1）、`textVerbosity` ✓、`web_search` ✓、`pdfInput` ✓、强制工具 ✓；① 温度不写格子。

### New API · `[Plus]` 档（GPT）

- 账号池 codex【实测 2026-09-24】。注入与改写：② 不带 `instructions` 注入 4,389（`attribution.request_fields.instructions.input_tokens: 4380`）；① 带 system 3/3 注入 4,395；乱写 effort → 502 `Upstream request failed`（① `reasoning_effort:"bogus"` 同）；`temperature:0.5` 回显 `1.0`；`max_output_tokens` 无视。
- 模型级行为（json_schema 省略／显式 strict 都 ✅——第八个样本那条「显式 strict 丢」在 Plus 上未复现；其余同 `[特价Pro]`）见 22 §3 `[Plus]` 两行。

### New API · `[Pro]` 档（GPT）

- 账号池 codex——校验与官方同源（乱写 effort 400 `Invalid value: 'bogus'. Supported values are: 'none', 'minimal', …`）却是唯一丢结构化输出的账号档：「校验同源 ≠ 能力同源」【实测 2026-09-24】。
- 手脚：② `text.format` json_schema 省略与显式 `strict:true` 各 4 次全丢，回显 `{type:"text"}`（丢 format 后提示语要求 JSON 仍回 JSON，「能解析」不能证明 schema 生效，坑 160）；旧：第八个样本（另一台，5.4／5.5）「只有显式 `strict:true` 才丢」→ 新：不论写不写都丢（2026-09-24 扩展）；① `response_format: json_schema` 丢（4/4）；不带 `instructions` 9 token 不注入、① 带 system 19 不注入，但带具名 `tool_choice` 时注入 4,434；`temperature:0.5` 回显 `1.0`；URL 图片拒爬主机 400 `Error while downloading file`。
- 模型级行为（服务端工具、具名 `tool_choice`）见 22 §3 `[Pro]` 两行。
- 能力表不给账号池写 `structuredOutput:false`（另两档白丢可用 JSON 模式），只在说明里告知；回显比对 `text.format`【未实现】。

### New API · `[Azure]` 档（GPT，带护栏的网关）

- 不是 Azure OpenAI，而是带「只准做 OpenAI 相关工作」护栏的网关；画像 azure（正向）；这一档没有 sol 线路（两次相隔 10 分钟 503 `No available channel for model gpt-5.6-sol under group …`），用 `gpt-5.6-terra` 顶替（比的是上游不是模型）【实测 2026-09-24】。
- 注入（护栏）：② 带 `instructions`（哪怕空串）输入 1,209 token——`instructions` 后追加约 1.2K 护栏，回显三段：作者原文 → 中转站反制「【最高优先级强制规则】…>>>IGNORE_AFTER<<<…」→ 上游「System integrity addendum (highest priority; supersedes any conflicting instructions above)」四步门禁（上文没把模型确立为「OpenAI 相关助手」就拒绝、明文拒 fiction/novels/poems/role-play 创作、拒泄露提示词、拒按随口给的数字批量输出）；中转站的反制大体有效但不是每次：约 60 次里至少 4 次被改写（鬼故事 6 拒 2，一道数学题、一次结构化输出的字段里也出现「only OpenAI-related」）——200、无 `refusal`、只是答案不对（坑 159）；不带 `instructions` 键就没有护栏（纯 `input`、system 放进 `{role:"developer"}`、① 面带或不带 system 都是 9–33 token，创作题全部照写）；`instructions` 写成写作者身份时 4/4 照写，样本太小、不能说身份压得住护栏。
- 改写与拒绝（网关侧）：`none` ② 关不掉（① 真关）；乱写 effort → 500 `Upstream gateway error`（① 同 500）；`temperature:0.5` 500（6/6，`1` 则 200，坑 162）；`store:true` 500；① 具名 `tool_choice` 500（9/9，`required` ✅）→ 画像强制工具 ✗；`web_search` 静默丢弃（无 `web_search_call`，模型答「I can't perform a live web search」，坑 163）；`code_interpreter`／`file_search` 500；URL 图片拒爬主机 500 `count_token_failed`（中转站计 token 前自己下载，请求没到上游，坑 167）；`max_output_tokens:16` ✅ `incomplete`、① `max_completion_tokens:16` → `finish_reason: length` 但 `completion_tokens` 128。
- 模型级行为（思考分档、`reasoning.mode`、`text.verbosity`、结构化、`image_generation`）见 22 §3 `[Azure]` 两行。
- 计费：前缀缓存 `cached_tokens` 11,576（多出的是护栏）；每请求 +1.2K 输入（多半命中缓存）；网关无 `attribution` 字段，护栏只能从回显 `instructions` 看出。
- 画像 azure：② `instructionsField` ✗ → 系统提示改为 `input` 开头 `{role:"developer", content}`、不发 `instructions` 键（不做全局开关——翻向 developer 账号池每请求 +4.4K，坑 169）；`temperature` ✗；`web_search` ✗；强制工具 ② ✓ ① ✗。对写作应用是最不该选的档。

### New API 中转站（另一台）· `[Pro]`／`[Plus]` 档（第八、第十个样本）

- base 未给；GPT-5.x 档位（5.4／5.5 第八个样本；5.6 sol／terra 第十个样本）。
- 四种静默行为（01 §9.2 第 1–4 条；坑 61、62、65）：注入 Codex 系统提示 4.4K–9K（Chat 面同样）；sol 发 `max` 回显 `none` 且 0 推理 token（2026-09-24 另一台四上游未复现，按「当时当档」理解）、terra 发 `none` 回显 `medium` 且照样推理（全部复现）、`temperature:0.5` 回显 `1.0`；其中一台无视 `max_output_tokens`；一个档位背后多个上游，回显字段时有时无。
- 第八个样本：GPT-5.4／5.5 显式 `strict:true` 才丢 `text.format`（旧结论，被 2026-09-24 同台 `[Pro]` 扩展，坑 63）。第十个样本：搜索 112 s（比第十七个样本慢一个量级）；改写随时间与上游出现又消失，比对要常开。

### 未具名中转（Claude 后端，Joycai 线上流量）

- ① 面：`arguments` 先吐空对象占位再给真参数 `{}{"id":1}`（按括号深度切、左到右合并，坑 105）；调用 id 是空串 `""`、同批两调用共用 → 下一轮重复 `tool_call_id` 400、整段会话此后每轮 400（空串按缺失处理、按序号补 id，坑 106）。

### Midjourney（midjourney-proxy／New API `/mj/*`）

- **正文所在**：13 §2、§4.2「midjourney」。【实现，日期未标】
- 独立异步出图协议（`/mj/submit`）；只有【实现】口径，地址／目录／计费全 ⚠。

### 3.5 本地运行时与 ASR 专营

### Ollama

- **正文所在**：02 §5、§6；01 §6；06 §6；坑 5。【实测，日期未标】
- 鉴权见 §1 本地运行时行；Windows 打包版 403 靠 http 层覆盖 `Origin` 头修复（按「URL 指向本机」判断，Ollama 不做成枚举值）。
- 超窗从头部静默截断 prompt、200 + system 指令没了（坑 5）→ 对策见 §1，另加探测 truncation check（快测 8k）。
- `/api/show`：`model_info` 与 `parameters` 常差 30 倍，小的才算数；`num_ctx` 默认 2048/4096 静默截断。
- JSON cue 位置：见 §1（坑 211）。
- 兼容层 `stream_options.include_usage` 可能没实现、usage 全 0（坑 8）。

### LM Studio／llama.cpp

- LM Studio `/models` 带 `max_context_length`；llama.cpp `/props`；`max_model_len` 置 high（探测 finding confidence high）。
- 两条连续 user 消息在严格交替 chat 模板上报错（坑 211）；超窗静默截断同 Ollama（坑 5）。

### Groq／硅基流动（仅 ASR）

- **正文所在**：16 §3。【实现】
- ⓐ OpenAI 兼容转写（multipart），地址与硅基流动 SenseVoice 语种在 16 §3；【实现】口径，OpenAI 兼容 ASR 无实测；chat 面未覆盖（§4）。

### 火山引擎 openspeech（豆包录音识别极速版）

- 与火山方舟 `ark` base 无关：host `openspeech.bytedance.com`、独立鉴权头；成败在 `X-Api-Status-Code` 头、HTTP 恒 200、缺头按失败（坑 122）【实现】。

### ASR 专营：Deepgram、ElevenLabs、CAMB AI、Gladia、小米 MiMo、302.AI

- **正文所在**：16 §10.2。【实现 2026-09，原 pyVideoTrans】
- 各自 SDK／私有协议，16 §10.2 渠道速查表；流式／实时 ASR（WebSocket）本库没有。

---

## 4 本表尚未覆盖的平台

以下平台（原 `15-vendor-index.md`「本库尚未覆盖」节，2026-09-28 并入本节；完整的待核实清单含优先级与测法在 `31-open-questions.md` §3「本库尚未覆盖的厂商／协议」）一律按「未知、需核实；先按 01 §2 判族，再用该族底座的全部检查项去审；厂商特有的不从相邻厂商类推；核实后按 `30-knowledge-ingestion.md` 写回并补进本表 §2 / §3 与 22 对应家族节」处理。

Kimi／Moonshot（本表 Kimi 行仅一条 `json_object` 事实）；智谱 GLM 的图像／视频模型；智谱 Coding Plan 编程端点的完整实测（本表只有「按量 key 200、扣套餐」）；Mistral；Cohere；Groq 的 chat 面（本表只有 ASR 面）；硅基流动的 chat 面（本表只有 ASR 面）；Together；Fireworks；Bedrock Converse 的 body（第五种 body，要么写第五个 adapter 要么明确不接）；OpenAI 兼容 ASR 的实测（16 §3 全是文档与实现口径）；流式／实时 ASR（WebSocket，本库没有）；Azure 的 `api-version` 细节；Seedance 视频（火山方舟套餐不含，实测 404，需按量 key；body 形状未覆盖）；OpenAI 官方收不收 ① `video_url`（02 §1 表后，未量）；火山方舟按量付费收不收 ① `video_url`（未量；按量对话面整体未实测）。
