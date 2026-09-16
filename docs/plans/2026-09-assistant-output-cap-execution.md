# 执行文档：提示词助手输出上限（2026-09-16）

> 施工中的对照表。方案正文在 [`2026-09-assistant-output-cap.md`](2026-09-assistant-output-cap.md)；
> 这里只记「做什么、按什么顺序、怎么验收、做到哪了」。分支 `claude/assistant-output-cap`，
> **一片一个 commit**，commit 正文带片号；每期结束跑一次 code review 再进下一期。
> 执行完毕后两份文档一起退役（结论回写架构文档，台账记 commit）。

## 不变量（施工时逐条对照，偏离即停）

1. 新列只有两态：`null` = 不发、`> 0` = 发这个数。不做「无限」。
2. 协议读上限只经 `protocol.dart` 的 `outputCapFor(target, options)`；每个请求选项
   `options['maxTokens']` 优先于模型配置（探针要 1 个 token）。
3. ① 的字段名由 `VendorProfile.outputCapField` 声明；协议里不出现 `vendor.id ==`。
4. 不把上限并进 `ContextBudget`，不在请求层夹到 `window − occupied`；只在编辑器提示。
5. `finish_reason == 'length'` 且带工具调用时，**一个半截调用都不执行**；连续两次即停。
6. 每片：`flutter analyze` 零问题，`flutter test -x screenshots` 绿；涉及 l10n 的片四语同改并
   `dart tool/merge_l10n.dart && flutter gen-l10n`。
7. 分层：services 不读 AppState；`widgets/ui` 不引 model / service / state；错误卡跳转设置走注入
   （`onExpand` 那种），不让 widget 引 screen。

## 分片

### 第一期（A + B0 + B1 + B3）

| 片 | 内容 | 涉及文件 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | 数据与解析：v44 `llm_models.max_output_tokens`（onCreate + onUpgrade）、`LLMModel.maxOutputTokens`、`LLMModelConfig.maxOutputTokens`、resolver 透传、备份导入不剥该列 | `database_migrations.dart` · `database_service.dart`（dbVersion 44）· `models/llm_model.dart` · `llm_types.dart` · `llm_config_resolver.dart` | 现有 DB 测试绿；新建库与升级库都有该列 | ✅ 76dc19f |
| 2 | 线上：`outputCapFor`；① chat 按 `VendorProfile.outputCapField` 选名（官方 OpenAI / New API = `max_completion_tokens`，其余 `max_tokens`）；② `max_output_tokens`；③ `maxOutputTokens`；④ `outputCapFor ?? 8192`；C2 `parameters.max_tokens`；`_outputCap` 多读一级；探针走同一个口 | `protocols/protocol.dart` · `openai_chat_payload.dart` · `openai_responses_protocol.dart` · `gemini_payload.dart` · `anthropic_wire.dart` · `dashscope_chat_protocol.dart` · `vendors/vendor_profile.dart` · `vendors/vendors.dart` · `llm_dispatcher.dart` | `test/output_cap_payload_test.dart`：null 不发；数字发到正确字段；① 按 vendor 选名；④ 默认 8192、thinking budget 取一半随 cap 放大；`options['maxTokens']` 压过模型配置；`_outputCap` 顺序 | ✅ |
| 3 | 编辑器与卡片：`OutputCapScale`（六档）；「最大输出」区块（自动 / 指定 + 输入框 + 单排刻度 + 状态文案 + ≥ 上下文警告；图像/视频隐藏）；模型卡 chip；l10n 四语 | `services/catalogue/output_cap_scale.dart` · `widgets/models/model_edit/model_edit_output_cap.dart`（新 part）· `model_edit_dialog.dart` · `model_edit_layouts.dart` · `model_card.dart` · `l10n/src/*/models.arb` | `test/output_cap_scale_test.dart`；编辑器截图四宽度无溢出；保存 / 读回一致 | ✅ |
| 4 | B0 截断对策：`length` + 工具调用 → 不执行、每个调用配 `output_truncated` 结果；纯文本被截 → 条目打 `truncated` 标记 + 卡片尾部提示与跳转；连续两次即停；子代理同款 | `prompt_optimizer_agent.dart` · `assistant_tool_calls.dart` · `prompt_optimizer_session.dart`（条目标记）· `sub_agent_runner.dart` · `prompt_optimizer_view.dart`（尾部标记 + 注入的跳转）· l10n workbench | `test/optimizer_truncation_test.dart`：不执行、结果形状、两次即停、纯文本标记；子代理一条 | ✅ |
| 5 | B1 + B3：四个模式提示各加一句；压缩摘要不再要求重抄提示词，App 把最新版本接在摘要后 | `assistant_system_prompts.dart` · `assistant_context_window.dart` | `optimizer_compaction_test.dart` 加一条：摘要消息含最新提示词全文且与 staging 版本逐字相同 | ☐ |
| R1 | 第一期 code review（`/code-review`），修掉 CONFIRMED 项 | — | — | ☐ |

### 第二期

| 片 | 内容 | 涉及文件 | 验收 | 状态 |
|---|---|---|---|---|
| 6 | B4 子代理 note 限长；B5 编辑器在推理非默认且上限已指定时提示「思考计入上限」 | `assistant_system_prompts.dart` · `model_edit_output_cap.dart` · l10n | 文案存在；截图 | ☐ |
| 7 | 发现时预填：Anthropic `/v1/models` 的 `max_tokens`、OpenRouter `top_provider.max_completion_tokens`；只在列为 null 时写 | `model_discovery_service.dart` 及其消费方 | 单测：有值预填、已有用户值不覆盖 | ☐ |
| R2 | 第二期 code review | — | — | ☐ |

### 第三期

| 片 | 内容 | 涉及文件 | 验收 | 状态 |
|---|---|---|---|---|
| 8 | B2 按节写入：`write_knowledge_file` 加 `section` / `mode`；`KnowledgeBaseService.spliceSection`；拼好后仍走 `_stageKbEdit`；编辑与蒸馏提示更新 | `knowledge_base_service.dart` · `assistant_toolset.dart` · `assistant_tool_calls.dart` · `assistant_system_prompts.dart` | `test/knowledge_base_splice_test.dart`：层级、末节、重复标题取第一个、CRLF、找不到即报错 | ☐ |
| R3 | 第三期 code review | — | — | ☐ |

### 收尾

| 片 | 内容 | 状态 |
|---|---|---|
| 9 | 文档：`architecture/llm-three-layer.md`（输出上限一节）、`architecture/assistant-context.md`（截断对策、摘要注入）、CLAUDE.md map 若有新文件；台账加一行；两份方案文档退役 | ☐ |
| 10 | `bump-version`（minor：4.8.0）；push；开 PR | ☐ |

## 施工记录

（每片完成后在此追加一行：片号 · commit · 与计划的出入。）

- 片 1 · 76dc19f · v44 步骤加了 `_tableExists` 守卫（迁移测试会用没有 `llm_models` 的局部库跑到 44）。
- 片 2 · 五条 wire + `OutputCapField` + `_outputCap`。与计划一处出入：③ 的 `prepareGooglePayload` 没有 target，加了 `outputCap` 命名参数由协议传入（回落到裸 option，探针与抓取器不变）。既有 `probe_max_tokens_payload_test` 的 ① 断言改为按 vendor 声明的字段名——探针在官方 OpenAI 上从此不再发旧名。
- 片 3 · 编辑器区块 + 卡片 chip + 四语。与计划两处出入：刻度用既有的 `ModelEditTrackSlider`（推理档位那条，snap）而不是再写一个画条形 tick 的滑杆；输入框不带「档位」菜单（那个菜单绑死在九档上）。截图夹具 `gpt-5-chat` 种了 65536，编辑器与卡片截图能看到指定态。
- 片 4 · B0。`truncatedToolResult` 与 `maxTruncatedRounds` 放在 `sub_agent_runner.dart`（agent 库已引它，反向引会成环），两个循环共用；`LLMService.outputTokensOf` 去掉 `@visibleForTesting` 供助手报「在 N tokens 处被截」。跳转走 `PromptOptimizerChatView.onOpenModelSettings` 注入，workbench 直接开 `ModelEditDialog`。
