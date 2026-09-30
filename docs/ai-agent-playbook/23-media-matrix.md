# 23 · 出图 ／ 视频 ／ 语音识别 矩阵

这张表回答：**某个出图／视频／ASR 模型在某个平台上走哪个 route（或线格式）、请求怎么写、尺寸／时长／参考图规则是什么、同步还是异步、响应长什么样、怎么计费、哪些参数会 400、哪些会被静默忽略**。主键 = （route 或线格式，平台，模型）。表是结论，报文细节、数值与原因在 13（出图）、14（视频）、16（ASR）篇里，用「详见」列跳过去；坑的编号指向 11 篇；待核实项指向 31 篇。

图例（与 20／22 篇相同）：✅ 实测生效；❌ 实测拒绝、**会响**（括号里写状态码或原文）；🔇 **静默失败**（200 但不生效／被丢／被改写）；🔀 被中转站改写或劫持；📄 只有文档口径；— 未测；⚠ 来源标注为推断或含糊。

面的编号：① OpenAI Chat ／ ② Responses ／ ③ Gemini ／ ④ Anthropic ／ Ⓓ DashScope 私有 ／ 🖼 出图 ／ 🎬 视频 ／ 🎤 ASR。ASR 线格式：ⓐ OpenAI 兼容转写 ／ ⓑ 百炼同步识别 ／ ⓒ 百炼录音文件转写（filetrans）。证据记法：【实测 YYYY-MM-DD】本库作者跑过；【文档 YYYY-MM】；【外部实测】他人实测；【实现】来自 pyVideoTrans 等原代码、本库未独立复核报文。

维护：按 `30-knowledge-ingestion.md`；每行带证据与指针，没有证据写 `—`；被推翻的旧结论写「旧：… → 新：…（日期推翻）」不删；文档与实测冲突写「文档：…；实测：…」。数值只在正文篇写一遍，本表只放关键值 + 指针。

目录：§1 出图（§1.1 route 速览 · §1.2 主表 · §1.3 每 route 展开 · §1.4 横切不变量）· §2 视频 · §3 语音识别（§3.1 线格式对照 · §3.2 主表 · §3.3 横切数值附表）· §4 尚未覆盖 · 附录 本表引用的坑。

---

## 1 出图

### 1.1 route 速览

route 按**端点**分发、不按供应商；L3 可声明，默认按协议族推导（gemini 族 → `gemini`，其余 → `images-api`），显式声明永远赢。surface 由用户声明；chat 兜底路由起名 `chat-image`。中转不提供厂商原生出图协议，例外是路径本身就是 `{base}/images/generations` 的（`ark`、`xai-images`）。端点、编辑表达、响应形状总表见 13 §2。

| route | 端点关键 | 同步／异步／流式 | 平台 |
| --- | --- | --- | --- |
| `images-api` | `/images/generations`；编辑 `/images/edits`（multipart） | 同步 | OpenAI 官方、OpenAI 兼容中继 |
| `chat`（`chat-image`） | `/chat/completions` 多模态 user 消息；保底表 `isImageGenerator:true` | 同步 | New API 式中继 |
| `gemini` | `:generateContent` + `responseModalities:["TEXT","IMAGE"]` | 同步 | Google 官方（AI Studio） |
| `imagen` | `:predict`；无 usage | 同步 | Google 官方 |
| `dashscope` 同步 | `…/multimodal-generation/generation`；原生 base 剥 `/compatible-mode/v1` 拼 `/api/v1` | 同步（qwen 仅同步；wan2.7 both） | 阿里百炼 DashScope |
| `dashscope` 异步 | `…/image-generation/generation` + `X-DashScope-Async: enable` → `GET /tasks/{id}` | 异步，六态 | 阿里百炼（wan2.7 家族） |
| `ark` | `{base}/images/generations`（body 超集且缺 `n`／`quality`） | 仅同步；`stream:true` 例外（5.0 lite／4.5／4.0） | 火山方舟 · 按量／套餐；① 族中转站 |
| `xai-images` | `/images/generations`；编辑 `/images/edits`（**JSON**） | 同步 | xAI 官方 |
| `minimax` | `/v1/image_generation`（**不是** Images API） | 同步但慢（声明「长任务」） | MiniMax |
| `midjourney` | `/mj/submit/imagine` → `/mj/task/{id}/fetch` | 异步：轮询 3 s、总帽 10 分钟 | midjourney-proxy ／ New API `/mj/*` |

### 1.2 模型 × 平台 主表

| route | 平台 | 模型 id（含被接受的拼法） | 请求关键 | 尺寸规则 | 编辑／参考图 | 响应 | 计费 | 不支持参数的报法 | 静默失败 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| images-api | OpenAI ／ 兼容 | 通用（route 级） | 编辑 multipart 字段名跟张数走；文件 part 显式 `Content-Type`，整体头不手设 | `sizes` 空 = 不带 `size`；回显 `size`／`quality` 是定了的规格 | `images` 非空即编辑；`mask` 仅此 route | `data[].b64_json`／`url`；mime 嗅探 | `input_tokens`／`output_tokens`；图像输入 $8/M vs 文本 $5/M | ❌ 中继对 `octet-stream` part 400【实测 2026-09-05】；`param:"x"` = 丢字段即可修 | 🔇 200 + HTML；200 + `{"error"}` 零张图 | 【实测 2026-09-05】（Content-Type）；其余【实现／文档】 | 13 §1、§3、§4.2、§5、§6、§7 | 57、93 |
| images-api | OpenAI | `dall-e-2` | `/images/edits` multipart | — | 单张必须 `image`（单数） | `data[]` | — | ❌ 只发 `image[]` 对单张 400 | — | 【实现】 | 13 §4.2 | 93 |
| images-api | OpenAI | `dall-e-3` | 同上 | — | — | 逐项回 `revised_prompt` | — | — | — | 【文档／实现】 | 13 §1、§4.2 | — |
| images-api | OpenAI | `gpt-image-1` | 同上 | 枚举与单价未列（31 篇 OQ-038） | 参考图上限 **16** | 不回 `revised_prompt` | 输入图计 `input_tokens`（$8/M） | — | — | 【文档／实现】 | 13 §4.2、§7 | — |
| images-api（中继） | New API 式中继 | 仅 Imagen | ❌ "only imagen models are supported"；Gemini／Flux 挂 `/chat/completions` | — | — | — | — | ❌ 非 Imagen 被拒 | route 不能从 ApiStandard 推导 | 【实现】 | 13 §2 | — |
| chat（chat-image） | 中继（New API 等） | 任意声明为出图的模型（`nano-banana-pro`、中转 `gpt-image-1`、Gemini 出图、Flux…） | 出图模型纯文本也发单元素 part 数组 | — | 多模态消息附图 | 全部形状都接，SHA-256 去重（13 §6） | — | ❌ 字符串 `content` → `400 images[0] must be an http/https URL or image data URI`【实测 2026-09-05】 | 🔇 `isImageGenerator` 假 = 图被丢；🔇 只认 data URI 零张图；两道闸 | 【实测 2026-09-05】（part 数组）；其余【实现】 | 13 §2、§4.2 末条、§6 | 92、110 |
| chat（chat-image） | New API · Gemini 出图走 ① | Gemini 出图模型 | 只认 `extra_body.google.image_config`（snake_case） | camelCase 被拒、顶层不读 | — | 同上行 | — | ❌ camelCase | 🔇 发错位置静默无效；③ 形状中继不补 `responseModalities` | 【实现】 | 13 §4.2 末条 | 2 |
| gemini | Google 官方 | Gemini 出图模型（原生） | `responseModalities:["TEXT","IMAGE"]` | — | 输入图 = parts | `parts[].inlineData` | 输入图在 `input_tokens` | — | — | 【实现】 | 13 §2、§7 | — |
| imagen | Google 官方 | Imagen（`:predict`） | `:predict` | — | **无编辑**；附参考图要显式警告 | `predictions[].bytesBase64Encoded`；无 usage | 按次；元数据至少张数 | — | 🔇 参考图静默丢弃 | 【实现】 | 13 §2、§4.2、§7 | — |
| dashscope 同步 | 阿里百炼 DashScope 原生 | 通用（qwen-image ／ wan ／ z-image） | 顶层 `model` + `input`；旋钮在 `parameters`，`extraBody` 并进去；qwen 图前文后、wan 文前图后 | `宽*高`；`size` 永远显式发；发前按模型校验；边长 16 倍数 | 公网 URL 或 data URL | `output.choices[].message.content[].{image}`；URL **24h** | qwen 按面积 `qima_output_1k`／`_2k`；wan 按张 | 顶层 `{code,message}`；`Throttling`／429；200 带 `code` | 🔇 省略 `size` → 2048² 按 2K 计【外部实测 2026-09-04】；🔇 `extraBody` 放顶层失效 | 【实测 2026-09-19】【外部实测 2026-09-04】【文档 2026-08/09】 | 13 §3、§4 | 58、59、101、102、103 |
| dashscope 同步 | 百炼 | `wan2.7-image-pro` | ❌ `messages` 放顶层 → `400 Field required: input.messages`【实测 2026-09-19】 | 总像素 768²–4096²（改图 4K ⚠）；`1K`／`2K`／`4K`，默认 `"1K"` | 0–9 张；`enable_sequential` 等；无 `negative_prompt` | ✅ `2688*1536` 原样返回 | 按张；**`n` 默认 4** | `negative_prompt` 报法 ⚠ | 🔇 `n` 默认 4 四倍计费；🔇 省略 `size` 按 2K | 【实测 2026-09-19】【文档 2026-09-19】【外部实测 2026-09-04】 | 13 §4 逐模型参数档、自由尺寸表、实测表 | 101、102、104 |
| dashscope 同步 | 百炼 | `wan2.7-image` | 同上 | 768²–2048²；`1K` `2K` | 同 pro | ✅ `960*1696` 原样 | 按张；`n` 默认 4 | 同上 | 同上 | 【实测 2026-09-19】 | 13 §4 | 102、104 |
| dashscope 同步 | 百炼 | `qwen-image-3.0`、`qwen-image-3.0-pro`、`qwen-image-2.0`、`qwen-image-2.0-pro` | 同通用行 | 总像素 512²–2048²；❌ `"1K"` → 400；默认 `1024*1024` | 1–3 张；`n` 1–6；有 `negative_prompt` | ✅ `2304*1728` 原样，`qima_output_2k` | 越过 1024² 落 2K（两倍价） | ❌ `"1K"` 400 | 🔇 省略 `size` 按 2K | 【实测 2026-09-19】【外部实测 2026-09-04】【文档 2026-09】 | 13 §4 | 102、103 |
| dashscope 同步 | 百炼 | `qwen-image-edit-max` ／ `qwen-image-edit-plus` | 改图：image part 前、指令后 | **单边** 512–2048；≤4:1；缺省按输入比例 1K 面积 | 1–3 张 | 同上 | 🔇 省略 `size` 放大到 2K 面积（768×1376 → 1520×2736）【外部实测 2026-09-04】 | — | 🔇 同左 | 【文档 2026-09，2026-09-19 复核】【外部实测 2026-09-04】 | 13 §4 | 102、103 |
| dashscope 同步 | 百炼 | `qwen-image` ／ `qwen-image-plus` ／ `qwen-image-max`（初代） | 同上 | 只收五个固定值（13 §4 自由尺寸表）⚠ | — | 同上 | — | — | — | 📄【文档 2026-09】⚠ | 13 §4 | 103 |
| dashscope 同步 | 百炼 | `qwen-image-edit`（基础版） | 同上 | **不支持 `size`** | `n` 固定 1 | 同上 | — | ❌ 填 size 400 | — | 📄【文档 2026-08】 | 13 §4 | 102 |
| dashscope 同步 | 百炼 | `z-image-turbo` | 同步端点 | ⚠ 未写（31 篇 OQ-036） | ⚠ | 同上 | ⚠ | ⚠ | — | 📄【文档】仅列名 | 13 §4 | — |
| dashscope 异步 | 百炼 | `wan2.7-image`、`wan2.7-image-pro` | 提交路径不同、body 一致 → `output.task_id` → `GET /tasks/{id}` | 同同步 | 同同步 | `output.results[].url`；task_id／URL 24h；过期也报 UNKNOWN | 同同步 | 打错路径报路径级 4xx | 🔇 FAILED／CANCELED 嵌在 200 的 `output` | 📄【文档 2026-08】 | 13 §3、§4 异步任务流 | 60 |
| ark | 火山方舟 · 按量（`/api/v3`）／套餐（`/api/plan/v3`） | 通用（Seedream；`ep-…`） | 无 `n`／`quality`；参考图 JSON `image`（`<fmt>` 小写）；**`watermark` 永远明发** | 档位或 `WxH` 不混用；`WxH` 约束总像素；`1.5K` 撞 `\d+K` | `max_images` 1–15（默认 15）；参考图 + 生成 ≤15，源图占一张；`<bbox>`／`<point>` | `data[]` `url`（24h）或 `b64_json` + `size`；单项 `{error}` 不判整次；回显 `model` 流式／非流式不同【实测 2026-09-18】 | `generated_images` 是账单；`output_tokens` = 像素/256 仅参考；5.0 pro 输入图 0.02 元/张首张免费；失败免费 | OpenAI 形信封；❌ 出图前 400 `param` 点名；审核 code 非「不能编辑」；免费探测非法 `size`（400／404） | 🔇 `watermark`；固定 3 分钟超时；一项 `error` 丢已计费图；校验顺序不固定 | 【文档 2026-09-18／09-22】【实测 2026-09-18、2026-09-23 套餐 key】 | 13 §4.1、§7；01 §9.3 | 79、80、81、82、83、84、131 |
| ark | 火山方舟 · 套餐 | `doubao-seedream-5.0-pro`（拼法见 01 §9.3；回显 `doubao-seedream-5-0-pro`） | `optimize_prompt_options.mode: standard/fast`；`output_format: png/jpeg`（仅 5.0） | 1K·1.5K·2K；✅ `1K` 无比例提示回 `1248x832` | 参考图 **10**（❌ 11 张 400【实测 2026-09-23】）；组图 ✗；联网 ✗；专属拆图层、透明背景 | 同上 | 同上 | ❌ `stream:true`／`sequential_image_generation:"auto"`／`tools web_search` 各 400 点名；❌ `webp` 400 | 见透明背景行 | 【实测 2026-09-18、2026-09-23】 | 13 §4.1；01 §9.3 | 81、131 |
| ark | 火山方舟 · 套餐 | 5.0 pro **`layer_decomposition:true`** | 与透明背景互斥；**恰好 1 张参考图**客户端先校验 | `size` 只收档位或 `auto` | 恰好 1 张 | 底图 + ≤16 图层，按 `z_index`，带 `name`／`description`／`bounding_box`（底图像素） | `generated_images` = 实出张数（2）；`input_images:1` | — | 人物整体一层——UI 别承诺 | 【实测 2026-09-18】 | 13 §4.1 拆图层实测形状、§8 | 82、88 |
| ark | 火山方舟 · 套餐 | 5.0 pro **`background:"transparent"`** | 只对改图开；**成对明发 `output_format:"png"`** | — | 恰好 1 张带 alpha；三条 400 全在出图前、`param` 点名；`image` 那条去两字段重试一次 | `data[]` 多 `output_format:"png"`；`input_images:1` | 每张计费 | 见左 | 🔇 语义是「结果背景透明」不是锁轮廓（坑 130）。**旧：「透明模式锁死原图 alpha 遮罩」→ 新：主体可变形、只保证结果背景透明（2026-09-23 箭头改向实测推翻）**；不按输入透明 PNG 自动开 | 【实测 2026-09-23 pro，31 次零成本探测 + 4 张计费】【文档 2026-09-22】 | 13 §4.1 透明背景 | 130、132 |
| ark | 火山方舟 · 按量 | `doubao-seedream-5.0-flash`（三种拼法见 13 §4.1） | 与 pro 同表，只少 `fast` | 1K·1.5K·2K | 10；组图 ✗；联网 ✗；专属同 pro 📄 | 同 pro | — | ❌ 套餐 key 三拼法 `404 UnsupportedModel` | ⚠ 流式未写（31 篇 OQ-009） | 📄【文档 2026-09】【实测 2026-09-23 套餐 404】 | 13 §4.1；01 §9.3 | 81、130 |
| ark | 火山方舟 · 套餐 | `doubao-seedream-5.0-lite`（拼法见 01 §9.3） | 联网 `tools:[{type:"web_search"}]`；优化仅 standard | 2K·3K·4K；`WxH` 下限 3686400 | **14**（❌ 15 张 400【实测 2026-09-23】）；组图 ✓ | 同上；2K 单张 26 s | 同上 | ❌ `mode:"fast"` 400【实测 2026-09-23】；❌ `webp` 400 | — | 【实测 2026-09-18、2026-09-23】 | 13 §4.1；01 §9.3 | 81、131 |
| ark | 火山方舟 · 按量 | `doubao-seedream-4.5` | 仅 jpeg；优化 standard | 2K·4K | 14；组图 ✓；联网 ✗ | 同上 | 同上 | ❌ 套餐 key 404 | — | 📄【文档 2026-09-18】【实测 2026-09-23 套餐 404】 | 13 §4.1 | 81 |
| ark | 火山方舟 · 按量 | `doubao-seedream-4.0` | 仅 jpeg；优化 standard/fast | 1K·2K·4K | 14；组图 ✓；联网 ✗ | 同上 | 同上 | ❌ 套餐 key 404 | — | 📄【文档 2026-09-18】【实测 2026-09-23】 | 13 §4.1 | 81 |
| ark 流式 | 火山方舟 · 套餐（官方渠道） | 5.0 lite（实测）／4.5／4.0（文档）；pro 不支持 | `stream:true` 只在官方渠道、声明流式的版本 | 只发档位两张自选 16:9 | 按 `max_images` | SSE 三种事件 + `[DONE]`；响应头等首张（≈27 s） | 按已送达张数；`usage` 只在 `completed`；图片块带记账中性键 | ❌ 校验失败回 400 JSON；看 body 首行 | 🔇 120 s 空闲守卫；`partial_failed` 当整次失败；只在流末记用量；拒收 `stream` 的中转 400 | 【实测 2026-09-18 5.0 lite】 | 13 §4.1 流式出图、§7 | 85、86、87、127 |
| ark | ① 族中转站 | Seedream（认得出的 id） | 默认 route 也是 `ark`；要求中转原样透传 body | — | — | — | — | — | 透传 SSE 未知（31 篇 OQ-010） | 【实现】 | 01 §9.3；13 §4.1 | — |
| ark | 火山方舟 | Endpoint ID `ep-…` | 看不出哪一代，让作者点单（声明出图 + 选 `ark`） | — | — | — | — | — | — | 📄【文档】 | 01 §9.3 | — |
| xai-images | xAI 官方 | `grok-imagine-image-2.0` | 编辑 JSON `image`／`images[]`；`resolution: 1k／1.5k／2k`；`quality: low／medium／high／auto`（不带 = medium）；价目端点见 13 §4.2 | `1.5k` 仅 2.0；`sizes` 空 | **文档：3 张【文档 2026-09】；实测：5 张 HTTP 200 并按 5 张收费【实测 2026-09-21】**——旧：「最多 3 张」→ 新：按 5 截断（2026-09-21 推翻） | OpenAI 形 `data[]`；`url`／`b64` 都空即失败 | `cost_in_usd_ticks`（1 tick = $10⁻¹⁰）；六格价目；输入图 **$0.01/张**按请求收一次；整单实扣替换不叠加；`auto` 模型定档 | ❌ `quality` 非枚举 **422**；❌ 2.0 `high` 400；❌ `size` 400 | 🔇 不带 `quality` 按 Medium 计，本地按 Low 低估三分之一；OpenAPI 未列 `quality`；中转透传 ticks 是 xAI 收中转的价 | 【文档 2026-09】【实测 2026-09-21、2026-09-22】 | 13 §4.2、§7 | 123、124、126、128 |
| xai-images | xAI 官方 | `grok-imagine-image`（$0.02）、`grok-imagine-image-quality`（$0.05） | 同上 | ❌ `1.5k` → 400 | 同上 | 同上 | `pricing: []` | ❌ `1.5k` 400 | 🔇 默默收下 `quality` 无效果 | 【实测 2026-09-22】 | 13 §4.2 | 125 |
| minimax | MiniMax | `image-01`、`image-01-live` | `aspect_ratio`（8 种）或 `width/height`（512–2048、8 倍数、仅 `image-01`）；`n` 1–9；`style` 仅 `-live`；`aigc_watermark` 默认关 | 同左 | **无编辑**——`subject_reference` 是主体参考；caps `edit:false` | `data.image_urls[]` + `base_resp`；URL 24h | 按次；元数据至少张数 | 两层：`base_resp.status_code≠0`（HTTP 200）；`success_count==0` | 🔇 风景图调色回无关图；🔇 `success_count` 是字符串 | 【实现／文档】 | 13 §2、§4.2、§7 | 6、90、91 |
| midjourney | midjourney-proxy ／ New API `/mj/*` | Midjourney（内置目录） | 垫图 `base64Array`；参数改写 `--ar/--v/--s/--c/--q`，用户 flag 优先，`--v niji 6` → `--niji` | `--ar` | 上限 ⚠（31 篇 OQ-045） | 任务记录四字段；回执 `code` 1 成功、22 排队 | 按次（单价 ⚠）；放弃永不重试 | — | 🔇 task id 出现前不入日志 | 【实现，日期未标】⏳待复核 | 13 §2、§4.2 | 60 |

### 1.3 每 route 展开（实测数值）

只留指针：

- **dashscope**：实测表、wan 官方推荐尺寸（1.75:1、3% 容差）、size 与计费档、尺寸校验器、异步轮询节奏 → 13 §4「自由尺寸的规则」「异步任务流」；RPM 未写（OQ-037）。
- **ark**：用时、超时公式、版本能力表、`WxH` 像素区间、拆图层实测形状、透明背景实测与 400 文案、不支持参数的 400 表、计费口径 → 13 §4.1 各小节、§7；套餐 vs 按量（两个 base、401、`/models` 404、静态目录、去尾斜杠回读、拼法）→ 01 §9.3。
- **xai-images**：六格价目、tick 单位、输入图算式、初代 `pricing: []`、`quality: auto` → 13 §4.2、§7。
- **minimax**、**midjourney** → 13 §4.2。
- **images-api ／ chat-image ／ gemini ／ imagen**：无本库实测数值；仅 Content-Type 400 与 part 数组 400 两条为【实测 2026-09-05】，其余【实现／文档】。

### 1.4 横切不变量

只列一句话 + 指针，原因与细则在 13 篇。

1. 出图入口是流式入口的兄弟，`images` 非空即编辑（13 §1）。
2. route 按端点分发；新增 route 五项清单；route 永不做新默认值（13 §2）。
3. **永不探测出图**：能力全部声明，`asyncTask` 三态；唯一零成本探测是 ark 的非法 `size`（13 §3、§4.1）。
4. **编辑降级只认「路由缺失」证据**，宽松误判 = 二次全价计费（13 §5；坑 57）。
5. **响应归一到字节**：当场下载、校验 content-type、嗅探 mime、空即失败（13 §6；坑 56）。
6. chat 出图接住所有形状，两道闸 + SHA-256 去重（13 §6；坑 92）。
7. **计费口径**：per-image 与 token 相加；上游报价替换不叠加；NULL vs 0；中性键是保留键（13 §7；坑 83、123、126、127）。
8. 出图进同一份 API 日志，mid-call `note` 记 task_id（13 §7；坑 60）。
9. 尺寸发前按目标模型规则校验（13 §4；坑 103）。
10. Seedream 纪律（`watermark` 明发、档位 + 比例、逐版本建档、专属任务互斥、透明背景成对字段与重试、单项 `error` 不判整次）（13 §4.1）。
11. 拆图层结果类型化、逐项下载保位置、按路径落库不进备份（13 §8；坑 88）。

---

## 2 视频

视频没有同步形态——全行业一律「提交拿 task_id → 轮询 → 结果 URL」；统一形状与 `media[].role` 见 14 §1。

| 平台 | 模型 | 提交 | 轮询与状态词 | 参考图／首帧 | 时长／分辨率 | 计费 | 失败／超时行为 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 阿里百炼 千问 | `wan3.0` | `…/video-generation/video-synthesis` + `X-DashScope-Async: enable`；`input.media[]`；**`audio` 默认 true** | `GET /api/v1/tasks/{id}`（与图片任务、ASR filetrans 共用）；六态；`output.video_url` | `input.media[].type` 标 role | 2–30s（`-1` 智能）；480P/720P/1080P（默认 1080P） | usage 报秒数/fps/分辨率，无 token；🔇 `audio:true` 默认乘在账单上 | 🔇 FAILED 在 HTTP 200 `output.code/message`；task_id **24h**，过期 = 独立错误；`UNKNOWN` 是终态；无取消端点；结果 URL 24h 不带认证头 | 【实测 2026-08-29，Joycai 用户账号】成功链路；失败态与取消未走到；【文档 2026-08】 | 14 §2、§3；01 §8.1 | 60、126 |
| MiniMax | `MiniMax-H3`（v2 API） | `POST /v2/video_generation`（base 见 01 §8）；`content[]` = text 项 + **嵌套**媒体项带 `role`；**`resolution` 与 `duration` 必填、无默认** | `GET /v2/query/video_generation/{id}`；`queued/running/succeeded/failed/cancelled`；结果 `task.content.url` | ✅ 首帧 + 尾帧跑通；媒体项旁**必须有 text 项**；`ratio:"adaptive"` 原样接受 | 4–15s；✅ `2K` 出片；`768P` 未实测 | 秒数 + token 双口径相加 | 🔇 `task.error` 在 HTTP 200；记录 **7 天**；取消 `DELETE` **仅 `queued`**；❌ 缺 resolution/duration 400 | 【实测 2026-08-29，首帧+尾帧全链路，来源 Joycai】；未实测项见 31 篇 OQ-041 | 14 §2、§3；01 §8.1 | 113 |
| xAI 官方 | `grok-imagine-video-1.5` | `POST /v1/videos/generations`（JSON）；回包只有 `{"request_id"}`；`GET /v1/video-generation-models` 无 `pricing` | `GET /v1/videos/{request_id}`；pending 是 **HTTP 202**；done 带 `usage.cost_in_usd_ticks`；`pending/done/expired/failed` | 首帧 `image`；`reference_images`；`reference_audios` | 实测三条 1 s · 480p；`video.duration` 报实际秒数；无最低计费秒数；720p／1080p【未验】 | $0.080/s；**报价只在终态回包**；参考图 **$0.01/张、线性**；提交先记一行，终态改写 | `video.url` 空且 `respect_moderation: false` = 审核拦下；`expired` 是终态 | 【实测 2026-09-22，来源 Joycai】 | 14 §2、§3 第 8 条；13 §7；01 §9.1 | 129 |
| xAI 官方 | `grok-imagine-video`（初代，$0.050/s） | `input_modalities` = text／image／video（`/videos/edits`、`/videos/extensions`） | 同上 | — | — | $0.050/s | **已下线（2026-09-22），不再追** | 【实测 2026-09-22】 | 14 §2 | — |
| OpenAI 官方 | Sora | `POST /v1/videos`（**multipart**） | `GET /v1/videos/{id}` + `/content`；`queued/in_progress/completed/failed` | ⚠ | ⚠ | ⚠ | `/content` 是 API 端点，**要带**认证头；保留期／取消 — | 📄【文档】⚠ 未标注实测 | 14 §2、§3 第 4 条 | — |
| Google 官方 | Veo | `:predictLongRunning` | operations `GET`；`{done: bool}`；URI 在 operation response 内 | ⚠ | ⚠ | ⚠ | 🔇 轮询把 operation body 整个当内部信封（坑 126）；保留期／取消 — | 📄【文档】⚠ | 14 §2 | 126 |
| 火山方舟 · 套餐 | Seedance（四个 id 见 14 §2） | 套餐 base 上 `/contents/generations/tasks` | — | — | — | — | ❌ 四个 id 全 `404 UnsupportedModel`——要按量 key；协议形状**未覆盖** | 【实测 2026-09-18】 | 14 §2；01 §9.3 | — |
| 中继（New API 等） | sora、grok-imagine、wan2.5、kling、hailuo… | 收敛到 OpenAI 式 `/v1/videos`（openai-videos） | 同 OpenAI 式 | — | — | — | **同一模型 id 官方与中继走不同协议**，按 model-id 硬编码会在一边坏掉 | 【实现】 | 14 §4 | — |

横切不变量（每条一句，细则在 14 §3）：失败装在 HTTP 200（第 1 条）；状态词表逐家归一化、已知终态显式抛错（第 2 条）；过期 task_id ≠ 失败任务（第 3 条）；结果 URL 当场下载、认证头按端点性质（第 4 条；13 §6）；取消分两层（第 5 条）；计费默认值显式下发（第 6 条）；必填无默认参数归 L3 参数表（第 7 条）；usage 两套口径相加、上游报价替换不叠加且只在 done 回包（第 8 条；坑 129）；submit／poll 分离、同一模型 id 官方／中继走不同协议（14 §1、§4）。

---

## 3 语音识别

### 3.1 三种线格式对照

三种线格式 = 三个适配器；百炼 ⓑ／ⓒ 按模型名后缀分发（`-filetrans` → ⓒ）。ⓐⓑⓒ 的选路规则、端点、上传方式、单次上限、时间码来源、说话人、代表模型见 16 §1；限流见 16 §4.2（ⓑ 约 100 RPM）、16 §5（ⓒ 轮询 2 → 3 → 5 → 8 → 10 s）；错误分类见 16 §8。ⓐ 本库**只有实现、没有实测、没有离线测试**；ⓑⓒ【实测 2026-09-13】。ⓐⓑⓒ 之外的私有 SDK／HTTP（豆包、Gemini、Deepgram、ElevenLabs、CAMB、Gladia、MiMo…）证据仅【实现】（16 §10.2）：

- 上传：整文件；Gladia 是 ⓒ 型三步异步；MiMo 走 ① `chat/completions` 的 `input_audio` 块。
- 单次上限：Gemini ≤300 s 整段；CAMB 轮询上限 600 s；Deepgram 超时 600 s。
- 时间码：豆包毫秒；Gemini 带 `s` 字符串；Deepgram／ElevenLabs／CAMB 秒；Gladia／自定义 API 直接 SRT。
- 说话人：豆包 `enable_speaker_info`；Deepgram `diarize`；ElevenLabs `speaker_id`；CAMB `speaker`；WhisperX 本地有。
- 限流与成败：GLM `error.code` 1302／1303／1214 是限流；Gemini 原实现 429 也不等；豆包成败看头 `X-Api-Status-Code == 20000000`。

### 3.2 模型 × 平台 主表

| 线格式 | 平台 | 模型 | 端点与上传 | 时间码 | 说话人分离 | 语种／限流 | 错误分类 | 证据 | 详见 | 坑 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ⓐ | OpenAI 官方 | `whisper-1` | multipart；`verbose_json` + `timestamp_granularities[]`；上限 **25 MB** | 句级 `segments[]`（**秒**）；`avg_logprob` 当置信度；无 `segments` 退回整段 | ❌ 无 | — | 16 §8 表 | 📄【文档】；本库 ⓐ 只有实现、无实测、无离线测试 | 16 §1、§3、§8 | 116 |
| ⓐ | OpenAI 官方 | `gpt-4o-transcribe` ／ `-mini-transcribe` | 同上 | 只支持 `json`／`text`，**不给 segments**；时间码来自切片 | ❌ 无 | — | — | 【文档 + 实现】 | 16 §3、§10.2 | 116 |
| ⓐ | OpenAI 官方 | `gpt-4o-transcribe-diarize` | 整文件，`chunking_strategy: "auto"`，`response_format: "diarized_json"` | `segments[].start/end/text/speaker` | ✅ `speaker`（首次出现顺序重编号） | — | — | 【实现】 | 16 §10.2 | — |
| ⓐ | Groq | `whisper-large-v3`、`whisper-large-v3-turbo` | `https://api.groq.com/openai/v1` | 同 ⓐ | — | — | — | 【实现】 | 16 §3 | — |
| ⓐ | 硅基流动 | `FunAudioLLM/SenseVoiceSmall` | OpenAI 兼容 | ⚠ 时间码形态未写 | — | zh／yue／en／ja／ko | — | 【实现】 | 16 §3 | — |
| ⓐ | OpenAI 兼容第三方（通用） | 非 `api.openai.com` | VAD 切片逐段 | `json` 只取 `text`，时间码来自切片 | ❌ 无 | — | — | 【实现】 | 16 §10.2 | — |
| ⓐ | 302.AI | whisper ／ `gpt-4o-*` | `api.302.ai/v1/audio/transcriptions`；whisper 整文件，`gpt-4o-*` 切片 | whisper `verbose_json`；gpt-4o 只能 `json` | 编号曾用「当前条数」（已修） | — | 请求**没有超时**；坏片段跳过，全部失败才报错 | 【实现】 | 16 §10.2、§10.3 | — |
| ⓐ | 智谱 BigModel | `glm-asr-2512` | `open.bigmodel.cn/api/paas/v4/audio/transcriptions`；VAD 切片 | 只有 `text` | ❌ 无 | `error.code` 1302／1303／1214 是**限流** | 401/403/404/422 致命；🔇 计数器曾在成功时递增（已修） | 【实现】 | 16 §10.2、§10.3；01 §9.4 | — |
| ⓐ（chat 面） | 小米 MiMo | `mimo-v2.5-asr` | `https://api.xiaomimimo.com/v1` 的 **`chat/completions`**，① `input_audio` 块 | `choices[0].message.content`，时间码来自切片 | ❌ 无 | `extra_body.asr_options.language`（zh／en／auto） | — | 【实现】 | 16 §10.2 | — |
| ⓐ（本地） | WhisperX ／ Parakeet ／ STT | — | 整文件 | WhisperX `diarized_json`；Parakeet、STT 要 `srt` | WhisperX 有 | — | — | 【实现】 | 16 §10.2 | — |
| 本地 | Faster-Whisper-XXL | — | — | — | — | — | 🔇 逐行正则吞掉行尾 `\n`，静默丢字幕（已修） | 【实现】 | 16 §10.3 | — |
| ⓑ | 阿里百炼 DashScope | `qwen3-asr-flash` | `…/multimodal-generation/generation`；`{audio}` 内容块 + `asr_options`（16 §4） | **无句级时间戳**；词级 `words[]` 是否给**没有实测** | ❌ 不支持【文档】 | 约 100 RPM | `ASR_RESPONSE_HAVE_NO_WORDS` = 成功空文本；404 `Model not exist` 致命（16 §8） | 【实测 2026-09-13】 | 16 §1、§4、§4.2、§8 | 116、118 |
| ⓑ | 百炼 | `qwen-audio-3.0-asr-flash` | 同上；`input_audio` 内容块 + `parameters:{format, sample_rate}` | 无句级；文本在 `output.text` 或 `output.choices[0].message.content` | 🔇 `diarization_enabled: true` **静默忽略**【实测 2026-09-13】；**文档：支持；实测：忽略** | 同上 | 同上；`DataInspectionFailed` = 跳过这一片 | 【实测 2026-09-13】 | 16 §4、§7、§10.2 | 115、118 |
| ⓑ | 百炼 | `fun-asr-flash-*` | 同上 | 同上 | 🔇 静默忽略【实测 2026-09-13】；文档称支持 | 同上 | 同上 | 【实测 2026-09-13】 | 16 §4、§7 | 115 |
| ⓑ（SDK） | 百炼 | `qwen3-asr-flash`（原 Python 版） | DashScope SDK `MultiModalConversation.call`；VAD 切片 | `content[].text` 拼接 | — | — | 原实现关 TLS 校验、无超时，任意 400/422 终止任务（已修） | 【实现】 | 16 §10.2、§10.3 | 118 |
| ⓒ | 百炼 | `qwen-audio-3.0-asr-flash-filetrans` | 五步（16 §5）：上传与下载不带鉴权头，提交带 `X-DashScope-OssResourceResolve`；**提交不幂等** | 句级 + 词级（**毫秒**）；`enable_words:true` 才有词级 | ✅ 一男一女英文标成 0／1【实测 2026-09-13】 | `language_hints` | 六态；按步骤回退（16 §8） | 【实测 2026-09-13】跑通五步；❌ Dart `http` `MultipartRequest` 传 OSS 被拒 `MalformedPOSTRequest`，手拼成功【实测】（触发点未定位；旧：「boundary 含 `()+,?:=`」不准确，保留以解释旧代码） | 16 §1、§5、§7、§8、§9 | 119、120、121 |
| ⓒ | 百炼 | `qwen3-asr-flash-filetrans` | 同上；`input.file_url`（**单数、字符串**）、`parameters.language` | 同上 | ❌ 不支持【文档】 | — | 同上 | 📄 **只按文档实现、未实测** | 16 §5、§7 | — |
| ⓒ | 百炼 | `fun-asr`、`fun-asr-mtl`、`paraformer-v2` 等 | 同上 | 同上 | 📄 文档称支持，≤2 小时 | — | — | 📄【文档，未测】 | 16 §7 | — |
| 私有 HTTP | 火山引擎 豆包 | `volc.bigasr.auc_turbo` | `…/auc/bigmodel/recognize/flash`；头 `X-Api-*`；mp3 base64 放 `audio.data` | `result.utterances[]`（**毫秒**） | `additions.speaker`；`enable_speaker_info` | — | 🔇 **成败看头 `X-Api-Status-Code == 20000000`**；子码见 16 §10.2 | 【实现】 | 16 §10.2；06 §2 | 122 |
| 私有 SDK | Google Gemini | `gemini-3.5-transcribe` | `google-genai` SDK；≤300 s 整段 | 词级 `word_info`；时间是**带 `s` 后缀的字符串** | — | 多 key 轮换 | 429 也不等；🔇 空字幕、502/503 吞成 None（已修） | 【实现】 | 16 §10.2、§10.3 | — |
| 私有 SDK | Deepgram | — | SDK `transcribe_file`，超时 600 s；>50 MB 先转 mp3 | `utterances[]`（秒） | `speaker`；`diarize`、`utt_split` | 中文去空格、繁转简 | 缺密钥文案曾硬编码「Deepgram」 | 【实现】 | 16 §10.2、§10.3 | — |
| 私有 SDK | ElevenLabs | `scribe_v2`／`scribe_v1` | SDK `speech_to_text.convert`，`diarize: true` | 词级 `words[]`（秒）；跳过 `audio_event` | `speaker_id`（`speaker_N`） | — | — | 【实现】 | 16 §10.2 | — |
| 私有 SDK | CAMB AI | — | 每 3 s 轮询，上限 600 s | `transcript[]`（秒） | `speaker` | 🔇 语言是**整数 ID**，查不到默认英语 | — | 【实现】 | 16 §10.2 | — |
| ⓒ 型三步异步 | Gladia | — | `/v2/upload`（`x-gladia-key`）→ `/v2/pre-recorded` → 每 1 s 轮询 | 直接要 SRT | — | — | — | 【实现】 | 16 §10.2 | — |
| 自定义 API | 用户自建 | — | `POST {url}?sk={key}`（**密钥在查询串**）；字段 `audio` | `{"code": 0, "data": "<SRT>"}` | — | — | 曾 `.lower()` 整个 URL、曾 `eval()` 输出 | 【实现】 | 16 §10.2 | — |

### 3.3 横切数值附表

只留指针：

| 项 | 出处 |
| --- | --- |
| 统一形状、输入音频（16 kHz 单声道 wav，约 1.9 MB/分钟）、语言代码只取主标签 | 16 §2 |
| 静音切片（`silencedetect=noise=-35dB:d=0.6`，<1 s 并入、>25 s 等分）与切单片（补 200 ms 静音，2026-09-13 修复） | 16 §4.1；坑 117 |
| 原 Python VAD 参数（25 s 硬上限、补静音代码实际 400 ms）、`_resegment`、LLM 重断句 | 16 §10.1 |
| 词级 → 字幕块、与服务无关的规整 | 16 §6.1、§6.2 |
| 说话人编号、测分离的嗓音 | 16 §7 |
| 检查点与续跑判据（不要求段数相等） | 16 §9；坑 121 |
| 错误分类原则（按步骤）、错误详情 600 字符 | 16 §8；坑 119 |
| 原 Python 通用教训 | 16 §10.3 |

---

## 4 尚未覆盖

来源明示信息不足或未实测的项统一登记在 31 篇 §2 主表，见 31 篇 §2 媒体相关 OQ：

- 🖼 出图：OQ-009、OQ-010、OQ-035、OQ-036、OQ-037、OQ-038、OQ-045、OQ-048、OQ-049
- 🎬 视频：OQ-008、OQ-034、OQ-039、OQ-040、OQ-041、OQ-050
- 🎤 语音识别：OQ-042、OQ-043、OQ-046、OQ-047、OQ-059、OQ-070；流式／实时 ASR（WebSocket）见 31 篇 §3
- 31 篇未单列的残项：Seedream 4.5／4.0 在按量 base 上的行为——只有文档能力表与套餐 404，按量 key 未实测（13 §4.1；01 §9.3）。

---

## 附录 本表引用的坑

只列媒体面相关坑号（现象、对策见 11 篇 F／J／K／M／N／O／P／Q 节）；chat 面的计费坑（3、4、18、62、77、108、145–197 等）不在本表。

- 🖼 出图：2、6、56、57、58、59、60、78、79、80、81、82、83、84、85、86、87、88、90、91、92、93、101、102、103、104、110、123、124、125、126、127、128、130、131、132
- 🎬 视频：60、113、126、129
- 🎤 ASR：115、116、117、118、119、120、121、122
