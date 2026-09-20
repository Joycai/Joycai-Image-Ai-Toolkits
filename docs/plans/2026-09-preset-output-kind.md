# 任务预设 · 产出类型（A3e）

2026-09-20 立项。分支 `claude/preset-output-kind`，界面稿 `A3e 提示词助手-预设产出类型.dc.html`
（Claude Design 项目 `925a4d48…`）。执行完删本文件，结论记进 `docs/plans/README.md`。

## 1. 为什么

「任务预设」把预设正文放在 system 消息最前，后面接一段写死的框架
（`assistant_system_prompts.dart` 的 `_buildSystemPrompt`）。框架只认一种任务——
「用户给粗想法，你产出一条优化过的提示词，只能经 `submit_prompt` 交付，聊天文字要短」。

用户要写的另一类预设是**识别 / 提取 / 描述**：预设规定流程和输出结构，用户每轮说
「识别参考图 1」「结合图 1、2 描述服装结构」「补充以下信息…」。这类预设与框架三处相撞：

| 框架里的话 | 撞在哪 |
|---|---|
| `you produce a refined, high-quality prompt` | 预设说「提取信息」，三行后框架说「产出提示词」；弱模型会把识别结果硬写成生图提示词，或把「帮我识别图 1」当成待优化的粗想法 |
| `submit_prompt … the ONLY way to deliver` + `Keep chat text brief` | 结果进卡片则标题「提示词 v1」和「应用到工作台」语义不对；走正文则被压成两三句 |
| `never ask about details you can reasonably infer` | 识别任务里问清「只看服装还是连背景」反而是对的 |

已经对的不动：参考图角标数字 = `list_reference_images` 的 id；预设每轮现读；
用户输入是普通 user 消息；助手正文已经是 `MarkdownBody`（可选中）。

## 2. 裁决

1. **预设带一个产出类型**，两值：`prompt`（提示词，默认，现状）｜`analysis`（分析文本）。
   不新增模式，A3d 的两级结构不动。
2. **存在哪**：`system_prompts.output_kind TEXT NOT NULL DEFAULT 'prompt'`（v47）。
   只对 `type = refiner` 有意义；`rename` 行恒为 `prompt`，编辑框不显示该项。
   模型层是 `enum PresetOutputKind { prompt, analysis }`（`models/prompt.dart`），
   库里存 `name`，读到不认识的值回落 `prompt`。
3. **怎么到 agent**：和预设正文同路——面板状态 → 任务参数 → `runTurn`。
   `WorkbenchUIState.optPresetOutputKind` 与 `optSysPromptTemplateId` 同时由
   `setOptimizerSysPromptTemplate` 写入；入队时 `'outputKind': kind.name`；
   `runTurn(outputKind:)` → `_systemPromptFor` → `_buildSystemPrompt`。
   - 内置预设 = `prompt`。
   - 面板里改了正文、没存：类型跟着已载入的那条走。
   - 库里的行被删（徽标显示「自定义」）：类型保留最后载入的值——正文还是那份，换类型才是意外。
   - 面板**不提供**改类型的开关：类型是预设的属性，改它去提示词库（「管理预设」已直达）。
4. **框架怎么分叉**（只有 `analysis` 变，`prompt` 一字不改——有测试钉住）：
   - 任务句改中性：按上面的说明完成用户的请求；用户消息是请求本身，不是待优化的提示词。
   - 交付：**完整结果直接写在正文**，按预设规定的结构，用 Markdown；不受「聊天文字要短」约束。
   - `submit_prompt` 留在工具集里但降为可选：仅当用户明确要一条可用于生成的提示词时才调。
     留着的理由：「识别完，顺手给我一条反推提示词」是自然的下一句，删掉工具就得换预设重开会话。
   - `ask_user`：范围真不清楚时可以问（看哪张图、提取哪一层），仍然一轮至多一次。
   - `_terseDeliveryNote` 换成只留后半句的版本：同一份内容不要正文写一遍、工具里再写一遍。
   - `_feedbackRoundNote` 保留（只有交过提示词才会触发，无害）。
   - 参考图查看步骤、`forceViewAllImages` 的强制条款：两种类型共用，措辞里的
     「before calling submit_prompt」在 `analysis` 下改成「before answering」。
5. **结果怎么认**：`analysis` 轮里，结束本轮的那条助手正文就是交付物。agent 给这条
   `LLMMessage` 打 `deliverable: true`（对话记录是从 history 重建的，所以标记和
   `truncated` 一样落在消息上、只在为真时写进 JSON；`OptimizerChatEntry.deliverable` 由它带出）。
   最后一轮（步数用尽的状态汇报）与知识库会话不打。
   界面只对它显示「复制」动作行。不做版本号、不做「应用到工作台」。
6. **看不到图要在对话里说**（两种类型都生效，但这一轮是因为识别场景才变致命）：
   模型不接受图片输入且本轮带了参考图时，除了现有的任务日志，再往对话里放一张
   notice（`imagesNotOfferedNoticeToken`）。同一会话、同一模型只说一次——判据是
   transcript 里上一张同 token 的 notice 的 `modelDbId` 与本轮相同就不再放。
7. **导入导出**：`prompts_io` 的 `toMap` 带上 `output_kind`；旧文件没有该键 → `prompt`。
   整库备份按表走，随 v47 自动带上。

### 明确不做

- 不给 `analysis` 单独的交付工具（`submit_result`）、不做结果版本、不做结果卡片。
- 不按类型裁剪工具集。
- 知识库模式不受影响（它不读预设）。
- 不在面板里临时切类型。

## 3. 界面（先出稿，再动手）

稿件 `A3e`，帧号 5a–5g + 规格汇总，全部用 `App*` 词汇：

| 帧 | 内容 |
|---|---|
| 5a | 提示词库 · 系统模板编辑框：类型分段下方加「产出」分段（提示词｜分析文本），仅 refiner 显示；切到 rename 时该行收起 |
| 5b | 提示词库 · 系统模板列表行：`analysis` 行的类型标记旁多一个次级标记；`prompt` 行不加（默认不说话） |
| 5c | 助手右面板 · 任务预设卡：摘要行下多一行「产出 · 分析文本」，只读；选择器行尾同样标记 |
| 5d | 空对话 · 预设磁贴带产出标记；载入 `analysis` 预设时示例句与输入框占位换一组 |
| 5e | 对话 · 分析结果：助手正文（Markdown）+ 尾部「复制」动作行；同一会话里随后一张可选的提示词卡 |
| 5f | 对话 · 「这个模型看不到图」notice，带「换模型」入口 |
| 5g | 手机宽度：5a 的编辑框与 5e 的结果 |

## 4. 执行清单（一片一提交，两道门全绿再提交）

- [x] **片 0 · 稿与清单**：本文件 + `A3e` 推到设计项目。`docs:` 提交。
- [x] **片 1 · 数据**：`PresetOutputKind`；`SystemPrompt.outputKind`（`fromMap`/`toMap`）；
      v47 `onUpgrade` 加列 + `onCreate` 同步；`dbVersion = 47`；`prompts_io` 往返。
      测：迁移后旧行为 `prompt`；未知值回落；导出再导入保类型；缺键文件导入为 `prompt`。
- [x] **片 2 · agent**：`_buildSystemPrompt(outputKind:)` 分叉；`runTurn`/`_systemPromptFor`
      传参；`task_executors` 读 `parameters['outputKind']`；`deliverable` 标记与序列化。
      测：`prompt` 类型的 system prompt 与改动前逐字相同（golden 字符串）；`analysis` 不含
      `ONLY way`、`Keep chat text brief`，含预设正文在最前；`analysis` 轮的收尾正文
      `deliverable == true`，`prompt` 轮为 false；知识库两种用途的 prompt 不变。
- [x] **片 3 · 状态与入队**：`WorkbenchUIState.optPresetOutputKind`（新对象/新值后再
      `notifyListeners`）；`_handlePickPreset`、面板选择器、库行被删三条路径；入队参数。
      测：载入 / 换内置 / 改正文未存 / 库行删除 四种情形下入队的 `outputKind`。
- [ ] **片 4 · 提示词库界面**（5a、5b、5g）：编辑框分段、列表标记；l10n 四语。
      测：refiner 才显示分段；保存写库；rename 保存恒 `prompt`；390 宽不溢出。
- [ ] **片 5 · 助手界面**（5c、5d、5e、5g）：预设卡产出行、选择器与磁贴标记、示例句与
      占位、结果「复制」行；l10n 四语。
      测：`deliverable` 才有复制行；复制内容是 Markdown 原文；`rebuild_scope_test` 不回退。
- [ ] **片 6 · 看不到图的 notice**（5f）：token、去重判据、渲染、l10n 四语。
      测：文本模型 + 有图 → 一张；同模型第二轮不再放；换模型后再放；无图不放。
- [ ] **片 7 · 收尾**：截图 harness 给 `analysis` 会话加一组 seed；`/code-review high` 并修；
      `architecture/assistant-context.md` 若提到框架文本则补一句；本文件删除，
      `docs/plans/README.md` 记「已执行」与出入；bump（minor → 4.20.0）；PR。

## 5. 风险

- **golden 字符串**会让以后任何对 `prompt` 框架的措辞调整都要改测试——这是有意的：
  这一轮承诺的就是「现有预设行为不变」。
- `analysis` 的框架措辞只能靠真实模型验证。片 2 完成后用一条识别预设 + 两张参考图，
  在一个强模型和一个本地小模型上各跑你给的三句话，结果记进 PR 描述。
- `deliverable` 的判定是「本轮收尾的正文」，紧跟在一次 `submit_prompt` 之后的那句不算
  （片 2 审查时补的：同一判据也收紧了 analysis 轮的「空回复可以收尾」）。
