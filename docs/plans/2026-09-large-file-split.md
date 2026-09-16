# 大文件拆分方案

**基线** `6e55653` 2026-09-16 v4.7.7（PR #288 合入后）· **状态** 片 1–7 已做

`lib/` 的结构债在 PR #287（目录间循环）和 #288（目录内平铺）之后只剩最后一项：单个文件
太大。这份方案把它切成八片，一片一个 PR。

写下来的理由和前两轮不同。前两轮的目标是可断言的不变量，写进 `test/source_layout_test.dart`
就不会回来；这一轮**没有同等干净的断言**（见 §6），所以清单本身就是记录 —— 尤其是
「哪个大文件是刻意的」这一条，不写下来下一轮还会重新上报一次。

---

## 0. 清单修正

上一轮结束时报的「8 个 1500 行以上的文件」是旧测量。对着 `6e55653` 重数（排除 `lib/l10n/`
的四份生成文件）：

| 文件 | 行 | 本轮 |
|---|---|---|
| `services/assistant/prompt_optimizer_agent.dart` | 4207 | 片 3 |
| `screens/workbench/widgets/prompt_optimizer_view.dart` | 2759 | 片 4 |
| `screens/workbench/widgets/video_config_panel.dart` | 1947 | 片 8 |
| `services/llm/protocols/openai_chat_protocol.dart` | 1784 | 片 2 |
| `services/llm/protocols/anthropic_chat_protocol.dart` | 1670 | 片 1 |
| `screens/workbench/directory_tree_item.dart` | 1593 | 片 5 |
| **`services/llm/llm_dispatcher.dart`** | **1584** | **排除，见下** |
| `screens/browser/ai_rename_dialog.dart` | 1510 | 片 7 |
| `widgets/models/model_edit_dialog.dart` | 1497 | 片 6 |

分布：1500+ 八个，1200+ 十六个，1000+ 二十二个，800+ 三十四个。本轮只碰上表九个中的八个。

### 为什么排除 `llm_dispatcher.dart`

CLAUDE.md 和 `docs/architecture/llm-three-layer.md` 都明文规定它是**唯一路由表**：
「all routing branches live in `llm_dispatcher.dart` only」。它的内容确实就是这个 ——
`descriptorFor` · `protocolMenu` · `_familyRoute` · `reasoningLadder` ·
`chatConsumesReasoningEffort` · `checkOperation`（171 行的 switch）· `startLongRunning`。

**它的大是设计出来的。** 按 surface 或按 family 把它切开，等于把路由分支散到多个文件，
直接违反那条不变量 —— 而那条不变量存在的原因正是「中转站不能靠 id 猜」那一整轮的结论。

> 下一轮谁再按行数扫一遍 `lib/`，这个文件还会排在最前面。**它不是债，不要立项。**

---

## 1. 判断标准与两类手法

不按行数切，按「这个文件里有几件互不相干的事」。这决定了两类完全不同的手法，验证成本差一个量级：

**A 类 — 文件里本来就是并列的独立单元。** 拆开是搬运 + 改 import，编译器兜底，行为等价几乎
免费。片 1–3（两个 protocol + agent）属于这类，片 5 半属于。

**B 类 — 一个巨型 State 类。** 拆开要真的抽 widget 或抽 service，得逐个论证行为等价。
片 4、6、7、8 属于这类。

所以顺序是：A 类先做，B 类里有测试的先做，零覆盖的最后做并且先补测试。

---

## 2. 分期

### 片 1 · `anthropic_chat_protocol.dart` 1670 → 7 个文件 ✅ 已做

这个文件不是一个大类，是**一个顶层函数库 + 两个 protocol 类**。切面天然存在。

| 新文件 | 内容 | 实际行 |
|---|---|---|
| `anthropic_wire.dart` | 七个 const + `anthropicMaxTokens` | 56 |
| `anthropic_history.dart` | `AnthropicHistory` · `buildAnthropicHistory` · `anthropicUserBlocks` · `_labelAuthorText` | 205 |
| `anthropic_thinking.dart` | thinking request / output config / effort wire / 备用方言 + 方言学习记忆 + `isAnthropicThinkingRejection` | 183 |
| `anthropic_payload.dart` | `prepareAnthropicPayload` + `applyAnthropicCacheBreakpoints` | 131 |
| `anthropic_response.dart` | `ServerToolRun` · `logAnthropicServerToolRun` · `AnthropicContent` · `parseAnthropicContent` · `parseAnthropicWebSearchResult` · `anthropicUsageMetadata` · `anthropicFinishReason` | 310 |
| `anthropic_stream.dart` | `AnthropicStreamAssembler` | 395 |
| `anthropic_chat_protocol.dart` | `AnthropicChatProtocol` + `AnthropicDiscoveryProtocol` | 420 |

依赖只朝一个方向：wire ← history / thinking / response；payload ← history + thinking；
stream ← response；protocol ← 全部。七个文件之间没有环。

**和原计划的两处出入**

- usage 与 `stop_reason` 翻译没进 wire，进了 response（原计划叫 `anthropic_content.dart`）。
  `anthropicUsageMetadata` 收 `List<ServerToolRun>`，放在 wire 会让最底层反过来依赖
  response；「读一个响应」本来也是一件事。
- 事前只查了**顶层**私有名，漏了一个**类内**私有静态：`AnthropicChatProtocol._logServerToolRun`
  也被 stream assembler 调用。它记录的是一个 `ServerToolRun`，所以变成顶层函数
  `logAnthropicServerToolRun` 住到那个类旁边。另一处已知的 `_parseWebSearchResult` →
  `parseAnthropicWebSearchResult`。**后面几片的事前检查要把类内私有静态一起查。**

`_learnedThinkingDialects`（进程级可变状态）和它的四个读写点、reset 一起整组进了
`anthropic_thinking.dart`，只有一份记忆。

**importer**：`llm_dispatcher.dart` 改引 thinking + wire；`turn_continuation.dart` 的
`show` 改指 wire；`anthropic_chat_test.dart` 改引六个新文件，**不再引协议文件本身**
—— 它测的一直是这些 helper，不是协议类。

**结果**：`flutter analyze` 零问题；`flutter test -x screenshots` 2183 passed（与基线
一致）。`docs/architecture/llm-three-layer.md` 的 ④ 一节加了文件 → 不变量对照表。

---

### 片 2 · `openai_chat_protocol.dart` 1784 → 6 个文件 ✅ 已做

| 新文件 | 内容 | 实际行 |
|---|---|---|
| `openai_chat_parsing.dart` | `contentToText` · `resolveToolCallId` · `decodeToolArguments`（含 `_recoverConcatenatedJsonObjects`）· `firstChoice` · `pickReasoningField` · `normalizeOpenAIUsage` | 187 |
| `streaming_tool_calls.dart` | `StreamingToolCallAccumulator` + `_PendingToolCall` | 187 |
| `inline_think.dart` | `stripInlineThink` + `InlineThinkStreamFilter` + `_ThinkPhase` | 145 |
| `chat_image_extraction.dart` | `StructuredImages` · `WholeContentImage` · `ImageDeduper` · `imageUrlsInText` | 195 |
| `openai_chat_payload.dart` | `openaiDefaultSystemPrompt` + `prepareOpenAIChatPayload` + `openaiReasoningEffortWire` · `openaiThinkingFields` + gemini 兼容扩展 | 298 |
| `openai_chat_protocol.dart` | `generate` · `generateStream`（372 行）· 图文处理 · `buildChatPayloadForTest` · discovery | 796 |

依赖：parsing ← streaming_tool_calls；inline_think 与 chat_image_extraction 不引任何兄弟；
payload 只引 `protocol.dart`；protocol ← 全部。

**做法**：顶层声明照片 1 的脚本原样搬；类里的 `_prepareChatPayload`、两个 static、
`_applyGeminiCompatExtensions` 去掉两格缩进变成顶层函数（`_prepareChatPayload` →
`prepareOpenAIChatPayload`，另两个 static 去掉 `static`）。事前查过：这几个成员在类里除了
彼此不碰任何东西。`buildChatPayloadForTest` 留在类上转调，四个测试一行不改。
按去缩进、改名之后的行做多重集比对，一行不差。

**importer**：`dashscope_chat_protocol.dart` 的 `show` 拆成两条（parsing + streaming_tool_calls），
`openai_responses_protocol.dart` 改引 parsing —— **这两个 ① 的兄弟协议现在不再经过
`openai_chat_protocol.dart` 拿公共件**。三个测试改引新文件。

**工具上的一个坑**：修剪未用 import 的脚本第一次把 `openai_responses_protocol.dart` 里
那条 `show` 也删了 —— 它的名字搬走后，analyzer 报的是「未用」而不是「找不到」。脚本
现在只改显式传入的文件。

**结果**：`flutter analyze` 零问题；`flutter test -x screenshots` 2183 passed。
`llm-three-layer.md` 里指向 `openai_chat_protocol.dart` 的公共件位置已改。

---

### 片 3 · `prompt_optimizer_agent.dart` 4207 → 用 `part` 拆成 7 个 ✅ 已做

**这个文件不能拆成独立库。** 耦合是双向的：session 一侧调
`PromptOptimizerAgent._isRealUserTurn` / `._isFreeTextAskUserReply`；agent 一侧调 13 个不同的
`session._*`（`_addEntry` 13 次、`_setRunning`、`_resolveKbEdit`、`_stageAskUser`…）。拆成
独立库要把 ~30 个故意私有的成员变 public。所以用 `part`（`app_state.dart`、
`task_queue_service.dart` 已有先例）。

**原计划漏了一件事：Dart 没有 partial class。** `part` 文件放不下「半个类体」，所以
「`part` 拆、零改动」只对顶层那一半（session 等）自动成立。类这一半的做法：

- `PromptOptimizerAgent` 本来就**只有 static 成员**（一个命名空间）。**公有成员全部留在类上**
  —— 42 个外部用到的 `PromptOptimizerAgent.X` 一个不动，类就是 API，文档也都在这。
- **私有 static 搬进 part，变成库私有的顶层声明**（去掉 `static`、去两格缩进）。类里的
  无限定调用照旧解析到它们。
- 反过来，搬出去的代码里用到的类成员（marker 常量、`_request`、`measureContext`…）
  由 analyzer 报出 22 处，脚本补上 `PromptOptimizerAgent.` 前缀；session 里原来带前缀
  调私有 static 的 3 处去掉前缀。

| 文件 | 内容 | 实际行 |
|---|---|---|
| `prompt_optimizer_session.dart` | 三个 enum + AskUser 三件套 + `OptimizerChatEntry` + `PromptOptimizerSession` + `AgentRequestFn` | 973 |
| `assistant_context_window.dart` | 调参常量 · `_readCapNow` · 轮次判定与 `_boundaryOf` · liveness · `_trimForSend` / `_elide` · `_maybeCompact` / `_serializeForSummary` | 557 |
| `assistant_tool_calls.dart` | `_executeTool` + delegate / note / write-knowledge 执行器 + `_clipPreview` · `_fileSizeKb` · `_mimeTypeFor` | 690 |
| `assistant_toolset.dart` | 四组 tool schema（`toolsetFor` / `delegateToolFor` 是公有的，留在类上） | 207 |
| `assistant_history_repair.dart` | `_repairPairingWithOrigins` · `_pairDanglingAskUser` · `_cancelDanglingAskUser` | 169 |
| `assistant_system_prompts.dart` | 四个 mode prompt + 两个 sub-agent prompt + `_finalRoundNudge` · `_feedbackRoundNote` | 272 |
| `prompt_optimizer_agent.dart` | 类：全部公有入口（`runTurn` 541 行）+ `_maxTurns` · `_request` · 持久化 · `_drainKbEditOutcomes` | 1352 |

**两个 analyzer 看不见的坑，都查了**

1. **字符串插值。** 补前缀的脚本把 `'$summaryMarker\n…'` 改成了
   `'$PromptOptimizerAgent.summaryMarker\n…'` —— 这**能编译**，插进去的是类型名，压缩摘要
   会以字面的 `PromptOptimizerAgent.summaryMarker` 开头。analyzer 只在另一处 `const` 字符串
   上报了错；两处都改成 `${…}`，脚本也改了。**以后任何「补限定前缀」的批量改动都要 grep
   `\$类名\.`。**
2. **静默改绑。** 搬出去的代码里如果有个类成员名在库作用域里恰好也有定义，不会报错而是
   绑到别处。逐名查过 49 个留在类上的名字：命中的 6 处全是参数 / 字段，和搬之前一样遮蔽。

另外 6 处 dartdoc 链接（`[viewResultMarker]` 之类）补了类名，否则搬出去之后指向空。

按「去 static、去前缀、`${}` 还原」归一后做多重集比对，一行不差。

**结果**：`flutter analyze` 零问题；`flutter test -x screenshots` 2183 passed；42 个 importer
零改动。`assistant-context.md` 加了「Where it lives」一节，CLAUDE.md 的 map 与必读说明跟着改。

`runTurn` 541 行仍是主文件里最大的一块，拆它要动控制流，本轮不动。

---

### 片 4 · `prompt_optimizer_view.dart` 2759 → 9 个文件 ✅ 已做

State 类 2140 行，builder 共享它的字段、常量和一套卡片词汇。

**手法和原计划不同：没有抽成独立 widget，而是 `part` + State 上的具名 extension。**
原计划写的是「真的抽 widget、抽出去的变 public、会改 rebuild 范围」。改主意的理由：
这个 view 只有部分覆盖（4 个 UI 测试 + screenshot），而抽 widget 会改元素树 —— state
保留、`setState` 范围、rebuild 范围都会动，那是行为变化，不是搬家。extension 让元素树
**一个节点都不变**。真要抽 widget（顺便收窄 rebuild），应当单独立项、单独验证。

| part（`widgets/optimizer/`） | extension | 内容 | 实际行 |
|---|---|---|---|
| `optimizer_card_chrome.dart` | `_CardChrome` | 头像列、卡片框 / 头、文字动作、徽标 | 181 |
| `optimizer_agent_timeline.dart` | `_AgentTimeline` | 运行卡 + 工具时间线 + `_ElapsedLabel` | 294 |
| `optimizer_kb_edit_card.dart` | `_KbEditCard` | KB edit 卡、diff、全文 + `_lineCount` | 386 |
| `optimizer_prompt_card.dart` | `_PromptCard` | 提示词卡 + `_fold` | 180 |
| `optimizer_feedback_card.dart` | `_FeedbackCard` | 结果反馈卡 | 173 |
| `optimizer_distill_cards.dart` | `_DistillCards` | 蒸馏请求卡 + 完成卡 + `_distillOutcome` | 219 |
| `optimizer_composer.dart` | `_Composer` | chip、输入栏、发送 / 停止、`_isSendKey` + `_RunStatus` | 349 |
| `optimizer_ask_user_card.dart` | — | `_AskUserCard`（本来就是独立 widget）+ 虚线 painter | 428 |
| `prompt_optimizer_view.dart` | — | widget + State 生命周期 + 转录装配 + `_buildEntry` 分派 | 594 |

**语言逼出来的两处改动**

- extension 里引用被扩展类型的 static 必须带类名：21 处补了
  `_PromptOptimizerChatViewState.`（其中一处在插值里，已加 `${}`）。
- extension 不能调 protected 的 `setState`：三个展开开关改走 State 上一行的 `_rebuild`。

**analyzer 看不见、查了的**：在 extension 体里，**库作用域的名字优先于隐式 `this`**（类体里
正相反）。代码用到的 69 个成员名（含继承来的 `context` / `widget` / `mounted`）逐个在
同一组 import 下探测过，没有一个在库作用域里有定义；库自己的顶层名也逐个对过。

**虚线 painter（§5 第 1 条）**：`DashedBorder` 不是 drop-in —— 它画在 child **后面**，而这里
child 是输入框自己的不透明底色，会把虚线盖住。所以保留前景 painter 和半像素内缩
（`app_reorder_gap.dart` 同款），只把虚线循环交给 `drawDashedRRect`。唯一可见变化是节奏
4/3 → 5/4；没有 harness 截图拍到这个输入框，另做了一张新旧并排的渲染肉眼核对。单独一个 commit。

**验证上学到的**：`diff -r` 比 PNG **字节**毫无意义 —— 两次运行几乎每张图的字节都不同（连
没碰过的下载器、文件浏览器也是）。改成解码后逐像素比（scratchpad 的 `pixdiff.py`）：
175 / 175 一致。`render_probe` 没有单独跑前后对比：元素树按构造不变，
`rebuild_scope_test` 照常通过。

按「去类名前缀、`_rebuild` 还原」归一后多重集比对：只多出 7 个 extension 外壳和
`_rebuild`，一行不少。

**结果**：`flutter analyze` 零问题；`flutter test -x screenshots` 2183 passed；screenshot
175 / 175 像素一致。

---

### 片 5 · `directory_tree_item.dart` 1593 → 4 个文件 ✅ 已做

| 文件 | 形式 | 内容 | 实际行 |
|---|---|---|---|
| `lib/widgets/files/folder_drop_feedback.dart` | 库 | `FolderDropRejection` + 标签扩展 + `FolderDropFeedback` + `FolderDropFollower` | 96 |
| `screens/workbench/folder_tree_row.dart` | 库 | `FolderDropTone` · `TreeDisclosure` · `FolderTreeMetrics` · `FolderTreeRow` · `FolderTreeRowAction` · `_DropNoteSlot` | 556 |
| `screens/workbench/folder_drop_target.dart` | `part` | `_RowDrop` · `_CopyModifierListener` · `_MaybeDropTarget` | 262 |
| `screens/workbench/directory_tree_item.dart` | 库 | `FolderDragPayload` · `DirectoryTreeItem` + State · `_Pulsed` · `_FolderDragChip` | 706 |

**错位修掉了，而且比原先以为的更实在**：`screens/browser/widgets/browser_drag_chip.dart`
原来 `import '../../workbench/directory_tree_item.dart' show FolderDropFollower` —— **一个
feature 直接引另一个 feature 的文件**（层级测试只管顶层目录，`screens/` 内部的横向引用它看不到）。
现在改引 `widgets/files/`，这条横向边没了。去 `widgets/files/` 而不是 `widgets/drag/` 的理由
见上一版：拒绝理由是文件夹语义，设计系统不该知道。

`FolderDropFeedback._post` / `._withdraw` 被留在 workbench 的 drop target 调用，所以变成公有的
`post` / `withdraw`，doc 里写明「只有发出判定的那一行能清掉它」。

`FolderTreeRow` 一组做成独立库（`folder_list.dart` 和 `result_tree_item.dart` 直接引它）；
drop target 只有 tree item 用，做成 `part`，名字保持私有。

`plans/README.md`（动效台账）里引的 `directory_tree_item.dart:647` 与 `:1073-1085` 本来就已经过期，
按拆分后的位置改成 `directory_tree_item.dart:583` 和 `folder_tree_row.dart:388-400`。

**结果**：`flutter analyze` 零问题；`flutter test -x screenshots` 2183 passed；screenshot
175 / 175 像素一致；`rebuild_scope_test` 的 *"a folder pulse reaches one tree row, not the
browser"* 通过。多重集比对只多出两个新方法的 doc。

---

### 片 6 · `model_edit_dialog.dart` 1497 → 6 个文件 ✅ 已做

和片 4 同一手法：`part` + State 上的具名 extension，放在 `widgets/models/model_edit/`。

| part | extension | 内容 | 实际行 |
|---|---|---|---|
| `model_edit_layouts.dart` | `_Layouts` | edit 对话框 / 手机页 / add 对话框、头尾与玻璃条、双栏 / 单栏排布 | 388 |
| `model_edit_identity.dart` | `_IdentitySection` | id · name · channel · kind · 费用组 + `_selectKind` | 240 |
| `model_edit_capabilities.dart` | `_CapabilitySections` | 能力 · 卡片预览 · agent · reasoning 阶梯 | 274 |
| `model_edit_context.dart` | `_ContextSection` | 上下文窗口段 | 176 |
| `model_edit_protocol.dart` | `_ProtocolSections` | provider 特性 + 按 surface 的协议点单及其过期判定 | 161 |
| `model_edit_dialog.dart` | — | widget + State：draft 字段、生命周期、校验、保存、删除 | 290 |

**原计划担心的「共享 draft 怎么传」没有发生。** 原方案在「draft 对象 + `onChanged`」和
「draft 提成 `ChangeNotifier`」之间选；extension 通过 `this` 直接读写 draft，元素树也不变，
两条路都不用走。

语言逼出来的改动同片 4：23 处 static 补类名、15 处 `setState` 改走 `_rebuild`。
extension 经 `this` 碰到的 82 个名字逐个在 import 和库顶层名下探测过，没有碰撞。
（探测脚本在这一片里修过一次：第一版把调用处当成了成员名、把缩进行当成了顶层名，报了一大堆
假阳性；收紧之后对片 4 也重跑了一遍，仍是零。）

**结果**：`flutter analyze` 零问题；`flutter test -x screenshots` 2183 passed；screenshot
175 / 175 像素一致 —— 模型编辑器三个布局带、两种亮度、new / protocol / relay 各态都在其中。
多重集比对只多出 5 个 extension 外壳和 `_rebuild`。

---

### 片 7 · `ai_rename_dialog.dart` 1510 → 业务逻辑下沉 + 3 个 part ✅ 已做 —— **顺带修了一个会删照片的 bug**

**第一步：冲突逻辑变成 service，并第一次有了测试。** `_RenameRow` · 两个 enum ·
`_recomputeConflicts`（会 stat 磁盘）· `_resolve` 原样搬到
**`services/tasks/ai_rename_review.dart`**（`RenameReviewRow` · `RenameConflict` ·
`RenameConflictChoice` · `recomputeRenameConflicts` · `resolveRenameConflict`），dialog 只留两个
「调完再 rebuild」的薄壳。**没放进原计划的 `services/files/`**：行包着 `RenameProposal`
（`services/tasks/ai_rename_agent.dart`），而 `files/` 今天不引任何其他 service 子目录。

`test/ai_rename_review_test.dart` 先钉住现状（7 条）。写到「两行重名时点改名」这一条时它失败了。

**找到的 bug（修复前的行为，用真实的 review + executor 端到端复现过）**

两行都提议 `beach.jpg`（「重名」），review 对每行都提供 改名 / 覆盖 / 跳过：

- **改名**调 `uniqueTargetPath` 时没传 `reserved`，只看磁盘 —— 共享的那个名字磁盘上还不存在 ——
  于是把同一个名字原样还回来，行上却显示「已改名」、算作已回答。
- **覆盖**在这种冲突上也可点，可磁盘上根本没有要替换的文件；它唯一能替换的是另一行刚改过去的结果。
- `applyProposals` 在 `overwrite` 为真时会删掉目标处的任何文件，包括同一批里前一条刚放过去的。

A 行点改名、B 行点覆盖 → 结果目录里只剩一个文件：**A 的照片被 `File.delete` 删了（不进回收站）**，
界面上没有任何提示。两行都点覆盖也一样。

**修法按项目对破坏性操作的规矩，两层都拦**（单独一个 `fix` commit）：

| 层 | 改动 |
|---|---|
| service | `resolveRenameConflict` 必须传整张表（`among:`，required），改名时避开其他活动行占用的名字（与冲突检查一样忽略大小写）；行间冲突上的覆盖直接抛 `StateError` |
| service | `applyProposals` 不会替换本批次里刚放到位的文件，无论 flag 是什么（大小写折叠，照顾会折叠大小写的文件系统） |
| UI | 这种行上的「覆盖」保持可见但禁用，tooltip 说明原因（新 key `renameOverwriteDuplicateHint`，四种语言） |

新增 12 个测试：重名改名、异大小写占用、覆盖被拒、executor 闸门（去掉闸门会失败，验过）、以及上面那个
端到端场景（现在两个文件都在）。executor 那条用同大小写的名字 —— CI 是 ubuntu，大小写敏感。

**没有覆盖到的**：禁用的覆盖按钮本身没有 screenshot 也没有 widget 测试。harness 从不展示 review 行，
而要种出这些行得先 stub 一次模型调用，dialog 没有给测试留这个口子。

**第二步：界面拆成 3 个 part**（同片 4 的手法，放在 `screens/browser/ai_rename/`）：

| part | extension | 内容 | 实际行 |
|---|---|---|---|
| `ai_rename_config.dart` | `_ConfigColumn` | 配置列 + 窄屏摘要行与抽屉 | 289 |
| `ai_rename_results.dart` | `_ResultsArea` | 过滤行、失败批次卡、空态 / 无模型态、review 列表、跳到下一个冲突 | 321 |
| `ai_rename_rows.dart` | — | `_GeneratingRow` · `_ResultRow` · `_RowAction` · 两个小部件 | 369 |
| `ai_rename_dialog.dart` | — | State：生成 / 合并 / 应用、计数、`build`、驱动应用的 footer | 477 |
| `services/tasks/ai_rename_review.dart` | 库 | 见上 | 146 |

2 处 static 补类名、3 处 `setState` 改走 `_rebuild`；54 个名字探测无碰撞。

**结果**：`flutter analyze` 零问题；`flutter test -x screenshots` **2195** passed（+12）；screenshot
175 / 175 像素一致。

---

### 片 8 · `video_config_panel.dart` 1947 → 5 个文件，**放最后**

| 新文件 | 内容 | 原行 | ~行 |
|---|---|---|---|
| `video/video_frame_slots.dart` | `_announceDrop` · `_DropSlot` · `_PlateLabel` · `_PlateCloseButton` · `_FrameDropTarget` · `_FilledFrameSlot` | 1003–1516 | 510 |
| `video/video_reference_images.dart` | `_ReferenceImagesSection` + `_ReferenceThumbnail` | 1517–1861 | 345 |
| `video/video_param_controls.dart` | `_buildVideoParamControl` · `_videoParamLabel` · `_paramGrid` · `_ParamCell` | 751–901 · 953–1002 | 200 |
| `video/video_panel_chrome.dart` | `_PanelCard` · `_EditorWell` · `_ToggleRow` · `_WarningNotice` | 902–952 · 1862–1947 | 140 |
| `video_config_panel.dart` | Panel + State + `build`（366 行）+ `_buildModelSection`（189 行）+ 提交 | 81–750 | 700 |

**风险最高的一片**：`VideoConfigPanel` 在 `test/` 里零引用，`test/screenshots/` 里也没有
任何拍到它的 case。**这一片要先补 screenshot 再动手** —— 把工作台视频 tab 纳进
`app_screens_workbench_tabs_test.dart`（或新开一个 case），存下 PNG 作为基线。

`video_param_controls` 那组要注意：按模型声明渲染参数（`model_capabilities.dart` 读来的）
是这个面板的核心契约 —— 参数**声明在模型上，不在面板里**。抽的时候只搬渲染，不要顺手
在新文件里加任何 `if (modelId == ...)`。

---

## 3. 每一片的验证流程

一片一个 PR，一片一个分支（`claude/split-<file>`），按 `docs/plans` 的老规矩每个切面一个
commit。

**开工前**

```bash
flutter test -x screenshots                     # 基线：当前 2183 passed
flutter test test/screenshots                   # 涉及 UI 的片：存一份 PNG 到别处
cp -r build/ui-screenshots /tmp/before-<片号>
```

**落地后**

```bash
flutter analyze                                 # 必须 No issues found!（含 info）
flutter test -x screenshots                     # 数字必须和基线一致（除了片 7 新增的）
flutter test test/screenshots && python3 pixdiff.py /tmp/before-<片号> build/ui-screenshots  # 比像素，不比字节
git diff -M25% --stat main...HEAD               # 看到的应该是 rename / 大块移动，不是重写
```

- PNG 对比对片 1–3、5 应当**逐像素一致**（字节每次运行都会变，见片 4）；片 4 的 dashed 节奏和片 6、8 的 section 抽取
  可能有 1px 级差异，逐张看过并在 PR 里说明。
- 片 4 和片 5 额外跑 `flutter test test/screenshots/render_probe.dart` 前后对比 rebuild 范围。
- 片 7 的测试数会涨（新增 `rename_plan_test.dart`），在 PR 里写明涨了几个。

**一个已知的既存 flake**（PR #288 时观察到，不是本轮引入）：
`test/video_job_resume_test.dart` 的 *"a user retry forgets the job id and submits afresh"*
在整跑时偶发失败一次，单跑和重跑均通过。撞上了重跑一次，不要当成本轮的回归。

---

## 4. 测试覆盖缺口（决定了顺序）

| 片 | 直接覆盖 | 缺口 |
|---|---|---|
| 1 anthropic | `anthropic_chat_test`（`AnthropicContent` 18 · `StreamAssembler` 7 · payload 多处） | `buildAnthropicHistory` 无直接测试，靠 payload 测试间接覆盖 |
| 2 openai | 7 个测试文件，accumulator / 图片中继 / payload 各有专属 | — |
| 3 agent | 31 个 `optimizer_*` | — |
| 4 view | 4 个 UI 测试 + screenshot | — |
| 5 tree | `rebuild_scope_test` + 文件浏览器 screenshot | — |
| 6 model_edit | **仅 screenshot（不断言）** | 靠 PNG 逐像素对比 |
| 7 ai_rename | **零** | ✅ 补了 `ai_rename_review_test.dart`（11 条）+ executor 1 条 |
| 8 video | **零，连 screenshot 都没有** | **本片先补 screenshot** |

---

## 5. 顺手修的三件事（不要漏，它们是拆这几个文件的一半价值）

1. **片 4** ✅ — `_DashedOutlinePainter` 是 `widgets/ui/dashed_border.dart` 明确要消灭的那种
   拷贝的第四份。换成 `drawDashedRRect`。
2. **片 5** ✅ — `FolderDropFollower` 一组从 workbench 移到 `widgets/files/`：它的唯一
   使用者在 browser，住在 workbench 是错位（browser 因此不再横向引 workbench）。
3. **片 7** ✅ — 重命名冲突检测从 dialog 下到 `services/tasks/ai_rename_review.dart`，第一次拥有测试 —— 并因此找到、修掉了一个会删用户照片的 bug（见片 7）。

---

## 6. 为什么这一轮不加断言

PR #287 和 #288 各留了一条 `test/source_layout_test.dart` 的断言（层级 rank、无环、
分组、设计系统纯度），共 8 条。这一轮**没有同等干净的对应物**，三个候选都是钝器：

| 候选 | 为什么不行 |
|---|---|
| 行数上限（比如 1200） | 1400 行的文件不违反它但也不好；**1584 行的 `llm_dispatcher.dart` 违反它但是对的**。上白名单则白名单必然腐化 |
| 「一个文件不超过 N 个 public 类」 | `anthropic_chat_protocol` 拆完每个文件 1–3 个类，但 `widgets/ui/` 有大量一文件一类的小文件，N 定在哪都没有依据 |
| 「一个 State 类不超过 N 行」 | 同上，而且鼓励把行数挪进私有 widget 而不是真的拆 |

**决定：不加断言。** 理由不是懒，是性质不同 —— 前两轮防的是**会静默失效的不变量**
（循环不破构建、散落文件不破任何东西，所以它们能活很久）；这一轮的问题是**可读性**，
它不会静默，每次打开文件都在喊。清单本身（尤其 §0 的 dispatcher 条）就是这一轮的记录。

---

## 7. 记账

八片全部落地后：删掉本文件，在 `docs/plans/README.md` 的「已执行」表里加一行，写清
**「`llm_dispatcher.dart` 1584 行是刻意的，不要立项」**，以及各片实际的收尾行数。
`CLAUDE.md` 的 Project Map 要跟着改（片 1、2 给 `protocols/` 加六个文件，片 3 给
`assistant/` 加 part 说明，片 5 给 `widgets/files/` 加一项，片 7 给
`services/files/` 加一项）。
