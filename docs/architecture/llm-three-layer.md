# LLM API 层：三层架构

> 2026-08 重构（`refactor/llm-three-layer`）确立。改动任何 `lib/services/llm/`
> 下的文件之前先读这份文档 —— 分层规则一旦被绕过，就会回到重构前
> "路由靠字符串嗅探、厂商差异散落各处" 的状态。

## 三层是什么

```
┌──────────────────────────────────────────────────────────────┐
│ 调用方: task_executors / prompt_optimizer_agent / UI          │
└──────────────────────────┬───────────────────────────────────┘
                           │  LLMService (门面: 重试/会话/计费记录)
                           ▼
                    LLMDispatcher  ← 所有路由规则唯一所在地
              ┌────────────┼────────────┐
              ▼            ▼            ▼
   Layer 2  vendor    Layer 3  model   Layer 1  protocol
   vendors/vendors.dart  model_descriptor.dart  protocols/*.dart
```

| 层 | 回答的问题 | 代码 |
|----|-----------|------|
| **1 Protocol** | 线上格式长什么样：endpoint 形状、请求体、响应/流解析 | `protocols/` — openai_chat · openai_responses · openai_images · openai_videos · ark_images · xai_images · xai_videos · gemini_chat · gemini_imagen · gemini_veo · anthropic_chat · midjourney · dashscope_chat · dashscope_images · dashscope_images_async · dashscope_video |
| **2 Vendor** | 谁在提供这个格式：认证方式、每个 surface 的协议菜单 | `vendors/vendor_profile.dart` + `vendors/vendors.dart`（id 即 `llm_channels.type`） |
| **3 Model** | 这个模型是什么：family 分类、能力、参数表 | `model_descriptor.dart`（包装 `model_family.dart` + `model_capabilities.dart`） |

协议家族（`ProtocolFamily`）有五个：`openai`（chat/completions 及其姊妹
images/videos surface）、`gemini`（`:generateContent` 及 `:predict` /
`:predictLongRunning`）、`anthropic`（`/messages`，2026-08 加入）、
`midjourney`（midjourney-proxy 的 `/mj/*`）、`dashscope`（阿里云百炼私有
REST：`/api/v1/services/aigc/*` 下的三段式 `{model, input, parameters}`，
回包套在 `output` 里，2026-08 加入）。
xAI 的 JSON images/videos surface 是 openai 家族下由 vendor 选择的替代协议。

**`dashscope` 家族 ≠ 「百炼」这家供应商**：`Vendors.dashscope`（兼容面通道）
family 仍是 `openai` —— 它线上说的就是 OpenAI，只是借用了原生的图片/视频
surface；`Vendors.dashscopeNative` 才是 family `dashscope`。同一家公司、同一
把 key、同一个 host，两个 vendor id 的区别只有**通道以哪条 chat wire 打头**，
因为两条面是两个 base URL，属于通道而非模型。两个 vendor 的 `chatMenu` 都是
同样三项（原生 / ① / ④），顺序不同而已。

`anthropic` 是唯一一个只有单一 surface 的家族 —— 没有生图/视频姊妹端点，
所以 dispatcher 的六个 switch 里它都只有一条分支（两条是
`UnsupportedError`）。接入它时**没有**动 Layer 3：Claude 的 modelId 落在
`ModelFamily.other`，而 family 在这条路径上只用来在 ①/③ 内部选姊妹 surface，
④ 没有可选的。**"新增协议家族要不要动 Layer 3"的判断标准是"这个家族内部要不要
按模型分流"，不是"这个家族新不新"。**

`dashscope` 是这条判断标准的反例：它三个 surface 全有，而且 chat 面内部还要
按模型分流（纯文本走 `text-generation/generation`、VL/omni/audio 走
`multimodal-generation/generation`），所以接它时动了 Layer 3 ——
`ModelDescriptor.needsMultimodalChatSurface`（规则在
`ModelFamilyClassifier.isDashScopeMultimodalChat`）。协议自己**不许**认模型
id：走错端点不报错，图片被静默丢弃、模型当作没看见图来回答。

## Surface × 协议菜单与模型级点单（2026-08 多面供应商重构）

> 协议事实见 [`docs/api/qianwen-bailian.md`](../api/qianwen-bailian.md)
> 与 [`docs/api/minimax.md`](../api/minimax.md)。当轮的完整设计与取舍已随执行
> 完毕的方案退役（[台账](../plans/README.md)），正文在
> `git show f709059:docs/plans/2026-08-vendor-protocol-model-refactor.md`。

百炼一家在同一 surface 上有多条 wire 且**与模型耦合**（qwen-image 仅同步、
wan2.7 同步异步皆可、④ 兼容面只服务子集），"vendor 固定一个 family + 布尔
surface 开关"表达不了它。绑定关系升级为：

- **`WireProtocol`**（`vendor_profile.dart`）：每个值 = 一个已实现的协议 +
  它的 `Surface`（chat / imageGen / videoJob）+ 稳定 `id` 字符串（存库）。
  **枚举值稀缺**：只有已实现的协议配拥有一个，存了的 id 永远解析得到代码。
- **`VendorProfile` 的菜单字段**：`chatMenu`（首项为默认，>1 项才出 UI）、
  `imageMenu`（同前）、`videoProtocol`（原生视频面，替代家族默认）、
  `protocolBases`（**通用**协议在替代面上的 base 推导 —— dashscope 的 ④ 面
  复用 `AnthropicChatProtocol`，路径由 vendor 声明推导，协议保持 vendor-blind；
  **vendor 专属**协议自己推导 base，不进这张表）。原来的
  `usesXaiNativeSurfaces` / `usesDashScopeNativeImages` 两个布尔已删除。
- **`unlistedModels`**：这家在**原生面**上服务、而它的 `/models` 结构上
  返回不了的模型。兼容层的列表端点枚举的是兼容层——MiniMax 的
  `GET /v1/models` 只给 M 系 chat，`image-01` 与 `MiniMax-H3` 住在
  `/v1/image_generation` 和 `/v2/video_generation` 上，那张表里没有它们的
  词汇（`docs/api/minimax.md` §5.1）。不声明的话，"拉取模型"这个按钮会
  成功、会返回、就是永远列不出这家被接进来的那两条 wire，且不报错。
  `LLMDispatcher.mergeUnlistedModels` 把它追加在实测列表之后并去重，
  **对每个 family 都跑**——"这个声明在这条家族分支上生效吗"不该是个问题。
  与 Midjourney 的内置目录区别在于加法还是替换：MJ 没有列表端点，目录就是
  全部答案。
- **`llm_models.wire_protocol`**（v36，可空 = auto）：模型级点单。不是可推导
  副本（v32 教训不适用）——与 `enable_thinking` 同性质的用户配置。
- **解析顺序**（全部在 dispatcher）：模型点单（合法时）→ vendor 该 surface
  默认 → 家族推断。点单失效（通道换供应商、未知 id、模型不支持）**静默回退
  auto**，由 UI 展示而非路由报错；用户下次保存时清空。
- **单点查询**：菜单/失效判定只经 `LLMDispatcher.protocolMenu` /
  `isStaleProtocolSelection` / `surfaceForModel`（UI 与路由共用，static，
  2026-09 起都接 `tag:`，见下一节）。`wire_protocol` 与 `tag` 两列只由
  `LLMConfigResolver` 读进路由。
- **`protocolBases` 是双向的**：百炼原生通道存 `…/api/v1`，兼容面
  （① chat 与**唯一那个 `GET /models`**）由 `dashscopeCompatibleBase` 反推；
  兼容面通道存 `…/compatible-mode/v1`，原生的图片/视频/chat 由
  `dashscopeNativeBase` 正推。两个推导都只看 path，所以国际站 host
  原样可用。少了反推那一半，原生通道的"拉取模型列表"只会失败。
- **菜单要与模型 family 求交，不能只判 `imageMenu.isNotEmpty`。**
  两家原生图像面并存后（百炼 + MiniMax），"这个 vendor 声明了图像菜单"不再
  等于"它服务这个模型"：往 MiniMax 通道里敲一个 `qwen-image`，旧写法会把它
  路由到 MiniMax 的端点。交集项是
  `LLMDispatcher._imageProtocolsFor(family)`，`_hasNativeImageRoute` 是所有
  图像分支共用的那个判据。
- **"这条渠道能不能跑视频任务"只有一个答案，住在 dispatcher。**
  `LLMDispatcher.canRunVideoJob` 与 `startLongRunning` 的分支一一对应，
  `AppState._supportsVideoForType`（工作台模型选择器的过滤条件）调它而不是
  自己再推一遍。这条是踩出来的：选择器那份副本写着"④ 族没有视频面"，等到
  一个 ④ vendor 声明了原生视频面，模型就从选择器里消失了 —— 而它背后的路由
  是通的，界面上没有任何解释。**UI 侧的能力判断复制路由规则 = 一个不会报错
  的静默失效**，同类判断（`streamSupportsTools` / `streamIsSingleShot` /
  `protocolMenuFor`）都是 dispatcher 的 public 方法，原因相同。
- **`videoProtocol` 声明 → 协议实现的映射只写一次**
  （`_nativeVideoProtocol`）。① 族在它返回 null 时回落到家族默认
  `/v1/videos`，④ 族没有默认，null 就是最终答案。`startLongRunning`、
  `checkOperation`、`canRunVideoJob` 三处共用，避免"提交能跑、轮询不认"这类
  半边路由。
- **视频任务的轮询按持久化的提交佐证路由，不按渠道现状。**
  `startLongRunning` 返回 `LLMOperationTicket`（operation id + 发出它的
  `WireProtocol`），executor 把两者一起写进 `tasks` 表
  （v38 的 `operation_name` / `operation_surface` 列；2026-09 起两列都在提交
  被受理的当下写入——此前 `operation_name` 实际没写。启动时仍处于
  processing 且带 operation id 的视频任务回到 pending，executor 见到持久化的
  id 就跳过提交、直接续轮询，而不是被标成 failed 后让用户再付一次钱；用户
  手动 retry 则清空 id、重新提交）；此后每一轮
  `checkOperation` / `cancelOperation` 带回 `surfaceId`，dispatcher 经
  `_videoJobProtocolFor`（`_nativeVideoProtocol` 的超集，补上两个从不被声明
  的家族默认面 ①/`veo`）直达当初的面。任务比启动它的配置活得久：渠道中途
  被改指到别家 vendor，轮询也不会再送进陌生的状态词表。`video_` 前缀守卫
  仍在家族分支里，作为 v38 之前旧行与无佐证调用方的兜底；cancel 在佐证面
  没有取消能力时回答 null，**绝不**回落到渠道当前声明的面。
- **`test/services/llm/wire_protocol_routing_test.dart`** 钉住"重构前存在的每个
  (vendor, model) 组合仍解析到同一条路"；
  `test/services/llm/dashscope_chat_payload_test.dart` 钉住私有 chat 面的线上规则
  （三段式分区、`result_format`、增量、多模态 content 形状）；
  `test/services/llm/minimax_payload_test.dart` 钉住 MiniMax 两条私有面的 body 规则与
  base 推导 —— 其中媒体项的嵌套形状、`metadata` 计数的字符串类型两条，都是
  "写错了上游不报错、照常出片并计费"的那种，所以按上游样例逐字断言。

## 模型类型声明与多媒体协议点单（2026-09）

> 当轮的完整设计、取舍与测试清单已随执行完毕的方案退役（[台账](../plans/README.md)，
> 三条没做的界面细节记在那里），正文在
> `git show f709059:docs/plans/2026-09-model-kind-protocol-pin.md`。

中转站的模型名是自由文本，`nano-banana-pro` 按 id 分类是 chat、`my-sora` 什么都
不是 —— 生图模型被当对话发、视频模型在工作台里根本不出现，而上一节的点单下拉在
中转上永远不渲染（中转 vendor 没有声明菜单，交集为空）。改成两个**已有的用户
字段**各升一级职责，不加列、不加协议族：

- **`llm_models.tag` 声明 surface。** image → imageGen、video → videoJob、
  chat / multimodal / refiner → chat。经 `LLMConfigResolver` →
  `LLMModelConfig.tag` → dispatcher 一条线；为 null（没有模型行的调用方、测试
  夹具）时退回按 id 分类，行为与改动前完全相同。
- **菜单：`LLMDispatcher.protocolMenu(channelType, modelId, tag:)` 返回
  `ProtocolMenu { surface, options, auto, fixed }`**，取代旧的
  `protocolMenuFor` 列表。`auto` 单独成字段、且恒在 `options` 里 —— 菜单列的是
  "允许点的"，比 auto 实际走的多（MiniMax 渠道上的 `qwen-image` 可以点 MiniMax
  出图，但自动仍走 chat）。`fixed` 专给 Midjourney：一条路没得选，和"这个渠道
  没有该 surface"（`auto == null`）不是一个答案。
- **options 的构成**：厂商声明的原生面（图像菜单**不再**与 id family 求交 ——
  交集只用于算 auto）＋ `VendorProfile.offersFamilyMediaSurfaces` 为真时的家族
  通用面（① `openaiImages` / `openaiVideos`，③ `geminiImagen` / `geminiVeo`，
  外加 `chatImage`）＋ auto 补位。该开关只在 openAIRest、newApiOpenAI、
  googleRest、officialGoogle、newApiGemini 上为真；一方厂商（百炼 compatible 面
  没有 `/images`、xAI 没有 Sora 形态 `/videos`、DeepSeek 都没有）与本地运行时
  （Ollama / LM Studio，未核实上游文档）一律为假。**中转站不提供任何厂商原生
  协议**：原生协议从 endpoint 推导路径，在中转 host 上推出来的路径没有意义。
- **`WireProtocol.chatImage`（`chat-image`）**：图像 surface 上"走渠道的 chat 面、
  图片随回复返回"。不是新协议类，是给 dispatcher 一直存在的 `_chatGenerate` 兜底
  路由起个名字 —— 没有它，中转上的 `gpt-image-1` 无法强制走 chat。解析得到已有
  代码，不违反"枚举值稀缺"。
- **auto ＝ 今天的路由，按构造成立。** `_familyRoute` 是 generate /
  startLongRunning 家族分支的镜像（不是从分支推导，由测试钉住）。唯一有意的变化：
  video surface 上家族规则拒绝的模型（非 ③ 渠道上的 Veo id、未识别的视频别名）
  不再抛错，auto 取菜单首项；菜单为空才是"该渠道没有视频面"。
- **`servedBy`：路由不同于 id 自身路由时才重新描述模型。**
  `ModelDescriptor.of(id, servedBy:)` —— 有独立面的协议（Images API、视频任务…）
  服务得了该 id 的 family 时保留 id 的精细表，否则按协议给 family 与
  `ModelCapabilities.forProtocol` 的保底表；chat 面与 `chatImage` 把"有专属路由"
  的 family 降为同源 chat family（`gemini*` → `geminiChat`，其余 → `other`）。
  dispatcher 只在 effective ≠ id 自身路由时才传 `servedBy`，所以**点单点到
  auto 本来就走的那条路，descriptor 不变** —— 中转上的 `qwen-image` 点
  "对话出图"不会丢掉 DashScope 参数表和生成级超时。
- **三个静默坑，写在这里是因为它们都不报错：**
  1. `chatImage` 的保底表必须 `isImageGenerator: true`。两条 chat wire 都按这个
     flag 决定"要不要出图"：③ 据此发 `responseModalities: IMAGE`，① 只在它为真时
     把"整条回复就是一个链接"当成图片下载。假的后果是请求成功、回复里的图被丢。
  2. `gemini*` 降级不能降成 `other`：OpenAI 兼容 chat wire 按 family
     （`isGeminiFamily`）加 Gemini 扩展字段，降错就静默丢扩展。
  3. descriptor 缓存按 `(modelId, servedBy)` 记录键，不是按 id。同一个 id 在两个
     渠道点了不同协议，按 id 缓存时后解析的会读到前一个的 family 与参数表。
- **UI / state 只走 `LLMDispatcher.descriptorFor(...)` /
  `AppState.descriptorForModel(model)`**。工作台的参数面板、参考图上限、参数记忆
  命名空间都从这里读；`ModelCapabilities.forModel(model.modelId)` 在
  `services/llm/` 之外出现，就是把点单绕过去了。
- **推理强度的挡位只问 `LLMDispatcher.reasoningLadder(channelType:, modelId:, tag:, wireProtocol:)`**
  （2026-09，模型编辑器的推理滑块）。**按解析出的 chat 面分派，不按 vendor 的
  family**（2026-09-14）：面 = 合法点单，否则 auto，与路由的 `_chatFace` 同一套
  解析。按 family 分派时，兼容面渠道点单到 ④ 的百炼模型会被给出 ① 的六档（而 ④
  budget 拼法只分得开两档），原生渠道点单到 ① 的模型会被给出原生开关。
  每条 wire 只给它分得开的档，发出去一样的
  两档就是一个没有效果的旋钮：① 六档全有（DeepSeek 的关闭走 `thinking` 对象，
  仍是另一种请求）；④ adaptive 没有「关闭」——它和「默认」一样不发 `thinking`；
  ④ budget（Claude 4.5 及更早、百炼 ④ 面）与 MiniMax 的裸 adaptive 没有强度，
  只有「默认 / 开启」（开启存为 medium）；百炼原生是「默认 / 关闭 / 开启」；
  百炼两个 vendor 的 **① 面**同样是「默认 / 关闭 / 开启」：它声明了
  `enable_thinking` 开关方言（`ThinkingDialect.openaiEnableThinking`，reasoning
  03 §3 switch 方言的 ① 拼法），发顶层 `enable_thinking: bool` 并**停发**
  `reasoning_effort`——商业款 Qwen3-Max/Plus 默认不思考，而 `reasoning_effort`
  叫不醒它（pitfalls 11 §A9）。方言按面声明：`VendorProfile.thinkingByProtocol`
  覆盖 `thinking` 默认值，读取一律经 `thinkingFor(face)`，协议与挡位读的是同一处；
  没有声明的 vendor 请求逐字节不变。该面的 `tool_choice` 恒为 `auto`，恰好满足
  「思考开启时只接受 auto|none」（pitfalls 11 §A13）。代价：3.7+ 的新款 Qwen 本
  可接受 `reasoning_effort` 的深度档，在 ① 面上只剩开关；本仓没有模型级方言列，
  未加。MJ 与非 chat surface 返回空。③ Gemini（2026-09-14）发
  `generationConfig.thinkingConfig`，**只发一代字段**、恒带
  `includeThoughts: true`：代次由 Layer 3 声明
  （`ModelDescriptor.geminiThinking` → `ModelFamilyClassifier.geminiThinkingGeneration`）
  —— 3+ 走 `thinkingLevel`（全大写，off → `MINIMAL`，max → `HIGH`），2.5 走
  `thinkingBudget`（0 / 1024 / 8192 / 24576，max 同 high），2.0 及更早与一切
  图像/视频生成模型不发；读不出版本号的自由文本 id 猜 `thinkingLevel`——错的方式
  都会响（对面报错点名字段），猜「不发」则是旋钮静默无效。Max 与 High 发出同一个
  请求，所以 ③ 的挡位是「默认 / 关闭 / 低 / 中 / 高」。默认档不发字段，与改动前逐字节
  相同。3.1 Pro 没有 `MINIMAL`、2.5 Pro 不接受预算 0：「关闭」在这两款上会 400，
  这是端点自己的声明，不做降级。④ 的 dialect 判定与请求共用
  `declaredAnthropicThinkingDialect`，编辑器看到的就是请求会用的。测试：
  `test/services/llm/reasoning_ladder_test.dart`。
- **测试**：`test/services/llm/model_kind_protocol_pin_test.dart` 钉住中转图像/视频、无通用面的
  渠道、一方厂商未收录的新 id、失效与缓存隔离，以及一条回归门 —— 对所有 vendor ×
  一组代表性 id，`tag = inferTag(id)` 时 descriptor 与 auto 必须和不带 tag 时
  是同一个对象 / 同一个值。

## 渠道 × 线路 × 模型（2026-09）

> 当轮的设计与执行清单已随执行完毕退役（[台账](../plans/README.md)）：
> `git show 9e90547:docs/plans/2026-09-channel-route-model.md`（设计 · 四个决定）与
> `…-execution.md`（十六片 + 三次评审的施工记录，每条偏离的理由都在那里）。标准是
> `channel-route-model` skill；设计稿 Claude Design `D1f 渠道与线路`。

以前「渠道类型」一个字段同时说「哪家平台」和「对话走哪个协议」：一把 New API 密钥
打四个协议就得建四个渠道、同一个模型建四次，点单换协议时推理强度与最大输出原样带过去。
拆成三层：

- **渠道 = 一份密钥。** 下面挂**线路**：每个 `RouteKind`（chat · responses ·
  anthropic · gemini · dashscope · midjourney，各对应一个对话 `WireProtocol`）至多
  一条，各带路径。**平台**（`vendors/platforms.dart` 的 `PlatformProfile` 表）不存，
  由（主线路 vendor, 主机）推断；决定标签、默认路径与能加哪些线路。线路的 vendor 也
  不存：主线路 vendor 的 chat 菜单含该面 → 主线路 vendor，否则平台表（按构造与迁移前
  逐字节一致）。
- **模型选当前线路**（`llm_models.active_route`，空 = 跟随主线路），**每条线路一份
  参数**：`RouteParams` 只有三个——推理强度、思考开关、最大输出（各有「同一模型换线
  路会变」的证据，见 `model_routes.dart` 注释）；其余线路的参数停放在
  `llm_models.route_params`。联网搜索是模型的**授权**，不随线路变，发不发得出按线路
  问 `serverWebSearch`；发得出但没在该平台实机验过的线路由画像声明
  （`PlatformProfile.untestedWebSearch`，New API 与自定义的 Anthropic 面），编辑器标「未实测」，发送不变。图像 / 视频模型不走线路，恒取主线路，媒体点单照旧。

**存储（v45）**：`llm_channels.routes` 内嵌 JSON 文档（主机、线路表、写入标记），
`llm_models.active_route / route_params`。**扁平列永远是主线路**——`type` / `endpoint`
= 主线路的 vendor 与完整地址，读写都过 `ChannelRoutes.resolve` 的幂等规范化
（`ModelRepository.normalizedChannel`）。无文档 → 读时由旧 (type, endpoint) 推出
（每个预设 × 每个面迁移后地址逐字节等于旧推导，`channel_routes_test`）；写入标记与
扁平列不符 → 别的写入方（旧版本、旧备份）只改了扁平列：同平台只重建主线路，换了平台
就整张换掉。

**请求**：`RoutedChannel.forModel(channel, model)` 是「按模型的线路看渠道」——
`LLMConfigResolver`、`AppState.descriptorForModel`、模型编辑器、模型卡都经它；
模型选的线路已不在 → 请求抛 `LLMConfigErrorKind.routeNotFound`，展示侧退回主线路。
`LLMModelConfig.faceBases` 让 `_faceTarget` 先用线路自己的地址，没有线路的面照旧推导。
界面上的「实际请求地址」是 `LLMDispatcher.chatRequestUrl`，与协议共用同一组地址函数。

**切线路**（`services/catalogue/route_switching.dart`）：保存与切换共用一条
`forRoute`——不在该面挡位表上的强度映射到在该面**发出同样请求**的档（不是丢弃，丢弃
会悄悄关掉思考）；切换 = 当前参数停放到来源线路、载入目标线路停放的（**没配过 = 全空**，
不复制）、覆盖全部三字段，模型 id 不变。来源线路已从渠道消失时参数停放在它自己名下
（`recoverMissingRoute`），绝不记到主线路名下。**改主线路前先钉住跟随者**
（`pinFollowers`），否则它们会带着为旧线路设的参数悄悄换协议。

**合并**（`channel_merge.dart` + `channel_merge_executor.dart`）：只检测、用户逐组
确认，永不自动。候选 = 同平台、同主机（忽略大小写）、**逐字节同密钥**、线路不相交、
每渠道至多一组；再加一道**请求不变**闸：合并后每条线路的 vendor 与地址、每个搬过去的
模型的请求都与合并前相同，否则不成对（换了保留方可能换线路 vendor；没有同名对应的
图像 / 视频模型会换地址——这时试反方向）。执行：一个事务（渠道 → 模型只写四列 →
删被并模型 → 删余下 → 删渠道），提交后先改写设置里的模型选择、再改写
`token_usage` / `tasks` 的 `model_pk`、最后改写助手对话 JSON 里的 `modelDbId`
（回复卡「打开该模型」的跳转）。密钥在渠道行里，随事务消失。

**界面**：`widgets/models/app_route_badge.dart`（四态徽标）· `route_labels.dart`
（线路名 / 平台名唯一一张表）· `channel_route_table.dart`（渠道编辑的线路表；路径
null = 平台默认，`''` = 主机本身，绝对 URL = 独立主机；「用主机本身」只在
`PlatformProfile.guessedPaths` 的自定义平台上给，中转与厂商的布局是已知的）；
模型编辑的线路条在 `model_edit/model_edit_routes.dart`（作用域灰字是
`AppSectionLabel.suffix` 的行内 span，手机上线路条横向滚动）；向导每条线路的私有能力一词
读 `ChannelRoutes.featuresOf`（vendor 画像的联网与 ④ 提示缓存，未实测的联网不列）；合并提示与审阅在
`screens/models/widgets/channel_merge_review.dart`。**单线路渠道零负担**：渠道 ≥2 条线路
（或平台提供第二条）才出线路界面，否则与改前一样。

**红线**：渠道的 `type` / `endpoint` 只许线路解析（`model_routes.dart`）、仓库规范化与
渠道编辑表单三处直读（`test/architecture/channel_flat_columns_scan_test.dart`）。其余任何地方读它
们，回答的是主线路——模型换到别的线路后就静默错。

## 分层纪律（违反会静默腐化）

1. **只有 `ModelDescriptor` 允许嗅探 modelId。**
   `ModelFamilyClassifier` / `ModelCapabilities` 是 Layer 3 的实现细节。
   协议和 vendor 拿到的是解析好的 descriptor，绝不自己 `contains('gemini')`。
2. **协议不认识 vendor。** 协议从 `LLMTarget` 拿 `headers()` / `decorateUrl()`
   做认证，此外不得出现任何 `vendor.id == ...` 分支。厂商差异要么是
   `VendorProfile` 上的声明式字段（如 surface 菜单 `imageMenu`），要么是一个
   独立协议实现，由 dispatcher 选择。
3. **所有路由 `if` 只住在 `llm_dispatcher.dart`。** 重构前散在
   provider 里的每一条规则（gpt-image 走 Images API、xAI 渠道换 video
   surface、`video_` 前缀轮询、`openai_lro_sim_` 模拟……）现在都在
   dispatcher 里逐条注释着，改动路由只看这一个文件。
4. **`llm_models.type` 已从数据库删除（v32 迁移）。** 模型的服务方由
   `channel.type → vendor → protocol` 每次请求时解析，不再落库 ——
   落库的副本曾在渠道改类型后不跟随，导致路由错乱。恢复 v32 之前的备份时
   `_importModels` 会剥掉该字段。

## 一次请求的路径

```
LLMService.request(modelIdentifier, messages, ...)
  → LLMConfigResolver: DB 查 model 行 + channel 行 + 计费组
      → RoutedChannel.forModel: 模型的线路 → vendor + 地址 + faceBases → LLMModelConfig
  → LLMDispatcher.generate(config, ...)
      vendor = Vendors.byId(config.channelType)      // Layer 2
      model  = descriptorFor(modelId, tag, wireProtocol)
               // Layer 3：id 自身路由时 == ModelDescriptor.of(modelId)；
               // 点单/类型把路由挪走时按协议重新描述（servedBy）
      switch (vendor.family) { ... }                 // → Layer 1 协议
  → 协议执行 HTTP，产出 LLMResponse / chunk 流
  → LLMService 记录 token 用量、维护会话
```

## 扩展方式

- **新增"兼容 OpenAI 标准的厂商"（DeepSeek / MiniMax …）**：
  `vendors.dart` 加一个 `VendorProfile`（family=openai，bearer），
  UI 渠道向导加预设。厂商特有参数/约定加在 profile 的声明式字段上，
  由对应协议读取 —— 不要在协议里写 `if (vendor.id == ...)`。
- **新增协议标准**：`protocols/` 新建协议类实现 `ChatProtocol` 等接口，
  `ProtocolFamily` 加值，dispatcher 的 switch 补分支，再加 vendor profile。
  ④ Anthropic 就是照这条路加的，可以直接当模板读
  （`anthropic_chat_protocol.dart` + `Vendors.anthropicRest` /
  `newApiAnthropic`）；DashScope 私有面（`dashscope_chat_protocol.dart` +
  `Vendors.dashscopeNative`）是"多 surface + 面内还要按模型分流"的模板。
  加完记得 grep 一遍 `ProtocolFamily` —— `analyze` 会把 dispatcher 的六个
  穷尽 switch 全部报出来，dispatcher 之外还有四处合法消费点：
  `app_state.dart`（"这个渠道能不能出视频"）、`channel_provider_presets.dart`
  的 `genericVendorForFamily` / `protocolFamilyLabel`、以及编辑器与向导的
  endpoint 提示。全是 UI/state 对 Layer 2 的只读消费。
- **新增模型能力**：只动 Layer 3（`model_capability_tables.dart` 的参数表——`model_capabilities.dart`
  的 part，按 id 分流的 `forModel` / `forProtocol` / `forFamily` 仍在主文件——、
  必要时 `model_family.dart` 的分类规则）。
- **新增任务类型**：与本层无关，见 CLAUDE.md 的 task type 扩展流程。

## 硬编码红线（code review 时直接 grep）

重构消灭的正是这些模式。任何一条重新出现，都意味着三层在被绕过 ——
review 时用下面的模式全仓库 grep 一遍即可：

| 红线模式（grep） | 为什么禁止 | 正确位置 |
|----------------|-----------|---------|
| `modelId.contains(` / `modelId.startsWith(` / `id.contains(` 出现在 `model_family.dart`、`model_capabilities.dart`、`model_descriptor.dart` 之外 | 模型分类只能有一个事实来源；散点嗅探曾导致 30+ 条规则互相踩（顺序敏感、改一处漏一处） | 加进 `ModelFamilyClassifier` 的规则表（含 `isNijiVariant` / `isTextOnlyChat` / `isMockModel` 这类具名谓词），消费方读 `ModelDescriptor.of(id)` |
| `vendor.id ==` 任何位置 | 协议一旦认识具体厂商，厂商差异就会重新散落 | `VendorProfile` 加声明式字段（surface 菜单 / `protocolBases` / `thinking`），dispatcher 据此选协议 |
| `if (protocol == ...)` 路由分支出现在 `llm_dispatcher.dart` 之外；UI 自拼协议 id 字符串 | 协议解析必须单点可审计；裸字符串拼错静默失效 | 菜单与失效判定读 `LLMDispatcher.protocolMenuFor` 等 static 查询；显示名走 `wire_protocol_labels.dart` 的唯一映射表 |
| `llm_models.wire_protocol` 在 `LLMConfigResolver` 之外被读取 | 点单是偏好不是路由事实，多个读取点会各自发明失效语义 | 列 → resolver → `LLMModelConfig.wireProtocol` → dispatcher 消费，一条线 |
| `llm_models.tag` 在 `LLMConfigResolver` 之外被当成路由事实读（按它选协议、判 surface） | 类型已参与路由；第二个读取点会和 dispatcher 的 surface 判定分叉 | 列 → resolver → `LLMModelConfig.tag` → dispatcher；UI 只把它原样传给 `LLMDispatcher.protocolMenu` / `isStaleProtocolSelection` / `descriptorFor` 的 `tag:` 参数。工作台选择器按 tag 过滤列表不在此列 |
| `ModelCapabilities.forModel(...)` / `ModelDescriptor.of(...)` 在 `services/llm/` 之外用于**一个已存储的模型**（参数面板、参考图上限、参数记忆键） | 只按 id 解析，绕过了点单：中转上点了 Images API 的模型会拿到空参数表，参数写进请求读不到的命名空间，不报错 | `AppState.descriptorForModel(model)`（内部走 `LLMDispatcher.descriptorFor`）。按 id 问的是 chat 事实（如 `acceptsImageInput`）时不受点单影响，可以直接用 |
| `channel.type` / `channel.endpoint` 被直读（线路解析、仓库规范化、渠道编辑表单之外） | 扁平列是**主线路**；模型换到别的线路后按它们回答的协议、能力、地址全是错的，且不报错 | `RoutedChannel.forModel(channel, model)`（关于一个模型）或 `RoutedChannel.primary(channel)`（关于渠道本身：发现、探测）；`channel_flat_columns_scan_test` 钉住 |
| `channelType ==` / `channel.type ==` 出现在 `vendors/`、`llm_dispatcher.dart` 之外 | 这是重构前 `isXai`/`isNewApiGemini` 散点判断的复活形态 | 语义抬升为 `Vendors.byId(...)` 后读 profile 字段 |
| UI/state 里出现 `'openai-api-rest'` 这类裸字符串字面量 | 拼错静默失效；重命名时漏改（`Vendors.byId` 对未知 id 静默回退 openAIRest，错拼永远不报错） | 引用 `Vendors.openAIRest` 等常量。**两条豁免**：`database_migrations.dart`（迁移代码按当时的字面量冻结，改成常量反而会让未来的常量重命名悄悄改写历史迁移）；`channel_provider_presets.dart` 的 `ChannelProviderPreset.id`（那是向导自己的预设命名空间，与 vendor id 拼写雷同但语义无关——真正进 `llm_channels.type` 的是 `preset.channelType` 字段，它已全部引用 `Vendors.*`） |
| `if (family == ...)` 路由分支出现在 `llm_dispatcher.dart` 和 Layer 3 之外 | 路由规则必须单点可审计 | 挪进 dispatcher 对应 switch，加注释说明规则来源 |
| 给 DB 表新增"由其他表推导出来的"列（如当年的 `llm_models.type`） | 冗余副本没有级联更新，就是 bug 面；v32 迁移专门为删它而生 | 运行时解析（`channel → vendor → protocol`），不落库 |
| 协议文件里写死某厂商的 endpoint 路径差异 | endpoint 形状属于协议，*选择哪个* endpoint 属于 vendor | 独立协议类 + vendor 覆写，由 dispatcher 组合 |

新增代码的自检口诀：**"这行代码回答的是哪一层的问题？"** ——
线上格式 → protocols/；谁在供货/怎么认证 → vendors/；这个模型是什么 → Layer 3；
选哪条路 → dispatcher。回答不出来的，先别写。

## 协议实现的共享机制（2026-08 M2 加固，新协议照抄）

写一个新协议（或改既有协议的解码路径）时，以下机制**必须复用而不是手写**，
它们各自对应一类踩过的静默失败（`test/services/llm/llm_error_handling_test.dart` 钉住）：

- **`decodeJsonBody(response, apiName: …)`**（`protocols/protocol.dart`）——
  唯一安全的解码顺序：状态码 → JSON → 形状 → 错误信封。手写这四步曾让
  Gemini 把网关的 HTML 502 报成裸 `FormatException`（真实状态码永不现身）。
  异步任务的 **poll** 面传 `checkEnvelope: false`：失败的任务以
  `{status:"failed", error:{…}}` 形式装在 200 里，由 poll 自己的状态机报错
  （带上 operation 名），通用信封检查会先一步抢走并丢掉这个上下文。
- **`LLMApiException`**（`llm_errors.dart`，经 `llm_types.dart` 再导出）—— 非 2xx 与信封错误一律抛它。
  `LLMService.isRetryable` 读它的 `statusCode` 决定重试（仅 5xx/429）；
  **但计费路由例外**：`LLMDispatcher.isBilledOnSubmit` 为真（单发图像面、
  Midjourney、一切非 chat surface）时只重试"可证明未被上游受理"的失败
  （429、连接被拒、DNS 失败，`LLMService.isRetryableBeforeAcceptance`）——
  中转的 502/524/断连可能发生在上游画完之后，重发就是二次计费。单发路由的
  首块超时抛 `LLMDeadlineExceeded`；轮询被放弃抛 `LLMJobAbandoned`（带任务
  id），两者都永不重试；
  抛裸 `Exception` 的老路径靠一条锚定 `failed: <status>` 的 legacy 正则兜底，
  新代码不许依赖它。
- **`sendJsonRequest(client, url, headers:, body:, options:)`**（2026-09-14）——
  非流式请求/提交面的唯一发送口：与 `client.post` 发出同样的字节，但是
  `http.AbortableRequest`，接 `options[llmAbortTriggerKey]`。连接池里的
  client 不能为一个请求关闭，所以取消与非流式超时以前只是"不交付"，请求在
  上游照跑照计费；现在 `LLMService` 每次 attempt 发一个触发器（取消时由
  watcher 触发、attempt 结束时由 `finally` 触发），经它真正中断。
  `request()` 设置 `llmCancellationProbeKey` 时**串联**调用方已放的探针
  （`LLMService.chainCancellationProbe`，pitfalls 11 §H72），不许覆盖。
  multipart 用 `http.AbortableMultipartRequest` + `abortTriggerOf(options)`。
  新的非流式发送点照此写，不要再直接 `client.post`。
- **`LLMApiException.retryAfter`**（2026-09-14）—— `decodeJsonBody` 与各族
  流式非 200 分支用 `parseRetryAfter(headers)` 通用读取（`retry-after-ms` /
  秒数 / HTTP-date），不按 vendor 分支。`LLMService` 在 `shouldRetry` 放行
  **之后**才读：等待 = max(Retry-After, 2s×attempt)，超过
  `maxRetryAfter`（60s）不重试直接报错，睡眠可被取消打断。计费路由规则不变。
- **API 调试日志（`llm_debug_logger.dart`，2026-09-14）** —— `appendLine` /
  `appendStreamLine` 对每行做 `sanitizeLine`：≥2048 字符的 base64（含 `data:`
  URL）折叠成 `<base64 N chars>`，协议无需各写 safe-body。`LLMService` 每个
  attempt 建一个 `LLMLogCorrelation`（context / request 序号 / leg / attempt），
  用 zone 值传递（`runCorrelated`；`requestStream` 自身是生成器，用
  `correlatedStream` 在 zone 内打开并订阅），`startLog` 写进文件头，结束时
  `appendSummaries` 追加一行归一化的 `Summary:`（finish_reason / usage /
  `wire_rewrites`，失败则是错误类型）。协议不必转发任何东西。
- **`sseDataPayload(line)`** —— SSE 行解析（`data:` 后空格可选、注释行、
  `[DONE]`）。调用前自行跳过 `event:` 行；解析失败的行**忽略**，不许把
  `FormatException` 重抛成整条流的死刑（gemini 踩过，见
  `geminiChunksFromSseLine` 的 dartdoc）。
- **`redactUrl(url)`**（经 `protocol.dart` 转出口）—— 任何写进 debug 日志的
  请求 URL 必须先过它：Google 系 vendor 的 URL 带 `?key=`，靠日志落盘层的
  正则兜底等于把一个机制的 bug 变成凭证泄漏。抛出的错误消息同样要带上脱敏后的
  请求 URL（errors 06 §2）：`decodeJsonBody` 从 `http.Response.request` 取，
  自己拼错误的流式分支用 `redactUrl(url)`。
- **内容拦截只在一处判定（2026-09-14）。** 协议只**发布**
  `finish_reason: content_filter`（① 原样；④ `refusal`；③ 拦截类
  `finishReason` 与 `promptFeedback.blockReason`，**有无已产出文本都一样**）；
  `LLMService` 在 `request` 与 `requestStream` 流末各做一次
  `contentBlockedFailure`，**先记用量再抛**不可重试的
  `LLMApiException(isContentBlocked: true)`。协议里不许再自己抛拦截错误——那会
  跳过计费，也会让"半截文本 + 拦截"重新变回成功（pitfalls 11 §A7）。
- **流的完整性由流末检查兜底，不靠调用方猜（2026-09-14）。** ① 流：结尾的
  metadata chunk **无条件**发出（很多中转不发 usage，只按 usage 发会丢
  `finish_reason`）；流干净关闭却没有 `finish_reason` 时，有待拼的工具调用 → 抛
  截断错误（半截参数绝不交给 agent 循环执行），纯文本 → 标 `length` +
  `stream_incomplete`；块都到了却什么内容都没有（无文本、推理、调用、图片）→ 抛，
  `length` / `content_filter` 例外。③ 流补上与 ①④C2 同款的"一个 chunk 都没有"
  守卫；④ 的 `AnthropicStreamAssembler.finish()` 在 `tool_use` 块未收到
  `content_block_stop` 时抛。③ 自造的调用 id 是 `gtc_<nonce>_<n>`
  （`GeminiToolCallIds`，一条流共用一个实例）——按候选按 chunk 从 0 计的旧 id
  会在流内与跨轮撞车。① 的内联 `<think>` 只认回复**开头**那一个（reasoning 03
  §6），正文里出现的标签是作者的文字。
- **`imageMimeFromBytes` / `imageExtensionFromBytes` / `resolveImageMime`**
  （`core/image_magic.dart`）—— 图片的类型**读字节，不信声明**。中转的
  `inlineData.mimeType` 写 `image/png` 给过 JPEG 字节，`b64_json` 根本没有
  mime，重命名过的 `.png` 里装着 JPEG 也是常态。落盘取扩展名走
  `imageExtensionFromBytes`（`task_executors.dart`），请求侧的 `media_type` /
  `mimeType` 由 `ImageCompressor.readForApi` 经 `resolveImageMime` 定 —— ④
  会校验字节与 `media_type` 是否一致，不一致整个请求 400。声明只在字节认不出
  时兜底。
- **③ 的请求键一律 camelCase**（`inlineData` / `mimeType` /
  `systemInstruction`）。Google 自家 proto3 JSON 两种拼法都收，但挂这条 wire
  的中转（New API 的 Gemini 面）只认 camelCase，且**未识别的键被忽略而不是
  拒绝**：snake_case 的后果不是 400，是图片压根没到模型、system 提示被丢，
  响应 200 一切正常。`test/services/llm/image_relay_compat_test.dart` 遍历整个 payload
  断言没有带下划线的结构键，新字段写成 snake 会在那里先挂。
- **`VendorProfile.downloadHeaders(apiKey)`** —— 下载生成产物（视频/图片 URI）
  时用什么认证头是 Layer 2 知识，executor 只消费；按协议族分支写在调用方
  曾是红线违规（错头会被静默忽略，下一个非 bearer vendor 只会得到一个 403）。
  **带不带头**则是 Layer 1 知识（2026-09 修）：video poll 的 done 信封里
  `video.requiresAuth`（`videoRequiresAuthKey`）由产出 URL 的协议判定——
  Sora 式 `/videos/{id}/content` 是 API 端点，要带；DashScope OSS、MiniMax
  CDN、xAI 结果链接是签名直链，不许带（带了等于把 key 交给第三方主机）。
  判据 `videoUriNeedsAuth`：URL 与渠道 endpoint 同 host 才带。executor 经
  `LLMService.downloadHeadersFor` → `LLMDispatcher.downloadHeaders` 取头，
  不再自己 `Vendors.byId`。下载按容器签名（MP4 `ftyp` / WebM EBML）验收，
  一次重试，失败删半截文件。
- **`VideoJobProtocol.poll` / dispatcher `checkOperation` 的返回契约**是
  Veo 信封（`{name, done, response|progress}`），各家族一致 —— 包括 MJ
  分支（dispatcher 内翻译）。**失败一律抛错、不进返回值**：原先
  `gemini_veo` 是唯一豁免（原样返回 `{done, error}`），而 executor 只读
  `response`，用户看到的是 "no video URI found. Response: null"——已取消
  豁免，`veoPollResult` 对 `done && error` 抛带 code/message 的
  `LLMApiException`（安全过滤同理）。终态错误不带 statusCode，轮询循环
  （`job_poll.dart`，容忍连续 3 次瞬时失败）因此不会把它当成可重试的轮询抖动。

## ④ Anthropic 的六条不变量（会静默错，不会报错）

协议事实见 [`docs/api/landscape.md`](../api/landscape.md) §5；这里只记本项目
踩得到、且**不会以报错形式暴露**的六条。前四条是接入时就有的，后两条随
thinking / server tool 一起加。

④ 的实现在 `protocols/` 下分七个文件，依赖只朝一个方向（wire 在最底，protocol
在最顶）。改哪条不变量先看它住在哪 —— 第 3 条鉴权不在这里，在 `vendors/` 的
`AuthScheme`；第 7 条的续跑在 `llm/turn_continuation.dart`：

| 文件 | 管什么 | 下面哪几条 |
|---|---|---|
| `anthropic_wire.dart` | 常量：`max_tokens` 兜底、图片媒体类型、web search 工具类型与上限、`pause` / `turn_incomplete` 两个标记、thinking 预算下限 | 2、7 |
| `anthropic_history.dart` | `buildAnthropicHistory`：system 上提、工具结果并进 user、同角色合并与作者文本标注；thinking 块与 server-tool 轮的原样回放 | 4、5、7 |
| `anthropic_thinking.dart` | thinking 请求与 `output_config`、两种方言的选择与**按端点+模型学来的记忆**（进程级，测试要 reset） | 5 |
| `anthropic_payload.dart` | `prepareAnthropicPayload` + 缓存断点 | — |
| `anthropic_response.dart` | 读响应：content 块、server tool 结果、usage 三桶求和、`stop_reason` 翻译、`turn_incomplete` 的形状判定 | 1、2、6、7 |
| `anthropic_stream.dart` | `AnthropicStreamAssembler`（见本节末） | 6、7 |
| `anthropic_chat_protocol.dart` | 传输：一次重试换方言、非流式 / 流式两条 I/O 路径、模型发现 | 5 |

1. **usage 三桶不重叠，必须先加起来。** ④ 的 `input_tokens` 只是未命中缓存的
   余量，`cache_read_input_tokens` / `cache_creation_input_tokens` 与它并列；
   而 `LLMService._recordUsage` 的口径是"prompt 总量包含缓存部分，再把缓存减
   出去"。直接把 `input_tokens` 交上去，长 prompt + 缓存命中会把输入量少报一
   个数量级，然后再被减一次。协议层把三桶之和以 `prompt_tokens` 发布
   （`_recordUsage` 优先读它），原始桶原样保留。
2. **`max_tokens` 必填且无服务端默认。** 常量在
   `anthropicDefaultMaxTokens`（8192 —— 在服的 Claude 全都接受的最大值；再高会
   在老型号上 400）。它同时意味着**截断是可达状态**，所以 `stop_reason` 还要
   翻译成 ① 的 `finish_reason` 词表：助手循环和网页抓取都只认
   `finish_reason == 'length'`。
3. **鉴权要两套都发。** 官方只认 `x-api-key`，生态里
   `ANTHROPIC_AUTH_TOKEN → Bearer` 同样是一等约定，中转两个都收且文档都不说要
   哪个。`AuthScheme.anthropicApiKeyWithBearerFallback` 一律发 `x-api-key` +
   `anthropic-version`，只在 host 是 `api.anthropic.com` 时不发 bearer。
   顺带：`VendorProfile.decorateUrl` 已从"非 bearer 就加 `?key=`"改写成穷尽
   switch —— 原来的写法会让每个**新增**的 auth scheme 默认继承 Google 的
   query 参数约定，把 Anthropic 的 key 写进 URL 和每一行日志。
4. **三处改写才能过 400：** system 提到顶层（④ 没有 system 角色）、工具结果变
   成 user 消息里的 `tool_result` block（④ 没有 tool 角色）、连续同角色消息合
   并（④ 要求角色交替）。第三条对 agent 循环是硬要求：一轮并行调用的 N 个结果
   必须装在**同一条** user 消息里。三条都由 `buildAnthropicHistory` 负责，
   `test/services/llm/anthropic_chat_test.dart` 逐条钉住。

5. **thinking 有三套词表，且开了就欠一笔债。** Anthropic 新代（4.6+）是
   `{type:"adaptive", display:"summarized"}` + 顶层 `output_config:{effort}`
   （`display` 必须显式——最新一代默认 `omitted`，思考照全额计费但一个字不给）；
   Anthropic 旧代（4.5 及更早）与百炼 ④ 面是
   `{type:"enabled", budget_tokens:N}`（N 从 `max_tokens` 里切，下限 1024，
   且必须给答案留出余量）；MiniMax M3 是裸 `{type:"adaptive"}`。**两代 Claude
   互斥**：4.7+ 收到 `enabled` 直接 400，4.5 不认 `output_config`，而两代
   住在同一个 host、同一把 key 下。所以 `VendorProfile.thinking` 只是**默认**，
   协议按请求解析（`resolveAnthropicThinkingDialect`）：一条 400 学来的记忆
   （按 endpoint + model，进程内）→ Layer 3 的代次判断
   （`ModelDescriptor.usesLegacyAnthropicThinking`，只在 vendor 说的是 Anthropic
   拼法时才生效，不会替 `none` 打开思考、也不改写 MiniMax 的方言）→ vendor 默认。
   400 且报文点名 `thinking` / `output_config`（但**不是** `effort` 的取值——
   那是档位太高，换拼法只会再吃一个 400）时换另一种拼法重试一次并记住
   （`isAnthropicThinkingRejection` / `learnAnthropicThinkingDialect`）；中转上
   模型名是自由文本，代次从名字猜不可靠，这条重试就是为它准备的。协议仍不许问
   "你是谁"—— **Layer 2 说默认方言，Layer 3 说这个模型是哪一代，Layer 1 说
   JSON 长什么样**。档位（`ReasoningEffort`）在 adaptive 拼法上落到
   `output_config.effort`（low/medium/high/max，本仓无 `xhigh`），在 budget 拼法
   上折叠为"开"，off 与默认一律不发字段（不发 `disabled`：最新一代无条件拒收）。
   开了之后：带工具调用的 assistant 轮**必须原样回传 thinking block，连同
   `signature`**，否则下一次请求被拒。它存在 `LLMMessage.reasoningSignature`
   （随会话持久化），回传时排在 text / tool_use **之前**；没有签名的 thinking
   宁可丢掉也不发 —— 发了必被拒，而"模型重新想一遍"好过"整个请求失败"。
   注意这与 ① 的机制不同：① 回传的是一个**字段**（名字记在
   `reasoningFieldName`），④ 回传的是一整个**块**，所以 ④ 路径上
   `reasoningFieldName` 永远是 null，① 的 payload builder 才不会替它编一个字段名。
   **三族的回传载体都按产出模型限定**（2026-09-14）：`rawThinkingModelId` 记录
   产出者——④ 的块、①/百炼原生的推理字段、③ 调用上的 `thoughtSignature`
   一视同仁（同步路径由协议记，流式路径由 `LLMService._streamOnce` 记），
   payload builder 只回传给同一个模型：换了模型，① 官方对未知字段 400，中转照
   input 计费。④ 的原始块要求匹配；其余载体在 `rawThinkingModelId` 为 null 时
   照旧回传，这是记录产出者之前持久化的旧会话能继续用的原因。
   ③ 的载体是整组原始 `parts`（`LLMMessage.rawModelParts`，2026-09-14，
   protocol 02 §2.2 第 3 条）：只挂在带工具调用的模型轮上，thought part、每个
   `thoughtSignature`（包括流末尾挂在空文本 part 上的那个）与顺序一并原样留存——
   只重建 text + functionCall 会丢掉不在调用 part 上的签名，③ 对此回
   `MISSING_THOUGHT_SIGNATURE`。流式路径由 `GeminiModelPartsCollector` 按到达顺序
   跨 chunk 收集（③ 的每个 chunk 都是完整对象），流末一次性发出。与 ④ 原始块同样
   **要求匹配**产出模型才原样回放；换了模型就重建且不带签名。改写工具调用参数的
   上下文省略（助手的 `write_knowledge_file` 省略、`ask_user` 剥调用）与
   `rawContentBlocks` 一起丢掉它。内联 `<think>`
   切出来的推理从不并入这个字段（reasoning 03 §6 第三条）。
6. **server tool 不是 tool call。** `web_search_20250305` 由服务端自己执行、
   自己回答，响应里的 `server_tool_use` + `web_search_tool_result` 是**已完成的
   事实**。把它当 `LLMToolCall` 交给 agent 循环，等于让本地去跑一个没人要求的
   工具，再去回答一个模型从没发起的调用。所以它们进 `serverToolRuns`，来源写进
   metadata 的 `server_tool_runs` 并打一条 INFO 日志（用户在为它付费，且答案建
   立在这个 App 没有选择过的网页上）。
   连带的一条：开了 server tool 之后一轮里会出现**多个 text block**（搜索前一
   段、搜索后一段），所以 block 之间按空行拼接，不是裸接 —— 裸接会把两段话连成
   一句。
7. **「一次请求 = 一个完整回答」在 server tool 面前不成立，且只有一种停法会
   明说。** 官方 ④ 用 `stop_reason: pause_turn`（协议发布为
   `finish_reason: pause`，**不再**翻成 `stop`）；MiniMax 的 ④ 面跑完搜索把结果
   送回就 `end_turn`，不再叫模型，响应是个格式完好的成功——协议按**形状**判：
   最后一个非 thinking 块是 `web_search_tool_result` 即 `turn_incomplete`
   （`anthropicTurnIncompleteKey`）。两种都由 `LLMService.request` 续跑，最多
   `maxTurnContinuations`（3）次，每段各自记用量，最后
   `mergeTurnParts` 合成一个响应交给调用方（文本按段落拼、tool_calls 取最后一段、
   token 求和、content 数组串接）。**续跑的形状不同**（`turn_continuation.dart`）：
   `pause` 按协议原样送回 assistant 消息；`turn_incomplete` 走纯文本回填——把
   `server_tool_runs` 渲染成 user 消息，因为 MiniMax **拒收自己发出的**
   `server_tool_use` 块。
   为此 server-tool 轮的**整个 `content` 数组原样留存**（`LLMMessage.rawContentBlocks`，
   与 `rawThinkingBlocks` 同性质、同 `rawThinkingModelId` 作用域，随会话持久化）：
   结果块里的 `encrypted_content` 是服务端解密用的，改了或缺了 400；
   `buildAnthropicHistory` 对带它的 assistant 轮整块回放而不重建。流式路径的
   `AnthropicStreamAssembler` 用 `content_block_start` 的副本 + delta 重组出同一
   份数组（含 `citations_delta`），`test/services/llm/anthropic_chat_test.dart` 钉住流式与同步
   给出同一份。助手对 `write_knowledge_file` 大参数做上下文省略时丢掉这份副本
   （省略正是为了不重发那段内容），改回重建路径。
   `web_search_tool_result` 的 `content` 是对象而非数组时是**错误块**
   （`error_code`：`max_uses_exceeded` / `too_many_requests` / …），记进
   `ServerToolRun.error` 并 WARN，不是失败——`max_uses_exceeded` 是刹车在起作用。
   声明 `web_search_20250305` 时同时发 `max_uses`（`anthropicWebSearchMaxUses`
   = 5）：按次计费且结果在后续每轮反复计入 input，这是唯一的刹车。

**四条 chat wire 现在全都声明工具**（`streamingDeclaresTools`：④ ③ ① C2）。理由
不是增量消费 —— agent 循环拿不到完整一批就配不出结果 —— 而是**保活**：
`LLMService` 流式分支的超时是**按 chunk** 计的、每个 chunk 重置，而非流式那条得
覆盖整轮生成。一次 `submit_prompt` 6–7K token，没有任何固定 deadline 能覆盖，这
正是助手每次交付都在写到一半时超时的原因（见
`docs/plans/2026-08-assistant-timeout.md`）。① 是最后补上的一条，而它覆盖面最大
—— 绝大多数中转渠道走的都是 ① 面，在此之前它们的助手每一轮都被静默降级成非流式。

拼装逻辑在 `AnthropicStreamAssembler` 里，从传输循环里拆出来是为了能不开 socket
就钉住 —— 和 ③ 的 `geminiChunksFromSseLine` 同一个套路。三条不变量：

- **`content_block_stop` 之前什么都不出去。** `input_json_delta` 的每一片单独看
  都不是合法 JSON。空 buffer 是 `{}`（无参工具根本不发 delta），不是解析失败。
- **分组键是 block index**，因为 ④ 可以在上一个 block 关闭前就打开下一个。
- **thinking 块必须在流式路径上原样留存**（`rawThinkingBlocks` +
  `signature_delta`）。带工具调用的一轮正是需要重放它们的那一轮，而 ④ 对不完整的
  thinking 历史不是报 400，是**静默关掉 thinking 继续计费** —— 漏了不会有任何
  报错。签名规则与同步路径一致：只留封好的块，`redacted_thinking` 永远留。

① 的 `function.arguments` 按 `delta.tool_calls[].index` 分片（streaming.md
§1），另有一套累积器 `StreamingToolCallAccumulator`（在
`streaming_tool_calls.dart`；`contentToText` / `resolveToolCallId` /
`decodeToolArguments` 在 `openai_chat_parsing.dart`，同属 ①-shaped 的公共件，
C2 与 Responses 协议都从这两个文件引，不经过 `openai_chat_protocol.dart`）。
**C2 复用同一个类** —— DashScope 私有面的 `tool_calls` 就是 ① 的拼法。
三条不变量：

- **流结束前什么都不出去。** ① 没有 ④ 的 `content_block_stop` 那种逐调用终止
  符，所以只能在传输循环跑完之后 `flush()`。这也是它必须放在 `finally` **之外**
  的原因：断在参数中间的流要报错，不能交出一个半成品调用。
- **分组键是 `index`，不是 `id`** —— `id` 自己也会分片。相对地，中转不发
  `index` 时退回该调用在本帧数组里的下标，那本来就是这个字段的含义。
- **分片是"合并"不是"追加"。** 同一套 JSON 分片走两种方言：① 发增量，而 C2 只在
  `incremental_output` 被兑现时发增量，被拒或被中间层重组时**每帧重复整个调用**。
  盲目追加会拼出 `{"a":1}{"a":1}`（解析为空）和 `view_imageview_image`。判据分两级：
  帧上**没有 name 而调用已有 name**，那它构造上就是增量帧，参数无条件追加 ——
  这关掉了前缀启发式的那个歧义窗口（`{"a":` + `{"a":1}}` 会被整体替换吞掉）；
  帧上重复了 name（累计方言的签名），才落回"本帧是否以已收内容为前缀"。
  `DashScopeStreamChannel` 对文本面对同一个歧义，文本没有 name 旁证，用的是
  **方言闩锁**：累计帧只可能延长累积，所以第一个没有延长累积的帧就证明了
  这条流说的是增量，此后一律追加 —— 重复性内容（分隔线、省略号、叠字）造成的
  "增量恰好以全部已收内容开头"不再被吞。

降级判断写在 `LLMDispatcher.streamSupportsTools` 里 —— 和其它路由分支放在一起，
逐 family 手写而不是查表，所以新增一族默认是 `false`，补上累积器是这里可见的一行
改动。

两个开关都是**按模型**存的（v33 迁移的 `llm_models.enable_thinking` /
`enable_web_search`，默认关），由 `LLMConfigResolver` 解析进 `LLMModelConfig`
—— 不是请求 option。这样助手、提示词精修、AI 重命名三条路自动都认，不必各自记得
传；同时一条渠道下"支持思考的模型"和"发了就 400 的模型"可以分别设置。UI 上思考开关行
只在 ④ 渠道下显示；**联网搜索开关**（2026-09-14）改问
`LLMDispatcher.serverWebSearch(channelType:, modelId:, tag:, wireProtocol:)`，
与推理挡位同一套面解析：④ 厂商的 ④ 面是带来源的 `web_search` server tool；
声明在 `VendorProfile.serverWebSearchFaces` 里的面（百炼两个 vendor 的 ① 与原生面）
是无痕的 `enable_search`——① 发顶层、原生发 `parameters.enable_search`，都不返回
来源，协议不解析也不伪造任何事件（pitfalls 11 §A10），编辑器在开关下写明
「搜索无痕」。① 适配器发之前再查一次声明：模型行上存着的开关会随导入、改渠道
类型旅行到 api.openai.com，那里未知顶层字段直接 400（tools 05 §5）。百炼的 ④ 面
未声明，开关不出现。

**同一个答案，编辑器和线上共用**（2026-09-16）：`VendorProfile.webSearchOn(face)` 是
「这个开关在这个面上变成什么」的唯一出处——④ 面只对 ④ 家族的 vendor 是 `withSources`，
①/原生面看 `serverWebSearchFaces`。`serverWebSearch` 返回它，三个 payload 构造器
（① `openai_chat_payload`、原生 `dashscope_chat_protocol`、④ `anthropic_payload`）问
`sendsWebSearchOn`。此前 ④ 构造器对任何 vendor 都声明 `web_search`：百炼模型在 ① 面开过
开关、再点单到 ④ 面，编辑器里开关已隐藏，请求里却还带着工具。存着的开关不在保存时清掉——
它在同一模型的 ①/原生面上仍然有效。

三个 ④ vendor（`anthropicRest` / `newApiAnthropic` / `minimaxAnthropic`）
除 thinking 方言外 chat 行为一致，分开还为记录供货方。**MiniMax 是唯一 base path
不是 `/v1` 的 ④ 主机**（`/anthropic/v1`，与它的 ① 端点并列），所以协议里不能有
任何地方假设版本后缀 —— 这也是它值得一个向导预设的原因：两个端点填反了只会得到
一个 404，而 404 不会说是 URL 的哪一半错了。同一家厂商同时供 ① 和 ④，正是"协议族
属于渠道、不属于厂商"最直白的证据。

**`minimaxAnthropic` 还是第一个带图像/视频菜单的 ④ vendor。** ④ 这个*协议*没有
图像面，但供这条 wire 的*厂商*可以有：MiniMax 的 `/v1/image_generation` 与
`/v2/video_generation` 和它的 `/anthropic/v1` chat 同主机同 key。所以
dispatcher 的 anthropic 分支从"整族抛 UnsupportedError"改成先看 vendor 的声明
——判据是声明而不是家族，和 ① 分支上的写法一致。两个 MiniMax vendor id 声明**同
一对**原生面：chat 走哪一面是渠道的选择，图像/视频端点是哪个则不是。

四条 wire 没有公共前缀（`/v1`、`/anthropic/v1`、`/v2`），而渠道只存一个地址，
所以 `minimax_payload.dart` 里三个 base 推导函数（幂等、只看 path）是这家能"一
条渠道一把 key 跑通四条面"的全部机关。两条私有协议自己推导 base，不进
`protocolBases` —— 那张表只服务*通用*协议在替代面上的复用。

## ② OpenAI Responses 的不变量（2026-09-14）

协议事实见 [`docs/api/responses.md`](../api/responses.md)；实现在
`protocols/openai_responses_protocol.dart`。`WireProtocol.openaiResponses`
（`openai-responses`）是 **`openai` 家族的一个 chat 面**，不是新家族：base、
bearer、`/models` 与 ① 完全相同，所以没有 `protocolBases` 项、discovery 不变
（standard 01 §3.1 的判据是 auth/发现形状，这两样没变）。它出现在
`openAIRest` / `newApiOpenAI` 的 `chatMenu` 里**排在 ① 之后**——① 仍是 auto，
存量渠道一个字节都不动。`xaiApi` 例外，**Responses 排第一**（2026-09-15）：xAI
官方把 Responses 标为推荐、Chat Completions 标为 Deprecated（01 §9.1），所以 xAI
渠道上未点单的 chat 模型改走 Responses，① 留作点单。这是有意移动存量路由的一次：
Grok 4.5/4.6 在该面上「关闭」必 400（见第 8 条），编辑器提示随之默认出现。菜单 >1
项，模型编辑器的点单下拉因此在这三家的 chat 模型上出现。

**渠道级默认（分行，01 §8.3）**：`openAIResponsesRest`（`openai-responses-rest`）与
`newApiOpenAIResponses`（`newapi-openai-responses`）是同一对 host/key 的第二行，
`chatMenu` 为 `[openaiResponses, openaiChat]`——Responses 排第一即渠道 auto，① 留作
点单。"整个中转只跑 GPT-5.x"是渠道的事，不该逐个模型点单；但 Responses-only 模型
与 ① 共存于一个渠道也是常态，所以两种表达并存。预设上是 OpenAI 官方的「对话接口」
切换与 NewAPI 的第四种格式，切换不改写地址。`_familyRoute` 的 chat 分支读
`menuFor(chat).first`，所以 id 自身路由在这两行上就是 Responses，`_servedBy`
为 null，descriptor 与 id 的一致（`model_kind_protocol_pin_test` 的全 vendor 回归门）。

以下几条都**不报错**，改动时逐条对照：

1. **`instructions` 恒发，空串也发。** 全部 system 消息 hoist 并以空行连接。
   New API 中转在它缺失时注入几千 token 的 Codex 系统提示，只在账单上可见
   （pitfalls 11 §62）。与 ① 不同，这里不补默认句——字段在就够了。
2. **`store: false` 恒发。** 应用自己存历史；零保留组织不发会被拒；也是端点给
   reasoning 条目附 `encrypted_content` 的前提。
3. **函数工具扁平 + 显式 `strict: false`。** 省略时官方端点自动升 strict，把带
   可选字段的 schema 改写成"全必填否则 400"（pitfalls 11 §64）。`tool_choice`
   只随函数工具发，命名形态 `{type:"function", name}`，没有 ① 的 `function` 包装。
4. **回传载体是整组 output 条目，原样、按模型限定、替代而非并列。**
   `LLMMessage.rawResponseItems`（与 `rawModelParts` 同一套：只挂在带工具调用的
   轮上、随会话持久化、`rawThinkingModelId` 记产出者、**要求匹配**才原样回放，
   null 也不回放）。流式由 `ResponsesStreamAssembler` 从 `output_item.done` 直接
   收集 reasoning / function_call / message（服务端工具条目不收），同步路径把
   `output[]` 逐条喂给同一个 assembler——两条路不可能分叉。换了模型就退回裸
   `function_call` + assistant 文本；**原样条目与裸调用绝不同时发**（call_id
   重复）。只有当每个组装出的调用都能在收集到的条目里找到同 `call_id` 的
   `function_call` 时才发出载体：只靠 delta 拼出的调用没有条目，只回放推理不回放
   调用会破坏配对。转发点与 `rawModelParts` 相同（`LLMService._streamOnce`、
   `mergeTurnParts`、助手两处写入、子代理、AI 重命名、网页抓取）；助手的
   `write_knowledge_file` 省略、`ask_user` 剥调用、配对修复三处改写**丢掉**它。
   回传缺失不报错（官方与 xAI 实测四种回传方式都 200 且答对），只能靠调试日志
   对照（protocol 02 §7.3）。
5. **流读取。** 只读 `data:` 行（`event:` 行冗余，`[DONE]` 容忍）；文本只读
   `delta`（旁边的 `obfuscation` 是填充）；函数调用按 **`output_index`** 分组
   （部分中继缺 `item_id`），`function_call_arguments.done` / `output_item.done`
   的整串覆盖 delta 累积；没有流式文本/摘要的条目在 `output_item.done` 时补发。
   终止：`completed` → `stop`（有调用时 `tool_calls`）；`incomplete` 的
   `max_output_tokens` → `length`，`content_filter` → `content_filter` 由
   `LLMService` 统一抛（协议不自己抛，与其它三条 wire 一致）；`response.failed`
   / `error` 事件 / 无 `type` 的裸 `{error}` → `LLMApiException`。**拒答**——
   `response.refusal.delta` / `response.refusal.done` 事件，或 message 条目里的
   `{type:"refusal", refusal}` part（流式与同步同一判定）——发布
   `finish_reason: content_filter`（`finish_reason_raw: refusal`），与 ④ 的
   `refusal` 一致，由 `LLMService` 记完用量后统一抛；拒答文字**不进**回复文本，只打
   一条 WARN（当成普通文字交付，等于把拒绝写进交付物并当成功）。**没有终止事件**
   就结束：纯文本按 ① 的规则标 `length` + `stream_incomplete`（usage 缺失 =
   未报告）；有调用则抛——无法证明这一批调用是完整的。一个事件都没有、或完成了却
   什么内容都没有 → 抛。
6. **usage 以 ① 的拼法发布**：`input_tokens` → `prompt_tokens`、
   `output_tokens` → `completion_tokens`、`input_tokens_details.cached_tokens`
   → `prompt_tokens_details.cached_tokens`（输入的子集，与 ① 同口径），
   `_recordUsage` 无需改动。
7. **回显比对（errors 06 §4.1）。** 终止响应回显 `reasoning.effort`；与本请求
   实际发出的值不同时写 `metadata['wire_rewrites'] = [{field, sent, echoed}]`
   并打一条 WARN，调试日志的 `Summary:` 行照录。只报告，不重试、不抛；没发就不比，
   没有回显也不报（同一档位背后可能是多个上游）。本路径不发 `temperature`，所以
   只比 effort。
8. **推理挡位**：六档（默认不发；关闭 `{effort:"none"}`；其余带
   `summary:"auto"`——不带就没有摘要事件，思考付费却看不见）。**不按型号裁剪**：
   Grok 4.5/4.6 拒 `none`、全系 Grok 与 GPT-5.4 拒 `max`，由端点 400 说话；编辑器
   在该面上多一行提示（`reasoningEffortResponsesHint`，面由
   `LLMDispatcher.resolvedChatFace` 判定，与挡位同一套解析）。
9. **`include:["reasoning.encrypted_content"]` 是 Layer 2 声明**
   （`VendorProfile.responsesIncludeEncryptedReasoning`，只有 xAI 为真）：xAI 不带
   就没有加密推理，回传照样 200 只是推理不延续。官方端点不带是否丢失未经官方 key
   验证，默认不发。协议里没有任何 vendor 分支。
10. `max_output_tokens` 只在调用方显式封顶时发（渠道探测）；有中转无视它，所以
    "没报截断"不等于"没超长"（pitfalls 11 §65）。

没做的（记在这里免得被当成遗漏）：`text.format` / `text.verbosity`（结构化输出
04 §5——本仓没有调用方）、Responses 内置工具（`web_search` 等，tools 05 §5；
编辑器的联网开关在该面上返回 unsupported）、`previous_response_id`（有状态模式
在第三方兼容层不存在）。测试：`test/services/llm/openai_responses_test.dart`。

## 输出上限（2026-09-16）

> 立项与实测证据在 `git show 2e7f443:docs/plans/2026-09-assistant-output-cap.md`
> （执行清单同目录 `-execution.md`）。这里只留分层结论。

四族里只有 ④ 的输出上限必填；①②③ 不发就是服务端默认，而中转站的默认常常是
4k–8k，提示词助手的一次交付实测 6–8K token。所以上限成了**模型级用户配置**
（`llm_models.max_output_tokens`，v44；`null` = 不发，`> 0` = 发这个数，**没有「无限」
态**——④ 必须发数字，其余家族的无限就是不发）。分层上的几条：

- **协议只经一个口读上限：`protocol.dart` 的 `outputCapFor(target, options)`。**
  顺序：每请求的 `options['maxTokens']`（渠道探针要 1 个 token）→ 模型配置 → null。
  五条 chat wire 各自把它写成自己的拼法（① 见下、② `max_output_tokens`、③
  `generationConfig.maxOutputTokens`、④ `max_tokens`、C2 `parameters.max_tokens`）；
  非流式 deadline 的 `_outputCap` 读同一个排序。③ 的 builder 没有 target，由协议算好
  经 `outputCap:` 传入，裸 option 仍作回落（探针与抓取器路径不变）。在 builder 里直接
  `requestedMaxTokens(options)` 而不经 `outputCapFor`，就是绕过了模型配置——review 时 grep。
- **① 的字段名是 Layer 2 知识，按 host 定：`VendorProfile.outputCapFieldFor(endpoint)`。**
  `api.openai.com` 发 `max_completion_tokens`（GPT-5 / o 系对旧名 400），其余一律
  `max_tokens`——包括 New API 中转与通用 ① profile（`Vendors.openAIRest` 同时是「自定义
  OpenAI 兼容」预设和未知渠道类型的回退，老中转与 Ollama 只认旧名）。和
  `AuthScheme.anthropicApiKeyWithBearerFallback` 的 host 判断同一形状：vendor 层看
  endpoint，协议只拿答案，不看模型 id，不做 400 换名重试。DeepSeek / 百炼兼容面 /
  MiniMax 文档写「旧名已弃用仍接受」，实测过再改声明（`outputCapField` 仍可按 vendor
  声明新名）。顺带修掉了探针在官方 OpenAI 上发旧名的问题。
- **④ 的 8192 退为兜底常量**（`anthropicDefaultMaxTokens`），budget 方言「取一半」随
  用户的上限放大。
- **不夹到 `window − occupied`。** 托管端点对不可能的请求会响，本地栈自己截短；请求层
  再改写就是第三种谁也看不见的行为。编辑器在上限 ≥ 上下文大小时提示，仅此而已。
- **发现时只预填新行的上下文窗口，不预填上限**（`discoveredLimitsOf` 按键形读 Anthropic
  `max_input_tokens`、Gemini `inputTokenLimit`、OpenRouter `context_length` 与
  `top_provider.context_length` 取小、LM Studio `max_context_length`；存量行是用户的，
  不改写）。列表报的输出上限是模型的**最大值**，不是谁选的要发的数——存进去就会随每次
  请求发出、撑大 deadline、④ budget 方言按它一半开思考、长会话上 input + max_tokens
  超窗直接 400——所以函数读得出（`max_tokens` 只在 `max_input_tokens` 同在时算上限），
  对话框不种。这是 usage 04 §4「协议不告诉你窗口」的唯一例外来源。
- 编辑器区块与刻度：`widgets/models/model_edit/model_edit_output_cap.dart` +
  `services/catalogue/output_cap_scale.dart`（六档 4k–128k，输出侧的刻度，不复用输入侧的
  九档）。设计稿 <https://claude.ai/artifact/Y5noFcoMjvC1VXaoSGXXvH>。
- 测试：`test/services/llm/output_cap_payload_test.dart`（五条 wire 逐字节、① 按 vendor 选名、④ 兜底与
  budget 折半、探针压过模型配置、deadline）、`test/services/llm/model_discovery_limits_test.dart`、
  `test/services/catalogue/output_cap_scale_test.dart`。

## 火山方舟 · Seedream（2026-09-18）

> 协议事实与实测在 [`docs/api/volcengine-ark.md`](../api/volcengine-ark.md)；当轮的执行清单
> 已退役，正文在台账指向的 `git show` 里。设计稿 Claude Design `D1e 火山方舟 · Seedream`。

- **一个 vendor、一个协议，不加家族。** `Vendors.volcengineArk`（`volcengine-ark`）是 ①：
  chat 走 `{base}/chat/completions`；生图是 `WireProtocol.arkImages`（`ark-images`，
  `protocols/ark_images_protocol.dart`，body 规则在纯函数的 `ark_payload.dart`），声明为
  `imageMenu`。与 `xaiImages` 同类：同一族下由 vendor 选的替代面。
- **两个 base 是一个 vendor 的两个向导变体。** 按量 `/api/v3`、套餐 `/api/plan/v3`，路径相同、
  key 不通用。这是**第一个两个变体同一 `channelType` 的预设**：`variantForChannelType` 因此按
  地址回读（只看类型时套餐渠道被读成按量，编辑器会提议把地址「恢复」到它的 key 必 401 的
  base）；变体卡副行在兄弟变体同协议族时印路径（`channelProviderVariantCaption`）。
- **发现靠目录。** 套餐 base 的 `GET /models` 是 404（实测），`unlistedModels` 给出按量四款
  带日期 id 与套餐两款点号别名，404 时退回目录。
- **Layer 3：`ModelFamily.seedreamImage`，按版本出表。** 分类只认 `seedream`；版本由
  `ModelFamilyClassifier.seedreamVersion` 读（`5-0` 与 `5.0` 同一代，六位日期不当次版本），
  pro 由 `isSeedreamPro` 认（lite 有三种拼写）。五张表 + 协议兜底表，控件跟着版本走。
  尺寸是「档位 + 比例」两个控件：比例自动 = 只发档位，选了比例 = 查
  `ModelCapabilities.tierPixelSizes`（各版本文档的映射，协议只查表）。**水印永远明发、默认关**
  （上游默认开且照常计费）。5.0 pro 的拆图层 / 透明编辑收成一个「任务」三段控件，恰好 1 张
  参考图的前置条件在发请求前检查（无状态码的 `LLMApiException`，不重试、不计费）。
- **中转站是这条规矩的例外：** 认得出的 Seedream id 在 ① 族 vendor 上 auto = `arkImages`，
  菜单首项（`_familyMediaSurfaces` 按模型 family 加），Images API / 对话出图仍可点单。理由：
  它的路径就是 Images API 的 `{base}/images/generations`，在中转 host 上有意义——「中转不提供
  厂商原生协议」防的是从 endpoint 推导出的私有路径，这里没有推导。先例是 grok-imagine 在
  中转上走 Images API。
- **路由答案**：单发、提交即计费、不声明工具；超时 5 分钟起，按一次请求可能画的张数
  （`maxImages`，拆图层按 17）每多一张 +40 s，封顶 15 分钟。计费按张：`image_count`；方舟的
  `output_tokens`（像素/256）不进 token 键，放在 `ark_usage` 下，免得按 token 的费用组算出假钱；
  不发布 `output_size`，按规格的档位行写的是 `2K`。
- **输入图张数（`input_image_count`，2026-09-21）**：七个 images 协议（OpenAI / xAI / 方舟 / 百炼同步 ·
  异步 / MiniMax / Midjourney）都在响应 metadata 里发布这次请求**实际放进请求体**的参考图张数，按规格计费组据此收
  输入费（`SpecUsage.price` 的输入一侧）。两条不变量：① 张数在组完请求体之后数——
  `capReferenceImages` 只管按 `maxReferenceImages` 截断，读不到的附件是在那之后才被丢掉的，拿截断后的
  长度计费会为没发出去的图收钱；② 上游自己回报的张数优先（方舟 5.0 pro 的 `usage.input_images`，
  原始张数），与 `output_size` 回显压过请求值同理，优先级写在 `sentInputImages(sent, reported:)` 一处。
  **每个图片块也必须带这个键**（`_asChunks`、方舟 SSE、Midjourney 自己的 controller——凡是自己造
  `imagePart` 块的地方）：流在出图之后、收尾块之前被放弃时，提前退出的记账靠它。上游回报的 0 要明发
  （`{input_image_count: 0}`）：合并后的 metadata 不会丢掉后一块只是没写的键，只有显式的值能把图片块
  带的本地张数压下去。文生图不发布这个键（除非上游自己回报了 0）；聊天面（①③④）也不发布，读作 0——按 token 计费的出图模型本该如此。
  **新增一个带参考图的 images 协议时必须发布它**，否则该协议上的输入费静默记 0。
- **上游报价（`reported_cost_usd`，2026-09-22）**：上游自己说这次请求扣了多少钱时，协议把它翻成美元发布在这个键下
  （`reportedCostKey`，`output_spec.dart`）；今天只有 xAI images 协议发（`usage.cost_in_usd_ticks`，1 tick = $10⁻¹⁰，
  换算 `reportedCostFromTicks` 一处）。记账（`_writeUsageRow`）只读这个键、不认任何 vendor 字段，落到
  `token_usage.reported_cost`（v49，NULL = 没报）；有值时**压过三种计费模式的全部算式**（`TokenUsage.costParts.reported`），
  因为它含输入图那一侧——计费组的快照照旧写在同一行上（`snapshotCost`），用量页拿两者对照。**中转协议不翻这个键**：
  中转有自己的价，用户填的档位表才是他付的钱；xAI images 协议只在 xAI 自家 vendor 的 image 菜单上（`llm_dispatcher.dart`）。
  **两条不变量**：① 凡是把上游 `usage`（或任何上游 map）原样铺进 metadata 的地方都走 `upstreamUsage()`（`protocol.dart`），
  它剔掉 `reported_cost_usd` 与 `input_image_count` 两个保留键——记账对所有 vendor 都读这两个键，原样铺就等于让中转 / 上游
  随便起个同名字段来定账（`upstream_usage_sites_test.dart` 钉聊天面四个纯函数面，百炼流式面在
  `dashscope_stream_regressions_test.dart` 走线钉；xAI、OpenAI Images、MiniMax 三个 images 协议在
  `xai_images_protocol_test.dart` / `input_image_count_test.dart` 的走线测试里各钉一条伪造用例）；
  ② 凡是自己造 `imagePart` 块的地方（今天是 `_asChunks`；方舟 SSE 与 Midjourney 的 controller 若哪天也报价，同样要带），
  图片块也要带这个键，与 `input_image_count` 同理——流在出图后被放弃时兜底记账只看到图片块。
- **视频的输入图与终态报价（`D2e`，2026-09-22）**：五个视频协议（Veo / OpenAI Videos / 百炼 / MiniMax 云与 H3 本地 /
  xAI）的 `submit` 返回 `VideoSubmission{requestId, inputImages}`，不再是裸 id；张数按上面的不变量①在**组完请求体之后**数
  （读不到的附件、互斥被丢的参考图、xAI 不支持的尾帧都不算：xAI 首帧计 1 或 `reference_images` 长度，OpenAI Videos 数
  multipart 文件，百炼数 `input.media[]`，MiniMax 两面数 partition 之后的 `kept`，Veo 用 `veoInputImages(payload)`）。
  `LLMOperationTicket.inputImages` 带到 `LLMService.startLongRunning`，提交行的 metadata 因此有 `input_image_count`，
  计费组的输入一侧对视频生效——判据 `PricingGroup.chargesInputImages` 自此不看单位：规格模式三种单位与按次都收，
  按 token 不收（`SpecUsage.price` 保留「零交付不收」；按次行只写输入三列，`SpecUsage.inputsOnly` /
  `LLMService.requestInputBilling`，输出四列留空，`costParts.request` 分支带 `spec.inputCost`）。
  **xAI 视频面的报价只在终态轮询里**（`api/usage.md` §5）：`xaiVideoPollEnvelope` 的 done 分支把 `video.duration`
  作 `renderedSeconds`、`usage.cost_in_usd_ticks` 经同一个 `reportedCostFromTicks` 作 `videoDoneEnvelope(reportedCost:)`
  发布在信封顶层的 `reported_cost_usd` 下；执行器只要两者任一在就调 `settleVideoUsage`，它是**两段独立的尽力而为**：
  规格模式按秒重写输出四列（`updateSpecBilling`，输入三列不碰），报价在任何模式下经
  `UsageRepository.updateReportedCost` **只写 `reported_cost` 一列**——提交行的档位估算从此被压过（D2d 口径），
  快照仍在行上。**新增一个视频协议时必须在 `VideoSubmission` 里报张数**，否则该协议上的视频输入费静默记 0。
- **流式出图（2026-09-18 补）**：只在方舟自家渠道、且表上 `streamsImages` 为真（5.0 lite ·
  4.5 · 4.0）时，`generateStream` 走 `ArkImagesProtocol.generateImageStream`——发
  `stream: true`，每个 `partial_succeeded` 下载后作为一个 `imagePart` 推出，`partial_failed`
  只记一张失败，`completed` 带 `usage`，收尾的 metadata 与同步路径同形。这条路由
  `streamIsSingleShot` 为假，但仍然**提交即计费**。空闲守卫按「一张图」计：
  `imageStreamChunkGap` = 单图期限（5 分钟），首块、后续块都用它，首块超时算期限不重试
  （聊天的 120 s 空闲守卫会在 4K 图还在画时把它丢掉）。协议对 `stream` 请求回来的
  JSON（参数错误的 400 都是这样回的）走同步读法；200 时是 SSE 还是 JSON 看 body 首行，不看
  `Content-Type`（流式回答的真实头没抓到过，误读会丢掉已计费的一整组）。中转、5.0 pro 照旧同步：中转是否透传
  SSE 未知，拒收 `stream` 的中转会把能用的渠道变成 400。执行器在流式路径上**边到边存**，
  后面失败或取消时，已落盘的图保留，`LLMService.requestStream` 也照已送达的张数记用量
  （review 发现：原先只在流跑完时记）。
  踩过的坑：`partial_failed` 事件里有 `error` 对象，通用的信封检查会把它当成整个请求失败
  ——只对不认识的事件做信封检查。测试：`seedream_routing_test`「live image stream」、
  `image_stream_save_test`（第一张在流还开着时就已落盘）。
- **拆图层落库与画布还原（2026-09-18 补，设计 `A7`）**：每张图的叠放信息是**类型化字段**，
  不进 `metadata`——`GeneratedImageLayer`（`z_index` · `name` · `description` · `box`，框是
  **底图像素**）在 `LLMResponse.imageLayers` 里与 `generatedImages` 按位置一一对齐，在流上与
  `imagePart` 同一个 chunk（`LLMResponseChunk.imageLayer`）。`metadata` 跨 chunk 合并，放进去就丢了对齐。
  方舟协议因此**逐项下载**，不走 `resolveImageRefs`（它跳过下载失败的项，后面每张都会错位）。
  执行器存图后写 `image_layers`（v46，按文件路径为主键，同一次响应一个 `set_id`），写失败只记日志、
  不丢图。应用内的改名 / 移动（改名对话框、AI 重命名、文件与文件夹搬运）调
  `ImageLayerRepository.move` 带着行走；它先查内存索引 `layeredPaths`，与图层无关的文件不碰库。
  画布（`screens/workbench/widgets/layers/`）按框把每层拉伸放回底图坐标系，逐层显隐、点选描框，
  「导出合成图」由 `LayerCompositeService` 在 isolate 里按底图分辨率合成可见层，存到底图旁。
  入口：图片卡右上角铭牌角标、右键菜单一行「打开图层」。不做：拖动 / 缩放 / 重排单层、显隐持久化。
  测试：`image_layer_store_test`（仓库、改名跟随、任务端到端）、`layer_canvas_test`（按框定位、
  显隐、点选、合成像素）、`seedream_routing_test`「a decomposition keeps each image paired」；
  截图 `workbench_*_layerCanvas`、`workbench_desktop_light_layerBadge`。
- 按规格计费的条件选单顺带收了 `ModelCapabilities.idRoutedTables`（按 id 才走到的表），
  `1.5K` 这类小数档位能选能排。
- **测试**：`seedream_capabilities_test`（分类、每表、像素落在各版本文档区间）、
  `ark_images_payload_test`（body 逐字段、组图收紧、任务前置条件、单张失败、图层排序）、
  `seedream_routing_test`（菜单 / auto / 点单 / 超时 / 本地 HTTP 端到端）、
  `ark_channel_preset_test`。截图：`models_desktop_light_wizardArk{,2}`、
  `workbench_desktop_*_seedream{Pro,Lite}`。
- **没做**：Seedance 视频面——记在台账「还欠的」。
  方舟 chat 面的 `thinking` 方言实测不需要（标准 `reasoning_effort` 即可，`api/volcengine-ark.md` §7.1）。

## 遗留与已知取舍

- 模型 family 的**默认值**仍由 modelId 字符串规则推断（`model_family.dart`）。
  中转乱起名的问题已由"模型类型声明 + 多媒体协议点单"解决（见上文「模型类型
  声明与多媒体协议点单」一节）；未点单、类型与 id 一致的模型仍逐位按 id 路由。
- `state/app_state_workbench.dart` 用 family 名做参数记忆的命名空间 ——
  现在读的是 `AppState.descriptorForModel(model).family`（按渠道所服务的形态），
  未点单模型的键与改动前相同，存量参数记忆不丢。`discovery_dialog` 用
  `inferTag` 自动打标，是 UI 对 Layer 3 的合法只读消费。
- dispatcher 的图像/视频分支仍按 descriptor 的 family 分派，点单靠
  "从协议反推 family"（`ModelDescriptor.of(id, servedBy:)`）打通，分支本身没改。
  改成按 effective 协议直接 switch 更干净，但要重写 generate / generateStream /
  startLongRunning / generateTimeout / streamSupportsTools 五处，留作后续。
- 协议文件里保留了 `AppState().enableApiDebug` 的调试日志钩子
  （历史模式，未在本轮改动）。

## 旧路径对照（读重构前的历史文档/报告用）

| 重构前（已删除） | 现在 |
|----------------|------|
| `llm/providers/openai_api_provider.dart` | 按 surface 拆为 `protocols/openai_chat_protocol.dart` · `openai_images_protocol.dart` · `openai_videos_protocol.dart` · `xai_images_protocol.dart` · `xai_videos_protocol.dart` |
| `llm/providers/google_genai_provider.dart` | `protocols/gemini_chat_protocol.dart` · `gemini_imagen_protocol.dart` · `gemini_veo_protocol.dart`（discovery 在 gemini_chat 文件内） |
| `llm/providers/google_payload.dart` | `protocols/gemini_payload.dart`（内容基本原样） |
| `llm/providers/google_auth.dart` | `vendors/vendor_profile.dart`（`headers()` / `decorateUrl()` / `redactUrl`） |
| `llm/providers/midjourney_proxy_provider.dart` | `protocols/midjourney_protocol.dart` |
| `llm/channel_dialect.dart` | `vendors/vendors.dart`（id 常量）+ `VendorProfile`（语义） |
| `llm/llm_provider_interface.dart`（`ILLMProvider`） | `protocols/protocol.dart`（能力接口）+ `llm_dispatcher.dart`（路由） |
| `llm_models.type` 数据库列 | 已删除（v32）；运行时 `channel.type → Vendors.byId → family` |
| `main.dart` 的 `registerProvider(...)` 注册 | 不存在；dispatcher 静态持有协议实例 |
