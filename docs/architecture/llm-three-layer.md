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
| **1 Protocol** | 线上格式长什么样：endpoint 形状、请求体、响应/流解析 | `protocols/` — openai_chat · openai_images · openai_videos · xai_images · xai_videos · gemini_chat · gemini_imagen · gemini_veo · anthropic_chat · midjourney · dashscope_chat · dashscope_images · dashscope_images_async · dashscope_video |
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

> 完整设计与取舍见
> [`docs/plans/2026-08-vendor-protocol-model-refactor.md`](../plans/2026-08-vendor-protocol-model-refactor.md)；
> 协议事实见 [`docs/api/qianwen-bailian.md`](../api/qianwen-bailian.md)
> 与 [`docs/api/minimax.md`](../api/minimax.md)。

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
- **单点查询**：菜单/失效判定只经 `LLMDispatcher.protocolMenuFor` /
  `isStaleProtocolSelection` / `surfaceForModel`（UI 与路由共用，static）。
  `wire_protocol` 列只由 `LLMConfigResolver` 读取。
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
  （v38 的 `operation_name` / `operation_surface` 列）；此后每一轮
  `checkOperation` / `cancelOperation` 带回 `surfaceId`，dispatcher 经
  `_videoJobProtocolFor`（`_nativeVideoProtocol` 的超集，补上两个从不被声明
  的家族默认面 ①/`veo`）直达当初的面。任务比启动它的配置活得久：渠道中途
  被改指到别家 vendor，轮询也不会再送进陌生的状态词表。`video_` 前缀守卫
  仍在家族分支里，作为 v38 之前旧行与无佐证调用方的兜底；cancel 在佐证面
  没有取消能力时回答 null，**绝不**回落到渠道当前声明的面。
- **`test/wire_protocol_routing_test.dart`** 钉住"重构前存在的每个
  (vendor, model) 组合仍解析到同一条路"；
  `test/dashscope_chat_payload_test.dart` 钉住私有 chat 面的线上规则
  （三段式分区、`result_format`、增量、多模态 content 形状）；
  `test/minimax_payload_test.dart` 钉住 MiniMax 两条私有面的 body 规则与
  base 推导 —— 其中媒体项的嵌套形状、`metadata` 计数的字符串类型两条，都是
  "写错了上游不报错、照常出片并计费"的那种，所以按上游样例逐字断言。

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
  → LLMConfigResolver: DB 查 model 行 + channel 行 + 计费组 → LLMModelConfig
  → LLMDispatcher.generate(config, ...)
      vendor = Vendors.byId(config.channelType)      // Layer 2
      model  = ModelDescriptor.of(config.modelId)    // Layer 3
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
- **新增模型能力**：只动 Layer 3（`model_capabilities.dart` 的参数表、
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
它们各自对应一类踩过的静默失败（`test/llm_error_handling_test.dart` 钉住）：

- **`decodeJsonBody(response, apiName: …)`**（`protocols/protocol.dart`）——
  唯一安全的解码顺序：状态码 → JSON → 形状 → 错误信封。手写这四步曾让
  Gemini 把网关的 HTML 502 报成裸 `FormatException`（真实状态码永不现身）。
  异步任务的 **poll** 面传 `checkEnvelope: false`：失败的任务以
  `{status:"failed", error:{…}}` 形式装在 200 里，由 poll 自己的状态机报错
  （带上 operation 名），通用信封检查会先一步抢走并丢掉这个上下文。
- **`LLMApiException`**（`llm_types.dart`）—— 非 2xx 与信封错误一律抛它。
  `LLMService.isRetryable` 读它的 `statusCode` 决定重试（仅 5xx/429）；
  抛裸 `Exception` 的老路径靠一条锚定 `failed: <status>` 的 legacy 正则兜底，
  新代码不许依赖它。
- **`sseDataPayload(line)`** —— SSE 行解析（`data:` 后空格可选、注释行、
  `[DONE]`）。调用前自行跳过 `event:` 行；解析失败的行**忽略**，不许把
  `FormatException` 重抛成整条流的死刑（gemini 踩过，见
  `geminiChunksFromSseLine` 的 dartdoc）。
- **`redactUrl(url)`**（经 `protocol.dart` 转出口）—— 任何写进 debug 日志的
  请求 URL 必须先过它：Google 系 vendor 的 URL 带 `?key=`，靠日志落盘层的
  正则兜底等于把一个机制的 bug 变成凭证泄漏。
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
  响应 200 一切正常。`test/image_relay_compat_test.dart` 遍历整个 payload
  断言没有带下划线的结构键，新字段写成 snake 会在那里先挂。
- **`VendorProfile.downloadHeaders(apiKey)`** —— 下载生成产物（视频/图片 URI）
  时用什么认证头是 Layer 2 知识，executor 只消费；按协议族分支写在调用方
  曾是红线违规（错头会被静默忽略，下一个非 bearer vendor 只会得到一个 403）。
- **`VideoJobProtocol.poll` / dispatcher `checkOperation` 的返回契约**是
  Veo 信封（`{name, done, response|progress}`），四个家族一致 —— 包括 MJ
  分支（dispatcher 内翻译）。唯一豁免：`gemini_veo` 的 poll 返回原始
  operation JSON 里的 `{done, error}` 由 executor 消费，注释已说明。

## ④ Anthropic 的六条不变量（会静默错，不会报错）

协议事实见 [`docs/api/landscape.md`](../api/landscape.md) §5；这里只记本项目
踩得到、且**不会以报错形式暴露**的六条。前四条是接入时就有的，后两条随
thinking / server tool 一起加。

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
   `test/anthropic_chat_test.dart` 逐条钉住。

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
6. **server tool 不是 tool call。** `web_search_20250305` 由服务端自己执行、
   自己回答，响应里的 `server_tool_use` + `web_search_tool_result` 是**已完成的
   事实**。把它当 `LLMToolCall` 交给 agent 循环，等于让本地去跑一个没人要求的
   工具，再去回答一个模型从没发起的调用。所以它们进 `serverToolRuns`，来源写进
   metadata 的 `server_tool_runs` 并打一条 INFO 日志（用户在为它付费，且答案建
   立在这个 App 没有选择过的网页上）。
   连带的一条：开了 server tool 之后一轮里会出现**多个 text block**（搜索前一
   段、搜索后一段），所以 block 之间按空行拼接，不是裸接 —— 裸接会把两段话连成
   一句。

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
`openai_chat_protocol.dart`，和 `contentToText` / `resolveToolCallId` 一样属于
①-shaped 的公共件）。**C2 复用同一个类** —— DashScope 私有面的 `tool_calls` 就
是 ① 的拼法。三条不变量：

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
传；同时一条渠道下"支持思考的模型"和"发了就 400 的模型"可以分别设置。UI 只在
④ 渠道下显示这两个开关。

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

## 遗留与已知取舍

- 模型 family 仍由 modelId 字符串规则推断（`model_family.dart`），
  第三方中转乱起名仍可能误判 —— 这是本轮"只理结构、不做增强"刻意保留的。
  将来若要改成"路由看配置"，改动点只有 Layer 3 的 `ModelDescriptor.of`。
- `state/app_state_workbench.dart` 用 family 名做参数记忆的命名空间，
  `discovery_dialog` 用 `inferTag` 自动打标 —— 都是 UI 对 Layer 3 的
  合法只读消费。
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
