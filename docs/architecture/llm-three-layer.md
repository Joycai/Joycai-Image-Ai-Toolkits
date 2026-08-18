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
| **1 Protocol** | 线上格式长什么样：endpoint 形状、请求体、响应/流解析 | `protocols/` — openai_chat · openai_images · openai_videos · xai_images · xai_videos · gemini_chat · gemini_imagen · gemini_veo · anthropic_chat · midjourney · dashscope_images |
| **2 Vendor** | 谁在提供这个格式：认证方式、是否用厂商私有 surface | `vendors/vendor_profile.dart` + `vendors/vendors.dart`（11 个 profile，id 即 `llm_channels.type`） |
| **3 Model** | 这个模型是什么：family 分类、能力、参数表 | `model_descriptor.dart`（包装 `model_family.dart` + `model_capabilities.dart`） |

协议家族（`ProtocolFamily`）有四个：`openai`（chat/completions 及其姊妹
images/videos surface）、`gemini`（`:generateContent` 及 `:predict` /
`:predictLongRunning`）、`anthropic`（`/messages`，2026-08 加入）、
`midjourney`（midjourney-proxy 的 `/mj/*`）。
xAI 的 JSON images/videos surface 是 openai 家族下由 vendor 选择的替代协议。

`anthropic` 是唯一一个只有单一 surface 的家族 —— 没有生图/视频姊妹端点，
所以 dispatcher 的四个 switch 里它都只有一条分支（两条是
`UnsupportedError`）。接入它时**没有**动 Layer 3：Claude 的 modelId 落在
`ModelFamily.other`，而 family 在这条路径上只用来在 ①/③ 内部选姊妹 surface，
④ 没有可选的。**"新增协议家族要不要动 Layer 3"的判断标准是"这个家族内部要不要
按模型分流"，不是"这个家族新不新"。**

## 分层纪律（违反会静默腐化）

1. **只有 `ModelDescriptor` 允许嗅探 modelId。**
   `ModelFamilyClassifier` / `ModelCapabilities` 是 Layer 3 的实现细节。
   协议和 vendor 拿到的是解析好的 descriptor，绝不自己 `contains('gemini')`。
2. **协议不认识 vendor。** 协议从 `LLMTarget` 拿 `headers()` / `decorateUrl()`
   做认证，此外不得出现任何 `vendor.id == ...` 分支。厂商差异要么是
   `VendorProfile` 上的声明式字段（如 `usesXaiNativeSurfaces`），要么是一个
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
  `newApiAnthropic`）。加完记得 grep 一遍 `ProtocolFamily` ——
  `app_state.dart` 里还有一个穷尽 switch 在 dispatcher 之外
  （合法：它问的是"这个渠道能不能出视频"，属于 UI 对 Layer 2 的只读消费）。
- **新增模型能力**：只动 Layer 3（`model_capabilities.dart` 的参数表、
  必要时 `model_family.dart` 的分类规则）。
- **新增任务类型**：与本层无关，见 CLAUDE.md 的 task type 扩展流程。

## 硬编码红线（code review 时直接 grep）

重构消灭的正是这些模式。任何一条重新出现，都意味着三层在被绕过 ——
review 时用下面的模式全仓库 grep 一遍即可：

| 红线模式（grep） | 为什么禁止 | 正确位置 |
|----------------|-----------|---------|
| `modelId.contains(` / `modelId.startsWith(` / `id.contains(` 出现在 `model_family.dart`、`model_capabilities.dart`、`model_descriptor.dart` 之外 | 模型分类只能有一个事实来源；散点嗅探曾导致 30+ 条规则互相踩（顺序敏感、改一处漏一处） | 加进 `ModelFamilyClassifier` 的规则表（含 `isNijiVariant` / `isTextOnlyChat` / `isMockModel` 这类具名谓词），消费方读 `ModelDescriptor.of(id)` |
| `vendor.id ==` 任何位置 | 协议一旦认识具体厂商，厂商差异就会重新散落 | `VendorProfile` 加声明式字段（参考 `usesXaiNativeSurfaces`），dispatcher 据此选协议 |
| `channelType ==` / `channel.type ==` 出现在 `vendors/`、`llm_dispatcher.dart` 之外 | 这是重构前 `isXai`/`isNewApiGemini` 散点判断的复活形态 | 语义抬升为 `Vendors.byId(...)` 后读 profile 字段 |
| UI/state 里出现 `'openai-api-rest'` 这类裸字符串字面量 | 拼错静默失效；重命名时漏改（`Vendors.byId` 对未知 id 静默回退 openAIRest，错拼永远不报错） | 引用 `Vendors.openAIRest` 等常量。**两条豁免**：`database_migrations.dart`（迁移代码按当时的字面量冻结，改成常量反而会让未来的常量重命名悄悄改写历史迁移）；`channel_wizard_dialog.dart` 的 `_ProviderPreset.id`（那是向导自己的预设命名空间，与 vendor id 拼写雷同但语义无关——真正进 `llm_channels.type` 的是 `preset.channelType` 字段，它已全部引用 `Vendors.*`） |
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

5. **thinking 有两套词表，且开了就欠一笔债。** 官方是
   `{type:"enabled", budget_tokens:N}`（N 从 `max_tokens` 里切，下限 1024，
   且必须给答案留出余量），MiniMax M3 是 `{type:"adaptive"}`。协议不许问"你是
   谁"，所以问的是 `VendorProfile.thinking`（`ThinkingDialect`）—— **Layer 2 说
   哪种方言，Layer 1 说 JSON 长什么样**。
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

流式那条路上 thinking 仍是只读的：`generateStream` 不声明工具，没有工具调用就
没有需要签名去封的重放，与 ① / ③ 对各自 reasoning 的处理一致。

两个开关都是**按模型**存的（v33 迁移的 `llm_models.enable_thinking` /
`enable_web_search`，默认关），由 `LLMConfigResolver` 解析进 `LLMModelConfig`
—— 不是请求 option。这样助手、提示词精修、AI 重命名三条路自动都认，不必各自记得
传；同时一条渠道下"支持思考的模型"和"发了就 400 的模型"可以分别设置。UI 只在
④ 渠道下显示这两个开关。

三个 ④ vendor（`anthropicRest` / `newApiAnthropic` / `minimaxAnthropic`）
除 thinking 方言外行为一致，分开还为记录供货方。**MiniMax 是唯一 base path 不是
`/v1` 的 ④ 主机**（`/anthropic/v1`，与它的 ① 端点并列），所以协议里不能有任何
地方假设版本后缀 —— 这也是它值得一个向导预设的原因：两个端点填反了只会得到一个
404，而 404 不会说是 URL 的哪一半错了。同一家厂商同时供 ① 和 ④，正是"协议族属于
渠道、不属于厂商"最直白的证据。

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
