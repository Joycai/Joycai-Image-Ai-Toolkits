# 用量与上限：token 怎么算，窗口怎么问

> 边界见 [`README.md`](README.md)：只写协议事实。族的编号沿用
> [`landscape.md`](landscape.md)：① Chat Completions ② Responses ③ Google GenAI
> ④ Anthropic Messages。

## 1. usage 字段对照

| | ① Chat Completions | ② Responses | ③ Google GenAI | ④ Anthropic |
| --- | --- | --- | --- | --- |
| **输入** | `usage.prompt_tokens` | `usage.input_tokens` | `usageMetadata.promptTokenCount` | `usage.input_tokens` |
| **输出** | `usage.completion_tokens` | `usage.output_tokens` | `usageMetadata.candidatesTokenCount` | `usage.output_tokens` |
| **缓存命中** | `prompt_tokens_details.cached_tokens` | `input_tokens_details.cached_tokens` | `usageMetadata.cachedContentTokenCount` | `usage.cache_read_input_tokens` |
| **缓存写入** | — | — | — | `usage.cache_creation_input_tokens` |
| **思考 token** | `completion_tokens_details.reasoning_tokens` | `output_tokens_details.reasoning_tokens` | `usageMetadata.thoughtsTokenCount` | `output_tokens_details.thinking_tokens` |

## 2. 两个口径陷阱

### 2.1 缓存计数：子集 vs 不重叠

**①②③ 的"缓存命中"是输入的子集**——`cached_tokens ≤ prompt_tokens`，计费时
只有未命中的余量按全价算：

```
成本 = (input − cached) × 全价 + cached × 缓存价
```

**④ 的三个桶互不重叠**：`input_tokens` **只是未命中缓存的余量**，缓存读与
缓存写各自单列。要得到可比的"总输入"必须**相加**：

```
总输入 = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
```

直接读 ④ 的 `input_tokens` 当作总输入，会在长提示词 + 缓存命中时把输入量少报
一个数量级。另外**缓存写入的价格高于基础输入价**，若数据模型里没有这一档费率，
把它算进全价桶会高估成本——那是这个方向上安全的一侧。

### 2.2 思考 token：已含 vs 未含

**①②④ 的"输出"已经包含思考 token**，`*_details.reasoning_tokens` 只是其中的
明细。

**③ 的 `candidatesTokenCount` 不含思考**，思考单列在 `thoughtsTokenCount`。
只读前者会把"思考 5k、回答 500"的一次请求记成 500 —— 少算的正是最贵的部分。
可比的输出是二者之和。

## 3. 输出上限

| 协议 | 字段 | 必填 | 备注 |
| --- | --- | --- | --- |
| **①** | `max_tokens` → **`max_completion_tokens`**（新名） | 否 | 旧名多数端点仍接受，部分已标记弃用 |
| **②** | `max_output_tokens` | 否 | |
| **③** | `generationConfig.maxOutputTokens` | 否 | |
| **④** | `max_tokens` | **是** | **没有服务端默认值**，不传就是错误 |

④ 的必填是跨族移植时最容易漏的一条：其余三族省略即用服务端默认，只有它必须
自带一个兜底常量。

App 侧（2026-09-16）：上限是模型级配置 `llm_models.max_output_tokens`，协议经
`outputCapFor` 读，① 的字段名按 `VendorProfile.outputCapField` 声明（官方 OpenAI /
New API 发新名，其余发旧名）。见 `architecture/llm-three-layer.md` 的「输出上限」。

**上限与思考的相互作用**：④ 的手动思考模式下 `budget_tokens` 必须 <
`max_tokens`（思考 token 计入同一个上限）；而在高 effort 下若 `max_tokens` 给
得太小，模型会把额度全用在思考上、正文被截断。JSON 输出场景尤其危险——截断的
JSON 解析失败，看起来像"模型不听话"。

## 4. 上下文窗口：协议不告诉你

**四族的请求响应里都没有"这个模型的上下文窗口有多大"。** 这不是遗漏，是分层
——窗口是模型属性，而协议只描述一次调用。

后果是：**超出窗口的表现各不相同，且最坏的一种是静默的。** 托管端点通常返回
一个明确的错误；本地栈（ollama 等）则可能**从头部丢弃**并返回 200 —— 丢掉的
一般正是 system 指令，而没有任何字段会说明这件事发生过。

可用的信息来源，可靠性递减：

1. **`/v1/models` 的扩展字段** —— 非标准，各家自定：OpenRouter 的
   `context_length` / `top_provider.max_completion_tokens`、LM Studio 的
   `max_context_length` 等。
2. **ollama 的 `/api/show`** —— `model_info` 里有 `<arch>.context_length`，
   `parameters` 里可能有实际生效的 `num_ctx`（**后者才算数**，且默认常常远小于
   模型本身的能力，2048/4096 是常见值）。
3. **llama.cpp 的 `/props`**。
4. **实测**：发一个已知长度的填充请求，看是被拒绝还是被截断。成本高但唯一
   可靠。

**测量会过期。** 中继随时可能把同一个模型名路由到另一个上游，所以任何探测结果
都应带时间戳，呈现为"某日实测"而非永久事实。

## 5. 计费维度不止 token

- **按张计价的图像端点**（Imagen、xAI 等）用"每张图"计费，而 OpenAI 的图像模型
  把生成计为 token。同一个模型可能两种都有，所以**两者相加**比二选一更安全。
- **输入图也可能按张计费**，与输出分开标价（2026-09-21 查证）：

  | 模型 | 输入图 | 输出 |
  |---|---|---|
  | xAI `grok-imagine-image-2.0` | $0.01/张 | 分辨率 × 质量：1K·Low $0.04 / 1.5K·Low $0.05 / 2K·Low $0.06 / 1K·Medium $0.06 / 1.5K·Medium $0.07 / 2K·Medium $0.08（`-quality` $0.05、初代 $0.02 起） |
  | 火山方舟 Seedream 5.0 pro | 0.02 元/张，**首张免费** | 0.3 元/张（≤261 万像素）、0.6 元/张（>261 万像素，2026-09-23 用户查证）——2K（419 万）落在后一档 |
  | GPT-Image-2 | token：图像输入 $8/M（文本 $5/M、缓存图像 $2/M） | 图像输出 $30/M |
  | Gemini 3 Pro Image / 3.1 Flash Image | token，文本与图像同价（$2/M / $0.50/M，约 $0.0011/张） | token，折合 1K/2K $0.134、4K $0.24 |

  后两家的输入图已在 `input_tokens` 里，按 token 的计费组照常覆盖。前两家由按规格计费组的
  「输入图」一侧覆盖：单价 + 每次请求的免费张数，张数取协议**实际放进请求体**的条数
  （`metadata['input_image_count']`，见 `llm-three-layer.md`）。xAI 的 `usage` 不回报张数；方舟 5.0 pro
  回报 `usage.input_images`。
- **xAI 把这次请求的实扣金额写在回包里**（2026-09-21 实测，`grok-imagine-image-2.0`，`POST /v1/images/edits`，
  不带 `resolution` / 质量参数）：`usage` 只有一个字段 `cost_in_usd_ticks`，**1 tick = $10⁻¹⁰**。

  | 请求 | `cost_in_usd_ticks` | 折合 |
  |---|---|---|
  | `images[]` 5 张参考图，出 1 张 | 1 100 000 000 | $0.11 = $0.06 + 5 × $0.01 |
  | `image` 1 张参考图，出 1 张 | 700 000 000 | $0.07 = $0.06 + 1 × $0.01 |

  由此：输入图 **$0.01/张、线性、没有免费张数**（计费组填 `0.01 / 0`）；5 张参考图被接受（HTTP 200）；
  不带质量参数时输出按 **1K · Medium（$0.06）** 计，不是标价表第一格的 Low $0.04。回包里**没有**输入张数，
  所以张数只能由协议自己数。

  **`n: 2`**（2026-09-22 补测，`/images/edits`，1 张参考图，`quality: low`）：200、两张图、
  `900 000 000` = $0.09 = 2 × $0.04 + **1** × $0.01——输入图**按请求收一次，不乘输出张数**。

  应用自 4.27.0 起读这个字段：xAI images 协议把它翻成美元发布为 `reported_cost_usd`，记账落到
  `token_usage.reported_cost`，**压过**计费组的任何算式（它含输入图那一侧）；档位表的快照仍写在同一行上，
  用量页把两者对照（`architecture/llm-three-layer.md`「上游报价」）。中转协议不翻这个键。
- **xAI 的质量参数**（2026-09-22 实测，`/images/generations`，同样读 `cost_in_usd_ticks`）。请求字段叫
  `quality`，枚举 `low | medium | high | auto`（别的值 422 并列出枚举）；`grok-imagine-image-2.0` 只收
  `low / medium / auto`（`high` → 400 `This model only supports … low, medium, auto`）；不带 = medium。
  分辨率字段 `resolution` 枚举 `1k | 1.5k | 2k`。OpenAPI（`docs.x.ai/openapi.json`）的请求体**没列** `quality`，
  只有 `ImagePricingTier` 一句「Medium is the default quality a request serves at when it leaves `quality` unset」；
  `GET /v1/image-generation-models/{id}` 回 `pricing[]`（`price_per_image` 单位 1e-8 美分 = tick），六格与文档页一致。

  | 请求 | `cost_in_usd_ticks` | 折合 |
  |---|---|---|
  | `quality: low` | 400 000 000 | $0.04 = 1K · Low |
  | `quality: low, resolution: 2k` | 600 000 000 | $0.06 = 2K · Low |
  | `quality: auto` | 400 000 000 | $0.04——这一次模型选了 Low；**由模型决定，档位表没法写** |
  | `/images/edits` + 1 张参考图 + `quality: low` | 500 000 000 | $0.05 = 0.04 + 0.01 |
  | 初代 `grok-imagine-image` + `quality: low` | 200 000 000 | $0.02——平价，参数被默默接受 |
  | 初代 `grok-imagine-image` + `resolution: 1.5k` | — | **400** `1.5K resolution is not supported for this model.` |

  `/v1/image-generation-models` 列表里 `grok-imagine-image`（$0.02）与 `grok-imagine-image-quality`（$0.05）
  都是 `pricing: []`（各质量同价），只有 2.0 有矩阵。应用自 4.26.0 起给 2.0 发 `quality`（默认 `medium`，
  明发，让用量行带 `1K · medium`）和 `1.5k`；初代不发质量、不给 1.5k（`_xaiImageLegacy`）。
- **xAI 视频也按张收输入图，且只在终态回包里报价**（2026-09-22 付费实测，`grok-imagine-video-1.5`，
  `POST /v1/videos/generations` → `GET /v1/videos/{request_id}`，1 s · 480p；标价页只写 $0.080/s，一个字没提输入图）：

  | 请求 | 终态 `usage.cost_in_usd_ticks` | 折合 |
  |---|---|---|
  | 文生视频 | 800 000 000 | $0.08 = 1 s × $0.08 |
  | `image`（首帧）× 1 | 900 000 000 | $0.09 = $0.08 + 1 × $0.01 |
  | `reference_images` × 2 | 1 000 000 000 | $0.10 = $0.08 + 2 × $0.01 |

  由此：视频的首帧 / 参考图 **$0.01/张、线性、无免费张数**——与它的出图面同价。报文形状：提交只回
  `{request_id}`；pending 是 **HTTP 202** `{status, progress}`；done 是 200
  `{status:'done', video:{url, duration, respect_moderation}, model, usage:{cost_in_usd_ticks}, progress:100}`——
  **报价与实际秒数（`video.duration`）都只在终态轮询里**，提交时什么都没有。OpenAPI 里 `VideoResponse.usage`
  是 `MediaUsage`（只有 `cost_in_usd_ticks` 必填，token 字段视频不带）；`GET /v1/video-generation-models` 没有 `pricing`；
  初代 `grok-imagine-video`（$0.050/s）已下线（2026-09-22）；720p / 1080p 是否加价未测。

  应用自 4.28.0 起：计费组的按秒 / 按条 / 按次都有「输入图」一侧（`D2e`）；五个视频协议在提交时发布实际放进
  请求体的张数（`VideoSubmission.inputImages` → 提交行的 `input_image_count`）；xAI 视频面的终态轮询读
  `video.duration` 结算秒数、读 `usage.cost_in_usd_ticks` 写 `token_usage.reported_cost`（`settleVideoUsage`
  的两段），用量页因此把视频行也显示成「上游报价 | 档位估算」。
- **③ 的多模态**在 `prompt_tokens_details` 下还有 `image_tokens` / `audio_tokens`
  等明细（部分兼容层也提供），且图片 token 用量随分辨率档位变化很大——同一张图
  在 low / default / high 三档下可能相差一个数量级。
