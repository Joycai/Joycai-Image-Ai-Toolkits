# 大文件拆分方案

**基线** `6e55653` 2026-09-16 v4.7.7（PR #288 合入后）· **状态** 片 1 已做

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

### 片 2 · `openai_chat_protocol.dart` 1784 → 6 个文件

| 新文件 | 内容 | 原行 | ~行 |
|---|---|---|---|
| `openai_chat_parsing.dart` | `contentToText` · `resolveToolCallId` · `decodeToolArguments`（含 `_recoverConcatenatedJsonObjects`）· `firstChoice` · `pickReasoningField` · `normalizeOpenAIUsage` | 22–155 · 333–384 | 150 |
| `streaming_tool_calls.dart` | `StreamingToolCallAccumulator` + `_PendingToolCall` | 156–332 | 180 |
| `inline_think.dart` | `stripInlineThink` + `InlineThinkStreamFilter` + `_ThinkPhase` | 385–531 | 150 |
| `chat_image_extraction.dart` | `StructuredImages` · `WholeContentImage` · `ImageDeduper` · `imageUrlsInText` | 532–717 | 190 |
| `openai_chat_payload.dart` | payload 构造 + `openaiThinkingFields` + gemini 兼容扩展 + `buildChatPayloadForTest` | 1445–1746 | 300 |
| `openai_chat_protocol.dart` | `generate` · `generateStream` · 图文处理 · discovery | 718–1444 · 1747–1784 | 620 |

**已验证的前提**：`OpenAIChatProtocol` **一个实例字段都没有**（727 行起直接是 `@override
generate`），是纯方法袋。所以 `_prepareChatPayload` 可以无损变成顶层函数
`prepareOpenAIChatPayload`，不需要传 `this`。

`_TextProcessResult`（1747）只被 `_processTextAndExtractImages` 用，跟着留在主文件。

**外部影响**（片 1 同理，但这片更大）：这些 helper 早就被跨文件用了 ——
`dashscope_chat_protocol.dart`（7 处）、`openai_responses_protocol.dart`（3 处）、
`turn_continuation.dart`、`protocols/protocol.dart`，加上 6 个测试文件。**它们本来就是共享
工具，只是住在一个 protocol 文件里。** 拆出来是把现状写明，不是新增耦合。import 改动机械但
会碰到 ~12 个 importer。

**守护**：`streaming_tool_call_accumulator_test.dart`（21 处引用）、
`image_relay_compat_test.dart`（12 处）、`openai_chat_payload_test.dart`（36 处）、
`openai_chat_image_links_test.dart`、`openai_stream_regressions_test.dart`、
`turn_continuation_test.dart`。

---

### 片 3 · `prompt_optimizer_agent.dart` 4207 → 用 `part` 拆成 7 个

**这个文件不能拆成独立库。** 耦合方向查过，是双向的：

- session 一侧调 `PromptOptimizerAgent._isRealUserTurn`（343）、
  `._isFreeTextAskUserReply`（358）
- agent 一侧调 13 个不同的 `session._*`：`_addEntry`（13 次）· `_setRunning`（3）·
  `_resolveKbEdit`（3）· `_resolveAskUser`（3）· `_reportedKbEditIds` · `_findKbEdit` ·
  `_backedUpPaths` · `_stagePrompt` · `_stageKbEdit` · `_stageAskUser` ·
  `_repairToolCallPairing` · `_markViewed` · `_carryStaleMarker`

拆成独立库要把 ~30 个私有成员变 public。那比现在更糟：它们是**故意**私有的（`_stageKbEdit`
之外还专门有一个 `stageKbEditForTest`，就是为了不把 staging 暴露出去）。

用 `part`。`lib/state/app_state.dart`（两个 part）和
`lib/services/tasks/task_queue_service.dart`（`task_executors.dart`）已有先例，
`use_string_in_part_of_directives` 已开，写字符串形式。

| part 文件 | 内容 | 原行 | ~行 |
|---|---|---|---|
| `prompt_optimizer_session.dart` | 三个 enum + AskUser 三件套 + `OptimizerChatEntry` + `PromptOptimizerSession` + `AgentRequestFn` | 35–1011 | 975 |
| `assistant_toolset.dart` | `_tools` · `_knowledgeTools` · `_knowledgeWriteTools` · `_noteTools` · `delegateToolFor` · `toolsetFor` | 1324–1641 | 320 |
| `assistant_context_window.dart` | `shouldCompact` · `compactionBoundary` · `occupiedChars` · `toolSchemaChars` · `measureContext` · `_trimForSend` · `_elide` · `_maybeCompact` · `_serializeForSummary` + liveness 判定 + 调参常量 | 1121–1268 · 2368–2927 | 700 |
| `assistant_tool_calls.dart` | `_executeTool` + `_executeDelegate` · `_runDraftDelegate` · `_finishDelegateRun` · `_executeReadNote` · `_executeSubAgentKbTool` · `_executeWriteKnowledge` · `buildDelegateTask` | 2947–3637 | 690 |
| `assistant_history_repair.dart` | `repairToolCallPairing` · `_repairPairingWithOrigins` · `_pairDanglingAskUser` · `_cancelDanglingAskUser` · `answerAskUser` · `resolvePendingAskUserAsFreeText` | 3724–3959 | 240 |
| `assistant_system_prompts.dart` | 四个 `_build*SystemPrompt` + 两个 sub-agent prompt + `_finalRoundNudge` · `_feedbackRoundNote` · `notRunStubMessage` | 2928–2946 · 3050–3063 · 3960–4207 | 300 |
| `prompt_optimizer_agent.dart` | marker 常量 + `tryParseResultFeedback` + `_request` + `sessions` + `runTurn`（536 行）+ 持久化 + KB edit 落盘 | 1012–1120 · 1269–1323 · 1642–2367 · 3639–3723 | 1000 |

**代价要说清楚：`part` 只减文件体积，不减耦合。** 但这个文件本来就是一个状态机，耦合是真的，
假装成七个独立模块才是撒谎。换来的是零风险：

- 42 个 importer 一个都不用改（`PromptOptimizerAgent.X` 全部原样可达）
- 31 个 `optimizer_*` 测试原样通过 —— **行为等价是现成的证明**，不用另外论证

`runTurn` 自己 536 行，拆完还是主文件里最大的一块。它是 tool loop 的主体，拆它要动控制流，
本轮不动。

---

### 片 4 · `prompt_optimizer_view.dart` 2759 → 9 个文件

State 类 2144 行（95–2239），里面是一串互不相干的卡片渲染器。新文件全部进
`screens/workbench/widgets/optimizer/` 子目录。

| 新文件 | 内容 | 原行 | ~行 |
|---|---|---|---|
| `optimizer_card.dart` | `_card` · `_cardHeader` · `_textAction` · `_statusBadge` · `_besideAvatar` · `_fold` → 一套卡片词汇 | 419–598 · 1515–1556 | 220 |
| `optimizer_agent_timeline.dart` | 时间线 + 过程卡 + 工作步 + 工具步 | 599–806 | 210 |
| `optimizer_kb_edit_card.dart` | KB edit 卡 + 结果 + diff + diff 行 + 全文 | 1007–1378 | 370 |
| `optimizer_prompt_card.dart` | 提示词卡 + 行数徽标 | 1379–1514 · 1919–1939 | 160 |
| `optimizer_feedback_card.dart` | 结果反馈卡 + `_feedbackChip` | 1557–1728 | 170 |
| `optimizer_distill_cards.dart` | 蒸馏请求卡 + 完成卡 + `_distillOutcome` | 1729–1918 | 190 |
| `optimizer_composer.dart` | 输入栏（176 行）+ 发送 / 停止 / chip | 1940–2238 | 300 |
| `optimizer_ask_user_card.dart` | `_AskUserCard` 全套 | 2340–2729 | 390 |
| `prompt_optimizer_view.dart` | State + `_TranscriptRow` + 转录装配 + 空状态 + `_RunStatus` + `_ElapsedLabel` | 25–418 · 2239–2339 | 500 |

**三个注意点**

1. **私有类跨文件不行** —— Dart 的 private 是库级。抽出去的要变 public。子目录
   `optimizer/` 就是用来圈住这批新 public 名字的。
2. **`_DashedOutlinePainter`（2730）是第四份拷贝。** `widgets/ui/dashed_border.dart` 的
   doc 里写着它存在的理由是「三处各自长了一个 painter」，并且导出了
   `drawDashedRRect(Canvas, RRect, Paint)` 正好给自绘 painter 用。差别只有节奏：
   本地是 dash 4 / gap 4−1，primitive 是 dash 5 / gap 4，而 primitive 明确说这个节奏
   **不参数化**（「no call site has ever wanted a different rhythm」）。
   **建议换过去并接受 1px 的节奏变化** —— 那正是这个 primitive 的意义；要 PNG 对比确认。
3. **抽 widget 会改 rebuild 范围**（往好的方向）。这片要跑
   `flutter test test/screenshots/render_probe.dart` 前后对比，确认没变差。

**守护**：`optimizer_ask_user_ui_test.dart` · `optimizer_kb_edit_ui_test.dart` ·
`optimizer_kb_loop_ui_test.dart` · `optimizer_a2_frames_test.dart` + screenshot。

---

### 片 5 · `directory_tree_item.dart` 1593 → 4 个文件，顺手修一处错位

**查消费者时发现的错位**：`FolderDropFollower` 住在 `screens/workbench/` 的文件里，
**唯一使用者是 `screens/browser/widgets/browser_drag_chip.dart`**。它和
`FolderDropRejection` / `FolderDropFeedback` 是一组（一个进程级 `ValueNotifier` +
读它的 follower），依赖只有 `AppLocalizations` · `AppDragFollower` · `AppDragTone` ·
`AppCopyModifier` —— 全在 `core` / `l10n` / `widgets/drag` 里。

跨 workbench 和 browser 两个 feature 用，按 #288 的规则该上 `lib/widgets/`。去哪：

- **不去 `widgets/drag/`**：拒绝理由是文件夹语义（`intoItself` · `root` · `readOnly` ·
  `nameTaken`），设计系统不该知道这些，而且 `drag/` 的命名是 `App*`。
- **去 `widgets/files/`**（已有 `folder_group_header` · `folder_outline_bar` ·
  `thumbnail_fit_toggle`）。它不在设计系统白名单里，可以引 `widgets/drag/` 和 `l10n`。

代价：`FolderDropFeedback._post` / `._withdraw` 目前私有，由同文件的行调用。行留在
workbench，所以这两个要变 public（`post` / `withdraw`），doc 里写清「只有指针下的那一行
可以调，并且只有它能清」。

| 新文件 | 内容 | 原行 | ~行 |
|---|---|---|---|
| `widgets/files/folder_drop_feedback.dart` | `FolderDropRejection` + 标签扩展 + `FolderDropFeedback` + `FolderDropFollower` | 47–130 | 120 |
| `workbench/folder_tree_row.dart` | `TreeDisclosure` · `FolderTreeMetrics` · `FolderTreeRow` · `FolderTreeRowAction` · `_Pulsed` | 750–1247 | 500 |
| `workbench/folder_drop_targets.dart` | `_FolderDragChip` · `_DropNoteSlot` · `_CopyModifierListener` · `_MaybeDropTarget` | 1248–1593 | 350 |
| `workbench/directory_tree_item.dart` | `FolderDragPayload` · `FolderDropTone` · `DirectoryTreeItem` + State | 40–46 · 131–749 | 620 |

`FolderTreeRow` / `FolderTreeMetrics` / `TreeDisclosure` 只被 `folder_list.dart` 和
`workbench/widgets/result_tree_item.dart` 用，**两者都在 workbench 内**，所以按同一条规则留在原地，
只是拿到自己的文件。

**守护**：`rebuild_scope_test.dart` 的
*"a folder pulse reaches one tree row, not the browser"* 正好压住这块 +
`app_screens_file_browser_test.dart`。

---

### 片 6 · `model_edit_dialog.dart` 1497 → 按 section 抽

已有先例 —— `model_edit_controls.dart`（1166 行，本身也在 1000+ 名单上）、
`model_protocol_section.dart`、`protocol_section_form.dart` 就是这么抽出来的。

| 新文件 | 内容 | 原行 | ~行 |
|---|---|---|---|
| `model_edit_identity_section.dart` | 身份段 + id / channel / kind / 费用组四个字段 | 581–794 | 250 |
| `model_edit_capability_sections.dart` | 能力段 + agent 段 + reasoning 段 + `_reasoningLadder` | 795–860 · 1080–1208 · 1345–1379 | 240 |
| `model_edit_context_section.dart` | 上下文窗口段 + Specify 字段 | 912–1079 | 170 |
| `model_edit_provider_section.dart` | provider 段 + protocol 段 + `_streamIgnoredBy` | 1209–1344 · 1380–1431 | 190 |
| `model_edit_dialog.dart` | State + draft 字段 + 三种外壳（edit / phone / add）+ 头尾 + 双栏 + 预览 + `_confirmDelete` | 49–580 · 861–911 · 1432–1497 | 650 |

**难点**：所有 section 读写同一份 draft —— 三个 `TextEditingController` + 一个
`FocusNode` + `channelId` / `tag` / `feeGroupId` / `supportsStream` / `supportsStandard` /
`forceViewAllImages` / `reasoningEffort` / `enableWebSearch` / `contextMode` /
`wireProtocol` / `_pinBySurface` + 三个 `_*Touched`。两条路：

- **(a) 传一个 draft 对象 + `onChanged`** —— 改动局限在这一片
- (b) 把 draft 提成 `ChangeNotifier` —— 更干净，但动静大得多，而且 CLAUDE.md 的 state
  规则会把它拉进「共享状态该不该进 `state/`」的讨论

**建议 (a)**。真觉得不够再单独立项 (b)。

**覆盖是弱点**：只有 `app_screens_model_editor_test.dart`（screenshot，不断言）+
`model_edit_track_slider_test.dart`（打的是 `model_edit_controls`）。所以拆前先跑
`flutter test test/screenshots/app_screens_model_editor_test.dart` 存 PNG，拆完逐张比。

---

### 片 7 · `ai_rename_dialog.dart` 1510 → 先把业务逻辑还给 service

**这个文件里有一块本来就不该在 widget 里的东西。** `_RenameRow` · `_RowConflict` ·
`_ConflictChoice` · `_recomputeConflicts` · `_resolve` 是纯业务逻辑：判互相重名、
判大小写（`toLowerCase` 建 key）、`File(targetPath).exists()`、判「目标就是自己」
（`p.equals(targetPath, row.path)`）、skip 传播。CLAUDE.md：「Business logic belongs in
`lib/services/`, not in widgets or screens」。

而且这个文件**零测试覆盖**（`AiRenameDialog` 在 `test/` 里零引用；
`ai_rename_apply_test.dart` 打的是 `services/tasks/ai_rename_agent.dart`）。

所以这一片的价值一半在拆，一半在**把这块逻辑变成可测的**。顺序：先 service + 测试，
再抽 widget。

| | 内容 | 原行 | ~行 |
|---|---|---|---|
| `services/files/rename_plan.dart` | `RenameRow` + `RenameConflict` + `ConflictChoice` + `recomputeConflicts` + `resolve` | 50–100 · 285–330 | 200 |
| `test/rename_plan_test.dart` | **新增**：两行互相重名 · 只差大小写 · 目标已存在 · 目标就是自己（no-op）· skip 后冲突消失 · 自动改名取唯一名 | — | 新 |
| `browser/widgets/ai_rename_config_column.dart` | 配置列（147 行）+ `_NarrowConfigSummary` + 窄屏抽屉 | 469–643 · 1407–1510 | 280 |
| `browser/widgets/ai_rename_result_rows.dart` | `_GeneratingRow` · `_ResultRow`（189 行）· `_RowAction` · `_Caption` · `_CenteredScroll` | 1051–1406 | 360 |
| `ai_rename_dialog.dart` | State + `_generate` + build + filter / footer / empty / no-models | 101–468 · 644–1050 | 620 |

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
flutter test test/screenshots && diff -r /tmp/before-<片号> build/ui-screenshots
git diff -M25% --stat main...HEAD               # 看到的应该是 rename / 大块移动，不是重写
```

- PNG 对比对片 1–3、5 应当**字节级一致**；片 4 的 dashed 节奏和片 6、8 的 section 抽取
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
| 6 model_edit | **仅 screenshot（不断言）** | 靠 PNG 逐张对比 |
| 7 ai_rename | **零** | **本片补 `rename_plan_test.dart`** |
| 8 video | **零，连 screenshot 都没有** | **本片先补 screenshot** |

---

## 5. 顺手修的三件事（不要漏，它们是拆这几个文件的一半价值）

1. **片 4** — `_DashedOutlinePainter` 是 `widgets/ui/dashed_border.dart` 明确要消灭的那种
   拷贝的第四份。换成 `drawDashedRRect`。
2. **片 5** — `FolderDropFollower` 一组从 workbench 下到 `widgets/files/`：它的唯一
   使用者在 browser，住在 workbench 是错位。
3. **片 7** — 重命名冲突检测从 dialog 下到 `services/files/`，并第一次拥有测试。

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
