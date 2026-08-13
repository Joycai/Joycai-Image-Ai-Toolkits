# API 规范实现审计

> **⚠️ 路径快照说明** — 本审计基于 2026-08-13 三层重构（PR #86）**之前**的
> 基线 commit `d03047e`：文中所有 `providers/*` 的 `file:line` 在当前代码里
> 已不存在，新旧路径对照见
> [docs/architecture/llm-three-layer.md](../architecture/llm-three-layer.md)。
> 各条发现的「验证」步骤仍然有效 —— 逻辑基本原样搬进了对应协议文件，
> 重新核对时按对照表换文件名即可。


**日期：2026-08-13** · 版本 3.14.1 · 基线 commit `d03047e`

对照 [`docs/api/`](../api/) 的协议事实知识库，逐条核对本工程 `lib/services/llm/` 的实现。
`docs/api/` 只写「业内是什么样」且明令不写 `src/` 路径；本文是它的对侧——**本工程实际怎么做的、
差在哪、怎么验证**，因此带完整的 `file:line`。

> 结论会过期。每条都附了「验证」一栏，改动前先按那一栏复核一遍，不要直接信这份快照。

---

## 结论摘要

严重度按「**会不会静默产生错误结果或错误账单**」排序，不按修复难度。

| # | 严重度 | 结论 | 状态 |
|---|---|---|---|
| 1 | 🔴 高 | 流式 usage 在 OpenAI 官方端点上必然丢失 → token 记 0 | 待修 |
| 2 | 🔴 高 | Gemini 请求体 snake/camel 混用，图片走 snake，中转上可能静默丢图 | 待实测 |
| 3 | 🔴 高 | 「HTTP 200 + 体内错误」四种形态，① 族一种都没处理 | 待修 |
| 4 | 🔴 高 | `reasoning_content` 未回传 → DeepSeek 系工具轮 400 | 待定（依赖 ④ 族决策） |
| 5 | 🔴 高 | 内联 `<think>` 思维链不剥离，会进最终产物 | 待修 |
| 6 | 🔴 高 | Google 流式的 catch 写反了，非 JSON 行会炸掉整条流 | 待修 |
| 7 | 🟡 中 | 结构化输出四档手段一档没用，无兜底解析 | 待定 |
| 8 | 🟡 中 | Gemini 思考整块未接，`thoughtsTokenCount` 不读（少算最贵的部分） | 待定 |
| 9 | 🟡 中 | `finish_reason` / `finishReason` 不进入决策 | 待修 |
| 10 | 🟡 中 | 视频：Veo 响应形状被当成跨族中间表示；LRO 轮询不看 `error` | 待定 |
| 11 | 🟡 中 | 无鉴权本地端点接不上（发空 Bearer 而非省略该头） | 待修 |
| 12 | 🔵 结构 | 协议族 / 部署 / 马甲 三个正交轴压成一个平坦字符串 | 待定 |
| 13 | 🔵 结构 | 能力 100% 靠模型名字符串匹配，discovery 的 `rawData` 从不读 | 待定 |
| 14 | 🔵 结构 | 上下文窗口三态解码在 UI 侧被手写重复了一遍 | 待修 |

---

## 覆盖面

| 协议族（[`landscape.md`](../api/landscape.md) 编号） | 本工程 | 实现位置 |
|---|---|---|
| ① OpenAI Chat Completions | ✅ | `lib/services/llm/providers/openai_api_provider.dart`（1442 行）<br>含 OpenAI 官方 / New API / xAI / **Claude 走中转** |
| ② OpenAI Responses | ❌ 未接 | — |
| ③ Google GenAI | ✅ 经典 `generateContent` | `providers/google_genai_provider.dart` + `providers/google_payload.dart`<br>未接 Interactions API |
| ④ Anthropic Messages | ❌ 未接 | 全项目 0 命中 `anthropic` / `x-api-key` / `/v1/messages` |

非对话面另有：OpenAI/xAI 图像、Sora/xAI/Veo 视频、Imagen `:predict`、Midjourney proxy。

### ④ 族的现状是一个取舍，不是遗漏

`lib/services/llm/model_family.dart:47` 把 Claude 明确归为 `ModelFamily.other`——
「通过 OpenAI 兼容中转，当作无扩展的普通聊天模型」。这是自洽的设计。

但要清楚它的代价：[`reasoning.md`](../api/reasoning.md) §3.1 那套回传规则、
[`structured.md`](../api/structured.md) 的「④ 没有 JSON 模式」、
[`usage.md`](../api/usage.md) §2.1 的三桶不重叠——在本工程里全部**不适用也无法表达**。
第 4、7、12 条的取舍都挂在「④ 族接不接」这个决策上，建议先定它。

---

## 🔴 高危

### 1. 流式 usage 在 OpenAI 官方端点上必然丢失 → token 记 0

**证据** `lib/services/llm/providers/openai_api_provider.dart:336`

```dart
final choice = chunkData['choices']?[0];   // choices 为 [] 时抛 RangeError
if (choice == null) {                      // 只兜住 null / 键缺失，兜不住 []
  if (chunkData['usage'] != null) {
    yield LLMResponseChunk(metadata: chunkData['usage']);
  }
  continue;
}
```

`stream_options.include_usage`（本工程在 `:1400-1402` 正确开启了）的最后一个 chunk
形如 `{"choices": [], "usage": {...}}`。空 list 上取 `[0]` 抛 `RangeError` →
被 `:373` 的 `catch (e) { // Ignore parse errors }` 吞掉 → usage 整个丢弃。

`:337` 的兜底只在 `choices` **键缺失**时生效。所以：

- 中转不发 `choices` 键的 → 碰巧记上
- **OpenAI 官方 → 一定记不上**

**影响**：所有走流式的 `imageProcess` 与旧版 `promptRefine` 在官方端点上 token 记 0。

**依据**：[`streaming.md`](../api/streaming.md) §1「usage 只在开了 `stream_options.include_usage`
时随最后一个 chunk 到达」。

**验证**：`enableApiDebug` 打开跑一次流式请求，看 debug 文件里最后一个非 `[DONE]` 的
`data:` 行是否含 `usage`，再查 `usage` 表有没有对应记录。

---

### 2. Gemini 请求体 snake/camel 混用，图片走的是 snake

**证据** `lib/services/llm/providers/google_payload.dart`，同一个 `prepareGooglePayload` 内两种拼法：

| 键 | 拼法 | 行 |
|---|---|---|
| `system_instruction` | **snake** | :314 |
| **`inline_data` / `mime_type`** | **snake** | :284-285 |
| `generationConfig` · `safetySettings` · `imageConfig` | camel | :309, :326-327 |
| `functionCall` · `functionResponse` · `functionDeclarations` · `thoughtSignature` | camel | :252, :272, :276, :319 |

而同一个文件里 Veo 的媒体对象又用 `mimeType`（:88-91），
[`veo.md`](../api/veo.md):69,125 的官方样例也是 camel。**一个 repo 里三种口径。**

**依据**：[`landscape.md`](../api/landscape.md) §7「第五个样本：New API 的 ③ 族端点」记的正是这条——
中继文档只写 camelCase，而**未识别的键是被忽略而不是被拒绝的**：

> 发 `inline_data` 的后果不是报错，是图片压根没到模型那里。
> ……请求成功、响应正常、模型只是看不见你发的图。

该节给出的可移植规则：**面向兼容层时，在「官方两种都收」的地方要选中继文档写的那一种。**

**影响范围**：本工程恰好有 `newapi-gemini` 通道类型（`lib/services/llm/channel_dialect.dart:30`）。
Google 官方通道无感（proto3 JSON 两种都收）。

**状态：待实测**，不宜先改。按文档规则现状是错的一侧，但这个具体中继是否真忽略 snake_case
要发一次带图请求确认。

**验证**：在一个 `newapi-gemini` 通道上发一张图 + 「描述这张图」，看模型是否真的看见了图。

---

### 3. 「HTTP 200 + 体内错误」四种形态，① 族一种都没处理

对照 [`streaming.md`](../api/streaming.md) §3：

| 失败形态 | ① `openai_api_provider.dart` | ③ `google_*` |
|---|---|---|
| §3.1 `data: {"error":…}` in 200 SSE | ❌ 无 `choices` 无 `usage` → `continue` → 流正常结束、`isDone` | ✅ `google_genai_provider.dart:224-228` |
| §3.2 `base_resp.status_code`（MiniMax） | ❌ 全项目 0 命中 `base_resp` | ❌ |
| §3.3 拦截在文本已开始之后到达 | ❌ 流式不读 `finish_reason`（见第 9 条） | ⚠️ 读了但**只打日志** `google_payload.dart:163-183`，SAFETY/RECITATION 仅 WARN，不作废已交付文本 |
| §3.4 静默截断输入 | ❌ 无发送前估算拦截 | ❌ |

**§3.1 的后果具体是**：余额不足 / 上游故障 / 内容审核 → 用户看到一次**正常的空回复**。
错误文本只在 `enableApiDebug` 开着时进 debug 文件（`:324-326`），运行时完全不可见。

**§3.4 的补充**：`ContextBudget` 那套估算只服务提示词助手与 `web_scraper_service`，
`imageProcess` / `videoGenerate` 不受任何约束。

**验证**：用一个余额耗尽或已失效的中转 key 发一次流式请求，看是报错还是返回空回复。

---

### 4. `reasoning_content` 未回传 → DeepSeek 系工具轮 400

[`reasoning.md`](../api/reasoning.md) §3 里**唯一会让请求被直接拒绝**的那条：

> 若您的代码中未正确回传 `reasoning_content`，API 会返回 400 报错。

**证据**：

- `lib/services/llm/llm_types.dart:64-123` —— `LLMToolCall` 有 `thoughtSignature`（③ 族）
  但**没有任何字段承载 ① 族的 `reasoning_content`**。协议要求在共享类型层就不可表达。
- `openai_api_provider.dart:1339-1352` —— assistant 回放分支只发 `role` / `content` / `tool_calls`。

**影响**：提示词助手正是工具循环。**DeepSeek + 助手 = 第二轮 400。**

**连带的显示问题**：收到的 `reasoning_content` 在 `:349-351` 被当作普通 `textPart` yield，
在 `lib/services/llm/llm_service.dart:70` 与正文拼进同一个 `accumulatedText`。
思考过程和答案粘在一起进最终产物。`LLMResponseChunk`（`llm_types.dart:246-254`）
没有独立的思维链通道。

**修法提示**：[`reasoning.md`](../api/reasoning.md) §3.4 给了一条可移植规则——
**收到什么字段名，就用什么字段名还回去**，比认准 `reasoning_content` 耐用；
且只在**带工具调用的 assistant 消息**上回传。

**状态：待定** —— 要在 `LLMMessage` 上加字段，与第 7、12 条一起受「④ 族接不接」影响。

**验证**：配一个 DeepSeek 思考模型跑一轮助手对话，看第二轮是否 400。

---

### 5. 内联 `<think>` 思维链不剥离

**证据**：全项目 0 命中 `<think>` 相关处理。

**依据**：[`landscape.md`](../api/landscape.md) §7 MiniMax 样本 + [`streaming.md`](../api/streaming.md) §4：

> 思维链默认内联在 `content` 里，形如 `<think>…</think>\n\n正式回答`。流式下标签也是从
> `delta.content` 分片到达的（`<thi` + `nk>` 属于正常情况）。
> 任何把 `delta.content` 直接当作正文的消费者，都会把模型的思考过程一并收下。

**影响**：MiniMax M2.x（思考关不掉）之类的中转，思维链会原样进提示词、进 AI 重命名的文件名。

**注意修法**：标签匹配**必须跨片**——`<thi` 与 `nk>` 分属两个 chunk 是正常情况。

**验证**：配一个 MiniMax M2.x 模型跑一次提示词优化，看产出的提示词里有没有 `<think>`。

---

### 6. Google 流式的 catch 写反了，非 JSON 行会炸掉整条流

**证据** `lib/services/llm/providers/google_genai_provider.dart:231-234`

```dart
} catch (e) {
  // Ignore parse errors for empty/non-json lines
  if (e is Exception) rethrow;     // ← 注释说忽略，代码说抛出
}
```

`FormatException implements Exception`，所以 `jsonDecode` 失败**一定**走 `rethrow`。
被吞掉的只有 `Error` 子类。注释与行为完全相反。

**触发条件**：任何非 JSON 的 SSE 行——注释行 `:`、`event:` / `id:` / `retry:` 字段、
keep-alive、以及 `data:{...}`（冒号后无空格，SSE 规范允许，而 `:216-218` 的
前缀剥离要求恰好 6 字符的 `data: `）。

**影响**：整条流以异常终止，已经产出的内容按失败处理。

**验证**：任一发送 SSE 注释行或 `data:` 无空格的中转，跑一次 Gemini 流式请求。

---

## 🟡 中危

### 7. 结构化输出四档手段一档没用，且无兜底解析

对照 [`structured.md`](../api/structured.md) 的四档强度（0 prompt / 1 JSON 模式 /
2 schema 严格 / 3 强制工具调用）：

| 手段 | 现状 |
|---|---|
| `tool_choice` 强制档 | ❌ 硬编码 `"auto"`（`openai_api_provider.dart:1397`），从不 `required` / 具名 |
| `toolConfig.functionCallingConfig` | ❌ 0 命中（`google_payload.dart:316-325` 只写 `functionDeclarations`） |
| `response_format` | ❌ chat 路径无。唯一命中是 `:587` 的 `'response_format': 'b64_json'`，那是 **Images API 的输出编码参数**，无关 |
| `responseMimeType` / `responseSchema` | ❌ 0 命中 |

替代做法是 system prompt 里喊——`lib/services/prompt_optimizer_agent.dart:753-756`
「This is the ONLY way to deliver a result — never paste the final prompt as plain chat text」，
在三份系统提示词里各重复一遍。

**关键缺口**：模型吐散文而不调 `submit_prompt` 时，循环直接退出、文本当聊天
（`prompt_optimizer_agent.dart:1052-1061`），**没有任何兜底从散文里抠 JSON / 抠提示词**。
`AiRenameAgent` 同理（`lib/services/ai_rename_agent.dart:181-185`）。

于是 `submit_prompt` / `rename_file` 的可靠性完全依赖模型自觉。

**修法提示**：[`structured.md`](../api/structured.md) §4 提醒强制工具调用与思考模式冲突，
且兼容层可能整个砍掉强制档（MiniMax ④ 族样本），所以「强制失败 → 退回 JSON 模式」
的降级路径不是防御性设计而是必需品；**降级后仍应带上 JSON 模式的原生参数**。
另注意 §2：`json_object` 要求上下文里出现字面量 "json"。

---

### 8. Gemini 思考整块未接，`thoughtsTokenCount` 不读

| 项 | 现状 | 依据 |
|---|---|---|
| `generationConfig.thinkingConfig`（`includeThoughts` / `thinkingBudget` / `thinkingLevel`） | ❌ 0 命中 | [`reasoning.md`](../api/reasoning.md) §1.5 |
| `part.thought` 解析 | ❌ `google_payload.dart:190-210` 只读 `text` / `inlineData` / `functionCall` / `thoughtSignature`——思考文本当正文输出 | §2 |
| **`usageMetadata.thoughtsTokenCount`** | ❌ 0 命中 | [`usage.md`](../api/usage.md) §2.2 |

**第三条是花钱的**。`usage.md` §2.2 原话：

> ③ 的 `candidatesTokenCount` **不含**思考……只读前者会把「思考 5k、回答 500」的一次请求
> 记成 500 —— 少算的正是最贵的部分。

`llm_service.dart:250` 读的正是 `candidatesTokenCount`。

同时未读：`totalTokenCount`、`toolUsePromptTokenCount`、模态明细。
① 族这边 `completion_tokens_details.reasoning_tokens` 同样 0 命中。

**注意**：`thoughtSignature` 是**已经做对了**的，见下方「做对了的」第 1 条。这一条说的是
思考的**配置与计费**，不是回传义务。

---

### 9. `finish_reason` / `finishReason` 不进入决策

| | 读了吗 | 用了吗 |
|---|---|---|
| ① 流式 | ❌ 不读 | — |
| ① 非流式 | ✅ `openai_api_provider.dart:239-240` 进 metadata | 仅 `lib/services/web_scraper_service.dart:364`（`== 'length'` → throw） |
| ③ | ✅ `google_payload.dart:163` | **只打日志**（:166-172），不进 metadata、不抛错。`MAX_TOKENS` 只有 INFO 级 |

**依据**：[`streaming.md`](../api/streaming.md) §2：

> 「达到上限」必须与「模型不听话」区分开。一个被截断的 JSON 回复和一个格式错误的 JSON
> 回复，解析时报的是同一个错，但原因和修法完全不同……结束原因是唯一能区分它们的信息。

与第 7 条叠加：结构化输出失败时无法判断该调高输出上限还是改提示词。

---

### 10. 视频：Veo 响应形状被当成跨族中间表示

**证据** `lib/services/task_executors.dart:388-397` 硬编码：

```
response['generateVideoResponse']['generatedSamples'][0]['video']['uri']
```

于是两条与 Veo 毫无关系的 API 都必须**伪造 Veo 信封**才能回到主流程：

- Sora 系：`openai_api_provider.dart:1019-1031`
- xAI 原生：`openai_api_provider.dart:1216-1228`

这是 [`landscape.md`](../api/landscape.md) 开篇「一个 adapter 换不到另一族去」的反面——
把**某一族的响应形状**当成了跨族的中间表示。加第三种视频 API 要继续伪造。

**同区域的其它问题**：

- **LRO 轮询不看 `error`**（`google_genai_provider.dart:324` 返回原始 JSON，
  `task_executors.dart:386` 只看 `done`）→ 已失败的 operation 会一直轮到 30 分钟超时。
- 进度条是假的：`task_executors.dart:368,409` 硬编码 `0.05` / `0.5`，
  provider 真实返回的 `progress`（`openai_api_provider.dart:1044,1242`）被忽略。
- 只取 `generatedSamples[0]`，多样本丢弃。

---

### 11. 无鉴权本地端点接不上

**证据** `openai_api_provider.dart:1310-1315`

```dart
Map<String, String> _getHeaders(String apiKey) {
  return {"Authorization": "Bearer $apiKey", "Content-Type": "application/json"};
}
```

无条件发送。空 key 得到字面量 `Authorization: Bearer `（尾随空格）。

**依据**：[`streaming.md`](../api/streaming.md) §4 末行——「无鉴权的本地端点：需要**省略**
`Authorization` 头，而不是发一个空 Bearer」。

**影响**：ollama / LM Studio / llama.cpp / vLLM 的默认无鉴权配置接不上。

**顺带**：本工程无 Azure OpenAI 支持（0 命中 `api-version`、无请求侧 `api-key` 头），
对应 [`landscape.md`](../api/landscape.md) §6 的部署轴。这是有意的缺口，记录备查。

---

## 🔵 结构性

### 12. 三个正交轴压成一个平坦字符串

[`docs/api/README.md`](../api/README.md)「三个正交的轴」要求把**协议族 / 部署 / 马甲**
分开。本工程 `lib/services/llm/channel_dialect.dart` 的 7 个值把三者混在一起：

| 常量 | 协议族 | 部署 | 马甲 |
|---|---|---|---|
| `openAIRest` | ① | 通用 | 官方+任意兼容 |
| `newApiOpenAI` | ① | 通用 | New API |
| `xaiApi` | ①（聊天） | 通用 | xAI（+私有视频面） |
| `googleRest` | ③ | 通用 | 第三方 |
| `officialGoogle` | ③ | **官方** | — |
| `newApiGemini` | ③ | 通用 | New API（Bearer） |
| `midjourneyProxy` | **不是对话族** | — | — |

`providerType()`（:61-65）用的是 **catch-all 默认**：一切非 Gemini / 非 MJ → `openai-api`。
**要加 ④ 族，任何 anthropic 通道类型会被静默路由到 OpenAI transport**——不报错，直接发错格式。

另：

- `lib/models/llm_channel.dart:6` 的 `type` 是无校验的自由 `String`，不是 enum。
- `lib/models/llm_model.dart:9` 的 `supportsStandard` 存了、UI 能编辑
  （`lib/widgets/models/model_edit_dialog.dart:382-383,434`）、**运行时从不读**。死字段。
- `lib/services/llm/llm_types.dart:156` 的注释只列了 3 个 dialect，实际有 7 个。已过期。

---

### 13. 能力 100% 靠模型名字符串匹配

`lib/services/llm/model_capabilities.dart`（652 行）与 `model_family.dart` 全部是对
`modelId` 的 `startsWith` / `contains` / 正则。无探测、无 API 元数据。

而 discovery 拿到的原始 payload **存了但从不读**：`DiscoveredModel.rawData`
（`lib/services/llm/model_discovery_service.dart:7`，填充于
`google_genai_provider.dart:46` 与 `openai_api_provider.dart:110`）零读取点。
Gemini 的 `supportedGenerationMethods` / `inputTokenLimit` 就在里面，被丢弃。

**依据**：[`reasoning.md`](../api/reasoning.md) §1.8——「在第三方兼容端点上模型名是自由文本，
猜代次不可靠」。[`usage.md`](../api/usage.md) §4 也把 `/v1/models` 的扩展字段列为
上下文窗口的第一信息源。

注意 `usage.md` §4 同时提醒：**测量会过期**，中继随时可能把同一个模型名路由到另一个上游，
所以任何探测结果都该带时间戳。

---

### 14. 上下文窗口三态解码在 UI 侧被手写重复了一遍

`lib/widgets/models/model_edit_dialog.dart:110-111` 手写 `cw <= 0 ? unlimited : specified`，
绕过 `ContextBudget.modeOf`（`lib/services/llm/context_budget.dart:108-110`）。

违反 [`docs/architecture/assistant-context.md`](../architecture/assistant-context.md):44
记的「`ContextBudget` 是 `context_window` 的唯一解释者」不变量。写回路径
（`model_edit_dialog.dart:438`）倒是正确调用了 `ContextBudget.store`。

纯一致性问题，当前行为等价。但这正是那份架构笔记警告的「破了不会有现象」的那类。

---

## ✅ 做对了的（改动时不要碰）

1. **`thoughtSignature` 全链路** —— 捕获（`google_payload.dart:206-207`，兼容
   `thoughtSignature` / `thought_signature` 两种拼法）→ 持久化 round-trip
   （`llm_types.dart:87-89`）→ 原样回放到同一个 `functionCall` part 上（`google_payload.dart:270-278`），
   还有测试（`test/google_payload_tool_call_test.dart`）。
   这是 [`reasoning.md`](../api/reasoning.md) §3 四条回传义务里**唯一被实现的一条**。

2. **Gemini 流式按完整响应对象处理** —— `parseGoogleChunks` 被流式与非流式复用
   （`google_genai_provider.dart:230` vs `:114`），不做 delta 拼接。
   [`streaming.md`](../api/streaming.md) §1「③ 那一列容易读错」没踩。

3. **① 族请求形状正确** —— tools 嵌套在 `function` 下（`openai_api_provider.dart:1389-1396`）、
   assistant `content: null` 显式发送而非省略字段（`:1342`，[`tools.md`](../api/tools.md) §4 明确区分）、
   `stream_options.include_usage` 已开（`:1400-1402`）、
   tool 结果用 `role:"tool"` + `tool_call_id`（`:1330-1336`）。

4. **助手 agent 的工具配对不变量守住了** —— [`tools.md`](../api/tools.md) §3
   「配对是硬要求，且违反的后果是永久的」这条：
   `prompt_optimizer_agent.dart:1080-1094` 有文档化的不变量，
   cancel 中途不 break 而是给剩余调用补 `cancelled` 结果（:1099-1104,1151-1156）、
   工具抛异常转成错误结果（:1143-1149）、
   `ask_user` 的悬空调用有自愈（`_cancelDanglingAskUser` :1874-1889）、
   `finally` 保证持久化（:1182-1190）。**本次审查里质量最高的一处。**

5. **Google 认证集中且有脱敏** —— `providers/google_auth.dart` 单一入口，含
   `newApiGemini` 的 bearer 分支、`officialGoogle` 不发 Bearer 的判断（避免被当 OAuth token 拒绝）、
   `redactUrl` 掩码 `?key=`，有测试（`test/google_auth_headers_test.dart`）。

6. **响应解析「最大宽容接收」** —— `google_payload.dart:194` 同时接受
   `inline_data` / `inlineData`。问题只在发送侧（第 2 条）。

7. **`_recoverConcatenatedJsonObjects`**（`openai_api_provider.dart:25`）—— 对中转返回
   非法 JSON tool arguments 的宽容处理，注释记了来源是「Claude-via-relay backend」。
   正是 [`landscape.md`](../api/landscape.md) §7「工具调用降级」那一行的实际应对。

8. **`ContextBudget` 的三态设计** —— `unset` / `unlimited` / `specified` 加上从 usage
   反标定 `charsPerToken`（`context_budget.dart:63-69`），与
   [`usage.md`](../api/usage.md) §4「协议不告诉你窗口，只能靠探测」是一致的。
   局限是只有助手与 `web_scraper_service` 用，`imageProcess` / `videoGenerate` 不受约束。

---

## 待实测，不宜先改

### A. Veo 媒体对象：`bytesBase64Encoded` vs `inlineData`

- 本工程发 `{"mimeType": …, "bytesBase64Encoded": …}`，
  `google_payload.dart:87` 注释称是从 AI Studio 逆向的，且写明「Google Gen API doc is wrong」。
- [`veo.md`](../api/veo.md):69,125 的官方样例是 `{"inlineData": {"mimeType", "data"}}`。

两者冲突。`:predict` / `:predictLongRunning` 系列确实惯用 `bytesBase64Encoded`
（与 `generateContent` 的 part 体系不同），所以现状**很可能是对的**，官方文档样例反而可疑。
**先测再定，别按文档改。**

### B. `newapi-gemini` 上的 snake_case 图片（第 2 条）

按 [`landscape.md`](../api/landscape.md) §7 的规则现状是错的一侧，但要发一次带图请求确认
该中继是否真的忽略 snake_case。

---

## 附：文档层杂项

- [`docs/README.md`](../README.md):13-15 的三个 API 链接是 `file:///d:/...` 的
  Windows 绝对路径，在 macOS/Linux 上打不开。同文件其余链接大多同样问题，
  只有 `architecture/assistant-context.md` 那条用了相对路径。
- `veo.md` / `gemini-api.md` / `google-api-standard.md` 没有出现在
  [`docs/api/README.md`](../api/README.md) 的索引表里，从索引上是孤立的。
  它们覆盖的**视频与图像端点**恰好是新知识库四族对照表不涉及的部分。
- [`docs/api/README.md`](../api/README.md) 末尾「相关的本项目方案文档」列出的六份
  （`provider-layering.md` / `provider-standards.md` / `reasoning-plan.md` /
  `anthropic-plan.md` / `gemini-plan.md` / `thinking-verification.md`）在本仓库**均不存在**——
  它们属于知识库的来源工程。本文可视为其中审计部分在本工程的对应物。

---

## 建议的处理顺序

1. **先修 1、6** —— 两个纯 bug，改动小、无争议、不触碰任何抽象。
2. **再实测 2 与 A** —— 两条都只需一次带图 / 带参考图的请求。
3. **然后定「④ 族接不接」** —— 第 4、7、12 条的取舍都挂在这个决策上。
   接，则 `channel_dialect` 的 catch-all 必须先改（第 12 条），
   `LLMMessage` 要加思维链承载字段（第 4 条）。
   不接，则第 4 条降级为「DeepSeek 系不可用于助手」的已知限制，写进文档即可。
4. 3、5、9、11 相互独立，可随时插入。
