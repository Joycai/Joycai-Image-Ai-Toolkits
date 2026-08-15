# AI 能力实现审查报告（2026-08）

**审查基准**：[docs/ai-agent-playbook/](../ai-agent-playbook/README.md)（README + 01~12，六条贯穿性原则 + 52 条坑清单）
**审查范围**：协议层 `lib/services/llm/`（全部 25 个文件）+ Agent 体系（`prompt_optimizer_agent.dart`、`ai_rename_agent.dart`、`context_budget.dart`、`knowledge_base_service.dart`、task executor 中的 agent 调用方）
**方法**：三路并行探索（playbook 规范提炼 / 协议层现状 / Agent 与上下文现状）→ 逐条人工读代码核实行号与语义 → 按「违反 / 真 bug / 合理取舍」三分归类。所有条目均标注对应 playbook 编号（Gx=贯穿原则，Px=坑清单，数字=主题篇条目）。

---

## 1. 总评

本项目的 AI 层整体成熟度高于 playbook 所警示的大多数反面案例：三层架构（协议/vendor/模型）的层间收窄、tool-call 配对纪律、写入审批安全这三块不是模板代码，而是与 playbook 同源的「踩坑后写回去」的实现，多处不变量有 dartdoc 论证和测试钉住。

审查发现的问题集中在四处：

1. **Gemini 路径是三个协议族中最旧的一条**，没有跟上 openai/anthropic 已完成的两轮加固（共享 SSE helper、状态码优先、`is Map` 保护、空结果抛错）。本报告确认的高严重度 bug 几乎全部落在这里（§3 B1–B4）。
2. **纪律执行有 5 处漏网**，其中硬编码 Bearer 和 setup wizard 的 id 嗅探直接违反项目自己在 [llm-three-layer.md](../architecture/llm-three-layer.md) 写明的红线（§4）。
3. **计费有系统性遗漏**：Imagen 与全部视频生成（Veo/Sora/xAI）不产生任何 usage 记录（§3 B4）。
4. **与 playbook 的最大结构性差距**在 Agent 体系：无子代理/任务工作区、无结构化输出降级链、无能力探测、prompt cache 零考虑（且 elide 机制每轮击穿隐式前缀缓存）。这些是设计缺口而非 bug，按路线建议列出（§5）。

---

## 2. 符合项（与 playbook 对齐的部分，审查时确认不应改动）

| 实现 | 位置 | 对应 playbook |
| --- | --- | --- |
| `LLMTarget` 把 vendor 收窄为 `headers()`/`decorateUrl()` 两个出口，协议层拿不到 `vendor.id` | `protocols/protocol.dart:24-39` | G1、G5 |
| dispatcher 单点路由，4 个穷尽 switch 全按 `vendor.family` 一级分支；`vendor.id ==` 全仓 0 处 | `llm_dispatcher.dart` | 1.9 红线 |
| 供应商是数据行：`VendorProfile` 仅 5 个字段，12 个 profile 全声明式；`decorateUrl` 穷尽 switch 防止新 auth scheme 继承 `?key=` 约定 | `vendors/vendor_profile.dart:93-180` | G1、2.26 |
| `ChatProtocol.generateStream` 签名级禁止流式工具调用（注释写明 arguments 跨 chunk 分片、index 才是分组键的理由） | `protocols/protocol.dart:44-72` | 2.10、P10 |
| 跨轮回传原物整存：①族按 `reasoningFieldName` 原名奉还、③族 `thoughtSignature` 逐 part 回传、④族 thinking block+signature 整块回传且排在 text/tool_use 之前、无签名则不发 | `openai_chat_protocol.dart:770-773`、`gemini_payload.dart:310-318`、`anthropic_chat_protocol.dart:102-128` | **G3**、3.23-3.27、P1、P3 |
| 只在带 tool_calls 的 assistant 轮携带 reasoning 回传 | 同上 | 3.26 |
| Anthropic usage 三桶求和后以 inclusive `prompt_tokens` 发布；`_extractCacheTokens` 三家 key 归一化且 clamp 防负数 | `anthropic_chat_protocol.dart:401-432`、`llm_service.dart:294-309` | 6.1-6.3、P16 |
| 「200 但空响应必须抛」贯彻 openai / anthropic / gemini_chat 同步路径三处 | `openai_chat_protocol.dart:379-386`、`anthropic_chat_protocol.dart:508-514`、`gemini_chat_protocol.dart:73-83` | 6.14、P6 |
| `throwIfEnvelopeError` 双错误通道（`error` + MiniMax `base_resp`），流式路径特意放在宽容 try 之外 | `protocols/protocol.dart:137-151` | 6.9-6.10、P6 |
| `<think>` 跨 chunk 状态机（`_partialTagSuffix` 最长前缀回退），切出的思考不回传 | `openai_chat_protocol.dart:171-222` | 3.30-3.33、P13 |
| 交替律修补：连续同角色合并、tool 结果并入 user 消息、空 turn 不发、空 tool 输出补 `'(no output)'` | `anthropic_chat_protocol.dart:67-139` | 2.1、5.13 |
| 「没报 usage」区别于「0」（`promptTokensOf` 返回 null） | `llm_service.dart:319-333` | P8 |
| Agent「出散文即完成」唯一终止判据 | `prompt_optimizer_agent.dart:1117` | 7.16 |
| tool-call 配对三路补桩（异常→error 结果、取消→cancelled 桩、未知工具→error），批内取消仍逐个配平后才 return | `prompt_optimizer_agent.dart:1178-1260` | **G6**、7.19-7.21、P17 |
| `ask_user` 单独成批铁轨（`canStageAskUser`）+ 悬空自愈（`_cancelDanglingAskUser`/`_pairDanglingAskUser` 相邻性二次检查） | `prompt_optimizer_agent.dart:2099-2176` | 5.12、G6 |
| 写入安全：`write_knowledge_file` 纯 staging 从不落盘、UI Apply 审批、read-before-write 铁轨（elide 掉的读取不再授权写入）、写后 `knowledgeStaleAt` 失效 | `prompt_optimizer_agent.dart:1882-1922、2044-2077` | 7.3、8.23 |
| 上下文三层：elide（无损、保留全部 reasoning 载体字段）/ compact（失败回退硬截断、不动原历史）/ read cap（per-call 重算而非 per-turn） | `prompt_optimizer_agent.dart:1583-1745`、`context_budget.dart` | 10.45-10.57、P45 |
| `context_window` tri-state 单点解码（null/≤0/>0），unlimited 用常量防 `0 × ratio == 0` | `context_budget.dart:108-110` | 类比 1.27 |
| charsPerToken 事后校准（clamp [0.5,6.0]），中文知识库不再按英文估值溢出 | `context_budget.dart:63-69` | 6.38 精神 |
| 「从历史推导而非 Set 追踪」liveness（`_liveReadPages`/`_liveViewedPaths`/`pendingAskUser`），架构文档记录了 Set 模式的死锁教训 | `prompt_optimizer_agent.dart:1513-1572` | 与 10.51「按对象身份不按索引」同源 |
| KB 路径安全：绝对路径拒绝、隐藏段拒绝、符号链接解析后二次包含检查、深度上限防环 | `knowledge_base_service.dart:98-149、203` | 8.13、P26 |
| ④ server tool 只读上报不配对回复，孤儿 result 保留不炸 | `anthropic_chat_protocol.dart:341-369` | 5.15-5.16、5.21 |

---

## 3. 确认的 bug（按严重度排序）

每条格式：现象 → 位置 → playbook 对应 → 修复方向。行号均经人工核实（2026-08-15，main @ 6a4920d）。

### B1 · Gemini 流式解析会被任何非 JSON SSE 行整条打断【高】

[gemini_chat_protocol.dart:178-197](../../lib/services/llm/protocols/gemini_chat_protocol.dart)

```dart
String dataLine = line;
if (line.startsWith('data: ')) {   // 只认带空格的拼写
  dataLine = line.substring(6);
}
try {
  final chunkData = jsonDecode(dataLine);
  ...
} catch (e) {
  if (e is Exception) rethrow;      // FormatException implements Exception
  // Ignore parse errors for empty/non-json lines
}
```

两个叠加的问题：

1. **没有使用共享的 `sseDataPayload`**（[protocol.dart:170-181](../../lib/services/llm/protocols/protocol.dart)）。该 helper 存在的全部理由（其 dartdoc 原文）就是「`data:` 后的空格在 SSE 语法里是可选的」——中继发 `data:{...}` 时这条路径会把整行（含 `data:` 前缀）拿去 jsonDecode。
2. **catch 分支与注释语义相反**：`jsonDecode` 抛的 `FormatException` 实现了 `Exception`，会被 `rethrow` 而不是被忽略。于是无空格的 `data:{...}`、keep-alive 注释行（`:`）、中继补发的 `data: [DONE]`、裸 `event:` 行——任何一个都会**终止整条流并报错**，而注释声称要忽略它们。

openai（`sseDataPayload` + 宽容 try）和 anthropic（类型化事件）路径都已修对，这是同类问题在 gemini 路径的漏网。

- **playbook**：2.9/2.11（malformed SSE 行直接忽略）、P11 精神、12.2「第一天就要有的三样」之一
- **修复方向**：改用 `sseDataPayload`（先跳过 `event:` 行），catch 只 rethrow 由错误信封分支主动抛出的异常（例如改为先解析、解析成功后再在 try 外检查 error），与 openai 路径对齐。

### B2 · Gemini 三个协议先 jsonDecode 再判状态码；error 检查无 `is Map` 保护【高】

[gemini_chat_protocol.dart:56-69](../../lib/services/llm/protocols/gemini_chat_protocol.dart)、[gemini_imagen_protocol.dart:64-74](../../lib/services/llm/protocols/gemini_imagen_protocol.dart)、[gemini_veo_protocol.dart:67-77](../../lib/services/llm/protocols/gemini_veo_protocol.dart)

三处的顺序都是 `jsonDecode(response.body)` → `data['error']` → `statusCode != 200`。后果：

- 网关/CDN 返回 HTML 502 时，用户看到的是 `FormatException: Unexpected character`，**真实状态码永远不出现在错误里**，`_isRetryable` 也无法识别为 5xx 可重试。
- `data['error']` 在 `data` 不是 Map（如 JSON 数组或裸值）时直接 `NoSuchMethodError`。openai/anthropic 路径都是先判状态码、且有 `is Map` 保护，顺序相反。

- **playbook**：6.34（错误判定读「回话的形状」，HTML/非 JSON body 意味着 base URL 指向了不是 API 的东西）、6.15（错误消息带上实际 URL/状态码）
- **修复方向**：与 openai 对齐——先判状态码（非 200 时把状态码+body 摘要放进异常），200 再 decode，decode 前后加形状保护。

### B3 · Imagen 零图片静默成功【高】

[gemini_imagen_protocol.dart:76-90](../../lib/services/llm/protocols/gemini_imagen_protocol.dart)：`predictions` 为 null、为空、或全部 base64 解码失败时，返回 `LLMResponse(text:'', generatedImages:[], metadata:{})`——一次「成功但什么都没有」。这正是 [openai_images_protocol.dart:160-168](../../lib/services/llm/protocols/openai_images_protocol.dart) 与 [xai_images_protocol.dart:137-140](../../lib/services/llm/protocols/xai_images_protocol.dart) 显式修掉的模式（xai 的注释还点名了 moderation 过滤场景），Imagen 是漏网的第三个。

- **playbook**：6.14（「200 且没有任何内容」当可疑而非成功）、P6 推论
- **修复方向**：`images.isEmpty` 时抛异常并附 body 摘要，与另外两个 images 协议一致。

### B4 · 计费系统性遗漏：Imagen 与全部视频生成不记账【高】

两处叠加：

1. `LLMService` 只在 `metadata.isNotEmpty` 时调 `_recordUsage`（[llm_service.dart:98,125,235](../../lib/services/llm/llm_service.dart)），而 Imagen 恒返回 `metadata: {}`（B3 同一行）——**Imagen 请求连 request-count 计费都不落库**。
2. `startLongRunning` / `checkOperation`（[llm_service.dart:339-371](../../lib/services/llm/llm_service.dart)）完全不经过 `_recordUsage`——**所有视频生成（Veo/Sora/xAI/wan/kling）零计费记录**，metrics 页对视频消费是盲的。

- **playbook**：6.6（persistUsage 覆盖所有路径）、9.20 精神（每次运行都要有独立的 usage 行）
- **修复方向**：Imagen 至少发布 request-count 元数据（或 `_recordUsage` 改为按请求无条件记 request）；视频路径在 submit 成功时记一次 request（token 数为 0），有 usage 信息的（Sora 部分中继报）再补。

### B5 · `_isRetryable` 用错误串里第一个三位数当 HTTP 状态码【中】

[llm_service.dart:150-170](../../lib/services/llm/llm_service.dart)：

```dart
final statusCodeMatch = RegExp(r'(\d{3})').firstMatch(errorStr);
```

抓的是异常文本里**第一个**三位数字，不限定它是状态码。误判两个方向都存在：错误体里先出现 `"max_tokens": 512`、`retry after 500ms` 之类的数字会把 4xx 误判成可重试 5xx（重试是重发钱包）；真正的 5xx 若前面先出现别的三位数则不重试。

- **playbook**：6.19（只对真正的 transient 错误重试；4.11 的教训同型——判定正则必须窄，宽判定「翻倍花钱 + 掩盖真实错误」）
- **修复方向**：协议层抛错时把状态码作为结构化字段（自定义异常类型）而不是让上层从文本里捞；或至少收窄正则锚定 `failed: (\d{3})` 之类协议层实际使用的格式。

### B6 · Anthropic `redacted_thinking` 块被丢弃，不回传【中】

[anthropic_chat_protocol.dart:371-373](../../lib/services/llm/protocols/anthropic_chat_protocol.dart) 解析侧对 `redacted_thinking` 明确「nothing to show and nothing to count」——既不展示（正确）也不留存；回传侧（[:110-116](../../lib/services/llm/protocols/anthropic_chat_protocol.dart)）只重建带签名的 `thinking` 块。若一个工具调用轮同时含 `tool_use` 与 `redacted_thinking`，回传历史会缺块。

- **playbook**：3.29（redacted_thinking 必须回传，过滤条件应是「是思考类块」而非精确 type 匹配）、3.25/P1（④ 对不合法思考历史的反应是**静默剥离思考而非报错**——最危险的失败形态：thinking 悄悄失效、照常计费）
- **注**：这是「理解后重建」路线（把 thinking 拆成 `reasoningContent`/`reasoningSignature` 字段再拼回）的固有代价，playbook G3 主张的「整块留存原物」正是为了这类块。当前影响面：Anthropic 渠道 + enableThinking + 工具调用（即 Prompt Assistant 的 ④ 通道）。
- **修复方向**：在 `LLMMessage` 上增加不透明原始块载体（或至少把 redacted_thinking 的 `data` 存进 metadata 随消息持久化），回传时按原顺序还原。

### B7 · Midjourney 非流式路径必然 120 秒超时【中】

`LLMService.request` 对非流式 `generate` 施加 `.timeout(120s)`（[llm_service.dart:119](../../lib/services/llm/llm_service.dart)），而 MJ 的 `generate` 内部是最长 10 分钟的提交+轮询循环（[midjourney_protocol.dart:45-65](../../lib/services/llm/protocols/midjourney_protocol.dart)，`_maxWait = 10min`，MJ 典型耗时 30–120s）。流式路径靠进度 chunk 重置超时（协议注释明写此设计），非流式路径没有这个机制——任何以 `useStream: false` 调用 MJ 模型的路径在 120s 处稳定失败。当前主流程（批处理图像任务）走流式所以未爆发，属于埋着的地雷。

- **playbook**：6.21（超时策略要按 surface 区分；长生成合法）
- **修复方向**：dispatcher 对 MJ 的非流式调用放宽/豁免超时，或内部统一走流式再聚合。

### B8 · xai_images 缺信封错误检查与形状保护【低】

[xai_images_protocol.dart:113-147](../../lib/services/llm/protocols/xai_images_protocol.dart)：没有调 `throwIfEnvelopeError`（200 + body 错误信封会走到「no image data」的间接报错，掩盖真实原因）；`items` 元素与 `data['usage']` 均无 `is Map` 保护（对照 openai_images 同位置全部做了保护）。有零图抛错兜底，所以降为低。

- **playbook**：P6、5.21（认不出的容器形状不该抛裸异常）
- **修复方向**：decode 后先 `throwIfEnvelopeError`，遍历时 `item is Map` 过滤，usage 读取加形状判断。

### B9 · debug 日志把完整请求体（含 base64 图片）原样落盘【低】

openai_chat 与 anthropic_chat 的四处 `startLog` 均传 `'body': payload` 原样（[openai_chat_protocol.dart:343,508](../../lib/services/llm/protocols/openai_chat_protocol.dart)、[anthropic_chat_protocol.dart:479,578](../../lib/services/llm/protocols/anthropic_chat_protocol.dart)）。带图附件的请求会把整段 base64（MB 级）写进 `api_logs/`。imagen/veo（`getSafePayload`）、MJ、xAI 都做了裁剪，chat 两族是漏网。另外 Gemini 系 14 处 `'url': url.toString()` 带 `?key=`，目前依赖 `_sanitize` 的正则兜底救回——链路正确但脆弱，不如源头 `redactUrl`（[gemini_veo_protocol.dart:41](../../lib/services/llm/protocols/gemini_veo_protocol.dart) 已示范）。

- **playbook**：6.26（base64 替占位符 + 协议无关的递归长串裁剪）、6.16/6.25（key 永不落日志）
- **修复方向**：`LLMDebugLogger._sanitize` 增加递归长字符串裁剪（>2048 字符截断），从机制上兜住所有协议，而不是逐协议手工 safe-payload。

### B10 · AiRenameAgent 批内取消不补桩（隐患）【低】

[ai_rename_agent.dart:199-208](../../lib/services/ai_rename_agent.dart)：工具批执行循环里 `if (isCancelled()) return;` 直接退出，此时带 `toolCalls` 的 assistant 消息已在 `messages` 里而结果缺失——违反配对不变量。**当前无实际危害**：`messages` 是方法内局部变量、每批丢弃、不持久化。但与 `PromptOptimizerAgent` 用 40 行注释+三条路径守住的纪律（[prompt_optimizer_agent.dart:1149-1260](../../lib/services/prompt_optimizer_agent.dart)）相反，且没有注释说明为什么这里允许——一旦有人照 optimizer 的样子给它加会话持久化，就是即刻的会话级 bug。

- **playbook**：G6、5.12（可中途退出的实现必须二选一）、P17
- **修复方向**：补桩（照抄 optimizer 的 cancelled 桩逻辑），或至少加注释声明「本历史不持久化，允许不配平」的前提。

---

## 4. 层间纪律违规

对照基准：项目自身红线（[llm-three-layer.md](../architecture/llm-three-layer.md) 的 greppable 清单）+ playbook G1/G5/1.9。

### V1 · `openai_videos_protocol.dart:50` 硬编码认证头【应修】

```dart
request.headers['Authorization'] = 'Bearer ${config.apiKey}';
```

全仓唯一绕过 `VendorProfile.headers()` 的协议代码。同文件的 poll 用的是 `target.headers()`，且 [openai_images_protocol.dart:61-68](../../lib/services/llm/protocols/openai_images_protocol.dart) 的注释正是在讲这个 bug 曾在 images 路径被修掉——这是同类问题的漏网。后果：任何非 bearer 认证的 vendor（未来接入）走 Sora 视频提交时认证错误。修复：换成 `request.headers.addAll(target.headers())`（multipart 需像 images 那样移除 Content-Type）。

### V2 · `llm_dispatcher.dart:192` model-id 嗅探【应修】

`config.modelId.startsWith('mock-')`。红线明写 `modelId.startsWith(` 只允许出现在 `model_family.dart`/`model_descriptor.dart`。修复：把 mock 判定挪进 `ModelDescriptor`（如 `isMockModel` getter），或统一走 `options['simulation']`。

### V3 · `setup_wizard.dart:499-506` id 子串嗅探【应修】

```dart
final id = selected.modelId.toLowerCase();
if (id.contains('vision') || id.contains('image')) { _modelTag = 'multimodal'; }
else if (id.contains('gemini')) { _modelTag = 'multimodal'; }
```

直接违反红线一，且 `ModelFamilyClassifier` 已有推断逻辑——这是会独立漂移的第二套规则。修复：调用 Layer 3 的既有推断（models 屏的对应逻辑），删除本地 contains 链。

### V4 · channel edit dialog 裸 vendor id 字面量【建议修】

**（2026-08 M2 核实后修订）** 初版报告称 `channel_wizard_dialog.dart` 有 15 处裸 vendor id——复核为误报：那些是 `_ProviderPreset.id`（向导自己的预设命名空间，拼写与部分 vendor id 雷同但语义无关），真正写入 `llm_channels.type` 的 `channelType` 字段已全部引用 `Vendors.*` 常量。真实违规仅 `channel_edit_dialog.dart:53` 的 `'google-genai-rest'` 一处（M2 已修）。`database_migrations.dart` 中的裸串属迁移代码冻结豁免——两条豁免均已写入红线文档。

### V5 · `task_executors.dart:459-463` 认证逻辑写在 Layer 2 之外【建议修】

视频下载按 `vendorFamily == ProtocolFamily.gemini` 选 `x-goog-api-key` vs `Bearer`。注释的理由成立（不嗅探 URL host），但「某 vendor 的资源下载用什么头」本质是 Layer 2 知识——正确归属是 `VendorProfile` 上的一个方法（如 `downloadHeaders(apiKey)`），executor 只消费。当前写法意味着未来新增非 bearer vendor 时这里会静默用错头（且注释说错头会被忽略——恰好是不会响的失败）。

### 备注（合法但值得整理）

`ModelDescriptor.isNijiVariant`（`contains('niji')`）与 `acceptsImageInput`（`contains('deepseek')`）位于允许嗅探的 Layer 3 内，不违规；但 niji 规则与 `ModelFamilyClassifier` 的规则表重复、deepseek 规则绕开规则表单独存在，把「单一规则表」拆成了三处真相源。建议收拢进 classifier/capabilities 表。

---

## 5. 能力缺口与取舍

以下是 playbook 有、本项目没有的能力。**标「取舍」的是可辩护的设计选择**（列出以便未来决策时有据可查），**标「缺口」的建议排入路线**。

### 5.1 结构化输出无降级链【缺口】

playbook 04 的方案是两级组合：强制 pseudo-tool → 收窄判据的错误回退 → JSON mode + cue。本项目全部结构化输出（`submit_prompt`/`select_images`/`rename_file`/`ask_user`）只有 pseudo-tool 一级，唯一的软降级是 web_scraper 的 nudge-once（[web_scraper_service.dart:370-379](../../lib/services/web_scraper_service.dart)）。后果：**不支持 function calling 的模型/中继在本 App 里没有任何可用路径，也没有任何诊断信号**——表现为「模型只会聊天，永远不交付」，用户无从判断是模型问题还是配置问题。最小改进：agent 循环里当模型连续 N 轮纯文本回答时，给用户一条明确的「该模型/渠道可能不支持工具调用」日志（不必先建完整降级链）。

### 5.2 ①族（OpenAI 系）无 reasoning 请求侧控制【半取舍半缺口】

`enableThinking` 只作用于 ④ 族（`anthropic_chat_protocol.dart:228-232`，UI 也只在 Anthropic 渠道显示）。①族既不发 `reasoning_effort` 也不发任何 thinking 开关——DeepSeek-R1、o 系列、经 OpenAI-compat 中继的 gemini thinking 都无法控制强度，只能吃端点默认值。playbook 03 的六档强度词汇 + 按族翻译表是现成方案。取回侧（`REASONING_CONTENT_FIELDS` 式候选字段表 + `<think>` 切分）本项目已有等价实现，缺的只是请求侧。

### 5.3 能力探测零支持【取舍，建议补最小闸】

playbook 06 的三分法：**声明 / 运行时降级 / 花钱实测**。本项目只有第一层（family 表 + id 规则 + 3 条 override），[llm-three-layer.md](../architecture/llm-three-layer.md) 的「遗留与已知取舍」承认了这点（第三方中继乱起名会误判，「只理结构、不做增强」）。这个取舍成立，但两个最便宜的探测值得单列：
- **连接测试**（playbook 6.31-6.35 providerProbe）：渠道配置界面目前没有「测一下」按钮；`/models` 探测 + 错误形状判定几乎零成本。
- **上下文窗口的发送前拦截**（playbook 1.21）：Prompt Assistant 已有字符域预算，但普通聊天/批处理路径超窗时只能吃端点报错（或更糟——本地栈静默截断，P5）。

### 5.4 无子代理 / 任务工作区【缺口（中长期）】

playbook 09/10 的核心：记忆落盘 + 单层委托 + 工具集级路由。本项目的 Prompt Assistant 把知识库通读、看图、压缩摘要、KB 编辑全部压在单 agent 主上下文里，read cap + 分页 + elide 是在**症状层**打补丁（正是 playbook 9.1 描述的病症的知识库版本）。同时缺「任务状态」这层记忆：撞 `maxTurns` 只有「停下」一个出口，无存档/断点续跑（playbook 10 的 task.md + resume seed 模式）。knowledgeEdit 模式 `baseTurns` 被抬到 24 本身就是单上下文承压的信号。若排期，playbook 的最小路径是：先做任务工作区（落盘 note + read_note），再做 delegate（knowledge-reader 子代理最对症——KB 通读的产出天然是「结论 + 路径」形态）。

### 5.5 prompt cache 零考虑，且 elide 逐轮击穿隐式缓存【缺口（省钱项）】

写入侧无任何 `cache_control` breakpoint（全仓 grep 仅命中文档）。更实质的是：**Layer 1 elide 每次请求都会改写历史前缀**（读取结果换占位、附件摘除、write 参数替换，边界随用户轮滚动）——对 OpenAI/Gemini/Anthropic 的前缀匹配式自动缓存是逐轮击穿的。playbook P46/10.50/10.58 的对策（压缩触发/目标留宽间隙、summary 紧贴 system 稳定前缀）在这里的等价物是：elide 边界只在压缩时移动、或对已 elide 的前缀保持字节稳定。长会话 + 大 system prompt（README 全文注入）场景下这是真金白银。

### 5.6 KB 写入无备份、Apply 后无回退【半取舍】

playbook 8.25-8.28「备份失败 = 写入失败」+ 备份先行。本项目的防线是审批卡 + read-before-write + 「只能新增或替换、永不销毁」的模式不变量，但用户点 Apply 后 `KnowledgeBaseService.writeFile` 直接覆盖（[knowledge_base_service.dart:246-269](../../lib/services/knowledge_base_service.dart)），无回退路径。审批制减轻了风险但没消除（陈旧预览覆盖新内容的窗口仍在，`fromStored` 的惰性化注释自己就在讲这个风险）。写前备份到 KB 根下隐藏目录是低成本补强。

### 5.7 可观测性缺口【缺口（低成本高收益）】

- **助手面板无停止按钮**：取消一个跑飞的 turn 要切到批处理页找任务（全仓 `cancelTask` 仅 task_queue_screen 调用）。
- **撞 `maxTurns` 静默**：[prompt_optimizer_agent.dart:1266](../../lib/services/prompt_optimizer_agent.dart) 只 onLog 一行（仅批处理页日志可见），transcript 无条目——用户看到的是「agent 干了一堆事然后安静地停了」。playbook 7.46：轮数中途用尽在用户看来等于「agent 拒绝干活」。
- **promptRefine 路径不发任何 `TaskEvent`**（对比 aiRename 有 textChunk）：五种事件类型对这条路径全部沉默，含 error。
- `finish_reason == 'length'` 只记日志不补救（截断的 `submit_prompt` 白烧一轮）。

### 5.8 其余工程健壮性备注

- `runTurn` 无 re-entrancy 守卫（并发保护全靠 UI `isBusy` + 队列并发上限 2；同 session 两个 promptRefine 任务同时到达会并发写同一 history）。
- 重试退避固定 2s 无抖动（playbook 6.19 线性退避已是底线）。
- KB 全部同步 IO（`readAsStringSync`/`listSync`）跑在 UI isolate。
- turn 内不落盘：24 轮 knowledgeEdit 中途崩溃丢整轮（`_syncPersistence` 只在 turn 首尾）。
- 流式路径写入 `_sessions` 的 assistant 消息不带 reasoning 字段（[llm_service.dart:104-107,241-244](../../lib/services/llm/llm_service.dart)）——当前无消费方，若未来复用该 session 做工具调用会踩 ①族 400（playbook 3.23）。

---

## 6. 整改建议（按优先级）

### P0 —— 真 bug，建议尽快修（全部是小改动）

| # | 项 | 文件 | 工作量 |
| --- | --- | --- | --- |
| 1 | Gemini 流式改用 `sseDataPayload` + 修 catch 语义（B1） | gemini_chat_protocol.dart | 小 |
| 2 | Gemini 三协议状态码优先 + `is Map` 保护（B2） | gemini_chat / gemini_imagen / gemini_veo | 小 |
| 3 | Imagen 零图抛错（B3） | gemini_imagen_protocol.dart | 极小 |
| 4 | Imagen + 视频 LRO 计费落库（B4） | llm_service.dart、gemini_imagen_protocol.dart | 中 |
| 5 | `_isRetryable` 状态码结构化（B5） | llm_service.dart + 各协议异常构造 | 中 |

P0 第 1-3 项修完后，Gemini 路径即与 openai/anthropic 同一代加固水平；建议同时为 gemini 流式补一个与 `test/openai_chat_payload_test.dart` 对应的 SSE 解析测试（无空格 `data:`、注释行、`[DONE]`、HTML 502 四个用例），防止再次掉队。

### P1 —— 纪律漏网与地雷

| # | 项 | 文件 |
| --- | --- | --- |
| 6 | 硬编码 Bearer → `target.headers()`（V1） | openai_videos_protocol.dart:50 |
| 7 | `mock-` 嗅探挪进 Layer 3（V2） | llm_dispatcher.dart:192 |
| 8 | setup wizard 嗅探改用 classifier（V3） | setup_wizard.dart:499 |
| 9 | MJ 非流式超时豁免（B7） | llm_dispatcher.dart 或 llm_service.dart |
| 10 | rename agent 补桩或注释声明前提（B10） | ai_rename_agent.dart:199 |
| 11 | debug logger 加递归长串裁剪（B9） | llm_debug_logger.dart |
| 12 | 裸 vendor id 字面量收敛为常量（V4）、下载头挪进 VendorProfile（V5） | channel_wizard_dialog.dart 等 |
| 13 | `redacted_thinking` 原物留存回传（B6） | anthropic_chat_protocol.dart、llm_types.dart |

### P2 —— 能力建设（按性价比排序，各自独立可做）

1. **可观测性三件套**（§5.7）：助手面板停止按钮、maxTurns 撞顶的 transcript 提示、promptRefine 的 TaskEvent 接线。改动小、用户感知直接。
2. **渠道「测一下」按钮**（§5.3）：providerProbe 的 `/models` + 错误形状判定，配置期把「base 填错 / key 过期 / 中继没有 /models」三类问题前置暴露。
3. **①族 reasoning 请求侧**（§5.2）：六档自有词汇 + 按族翻译，UI 复用现有 ④ 开关。
4. **结构化输出的诊断信号**（§5.1）：先做「疑似不支持工具调用」的显式提示，降级链视需求再排。
5. **KB 写前备份**（§5.6）。
6. **prompt-cache 友好的 elide/compact**（§5.5）：长会话省钱项，动 elide 边界策略，需要设计。
7. **任务工作区 → 子代理**（§5.4）：中长期，建议按 playbook 12 的依赖顺序（工作区先行，delegate 其次），首个子代理选 knowledge-reader。

---

## 附录 · 审查追溯

- 探索与核实日期：2026-08-15，基线 main @ 6a4920d。
- 报告中每条 bug/违规的行号均经人工 Read 核实原文；探索 agent 的两项原始结论在核实中被降级：`ModelDescriptor` 的 id 嗅探（位置合法，降为「规则重复」备注）、MJ 超时（触发面窄于原始描述，标为地雷而非现行 bug）。
- playbook 编号索引：Gx = README 六条贯穿性原则；数字条目 = 对应主题篇（01 分层 / 02 协议差异 / 03 reasoning / 04 结构化 / 05 工具 / 06 错误 / 07 runtime / 08 权限 / 09 子代理 / 10 上下文）；Px = 11-pitfalls 坑清单。
