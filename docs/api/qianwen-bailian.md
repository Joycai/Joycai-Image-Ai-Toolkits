# 千问（阿里云百炼 / DashScope）协议标准

> 一家供应商、一把 key、一个 host（`dashscope.aliyuncs.com`），六条 wire：
> 3 种 chat + 图片同步/异步 + 视频异步。本文只写协议事实（本目录的规矩）；
> 本项目怎么路由这六条 wire，见
> [`../plans/2026-08-vendor-protocol-model-refactor.md`](../plans/2026-08-vendor-protocol-model-refactor.md)。
>
> **来源与可信度**：整理自 `platform.qianwenai.com` 的 API reference
> （2026-08 抓取）。该站曾被证实是二手镜像（见
> `2026-08-dashscope-native-image.md` §2.2 的 B 形状前科），实现前对
> 有 ⚠ 标记的条目按 help.aliyun.com 官方文档或实测复核。猜错会响
> （400 / 404），不会静默。

## 0. 总览：六条 wire 一张表

| # | Surface | 协议 | 路径（相对 host） | 同/异步 | 模型 |
| --- | --- | --- | --- | --- | --- |
| C1 | chat | OpenAI 兼容 | `/compatible-mode/v1/chat/completions` | 同步/SSE | Qwen 全系 + 三方（DeepSeek/Kimi/GLM/MiniMax）；**Qwen-Audio 除外** |
| C2 | chat | DashScope 私有 | `/api/v1/services/aigc/text-generation/generation`（纯文本）<br>`/api/v1/services/aigc/multimodal-generation/generation`（多模态） | 同步/SSE | Qwen 全系；**Qwen-Audio 仅此协议** |
| C3 | chat | Anthropic 兼容 | `/apps/anthropic/v1/messages` | 同步/SSE | Qwen max/plus/flash/turbo/coder/VL 子集 + 三方子集（§3） |
| I1 | imageGen | DashScope 图片·同步 | `/api/v1/services/aigc/multimodal-generation/generation` | 同步 | `qwen-image*` 全家族、`wan2.7-image(-pro)` |
| I2 | imageGen | DashScope 图片·异步 | `/api/v1/services/aigc/image-generation/generation` + 通用轮询 | 异步任务 | `wan2.7-image(-pro)`（qwen-image 系无异步页 ⚠） |
| V1 | videoJob | DashScope 视频·异步 | `/api/v1/services/aigc/video-generation/video-synthesis` + 通用轮询 | **仅异步** | `wan3.0-video`、`wan3.0-video-prime` |

通用轮询端点（I2 / V1 共用）：`GET /api/v1/tasks/{task_id}`。

**认证全线一致**：`Authorization: Bearer <DASHSCOPE_API_KEY>`。差异只有三个附加 header：

- C2 流式必须加 `X-DashScope-SSE: enable`（漏加拿不到 SSE，不报错）；
- I2 / V1 提交必须加 `X-DashScope-Async: enable`；
- C3 也接受 `x-api-key: <key>`（与 bearer 二选一，两个都发也不冲突）。

**产物有效期全线一致**：图片/视频结果 URL、`task_id` 均 **24 小时**。
拿到结果就得下载，存 URL 的一切消费一天后全部失效。

**错误信封两套**：

- C1（OpenAI 兼容面）：`{"error": {"message", "type", "code"}}` —— 共享的
  `decodeJsonBody` 信封检查直接认得。
- 其余全部（DashScope 原生）：顶层 `{"code", "message", "request_id"}`，
  成功响应 `code` 为空串/缺失 —— 判错依据是「`code` 非空」，不是「有没有
  status_code」（成功体里也有 `status_code: 200`）。任务失败时 `code`/`message`
  内嵌在 `output` 里。`DataInspectionFailed`（审核拒绝）必须保住结构化 code。
- 状态码：400 参数/审核 · 401/403 认证/欠费 · 429 限流（`Throttling`，可重试）
  · 5xx 服务端。几乎所有错误带 `request_id`，日志要落。

---

## 1. C1 — OpenAI 兼容 chat

- **POST** `{host}/compatible-mode/v1/chat/completions`；请求/响应/SSE 均为
  标准 OpenAI 形状，`messages` 四角色（system/user/assistant/tool）。
- **`max_tokens` 已废弃**，用 `max_completion_tokens`（含思维链）。
- 非标参数经 body 顶层直发即可（HTTP 层无 `extra_body` 概念，那是 Python SDK
  的包装）：`top_k`、`enable_thinking`、`thinking_budget`、`reasoning_effort`
  （`low`–`max` 五档）、`enable_search`、`tool_stream`、`vl_high_resolution_images`。
- 思考模型回包扩展字段 `choices[].message.reasoning_content`
  （DeepSeek 首创的 ① 族惯用扩展位）。
- usage：标准 `prompt_tokens`/`completion_tokens`，另有
  `prompt_tokens_details.cached_tokens`（显式缓存 `ephemeral_5m` 命中）。
- `n` 1–4；`response_format` 支持 `json_object` / `json_schema`。
- 图片输入：Qwen-VL 按 OpenAI 惯例 `content[].image_url`（URL 或 data URI）⚠
  未在该页展开，按 ① 协议现状即可。
- 模型注意：`qwen3.8-max` 思考模式建议温度 0.6；QwQ 系不要发 system 消息。

## 2. C2 — DashScope 私有 chat（三段式）

- **POST** 纯文本 `/api/v1/services/aigc/text-generation/generation`；
  多模态模型换 `/api/v1/services/aigc/multimodal-generation/generation`
  （与 I1 同路径，靠 model 区分）。
- 请求三段式：`{model, input: {messages: [...]}, parameters: {...}}`。
  `parameters` 关键项：`result_format` **必须设 `"message"`**（默认 `"text"`
  只回纯文本，多轮/工具都要 message 形状）、`stream` + header、
  `incremental_output`（true=增量，false=每帧累积全文 —— 解析器必须先看这个）、
  `max_completion_tokens`、`enable_thinking`、`tools`、`response_format`。
- 响应：`output.choices[].message`（content / `reasoning_content` /
  `tool_calls`），`finish_reason` 词表同 ①。
- **usage 命名不同**：`input_tokens` / `output_tokens` / `total_tokens`
  （不是 prompt/completion）—— 接入时要在协议层译成 ① 命名再发布，
  `LLMService._recordUsage` 只认 OpenAI/Google 两套键。
- 独占能力：Qwen-Audio 仅此协议可用。

## 3. C3 — Anthropic 兼容 chat

- **POST** `{host}/apps/anthropic/v1/messages`；SDK base_url 写
  `{host}/apps/anthropic`，**不要以 `/v1` 结尾**（客户端库自己拼 `/v1/messages`）。
- 请求/响应/SSE 均为标准 Anthropic Messages：`max_tokens` 必填、`system`
  顶层字段、content block（text / thinking / tool_use）、
  `stop_reason: end_turn|max_tokens|tool_use`、事件流 `message_start` →
  `content_block_*` → `message_delta`。④ 族的既有对接（含流式拼装与
  三改写）应当原样成立。
- thinking：官方拼写 `{type: "enabled"|"disabled", budget_tokens}`，要求
  `max_tokens > budget_tokens` → `ThinkingDialect.anthropicBudget`。
- usage：标准四桶（input/output/cache_creation/cache_read）——
  ④ 协议的三桶求和规则原样适用。
- 平台扩展：`output_config`（`effort` + JSON Schema 结构化输出），本仓暂不消费。
- **模型是子集**：Qwen max/plus/flash 各代、turbo、coder（qwen3-coder-next/
  plus/flash）、VL（qwen3-vl-plus/flash、qwen-vl-max/plus）+ 三方 20+
  （deepseek-v4-pro、kimi-k2.7-code、glm-5.2、MiniMax-M2.5 等）。
  图片输入按 Anthropic image block ⚠ 待实测。
- deepseek/glm 在此面上 `max_tokens` 与思考开销的扣减行为与 Qwen 不同
  （文档有专门备注）⚠ 接入三方时复核。

## 4. I1 — 图片·同步

- **POST** `/api/v1/services/aigc/multimodal-generation/generation`，
  无特殊 header。请求三段式，`input.messages` 仅**单轮** user 消息，
  `content[]` = text + image 混排（qwen 系与 wan 系的 body 细节有别，
  即旧方案里的 A/B 两种形状）。
- 结果：`output.choices[].message.content[].image` = 签名 URL（24h）。
  注意 qwen 系的 content 项只有 `image` 键，wan 系多一个 `type: "image"`
  —— 提图逻辑不得依赖 `type` 存在。
- usage 形状按系列不同（qwen 3.0 系 `output_width/height +
  input/output_image_count/type`；wan 系 `image_count + token 数 + size`），
  只透传不解析。

### 4.1 逐模型参数档（Layer 3 建表依据）

| 模型 | 输入图 | 文本上限 | `n` | `size` | 特有 |
| --- | --- | --- | --- | --- | --- |
| `qwen-image-3.0(-pro)` | 1–3 张，≤10MB，建议 384–3072px | 4500 tok | 1–6 | `宽*高`，512²–2048²，比例 1:8–8:1 | `prompt_extend_mode: direct\|agent`（agent 仅文生图） |
| `qwen-image-2.0(-pro)`（含日期版） | 同上 | 1300 tok | 1–6 | `宽*高`，512²–2048² | |
| `qwen-image-edit-max` / `-plus`（含日期版） | 同上 | 800 tok | 1–6 | 512–2048，自动取 16 倍数 | |
| `qwen-image-edit`（基础版） | 同上 | 800 tok | **仅 1** | **不支持 size** | 与同族行为不同，参数表必须单列 |
| `wan2.7-image(-pro)` | **0–9** 张，≤20MB，单边 240–8000px，比例 1:8–8:1 | 5000 字符 | 1–4（`enable_sequential` 时 1–12） | `1K`/`2K`（pro 另有 `4K`）或 `宽*高` | `enable_sequential`（组图）、`thinking_mode`（仅纯文生图）、`bbox_list`（编辑选区，每图 ≤2 框）、`color_palette`（3–10 个 `{hex, ratio}`） |

- 图片传入：公网 URL 或 `data:{mime};base64,{data}`。qwen 系收
  JPG/JPEG/PNG/BMP/TIFF/WEBP/GIF（GIF 取首帧）；wan 系收 JPEG/JPG/PNG/BMP/WEBP。
- qwen 多图编辑时输出宽高比由**最后一张**输入图决定。
- 公共 `parameters`：`prompt_extend`（默认 true）、`watermark`（默认 false）、
  `seed`（0–2147483647）。仅 qwen 系：`negative_prompt`（≤500 字符）、
  `enable_thinking`（默认 true，仅 prompt_extend 开着才生效）——
  wan2.7 的参数表**没有** `negative_prompt`，发了会 400 或被静默忽略 ⚠。
- wan2.7 的 `n` 默认 **4**，且按成功生成的张数计费 —— 不显式发 `n` 的
  客户端每次请求都花四倍的钱。

## 5. I2 — 图片·异步任务

- 提交：**POST** `/api/v1/services/aigc/image-generation/generation` +
  `X-DashScope-Async: enable`。**路径与 I1 不同** —— 同步请求打异步路径、
  或反之，报的是路径级错误而非「缺 async header」，排查时先看路径。
- body 与 I1 的 wan 形状**完全一致**（model / input.messages / parameters
  同一份），仅模型限 `wan2.7-image(-pro)`。`qwen-image*` 未见异步文档，
  按仅同步处理 ⚠。
- 回执：`output.task_id`（24h 有效）+ `task_status: "PENDING"`。
- 轮询：`GET /api/v1/tasks/{task_id}`，建议 **5–10s** 间隔。
  `task_status` 枚举：`PENDING → RUNNING → SUCCEEDED | FAILED`，
  另有 `CANCELED`、`UNKNOWN`（任务过期也报 UNKNOWN）。
- 成功结果与 I1 的 `output` 同形（`choices[].message.content[].image`）；
  失败时 `output.code` / `output.message`。

## 6. V1 — 视频·异步任务（仅异步）

- 提交：**POST** `/api/v1/services/aigc/video-generation/video-synthesis` +
  `X-DashScope-Async: enable`。模型：`wan3.0-video` | `wan3.0-video-prime`。
- **input 不是 chat 形状**：`input.prompt`（≤20,000 字符，可用「图1」「视频1」
  指代素材）+ `input.media[]`，media 项 =
  `{type: first_frame|last_frame|reference_image|reference_video|reference_audio|file|link, url}`
  （URL 或 Base64）。`prompt` 与 `media` 至少一个。
- `parameters`：`resolution`（`480P|720P|1080P`，默认 1080P）、`ratio`
  （`adaptive|16:9|4:3|1:1|3:4|9:16`）、`duration`（2–30s，默认 5，`-1` 智能）、
  `audio`（默认 **true**，生成音频）、`prompt_extend`、`watermark`、`seed`。
- 回执与轮询同 I2（同一个 `GET /tasks/{task_id}`、同一套状态枚举）。
- **成功结果是顶层扁平字段 `output.video_url`**（不是 choices 结构），
  另带 `orig_prompt`。失败时 `output.code`/`output.message`。
- usage：`video_count`(=1) / `duration` / `fps` / `SR` / `ratio`，**无 token**。
- 轮询间隔与 task_id 有效期该页未写 ⚠ —— 类推图片的 5–10s / 24h。
- **失败任务装在 HTTP 200 里**（`task_status: FAILED` + `output.code`），
  通用的错误信封检查抢不到它 —— 轮询方要自己实现状态机。图片异步同理。

---

## 7. 模型 × 协议矩阵

| 模型 | C1 | C2 | C3 | I1 | I2 | V1 |
| --- | --- | --- | --- | --- | --- | --- |
| qwen chat 全系（max/plus/flash/turbo/…） | ✅ 默认 | ✅ | 子集 ✅ | — | — | — |
| Qwen-Audio | ❌ | ✅ 唯一 | ❌ | — | — | — |
| Qwen-Omni（音频输出） | ✅ 唯一（`modalities`） | — | ❌ | — | — | — |
| 三方（DeepSeek/Kimi/GLM/MiniMax） | ✅ | ✅ | 子集 ✅ | — | — | — |
| `qwen-image*` 全家族 | — | — | — | ✅ 唯一 | ❌ ⚠ | — |
| `wan2.7-image(-pro)` | — | — | — | ✅ 默认 | ✅ 可选 | — |
| `wan3.0-video(-prime)` | — | — | — | — | — | ✅ 唯一 |

> **wan2.6 缺席说明**：用户侧预期有 wan2.6 图片模型，但抓取的同步/异步两页
> 的 model 枚举都只列 `wan2.7-image(-pro)`。wan2.6 或在未抓取的独立页面、
> 或已下线 ⚠ —— 实现前确认；分类规则按前缀写（`wan2.6-image` / `wan2.7-image`
> 精确到 `-image`，不吞未来的 `-t2v`），到了就能接住。

## 8. 对接注意事项（文档明示的坑，实现 checklist）

1. C1 用 `max_completion_tokens`，不发 `max_tokens`（已废弃）。
2. C2 流式漏 `X-DashScope-SSE: enable` → 静默拿不到 SSE；
   `incremental_output` 决定增量还是累积，解析器先读它。
3. C3 base 不带尾部 `/v1`；本仓自拼完整路径时是 `/apps/anthropic/v1/messages`。
4. I1 与 I2 路径不同（`multimodal-generation` vs `image-generation`），
   不是「同路径 + header 切换」。
5. `qwen-image-edit` 基础版：`n` 固定 1、无 `size` —— 与同家族其他成员
   行为不同，参数表必须单列，填错即 400。
6. 结果 URL 一律 24h 过期：当场下载。下载 GET **不带** Authorization ——
   那是 OSS 签名地址，签名在 URL 里，API key 在那个 host 没有意义。
7. usage 三套命名并存（C1 是 prompt/completion_tokens、C2/C3 是
   input/output_tokens、图片视频按张/按秒）—— 统一计量的客户端要自己翻译。
8. 与计费相关的默认值偏贵：wan2.7 图片 `n` 默认 **4**、V1 `audio` 默认
   true、`prompt_extend` 默认 true —— 不想吃服务端默认就得显式下发。
9. C2 的 `result_format` 默认是 `"text"`：不显式发 `"message"` 就只回一个
   裸字符串、没有 `choices`、没有 tool_calls、没有 finish_reason ——
   读 choices 的解析器会把它当"模型什么都没说"，不会报错。
10. C2 的两个端点靠**模型**分（纯文本 `text-generation` / VL·omni·audio
    `multimodal-generation`），不靠请求内容。把图片发给文本端点不报错，
    图片被丢掉，模型当作没看见图来回答。

## 9. 本仓实现状态（2026-08-26）

六条 wire 全部实现：C1 `openai_chat_protocol` · C2 `dashscope_chat_protocol`
· C3 `anthropic_chat_protocol`（base 由 vendor 推导）· I1
`dashscope_images_protocol` · I2 `dashscope_images_async_protocol` · V1
`dashscope_video_protocol`。两个 vendor id 分别以兼容面（`dashscope-api`）
和原生面（`dashscope-native`）打头，chat 三面在两个通道上都能按模型点单。
路由与分层见
[`../architecture/llm-three-layer.md`](../architecture/llm-three-layer.md)。
**未实测**：本文全部 ⚠ 条目，以及 C2 的多模态面与 SSE 增量。
