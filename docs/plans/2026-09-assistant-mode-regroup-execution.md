# 提示词助手 · 模式重组（A3d）施工清单

设计稿：Claude Design `A3d 提示词助手-模式重组`（帧 4a–4f + 规格汇总）。
分支：`claude/prompt-assistant-design-review-39a2bd`。一片一个 commit，每片之后 code review 并修复，
最后一片后整体 review。

## 为什么做

三段开关「系统提示词｜知识库｜库编辑」把两个维度摊平了：**依据**（任务预设 vs 知识库）与
**用途**（出词 vs 维护）。重组为两级：第一级「任务预设｜知识库」，选中知识库后第二级
「用它来：出词｜维护」。`AssistantMode` 枚举、持久化、历史会话图标**不变**——两级开关只是三个旧值的另一种呈现。

| 两级 | 枚举值 |
|---|---|
| 任务预设 | `systemPrompt` |
| 知识库 · 出词 | `knowledgeBase` |
| 知识库 · 维护 | `knowledgeEdit` |

## 每片的闸

`flutter analyze` → No issues found! · `flutter test -x screenshots` 全绿 · 四语 l10n 同步 ·
截图 harness（`test/screenshots/app_screens_workbench_tabs_test.dart`）看过 390 / 834 / 1440。

## 切片

| # | 内容 | 主要文件 | 验收 | 状态 |
|---|---|---|---|---|
| 0 | 脚注文案纠正（`optSysPromptNoKb`） | `sys_prompt_card.dart`、四语 arb | 已在 `5913b2f` | ✅ |
| 1 | 两级开关 + 改名 + 徽标。开关移到列顶（模型卡之上）；第一级 tinted·expand·compact，第二级 plain + 11px「用它来」；知识库未配置时「知识库」段仍可点，落到未配置状态卡，第二级置灰；工具头徽标 =「任务预设 ·〈预设名〉」/「知识库 · 出词」/「知识库 · 维护」，去掉「· Agent」；切换确认改为带标题的对话框（取消｜开始新会话）。l10n：改 `optModeSystemPrompt`→任务预设、`optModeKnowledgeEdit`→维护；删 `optModeKnowledgeEditShort`、`optModeBadgeAgent`、`optModeSwitchConfirm` | `optimizer_config_panel.dart`、`prompt_optimizer_toolbar.dart`、`assistant_tab.dart`、`workbench_screen.dart`、`assistant_actions.dart` | 三态右栏与稿 4a 一致；250px 列宽不溢出；现有测试按新文案更新 | ✅ |
| 2 | 任务预设卡：折叠 + 内置项。选择器首项恒为内置「通用优化」（灰「内置」徽标）；说明行 = 预设正文首段去 markdown（不加库列）；披露行「查看 / 编辑指令」+ 右侧 mono「约 N tokens」，默认折叠，展开态按会话记（不持久化）；「未保存」徽标折叠时保留在标题行；内置项：锁 +「内置指令不可编辑」+「另存为预设…」；页脚「在提示词库中管理预设」；未保存时换预设先确认一次。删 `optSysPromptNone` | `optimizer_config/sys_prompt_card.dart`、`assistant_system_prompts.dart`（内置文案出口）、`assistant_actions.dart` | 稿 4b 五态；1440 下折叠态时间线与上下文卡进首屏 | ✅ |
| 3 | 分模式空状态。任务预设：标题 + 副标 + 2×2 预设砖（<600 单列；0 预设 → 内置 + 去新建）+「全部 N 个预设…」，点砖 = 选中不发送；出词 / 维护：标题 + 副标 + 三条示例，点示例 = 填入输入框不发送。删 `optEmptyChat` | `prompt_optimizer_view.dart`（+ part）、`assistant_tab.dart` | 稿 4c 三态 | ✅ |
| 4 | 维护左栏分段「文档 · N｜参考图 · N」（plain·28 高，默认文档）；其余模式无分段 | `optimizer_left_panel.dart` | 稿 4e；维护模式下参考图可见可管 | ⬜ |
| 5 | 出词⇄维护同会话。先读 `architecture/assistant-context.md`。`session.mode` 在知识库对内可变（`switchKnowledgeUse`，运行中 / 跨依据拒绝——UI 与 session 两层都拦）；`upsertSession` 回写 mode；对话里插分隔提示；写工具从下一轮起挂 / 卸；运行中第二级锁定；维护→出词后待确认改动仍可应答 | `prompt_optimizer_session.dart`、`assistant_session_repository.dart`、`workbench_ui_state.dart`、`assistant_actions.dart`、`prompt_optimizer_view.dart`、`assistant-context.md` | 单测：切换不换会话、运行中拒绝、跨依据拒绝、mode 落库并可恢复、切回出词后 `canWriteKnowledge` 为假；稿 4d | ⬜ |
| 6 | 收尾：整体 review 修复；本文退休、台账加行；bump version | `docs/plans/README.md`、`CLAUDE.md` 版本行 | — | ⬜ |

## 决策记录

1. **不加库列**：预设说明从正文首段派生（CLAUDE.md：不持久化可派生的列）。
2. **内置「通用优化」不是一条库记录**：`sysPromptTemplateId == null && 文本为空` 即内置；agent 侧本来就在没有模板时用内置底稿，UI 只是把它说出来。
3. **切换提示不进 history**：它是界面事实，模型从每轮重建的 system prompt 与工具表得知变化；恢复的会话不重现这条分隔线（与 `kbEdit` 卡恢复成 chip 同一取舍）。
4. **未配置状态卡沿用现有单按钮**（选文件夹 + 初始化在同一个流程里，`_handleScaffoldKb`），不拆成稿上的两个按钮——流程本身已经先问文件夹。

## 施工记录

（每片落地时补：与稿的出入、review 的发现与处置。）

### 片 1

- 运行中锁定提前到这一片：两级都锁（第一级切换会换掉正在跑的会话，与工具头「新会话」运行中禁用同理），并显示「助手回复中 · 模式已锁定」。`_handleAssistantModeChange` 自己也拦一次。
- 第二级「plain」落为 `AppSegmentStyle.raised`（设计系统里没有叫 plain 的样式；强调色已花在第一级）。
- 徽标文案由调用方拼好传入（`_assistantBadgeLabel`），工具头不再包一层；屏幕用 `context.select` 取它，换预设会重新量槽宽。
- review（5 条，修 4）：徽标在「无预设但有自写文本」时改称「自定义指令」；确认框关闭后重查运行态与会话身份；任务预设态运行中也显示锁定说明；手机面板里第一级按手指尺寸。留到片 5：出词⇄维护此时仍走跨依据确认框，文案不对题。

### 片 2

- 内置文案的出口是 `PromptOptimizerAgent.builtinPresetInstructions`，`_buildSystemPrompt` 的兜底改读它——面板显示的与实际发出的是同一个常量。
- 选内置 = `setOptimizerSysPromptTemplate(null, '')`：空串而非 null，null 表示「从没选过」，首次加载会据此选库里第一条。
- 第三态「自定义指令」：模板 id 指向已删的库记录、但编辑器里还有文本。可编辑，不能保存回去，只给「另存为预设…」。稿上没有这一态。
- 「另存为预设…」走提示词库自己的系统模板对话框（新增 `initialContent`），保存后自动选中新建的那条。
- 「在提示词库中管理预设」只跳到提示词库页面，**没有**落到「系统模板 · refiner」筛选：那一页的标签页与筛选是它自己的局部状态，没有外部入口。
- 展开态记在面板 State 上（面板活多久记多久），不是严格的「按会话」。
- 说明行派生函数 `presetSummaryOf` 单独成库并有测试。
- review（3 条，全修）：孤儿文本换预设同样先确认；丢弃确认补了测试；派生函数的正则提到库级。

### 片 3

- 预设砖与「全部 N 个预设…」从面板外部换预设，走同一个未保存确认：`confirmDiscardPresetEdit` 提成公开函数，屏幕侧 `_handlePickPreset` 自己算「有没有未保存」。
- 「全部 N 个预设…」在有预设时恒显示（不只在超过四个时）：它同时是回到内置预设的入口。
- 知识库未配置时输入框**没有**禁用：发送处原有的拦截（刷新状态 → snackbar）保留，空状态示例也仍可点。稿 4d 写的是禁用。
