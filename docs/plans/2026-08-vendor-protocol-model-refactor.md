# Vendor–Protocol–Model 路由重构：从「vendor 固定 family」到「按 surface 解析协议」

**性质**：高层架构设计 + 分期实施计划。不含逐行实现。
**状态（2026-08-26）**：A 期 + B 期 + 点单 UI（spec D2 18a–18f）+ D 期的
`dashscope_chat` 私有面已实现并合入本分支 —— `WireProtocol`/surface 菜单、
v36 `wire_protocol` 列、`dashscope_images_async` / `dashscope_video` /
`dashscope_chat` 协议、④ 面复用、模型编辑器四态、列表 chip 与通道副行；
`test/wire_protocol_routing_test.dart` + `test/dashscope_chat_payload_test.dart`
钉住同构与线上规则。私有 chat 面同时带来第五个 `ProtocolFamily.dashscope`
与第二个百炼 vendor（`Vendors.dashscopeNative`，原生打头；原 `dashscope`
仍是兼容面打头），两者 chatMenu 都是原生/①/④ 三项，只是顺序不同。
**未实现**：C 期（MiniMax 视频）、`VideoJobProtocol.cancel`。B 期的真机退出
标准（wan 视频/异步图/④ 面实测）尚未跑，私有 chat 面（文本面 + 多模态面 +
SSE 增量）同样待实测，属发布前验证项。
**输入**：`docs/architecture/llm-three-layer.md`（现行分层）、
`docs/plans/2026-08-dashscope-native-image.md`（百炼出图期一的既有决策，本方案部分推翻它）、
`docs/api/qianwen-bailian.md` + `docs/api/minimax.md`（两家的协议标准文档，与本方案同批产出）、
`docs/api/landscape.md`（三家官方的 surface 全景，§1.4 的盘点依据）。
**触发**：千问（阿里云百炼）一家 vendor 同时提供 3 种 chat 协议
（OpenAI 兼容 / DashScope 私有 / Anthropic 兼容）、2 条图片路径（同步 / 异步任务）、
1 条视频路径（异步任务），且**协议可用性与模型强相关** —— 现行「vendor 固定
一个 `ProtocolFamily`」的绑定方式已经装不下它。

---

## 0. 结论

**不需要在 vendor 和 model 之间新加一层。** Protocol 本来就是 Layer 1 ——
三层齐全，缺的不是层，是**绑定关系**：

- 现状：`vendor → 唯一 family`（1:1），surface 例外靠布尔开关
  （`usesXaiNativeSurfaces` / `usesDashScopeNativeImages`）+ Layer 3 家族嗅探。
- 目标：`(vendor, surface) → 协议菜单 + 默认值`（1:N），model 可以在菜单内
  **点单**（一个持久化的用户选择，`llm_models.wire_protocol`），dispatcher
  负责解析：**model 点单 → vendor 该 surface 的默认 → 现行家族推断**。

`ProtocolFamily` 保留，但身份下降：从「vendor 的属性」变成「每个协议实现的
方言分组属性」。所有现在读 `vendor.family` 的地方改读**解析结果**。

一句话回答「vendor 层固定协议是否恰当」：**chat 主面固定在通道级曾经恰当**
（MiniMax ①/④ 双通道、Google 双面就是这么做的，且继续成立），但它成立的前提
是「同一通道下所有模型走同一条 wire」。百炼打破了这个前提 ——
协议选择与模型耦合（wan3.x 只有异步视频、qwen-image 只有同步、wan2.x 图片
同步异步皆可），所以协议必须能落到模型粒度，vendor 层只声明**菜单**。

---

## 1. 现状为什么撑不住（问题陈述）

现行机制有三种表达「一家多协议」的手段，各自的极限：

1. **多 vendor id + 向导 variants**（MiniMax ①/④、Google 双面、NewAPI 三格式）
   —— 协议选择落在**通道**级。极限：用户要为一家供应商建 N 个通道（同一把
   key 在库里存 N 份）；且表达不了「这个面只服务这些模型」—— 用户必须自己知道
   哪个模型该配哪个通道，配错得到一个不解释原因的 404/400。
2. **VendorProfile 布尔开关 + dispatcher 组合分支**（xAI 原生 surface、
   百炼原生出图）—— 每加一种 surface 组合加一个 bool，dispatcher 里
   `flag × family` 的组合分支平方增长。现在已有 5 处消费点，百炼强化后
   还要加 `usesDashScopeNativeVideo`、`usesDashScopeAsyncImages`……显然不收敛。
3. **Layer 3 家族嗅探**（`ModelFamily.dashscopeImage` → 换图像协议）——
   只能表达「这个模型**只能**走某条路」，表达不了「两条都行、用户选」
   （wan2.x 图片同步 / 异步就是这种）；且对中转乱起名天然脆弱。

而这不是百炼一家的事。把每家供应商的 surface × wire 全景摆出来
（官方协议事实见 `docs/api/landscape.md`，千问见 `docs/api/qianwen-bailian.md`）：

### 1.4 全景盘点：vendor × surface × wire

| Vendor | chat | imageGen | videoJob | 备注 |
| --- | --- | --- | --- | --- |
| **OpenAI 官方** | ① Chat Completions；**② Responses（未接）** | Images API（gpt-image） | `/v1/videos`（Sora，多段式） | ② 与 ① 结构不兼容（item 流、类型化事件、服务端状态）；官方已有 **Responses-only 模型**（o1-pro / o3-pro、codex 系、computer-use，截至 2026-08）—— 哪天要接这些模型，「同一通道、按模型选 chat 协议」就从便利变成**硬需求** |
| **Google 官方** | ③ generateContent；**Interactions（未接）**；OpenAI 兼容面（变体通道） | `:generateContent`（nanoBanana）+ `:predict`（Imagen） | `:predictLongRunning`（Veo） | Interactions 与 ③ 的关系和 ②:① 同构（官方推荐新项目用、旧的不弃用）；Gemini 3 的思考在经典面上「官方文档给不出答案」（landscape §4.1）—— 迟早也是按模型选面的事 |
| **Anthropic 官方** | ④ Messages（唯一 surface） | — | — | 单面 vendor 是**合法的退化情形**：菜单恰好一项，设计不为它付任何复杂度 |
| **xAI** | ① 兼容 | 私有 JSON images | 私有 `/videos/generations` | 今天靠 `usesXaiNativeSurfaces` 布尔开关表达的，正是「surface 槽位」的原型 |
| **千问/百炼** | ①兼容 / DashScope 私有 / ④兼容 | DashScope 同步 / 异步 | DashScope 异步任务 | 三种手段同时逼到极限的第一家（§1 前半） |
| **MiniMax** | ①兼容 / ④兼容（今天是两个通道，模型 id 两面完全一致） | — | **私有 v2 任务面（`MiniMax-H3`，待接，见 §4）** | 视频面落在哪个 chat 通道上都不对 —— 它是 vendor 的 surface，不是某张 chat 面的附属：两个 chat vendor id 都该声明同一个 video 槽位 |
| **中转（NewAPI 等）** | ①/③/④（变体通道） | ① Images / chat 内联提图 | ① `/v1/videos` | 中转的价值恰是「把百家收敛成三族」—— 它们的菜单就是单项，auto 即全部 |
| **本地（Ollama / LM Studio）** | ① 兼容 | — | — | 同上，单项菜单 |

三个结论从表里直接掉出来：

1. **「一家多 chat 协议、且按模型分」不是百炼特色，是行业常态的下一步** ——
   OpenAI 的 Responses-only 模型已经存在，Google 正把新能力搬进 Interactions。
   今天不为它建机制，明天每接一家就再发明一次例外。
2. **surface 目录四个就够**（chat / imageGen / videoJob / discovery）：
   三家官方的全部生成面都落得进去；②/Interactions 是 chat 槽位的**候选协议**，
   不是新 surface。多段式（Sora 的 multipart + `/content` 下载）之类的差异
   藏在协议实现内部，不上升到目录。
3. **菜单退化成单项时设计零开销**：Anthropic 官方、中转、本地运行时都是
   单项菜单，auto 即全部行为，UI 不出现选择器 —— 通用化不向简单情形收税。

百炼只是第一个同时把三种旧手段逼到极限的，所以由它当第一个落地样本。

---

## 2. 目标模型

### 2.1 概念

- **Surface**（调用面）：`chat` / `imageGen` / `videoJob` / `discovery`。
  由调用点（generate vs startLongRunning）+ 模型的任务类型共同决定，
  这一判定本来就在 dispatcher 里，不变。
- **`WireProtocol`**（新枚举，Layer 1 目录）：每个值 = 一个协议实现 +
  它所属的 `ProtocolFamily` + 它服务的 surface。示意：

  ```dart
  enum WireProtocol {
    openaiChat(ProtocolFamily.openai, Surface.chat),
    dashscopeChat(ProtocolFamily.openai, Surface.chat),   // 方言分组见 §2.4
    anthropicChat(ProtocolFamily.anthropic, Surface.chat),
    geminiChat(ProtocolFamily.gemini, Surface.chat),
    openaiImages(...), xaiImages(...),
    dashscopeImagesSync(...), dashscopeImagesAsync(...),
    geminiImagen(...),
    openaiVideos(...), xaiVideos(...), dashscopeVideo(...), geminiVeo(...),
    minimaxVideo(...),
    midjourney(...),
    // 预留、暂不实现（§1.4 的官方第二代 chat surface）：
    // openaiResponses(ProtocolFamily.openai, Surface.chat)
    // geminiInteractions(ProtocolFamily.gemini, Surface.chat)
    // 接入之日只是 chatAlternates 多一项 + 一个新协议类，路由机制零改动。
  }
  ```

- **`VendorProfile.surfaces`**：per surface 的 `默认协议 + 支持集合`，
  替代两个布尔开关。示意：

  ```dart
  class VendorSurfaces {
    final WireProtocol chat;                 // 默认 chat 协议
    final List<WireProtocol> chatAlternates; // 菜单里的其它选项
    final WireProtocol? image;               // null = 用 family 缺省(openaiImages 等)
    final List<WireProtocol> imageAlternates;
    final WireProtocol? video;
    ...
  }
  ```

- **`llm_models.wire_protocol`**（TEXT，可空，v34 迁移）：模型级点单。
  null = auto（今天的全部行为）。

### 2.2 为什么模型级点单不违反 v32 教训

v32 删掉 `llm_models.type` 的理由是：那是**从 channel 可推导的副本**，
副本没有级联更新就是 bug 面。`wire_protocol` 不是副本 —— 它是**新的用户配置**
（「同一通道下这个模型走哪条 wire」，无处可推导），性质与 v33 的
`enable_thinking` / `reasoning_effort` 完全相同：按模型存、由
`LLMConfigResolver` 解析进 `LLMModelConfig`、LLM 层消费。

防腐条款：

- 存**字符串**（协议名），解析不认识 → 回退 auto + WARN（`reasoningEffort`
  先例：未知值存活往返、不静默丢弃、不炸）。
- 解析时校验「是否在当前 vendor 的菜单里」：通道改了类型之后，残留的点单
  自动失效回 auto —— 这正是 v32 那类「副本不跟随」bug 的反面：点单是**偏好**
  不是路由事实，失效的偏好可以安全忽略。
- 消费点唯一：`LLMConfigResolver` 读列，dispatcher 的 resolver 用值。
  任何协议 / UI 不得直接读列（红线，见 §7）。

### 2.3 解析顺序（dispatcher 内新增一个函数，routing 单点不变）

```dart
WireProtocol resolveProtocol(LLMTarget target, Surface surface) {
  // 1. 模型点单，且在 vendor 菜单内 → 用它
  // 2. vendor 对该 surface 声明的默认（含"按 model.family 细分"的既有 auto 规则，
  //    逐条从现在的 switch 翻译过来，注释保留)
  // 3. family 缺省（openaiChat / openaiImages / …）
}
```

五个既有 switch（generate / generateStream / startLongRunning /
checkOperation / discoverModels）改为 `switch (resolveProtocol(...))` ——
所有路由 `if` 仍然只住在 `llm_dispatcher.dart`，红线不动。

### 2.4 `ProtocolFamily` 的消费点怎么迁

盘点现有 `vendor.family` / `ProtocolFamily` 的 dispatcher 之外消费点，
逐处改为读解析结果或新的 dispatcher 查询：

| 消费点 | 现状 | 目标 |
| --- | --- | --- |
| `generateTimeout` | family==midjourney 豁免 | 读 resolved protocol（midjourney）+ 既有 `capabilities.longRunning`，语义不变 |
| `streamSupportsTools` | family switch | `resolveProtocol(chat)` 后按协议问 |
| `app_state._supportsVideoForType` | family switch + openaiVideo 家族 | 新 dispatcher 查询 `supportsVideoGeneration(channel, model)` —— UI 不再自己 switch（顺手消灭 dispatcher 外唯一的穷尽 switch） |
| ④ thinking 开关的 UI 显隐 | vendor.family == anthropic | 「vendor 的 chat 菜单里含 anthropicChat」或该模型解析结果为 anthropicChat |
| `discoveryUsesNetwork` | family != midjourney | resolved discovery protocol != midjourney |

`ThinkingDialect` 仍留在 VendorProfile（Layer 2 说方言，Layer 1 说 JSON，
不变）。`dashscopeChat` 的 family 归入 ①（openai）：它的 usage / 错误信封
虽是私有形状，但对上层可见的能力面（工具、流式语义）与 ① 同构，单独立
family 要为它穷举四套 switch 分支 —— 这正是
`2026-08-dashscope-native-image.md` §0 拒绝过的开销，理由依旧成立。

---

## 3. 千问 / 百炼落地（本次重构的第一个受益者）

> 端点细节、字段与模型对应关系见 `docs/api/qianwen-bailian.md`；此处只写路由。

### 3.1 一个通道，一把 key，全部 surface

保持 `Vendors.dashscope` **一个 vendor id、一个通道**（不学 MiniMax 拆面）。
成立条件：百炼所有面同 host、路径可从通道 endpoint 推导
（`dashscopeNativeBase()` 已是先例），auth 全部 bearer。

```dart
VendorProfile(
  id: dashscope,
  surfaces: VendorSurfaces(
    chat: WireProtocol.openaiChat,
    chatAlternates: [WireProtocol.dashscopeChat, WireProtocol.anthropicChat],
    image: WireProtocol.dashscopeImagesSync,
    imageAlternates: [WireProtocol.dashscopeImagesAsync],
    video: WireProtocol.dashscopeVideo,
  ),
  auth: AuthScheme.bearer,
)
```

### 3.2 auto 规则（用户什么都不点时的默认路由）

| 模型 | surface | auto 协议 | 依据 |
| --- | --- | --- | --- |
| qwen 系 chat（qwen-max / qwen3.x / …） | chat | `openaiChat` | 兼容面覆盖模型最全（协议文档 §7 矩阵）、与现状一致 |
| `qwen-image*` | imageGen | `dashscopeImagesSync` | 官方仅同步（无异步文档） |
| `wan2.7-image(-pro)` | imageGen | `dashscopeImagesSync`，菜单含 async | 同步先行（期一实测决策沿用）；跑不进超时的场景用户可点单 async。异步提交路径与同步**不同**（协议文档 §5） |
| `wan3.0-video(-prime)` | videoJob | `dashscopeVideo` | 官方仅异步任务 |

（wan2.6 图片模型未出现在抓取到的任何 model 枚举里 —— 见协议文档 §7 的
缺席说明；分类规则按 `-image` 前缀写好即可，模型真到了不需要再改路由。）

### 3.3 新协议实现（Layer 1）

- **`dashscope_images_async`**：**POST
  `/api/v1/services/aigc/image-generation/generation`**（注意与同步的
  `multimodal-generation` **不是同一路径**）+ `X-DashScope-Async: enable`
  提交 → `GET /api/v1/tasks/{task_id}` 轮询（建议 5–10s）。body 与同步的
  wan 形状完全一致，payload 构造直接复用 `dashscope_payload.dart` 的 B 形状。
  轮询循环**藏在 `generateImage()` 内部**（midjourney 先例；`imageProcess`
  执行器不消费 LRO 信封），设计点照抄 `2026-08-dashscope-native-image.md`
  §2.3（总 deadline、节奏、瞬时失败限次、task_id 先行落日志、取消检查点）。
- **`dashscope_video`**：实现 `VideoJobProtocol`。submit =
  **POST `/api/v1/services/aigc/video-generation/video-synthesis`** +
  async header，input 是 `prompt` + `media[]{type, url}`（**非 chat 形状**）；
  poll 共用 `GET /tasks/{task_id}`，把 `task_status` / 顶层
  `output.video_url` 翻译成 **Veo 形状信封** —— 与 ①/③/MJ 一致，
  `videoGenerate` 执行器零改动（xai_videos 是最近的模板）：

  ```
  SUCCEEDED        → { name: task_id, done: true, response: {
                        generateVideoResponse: { generatedSamples: [
                          { video: { uri: output.video_url } } ] } } }
  PENDING/RUNNING  → { name: task_id, done: false, status: task_status }
  FAILED/CANCELED/UNKNOWN → 抛 LLMApiException（带 output.code/message/request_id）
  ```

  失败任务装在 HTTP 200 里（协议文档 §6），所以 poll 面
  `decodeJsonBody(..., checkEnvelope: false)`，状态机自己报错 ——
  llm-three-layer.md「共享机制」节的既有规则。
- **`dashscope_chat`**（私有 chat，`input.messages` + `parameters` 三段式，
  纯文本与多模态**两条路径**）：实现 `ChatProtocol`。要点：
  `result_format: "message"` 必发、流式加 `X-DashScope-SSE: enable` 且按
  `incremental_output` 解析、usage 的 `input_tokens/output_tokens` 译成
  ① 命名再发布。**默认不占 auto 位** —— 兼容面已覆盖日常（唯一例外
  Qwen-Audio，本应用暂无音频输入场景）；有点单机制在，晚交付不阻塞任何人。
  可以放末期甚至砍掉。
- **`anthropic_chat` 复用**：百炼的 Anthropic 兼容面
  （`/apps/anthropic/v1/messages`）复用既有 `AnthropicChatProtocol`，差异
  只有 base path 推导（剥 `/compatible-mode/v1` → 拼 `/apps/anthropic/v1`）。
  auth 已确认 `x-api-key` 与 bearer 二选一皆可 —— 既有
  `anthropicApiKeyWithBearerFallback` 双发直接成立。thinking 方言为官方拼写
  `{type, budget_tokens}` → `ThinkingDialect.anthropicBudget`。

### 3.4 Layer 3 改动

- 分类规则：`wan2.6-image*` 与 `wan2.7-image*` 一样并入 `dashscopeImage`
  （精确到 `-image`，不吞未来的 `-t2v`；wan2.6 未现身文档，规则先备着，
  见协议文档 §7）；`wan3.0-video(-prime)` 进视频家族 —— 现有规则
  `startsWith('wan2.5')` / `startsWith('wan-')` / `-t2v`/`-i2v` 都接不住它，
  需要新规则，且注意排序陷阱（旧方案 §3.2）。
- capabilities：`asyncTask` 能力位改为**三态**语义 —— 仅同步（qwen-image 系）/
  仅异步（wan3.0 视频）/ 皆可（wan2.7 图片，皆可才在 UI 出菜单）；参考图
  上限（qwen 3 / wan2.7 **9**）、`n`（`qwen-image-edit` 基础版仅 1、wan2.7
  默认 4 须显式发 1）、尺寸方言按协议文档 §4.1 逐模型建档。

### 3.5 UI

- **模型编辑器**加「接口协议」下拉：仅当该模型所属 surface 的菜单 > 1 项时
  显示；默认「自动」。选项文案带协议说明（l10n 四语言，走 `joycai-l10n`）。
- **通道向导**：百炼预设不加 variants（一个通道全包），预设描述提及
  「对话 / 生图 / 视频同通道」。
- `app_state` 视频兼容判定改问 dispatcher（§2.4）。

---

## 4. MiniMax 落地（第二个样本）

> 协议事实见 `docs/api/minimax.md`。百炼验证的是「chat 面也要按模型选」，
> MiniMax 验证的是另一半：「chat 面维持通道级、但 surface 槽位属于 vendor」。

### 4.1 chat 双面：variants 保留，不迁点单

两面模型 id **完全一致**（矩阵见协议文档 §4）—— 不存在「某模型仅某面」的
耦合，选面改变的只是路径、thinking 默认值、错误信封。这正是通道级选择的
适用条件，与百炼形成对照：**有模型耦合才点单，没有就维持 variants**。

### 4.2 视频是 vendor 的 surface，不是某张 chat 面的附属

`minimax` 与 `minimaxAnthropic` 两个 vendor id **声明同一个视频槽位**
`surfaces(video: minimaxVideo)` —— 用户无论建的是 ① 面还是 ④ 面通道，
`MiniMax-H3` 都能跑。base 推导：剥 `/v1` 或 `/anthropic/v1` → 拼 `/v2/…`
（`dashscopeNativeBase` 同款只认路径的幂等推导，两个 chat base 都要测）。

### 4.3 `minimax_video` 协议（Layer 1，实现 `VideoJobProtocol`）

- **submit**：`POST /v2/video_generation`。`content[]` 携带 text +
  role 标注的媒体项（`first_frame` / `last_frame` / `reference_*`）；
  **`resolution` 与 `duration` 必填、无服务端默认** —— 客户端缺省值是
  Layer 3 参数表的责任（协议只读 caps，不自己编数）。
- **poll**：`GET /v2/query/video_generation/{task_id}` → Veo 信封翻译：

  ```
  succeeded         → { name, done: true, response: { generateVideoResponse: {
                         generatedSamples: [ { video: { uri: task.content.url } } ] } } }
  queued/running    → { name, done: false, status }
  failed/cancelled  → 抛 LLMApiException（task.error.code/message）
  ```

  失败装在 200 里 → poll 面 `decodeJsonBody(..., checkEnvelope: false)`，
  与 dashscope_video 同款状态机。结果是**直链**（v1 的 file_id →
  files/retrieve 二段式已废除），下载即存。
- **7 天保留期**：过期 task_id 查到的不是 FAILED 而是「查无此任务」——
  必须报成明确错误（「任务已过期」），不能落进重试循环。
- 错误对象是 Anthropic 风格但 type 词表自成一派（`authorized_error` 等），
  协议内自行解析，不进共享信封检查。

### 4.4 可选扩展：`VideoJobProtocol.cancel`

v2 有取消端点（`DELETE /v2/video_generation/{task_id}`），但**仅 `queued`
状态可取消**（免扣费），`running` 停不下来。今天 `videoGenerate` 执行器的
「取消」只是本地放弃轮询 —— 接上这个端点，排队中的任务才能真正免费停掉。
设计为 `VideoJobProtocol` 的**可选方法**（默认 no-op），执行器取消时调用、
失败静默降级为本地放弃。放 D 期，不阻塞主线。

### 4.5 Layer 3

- `MiniMax-H3` 进视频家族。分类规则**精确到 `minimax-h` 前缀** ——
  `MiniMax-M3` 是 chat 模型，一字之差（协议文档 §5-7）。沿 xAI 前例：
  family 归 `openaiVideo`（表达「这是个视频任务模型」），协议选择由
  vendor surface 决定；中转上同 id 照旧走 ① `/v1/videos`，行为不变。
- caps 参数表：`resolution`（`768P`/`2K`，客户端缺省 `768P`）、`duration`
  （4–15s，缺省跟随全局视频参数）、`ratio` 枚举、参考素材 role 支持。

## 5. 对既有 vendor 的收敛与不动

- **xAI**：`usesXaiNativeSurfaces` → `surfaces(image: xaiImages, video:
  xaiVideos)`，行为不变，两个 bool 字段删除。
- **MiniMax / Google / NewAPI 的 chat variants 保留不动。** 通道级选面与
  模型级点单的裁决标准（§4.1 由 MiniMax 实证）：**协议与模型有耦合才点单，
  没有就维持 variants**。variants 承载「你指向哪个 URL / 哪家供应商的拼写」
  （host、path、auth 差异，模型集合不变），点单承载「同一通道下这个模型
  走哪条 wire」。百炼两个条件都满足所以点单；MiniMax 双面模型集合完全一致，
  通道级仍是正确粒度 —— 但它的**视频槽位声明在两个 vendor id 上**（§4.2），
  variants 与 surface 槽位并用，互不排斥。
- **三家官方的头寸**（§1.4 表）：Anthropic 官方是单项菜单的退化情形，零改动；
  OpenAI 官方接 Responses、Google 官方接 Interactions 的那天，就是各自
  chat 菜单加一项 + 新协议类，机制零改动 —— Responses-only 模型（o1-pro /
  codex 系）正是「官方 vendor 也需要按模型点单」的存在证明。Google 双面
  今天靠 variants（两个通道），将来若收敛成一个通道 + 点单，机制已就位，
  不在本次范围。
- **中转上的 qwen/wan/hailuo 模型行为不变**（旧方案 §4 的显式决策继续成立）：
  auto 规则里「原生协议」只在 vendor 菜单声明了它时才可达，中转 vendor
  的菜单里没有，照旧走 chat / ① `/v1/videos`。

---

## 6. 分期

| 期 | 内容 | 行为变化 | 退出标准 |
| --- | --- | --- | --- |
| **A · 绑定关系重构**（纯机械） | `WireProtocol` + `VendorSurfaces` + `resolveProtocol()`；五个 switch 改写；删两个 bool；§2.4 消费点迁移 | **零**（现有路由逐条翻译，注释保留） | `flutter analyze` 零问题；现有全部测试绿；新增 resolver 纯函数测试钉住「每个 (vendor, family) 组合解析到与今天相同的协议」 |
| **B · 百炼强化** | v34 迁移 + `dashscope_video` + `dashscope_images_async` + Anthropic 面接入 + Layer 3 家族/能力 + 模型编辑器点单 UI + l10n | 百炼通道新增视频、异步图、④ 面能力 | 真机各跑通一次：wan 视频任务全程、异步图任务全程（含中途取消 ≤5s 生效）、④ 面一轮工具调用 |
| **C · MiniMax 视频**（§4） | `minimax_video` 协议 + 两个 MiniMax vendor 的 video 槽位 + `MiniMax-H3` 分类/caps + base 推导测试 | MiniMax 通道新增视频能力 | 真机跑通一次 H3 任务全程（①、④ 面通道各一次）；7 天过期 id 报「任务已过期」而非重试 |
| **D · 可选打磨** | `dashscope_chat`、`VideoJobProtocol.cancel`（§4.4）、点单机制推广到其它 vendor、discovery 增强 | 增量 | — |

A 期独立合并、可独立回滚；B / C 互相独立、可并行，各自内部还可再拆。

---

## 7. 红线更新（合入 A 期时同步改 `llm-three-layer.md`）

- 新增：**协议解析只经 `resolveProtocol()`**；`wire_protocol` 列的读取只在
  `LLMConfigResolver`，其值只在 dispatcher 消费。UI 展示菜单读
  `vendor.surfaces`，不得自拼协议名字符串。
- 修订：「`if (family == ...)` 只住 dispatcher」条目改为
  「`if (family == ...)` **与 `if (protocol == ...)`** 只住 dispatcher」。
- 废止：`usesXaiNativeSurfaces` / `usesDashScopeNativeImages`
  （grep 确认无残留）。

---

## 8. 风险与开放问题

1. **A 期是纯重构但面积大**（dispatcher 全部 switch + 5 个消费点）。
   缓解：resolver 纯函数测试先行，「翻译前后同构」逐条钉住。
2. **异步图片的取消**：同步路径没有检查点，异步循环必须自查
   `TaskStatus.cancelled`（旧方案 §2.3-6 未解决项，B 期必须解决）。
3. **`platform.qianwenai.com` 文档是二手镜像**（旧方案 §2.2 已有前科）：
   B 期实现前按 help.aliyun.com 官方文档复核带 ⚠ 的条目（协议文档内已
   逐条标记）；猜错会响（400 / 404），不会静默。
4. **wan2.6 图片模型未在文档现身**（协议文档 §7）：分类规则先备着，
   模型枚举里没有就不进预设目录；用户点名过它，落地前问一次官方文档。
5. **`wire_protocol` 的迁移面**：备份导入（`_importModels`）要原样保留该列；
   老备份没有该列 → null → auto，天然兼容。
6. **MiniMax ① 面的 thinking 默认开**（协议文档 §5-2：两面默认值相反，
   ① 不发 `thinking` 字段 = adaptive 开启）：本仓 ① 协议从不发该字段，
   意味着 MiniMax ① 通道的 M 系模型默认在思考、按思考计费。是否在
   `enableThinking == false` 时显式发 `{type: "disabled"}`（经 profile
   声明式字段，不是协议里的 vendor 分支）—— C 期实测后拍板。
7. **H3 的结果 URL 有效期与建议轮询间隔文档均未给**：实现按 dashscope
   同款保守处理（当场下载、5–10s 轮询），实测校准。
