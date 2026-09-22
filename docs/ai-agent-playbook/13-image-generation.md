# 13 · 图像生成/编辑管线（文生图、改图、DashScope 千问/万相、火山方舟 Seedream、MiniMax、xAI、Imagen、Midjourney）

> 本篇解决的问题：在多协议 AI 层里加一条图像生成与编辑管线——OpenAI images API、
> 中继经 chat 出图、Gemini generateContent、DashScope 原生（qwen-image / wan /
> z-image）、字节跳动火山方舟 Seedream（含流式逐张推送与拆图层）、MiniMax image-01、
> xAI Grok Imagine、Imagen `:predict`、Midjourney 代理，以及异步任务型出图接口该怎么接；
> 结构化出图结果（图层）怎么落库、怎么在画布上还原。
> 不读会踩的坑：把出图塞进流式管线、按供应商写子类；短时效签名 URL 直接入库，
> 图库一小时后全 404；把「内容审核拒绝」误判成「端点不能编辑」，触发第二次计费
> 的降级重生成；用 model-id 嗅探决定同步/异步，违反分层铁律且一换名就崩。

出处：simple-ai-writer `src/lib/ai/image.ts`（四条 route 全在一个文件），
`docs/feature/image-generation-plan.md`（决策记录）、`docs/api/landscape.md`（协议事实）；
Joycai Image AI Toolkits（Flutter）`lib/services/llm/protocols/*_images_protocol.dart`、
`chat_image_extraction.dart`、`docs/api/{volcengine-ark,minimax,qianwen-bailian}.md`。

目录：
- §1 出图入口是对话流式入口的兄弟，不是变体
- §2 route：按端点分发，不按供应商（总表 + surface 由用户声明）
- §3 能力声明而非探测
- §4 DashScope 原生（千问 / 万相）：逐模型参数档、异步任务流
- §4.1 火山方舟 Seedream：版本能力表、组图、5.0 pro 专属任务、流式出图、拆图层实测形状
- §4.2 其余几家：images-api（OpenAI）· imagen · xai-images · minimax · midjourney · 经 chat 出图的中继
- §5 编辑降级的判定
- §6 响应统一化：一切归一到字节（含中继回图形状、去重、空结果即失败）
- §7 计费与观测
- §8 结构化出图结果：拆图层的落库与画布还原

---

## 1. 出图入口是对话流式入口的兄弟，不是变体

图像响应是**一个 JSON body**（base64 或短时效 URL），没有 SSE、没有 token
delta、没有 tool loop。硬塞进 `StreamChunk` 会让每个文本消费者绕一个永远
打不中的分支。所以独立一个入口，与流式入口平级：

```text
出图(连接, 请求) -> 结果

请求 = { prompt,
         images?     data URL 列表；非空即「编辑」语义——不拆两个入口，
                     否则按供应商分派的差异会被推给每个调用方
         mask?       仅 OpenAI edits 有；其余 route 忽略而非报错
         n?, size?, aspect?,
         extraBody?  长尾旋钮逃生口（与对话入口同义）
         取消信号 }
结果 = { images: [{ 字节或 data URL, mime }]   一切归一到字节
         text?     模型附带的文字（Gemini 的 text part、DashScope 扩写后的提示词、dall-e-3 的 revised_prompt）
         usage?    { inputTokens, outputTokens }  仅 token 计费的模型有 }
```

## 2. ImageRoute：按端点分发，不按供应商

出图端点**不能从 ApiStandard 推导**：newAPI 式中继讲 OpenAI 协议，却把
Gemini/Flux 图像模型挂在 `/chat/completions` 上，它们的 `/images/generations`
只认 Imagen（"only imagen models are supported"）。同一供应商、同一协议、
按模型走不同端点——所以 route 是 **L3 可声明**的枚举，默认值按协议族推导
（gemini 族 → `gemini`，其余 → `images-api`），显式声明永远赢：

| route | 端点 | 编辑的表达 | 响应形状 |
| --- | --- | --- | --- |
| `images-api` | `POST /images/generations`；编辑另走 `/images/edits`（**multipart**） | 不同 URL + 不同编码 | `data[].b64_json / url` |
| `chat` | `POST /chat/completions` | 多模态 user 消息 | `message.images[]` / content parts / 正文里的 `![](…)` markdown——中继各放各的，全都要接 |
| `gemini` | `POST /models/{id}:generateContent` + `responseModalities:["TEXT","IMAGE"]` | 输入图就是额外 parts | `candidates[].content.parts[].inlineData` |
| `dashscope` | 原生 `/api/v1`（见 §4） | 输入图是 content parts | `output.choices[].message.content[].{image}` 或 `output.results[].url` |
| `ark` | `POST {base}/images/generations`（与 `images-api` 同路径，见 §4.1） | JSON 的 `image` 字段（URL / data URL，单张或数组） | `data[].{url\|b64_json, size}`，组图里单项可以是 `{error}`；`stream:true` 时是 SSE 逐张事件 |
| `imagen` | `POST /models/{id}:predict`（**不是** `:generateContent`） | 无——纯文生图 | `predictions[].bytesBase64Encoded`，无 usage |
| `xai-images` | `/images/generations`；编辑 `/images/edits`（**JSON**，不是 multipart） | 1 张 `image:{url}`，2–3 张 `images:[{url}…]`（互斥），提示词里用 `<IMAGE_0>` 指代 | OpenAI 形 `data[]` |
| `minimax` | `POST /v1/image_generation`（挂在 `/v1` 下但**不是** Images API） | 没有编辑——只有 `subject_reference` 主体参考（§4.2） | `data.image_urls[]` + `base_resp`，逐图计数在 `metadata` |
| `midjourney` | midjourney-proxy 的 `/mj/submit/imagine` → `/mj/task/{id}/fetch`（异步） | `base64Array` 垫图 | 任务记录 `{status, progress, imageUrl, failReason}` |

**surface 由用户声明，id 分类只做默认值。** 中转站的模型名是自由文本（`nano-banana-pro`
按 id 分类是 chat、`my-sora` 什么都不是）；让模型行上一个用户可改的「类型」字段（图像 / 视频 /
对话）决定走哪个 surface，未声明时才退回按 id 分类——退回路径与改动前逐字节相同。再给「走
渠道的 chat 面出图」起一个名字（如 `chat-image`），它不是新协议，是一直存在的 chat 兜底路由，
有了名字中转上的 `gpt-image-1` 才能被强制走 chat。它的能力保底表必须 `isImageGenerator:true`：
③ 据此发 `responseModalities:["IMAGE"]`，① 据此把「整条回复就是一个链接」当图下载——假了就是
请求成功、图被丢。**中转不提供厂商原生出图协议**（原生路径从 endpoint 推导，在中转 host 上
无意义）；例外是路径本身就是 `{base}/images/generations` 的（Seedream、grok-imagine），可在
中转上作为 auto。

新增一条 route 的完整清单：枚举加一个值 + dispatch 加一个 case + 设置界面的
route 下拉加一项 + 对应 i18n + 测试文件里一个新 describe 块。route 永远不做
新的默认值——已有供应商行的推导结果不能因为加了新枚举而改变。

## 3. 能力声明而非探测（ImageCaps）

文本模型的能力可以探测（一次便宜的小请求）；**图像端点的探测 = 一次真实计费的
生成**。所以能力全部由作者声明，默认值按协议族猜（官方端点乐观、compat 悲观），
运行期证明声明错了就**可见地**降级：

```text
出图能力声明（模型级，全部可选）：
  edit?       false = 编辑请求直接跳过，不浪费一次调用
  sizes?      空 = 请求里完全不带 size（xAI 等端点会 400 该字段）
  maxRefs?    一次编辑最多几张参考图
  route?      不设 = 按协议族推导
  asyncTask?  sync-only | async-only | both   dashscope 专用，三态（见下）
```

**同步/异步是声明的能力，不是 model-id 嗅探**（嗅探 = 按模型名分支，改名/新模型
即崩，且违反「供应商是数据不是代码」）。且它是**三态**，不是布尔：qwen-image
全系**仅同步**；`wan2.7-image(-pro)` **同步异步皆可**——同一模型两条路都通，
走哪条是用户偏好（同步简单、异步不怕长任务超时），只有 `both` 档才值得给用户
一个选择。声明错了会收到端点自己的明确报错（同步/异步**提交路径不同**，
打错路径报的是路径级 4xx），和 caps 体系其余部分的降级哲学一致。

## 4. DashScope 原生协议（千问/万相出图）

qwen-image / wan / z-image **不走 compatible-mode**——出图只有原生 `/api/v1`
协议，body 形状与 OpenAI images API 完全不同，按 01 篇的标准配得上一个 route
枚举值：

- **原生 base 从既有供应商行推导**（剥 `/compatible-mode/v1` 拼 `/api/v1`，见第 1 篇 §8.4）：同一供应商行、同一个密钥同时服务文本与出图——不要让作者为出图建第二个供应商（那意味着同一个 key 存两份）。
- **同步端点**（qwen-image-3.0\*、qwen-image-edit\*、z-image-turbo、wan 改图）：
  `POST /services/aigc/multimodal-generation/generation`。
- **body 两段式**：`input.messages[].content` 是 `{image}`/`{text}` part 数组
  （改图 = image part 在前、指令在后；image 收公网 URL 或 data URL），旋钮全在
  `parameters`（`n`、`size`、`negative_prompt`（wan2.7 不支持）、`seed`、
  `watermark`、`prompt_extend`…）。**`extraBody` 要并进 `parameters` 而非顶层**
  ——顶层只有 `model` 和 `input`，放错位置整个逃生口失效。
  **qwen 与 wan 的信封完全相同**，区别只在 content 里 part 的顺序：qwen 图在前、
  文在后，wan 文在前、图在后。【实测 2026-09-19】wan2.7-image-pro 把 `messages`
  放在顶层会得到 `400 InvalidParameter: Field required: input.messages`。
  这个顶层写法来自一份二手文档镜像，官方页没有这么写（坑 101）。
- **尺寸拼写是 `宽*高`**（如 `1024*1024`）。**只有 wan** 另收 `"1K"/"2K"/"4K"` 预设；
  qwen-image-3.0 收到 `"1K"` 会回 400 `Expected format: '<width>*<height>'`。
  通用侧的尺寸解析分隔符放宽为 `/[x*×]/`，发出前把作者写的 `1024x1024`
  归一成端点拼写。`"2K"` 这类预设没有宽高比信息（关键字本身出方图），
  不参与按 aspect 挑选，只作兜底。
- **`size` 永远显式发**：【外部实测 2026-09-04】qwen-image-3.0-pro 与
  wan2.7-image-pro 省略 `size` 都出 2048²，并按 2K 档计费（qwen 是 1K 档的两倍价）。
  qwen 改图省略 `size` 时画幅跟随输入，但同样放大到 2K 面积（768×1376 的输入
  出 1520×2736）。默认值的合理写法：qwen 文生图发 `1024*1024`；qwen 改图按第一张
  输入图的比例在 1K 面积内重算（16 的倍数，面积 ≤1024²，比例夹在规则上限内）；
  wan 发 `"1K"`。唯一不发的是基础版 `qwen-image-edit`，它没有 `size`（坑 102）。
- **发之前先按目标模型的规则校验 `size`**：任务参数会比选它的模型活得久，比如重试
  时换了模型，或者值是从别的厂商那边留下来的（`auto`、另一家的像素值）。
  不合当前模型规则的值要换成该模型的默认值，不要原样转发出去吃 400。
- **响应里的图是 URL 且 24 小时过期**——拿到立刻下载内联（§6）。
- **错误是顶层 `{code, message}`**（不是 OpenAI 的 `{error:{…}}`；任务失败时
  嵌在 `output` 里）。错误解析必须兼容两种形状，否则 `DataInspectionFailed`
  （内容审核拒绝）丢掉结构化 code，掉进 prose 正则被误读（§5）。
  `Throttling`/429 = 限流；HTTP 200 带 `code` = body 里送达的错误，照常抛。

### 逐模型参数档（2026-08 官方文档核对，坑都在档位差里）

- `wan2.7-image(-pro)`：参考图 0–9 张（≤20MB，单边 240–8000px）；`n` **默认
  4 且按张计费**——不显式发 `n:1` 的客户端每次请求花四倍的钱；size 收
  `1K`/`2K`（pro 另有 `4K`）或 `宽*高`；特有旋钮 `enable_sequential`（组图，
  n 上限变 12）、`bbox_list`（编辑选区）、`color_palette`、`thinking_mode`；
  **不支持 `negative_prompt`**（qwen 系才有）。
- qwen-image 系：参考图 1–3 张（≤10MB）；`n` 1–6，**但 `qwen-image-edit`
  基础版固定 1 且不支持 `size`**——同家族行为不同，参数表必须逐模型建档，
  填错即 400。
- 响应提图的键：qwen 系 content 项只有 `image` 键，wan 系多一个
  `type:"image"`——提图逻辑不得依赖 `type` 存在。

### 自由尺寸的规则（逐模型不同，按数据建档）

【文档 2026-09，2026-09-19 复核】各模型对 `宽*高` 的约束不是同一种，校验器要能表达
「面积区间」和「单边区间」两类规则：

| 模型 | 约束 | 比例上限 | 关键字 |
| --- | --- | --- | --- |
| `qwen-image-3.0(-pro)`、`qwen-image-2.0(-pro)` | **总像素** 512²–2048² | 1:8–8:1 | 不收 |
| `qwen-image-edit-max` / `-plus` | **单边** 512–2048（不是面积）；缺省约 1024² 且保持原图比例 | 由单边区间推出，最多 4:1 | 不收 |
| `qwen-image` / `-plus` / `-max`（初代文生图） | **只收五个固定值**：`1664*928`（缺省）、`1472*1104`、`1328*1328`、`1104*1472`、`928*1664` ⚠ | — | 不收 |
| `qwen-image-edit`（基础版） | 不支持 `size` | — | — |
| `wan2.7-image` | 总像素 768²–2048² | 1:8–8:1 | `1K` `2K` |
| `wan2.7-image-pro` | 总像素 768²–4096²（4K 文档只在文生图语境下出现，改图是否接受未写明 ⚠） | 1:8–8:1 | `1K` `2K` `4K` |

所有边长落在 16 的倍数上。

**wan 官方推荐尺寸不是精确比例**【文档 2026-09-19】：`1K`=1024²、`2K`=2048²、`4K`=4096²；
16:9 → 1696×960 / 2688×1536 / 4096×2304；4:3 → 1472×1104 / 2368×1728 / 4096×3072
（竖版对调）。其中 2688×1536 是 1.75:1，不是 1.778:1。所以用精确比例去反查「这是
哪个比例芯片」会把官方格子认成自定义比例。反查要给容差（参考实现用 3%），
认出芯片后改用芯片的精确比例继续算。

**计费档按面积落档**：qwen 按输出面积分 `qima_output_1k` / `qima_output_2k` 两档，
wan 按张计费，usage 里回显 `size`。

**实测结果**【实测 2026-09-19，北京节点，每次 `n:1`、`prompt_extend:false`】：
返回图片的像素（读 PNG IHDR）与发送的 `size` 完全一致。

| 模型 | 发送 `size` | 返回 | usage 要点 |
| --- | --- | --- | --- |
| wan2.7-image-pro | `2688*1536`（16:9 · 2K 官方格） | 2688×1536 | `{image_count:1, size:"2688*1536", input_tokens:1351, output_tokens:2}` |
| qwen-image-3.0 | `2304*1728`（4:3，≈3.98 MP） | 2304×1728 | `{output_width:2304, output_height:1728, output_image_type:"qima_output_2k", input_image_type:"qima_input_2k"}` |
| wan2.7-image | `960*1696`（9:16 · 1K） | 960×1696 | `{image_count:1, size:"960*1696"}` |

推论：自由 `宽*高` 在这两个家族上照原样出图，不会被悄悄改尺寸；qwen 越过
1024² 面积就落进 2K 档。给用户做尺寸选择器时，应当把计费档标出来。
- `task_id` 与结果 URL 均 24h 有效；官方建议轮询 5–10s。

### 异步任务流（wan2.7，用户可选的第二条路）

提交 `POST /services/aigc/image-generation/generation` + 请求头
`X-DashScope-Async: enable`（**路径与同步的 `multimodal-generation` 不同**，
body 完全一致）→ 拿 `output.task_id` → 轮询 `GET /tasks/{id}`，
`task_status: PENDING/RUNNING → SUCCEEDED/FAILED/CANCELED/UNKNOWN`
（过期也报 UNKNOWN）。轮询循环的设计点：

1. **一个总 deadline 罩住整个任务**（参考值 600s，提交、全部轮询、下载都在
   其内）——生成以分钟计，逐请求的 180s 帽子在这里语义就是错的。总 deadline
   与调用方 `signal` 合成一个信号，喂给每次 fetch **和轮询间的 sleep**
   （`sleep(ms, signal)`，abort 即拒绝）——用户按「停止」必须立刻生效，
   而不是等下一次轮询醒来。
2. **节奏**：~3s 起步，十来次后放缓到 5s（官方建议前 30s 密集）。
3. **瞬时失败限次容忍**：任务已经付费、轮询是廉价 GET，网络抖动或 429 值得
   重试——但连续 3 次就是真错误，照抛。
4. **task_id 提交成功后立刻写进 API 日志**（mid-call note，见 §7）——轮询
   挂死时这是唯一能拿去查任务状态的线索，等成功日志就永远拿不到了。
5. FAILED/CANCELED/未知状态 → 抛错误，把 `output` 整段作为错误 body（code
   与 message 在里面，统一错误解析能读到）。

## 4.1 火山方舟 Seedream（字节跳动 · 豆包）

> 2026-09-18，官方文档（Seedream 4.0–5.0、5.0 pro 教程与 API 参考）+ 订阅套餐 key 实测。
> 供应商行（按量/套餐两个 base、套餐挑拼写、`ep-…` 接入点）见第 1 篇 §9.3。
> 控制台文档是 SPA：WebFetch 只拿到标题，要浏览器渲染后取正文。

**为什么是一条独立 route 而不是 `images-api` 的变体**：路径与 OpenAI 生成端点同形
（`{base}/images/generations`），`model`/`prompt`/`size`/`response_format` 同名同义，但
body 是**超集且缺字段**——没有 `n`/`quality`，参考图走 JSON 的 `image`（不是 `/images/edits`
的 multipart），张数由组图开关表达。body 形状不同 = 配一个枚举值（第 1 篇 §2）。
好处是：只要中转站原样透传 Images API 的 body，同一 route 在中转上也能用（第 1 篇 §9.3 的中转例外）。

- **仅同步**（`stream:true` 例外，逐张推事件，5.0 pro 不支持）：一次请求等到**全部**图画完才
  返回。实测 5.0 pro 1K 单张 **43 s**、5.0 lite 2K 单张 26 s；组图最多 15 张。逐请求超时必须
  **按一次请求可能画的张数放宽**（参考：5 分钟起，每多一张 +40 s，封顶 15 分钟；图层拆分按 17
  张算）——固定 3 分钟的帽子会在组图上把一个已计费的请求判超时。
- **`watermark` 默认 `true`**：不写就在右下角加「AI 生成」字样，照常计费，文档每个示例都显式写
  `false`。客户端**永远明发**这个字段，UI 默认关。
- **尺寸两种写法不可混用**：档位（`1K`/`1.5K`/`2K`/`3K`/`4K`，**按模型不同**）或 `WxH`。
  填档位时宽高比由模型**从提示词里猜**（实测 5.0 pro `1K` 无比例提示回了 `1248x832`，3:2）。
  所以 UI 做成「档位 + 比例」两个控件：比例为自动 = 只发档位；选了比例 = 查文档给的
  「档位 × 比例 → 像素」映射表发 `WxH`（表是 L3 数据，协议只查表，不自己算）。
  `WxH` 约束的是**总像素乘积**，不是单边：5.0 lite 下限 3686400（2560×1440），`1500x1500` 无效；
  5.0 pro 区间 [921600, 4624220]。`1.5K` 这类**小数档位**会撞上按 `\d+K` 解析/排序的通用代码。
- **能力逐版本建档**（坑全在档位差里）：

| 版本 | 档位 | 参考图 | 组图 | 输出格式 | 提示词优化 | 联网搜索 | 专属 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 5.0 pro | 1K·1.5K·2K | 10 | ✗ | png/jpeg | standard/fast | ✗ | 图层拆分、透明背景 |
| 5.0 lite | 2K·3K·4K | 14 | ✓ | png/jpeg | standard | ✓（`tools:[{type:"web_search"}]`） | — |
| 4.5 | 2K·4K | 14 | ✓ | 仅 jpeg | standard | ✗ | — |
| 4.0 | 1K·2K·4K | 14 | ✓ | 仅 jpeg | standard/fast | ✗ | — |

  发了不支持的字段就是 400——`output_format` 只能发给 5.0，`fast` 只能发给 5.0 pro / 4.0。
- **组图**：`sequential_image_generation:"auto"` + `sequential_image_generation_options.max_images`
  （1–15，**默认 15**）。`auto` 时模型**自行决定**画几张，`max_images` 只是上限；且**参考图数 +
  生成数 ≤ 15**——客户端发送前按参考图数收紧上限，不要让端点 400。
- **参考图**：URL 或 `data:image/<fmt>;base64,…`，**`<fmt>` 必须小写**（`image/PNG` 被拒）。
- **5.0 pro 专属任务是互斥模式，不是开关组合**：`layer_decomposition:true`（底图 + 最多 16 个
  带透明通道的图层，`data[]` 按 `z_index` 排，图层带 `name` 与 `bounding_box`；任一层失败 = 整个
  请求失败；`size` 只收档位或 `auto`）与 `background:"transparent"`（只用于图生图，输出恒 png，
  同时发 `output_format:jpeg` 报错）。二者都要求**恰好 1 张参考图**（透明背景还要求它带 alpha）——
  这是纯客户端能判定的前置条件，**发请求前检查**并抛不重试、不计费的错误，别花一次调用去换一个 400。
  UI 上收成一个「任务：生成 / 拆图层 / 透明编辑」的分段控件。编辑选区没有字段，写在 prompt 里：
  `<bbox>x1 y1 x2 y2</bbox>` / `<point>x y</point>`（0–1000 归一化）。
- **响应**：`data[]` 每项 `url`（**24 小时过期**，当场下载，§6）或 `b64_json`，加 `size`。
  **组图里单张失败不影响其余**：那一项只有 `error{code,message}`（审核不通过继续画下一张，500 则
  停止后续）；顶层 `error` 只在一张都没画出来时出现。客户端收下成功的、把失败张数报出来，**不能**
  因为一项 error 就判整次失败——别的图已经计费了。
- **计费按张**：`usage.generated_images`（成功张数）是账单口径；`output_tokens` = Σ(宽×高)/256，
  **仅供参考**。把它塞进通用的 token 用量键，按 token 计价的费用组就会算出一笔假钱——放进私有的
  元数据键里只展示。实测回显的 `model`：非流式是去掉日期的 id（`doubao-seedream-5-0-pro`），**流式是请求里的拼写**【实测 2026-09-18】——
  拿回显做模型识别或回显比对时两条路径要分开对待。`usage.input_images` 是参考图张数（实测拆图层 1、文生图 0）；
  `usage.tool_usage.web_search` 是实际搜索次数，0 = 开了联网但没搜【文档 2026-09-18】。
- **错误信封是 OpenAI 形**（`{"error":{"code","message","param","type"}}`，消息尾带 Request id）；
  审核类 code：`InputTextSensitiveContentDetected` / `InputImageSensitiveContentDetected` /
  `OutputImageSensitiveContentDetected`——按 §5，这些**永远不是**「端点不能编辑」的证据。
- **免费探测一个模型能不能用**：发一个非法 `size`（如 `"1x1"`）。支持的模型在生成前就回
  `400 InvalidParameter`（消息里写该模型的最小像素），不支持的回 `404 UnsupportedModel`——
  一次零成本的请求区分「套餐没开这个模型」与「参数错」，比真画一张便宜（第 6 篇 §8 的纪律）。

### 流式出图（`stream:true`，2026-09-18 实测 5.0 lite）

5.0 lite / 4.5 / 4.0 支持，5.0 pro 回 `400 InvalidParameter param:"stream"`。标准 SSE，`event:` 与
`data.type` 同名：

```
event: image_generation.partial_succeeded
data: {"type":"image_generation.partial_succeeded","image_index":0,"url":"https://…","size":"2496x1664",…}

event: image_generation.completed
data: {"type":"image_generation.completed","usage":{"generated_images":2,"output_tokens":32448,…}}

data: [DONE]
```

- 每张一个 `partial_succeeded`（`image_index` 从 0 起），单张失败是 `partial_failed`（带 `error`
  对象）；`usage` 只在 `completed` 里。
- **响应头要等第一张画完才回来**（`x-envoy-upstream-service-time` ≈ 27 s）。聊天用的「首块 120 s
  空闲守卫」会在 4K 图还在画时把一个已计费的请求掐掉——出图流的首块与后续块都按**单图期限**
  （参考 5 分钟）计，首块超时判期限、不重试。
- **参数校验失败不走 SSE**：`stream:true` 的请求照样回 `400 application/json` 普通错误信封。200 时
  是 SSE 还是 JSON 看 **body 首行**，不看 `Content-Type`——误读会丢掉已计费的一整组。
- **已知事件不做通用错误信封检查**：`partial_failed` 里有 `error` 对象，通用检查会把它当成整个
  请求失败、扔掉已到的图。只对不认识的事件做信封检查。
- **边到边存、按已送达记账**：每张到了就下载落盘；后面失败或用户取消，已落盘的保留，用量按已
  送达张数记（原先只在流跑完时记 = 取消的任务在统计里消失，钱照扣）。
- 只在官方渠道、且表上声明了流式的版本发 `stream:true`；中转与 5.0 pro 照旧同步——中转是否透传
  SSE 未知，拒收 `stream` 的中转会把能用的渠道变成 400。
- App 内实测（套餐、5.0 lite、`2K`、组图上限 2）：第一张 **27.9 s** 落盘，第二张 **48.4 s**；只发档位
  时模型两张都自选了 16:9（2848×1600）。

### 拆图层的实测形状（5.0 pro，1500×1920 单人立绘，`size:"1K"`，不写 prompt）

200，**37 s**。`data[]` 两项：`z_index:0` 底图 912×1168 jpeg（人物被抹掉只剩背景）；`z_index:1`
图层 861×1137 RGBA png，带 `name`、中文 `description`、`bounding_box.absolute:[27,0,888,1137]`
（**底图像素**，不是输入图像素）与 `.normalized`（0–1000）。自动拆时整个人物是**一层**，不会再拆
头发、衣服。`usage.generated_images` = 实出张数（2），不是超时预算用的 17。落库与还原见 §8。

## 4.2 其余几家的逐家事实（按 route）

- **`images-api`（OpenAI / 兼容）**：编辑的 multipart 字段名**跟张数走**——1 张发 `image`、多张发
  `image[]`。只发复数时 dall-e-2 的编辑与照它写的中继对单张图 400，而单数哪里都收。每个文件
  part 显式带 `Content-Type`（有中继对默认的 octet-stream 400【实测 2026-09-05】）。gpt-image-1 参考图上限 16。
  dall-e-3 逐项回 `revised_prompt`（实际画的提示词，放进结果 text），gpt-image-1 不回。
  用量拼写是 `input_tokens`/`output_tokens`（不是 chat 的 `prompt_/completion_tokens`），
  记账要两种都认。端点回显的 `size`/`quality` 是**定了的规格**（请求写 `auto` 时只有回显才有规格），
  按规格计价的费用组优先用回显。
- **`imagen`（Gemini `:predict`）**：纯文生图。用户附了参考图要**显式警告**而不是静默丢掉；
  响应没有 token 用量——元数据至少放张数，否则按次计费的调用在统计里整条消失（§7）。
- **`xai-images`（Grok Imagine）**：编辑是 JSON（`image:{url:<data URI>}` 或 `images:[…]`，二者互斥）；
  参考图上限**文档写 3 张【文档 2026-09】，实测 5 张 HTTP 200 并按 5 张收费【实测 2026-09-21】**——旧结论
  「最多 3 张」被推翻，按 5 截断。`aspect_ratio` 收 `auto`；清晰度走 `resolution: 1k|1.5k|2k`（不是 `size`；`1.5k`
  只有 2.0 收）；要 `response_format:"b64_json"` 省一次下载。`respect_moderation:false` 之类会让 `url`/`b64` 都空——
  空即失败。
  **质量（`grok-imagine-image-2.0`，【实测 2026-09-22】）**：请求字段 `quality`，枚举 `low | medium | high | auto`
  （别的值 → 422，错误信息列出枚举）；2.0 只收 `low / medium / auto`（`high` → 400 `This model only supports the following
  quality value(s): low, medium, auto.`）；**不带 = medium**。OpenAPI（`docs.x.ai/openapi.json`）的请求体**没列** `quality`，
  只有 `ImagePricingTier` 一句「Medium is the default quality a request serves at when it leaves `quality` unset」——文档与
  OpenAPI 不一致，以实测为准。`GET /v1/image-generation-models/{id}` 回 `image_price` + `pricing[{quality, resolution,
  price_per_image}]`（`price_per_image` 单位 1e-8 美分 = 1 tick，见 §7）；2.0 六格：1K·Low $0.04 / 1.5K·Low $0.05 /
  2K·Low $0.06 / 1K·Medium $0.06 / 1.5K·Medium $0.07 / 2K·Medium $0.08。**初代 `grok-imagine-image`（$0.02）与
  `grok-imagine-image-quality`（$0.05）是 `pricing: []`（各质量同价）**：它们**默默收下** `quality`（一个骗人的旋钮，别在
  UI 上给），而 `resolution: 1.5k` → 400 `1.5K resolution is not supported for this model.`（坑 125）。`quality: auto` 由模型
  定档（一次实测选了 Low，$0.04）——按规格计价的表写不出它（坑 124）。
- **`minimax`（`image-01` / `image-01-live`）**：**不是** Images API，也到不了 Images API。
  `aspect_ratio`（8 种）与 `width/height`（512–2048、8 的倍数、仅 `image-01`）是同一件事的两种拼法；
  `n` 1–9；`style` 仅 `-live`；`aigc_watermark` 默认关。`subject_reference[{type:"character", image_file}]`
  是**主体参考**，把参考图里的**人物**带进新画面——这条 wire 上不存在「编辑」：喂风景图要求调色
  会正常返回一张无关的图，所以 caps 要声明 `edit:false`、UI 要说清。**两层失败**：`base_resp.status_code≠0`
  是请求级（过期 key、余额、审核都是 HTTP 200）；`status_code==0` 但 `metadata.success_count==0`
  是逐图失败——只看前者，症状只是「结果为空」。**`success_count`/`failed_count` 实际是字符串**
  （`"0"`/`"3"`），按数字判会静默永不命中，两种都认。URL 24 小时过期。同步但慢：模型声明
  「长任务」，路由据此放宽单请求超时。
- **`midjourney`（midjourney-proxy / New API `/mj/*`）**：独立 L1 协议，异步：submit → 轮询 →
  下载。提交回执 `code` 1 = 成功、22 = 排队中（也算建好）；**task id 一出现就写日志**（已计费，
  轮询死了这是唯一线索）。轮询 3 s、总帽 10 分钟，走共享轮询循环（可取消、容忍几次失败的 fetch）；
  放弃时抛「已放弃的任务」且**永不重试**——重试 = 再付一次 imagine。把每次进度作为一个文本 chunk
  推出，顺带让 chat 的空闲守卫不超时。参数（比例、版本、stylize、chaos、quality）在 UI 用下拉，
  发出前改写成 `--ar/--v/--s/--c/--q` 拼进 prompt；**用户自己写了的 flag 优先**；`--v niji 6` 改写成
  `--niji`。代理没有 `/models`，给内置目录。调试日志里把 `base64Array` 截断成计数。
- **经 chat 出图的中继（`chat` route）**：见 §6 的形状清单。New API 的 Gemini 出图走 ① 形状时
  出图参数**只认 `extra_body.google.image_config`**（snake_case：`aspect_ratio`/`image_size`；
  camelCase 被拒、顶层 `image_config` 不读）——发错位置宽高比与分辨率**静默无效**；走 ③ 原生形状
  时中继**不替你补** `responseModalities`，老模型只回文本。所以同一个模型走 ① 反而更稳。
  **出图模型的纯文本消息也发成单元素 part 数组**：有中转把这次 chat 调用翻译成出图请求，字符串形 `content` 回
  `400 images[0] must be an http/https URL or image data URI`，同一段文字包成 `[{"type":"text","text":…}]` 就收【实测 2026-09-05；坑 110】。
  只对声明为出图的模型这样发；对话模型保持字符串——那是所有宿主都收的形状。

## 5. 编辑降级的判定：宽松方向的误判 = 二次计费

「这个端点不能编辑」触发可见的降级重生成（**另一次全价调用**），所以判定
必须只认「路由缺失」证据，拿不准一律不降级：

1. **模型自己说的话永远不是证据**。「模型只回了文字」（NoImageError）常见于
   文本模型被配成图像模型，其正文里往往就有 "I don't support image editing"
   ——拿去匹配正则就是白花一次生成费。
2. **404 / 405 / 501** = 端点不存在，降级最初就是为这个存在的。
3. **有结构化 code/param 就信它**：只有指名「模型」的才算路由缺失
   （`param === "model"` 或 model_not_found 类 code）。
   `Unsupported parameter: 'x' is not supported with this model.` 带
   `param:"x"`——请求被理解了，丢掉那个字段就能修，重生成是双倍计费。
4. **纯 prose 才落到正则**，且只匹配明确谈「编辑」或「模型」的措辞；正文里
   出现 param/parameter 字样直接判否。

配合两层跳过：声明 `edit:false` 的模型连第一次调用都不发；运行期失败经上述
判定后重试为纯生成，并把 `degraded` 标记透出到 UI/工具结果——降级必须可见。

## 6. 响应统一化：一切归一到字节

- **URL 一律当场下载内联成 data URL**。签名 URL 普遍短时效（DashScope 明文
  24 小时），存链接的图库会静默腐烂。已计费的图值得**一次重试**（刚铸的链接
  + 抖动的网络都常见，另一边是整次生成打水漂）。
- **下载校验 content-type**：中继用 200 + HTML 错误页应答很常见，不校验就会
  往图库写一个谁都打不开的 `.png` 而 UI 报成功。
- **mime 从 magic bytes 嗅探**：`data[].b64_json` 线格式不带 mime，端点却
  可能按 `output_format` 回 JPEG——猜 PNG 会写出扩展名撒谎的文件。
- **base64 出现在 `url` 字段**（中继习惯）：识别 `data:` 前缀直接收下——
  当链接 fetch 在浏览器里碰巧能跑，在桌面端 HTTP 栈里不行。
- **multipart 编辑（OpenAI `/images/edits`）绝不手动设 `Content-Type`**：
  boundary 由运行时序列化 FormData 时生成，手写的头恰好把它抹掉，服务端
  永远解析失败。
- **只有一个交付物的端点，空 = 失败**。Images API / Imagen / xAI / MiniMax 回 200 却一张图都解不出
  （中继的 200 + `{"error":…}`、审核拦截、字段缺失），返回空结果会被任务层读成「成功生成了零张」，
  与模型拒绝无法区分——要抛错并说明实际回来了什么。解析顺序：状态码 → 是不是 JSON → 形状 →
  错误信封。
- **经 chat 出图的回复形状（中继各放各的，全都要接）**：`content` 里的 markdown
  `![image](data:…)` 或 `![image](https://…)`（对象存储型中继给链接，只认 data URI 就是零张图）；
  `message.images[].image_url.url` / `images[].b64_json` / `images[].url` / 裸字符串；
  `message.image_b64_json`；以及**整条回复就是一个裸链接或裸 base64**（同一中继同一模型一小时内
  两种都见过，取决于它挑的上游）。两道闸防误收：裸链接只在模型声明为出图模型时才下载（对话
  模型回一个 URL 是在引用，不是交付）；裸 base64 至少 64 个字符**且解码后 magic bytes 是图片**
  （一个英文单词也在 base64 字母表里）。
- **同一张图在一个回复里出现多次**：见过中继把同一张图同时放在 `content`（裸 base64）、
  `images[0].b64_json`、`image_b64_json` 三处，各存成一个文件。按**字节的 SHA-256** 去重，
  与字段、编码无关。

## 7. 计费与观测

- 无 token 用量的按 `pricePerImage × 张数` 记账，与 token 计费**相加**而非
  二选一（两种口径的模型都存在）。
- 出图调用必须进与文本同一份 API 调试日志（request/response/error 三类目），
  它们按次计费且失败最难复现——恰恰最不该缺席。日志器加一个 **mid-call
  `note(data)`** 通道，记录「调用没走完就没了也想要」的事实（异步任务的
  task_id 是第一个用例）。
- **按次计费的出图，用量元数据永不为空。** 很多记账路径「元数据非空才记一行」；Imagen、MiniMax
  这类不回 token 的端点返回 `{}` 就会在统计里整条消失——上游照扣。至少放张数。
- **按张计费的端点，别把像素折算的 token 塞进通用 token 键**（Seedream 的 `output_tokens`
  = 像素/256），放私有键只展示（坑 83）。
- **有的端点直接报钱。** xAI images 的 `usage` 只有一个字段 `cost_in_usd_ticks`，**1 tick = $10⁻¹⁰**（OpenAPI 把
  `price_per_image` 定义为 "1/100,000,000ths of a USD cent"；实测 400 000 000 = 1K·Low $0.04）【实测 2026-09-21/22】。
  它**含输入图**（$0.06 + 5 × $0.01 = 1 100 000 000），是**整单实扣**——压过任何本地算式，不与 token / 按张**相加**
  （上一条的「相加」规则对它不适用）；回包里**没有**输入张数，张数只能自己数。「没报」（字段缺）与「报了 0」要分开存
  （NULL vs 0）。经中转（走 Images API 形状）时这个字段可能原样透传，但**那是 xAI 收中转的价，不是用户付中转的价**——
  只在自家协议上读它。**视频面同样报**（`GET /v1/videos/{id}` 的 done 回包 `usage.cost_in_usd_ticks`，提交回包没有；14 §2）【实测 2026-09-22】。
- **输入图按张计费，与输出分开标价**【2026-09-21 查证】：xAI 2.0 **$0.01/张、线性、无免费张数**，`n:2` 时**按请求收一次、
  不乘输出张数**（1 张参考图 + `n:2` + low = 900 000 000 = 2 × 0.04 + 1 × 0.01【实测 2026-09-22】）；**xAI 视频面同价**（1.5：首帧
  `image` +$0.01、`reference_images` 每张 +$0.01，标价页只写 $0.08/s【实测 2026-09-22】）——按秒计价的组也要有输入图一侧；Seedream 5.0 pro
  0.02 元/张、**每次请求首张免费**，回报 `usage.input_images`（原始张数）。gpt-image / Gemini image 的输入图在 `input_tokens` 里
  （图像输入单价与文本不同：$8/M vs $5/M，`input_tokens_details.image_tokens` 有明细）。**张数要在组完请求体之后数**：
  按上限截断、再丢掉读不出的附件——截断后的长度会为没发出去的图收钱。**一张没交付就不该收输入费**（方舟明说失败免费）。
  失败 / 被审核拦下的请求上游是否仍收输入费：【未验】——失败的回包走不到记账，只能对账单。
- **计费相关的请求默认值要明发**（与 14 §3.6 同一条）：xAI 不带 `quality` 按 Medium 计（$0.06），不是标价表第一格的
  Low（$0.04）；只发分辨率、本地按「表第一行」估价，会把每张图**低估三分之一**而不报错（坑 123）。默认值写死并发出去，
  用量记录才带得上规格。
- **记账读的中性键是保留键。** 记账层对所有厂商一视同仁地读 `input_image_count` / `reported_cost_usd` 这类**应用自己**的键；
  凡把上游 `usage`（或任何上游 map）**原样铺进** metadata 的地方，都要先剔掉这些键——否则中转或厂商起个同名字段就能定账
  （坑 126）。只有协议自己的换算（tick → 美元、数出来的张数）能写它们，且写在铺之后。聊天四族与 images 各家都有这种原样铺的
  代码（06 §1 给 DeepSeek 补 `cached_tokens` 的那种地方就是）。**流式出图的每个图片块也要带**这两个键：流在出图后、收尾块前
  被放弃时，记账只看到图片块（坑 127）。设计层（计费组 / 用量行快照 / 档位匹配 / 用量页）见 `llm-billing-model` skill。

## 8. 结构化出图结果：拆图层的落库与画布还原（Joycai 2026-09 实现）

一次请求出一组有**叠放关系**的图（底图 + N 个透明图层，各带名字、描述、底图坐标的框），
数据要能跨重启、跨改名还原成原来的画面。

1. **逐图属性是类型化字段，按位置与图对齐，不进通用 metadata。** 响应层
   `imageLayers[i] ↔ generatedImages[i]`；流式时图层信息与它的图**在同一个 chunk** 上。通用
   metadata 跨 chunk 合并，放进去就丢了「哪条属性属于哪张图」。
2. **下载要逐项、保位置。** 通用的「批量解析图片引用」会跳过下载失败的项——后面每张的
   属性全部错位一格。要么逐项下载、失败的位置留空，要么整组失败。
3. **落库按文件路径为主键**，同一次响应一个 `set_id`，列：`z_index`、`name`、`description`、
   `box_left/top/right/bottom`、`created_at`。存图成功后再写；写库失败只记日志、**不丢图**。
   覆盖写同名文件时先删旧行（否则旧图层信息挂在新图上）。这张表是本机索引，**不进备份**
   （路径换机器无意义）。
4. **路径是主键，就要跟着文件走。** 应用内一切改名 / 移动 / 跨目录搬运（改名对话框、AI 批量
   重命名、文件与文件夹移动）都调 `move(old, new)`；文件夹移动按前缀改写（`UPDATE OR REPLACE`，
   目标已有行时以搬来的为准）；删除调 `forget`。为了不让每次文件操作都碰库，维护一个内存索引
   （路径 → z_index，一个可监听值），不在索引里的路径直接跳过——它同时驱动图库卡片上的「图层」角标。
   应用外的改名无法跟踪，行就成了孤儿，读取时文件不存在即忽略。
5. **画布的坐标系是底图像素。** 整个叠放在底图像素网格里摆好，只在最外层整体缩放一次——
   单层分别缩放的话缩放 / 平移时各层会漂移。没有框的层铺满底图。点选 = 从最上层往下找第一个
   可见且框包含该点的层；空白处（含图外地面）取消选择。选中描边用两层描边而**不是 BoxShadow**
   （阴影是填充形状，会把被指的那层染色）。
6. **导出合成图** = 按底图分辨率新建透明画布，可见层自下而上按框拉伸合成；底图隐藏时地面透明、
   画布不缩（图层位置不变）。解码 + 缩放每层几兆像素，放后台 isolate/worker；文件存底图旁
   `<stem>_composite.png`，重名编号 `(2)`、`(3)`，永不覆盖。
7. **实测提醒**：自动拆图时一个人物就是一层，别在 UI 上承诺「头发 / 衣服分层」；要细分得在
   prompt 里点名元素或用 `<bbox>`。

---

## 本篇检查清单

- [ ] 出图入口独立于流式入口；编辑 = `images` 非空，没有第二个函数。
- [ ] 分发按 `ImageRoute` 枚举，route 是 L3 可声明字段；grep 不到按供应商名
      或 model-id 分支的出图代码。
- [ ] `ImageCaps` 全部声明、无探测；`edit:false` 跳过调用；`sizes` 空 = 不发
      size 字段。
- [ ] dashscope route：原生 base 从 compatible-mode base 推导（幂等，裸 host /
      已原生地址均通过）；`extraBody` 并进 `parameters`；尺寸发出前归一成
      `宽*高`；错误解析兼容顶层 `{code,message}` 与 `{error:{…}}` 两种形状。
- [ ] ark route（火山方舟 Seedream）：`watermark` 恒明发（上游默认 true）；档位与 `WxH` 不混发，
      选了比例才查表发像素；按版本出参数表，不支持的字段不发；`max_images` 按参考图数收紧；
      5.0 pro 的拆图层/透明背景在发请求前校验「恰好 1 张参考图」；组图单项 `error` 不判整次失败；
      计费按 `generated_images`，`output_tokens` 不进 token 用量键；超时随张数放宽。
- [ ] ark 流式：只对声明了流式的版本、只在官方渠道发 `stream:true`；首块与后续块按单图期限计；
      SSE/JSON 按 body 首行判断；已知事件不做信封检查；边到边存、按已送达记账。
- [ ] minimax：`base_resp` 与 `success_count`（字符串！）两层失败都查；caps `edit:false`；
      images-api：multipart 字段名按张数 `image` / `image[]`；imagen 附图要警告不静默丢。
- [ ] midjourney：task id 出现即入日志；放弃的任务永不重试；用户写的 `--flag` 优先。
- [ ] 单交付物端点 200 但零张图 = 抛错；chat 出图接住 markdown / `images[]` / 裸链接 / 裸 base64
      全部形状，裸内容过两道闸；按字节 SHA-256 去重；按次计费的用量元数据永不为空。
- [ ] 结构化逐图属性（图层）：类型化、按位置对齐、与图同 chunk；逐项下载保位置；按路径落库，
      应用内改名 / 移动带着行走；画布只在最外层缩放一次；合成在后台按底图分辨率做。
- [ ] 异步任务：总 deadline 罩全程；sleep 可被 abort 打断；瞬时失败限次容忍；
      task_id 提交后立刻入日志；FAILED 把 `output` 整段作错误 body。
- [ ] 编辑降级判定：NoImageError 永不触发；结构化 code/param 优先且只认指名
      模型的；prose 正则排除含 param 字样的 body；降级结果带可见的 degraded 标记。
- [ ] 一切 URL 响应当场下载内联（一次重试）；下载校验 content-type；mime 从
      magic bytes 嗅探；multipart 不手动设 Content-Type。
- [ ] 出图调用进 API 日志，异步路径有 mid-call note；per-image 与 token 计费
      相加记账。
