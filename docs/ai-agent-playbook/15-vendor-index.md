# 15 · 厂商索引：每家的事实散在哪里

这是一张目录，本身不写事实。审查或接入某一家时，先在这里找到它，再把列出的小节全部读一遍。
一家的事实通常分散在五六篇里：协议差异一篇、思考一篇、错误一篇、出图一篇……只读一篇，就会漏掉另外几个维度。

「证据」一列用 SKILL.md 定义的记法，是那几节里标注的最近来源。没标日期的，按「文档口径、日期未知」对待。

## 协议族（与厂商无关的底座）

| 族 | 端点形状与差异 | 思考 | 结构化 | 工具 | 错误 / usage | 坑 |
| --- | --- | --- | --- | --- | --- | --- |
| ① Chat Completions | 02 §1、§3、§4、§5 | 03 §2、§4–6 | 04 §2–4 | 05 §1–3 | 06 §1–2 | A、B 组 |
| ② Responses | 02 §7（请求骨架 / 事件 / 回传）；01 §3.1 为什么独立成族 | 03 §7 | 04 §5 | 05 §1、§5「② Responses 族」、§7 | 06 §4.1 回显比对 | G 组 |
| ③ Gemini generateContent | 02 §1、§2.2、§3.2 | 03 §2–5 | 04 §2 | 05 §1–2 | 06 §2（三层错误） | A、B 组 |
| ④ Anthropic Messages | 02 §1、§2.1、§3.2、§5 | 03 §2–5 | 04 §2（只有 cue） | 05 §1–6（续跑循环） | 06 §1（三桶 usage） | A、B 组 |

## 厂商与平台

| 厂商 / 平台 | 协议与面 | 事实所在 | 证据 |
| --- | --- | --- | --- |
| **OpenAI 官方** | ①、② 两张 chat 脸（部分模型只有 ②）；Images API；Sora 视频；`/audio/transcriptions` 转写 | 01 §8.1（Responses-only 模型）；02 §7（含 GPT-5.x 空 `final_answer` 收尾）；03 §7；04 §5；05 §5、§7；13 §2、§4.2「images-api」；14 §2；16 §3、§10.2（whisper / gpt-4o-transcribe / diarize）；坑 109 | 【实测 2026-09 经中转 + 文档】 |
| **Anthropic 官方** | ④；部署变体 Vertex / Bedrock | 02 §1、§2.1、§5；03 §3、§5；05 §5–7；06 §1；01 §2（Bedrock Converse 是另一族）；坑 1 | 【文档】 |
| **Google Gemini** | ③ chat（同一 wire 也出图）；Imagen `:predict`；Veo 视频 | 02 §2.2、§3.2；03 §2–5；06 §2；13 §2、§4.2「imagen」；14 §2 | 【文档】 |
| **xAI Grok** | ②（官方推荐；① 已标弃用）；Grok Imagine 出图（2.0：`quality` low/medium、`resolution` 1k/1.5k/2k、`usage.cost_in_usd_ticks` 报实扣；初代平价）/ 视频（1.5：$0.08/s，首帧与参考图各 +$0.01/张，done 回包报 ticks，`video.duration` 报实际秒数） | 01 §9.1；03 §7.1、§7.3；05 §5「② Responses 族」、§7（tool search 403）；13 §4.2「xai-images」（质量 / 分辨率 / 定价端点 / 参考图上限纠错）、§7（报价、输入图按张）；06 §1（第四种口径）；14 §2「xAI 实测」、§3.8；坑 66–67、123–129 | 【实测 2026-09-22 出图质量与计费、视频 1.5 计费；其余 2026-09】 |
| **DeepSeek** | ① | 03 §2（`none` 关不掉，要 `thinking:{type:"disabled"}`）、§5（回传义务分场景，两个方向都会 400）；04 §1–2；06 §1（缓存命中字段 `prompt_cache_hit_tokens`） | 【文档 2026-08】 |
| **阿里百炼 / 千问 DashScope** | chat 三张脸（① 兼容 / 私有三段式 / ④）；出图同步 + 异步；视频异步；服务端工具；语音识别两张脸（同步 multimodal-generation / `-filetrans` 异步） | 01 §8.1、§8.4；03 §3、§7；04 §4（tool_choice 砍档）、§5.1；05 §5「代码解释器」；13 §4（含「自由尺寸的规则」）；14 §2（wan3 视频链路实测）；16 §4–§9；坑 9、10、13、56–59、70、74–78、101–104、115–121 | 【实测 2026-09-19 出图信封与自由尺寸；实测 2026-09-17 服务端工具；实测 2026-09-13 ASR 两条路；实测 2026-08-29 视频；文档 2026-09】 |
| **MiniMax** | chat ① / ④ 两张脸（模型 id 相同）；`image-01` 出图；v2 视频任务；`<think>` 内联 | 01 §8.1、§8.3–8.4；03 §3、§6；05 §6；06 §2（`base_resp`）；13 §4.2「minimax」；14 §2（含 v2 视频实测）；坑 6、11、90、91、113 | 【实测 2026-08-29 视频全链路；其余文档 2026-08】 |
| **字节跳动火山方舟（豆包 / Seedream）** | ① chat；Seedream 出图（`ark` route，含流式与拆图层）；按量 / 套餐两个 base；另有 openspeech 的录音识别极速版（独立鉴权头） | 01 §9.3；03 §3.2（对话思考控制）；13 §4.1（含「流式出图」「拆图层的实测形状」）、§7（`usage.input_images`、首张免费、失败免费）、§8；14 §2（Seedance 套餐 404）；16 §10.2（ASR，【实现】）；坑 79–85、87、114、122 | 【实测 2026-09-18】 |
| **智谱 BigModel（GLM）** | ① chat 标准端点；同一把 key 另通 Coding Plan 的 ① / ② / ④ 编程端点（路径决定计费）；独立的网络搜索 / 网页阅读端点；`glm-asr` 转写 | 01 §9.4；03 §3.1；04 §2（`json_schema` 静默无视）、§4（砍档第三种变体）；05 §5「服务端工具归平台」；06 §2（`sensitive` / `network_error`、笼统文案）；16 §10.2（GLM-ASR 限流码，【实现】）；坑 94–100 | 【实测 2026-09-19，11 个对话模型】 |
| **New API 类中转站** | ①、②、③ 形状都有；`/mj/*` Midjourney | 01 §9.2（四种静默行为）；04 §5.1（显式 `strict` 丢 format）；06 §4.1；13 §4.2「经 chat 出图的中继」、§6；14 §4；02 §2.2（③ 面只认 camelCase）、§3.2（`content` 数组、usage 末块）；03 §4（空 `reasoning_content`）；05 §3（拼接参数、空串 id）；06 §5（402）；坑 62、105–112 | 【实测 2026-09 + 中继源码】 |
| **OpenRouter** | ① | 06 §2（SSE 体内 error 常见）、§6（`/models` 带 `context_length`） | 【文档】 |
| **Ollama / LM Studio**（本地） | ① | 02 §5（空 Bearer 被拒）、§6（Windows 打包版 403）；01 §6（超窗静默丢头部）；06 §6；坑 5 | 【实测，日期未标】 |
| **Azure OpenAI / Vertex / Bedrock** | 部署变体 | 01 §2；02 §5；06 §2（Azure 用 `content_filter` 代替错误码） | 【文档】 |
| **Midjourney（midjourney-proxy / New API `/mj/*`）** | 独立的异步出图协议 | 13 §2、§4.2「midjourney」 | 【实现，日期未标】 |
| **Groq / 硅基流动（仅语音识别）** | ⓐ OpenAI 兼容转写 | 16 §3（地址、SenseVoice 语种） | 【实现】 |
| **ASR 专营：Deepgram、ElevenLabs、CAMB AI、Gladia、小米 MiMo、302.AI** | 各自 SDK / 私有协议 | 16 §10.2 | 【实现 2026-09，原 pyVideoTrans】 |

## 本库尚未覆盖（审查时按「未知、需核实」处理）

Kimi / Moonshot、智谱 GLM 的图像 / 视频模型与 Coding Plan 编程端点的完整实测、Mistral、Cohere、Groq 与硅基流动的 chat 面、Together、Fireworks、Bedrock Converse 的 body、
OpenAI 兼容 ASR 的实测（16 §3 全是文档与实现口径）、流式 / 实时 ASR（WebSocket，本库没有）、
Azure 的 `api-version` 细节、Seedance 视频（火山方舟套餐不含，实测 404，需按量 key；body 形状未覆盖）。

遇到它们：
- 先按 01 §2 判定协议族，再用该族底座的全部检查项去审。
- 厂商特有的东西一律当「未知」，不要从相邻厂商类推。
- 核实后按 SKILL.md「维护知识库」写回本库，并补进上面的表。
