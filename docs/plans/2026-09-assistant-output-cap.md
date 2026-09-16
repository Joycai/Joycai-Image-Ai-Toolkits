# 提示词助手输出截断：调研与优化方案

> 2026-09-16 立项，尚未施工。执行完毕后按 [台账](README.md) 的做法删除正文、
> 把结论回写到 `architecture/assistant-context.md` 与 `architecture/llm-three-layer.md`。

## 0. 结论

**截断不是一个 bug，是三件事叠在一起：**

1. **App 对 ①②③ 不发输出上限，对 ④ 发一个写死的 8192。** 上限由服务端（或中转）
   决定，用户没有任何地方能调它。④ 的 8192 是「在服 Claude 都接受的最大值」，但
   现在的 Claude 输出上限是 128K；而 thinking 一开，思考 token 与正文共用这 8192。
2. **助手的一次交付本来就大。** 实测 `submit_prompt` 单次 5.9K（④）到 8.1K（② GPT-5.6，
   含 1.2K reasoning）输出 token；`write_knowledge_file` 要发**整个文件**，蒸馏轮一条
   消息里还可能带多个文件；压缩摘要要求「原样保留最新一版提示词」。这些都贴着 8K 走。
3. **截断之后 agent 循环没有对策。** `finish_reason == 'length'` 只打一行日志，被截断
   的工具调用参数解成 `{}`，`submit_prompt` 返回「prompt 不能为空」，模型**从头再生成
   一遍**，大概率再截一遍，直到耗尽本轮 12–24 次的步数。用户看到的是错误卡，没有任何
   提示指向「输出上限」。

**方案分两条线、三期：**

- **A 线（用户想法 1）：模型级「最大输出」字段。** 一列、一条解析线、每个协议一行，
  编辑器里一个与「上下文窗口」同形的区块。这是根治：用户能把 Claude 抬到 64K、把
  中转的默认值抬起来。
- **B 线（用户想法 2）：让大输出只发生在交付那一刻，并让截断可恢复。** 五条改动，
  其中「截断变成有指向的工具结果」和「压缩摘要不再让模型重抄提示词」两条零风险、
  立刻有效；`write_knowledge_file` 的按节写入是最大的输出削减，放第三期。

## 1. 现状调研

### 1.1 四族协议对输出上限的支持

| 族 | 字段 | 必填 | 不发时的服务端默认 | 截断信号 | 思考 token 计入上限？ |
|---|---|---|---|---|---|
| ① chat/completions | `max_tokens` → **`max_completion_tokens`**（新名） | 否 | 官方 OpenAI：模型上限；DeepSeek：非思考 8K / 思考 64K；百炼、MiniMax：按模型；Ollama：`num_predict=-1` 即 10×`num_ctx`；**中转站：各自配置，不可知** | `finish_reason: length` | 是（①②④ 的 `completion_tokens` 已含 reasoning） |
| ② responses | `max_output_tokens` | 否 | 模型上限 | `incomplete_details.reason: max_output_tokens` → App 译为 `length` | 是 |
| ③ generateContent | `generationConfig.maxOutputTokens` | 否 | 模型上限（2.5 起 64K） | `MAX_TOKENS` → App 译为 `length` | **是**（2.5+ 思考默认开启，`thinkingBudget` 与正文共用该上限，官方建议降 `thinkingLevel` 而非压 `maxOutputTokens`） |
| ④ messages | `max_tokens` | **是** | 无——App 兜底 `anthropicDefaultMaxTokens = 8192` | `stop_reason: max_tokens` → `length` | 是；budget 方言下 `budget_tokens` 必须 < `max_tokens`，App 取一半 |
| C2 百炼原生 | `parameters.max_tokens` | 否 | 按模型 | `finish_reason: length` | 是 |
| ① 的 GPT-5 / o 系列 | **只收 `max_completion_tokens`**，发 `max_tokens` 直接 400 `Unsupported parameter` | | | | |

### 1.2 App 今天发什么

| 位置 | 行为 |
|---|---|
| `llm_types.dart` `requestedMaxTokens(options)` | 只读 `options['maxTokens']`；全仓唯一的设置者是渠道探针（`_probeMaxTokens`，要 1 个 token） |
| `openai_chat_payload.dart:186` | 有则发 `max_tokens`（**旧名**——这条今天只有探针会触发，所以 GPT-5 上探针实际吃到 400，被当成「协议形状的拒绝 = 已连通」，恰好无害） |
| `openai_responses_protocol.dart:187` | 有则发 `max_output_tokens` |
| `gemini_payload.dart:671` | 有则发 `maxOutputTokens` |
| `dashscope_chat_protocol.dart` `buildDashScopeChatPayload` | **完全不发** |
| `anthropic_wire.dart` `anthropicMaxTokens` | `requestedMaxTokens ?? 8192`，恒发 |
| `llm_dispatcher.dart` `_outputCap` | deadline 按 `maxTokens` → `expectedOutputTokensKey`（助手与子代理声明 8192）→ 家族默认 |
| `prompt_optimizer_agent.dart:660` | `finish_reason == 'length'` 时只 `onLog` 一行 |
| `web_scraper_service.dart:345` | `length` 时抛带提示的异常（唯一把截断说清楚的调用方，但它是下载器） |

`2026-08-assistant-timeout.md` §5.5 当时刻意没给 ①③ 发 cap，理由是「凭空加一个会对
上限更低的模型 400」——那是**固定常量**的风险，不是**用户逐模型配置**的风险。这份方案
正是把那条「没答的问题」答掉。

### 1.3 截断在代码里怎么变成错误

```
模型输出到上限
  ├─ ① 流式：finish_reason=length，tool_calls 分片半截
  │     → StreamingToolCallAccumulator.flush() → decodeToolArguments 解析失败 → {}（WARN）
  │     → submit_prompt: "The prompt argument must not be empty."（tool result）
  │     → 模型下一轮从头再写 → 再截 → …直到 maxTurns
  ├─ ① 流式：流被中转掐断、没有 finish_reason，且有半截调用
  │     → 抛 LLMApiException「stream closed without a finish_reason」→ 错误卡，本轮终止
  ├─ ④ 流式：max_tokens 时 content_block_stop 照发，input_json 半截
  │     → 同 ① 第一条（{} → 空 prompt → 重来）
  ├─ ② / ③：finish_reason 译为 length，参数同样半截 → 同上
  └─ 纯文本被截：当成一条正常 assistant 聊天写进历史，无任何标记
```

`assistant_tool_calls.dart:644` 与 `prompt_optimizer_agent.dart:660` 是两处要动的地方。

### 1.4 实测证据（本机 `api_logs/`，51 条，2026-09-16）

| 观察 | 数值 |
|---|---|
| 单次输出最大 | **8097** completion tokens（② `gpt-5.6-sol` 中转，其中 reasoning 1161，`finish_reason=tool_calls`，prompt 103K） |
| 次大 | 4242（④ `claude-opus-4-8` 中转，上限被 App 钉在 8192） |
| 出现 `length` 的次数 | 0（这批日志里没截；但 8097 已贴着常见的 8192 默认值） |
| 已出现的相邻失败 | ① 流式 `returned no content`（`completion_tokens=4`，`finish_reason=stop`）——中转把 GPT-5.6 的一次续写吞成空回复，与截断不同类，但同样落成错误卡 |

结论：输出量级是 6–8K token，任何 8K 及以下的上限都是随机截断；④ 的 8192 与 thinking
共用，是**结构上最先截的一条线**。

### 1.5 助手里的大输出点（按单次输出量排序）

| # | 输出 | 量级 | 能否避免 |
|---|---|---|---|
| 1 | `write_knowledge_file.content`——整个文件，无 patch 模式；蒸馏轮一条消息可带多个文件 | 文件大小 × 文件数（`pageSize` 8000 字符/页的文件常见 2–3 页 = 4–8K token CJK） | **能**：按节写入（B2） |
| 2 | `submit_prompt.prompt` | 6–8K token（知识库模式的结构化提示词） | 不能——这就是交付物；只能保证它是本轮**唯一**的大输出 |
| 3 | 压缩摘要（非流式）：系统提示要求「最新提交的提示词全文原样保留」 | 摘要 + 一份 6–8K 的提示词；deadline 按 4096 猜 | **能**：App 手里就有那份提示词（B3） |
| 4 | 思考 token | 模型自定；④ budget 方言下取 `max_tokens` 一半 | 调 reasoning 档位（已有）；A 线把上限抬起来即可 |
| 5 | 交付前的散文（模型先把分析/提示词写一遍再调工具） | 0–2K | **能**：系统提示（B1） |
| 6 | 子代理 note | 数百到数千 | 系统提示限长（B4） |

## 2. A 线：模型级「最大输出 token」

### 2.1 数据与解析（一条线，照 `context_window` / `wire_protocol` 的样子）

- **`llm_models.max_output_tokens INTEGER`（可空）**，v44：`_createV44Columns` 加
  `_addColumnIfNotExists`，`onCreate` 的建表语句同步加列。语义只有两态：`null` =
  不发（服务端/家族默认）、`> 0` = 发这个数。**不做「无限」态**——④ 必须发数字，
  ①②③ 的「无限」就是不发，两者在 `null` 里已经表达完。
- `LLMModel.maxOutputTokens` + `fromMap` / `toMap`；备份导入走 `_importModels` 的
  白名单（确认是按列名透传，缺列不报错）。
- `LLMConfigResolver` → `LLMModelConfig.maxOutputTokens`（原样，不解释）。
- **协议读取只经一个口**：`protocol.dart` 新增

  ```dart
  /// The output cap for this request: the caller's per-request option wins
  /// (the probe's one token), then the model's stored cap, then null —
  /// "send nothing" on ①②③, [anthropicDefaultMaxTokens] on ④.
  int? outputCapFor(LLMTarget target, Map<String, dynamic>? options) =>
      requestedMaxTokens(options) ?? target.config.maxOutputTokens;
  ```

  五个 payload builder（① chat、② responses、③ gemini、④ anthropic、C2 dashscope）
  把各自的 `requestedMaxTokens(options)` 换成它；④ 的 `anthropicMaxTokens` 变成
  `outputCapFor(...) ?? anthropicDefaultMaxTokens`，thinking budget 方言的「取一半」自动
  跟着放大。C2 补 `parameters['max_tokens']`。
- **`_outputCap`（deadline）自动受益**：`requestedMaxTokens` 之后加一级 `config.maxOutputTokens`，
  64K 的 cap 会被 `_maxChatDeadline` 夹住，没有新的风险。

### 2.2 ① 的字段名：Layer 2 声明，不在协议里猜

`max_tokens` 与 `max_completion_tokens` 是同一族内的演化，**选哪个是 vendor 知识**：

- `VendorProfile.outputCapField`（枚举 `OutputCapField.maxTokens | maxCompletionTokens`），
  默认 `maxTokens`（Ollama / LM Studio / 老中转只认旧名；llama.cpp、vLLM、New API 两个都收）。
- `Vendors.openAIRest`（官方）与 `newApiOpenAI` 声明 `maxCompletionTokens`（GPT-5 / o 系列
  拒收旧名；New API 透传两个）；DeepSeek、百炼 compatible、MiniMax 文档都写「旧名已弃用、
  仍接受」——**先保持 `maxTokens`**，等 §1 的实测清单跑过再翻。
- 不做「400 就换名重试」：thinking 方言那套学习机制是为「同一 host 两代模型互斥」准备的，
  这里 vendor 一次声明就够；多一套 400 分类器只会多一处静默错。
- 顺手修探针：它发 `maxTokens: 1` 走同一个口，官方 GPT-5 上从此不再 400。

### 2.3 与上下文预算的关系

- **不把上限并进 `ContextBudget`。** 上下文窗口是输入侧的预算，`reserveFor` 已经给回复
  留了 25%（上限 16000 字符≈8K token）的余量。输出上限是输出侧的硬 cap，两者的正确
  关系只有一条：**cap 不应大于 `window − occupied`**。本地栈（Ollama）会在 `num_predict`
  超过剩余上下文时自行截短，托管端点会 400。这条**只在编辑器里提示**（cap ≥ 上下文窗口
  时显示警告文案），不在请求层夹——夹了就是又一个静默改写。
- `preflightContextSize` 不动：它估的是输入。

### 2.4 编辑器（D2a 稿的延伸，一个区块）

放在「上下文窗口」区块正下方，同一套 `ModelEditChoiceGrid` + 输入框：

```
最大输出                                     = 64k · 预设
┌──────────┬──────────┐
│  自动     │  指定    │
└──────────┴──────────┘
[ 65536              ] tokens   ▴▾
 4k   8k   16k  32k  64k  128k          ← 六档预设 tick，同 ContextWindowSlider 的画法但单排
说明文案（随状态）：
  自动 · ①②③：「不发送上限，由服务端决定。中转站的默认值常为 4k–8k，助手的一次
        交付约 6–8k，被截断时请改为指定。」
  自动 · ④：「Anthropic 格式必须携带上限，未指定时发送 8192。思考与正文共用它。」
  指定：「同时限制思考与正文。低于 8k 时提示词助手很可能被截断。」
  指定且 ≥ 上下文窗口：警告「超过上下文窗口的部分不会生效」
  图像 / 视频 kind：整个区块隐藏（与上下文窗口的 unsetDesc 同理）
```

- 六档是输出侧的常见上限（4k 老模型 / 8k 常见默认 / 16k / 32k Qwen / 64k Gemini-Claude /
  128k GPT-5-Claude 5），不复用 `ContextWindowScale` 的九档——那是输入侧的刻度。
  刻度实现抽成 `OutputCapScale`（`services/catalogue/`，与 `context_window_scale.dart` 并列）。
- 模型卡新增一枚 mono chip：`↥ 64k`（未指定不显示，卡上已经很挤；④ 也不显示 8192——
  那是 App 的默认，不是用户的声明）。
- l10n：`outputCap` / `outputCapAuto` / `outputCapSpecify` / `outputCapAutoDesc` /
  `outputCapAutoAnthropicDesc` / `outputCapSpecifyDesc` / `outputCapExceedsWindow` /
  `outputCapChip`，四语。
- 设计稿：<https://claude.ai/artifact/Y5noFcoMjvC1VXaoSGXXvH>（Claude Design 画布，三块：
  指定态、四种状态、助手侧的截断提示）；与 D2a 的出入只有「单排六档 tick」一条，其余
  token 全部沿用「上下文窗口」区块。

### 2.5 后续（不在第一期）：发现时预填

- Anthropic `GET /v1/models` 自 2026-03 起返回 `max_tokens`（输出上限）与 `max_input_tokens`；
  OpenRouter 的 `top_provider.max_completion_tokens`；LM Studio 的 `max_context_length`。
  `model_discovery_service.dart` 拉到就写进 `max_output_tokens`（**只在列为 null 时**，
  不覆盖用户的数字）。这和 `context_window` 的「协议不告诉你」是同一个话题（usage.md §4），
  一起做。

## 3. B 线：让大输出只发生在交付那一刻，并让截断可恢复

### B0（第一期，与 A 同 PR）截断变成有指向的工具结果，不再是 `{}`

`prompt_optimizer_agent.dart:660` 的那一行日志升级为分支：

- `finish_reason == 'length'` 且本轮有 tool call → **不执行任何调用**（半截参数一个都不
  跑——`write_knowledge_file` 的半截内容进 staging 卡就是「文件被悄悄砍半」，
  `optimizer_kb_edit_card.dart:25` 的 `suspiciousShrink` 就是为它兜底的），给每个调用配
  一条 tool result：

  ```
  {"status":"error","code":"output_truncated",
   "message":"Your reply hit the output limit (N tokens) before this call was
   complete; nothing was delivered. Reply with ONLY the tool call — no prose
   before it. If the content itself cannot fit, tighten it; do not restart
   the analysis."}
  ```

  N 取 `outputCapFor` 的值，① ②③ 不发 cap 时说 `the endpoint's output limit`。
- `length` 且**没有** tool call（纯文本被截）→ 历史里的 assistant 消息照存，但聊天条目
  打 `truncated` 标记，UI 卡片尾部显示「回复被输出上限截断」+ 「去模型设置调整最大输出」
  的动作链接（`AppSnackbar`/卡片 action，走 `onExpand` 那样的注入，不让 widget 引 screen）。
- 连续两次 `output_truncated` → 结束本轮，错误卡文案指向模型设置。不让它烧完 12 轮。
- 子代理（`sub_agent_runner.dart`）同样的两条，量小，一起改。
- 钉住：`test/optimizer_truncation_test.dart`——`length`+tool call 不执行、result 形状、
  两次即停；`debugRequestOverride` 已经提供了不开 socket 的口子。

### B1（第一期）系统提示：交付前不写散文，不重抄提示词

`assistant_system_prompts.dart` 四个模式各加一句（不是新段落）：

> Keep chat text brief. Never write the prompt (or a knowledge-file's content) as
> plain text and then again inside the tool call — the tool call is the only copy.
> Think, read, then deliver in one call.

代价为零；对 GPT-5 / Claude 这类先写「分析」再调工具的模型，去掉 1–2K 的重复输出。

### B3（第一期）压缩摘要不再让模型重抄提示词

`_maybeCompact` 的系统提示要求「the LATEST submitted prompt in full」。那份提示词 App 手里
就有（`session` 的 prompt 版本条目）。改为：

- 摘要提示改成「refer to the latest submitted prompt as `[latest prompt]`, do not copy it」；
- App 把最新版本的全文接在摘要消息末尾：`summaryMarker\n<summary>\n\n[latest prompt v7]\n<全文>`。

省掉一次 6–8K 的**非流式**输出（它的 deadline 按 4096 猜，本来就是压线的），且摘要不再
可能截掉提示词的尾巴。`optimizer_compaction_test.dart` 加一条：摘要消息包含最新提示词全文
且与 staging 的版本逐字相同。

### B4（第二期）子代理 note 限长

`_kbSubAgentSystemPrompt` / `_draftSubAgentSystemPrompt` 加「findings under ~1500 words」；
父级只看 800 字符摘要，note 全文按需 `read_note` 分页，长 note 只是白花输出。

### B5（第二期）思考与上限的提示

编辑器里 reasoning 档位非默认且「最大输出」为指定时，在说明文案里带一句「思考 token 计入
此上限」。④ budget 方言的「取一半」已经在 `anthropic_thinking.dart`，无需改。

### B2（第三期）`write_knowledge_file` 按节写入

今天「无 patch 模式」是刻意的（预览卡是整文件 diff，模型必须先读再写）。按节写入不推翻
这两条，只把**线上传输的内容**从整文件缩到一节：

- 工具新增可选参数 `section`（一个 markdown 标题行，逐字）与 `mode: replace_section | append`；
  不带就是今天的整文件替换。
- 服务端拼接是确定性的：`KnowledgeBaseService.spliceSection(existing, heading, body)`——
  找到该标题到下一个同级或更高级标题之前的范围，替换；找不到 → 工具结果报错、要求整文件
  重写或改用 `append`。**拼好之后**走的仍是 `_stageKbEdit(newContent: 拼接结果)`，预览卡、
  read-before-write rail、`suspiciousShrink` 一个都不变。
- 蒸馏提示里「one file per call」补成「one call per message when a file is large」——一条
  消息里 N 个文件 = 一次生成 = 一个上限。
- 钉住：`knowledge_base_splice_test.dart`（标题层级、末节、重复标题取第一个、CRLF）。

这条是最大的输出削减（整文件 → 一节，通常 5–10×），但它改工具契约、要改四个模式的提示与
蒸馏提示，单独一期。

## 4. 分期与验收

| 期 | 内容 | 门 |
|---|---|---|
| **1** | A 线 2.1–2.4（列 / resolver / 五个 builder / vendor 字段 / 编辑器 / 卡片 / l10n）+ B0 + B1 + B3 | `flutter analyze` 零问题；`flutter test -x screenshots` 绿；新增：`test/output_cap_payload_test.dart`（五个 builder 逐字节：null 不发、数字发到正确字段、① 按 vendor 选名、④ 默认 8192 与 thinking 一半、探针仍发 1）、`test/optimizer_truncation_test.dart`、`optimizer_compaction_test.dart` 加一条；`component_gallery` 不动（无新颜色）；`model_edit_dialog` 截图看四宽度 |
| **2** | B4、B5、发现时预填（2.5） | 同上 + `model_discovery` 的预填只在 null 时写 |
| **3** | B2 按节写入 | `knowledge_base_splice_test.dart`；蒸馏与编辑模式各跑一次真实会话看预览卡 |

需要真实 key 才能定论、跑完回写 `docs/api/`：

| 条 | 判据 |
|---|---|
| 官方 OpenAI GPT-5.x 发 `max_completion_tokens` | 200 且 `completion_tokens ≤ cap` |
| DeepSeek / 百炼 compatible / MiniMax 发旧名 `max_tokens` | 是否仍 200（决定 §2.2 要不要翻声明） |
| Ollama 发 `max_tokens` = 64k、`num_ctx` 4096 | 是否静默截短（预期是），编辑器警告文案是否够用 |
| ④ 中转 `max_tokens: 65536` 非流式 | 中转是否要求流式（官方对大 cap 的非流式请求有超时风险，App 的助手路径已流式，refine/rename 非流式） |
| ③ Gemini 2.5 指定 8192 + thinking 开 | `MAX_TOKENS` 出现率是否上升（思考共用上限） |

## 5. 已否决的做法

- **给 ①③ 发一个固定的默认 cap（如 16384）。** 就是 timeout 方案否掉的那条：对上限更低的
  模型 400，且用户无处关。用户声明的数字没有这个问题。
- **在请求层把 cap 夹到 `window − occupied`。** 又一个静默改写；本地栈自己会夹，托管端点
  的 400 是可见的。编辑器提示即可。
- **续写截断的工具调用。** 四族都不支持「接着上一个 tool_use 写」；④ 4.6+ 连 assistant
  prefill 都已移除。B0 的「有指向的重试」是能做到的上限。
- **把 `submit_prompt` 拆成多段提交。** 每段都要重发全部上下文，版本模型（`promptVersions`）
  与反馈轮的「版本号」全要改；抬 cap 就够了。
- **用 `expectedOutputTokensKey` 兼任 cap。** 它是给 deadline 的、刻意不上线（dispatcher
  第 45 行的注释）；两者仍分开，只是 `_outputCap` 多读一级模型配置。
- **「无限」态。** ④ 必须发数字；①②③ 的无限就是不发，`null` 已经是它。
