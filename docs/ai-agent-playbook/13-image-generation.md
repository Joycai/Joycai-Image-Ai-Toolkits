# 13 · 图像生成/编辑管线（文生图、改图、DashScope 千问/万相）

> 本篇解决的问题：在多协议 AI 层里加一条图像生成与编辑管线——OpenAI images API、
> 中继经 chat 出图、Gemini generateContent、DashScope 原生（qwen-image / wan /
> z-image），以及业内第一条异步任务型出图接口该怎么接。
> 不读会踩的坑：把出图塞进流式管线、按供应商写子类；短时效签名 URL 直接入库，
> 图库一小时后全 404；把「内容审核拒绝」误判成「端点不能编辑」，触发第二次计费
> 的降级重生成；用 model-id 嗅探决定同步/异步，违反分层铁律且一换名就崩。

参考实现：simple-ai-writer `src/lib/ai/image.ts`（四条 route 全在一个文件），
`docs/image-generation-plan.md`（决策记录）、`docs/api/landscape.md`（协议事实）。

---

## 1. 出图客户端是 streamCompletion 的兄弟，不是变体

图像响应是**一个 JSON body**（base64 或短时效 URL），没有 SSE、没有 token
delta、没有 tool loop。硬塞进 `StreamChunk` 会让每个文本消费者绕一个永远
打不中的分支。所以独立一个入口，与流式入口平级：

```ts
generateImage(conn: ImageConn, req: ImageRequest): Promise<ImageResult>

interface ImageRequest {
  prompt: string;
  images?: string[];   // data URL；非空即「编辑」语义——不拆两个函数，
                       // 否则 provider 分派差异会被推给每个调用方
  mask?: string;       // 仅 OpenAI edits 有；其余 route 忽略而非报错
  n?: number; size?: string; aspect?: string;
  extraBody?: Record<string, unknown>;   // 长尾旋钮逃生口（对齐 StreamOptions）
  signal?: AbortSignal;
}
interface ImageResult {
  images: { dataUrl: string; mime: string }[];  // 一切归一到 data URL
  text?: string;    // 模型附带的文字（Gemini 的 text part、DashScope 扩写后的提示词）
  usage?: { inputTokens: number; outputTokens: number };  // 仅 token 计费的模型有
}
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

新增一条 route 的完整清单：枚举加一个值 + dispatch 加一个 case + 设置界面的
route 下拉加一项 + 对应 i18n + 测试文件里一个新 describe 块。route 永远不做
新的默认值——已有供应商行的推导结果不能因为加了新枚举而改变。

## 3. 能力声明而非探测（ImageCaps）

文本模型的能力可以探测（一次便宜的小请求）；**图像端点的探测 = 一次真实计费的
生成**。所以能力全部由作者声明，默认值按协议族猜（官方端点乐观、compat 悲观），
运行期证明声明错了就**可见地**降级：

```ts
interface ImageCaps {
  edit?: boolean;      // false = 编辑请求直接跳过，不浪费一次调用
  sizes?: string[];    // 空 = 请求里完全不带 size（xAI 等端点会 400 该字段）
  maxRefs?: number;    // 一次编辑最多几张参考图
  route?: ImageRoute;  // 不设 = 按协议族推导
  asyncTask?: "sync-only" | "async-only" | "both";  // dashscope 专用，三态（见下）
}
```

**同步/异步是声明的能力，不是 model-id 嗅探。** 且它是**三态**，不是布尔
（2026-08 按官方文档全量核对后修正本篇旧说法）：qwen-image 全系**仅同步**；
`wan2.7-image(-pro)` **同步异步皆可**——同一模型两条路都通，走哪条是用户
偏好（同步简单、异步不怕长任务超时），只有 `both` 档才值得给用户一个选择。
这个事实写进代码就是按模型名分支，改名/新模型即崩，且违反「供应商是数据
不是代码」。声明错了会收到端点自己的明确报错（同步/异步**提交路径不同**，
打错路径报的是路径级 4xx），和 caps 体系其余部分的降级哲学一致。

## 4. DashScope 原生协议（千问/万相出图）

qwen-image / wan / z-image **不走 compatible-mode**——出图只有原生 `/api/v1`
协议，body 形状与 OpenAI images API 完全不同，按 01 篇的标准配得上一个 route
枚举值：

- **原生 base 从既有供应商行推导**：剥掉 base URL 尾部的 `/compatible-mode/v1`
  再拼 `/api/v1`（已是原生地址或裸 host 的输入原样通过）。同一供应商行、同一个
  密钥同时服务文本与出图，国内 / intl 域名都成立——不要让作者为出图建第二个
  供应商（那意味着同一个 key 存两份）。
- **同步端点**（qwen-image-3.0\*、qwen-image-edit\*、z-image-turbo、wan 改图）：
  `POST /services/aigc/multimodal-generation/generation`。
- **body 两段式**：`input.messages[].content` 是 `{image}`/`{text}` part 数组
  （改图 = image part 在前、指令在后；image 收公网 URL 或 data URL），旋钮全在
  `parameters`（`n`、`size`、`negative_prompt`（wan2.7 不支持）、`seed`、
  `watermark`、`prompt_extend`…）。**`extraBody` 要并进 `parameters` 而非顶层**
  ——顶层只有 `model` 和 `input`，放错位置整个逃生口失效。
- **尺寸拼写是 `宽*高`**（如 `1024*1024`），wan 另收 `"1K"/"2K"/"4K"` 预设。
  通用侧的尺寸选择器分隔符放宽为 `/[x*×]/`；发出前把作者写的 `1024x1024`
  归一成端点拼写。`"2K"` 这类无宽高比信息的预设不参与按 aspect 挑选，只作兜底。
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

## 7. 计费与观测

- 无 token 用量的按 `pricePerImage × 张数` 记账，与 token 计费**相加**而非
  二选一（两种口径的模型都存在）。
- 出图调用必须进与文本同一份 API 调试日志（request/response/error 三类目），
  它们按次计费且失败最难复现——恰恰最不该缺席。日志器加一个 **mid-call
  `note(data)`** 通道，记录「调用没走完就没了也想要」的事实（异步任务的
  task_id 是第一个用例）。

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
- [ ] 异步任务：总 deadline 罩全程；sleep 可被 abort 打断；瞬时失败限次容忍；
      task_id 提交后立刻入日志；FAILED 把 `output` 整段作错误 body。
- [ ] 编辑降级判定：NoImageError 永不触发；结构化 code/param 优先且只认指名
      模型的；prose 正则排除含 param 字样的 body；降级结果带可见的 degraded 标记。
- [ ] 一切 URL 响应当场下载内联（一次重试）；下载校验 content-type；mime 从
      magic bytes 嗅探；multipart 不手动设 Content-Type。
- [ ] 出图调用进 API 日志，异步路径有 mid-call note；per-image 与 token 计费
      相加记账。
