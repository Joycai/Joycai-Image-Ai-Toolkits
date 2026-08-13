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
| **1 Protocol** | 线上格式长什么样：endpoint 形状、请求体、响应/流解析 | `protocols/` — openai_chat · openai_images · openai_videos · xai_images · xai_videos · gemini_chat · gemini_imagen · gemini_veo · midjourney |
| **2 Vendor** | 谁在提供这个格式：认证方式、是否用厂商私有 surface | `vendors/vendor_profile.dart` + `vendors/vendors.dart`（7 个 profile，id 即 `llm_channels.type`） |
| **3 Model** | 这个模型是什么：family 分类、能力、参数表 | `model_descriptor.dart`（包装 `model_family.dart` + `model_capabilities.dart`） |

协议家族（`ProtocolFamily`）只有三个：`openai`（chat/completions 及其姊妹
images/videos surface）、`gemini`（`:generateContent` 及 `:predict` /
`:predictLongRunning`）、`midjourney`（midjourney-proxy 的 `/mj/*`）。
xAI 的 JSON images/videos surface 是 openai 家族下由 vendor 选择的替代协议。
Anthropic `/v1/messages` 尚未实现；实现时是 Layer 1 加一个协议家族 +
Layer 2 加一个 vendor profile，其余层不动。

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
- **新增协议标准（如 Anthropic）**：`protocols/` 新建协议类实现
  `ChatProtocol` 等接口，`ProtocolFamily` 加值，dispatcher 的 switch
  补分支，再加 vendor profile。
- **新增模型能力**：只动 Layer 3（`model_capabilities.dart` 的参数表、
  必要时 `model_family.dart` 的分类规则）。
- **新增任务类型**：与本层无关，见 CLAUDE.md 的 task type 扩展流程。

## 硬编码红线（code review 时直接 grep）

重构消灭的正是这些模式。任何一条重新出现，都意味着三层在被绕过 ——
review 时用下面的模式全仓库 grep 一遍即可：

| 红线模式（grep） | 为什么禁止 | 正确位置 |
|----------------|-----------|---------|
| `modelId.contains(` / `modelId.startsWith(` / `id.contains(` 出现在 `model_family.dart`、`model_descriptor.dart` 之外 | 模型分类只能有一个事实来源；散点嗅探曾导致 30+ 条规则互相踩（顺序敏感、改一处漏一处） | 加进 `ModelFamilyClassifier` 的规则表，消费方读 `ModelDescriptor.of(id)` |
| `vendor.id ==` 任何位置 | 协议一旦认识具体厂商，厂商差异就会重新散落 | `VendorProfile` 加声明式字段（参考 `usesXaiNativeSurfaces`），dispatcher 据此选协议 |
| `channelType ==` / `channel.type ==` 出现在 `vendors/`、`llm_dispatcher.dart` 之外 | 这是重构前 `isXai`/`isNewApiGemini` 散点判断的复活形态 | 语义抬升为 `Vendors.byId(...)` 后读 profile 字段 |
| UI/state 里出现 `'openai-api-rest'` 这类裸字符串字面量 | 拼错静默失效；重命名时漏改 | 引用 `Vendors.openAIRest` 等常量 |
| `if (family == ...)` 路由分支出现在 `llm_dispatcher.dart` 和 Layer 3 之外 | 路由规则必须单点可审计 | 挪进 dispatcher 对应 switch，加注释说明规则来源 |
| 给 DB 表新增"由其他表推导出来的"列（如当年的 `llm_models.type`） | 冗余副本没有级联更新，就是 bug 面；v32 迁移专门为删它而生 | 运行时解析（`channel → vendor → protocol`），不落库 |
| 协议文件里写死某厂商的 endpoint 路径差异 | endpoint 形状属于协议，*选择哪个* endpoint 属于 vendor | 独立协议类 + vendor 覆写，由 dispatcher 组合 |

新增代码的自检口诀：**"这行代码回答的是哪一层的问题？"** ——
线上格式 → protocols/；谁在供货/怎么认证 → vendors/；这个模型是什么 → Layer 3；
选哪条路 → dispatcher。回答不出来的，先别写。

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
