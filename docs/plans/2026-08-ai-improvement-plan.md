# AI 能力改进计划与高层设计（2026-08）

**输入**：[2026-08 AI 能力审查报告](../reviews/2026-08-ai-capability-review.md)（下称「审查报告」）+ [ai-agent-playbook](../ai-agent-playbook/README.md)（下称 playbook）+ 产品决策（见 M3 前提）。
**性质**：路线计划 + 高层设计（HLD）。不含逐行实现；每个里程碑开工前按此文档拆实现任务。

---

## 0. 总览

三个里程碑，按依赖与风险排序：

| 里程碑 | 内容 | 规模 | 依赖 |
| --- | --- | --- | --- |
| **M1 · Bug 修复** | 审查报告 P0 五项 + 顺手的 P1 小项，外科手术式修复 | 小（数天） | 无 |
| **M2 · 协议层重构** | 把「加固模式」从散落的实现提炼为共享机制，Gemini 路径对齐，纪律清零 | 中（1–2 周） | M1（M1 的两个小 helper 是 M2 的种子） |
| **M3 · 知识库子代理** | delegate 工具 + 可复用子代理循环 + 笔记存储；识图留在主模型 | 大（分三期） | 与 M2 无硬依赖，M1 后即可并行 |

原则（来自 playbook 12 路线图）：每个里程碑独立交付、独立回退；每期结束 `flutter analyze` 零问题 + 新增测试钉住不变量。

---

## 1. M1 · Bug 修复排期

审查报告 §3/§6 的 P0 项，全部按「目标形态」修（即 M2 要提炼的共享 helper 在这里首次落地，避免修两遍）：

| # | 项 | 位置 | 做法 | 测试 |
| --- | --- | --- | --- | --- |
| 1 | Gemini 流式 SSE（B1） | `gemini_chat_protocol.dart:178-197` | 跳过 `event:` 行 → 改用共享 `sseDataPayload` → catch 只吞解析错误，错误信封在 try 外抛 | 新增 `test/gemini_stream_test.dart`：无空格 `data:`、注释行、`data: [DONE]`、裸 event 行四用例 |
| 2 | 状态码优先 + 形状保护（B2） | gemini_chat / imagen / veo | 新增共享 `decodeJsonBody()`（见 M2 §2.2，M1 先落最小版）并让三处 Gemini 协议接入 | HTML 502 → 报错含状态码；JSON 数组 body 不炸 |
| 3 | Imagen 零图抛错（B3） | `gemini_imagen_protocol.dart:76-90` | `images.isEmpty` → throw（附 body 摘要），对齐 openai/xai images | 空 predictions 用例 |
| 4 | 计费遗漏（B4） | `llm_service.dart` | ① Imagen 返回非空 metadata（至少 request 计数信息）；② `startLongRunning` 成功后记一行 usage（request_count=1、token 0） | usage 落库断言 |
| 5 | `_isRetryable`（B5） | `llm_service.dart:161` + 各协议 | 引入 `LLMApiException`（见 M2 §2.1）最小版：先让 Gemini/openai/anthropic 的非 200 抛结构化异常，`_isRetryable` 优先读 `statusCode`，字符串正则仅作 legacy 兜底且收窄锚定 | `retry after 500ms` 不重试；真 502 重试 |

顺手项（同 PR 或紧随）：rename agent 补桩或注释声明前提（B10）、debug logger 递归长串裁剪（B9，机制级，一处改动覆盖全协议）、MJ 非流式超时豁免（B7）。

**退出标准**：审查报告 §3 的 B1–B5 状态翻绿；`flutter analyze` 零问题；上表测试全部落仓。

---

## 2. M2 · 协议层重构 HLD

### 2.1 目标与非目标

审查结论是：协议层的**骨架是对的**（三层收窄、单点路由、配对纪律），问题在于加固模式靠「逐协议手工复制」传播，Gemini 路径掉队、xai/videos 各漏一块。所以这不是推倒重来，而是**把加固模式下沉为共享机制，让协议实现无法再漂移**。

非目标：不改三层架构本身；不改 wire 类型（`LLMMessage`/`LLMResponse`）；不动 Anthropic 路径已验证的实现（它是标杆，只往它看齐）。

### 2.2 四个共享机制（下沉到 `protocols/protocol.dart` / 新文件）

**① `LLMApiException` — 结构化错误（替代字符串捞状态码）**

```dart
class LLMApiException implements Exception {
  final int? statusCode;      // HTTP 状态码；body 内错误信封时为 null
  final String message;       // 人类可读，含 body 摘要（≤500 字符）
  final Uri? url;             // playbook 6.15：错误一律带实际请求 URL（脱敏后）
  final bool isEnvelope;      // 200 + body 错误信封
}
```

- 所有协议的非 200 与信封错误统一抛它；`throwIfEnvelopeError` 改抛它。
- `_isRetryable` 变成：`e is LLMApiException ? (5xx || 429) : (Timeout/Socket)`——彻底废掉三位数正则（B5 根治）。
- URL 入异常前过 `redactUrl`（playbook 6.16：错误消息永不带 key）。

**② `decodeJsonBody(http.Response response, {Uri? url})` — 统一响应解码**

固化「正确顺序」：先判状态码（非 2xx → `LLMApiException` 带状态码+摘要）→ `jsonDecode`（FormatException → 明确的「端点返回了非 JSON（HTML？）——base URL 可能指向了不是 API 的东西」，playbook 6.34）→ 形状保护（非 Map → 报错）→ `throwIfEnvelopeError`。**10 个协议全部迁移到它**，逐协议手写的 decode 顺序从此不存在。

**③ SSE 消费统一**：`sseDataPayload` 已存在（`protocol.dart:170`），M2 把三个流式协议（openai/gemini/anthropic）的行处理收敛为同一骨架（跳 `event:` 行 → `sseDataPayload` → 宽容 decode → 信封检查在宽容 try 之外）。openai 路径已是这个形状，gemini 在 M1 对齐，M2 补 anthropic 侧核对 + 把骨架写进 dartdoc 作为新协议模板。

**④ debug 日志机制级脱敏**：`LLMDebugLogger._sanitize` 增加协议无关的递归裁剪（任何 >2048 字符的字符串截断为 `<N chars omitted>`，playbook 6.26），废除逐协议手工 safe-payload 的必要性（已有的保留不动）。URL 落日志前统一 `redactUrl`（消除对 `_sanitize` 正则兜底的依赖）。

### 2.3 纪律清零（审查报告 §4）

| 项 | 目标形态 |
| --- | --- |
| V1 硬编码 Bearer | `openai_videos` submit 改 `request.headers.addAll(target.headers())`（照 `openai_images:61-68` 的既有修法，multipart 移除 Content-Type） |
| V2 `mock-` 嗅探 | `ModelDescriptor.isMockModel` getter，dispatcher 消费 |
| V3 wizard 嗅探 | 删除 contains 链，调用 `ModelFamilyClassifier.inferTag` |
| V4 裸 vendor id | `Vendors` 上补齐 id 常量，wizard/edit dialog 全部替换；`database_migrations.dart` 在 llm-three-layer.md 红线清单补「迁移代码冻结豁免」条款 |
| V5 下载认证头 | `VendorProfile.downloadHeaders(String apiKey)`（按 auth scheme 返回正确头），`task_executors` 消费 |
| 备注项 | `isNijiVariant`/`acceptsImageInput` 的 id 规则收拢进 classifier/capabilities 表（Layer 3 内部整理） |

完成后更新 [llm-three-layer.md](../architecture/llm-three-layer.md) 的 greppable 红线清单并全仓 grep 验证清零。

### 2.4 覆盖补齐

- `checkOperation` 对 MJ 返回原始任务 JSON、对其他家族返回 Veo 信封的契约不统一 → 统一为 Veo 信封（dispatcher 内翻译，调用方已按信封消费）。
- `redacted_thinking` 原物留存（审查 B6）：`LLMMessage` 增加不透明块载体（`List<Map> rawThinkingBlocks`，带 modelId，playbook 3.27/G3），④ 解析侧留存、回传侧按原序还原、换模型整组剥离。此项动 wire 类型持久化，放 M2 尾期单独 PR。

### 2.5 可选扩展（M2+，按需单独立项）

- **①族 reasoning 请求侧**（playbook 03 六档词汇 + 按族翻译表）：现有 `enableThinking` 布尔升级为强度档位，④ 现行为不变，①族翻译为 `reasoning_effort`。
- **渠道「测一下」按钮**（playbook 6.31-6.35）：`/models` 优先 + 错误形状判定 + compat 降级。

### 2.6 退出标准

analyze 零问题；红线 grep 清零；`test/gemini_stream_test.dart` + `decodeJsonBody` 单测 + usage 覆盖断言全绿；`docs/architecture/llm-three-layer.md` 更新（新协议接入模板指向共享机制）。

---

## 3. M3 · 知识库子代理 HLD

### 3.1 前提与产品决策

- **本项目主力模型默认多模态** → **识图（`view_image`）留在主模型**，不做 vision 子代理。这是对 playbook 09 的有意偏离（playbook 的 vision 接管前提是主模型可能纯文本），记录为本项目的决策。
- 子代理负责**知识库检索/通读**：把「读很多页 markdown、消化、给结论」这种上下文灾难型工作移出主上下文。
- 写入（`write_knowledge_file`）**永远留在主模型**：审批链（staging → Apply 卡片）与 read-before-write 铁轨都锚定在主会话，子代理是只读沙箱（playbook 9.28/9.53②）。

### 3.2 目标 / 非目标

**目标**
1. 主上下文不再被 KB 原文淹没：研究产出以「摘要 + 笔记引用」回到主对话（playbook 9.3「工作区是总线」）。
2. 研究深度与主会话剩余窗口解耦：子代理在自己的全新上下文里翻页，read cap 按**它自己的**模型窗口计算。
3. 主会话 context-exhausted 后仍能继续研究：现在 `read_knowledge_file` 被摘掉就断粮（`prompt_optimizer_agent.dart:1058`），此后 delegate 仍在。

**非目标**（playbook 9.64-9.71 逐条对齐）：不做子代理间通信、不做并行编排、不做递归委托（子代理工具集不含 delegate）、不做自定义子代理种类/自定义 system prompt、不做 fallback 链（绑定失效就报配置错误，不静默退回主模型）、写入与审批动作不进子代理。

### 3.3 架构总览

```
PromptOptimizerAgent.runTurn（主循环，不变）
   │  工具集组装（§3.6 路由）
   ├─ delegate 工具 ──→ SubAgentRunner.run（新，可复用有界 tool loop）
   │                       │  全新 2 条消息（零上下文渗透，playbook 9.53③）
   │                       │  工具：list_knowledge_files / read_knowledge_file
   │                       │  自己的 ContextBudget（子代理模型的窗口）
   │                       ▼
   │                    产出文本 ──→ AssistantNoteStore 落盘（§3.7）
   │                       │
   │  tool result ◄────────┘  {status, note: {id, title}, summary ≤800字符}
   ├─ read_note 工具 ──→ 分页读回笔记（复用 pageBoundaries）
   └─ read_knowledge_file（保留！§3.6）
```

### 3.4 `SubAgentRunner` — 可复用的有界 tool loop（新文件 `lib/services/sub_agent_runner.dart`）

从 `runTurn` 的经验提炼，但**不是**重构 `runTurn`——是一个独立的、无持久化、无 UI 耦合的小循环（playbook 9.52：子代理就是一次嵌套的 agent 调用，前提是循环可重入）：

```dart
class SubAgentResult { final String output; final bool cancelled; final int turnsUsed; }

class SubAgentRunner {
  static Future<SubAgentResult> run({
    required dynamic modelIdentifier,
    required String systemPrompt,
    required String task,                    // 现场构造的 user 消息
    required List<LLMTool> tools,
    required Map<String, dynamic> Function(LLMToolCall) executeTool,  // 同步执行器
    int maxTurns = 6,
    bool Function()? isCancelled,
    void Function(String)? onLog,            // 嵌套日志（前缀由调用方加）
    String? contextId,
  });
}
```

**不变量**（每条都有 playbook 出处，测试钉住）：
1. **配对纪律与主循环同标准**：工具异常 → error 结果；批内取消 → 剩余调用逐个补 `cancelled` 桩，配平后才返回（G6/7.19-7.21）。实现上把 `runTurn` 的补桩逻辑提炼为共享私有 helper 供两处使用，顺便解决审查 B10 指出的双标准问题（`ai_rename_agent` 后续也迁移到它）。
2. **最后一轮撤工具强制成文**（playbook 7.12 `withholdTools`）：`turn == maxTurns - 1` 时不发 tools，逼出散文交付。子代理不打扰用户，撞上限就收尾（playbook 9.58）。
3. **产出 = 最后一条纯文本回复**（本项目是同步循环，最终文本就是返回值，不存在 playbook 9.13 的 onOutputText 陷阱——但在 dartdoc 里记录这个差异，防止未来改流式时踩坑）。
4. **空产出 → 调用方收到 error 结果，不建笔记**（playbook 9.18）。
5. **取消传播**：`isCancelled` 透传主任务的取消信号；子循环取消后 `SubAgentResult.cancelled = true`，delegate 执行器返回 `{'status':'cancelled'}`——与主循环既有的取消桩语义一致（playbook 9.19 的 AbortError 语义在本项目的协作式取消模型下等价于此）。
6. **自己的上下文预算**：用子代理模型自己的 `context_window` 建 `ContextBudget`，`read_knowledge_file` 的 per-call cap 按子循环内的 occupied 重算（复用现有公式）；子循环不做 elide/compact——6 轮的循环装不满就不需要，装满即强制成文。

### 3.5 `delegate` 工具契约

进 `_knowledgeTools` 同级的新常量组（仅在子代理可用时进入工具集，§3.6）：

```json
{
  "name": "delegate",
  "description": "把一个知识库研究任务交给子代理。子代理看不到本对话的任何内容——把它需要知道的全部背景写进 task。它会自行检索并通读知识库，把完整发现存为一条笔记，返回摘要。",
  "parameters": {
    "kind":  { "enum": ["knowledge"] },
    "task":  { "type": "string" },
    "paths": { "type": "array", "items": {"type": "string"}, "description": "可选：点名要读的 KB 文件相对路径" }
  },
  "required": ["kind", "task"]
}
```

- `kind` 现在只有一个值，但保留枚举位——未来加种类（§3.10 任务拆分）= 加数据不加协议（playbook 9.6-9.7）。
- description 直接教模型「零上下文继承」（playbook 9.8）；措辞领域中性（9.9）。
- **有 paths / 无 paths 是两个 prompt 模板**，不是一个模板插空串（playbook 9.12 不变量，曾是真实 bug；用测试钉住）。
- 执行器前置校验零副作用（playbook 9.56-9.57）：kind 合法、task 非空、子代理可用（§3.8 单一判断函数）、KB 可用；任一失败 → error 结果指路，不发请求不建笔记。
- 子代理 system prompt 是代码资产（i18n 键），不可用户自定义（playbook 9.25）；内容要点：你是知识库研究员、先 list 后按需分页 read、输出结构（结论 + 依据文件路径 + 未决问题）、引用时带相对路径。
- tool result 形状（playbook 9.16-9.17）：

```json
{ "status": "ok",
  "note": { "id": 3, "title": "…" },
  "summary": "≤800 字符 —— 够判断要不要展开读，不够替代读笔记" }
```

### 3.6 能力路由 = 改工具集（playbook 9.36）

改动点即现有组装处 `prompt_optimizer_agent.dart:978-986`：

| 条件 | 工具集变化 |
| --- | --- |
| 子代理可用 且 mode ∈ {knowledgeBase, knowledgeEdit} | **追加** `delegate` + `read_note` |
| 子代理不可用 | 完全不出现（模型幻觉调用 → 既有 default 分支的 error 结果自纠，不加特例映射，playbook 9.43） |
| contextExhausted（`:1058`） | 现行为：摘 `read_knowledge_file`。新行为：摘 `read_knowledge_file`，**保留 `delegate` 与 `read_note`**——耗尽后研究能力不清零 |

**与 playbook 9.38（vision 接管）的两处有意偏离，记录进架构文档**：
1. `view_image` 不路由走（产品决策：主模型多模态）。
2. `read_knowledge_file` **不被 delegate 接管**（对齐 playbook 9.41 longread 判据：主模型定点读一小段是日常工作，接管只针对「造成上下文灾难」的通读；且 **read-before-write 铁轨锚定在主会话的活读上**——`_liveReadPages` 只认主 history 里的 `read_knowledge_file` 结果，笔记与子代理的读**不授权写入**，knowledgeEdit 模式因此必须保留主模型直读）。工具 description 分工引导：`read_knowledge_file` 注明「定点读已知文件/写前必读」，`delegate` 注明「跨文件研究、找答案、不确定读哪些时用」。

### 3.7 笔记存储 `AssistantNoteStore`

playbook 9.3「产出落盘，只回摘要+路径」的本项目形态。KB 是本地可重读的，笔记的价值是**已消化的研究结论可廉价复取**（否则复问 = 再跑一次子代理）。

- **新表** `assistant_notes(id, session_db_id → assistant_sessions ON DELETE CASCADE, slug, title, content, created_at)` + repository；随会话保留策略一起 GC（复用 `enforceRetention` 的删除路径）。
- **会话作用域**：笔记属于会话（同 playbook 10.5 chat 场景 per-session 判断）；跨重启随会话恢复——`fromStored` 重建时 delegate 调用映射为惰性 chip（笔记在 DB，`read_note` 重启后仍可读，比 kbEdit 卡片的处境好）。
- **约束**（playbook 10.29/10.33/10.35/10.36）：slug 用 Unicode 属性类清洗（`\p{L}\p{N}-`，中文标题不得坍缩）；撞名加 `-2` 后缀并在结果中告知；单笔记上限 64k 字符，**超限报错不截断**；绝不覆盖。
- **`read_note` 工具**（read）：`{note_id, page?}`，复用 `KnowledgeBaseService.pageBoundaries` 的分页（页大小 8000，页号稳定规则同 KB 读），受既有 read cap 闸门管；结果进入既有 elide 规则（>300 字符的 tool result 会被折叠——「读过即忘、随时再读」与 KB 读一致）。
- **明确不做**：笔记不授权写入（§3.6）；不做跨会话共享；不做磁盘任务工作区（本项目没有 pause/resume 需求时，SQLite 会话作用域已够——若未来做断点续跑再按 playbook 10.1-10.5 升级，两套设计兼容）。

### 3.8 配置与可用性

- 设置页新增：知识库子代理开关 + 模型选择（默认「跟随会话模型」；可绑更便宜的长上下文模型）。应用级偏好，不入项目/会话（playbook 9.29）。
- **单一可用性函数**（playbook 9.44-9.45，防「启用≠可用」双输）：

```dart
/// 唯一答案：开关开 && (跟随会话 || 绑定模型仍存在且 enabled)
static Future<bool> knowledgeDelegateAvailable(sessionModelId) …
```

  路由（§3.6）、设置页警告、transcript chip 显隐全部走它。绑定模型被删 → 不可用（设置页就地警告，不静默退回，playbook 9.46-9.47）。
- 首期默认**关**（灰度），行为可整体回退（playbook 10.40 精神）。

### 3.9 计费、日志与 UI

- **计费**：子代理每次 LLM 请求经现有 `LLMService.request` 自动落 usage（模型 id 记的是子代理模型，天然正确）。补：`options` 透传一个 usage 标签（`task: 'subagent:knowledge'`）以便 metrics 页聚合（playbook 9.20）——需要 `_recordUsage` 接受调用方 task_id，属小改。
- **transcript**：新 entry kind `subagent`（折叠卡：task 摘要 → 运行中 spinner → 完成后摘要 + 笔记 chip）；子循环的 onLog 以 `[KB 子代理]` 前缀并入任务日志。恰好落在审查 §5.7 可观测性改进的同一批 UI 工作里，建议同期做停止按钮。
- **失败呈现**：子代理 LLM 报错 → error 结果回主模型（含「可自行用 read_knowledge_file 继续」的指引，playbook 8.9 错误写成下一步动作）；不中断主 turn。

### 3.10 M3.3：`draft` kind（2026-08 定稿）

批量参考图场景的「上下文灾难」是图片本身：每张 `view_image` 都把 base64 附件塞进主
历史（估价 `_attachmentChars=2000`/张，真实成本更高）。`draft` kind 把「看一张图、
按 brief 起草」整个搬进子代理的独立上下文——**每次委托恰好一张图**，主模型只收
文字草稿并负责终审合成，主上下文可以全程不装图。

设计要点：

- **工具形状**：`delegate` 的 `kind` 枚举扩为按可用性动态组装（schema 在下发时
  构造，playbook 8.11 的拷贝注入同理）：`paths` 字段仅 knowledge 可用时出现，
  `image_id`（1-based，与 `view_image` 同一编号空间）仅 draft 可用时出现。
- **可用性（每 kind 独立前置条件，playbook 9.44）**：`knowledge` = 开关 + 知识
  模式；`draft` = 开关 + 会话有参考图 + **生效子代理模型接受图片输入**（Layer 3
  `acceptsImageInput`；绑定模型由 executor 解析时判定，跟随会话则同会话模型）。
  任一 kind 可用即挂 `delegate` + `read_note`。
- **子代理运行形状**：无工具、`maxTurns: 1` 的单发——system（draft 专用 prompt：
  先描述图中要素，再按 brief 给草稿片段，不得虚构图外内容）+ user（brief + 单图
  附件，`viewOnly` 引用类型走既有压缩通道）。产出走与 knowledge 相同的
  笔记 + ≤800 digest 收尾（`subagent:draft` usage 标签）。
- **不改的东西**：`view_image` 仍在主模型工具集（主模型想亲自看图仍然可以）；
  `forceViewAllImages` 铁轨不认草稿（该模式的语义就是主模型亲看，与委托互斥由
  用户选择）；同轮多个 delegate 顺序执行（playbook 9.63）。
- **展望（未立项）**：`longread` kind——通读单个超长 KB 文件出结构化提要。

### 3.11 分期与退出标准

| 期 | 内容 | 退出标准 |
| --- | --- | --- |
| **M3.1** | SubAgentRunner + delegate（digest-only：结果只回 ≤2000 字符摘要，暂无笔记）+ 设置开关（默认关） | Runner 单测（配对/取消桩/最后轮撤工具/空产出）；模板不变量测试（有/无 paths）；路由测试（不可用→无工具；exhausted→保留 delegate）；真机验证一次典型 KB 研究任务的主上下文占用对比 |
| **M3.2** | AssistantNoteStore + `read_note` + summary 收敛到 800 + 会话恢复 chip + usage 标签 | 笔记 CRUD/GC/恢复测试；elide 对 read_note 结果生效；`flutter test test/screenshots` 过 transcript 新卡片 |
| **M3.3** | `draft` kind（批处理拆分）——单独立项再细化 | — |

### 3.12 风险与开放问题

1. **子代理模型不支持工具调用**（审查 §5.1 的老问题在子代理复现）：子循环连续纯文本但无交付时，把最后文本当产出返回（force-text 语义天然兜住）；若首轮即散文且无任何工具调用，结果照收——研究质量差但不失败。设置页对绑定模型无诊断信号的问题记录在案，依赖 M2+ 的探测项。
2. **摘要质量**：主模型可能只看 800 字符摘要不读笔记导致引用失真。缓解：摘要模板强制含「依据文件路径」列表；不够再调。
3. **read-before-write 的交互成本**：knowledgeEdit 模式下模型可能先 delegate 研究、被写入拦截后再直读一遍目标文件（多一轮）。接受此成本——它正是铁轨在起作用；description 引导「要改哪个文件就直接 read_knowledge_file 它」。
4. **同轮多个 delegate**：顺序执行，耗时叠加且 UI 只有 spinner。M3.1 观察真实调用形态，必要时在子代理 system prompt/description 引导单次委托。

---

## 4. 执行顺序建议

```
M1（bug 修复，数天）
 ├─→ M2（协议层重构，1–2 周，含纪律清零与覆盖补齐；M2+ 可选项单独立项）
 └─→ M3.1（子代理 MVP，默认关）→ M3.2（笔记存储）→ M3.3（任务拆分，另行细化）
```

M2 与 M3 无硬依赖，可按人力并行；共同的前置只有 M1（M3 的 SubAgentRunner 会复用 M1 里为 rename agent 补桩时提炼的配对 helper）。
