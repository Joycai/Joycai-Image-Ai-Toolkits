# 31 · 待核实清单（知识库的负空间）

本表列出本库**没有**的东西：没测过的组合、证据等级不够的结论、文档与实测冲突还没定论的格子、证据超过半年或没标日期的旧事实。目的有两个：下次有 key、有时间时知道先测什么；审查项目时撞到这里列的组合，一律按「未知」处理，不做对错判定。

**怎么用**

1. 审查时遇到列在这里的（平台 × 面 × 模型）组合，报告里一律写「待核实」，附本表编号；不从相邻厂商、相邻渠道、相邻面类推。
2. 有条件实测时按 §1 的优先级挑：P1 先测，同级里先测「怎么测」一栏成本最低的（非法参数零成本探测、`Say OK.` 对照输入 token）。
3. 核实后把结论（带日期、证据等级）写回「相关篇章」列指向的那一篇，再把本表对应行删掉；流程见 `30-knowledge-ingestion.md`。文档与实测冲突定论后，原篇按「文档：…；实测：…」记法保留冲突痕迹。

记法沿用全库：①②③④ 见 `01 §2`；🖼 出图／🎬 视频／🎤 ASR；【实测 日期】【文档 日期】【实现】【未验】⚠ 见 SKILL.md。表格单元格内不出现竖线，用「／」。

---

## §1 优先级说明

| 级 | 定义 | 典型例子 |
| --- | --- | --- |
| P1 | 常用组合但完全未测：库里没有任何实测证据，能力格写 `unknown` 或故意留空 | 火山方舟按量 base 的对话面；百炼 Responses 面 PDF |
| P2 | 有文档口径、无实测：库里按【文档】或【参考实现】写，项目行为不同时只能写「与文档口径不一致」 | DeepSeek ① 面 `thinking:{type:"disabled"}`（④ 面已于 2026-09-28 验过）；Sora／Veo body |
| P3 | 只有【实现】口径：事实来自移植进来的代码（pyVideoTrans、参考实现），本库未独立复核报文 | ASR 专营六家；Midjourney 代理协议 |
| P4 | 已测但证据日期早于 2026-03-28（相对 2026-09-28 超过半年）或「日期未标」，需复核 | Ollama／LM Studio 超窗截断；智谱 `fps` 样本 |
| P5 | 文档与实测冲突、或两次实测互相矛盾、或归属（网关 vs 上游）分不出，尚未定论 | glm-5.2 `none` 关不掉；Gemini `thinkingBudget:0` 经网关照想 |

一行同时命中两级时取更高级（P1 最高），另一级写在「现状」里。

---

## §2 主表

列说明：**待核实的问题**写清发什么、看什么；**现状**写库里现在怎么写的与证据等级；**来源**只补「相关篇章」列之外的出处（11 篇坑号、20 §4「本表尚未覆盖的平台」节），没有就写 `—`。

### P1 · 常用组合但完全未测

| 编号 | 级 | 平台 | 面 | 模型 | 待核实的问题（怎么测） | 现状 | 相关篇章 | 来源 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OQ-001 | P1 | 火山方舟 · 按量付费 base（`/api/v3`） | ① | doubao-seed-2.0-pro／2.0-lite／2.0-mini／2.1-turbo | 对话面整体：思考控制（`reasoning_effort` 七档、`thinking:{type}`）、`json_schema` 守不守、强制 `tool_choice` 是否跳过思考、PDF 三形态（`file_data`／`file_url`／`file_id`）、`max_tokens` 上限、是否注入。测法：按量 key 打 `https://ark.cn-beijing.volces.com/api/v3/chat/completions`，原样跑套餐上的 39 条 live 用例，逐格与套餐结果比对，不一致的格子按量单独记 | 01 §9.3 能力格记 `unknown`，明文「不抄套餐的」；手头只有套餐 key，全部实测【2026-09-18／09-23／09-28】都在 `/api/plan/v3` | 01 §9.3；03 §3.2；04 §2；05 §5 | 20 §4 |
| OQ-002 | P1 | 火山方舟 · 按量 | ① | 豆包 2.x | ① `video_url` 收不收；`fps` 是否改账单（套餐 mini 上 4 秒片段两种拼法都不改，可能低于最少帧数，坑 208 未定论）。测法：先红后蓝 640×480、≥10 秒纯色片段，三组请求（不带片段／带片段／带片段 + `fps:1`，`fps` 片段旁与 `video_url.fps` 各一次），比 `prompt_tokens` 与答案 | 02 §1 表后「未量」；坑 208「未定论」；平台格对按量不发 | 02 §1；11 坑 206–208 | 11 坑 208；20 §4 |
| OQ-003 | P1 | 火山方舟 · 按量 | ②④ | 豆包 2.x | ② `{type:"web_search"}` 不写 `sources:["doubao"]` 是否落到按次计费的「联网内容插件」；④ `web_search_20250305` 与 ②④ 其余能力（思考、schema、强制工具、PDF）。测法：按量 key 同一问题两次（带／不带 `sources`），比 `usage.tool_usage_details.web_search` 下的键名与控制台账单条目；④ 跑套餐 ④ 用例集 | 05 §5【未验】；「按量 key 的 ②④ 能力未知」 | 05 §5；01 §9.3 | — |
| OQ-004 | P1 | 火山方舟 · 按量 ↔ 套餐 | ①② | 豆包 2.x | 按量 key 上传的 `file_id` 能否被套餐 key 引用。测法：按量 key `POST /api/v3/files` 传秘密词 PDF，套餐 key 在 ① `{type:"file",file:{file_id}}` 与 ② `input_file.file_id` 引用同 id，看 404 `ResourceNotFound` 还是答出秘密词 | 01 §9.3【未验】；套餐 key 无上传入口，假 id 回 404【2026-09-23】 | 01 §9.3；02 §1 | — |
| OQ-005 | P1 | 火山方舟 Coding Plan | ① | doubao-seed-2.1-turbo | `encrypted_content` 同一 modelId 换渠道（套餐↔按量↔中继）能否解密；篡改密文报不报错。测法：套餐 key 工具轮拿到 `encrypted_content`，第二轮分别在按量 base 与一台中继上原样回灌；另一组把密文末尾改一位回灌；看 400 与否、`reasoning_tokens`、答案质量 | 03 §3.2 ⚠ 未测；只回摘要不报错（静默降级第四种载体） | 03 §3.2；03 §5 | — |
| OQ-006 | P1 | 火山方舟 Coding Plan | ④ | doubao-seed-2.1-turbo | 删 `signature` 回灌是否让推理变差（已知三种回传都 200）；④ `signature` 与 ① `encrypted_content` 是否同一密文（仅前缀 `dj…` 相同的推测）。测法：同一工具轮原样／删签名各 5 次比答案质量与 `output_tokens`；把 ④ 签名塞进 ① `encrypted_content` 回灌看是否被接受 | 03 §3.2 ⚠ 推测；坑 137 | 03 §3.2；03 §5 | — |
| OQ-007 | P1 | 火山方舟 Coding Plan | ④ | 豆包 2.0／2.1 | `output_config.effort` 只知不报错、效果未比。测法：同一难题 `low`／`high`／`max` 各 5 次，比 thinking 块长度与 `output_tokens` | 03 §3.2「不报错（效果未比 ⚠）」 | 03 §3.2 | — |
| OQ-008 | P1 | 火山方舟 · 按量 | 🎬 | Seedance（`doubao-seedance-1-0-pro-250528`、`-2.0`、`-1-0-lite-t2v-250428`） | 视频 body 形状、轮询状态词、结果 URL 有效期、usage 口径。测法：按量 key `POST /api/v3/contents/generations/tasks`，文生与首帧各一条最短时长，抄提交回包、`GET` 轮询字段、终态 usage | 14 §2 只有套餐 key 四个 id 全 404【2026-09-18】；body 未覆盖 | 14 §2；01 §9.3 | 20 §4 |
| OQ-009 | P1 | 火山方舟 · 按量 | 🖼 | doubao-seedream-5.0-flash | 能力表全按文档；流式支不支持（能力表无流式列，pro 不支持、lite／4.5／4.0 支持）；按量实测为零。测法：按量 key 先发 `size:"1x1"` 零成本看 400 `InvalidParameter`／404；再 `stream:true` 看 400 `param:"stream"` 还是 SSE `event:` 行 | 13 §4.1【文档 2026-09】；套餐三种拼法 404【2026-09-23】 | 13 §4.1 | — |
| OQ-010 | P1 | New API 类中转 | 🖼 | Seedream 5.0 lite／4.5／4.0 | 中转是否透传出图 SSE。测法：中转上同一 `stream:true` body，看 200 时 body 首行是 `event:` 还是 JSON，或直接 400 | 13 §4.1「中转是否透传 SSE 未知」；参考实现只对官方渠道发 `stream` | 13 §4.1 | — |
| OQ-011 | P1 | 阿里百炼 DashScope | ② `/compatible-mode/v1/responses` | 千问（qwen3.x） | (a) `input_file` PDF：文档说不支持，能力表故意不写 `false`；(b) `text.format`／`text.verbosity`：文档无 `text` 字段，报错还是忽略；(c) `reasoning_text.delta` 与明文 `summary` 回传的实际形态（文档说无 `encrypted_content`）。测法：秘密词 PDF `input_file.file_data`；`text.format: json_schema` 用 schema 与 prompt 冲突的 enum；工具轮回灌 reasoning 条目看 400 与质量 | 01 §9.2「上游做成作者声明的数据」第 7 条：保留出入待实测；04 §5.1【未验】；03 §7.2／§7.3【文档】；② 面服务端工具已实测【2026-09-17】 | 01 §9.2；03 §7.2；04 §5.1 | — |
| OQ-012 | P1 | OpenAI 官方 | ① | GPT-5.x | ① `video_url` 收不收。测法：官方 key，先红后蓝片段，看 4xx 原文或 200 + `prompt_tokens` 差 | 02 §1 表后「未量」；平台格不发 | 02 §1 | 20 §4 |
| OQ-013 | P1 | 智谱 BigModel · Coding Plan | ① `/api/coding/paas/v4`、④ `/api/anthropic`、② `/api/v1` | glm-5.x／4.x | 三个编程端点完整能力：思考控制（④ 面已知：4.7 默认不想、5.3 系默认想且 `disabled` 400、4.6 真关【2026-09-28】；4.6 默认值、4.7 的 `disabled`、5.2／5／5.1 全未测）、`json_schema`、强制工具、读图、`max_tokens` 上限；② `GET /api/v1/models` 只列的 3 个模型是哪三个（`slug`）。测法：同一按量 key 把按量端点的 11 款用例集分别打三个前缀；抄 `/api/v1/models` 的 `models[].slug` | 01 §9.4 只到「按量 key 200，但扣套餐」【2026-09-19】+ ④ 思考补测【2026-09-28，每条一次】；20 §4 列为未覆盖 | 01 §9.4；03 §3.1、§3.5 | 20 §4 |
| OQ-014 | P1 | 智谱 BigModel | ① | glm-4.6／4.7／5／5-turbo／5.1／5.2／5.3 系 | 关思考时 `usage.completion_tokens_details.reasoning_tokens` 给 0 还是缺席（已知 4.5-air 从不给；glm-5／4.6／4.5 关时缺席）。测法：11 款各发 `thinking:{type:"disabled"}` 一次，抄 `completion_tokens_details` | 03 §3.1 只列三款 | 03 §3.1 | — |
| OQ-015 | P1 | New API · `[官key量]` 渠道／`[官key]` 档 | ④①② | claude-opus-4-6／opus-5；gpt-5.6-sol | 当天两端点 502 `Upstream request failed`、GPT 503 `No available channel`，能力全空；是否长期无线路。测法：隔日先打 `Say OK.`；通了先发 `output_config.effort:"bogus"`（② 发 `reasoning.effort:"bogus"`）分正向／反代，再跑 `live.relay-kiro.test.ts` 31 条与 ② 45 条 | 01 §9.2 画像 `official` 无任何格子，选它只表示「已分类」；06 §5「当时没线路」 | 01 §9.2；06 §5 | — |
| OQ-016 | P1 | New API · Kiro 渠道 | ①④ | Claude Sonnet（`[kiro]claude-sonnet-*`） | 按推断收进 `refuses` 名单，未测。测法：跑 `live.relay-kiro.test.ts` 31 条，逐格比对 opus-4-6／opus-5 结果 | 01 §9.2 第 5 条「⚠ 推断（有意例外，理由已写）」 | 01 §9.2 | — |
| OQ-017 | P1 | xAI 官方 | ① legacy | grok-4.3／4.5／4.6 | ① 面除 `video_url` 400 外无实测：`reasoning_effort` 档位、`response_format`、`tools`、PDF `file`；`GET /v1/models` 形态。测法：grok-4.3 ① 各一发；抄 `/models` 回包 | 01 §9.1 ① 官方标 Deprecated 仍作 legacy；仅 `video_url` 400【2026-09-28】 | 01 §9.1 | — |
| OQ-018 | P1 | xAI 官方 | ② | grok-4.5／4.6 | 结构化输出 `text.format` 守不守、函数工具／并行／具名 `tool_choice`。测法：冲突 enum schema；两个函数工具并行题 | 01 §9.1 表 B1 结构化、工具两格 ⚠ | 01 §9.1；04 §5 | — |
| OQ-019 | P1 | OrcaRouter · ② 原样线路（`store:true`） | ② | gpt-6-luna／sol | 原样线路上的结构化、函数工具、reasoning 回灌义务、`include` 行为。测法：`store:true` 下跑 ② 全套（schema 冲突、并行工具、删 `encrypted_content` 回灌） | 01 §9.5 只记分流触发条件与「没有任何花费字段」【2026-09-26】 | 01 §9.5 | — |
| OQ-020 | P1 | OrcaRouter · 免费档 | ①②③④ | — | 免费档具体模型与限制（2026-09-03 第七个样本只提「探测与免费档」与 402 闸）。测法：`GET /v1/models` 过滤价格为 0 的条目；各打一次看 429／402 与限额响应头 | 01 §9.5 未给 | 01 §9.5 | — |
| OQ-021 | P1 | Google AI Studio 官方（`generativelanguage.googleapis.com`） | ③ | Gemini 3.8 Flash／3.1 Pro／2.x | 3.8 Flash 的档位量、工具轮、PDF 实测经 OrcaRouter 即 Vertex；AI Studio 上只直验了档位值大小写（`"low"`／`"LOW"` 都 200、`"lowest"` 400）【2026-09-28】，其余未直验：`MINIMAL` 400、`thinkingBudget:0`、`googleSearch`／`urlContext`／`codeExecution` 形状与计费、与函数工具同发（尤其 Gemini 2.x）、流式 usage 是否每块都带（文档说都带，Vertex 只末块）、空 `{text:""}` 回灌、缺签名报法、`inline_data` 两种拼写；另：3.8-flash `low` 答一词时 usage 不带 `thoughtsTokenCount`——是「没想」还是「不报」未定。测法：官方 key 复跑 OrcaRouter ③ 第十八个样本用例；3.8-flash 换一道要想的题看 `thoughtsTokenCount` 出不出 | 01 §9.5「不照搬给 AI Studio」；03 §2（AI Studio 直连仅档位大小写【2026-09-28】）；05 §5「未实测、照发」；Gemini 2.x 同发问题【未测】（有意接受的风险） | 01 §9.5；03 §2；05 §5；02 §3.2 | 11 坑 222 |
| OQ-022 | P1 | Google（Vertex 经 OrcaRouter） | ③ | Gemini 3.8 Flash | `googleSearch` 回报的 `vertexaisearch` 跳转 `uri` 能用多久。测法：记录 uri，1 小时／24 小时／7 天后 GET 看跳转还是 4xx | 05 §5 ⚠ 未测 | 05 §5 | — |
| OQ-023 | P1 | OpenAI／xAI（经中转与网关） | ② | GPT-5.4／5.5／5.6、Grok | 回传缺失四种（原样／删 reasoning／删 `encrypted_content`／只回裸 `function_call`）都 200 且答对，对质量的实际影响未量化。测法：多步工具题各 10 次，四种回传比正确率与 `reasoning_tokens` | 02 §7.3「代价只在质量」 | 02 §7.3 | — |
| OQ-024 | P1 | 百炼／智谱／DeepSeek／GPT（中转）／Claude（OrcaRouter） | ①④ | qwen3.x、glm-5.x、deepseek-flash、gpt-5.6-sol、Sonnet 5 | 温度收敛性只测了 MiniMax-M3 与火山 ④／① mini；其余模型关思考时温度是否生效未测（GPT ① 发 0.5 都 200、无回显，格子不写）。测法：有限答案题 ×2、每档（不发／`0`／`0.01`／`0.3`／`1`）20 次，`0` 单列 | 06 §8 第 13 条只两个例子；01 §9.2「上游画像扩到 GPT」：GPT ① 温度不写格子 | 06 §8；03 §3.4 | — |
| OQ-071 | P1 | 火山方舟 · `/api/coding` 前缀 | ④ `https://ark.cn-beijing.volces.com/api/coding`、① `/api/coding/v3` | 豆包 2.x | Coding Plan 接入文章（`volcengine.com/article/38136`）给的前缀是 `/api/coding`，本库全部套餐实测在 `/api/plan`：两者是两个套餐、还是同一套餐改过名；`/api/coding` 上的 ④ 面是否与 `/api/plan` 的 ④ 同一套行为（温度 `0` 当未设、签名不校验、`disabled` 真关）。无 key 探四条候选路径全 401，鉴权先于路由。测法：套餐 key 打 `/api/coding/v1/messages` 与 `/api/coding/v3/chat/completions` 各发 `Say OK.`，401／404／200 三种各定一条结论；200 则复跑 `/api/plan` 的 ④ 用例集逐格比对 | 20 §3 火山套餐节只记「文档 + 无 key 探测，不要套用 `/api/plan` 结论」【2026-09-28】 | 20 §3；01 §9.3；03 §3.4 | — |
| OQ-073 | P1 | 阿里百炼 DashScope | ④ `/apps/anthropic` | glm-5.3（托管） | 不发 `thinking` 时的默认值未测（来源表格留空）；已知 `disabled` 400 点名 `enable_thinking`；文档默认表说 glm 系默认开。测法：不发 `thinking` 一次，看有无 thinking 块与文本；再发 `output_config:{effort:"low"}` 对照智谱自家 ④ 的「200 无 thinking 块」 | 03 §3.5 表该格为「—」【2026-09-28】 | 03 §3.5 | — |
| OQ-074 | P1 | 阿里百炼 DashScope | ④ `/apps/anthropic` | kimi-k2.6（托管） | 不发 `thinking` 与 `disabled` 都回文本与签名都空的 thinking 块、显式 `enabled` 才有文本【2026-09-28】——「显式 `enabled` 才有文本」是否等于「默认关」（文档默认表：k2.6 默认关）：空块是「没想」还是「想了但不给看」（对照 Claude `omitted`）。测法：同一道要想的题，不发／`disabled`／`enabled` 各 3 次，比 `output_tokens` 与 `usage` 里有无思考计数；有计数而文本空 = 想了不给看 | 03 §3.5、§4.1 记「内容上没想」，未从 usage 侧证实 | 03 §3.5；03 §4.1 | 11 坑 218 |

### P2 · 有文档口径、无实测

| 编号 | 级 | 平台 | 面 | 模型 | 待核实的问题（怎么测） | 现状 | 相关篇章 | 来源 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OQ-025 | P2 | DeepSeek 官方 | ① | deepseek-flash／推理系 | ① 面全部为文档口径：`thinking:{type:"disabled"}` 真关（Joycai 2026-09-05 按文档修复、① 未实测——**④ 面已验真关**【2026-09-28】，① 面同一字段仍未验）；`reasoning_effort:"none"` 被无视照想；回传义务两方向 400（有工具轮不回传 400、无工具轮携带 400，「新版部分改为忽略但不可依赖」）；`prompt_cache_hit_tokens`／`_miss_tokens` 顶层且 `prompt_tokens` 已含命中；`json_schema` 不支持；`medium` 折进 `high`。测法：各一发，抄 `reasoning_tokens`、400 原文、usage 键名 | 03 §2／§5、04 §2、06 §1【文档 2026-08】；`video_url` 422【2026-09-28】；④ 面思考【2026-09-28】（03 §3.5） | 03 §2；03 §3.5；03 §5；04 §2；06 §1 | — |
| OQ-026 | P2 | Anthropic 官方直连（`api.anthropic.com`） | ④ | Claude Sonnet 5／Opus 5.5／Fable 5.1／4.6+／≤4.5 | 所有 Claude 5 实测经 OrcaRouter（请求侧被重序列化），官方口径未直验：思考开着 `temperature≠1` 400；未知顶层键 400；`output_config.effort:"bogus"` 400 原文；`output_config.format` 拒绝报文（非法关键字／递归／缺 `schema`）至今无样本，降级判据「报文以字段路径开头」是推测；`display` 默认 `omitted` 文本空但全额计费；≤4.5 `budget_tokens ≥ max_tokens` 400；`count_tokens` 形态。测法：官方 key 逐项发非法值抄 400 原文；不发 `display` 看 thinking 文本与 `thinking_tokens` | 01 §2、03 §3、04 §2【文档／参考实现】；实测样本仅 Sonnet 5／Opus 5.5／Fable 5.1 经网关【2026-09-26／09-28】 | 01 §2；03 §3；03 §3.4；04 §2；06 §2 | — |
| OQ-027 | P2 | OpenAI 官方直连（`api.openai.com`） | ①② | GPT-5.x、o1-pro／codex 系／computer-use | 所有 GPT 实测经 New API／OrcaRouter；官方未直验：② `store:false` 不发 `include:["reasoning.encrypted_content"]` 是否仍附 `encrypted_content`；Responses-only 模型走 ① 的失败形态；① `web_search_options` 形状；未知顶层参数 400；注入／回显／`max_output_tokens` 执行。测法：官方 key 各一发 | 03 §7.3「未经官方 key 验证，参考实现暂不发」；01 §8.1【文档 2026-08】 | 03 §7.3；01 §8.1；05 §5 | — |
| OQ-028 | P2 | OpenAI 官方／xAI／Google | ②③ | GPT-5.4+、Grok、Gemini | 原生工具按需加载：`defer_loading`／`tool_search`／`namespace`／`additional_tools`、下一轮回传 `tool_search_output` 形状未全实测；xAI 应用侧插入定义与回传义务未见；③ `defer_loading` 整个被拒仅第三方报告。测法：官方 key 声明 20 个 `defer_loading:true` 工具 + `tool_search`，两轮抄条目类型；故意不回传看工具是否消失；③ 发 `defer_loading` 抄 400 | 05 §7【文档 2026-09】；只有 xAI 403【2026-09】是实测 | 05 §7 | — |
| OQ-029 | P2 | 阿里百炼 DashScope | ① compatible-mode | Qwen3-Max／Plus 商业款、Qwen3.5+、Qwen3.7+、开源款 | 思考控制文档口径：商业款默认关、`enable_thinking` 顶层；3.5+ 默认开；3.7+ 直接收标准 `reasoning_effort`（与 `thinking_budget` 互斥）；思考开时 `tool_choice` 只 `auto`／`none`；部分开源模型思考模式强制 `stream:true`。测法：三代各发 `reasoning_effort`、具名 `tool_choice` + `enable_thinking:true`、非流式思考，抄 400 原文与 `reasoning_content` | 03 §3 switch【文档／参考实现】；坑 9 | 03 §3；04 §4 | 11 坑 9 |
| OQ-030 | P2 | 阿里百炼 DashScope | ④ `/apps/anthropic/v1/messages`；私有面；① | 千问 ④ 面「模型子集」的完整名单；Qwen-Audio；qwen3.8-max | ④ 面完整名单：已验到 qwen3.8-flash／3.7-flash／3.5-plus／qwen-turbo 与托管的 MiniMax-M2.5／glm-5.3／kimi-k2-thinking／kimi-k2.6／deepseek-v4-pro【2026-09-28】，其余千问 id（含 qwen3.8-max）未逐个打；④ 面除思考外的能力（结构化、工具、读图、PDF）未测；Qwen-Audio 私有面细节；`qwen3.8-max` ① PDF `{type:"file",file:{file_data,filename}}` 镜像「仅此款」（文中陈述、无日期）。测法：④ 面对全部千问 id 发最小请求收 400 `does not exist` 名单；qwen3.8-max 与 qwen3.5-plus 各发秘密词 PDF | 01 §8.1【文档】+ ④ 面思考实测【2026-09-28，每条一次】（03 §3.5）；02 §1【文中陈述】 | 01 §8.1；03 §3.5；02 §1 | — |
| OQ-031 | P2 | MiniMax | ①④ | MiniMax-M3 | 除温度、④ 关闭档与未知值、① 交错思考回传【2026-09-28】、`base_resp`／砍档／拒收自发块【2026-08】外：结构化输出、函数工具形状、多模态输入未测；① `<think>` 内联已由 2026-09-28 回传实测侧面证实（M3 默认内联、不出 `reasoning_content`）。测法：schema 冲突用例；图片／PDF 各一发 | 01 §8.1【文档 2026-08】；03 §3.5、§5【实测 2026-09-28】；03 §6【参考实现】 | 01 §8.1；03 §3.5；03 §6；04 §2 | — |
| OQ-032 | P2 | OpenRouter 本身 | ①② | 任意 | 库内所有「OpenRouter 形态」指纹（`gen-…` id、`provider`、`native_finish_reason`、`usage.cost`／`is_byok`、`reasoning_details[]`、② `msg_tmp_`／`fc_tmp_`、`summary` 改写）都在 OrcaRouter 上看到；OpenRouter 自身只知 `/models` 带 `context_length`、SSE 体内 error「routinely」为经验。测法：openrouter.ai key 打 ①② 各一发抄回包与 `/models` | 20 §3 OpenRouter 节【文档；指纹经 OrcaRouter 实测 2026-09-26】 | 20 §3 OpenRouter 节；01 §9.5；06 §2；06 §6 | — |
| OQ-033 | P2 | Google | ③ | Gemini 3.1 Pro | 档位只有 `low`／`medium`／`high`（无 `minimal`）【文档】。测法：发 `thinkingLevel:"MINIMAL"` 抄 400 | 03 §2【文档】 | 03 §2 | — |
| OQ-034 | P2 | xAI | 🎬 | grok-imagine-video-1.5 | 720p／1080p 是否加价（标价页只写 $0.080/s，实测三条都 480p）。测法：同 prompt 1 秒各分辨率，比 done 回包 `usage.cost_in_usd_ticks` | 14 §2【未验】 | 14 §2；14 §3 第 8 条 | 11 坑 129 |
| OQ-035 | P2 | 火山方舟 | 🖼 | Seedream 5.0 pro／lite | 失败或被审核拦下的请求是否仍收输入图费（方舟文档「失败免费」）。测法：带 2 张参考图故意触发 `OutputImageSensitiveContentDetected`，对控制台账单 | 13 §7【未验】只能对账单 | 13 §7 | — |
| OQ-036 | P2 | 阿里百炼 DashScope | 🖼 同步 | z-image-turbo；qwen-image／-plus／-max 初代；wan2.7-image-pro；wan 系 | `z-image-turbo` 尺寸规则／参考图／计费／错误报法全未写；初代只收五个固定 `size` 为【文档 2026-09】⚠；`wan2.7-image-pro` 改图是否收 `"4K"`；wan `negative_prompt` 不支持是 400 点名还是静默忽略。测法：各发一次非法 `size` 抄 400 原文（零成本）；改图带 `"4K"`；wan 带 `negative_prompt` 看 400／回显 | 13 §4 表 ⚠ | 13 §4 | — |
| OQ-037 | P2 | 阿里百炼 DashScope | 🖼 异步 | wan2.7-image／-pro | 异步流程（`image-generation/generation` + `X-DashScope-Async: enable` → `GET /tasks/{id}`）状态词序列、URL 24h；出图 `Throttling`／RPM 数值未写。测法：提交一次记状态词与 URL 失效时间；并发打到 429 记 RPM 与 `Retry-After` | 13 §3／§4【文档 2026-08】；限流数值未写（ASR 侧约 100 RPM） | 13 §3；13 §4 | — |
| OQ-038 | P2 | OpenAI | 🖼 images-api | gpt-image-1；dall-e-3 | gpt-image-1 尺寸／质量枚举与单价、不回 `revised_prompt`、参考图上限 16；dall-e-3 逐项 `revised_prompt`。测法：官方 key 各一发，抄回显 `size`／`quality` 与 `usage.input_tokens_details.image_tokens` | 13 §4.2／§7【文档／实现】，只提回显与 $8/M vs $5/M | 13 §4.2；13 §7 | — |
| OQ-039 | P2 | OpenAI；Google | 🎬 | Sora；Veo | Sora（`POST /v1/videos` multipart、`GET /v1/videos/{id}`、`/content` 要带鉴权头）与 Veo（`:predictLongRunning`、operations `{done}`）：body 字段、参考图、时长／分辨率、计费、保留期、取消均未写，未标实测。测法：各提交一条最短时长文生视频，抄 body、状态词、`/content` 响应头、账单 | 14 §2 各一行【文档】⚠ | 14 §2；14 §3 第 4 条 | — |
| OQ-040 | P2 | 阿里百炼 千问 | 🎬 | wan3.0 | 失败态 `FAILED` 与取消分支未走到；是否有取消端点。测法：违规 prompt 触发 FAILED 抄 `output.code/message`；核文档 cancel | 14 §2【实测 2026-08-29 只有成功链路】 | 14 §2；14 §3 | — |
| OQ-041 | P2 | MiniMax | 🎬 v2 | MiniMax-H3 | 未实测：纯文生视频 `ratio` 替换、首尾帧与 `reference_image` 互斥、`reference_image` role、取消 `DELETE`（仅 `queued` 免扣费）、`768P`。测法：各一发；取消在提交后立即 DELETE 看状态与账单 | 14 §2【实测 2026-08-29 首帧+尾帧】其余【文档】 | 14 §2；14 §3 第 5 条 | — |
| OQ-042 | P2 | 阿里百炼 DashScope | 🎤 ⓑ 同步 | qwen3-asr-flash；qwen-audio-3.0-asr-flash | 同步接口会不会给词级 `output.sentence.words[]`；单次上限「约 10 MB」与「3–5 分钟」两种说法的真实边界。测法：3 分钟与 6 分钟、9 MB 与 12 MB 各一段，看 413／400 原文与响应有无 `words` | 16 §4 未实测，代码只允许它不存在 | 16 §4 | — |
| OQ-043 | P2 | 阿里百炼 DashScope | 🎤 ⓒ filetrans | qwen3-asr-flash-filetrans；fun-asr／fun-asr-mtl／paraformer-v2 | `qwen3-asr-flash-filetrans`（`input.file_url` 单数字符串、`parameters.language`）只按文档实现；fun-asr 系说话人分离【文档称支持】。测法：一男一女英文对话走五步，看 `speaker_id` 与 `words[]` | 16 §5／§7 未实测 | 16 §5；16 §7 | — |

### P3 · 只有【实现】口径

| 编号 | 级 | 平台 | 面 | 模型 | 待核实的问题（怎么测） | 现状 | 相关篇章 | 来源 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OQ-045 | P3 | midjourney-proxy／New API `/mj/*` | 🖼 异步 | Midjourney | `POST /mj/submit/imagine` → `GET /mj/task/{id}/fetch`；回执 `code` 1／22；任务字段 `{status,progress,imageUrl,failReason}`；`base64Array` 垫图张数上限、计费单价均未写；日期未标。测法：一次 imagine 抄回执与轮询字段；垫图 2／5／10 张看拒收点 | 13 §2／§4.2【实现，日期未标】 | 13 §2；13 §4.2 | — |
| OQ-046 | P3 | OpenAI；Groq；硅基流动；302.AI；智谱；小米 MiMo；本地 WhisperX／Parakeet | 🎤 ⓐ | whisper-1；gpt-4o-transcribe／-mini／-diarize；whisper-large-v3；FunAudioLLM/SenseVoiceSmall；glm-asr-2512；mimo-v2.5-asr | ⓐ OpenAI 兼容 ASR 只有实现、无实测、无离线测试：`verbose_json` `segments[].start/end` 秒；`gpt-4o-*` 只 `json`／`text` 无 segments；`diarized_json` `speaker`；硅基流动时间码形态未写；GLM-ASR 限流码 `1302`／`1303`／`1214`；MiMo 走 ① `input_audio`。测法：同一段一男一女英文 wav 逐家发，抄时间码单位、`speaker`、限流码 | 16 §3／§10.2【实现】；20 §4 明示 OpenAI 兼容 ASR 未实测 | 16 §3；16 §10.2 | 20 §4 |
| OQ-047 | P3 | 火山引擎 openspeech；Google；Deepgram；ElevenLabs；CAMB AI；Gladia | 🎤 私有 SDK | volc.bigasr.auc_turbo；gemini-3.5-transcribe；scribe_v1／v2 等 | 证据仅【实现 2026-09，原 pyVideoTrans】，本库未复核报文：豆包成败看 `X-Api-Status-Code == 20000000`；Gemini `word_info` 时间是带 `s` 字符串；Deepgram `utterances`；ElevenLabs `words[]`；CAMB 整数语言 ID 默认英语；Gladia 三步。测法：同上音频逐家发，抄响应形状与错误码；豆包看响应头码 | 16 §10.2「据此判错前先实测」 | 16 §10.2；16 §10.3 | — |
| OQ-048 | P3 | OpenAI／New API 式中继／Google | 🖼 images-api、chat-image、gemini、imagen | dall-e-2；Imagen；Gemini 出图；nano-banana-pro 等 | dall-e-2 单张必须 `image`（单数）；中继 `/images/generations` 只认 Imagen（Gemini／Flux 挂 chat）；chat-image 各回包形状（裸链接／裸 base64／`images[]`／`image_b64_json`）与 `extra_body.google.image_config` snake_case；Imagen `:predict` 无 usage；Gemini 原生 `responseModalities`。测法：各发一次抄响应形状（只有「纯文本 part 数组 400」与 multipart Content-Type 有实测【2026-09-05】） | 13 §2／§4.2【实现】 | 13 §2；13 §4.2；13 §6 | — |
| OQ-049 | P3 | MiniMax | 🖼 | image-01／image-01-live | `/v1/image_generation`、`subject_reference`、`success_count` 为字符串、URL 24h、`base_resp` 两层失败【实现／文档】。测法：一发看 `metadata.success_count` 类型与 `base_resp` | 13 §4.2；坑 90／91 | 13 §4.2 | 11 坑 90、91 |
| OQ-050 | P3 | New API 类中继 | 🎬 openai-videos；🖼 ark | sora／grok-imagine／wan2.5／kling／hailuo；Seedream | 中继把视频收敛到 `/v1/videos`（同一模型 id 官方与中继走不同协议）；Seedream 在 ① 族中转默认 route `ark`（路径 = Images API）【实现】。测法：中继上各提交一次抄路径、状态词、body 差异 | 14 §4；01 §9.3【实现】 | 14 §4；01 §9.3 | — |

### P4 · 已测但超半年／日期未标，需复核

| 编号 | 级 | 平台 | 面 | 模型 | 待核实的问题（怎么测） | 现状 | 相关篇章 | 来源 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OQ-051 | P4 | Ollama／LM Studio／llama.cpp | ① | 本地模型 | 超窗从头部静默截断（先丢 system）返回 200【实测，日期未标】；`/api/show` 的 `model_info` 与 `parameters` 常差 30 倍、`num_ctx` 默认 2048／4096；空 `Authorization: Bearer` 被拒；Windows 打包版 403 要覆盖 `Origin`；连续 user 消息在严格交替模板报错【参考实现】。测法：当前版 ollama 发超 `num_ctx` 的 prompt（秘密词放 system）看答不答得出；抄 `/api/show` 两键；空 Bearer 与两条 user 各一发 | 01 §6、02 §5／§6、06 §6；坑 5、211 | 01 §6；02 §5；02 §6；06 §6 | — |
| OQ-052 | P4 | 智谱 BigModel | ① | GLM（读视频型号） | 收 `video_url`、忽略 `fps`——「更早的样本」日期未标。测法：glm-5.3-flash 带／不带 `fps:1` 比 `prompt_tokens` | 02 §1；坑 206／208 | 02 §1 | 11 坑 206、208 |
| OQ-053 | P4 | 经中转（New API 第十个样本）；Anthropic（平台未标）；xAI 官方 | ②④ | GPT；Claude；Grok | 未标日期的服务端工具数值：GPT ② 经中转一次搜索 45.7K 输入／112 s／首事件 54 s；Anthropic `web_search` 一题 8 次；xAI `web_search_call` 一次 6,851 输入、`open_page`／`find_in_page` 形状（`tool_search` 403 已标 2026-09）。测法：同题各跑 3 次记 `input_tokens`、耗时、首事件时刻、`num_requests` | 05 §5【实测】无日期 | 05 §5；06 §1 | — |
| OQ-054 | P4 | 经中转 | ② | GPT-5.4 | 默认 effort `none`、上限 `xhigh`、`max` 400 并列出合法值（【实测，responses.md】未标日期）。测法：任一 GPT-5.4 线路不带 effort 看回显；发 `max` 抄 400 | 03 §7.1；02 §7.3 | 03 §7.1 | — |
| OQ-055 | P4 | Google | ③ | Gemini 3.8 之前型号（含 2.5） | `functionCall` 无 id、`functionResponse` 靠函数名；丢签名 200 + `finishReason: MISSING_THOUGHT_SIGNATURE`；`thinkingBudget` 方言（2.5）；「有模型静默无视 `responseMimeType`」无模型名与日期。测法：gemini-2.5-flash 官方 key 各一发 | 02 §2.2、03 §3、04 §2、05 §3【参考实现／经验，未标日期】 | 02 §2.2；03 §3；03 §5；04 §2 | — |
| OQ-056 | P4 | Kimi／Moonshot | ① | Kimi | `json_object` 不查 "json" 字样：日期按同批智谱 2026-09-19 推断 ⚠，且是本库对 Kimi 的唯一事实。测法：发 `json_object` 无 json 字样看 400／200 | 04 §2 一句带过 | 04 §2 | — |

### P5 · 文档与实测冲突／归属未定论

| 编号 | 级 | 平台 | 面 | 模型 | 待核实的问题（怎么测） | 现状 | 相关篇章 | 来源 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OQ-057 | P5 | xAI 官方 | ② | grok-4.5／4.6 | 推理模型上发 `frequency_penalty`：文档说报错，实测 200 未报错。测法：② 与 ① 各发 `frequency_penalty:0.5` 看回显／400；隔月复测一次 | 01 §9.1 按实测记 | 01 §9.1 | — |
| OQ-058 | P5 | 智谱 BigModel | ① | glm-5.2 | `reasoning_effort:"none"`：文档说放弃思考，实测关不掉（与 `low` 想得一样多）。测法：同题 `none`／`low`／`thinking:{type:"disabled"}` 各 5 次比 `reasoning_tokens` | 03 §3.1 记「文档与实测冲突」；坑 94 | 03 §3.1 | 11 坑 94 |
| OQ-059 | P5 | 阿里百炼 DashScope | 🎤 ⓑ 同步 | qwen-audio-3.0-asr-flash；fun-asr-flash | `diarization_enabled: true`：文档称支持，实测 200、有文本、没有 `speaker_id`，片段放长到 2 分钟也无（两个口径都记）。测法：核对文档参数拼写与位置后重发一男一女英文 2 分钟片段 | 16 §7；坑 115 | 16 §7 | 11 坑 115 |
| OQ-060 | P5 | 阿里百炼 DashScope | ① | qwen3-max | `enable_code_interpreter:true` 思考关闭照常跑（文档说需思考开启）。测法：`enable_thinking:false` + 模型背不出的算题 3 次，看 `prompt_tokens` 涨幅与答案 | 05 §5「与文档不符」 | 05 §5 | — |
| OQ-061 | P5 | OrcaRouter（Vertex）／Google | ③ | Gemini 3.8 Flash | `thinkingBudget: 0` 照样思考（312 token）：网关重序列化把 0 当空值丢了，还是模型本身。测法：官方 key（见 OQ-021）同请求；网关上发 `thinkingBudget:1` 对照 | 03 §2「只能说经那台网关关不掉」；坑 171 | 03 §2 | 11 坑 171 |
| OQ-062 | P5 | OrcaRouter | ② | gpt-6-luna | `reasoning.effort:"minimal"` 被改写成 `low`：翻译层还是上游干的。测法：原样线路（`store:true`）发 `minimal` 看回显 | 03 §7.1 ⚠ | 03 §7.1；01 §9.5 | — |
| OQ-063 | P5 | OrcaRouter（Vertex）／Google | ③ | Gemini 3.8 Flash | 流末空 `{text:""}` part 回灌 400 `required oneof field 'data' must have one initialized field`：Vertex 本身还是网关把空串丢成 `{}`。测法：官方 key 回灌同一 part | 05 §3「只对网关成立」；坑 172 | 05 §3 | 11 坑 172 |
| OQ-064 | P5 | Anthropic（经 OrcaRouter 原样） | ④ | Sonnet 5 vs Opus 5.5 | 同一 PDF 请求 Sonnet 5 未带 `cache_control` 却记 1,630 `cache_creation_input_tokens`，Opus 5.5 没有——原因未明。测法：同请求各 3 次比 `cache_creation`；换 `web_search` 请求看是否服务端自动缓存所致 | 02 §1；坑 179／197 | 02 §1；06 §1 | — |
| OQ-065 | P5 | New API · Kiro 渠道 | ④ | claude-opus-4-6／opus-5 | 不带思考 + 流式的强制 `tool_choice`「随时间变」（16 次 1 次 → 5 次 3 次），无稳定结论。测法：每次 20 发，间隔一周两次 | 04 §4 判「时好时坏」不判不发 | 04 §4 | — |
| OQ-066 | P5 | New API · 第十个样本那台 `[Pro]`／`[Plus]` | ② | gpt-5.6-sol | 旧结论「sol 发 `max` 回显 `none` 且 0 推理 token」2026-09-24 另一台四上游未复现（保留、按当时当档）。测法：原台 `[Pro]`／`[Plus]` 发 `max` 各 3 次看回显与 `reasoning_tokens` | 03 §7.4 旧结论不删 | 03 §7.4；01 §9.2 | — |
| OQ-067 | P5 | New API · `[Azure]` 网关 | ② | gpt-5.6-terra | `reasoning.mode:"pro"` 回显 `pro`、同题输入 6,445（别的 1.2K），只测 1 次；账号池回显 `standard`。测法：同题各 3 次比输入 token 与 `reasoning_tokens` | 03 §7.4 不接 | 03 §7.1；03 §7.4 | — |
| OQ-068 | P5 | OrcaRouter | ②③④ | — | 文档说的上游错误 `type` `claude_error`／`gemini_error` 一次没出现，改写规则是否覆盖所有错误类型；② 原样线路「无花费字段」：04-06 抽取记「同一端点时有时无、触发条件未明」，01 §9.5 已给触发条件（`store:true` 或 `include` 含 `web_search_call.action.sources`），两处口径需对齐。测法：④③ 各触发 401／429／5xx 抄信封；② 两条线路各一发抄 usage | 06 §2 ⚠；01 §9.5 | 06 §2；01 §9.5 | — |
| OQ-069 | P5 | New API · CC／anti 渠道 | ①④ | claude-opus-4-6／opus-5 | 渠道背后上游未证实（推测 Claude Code 通道／Antigravity）；各渠道上游模型版本无官方 id 对应。测法：看消息 id 前缀、漏出的响应头（`anthropic-ratelimit-*`、`request-id`）、anti 注入的 30 token 原文、usage 形状 | 01 §9.2 画像 cc／anti 只按站主缩写建，证据等级仅 curl | 01 §9.2 | — |
| OQ-070 | P5 | 阿里百炼 OSS（filetrans 上传） | 🎤 ⓒ | — | Dart `http` `MultipartRequest` 被拒 `MalformedPOSTRequest`，手拼成功：三处差异（boundary 含 `+` `.`、part 头全小写、文件段先 content-type）哪一处触发未定位。测法：逐项只改一处重发 | 16 §5 | 16 §5 | — |
| OQ-072 | P5 | MiniMax 国内站 | ④ `api.minimaxi.com/anthropic` | MiniMax-M3／M2.7 | `thinking.type:"bogus"` 200 且开始想——只发了一次，是稳定的「非法值 = 开」还是碰巧落到默认（M2.7 本来就想）；`top_k:99999`、`temperature:2.5` 200 是否同样不生效。测法：M3（默认不想）上 `bogus` 5 次，看每次有无 thinking 块；再发 `thinking.type:"off"`、`""`、`null` 各 3 次看是否都当「开」 | 03 §3.5 记「200 而且开始想」，样本 1【2026-09-28】 | 03 §3.5；06 §2 | 11 坑 220 |

---

## §3 本库尚未覆盖的厂商／协议

以下厂商、协议或面在本库没有任何一行事实。接入或审查时：**先按 `01 §2` 判定协议族（只改 URL 与鉴权头能跑通就不是新族），再用该族底座（02–06 篇）的全部检查项去审；厂商特有的字段、默认值、错误码一律当「未知」，不从相邻厂商类推。** 核实后按 `30-knowledge-ingestion.md` 写回并从本节删行。

| 项 | 本库现状 | 接入时怎么做 |
| --- | --- | --- |
| Kimi／Moonshot chat 面 | 只有 OQ-056 一句（`json_object` 不查 json，日期推断） | 先按 01 §2 判族（预期 ①），再用 ① 底座检查项审；思考字段、结构化档位、工具砍档一律当未知 |
| Mistral | 无 | 先按 01 §2 判族，再用该族底座检查项审；厂商特有的一律当未知 |
| Cohere | 无 | 同上；Cohere 有自家 wire，先确认是否真是 ① 兼容，不是则按 12 篇配方 B 当新族 |
| Together | 无 | 先按 01 §2 判族（预期 ① 兼容），用 ① 底座检查项审；`include_usage`、`<think>`、思考字段拼写当未知 |
| Fireworks | 无 | 同上 |
| Groq chat 面 | 只有 ⓐ ASR 地址（OQ-046） | 先按 01 §2 判族，用 ① 底座检查项审；chat 面能力一律当未知 |
| 硅基流动 chat 面 | 只有 ⓐ ASR 一行（OQ-046） | 同上 |
| 智谱 GLM 图像／视频模型 | 无（对话与 ASR 有） | 出图按 12 篇配方 C 先判 route（13 §2），视频按配方 D；不从 GLM 对话面的事实类推 |
| AWS Bedrock Converse body | 只知是第五种独立 body（camelCase、SigV4），要么写第五个 adapter 要么明确不接（01 §2）；Bedrock 上的 Claude 经 New API AWSb 渠道 ④ 面已实测 | 按 12 篇配方 B 当新族；Bedrock 无 Anthropic 服务端工具、不收 URL 图片（01 §9.2 第 4 条）可沿用，其余当未知 |
| Azure OpenAI `api-version`、`/openai/deployments/{d}` URL、`api-key` 头 | 02 §5 明确「不做成 compat 选项，要做是另一族」；只知 `content_filter` 替代错误码【文档】；中转站里叫 `[Azure]` 的不是 Azure OpenAI | 按 12 篇配方 B 当新族或明确不接；不把 New API `[Azure]` 档的事实当 Azure OpenAI 的 |
| 流式／实时 ASR（WebSocket） | 无（16 篇只有 ⓐⓑⓒ 三种 HTTP 线格式） | 当新线格式，按 12 篇配方 E 建档；时间码来源、说话人、断线续传全部当未知 |
| Chat 面音频输入（① `input_audio`、③④ 音频 part） | 02／03 篇多模态列「音频未提及」；只有 MiMo ASR 用 ① `input_audio`（OQ-046） | 按族查官方参考页确认片段形状；平台格与 `video_url` 同法（实测收的点名、没测不发） |
| Seedance 视频 body | 见 OQ-008 | 拿到按量 key 先测 OQ-008，之后按配方 D 建档 |
| OpenAI Sora、Google Veo 细节 | 见 OQ-039 | 只有端点与状态词，按配方 D 补齐前当未知 |
| OpenAI 官方与火山按量 ① `video_url` | 见 OQ-012、OQ-002 | 平台格不发，直到实测 |
| OpenAI 兼容 ASR 实测 | 见 OQ-046 | 16 §3 全是文档与实现口径，按配方 E 发一小段真实音频确认再用 |

---

## §4 超期待复核

证据日期早于 2026-03-28 或「日期未标」的事实，按 SKILL.md「证据记法」规则在矩阵证据列尾加「⏳待复核」；复核后把新日期写回原篇。本节只列条目与复核方法，细节在 §2 对应行。

| 事实 | 现证据 | 复核方法 | 对应 OQ |
| --- | --- | --- | --- |
| Ollama／LM Studio 超窗从头部静默截断、`/api/show` 两键差 30 倍、空 Bearer 拒、Windows 403、连续 user 报错 | 【实测，日期未标】＋【参考实现】 | 当前版 ollama 发超 `num_ctx` prompt（秘密词在 system）看答不答得出；抄 `/api/show`；空 Bearer 与两条 user 各一发 | OQ-051 |
| Midjourney 代理协议（`/mj/submit/imagine`、`/mj/task/{id}/fetch`、`code` 1／22） | 【实现，日期未标】 | 一次 imagine 抄回执与轮询字段；垫图张数递增看拒收点 | OQ-045 |
| ASR 专营六家（豆包 openspeech、Gemini transcribe、Deepgram、ElevenLabs、CAMB AI、Gladia）与 302.AI、GLM-ASR、MiMo、本地 WhisperX | 【实现 2026-09，原 pyVideoTrans】——日期是移植日期，报文本身未复核 | 同一段一男一女英文 wav 逐家发，抄时间码单位、说话人字段、错误码 | OQ-046、OQ-047 |
| ⓐ OpenAI 兼容 ASR（whisper-1 `verbose_json`、gpt-4o-transcribe 无 segments、diarize） | 【文档 + 实现】，无实测、无离线测试 | 同上 | OQ-046 |
| 智谱 ① 收 `video_url`、忽略 `fps` | 【实测，日期未标】 | 带／不带 `fps:1` 比 `prompt_tokens` | OQ-052 |
| OpenAI ② 一次搜索 45.7K／112 s／首事件 54 s；Anthropic 一题 8 次搜索；xAI 一次 6,851 输入、`open_page` 形状 | 【实测】无日期 | 同题 3 次记 `input_tokens`、耗时、首事件时刻 | OQ-053 |
| GPT-5.4 默认 `none`、上限 `xhigh`、`max` 400 | 【实测，responses.md】无日期 | 不带 effort 看回显；发 `max` 抄 400 | OQ-054 |
| Gemini 旧型号无 `functionCall.id`、`MISSING_THOUGHT_SIGNATURE` 200、静默无视 `responseMimeType` | 【参考实现／经验】无模型名与日期 | gemini-2.5-flash 官方 key 各一发 | OQ-055 |
| Kimi `json_object` 不查 json | 日期按同批智谱 2026-09-19 推断 | 发 `json_object` 无 json 字样 | OQ-056 |
| 「Gemini 2.x 在 AI Studio 与函数工具同发内置工具」 | 【未测】（review 提过，有意接受） | 见 OQ-021 | OQ-021 |

以下日期在半年之内、不需复核，列出只为避免误判：MiniMax ① `base_resp`／砍档／拒收自发块【实测 2026-08】；中转 ① 畸形参数与空串 id【实测 2026-08-08】；① `content` part 数组镜像【实测 2026-08-14】；千问 wan3.0／MiniMax v2 视频【实测 2026-08-29】；OrcaRouter 402 闸【实测 2026-09-03】；xAI 出图与视频【实测 2026-09-21／22】。

---

## 附 · 不是实测项，但审查时容易误当「已做」的记录缺口

- **代码防法标【未实现】**（参考实现只在说明里写，未落代码）：中转站 ① 面把 `max` 夹到 `high`（03 §3.3）；② `text.format` 被丢时回显 `{type:"text"}` 的比对（04 §5.1、06 §4.1）；「① `response_format` 被丢应扩到整台 New API 的 Claude」只点名了 Kiro（04 §2）；Kiro 渠道「只在本轮带函数工具且流式时发 `web_search`」的按请求判定（05 §5）；学到的上限 7 天过期「这个数没有实测依据」（06 §9.4）。审查项目时这些不是判错依据。
- **记录本身的缺口**（无法靠实测补）：New API 两台中转站的 host／站名全文未记，只靠样本编号区分；OrcaRouter 目录 203 条里除八个标定模型外的条目未列；坑号对应内容只在 11 篇（抽取文件只给编号）。
