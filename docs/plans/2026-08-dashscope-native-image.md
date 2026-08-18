# DashScope 原生出图接入方案（qwen-image / wan / z-image）

**性质**：高层设计 + 分期实施计划。不含逐行实现；每期开工前按本文档拆任务。
**输入**：`docs/architecture/llm-three-layer.md`（分层铁律）、`docs/api/landscape.md` §8（已记录"阿里 DashScope 原生 —— `input.messages` + `parameters` 两段式"为未接的自有格式）、ai-agent-architecture skill §13。
**现状**：wan 系列**视频**已可用（`ModelFamily.openaiVideo` → `/v1/videos`，走 OpenAI 兼容中继）；qwen-image / wan 文生图的**原生**通道零支持。

---

## 0. 结论：一个 vendor + 一个 protocol，**不新增 `ProtocolFamily`**

DashScope 的对话走 compatible-mode，就是 ① 家族；**只有出图是自有 wire format**。
这与 xAI 的形状完全同构（chat 兼容、images/videos 原生），因此照抄既有先例：

- 新 `VendorProfile`：`family: ProtocolFamily.openai` + `auth: bearer` + 声明式开关 `usesDashScopeNativeImages`；
- dispatcher 在 ① 分支里按该开关换掉图像协议，chat / stream / discovery 一行不动。

**为什么不新增 family**：`ProtocolFamily` 是 dispatcher 五个 switch 的穷举维度，新增一个值等于要为它实现 chat、stream、LRO、discovery 四套本来毫无差别的分支——DashScope 的对话恰恰**不**需要它们。新增 family 属于「protocol 真正不同」时才付的代价，这里不是。

---

## 1. 分层落点

| 层 | 文件 | 改动 |
| --- | --- | --- |
| 2 · vendor | `vendors/vendor_profile.dart` | 新增 `final bool usesDashScopeNativeImages`（默认 false），与 `usesXaiNativeSurfaces` 并列 |
| 2 · vendor | `vendors/vendors.dart` | 新增 `dashscope = 'dashscope-api'` + profile |
| 1 · protocol | `protocols/dashscope_images_protocol.dart`（新） | `implements ImageGenProtocol`；同步端点 + 异步任务的提交/轮询循环 |
| 1 · protocol | `protocols/dashscope_payload.dart`（新） | **纯函数**：base 推导、payload 构造、响应提图、错误识别、尺寸归一（见 §5 测试策略） |
| 0 · 路由 | `llm_dispatcher.dart` | `generate` / `generateStream` 的 ① 分支各加一条；`generateTimeout` 改判定依据（见 §3.1） |
| 3 · model | `model_family.dart` | 新 `ModelFamily.dashscopeImage` + 分类规则；并入 `isImageGeneration` / `inferTag`；新规则精确匹配 `wan2.7-image`、置于视频块之前（见 §3.2） |
| 3 · model | `model_capabilities.dart` | 按模型（不是按家族）建参数表 —— 参考图上限、`n` 上限、size 方言、`asyncTask` / body 形状全按模型分档（见 §3.4） |
| UI | `widgets/models/channel_wizard_dialog.dart` | `_presets` 加一项 + `_providerTitle` / `_providerSubtitle` 分支 |
| l10n | `l10n/src/{en,zh,zh_Hant,ja}/*.arb` | `providerDashScope` 等键，四语言同步（走 `joycai-l10n` skill） |

---

## 2. 协议层设计

### 2.1 base 地址推导（不让用户建第二个通道）

通道的 `endpoint` 填 compatible-mode 地址（对话直接可用），出图协议在内部推导原生 base：

```
剥掉尾部 /compatible-mode/v1  →  拼 /api/v1
```

幂等要求：输入已是 `.../api/v1`、或是裸 host、或带尾斜杠，都必须得到同一个结果。
**理由**：同一供应商同一把 key 同时服务文本与出图；逼用户建两个通道意味着同一个 key 在库里存两份，改期失效时只改一处。国内域名与 intl 域名都成立，所以推导只认路径、不认 host。

### 2.2 两种 body 形状（**不是一种**）

按 [qwen 图像编辑](https://platform.qianwenai.com/docs/developer-guides/image-generation/image-editing) 与 [万相图像编辑](https://platform.qianwenai.com/docs/developer-guides/image-generation/wan-image-editing) 两篇文档核对，DashScope 出图不是一个统一形状。**产品决策：只支持 wan2.7+**，因此 wan2.6 与 wan2.5 及其专有形状全部不在范围内，落到两种：

| 形状 | 模型 | 端点 | body |
| --- | --- | --- | --- |
| **A** | `qwen-image-2.0/3.0/3.0-pro`、`qwen-image-edit(-max/-plus)` | `POST {base}/services/aigc/multimodal-generation/generation` | `input.messages[].content` 是 `{image}`/`{text}` part 数组；旋钮全在 `parameters` |
| **B** | `wan2.7-image`、`wan2.7-image-pro` | 同步同上；异步 `POST {base}/services/aigc/image-generation/generation` | **顶层** `messages[]`（不套 `input`），`watermark` / `n` 也在顶层，其余在 `parameters` |

> **B 的顶层 `messages` 待复核**：它与 A 的 `input.messages` 直接冲突，来源是镜像站文档的二手摘要。好在这类猜错**会响**（400，不是静默降级），因此按 A 的形状先实现、按端点报错修正即可，不值得为它预付设计预算。以官方 help.aliyun.com 文档为准复核一次。

因此 payload 构造必须**按形状分派**，而不是一个函数加 if。形状的选择是 layer 3 声明的能力（同 §3.3 的 `asyncTask`），协议只读、不 sniff。

**A 形状的细节**（覆盖面最大，期一主力）：

- `input.messages[].content`：改图时 image part 在前、指令在后；image 收公网 URL 或 `data:{MIME};base64,{data}`。
- `parameters`：`n`、`negative_prompt`、`watermark`（默认 false）、`seed`（0–2147483647）、`size`、`prompt_extend`（默认 **true**）、`prompt_extend_mode: "direct"`（仅 3.0）、`enable_thinking`（默认 **true**，仅 qwen-image 系）。
- **顶层只有 `model` / `input` / `parameters`**。将来引入 `extraBody` 逃生口必须并进 `parameters`，放顶层会被整段忽略（静默）。

尺寸方言按形状而异，`ParamSpec` 存通用 `1024x1024` 拼写、**发出前归一**：

| 形状 | 取值 | 范围 |
| --- | --- | --- |
| A（qwen） | `宽*高` | 边长 512–2048 |
| B（wan2.7） | `1K` / `2K`（默认）/ `宽*高` | 768×768 – 2048×2048 |

`1K`/`2K` 这类无宽高比信息的预设不参与按 aspect 挑选，只作兜底。

### 2.3 异步任务流（wan2.7，**备选而非必需**）

限定 wan2.7+ 之后，范围内**没有任何纯异步模型** —— wan2.7 同步异步都给，同步就能出图。所以异步不再是一个必须交付的里程碑，而是同步跑不住时的兜底（见 §3.1：即使同步，120s 的帽子也未必够）。

```
POST {base}/services/aigc/image-generation/generation   + header X-DashScope-Async: enable
  → output.task_id
GET  {base}/tasks/{task_id}   → task_status: PENDING / RUNNING → SUCCEEDED / FAILED
```

轮询循环**藏在 `generateImage()` 内部**（`midjourney_protocol` 已是这个先例：异步 wire 藏在同步接口后面）。不复用 `VideoJobProtocol`：那条路的 poll 契约是 Veo 形状的视频信封，`imageProcess` 执行器不消费它。

循环设计点：

1. **一个总 deadline 罩住整个任务**（建议 600s：提交 + 全部轮询 + 下载都在其内）。逐请求的 120s 帽子在这里语义就是错的（见 §3.1）。
2. **节奏** ~3s 起步、十来次后放缓到 5s。
3. **瞬时失败限次容忍**：轮询是廉价 GET 且任务已计费，网络抖动/429 值得重试，**连续 3 次**即真错误、照抛。
4. **`task_id` 一拿到就写进日志**（`logger` + `LLMDebugLogger`）——轮询挂死时这是唯一能拿去查任务状态的线索；等成功再记就永远拿不到。
5. FAILED / CANCELED / 未知状态 → 抛错，把 `output` 整段作为错误 body（code 与 message 在里面）。
6. **取消**：`imageProcess` 执行器只在 chunk 之间检查 `TaskStatus.cancelled`，同步路径根本没有检查点。异步循环必须自己拿到取消信号（启用异步时一并解决）。

### 2.4 响应与错误

- 出图结果在 `output.choices[].message.content[].image`（A/B 形状）或 `output.results[].url`（异步任务），**是 URL 且 24 小时过期**（qwen 文档明写 24h；万相文档未标注有效期 —— 按同样处理，别赌） → 当场 GET 下载成 bytes 返回 `LLMResponse.generatedImages`（与 `openai_images_protocol` 的 URL 分支一致）。下载**不要带 `Authorization`**：那是 OSS 签名地址，多带头有害无益。
- 错误在**顶层 `{status_code, code, message, request_id}`**，不是 OpenAI 的 `{error:{…}}`；任务失败时嵌在 `output` 里。注意**成功响应里也有 `status_code: 200`**，所以判错的依据是「`code` 字段存在且非空」（成功响应无 `code`），不是「有没有 status_code」。共享的 `throwIfEnvelopeError` **不改**（它认 `error` / `base_resp`，加一条"顶层有 `code` 就算错"会误伤别家正常 body），改为在协议内单独判：`HTTP 200` + 非空 `code` → 抛 `LLMApiException`，message 带上 code 原文。
  - `DataInspectionFailed`（内容审核拒绝）必须保住结构化 code，否则会掉进 prose 正则被误读成"端点不支持编辑"，触发**第二次计费**的降级重生成。
  - `Throttling` / 429 → 走 `LLMApiException(statusCode:)`，`_isRetryable` 才认得。
- **零图必抛**（对齐 B3 教训）：返回空 `LLMResponse` 会被执行器读成"成功生成了 0 张"，与模型拒绝无法区分。

---

## 3. 四个必须同期处理的点（前两个漏了就是静默失败）

### 3.1 `generateTimeout` 的 120s ——**同步路径也会被砍**

`llm_dispatcher.dart:72` 现在只按 `vendor.family` 判定，midjourney 豁免到 11 分钟、其余一律 120s。

**限定 wan2.7+ 之后这条不但没消失，反而是唯一还会静默咬人的**：走同步端点意味着一次 HTTP 请求要等到出图完成，wan2.7 出一张 2K 图未必压得进 120s，超时报出来的是"超时"而不是任何有用信息，而且**那次生成已经计费**。

**做法**：把判定依据从"family 相等"改成"这次请求要走的 route 是不是长任务"——即读 `target.model.capabilities`（`asyncTask` 或一个更直白的 `longRunning` 位，§3.3），midjourney 的既有豁免顺势并进同一个判定，而不是再加一个 `||`。期一就要做，不能等异步。

### 3.2 新分类规则的排序约束（限定 wan2.7+ 后已不是 bug，但仍是陷阱）

`wan2.7-image` / `-pro` 不匹配任何现有规则（落 `other`），需要新规则接住 —— 而且**必须精确匹配 `wan2.7-image`，不能写 `startsWith('wan2.7')`**：那会连未来的 `wan2.7-t2v` 之类视频 id 一起吞进图像家族。新规则放在视频块**之前**，并补测试钉住 `wan2.5-t2v` / `wan2.5-i2v`（现有可用的视频路径）仍判视频。

> 顺带记录一个我们**恰好躲开**的雷：视频块用 `id.startsWith('wan2.5')`，而万相 2.5 的图像编辑模型正好叫 `wan2.5-i2i-preview`（`-i2i` 与视频规则的 `-i2v` 只差一个字母），今天就会被路由到 `/v1/videos`。因为产品决策不支持 2.5 出图，这条不必修 —— 但哪天放开 2.5，它就是第一个要撞的。

### 3.3 同步/异步是**声明的能力**，不是协议里的 model-id 分支

"这个模型走同步还是异步、用 A 还是 B 形状"是事实，但写成协议里的 `if (modelId.startsWith('wan'))` 就违反分层铁律，且改名即崩。

**做法**：在 `ModelCapabilities` 加 `final bool asyncTask`（默认 false），由 layer 3 的参数表声明——`model_capabilities.dart` / `model_family.dart` 是本仓**唯一允许 sniff model-id** 的地方。协议只读 `target.model.capabilities` 决定走哪条端点、拼哪种 body（body 形状同样是一个声明位）。声明错了会收到端点自己的明确报错（同步端点收异步模型 → 400），与现有 caps 体系的降级哲学一致。

### 3.4 参考图与 `n` 的上限**按模型分档**，不能按家族填一个数

文档核对结果 —— 这是 `ModelCapabilities` 必须逐模型建表的原因，一个 `_dashscopeImage` 表填不下：

| 模型 | 参考图张数 | 单图大小 | 边长范围 | 输出 `n` | 异步 | body 形状 |
| --- | --- | --- | --- | --- | --- | --- |
| `qwen-image-2.0` / `3.0` / `3.0-pro` | 1–3 | ≤10MB | 384–3072（建议） | 1–6 | 否 | A |
| `qwen-image-edit-max` / `-plus` | 1–3 | ≤10MB | 384–3072 | 1–6 | 否 | A |
| `qwen-image-edit` | 1–3 | ≤10MB | 384–3072 | **仅 1** | 否 | A |
| `wan2.7-image` / `-pro` | **0–9** | ≤**20MB** | 240–8000 | — | 可选（默认同步） | B |

受支持的输入格式：JPG/JPEG/PNG/BMP/WEBP（qwen 另收 TIFF/GIF）。传入方式：公网 URL 或 `data:{MIME};base64,{data}`（`file://` 仅官方 SDK 支持，本仓用不上）。

**`maxReferenceImages` 因此取 3（qwen 系）/ 9（wan2.7）两档**，不是原先设想的一个家族值；`n` 也要进 `ParamSpec`（`qwen-image-edit` 的上限 1 与同族其他成员的 6 不同，填错会 400）。

---

## 4. 中继上的 qwen-image：行为**不变**（显式决策）

今天 `qwen-image` 在 NewAPI 类中继上落到 `ModelFamily.other` → chat 协议，而 `openai_chat_protocol` 已能从 `images[]` / `image_data` / markdown 链接里提图——**这条路是通的**，只是没声明、没测试。

新增 `ModelFamily.dashscopeImage` 后，dispatcher 分支必须写成：

```dart
if (target.model.family == ModelFamily.dashscopeImage &&
    target.vendor.usesDashScopeNativeImages) {
  return _dashscopeImages.generateImage(...);
}
// 否则继续落到 chat —— 中继路径保持原样
```

反面写法（`dashscopeImage → _openaiImages`）会把中继通道改路到 `/v1/images/generations`，而多数中继并不为 qwen-image 提供该端点——原本能出图的通道会直接坏掉。
副作用（**期望内**）：`isImageGeneration(dashscopeImage) == true` 会让工作台对这些模型显示图像参数面板，中继通道也一样受益。

---

## 5. 测试策略：把可测的部分做成纯函数

本仓**没有 HTTP mock 设施**（`LLMModelConfig.createClient()` 不可注入，现有协议测试全是纯函数测试，如 `image_relay_compat_test.dart` 直接测 `extractStructuredImages`）。因此协议里所有能脱离 IO 的逻辑都放进 `dashscope_payload.dart`，照 `gemini_payload.dart` 的先例。

新增 `test/dashscope_payload_test.dart`，钉住：

| 用例 | 断言 |
| --- | --- |
| base 推导 | `.../compatible-mode/v1`、`.../compatible-mode/v1/`、`.../api/v1`、裸 host 四种输入 → 同一个 `/api/v1` |
| payload 形状 | 改图时 image part 在 text 之前；旋钮全在 `parameters`、顶层只有 `model` / `input` |
| 尺寸归一 | `1024x1024` → `1024*1024`；`2K` 原样；`not_set` 不发字段 |
| 错误识别 | `{code: 'DataInspectionFailed', message: …}`（HTTP 200）→ 抛且 message 含 code；`{output: {code: …}}` 同样识别 |
| 提图 | `output.choices[].message.content[].image` 与 `output.results[].url` 两种形状都取到；都缺 → 抛而非空返回 |
| 分类 | `wan2.7-image` / `-pro` → `dashscopeImage`；`wan2.5-t2v-*` / `-i2v-*` 仍 `openaiVideo`；`qwen-image-edit` → `dashscopeImage` |
| 能力 | 参考图上限逐模型正确：`wan2.7-image` → 9、`qwen-image-edit` → 3 且 `n` 上限为 1（同族其他成员 6） |
| payload 分派 | 同一份 history 在 A / B 两种形状下生成两种 body，各自的顶层字段集正确 |

轮询循环本身（节奏、限次、deadline）不做单测——需要注入 client，成本高于收益；真要启用异步时人工验证一次真实 wan 任务，并把 `task_id` 日志作为可观测兜底。

---

## 6. 分期

| 期 | 内容 | 可独立交付 | 退出标准 |
| --- | --- | --- | --- |
| **期一 · 同步出图（唯一必需）** | vendor + profile 开关 + 同步端点协议 + payload 纯函数（A/B 两形状）+ family/caps + `generateTimeout` 判定改造（§3.1）+ 向导预设 + l10n。覆盖 `qwen-image-2.0/3.0/3.0-pro`、`qwen-image-edit(-max/-plus)`、`wan2.7-image(-pro)` | ✅ | `flutter analyze` 零问题；§5 用例全绿；真机跑通一次文生图 + 一次改图（含一次 2K wan2.7，验证不撞超时） |
| **期二 · 异步兜底（条件触发）** | 仅当期一实测发现同步端点在可接受的超时上限内跑不完时启用：`X-DashScope-Async` 提交 + 轮询循环 + 总 deadline + 取消信号 | ✅（期一之上） | 任务中途"停止"能在 ≤5s 内生效；`task_id` 出现在日志 |
| **期三 · 可选打磨** | discovery（compatible-mode `/models` 是否可用，探测走 `ChannelProbeService` 的 completion 兜底）、计价分组预设、首启向导下拉项 | ✅ | — |

限定 wan2.7+ 之后，**期一即是完整可用形态**：范围内没有纯异步模型，期二从"必做的第二个里程碑"降为"实测不够快才做"。

**风险与回退**：三期彼此独立，任一期回退不影响其余；期一之前所有中继路径行为不变（§4），因此回退面只有新 vendor 自身。

---

## 7. 开工前需要确认的事项

1. ~~通道 endpoint 填哪个~~ —— **已定（产品决策）：只给国内域名**。向导预设固定 `https://dashscope.aliyuncs.com/compatible-mode/v1`，出图协议按 §2.1 从它推导出 `https://dashscope.aliyuncs.com/api/v1`。国际站（`dashscope-intl.aliyuncs.com`）不做预设——推导规则只认路径不认 host，用户手填 intl 地址一样能跑，不必为它单列一项。
2. ~~z-image / wan 改图的参考图上限~~ —— **已由文档回答**，见 §3.4（qwen 系 3、wan2.7 为 9）。`z-image` 未出现在这两篇文档里，且不属于 wan2.7+ 范围，暂不接。
3. **B 形状的顶层 `messages`** 是否属实（§2.2 注）——以官方 help.aliyun.com 文档复核一次，或实现时按 400 报错修正。
