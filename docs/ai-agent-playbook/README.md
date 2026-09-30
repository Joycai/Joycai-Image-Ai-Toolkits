# AI Provider 协议层 + Agent/子代理体系 · 复用规范文档集

这套文档提炼自 simple-ai-writer（Tauri + React 桌面写作应用）的 AI 层实战：它同时对接
OpenAI Chat Completions、OpenAI Responses、Google Gemini generateContent、Anthropic Messages
四个协议族与大量第三方兼容中继（New API、OrcaRouter、OpenRouter、MiniMax、DeepSeek、千问、智谱、
火山方舟、xAI、Ollama、LM Studio…），并在统一 tool loop 之上实现了权限分级、审批通道、子代理委派与
长会话上下文管理。2026-08 起并入本仓库（Joycai Image AI Toolkits）的 vendor–protocol–model 路由重构与
千问 / MiniMax 图像、视频面的核对；2026-09 并入 ② Responses 族、中转站回显改写、工具按需加载、
火山方舟 Seedream（含流式与拆图层）、xAI 出图 / 视频计费实测、语音识别（来自 pyVideoTrans / subtitle_studio）。

> 本目录是**两个** skill 的 `references/` 快照（**2026-09-30 第四次同步**，对应
> `ai-agent-architecture` v2.1.0 的 2026-09-28 重组）：
> `ai-agent-architecture`（协议事实知识库：00–06、11、12、13、14、16、20、22、23、30、31、CHANGELOG）与
> `agent-runtime-architecture`（agent 层设计标准：07–10、11b、12b）。两者 2026-09 中旬起从一个 skill 拆成两个，
> 坑与路线图因此各有一份（11 / 11b，12 / 12b），编号全局唯一、互相引用。
> 这次同步的结构性变化：原 `15-vendor-index.md`（厂商索引）**已删除**，并入 `20-platform-matrix.md`
> （§0 协议族、§3 各节「正文所在」行）；新增四张结论矩阵（20 平台、22 模型能力、23 媒体、31 待核实）、
> 知识吸收协议（30）与改动日志（CHANGELOG）；正文各篇的小节号与坑号**没有变**，旧文档里的
> 「0N §x」「坑 N」引用继续有效。
> **不要在这里改**——有新事实先写回 skill（按 30 篇的流程），再整目录重新同步过来。
> 它描述**机制**，不描述本仓库的现状——本仓库怎么做的见 `../architecture/`。

文档以**通用规范**口吻撰写，可直接放进新项目的 `docs/` 作为搭建标准；关键处均标注
参考实现文件（simple-ai-writer、本仓库、subtitle_studio），迁移时可对照抄写接口与骨架。

## 文件地图：五层

每个文件只属于一层，每层只回答一类问题。找东西先定层，再定文件。

| 层 | 文件 | 回答什么 | 里面没有什么 |
| --- | --- | --- | --- |
| **流程** | [00](00-audit-playbook.md) 审查 · [12](12-migration-roadmap.md) 新增（协议层）· [12b](12b-agent-roadmap.md) 新增（agent 层）· [30](30-knowledge-ingestion.md) 写回 | 按什么步骤做 | 不复述事实 |
| **结论表** | [20](20-platform-matrix.md) 平台 · [22](22-model-capability-matrix.md) 模型 × 平台 × 面 · [23](23-media-matrix.md) 出图 / 视频 / ASR · [31](31-open-questions.md) 待核实 | 能不能、哪里静默、证据日期、正文在哪 | 每格只写记号 + 关键值 + 证据 + 指针，原因与报文在正文 |
| **正文** | 协议层 [01](01-provider-layering.md)–[06](06-errors-probing-observability.md)、媒体 [13](13-image-generation.md) / [14](14-video-generation.md) / [16](16-speech-recognition.md)；agent 层 [07](07-agent-runtime.md)–[10](10-context-management.md) | 报文、数值、原因、后果、对策——事实的唯一正文 | 不按厂商重复；厂商差异是同一小节里的对照表 |
| **反查** | [11](11-pitfalls.md) 协议层坑（1–18、54–223）· [11b](11b-agent-pitfalls.md) agent 层坑（19–53） | 现象 → 一句对策 → 指针 | 原因在正文 |
| **日志** | [CHANGELOG](CHANGELOG.md) | 知识库改动史（入口 A 实测 / B 审查 / C 文档 / D 口述 / M 整理） | — |

## 目录

### 0. 流程

| 篇 | 主题 | 一句话 |
| --- | --- | --- |
| [00](00-audit-playbook.md) | 审查一个项目的模型接入 | 盘点 → 覆盖矩阵 → 先查静默失败 → 证据等级 → 报告模板 |
| [12](12-migration-roadmap.md) | 新增支持的落地顺序与配方（协议层，阶段 0–3） | 第一步永远是先查 20 / 22 / 23 有没有现成事实 |
| [12b](12b-agent-roadmap.md) | Agent 体系分阶段路线图（阶段 4–9，依赖阶段 0–2） | — |
| [30](30-knowledge-ingestion.md) | 知识吸收协议 | 七字段齐全 → 决策树定位置 → 正文一处 + 矩阵格指针 → 推翻旧结论留痕不删 → 自检清单 → CHANGELOG 一行 |

### 结论表（先查这里）

| 篇 | 主题 | 一句话 |
| --- | --- | --- |
| [20](20-platform-matrix.md) | 平台表 | 平台 × 面 × 地址鉴权 × 目录可信度 × 对请求的手脚 × 计费报法；每家厂商的正文散在哪（原 15 篇的职责） |
| [22](22-model-capability-matrix.md) | 模型 × 平台 × 面 能力矩阵 | 思考 / 结构化 / 函数工具 / 服务端工具（§14 按工具专表）/ 多模态 / 上限；找不到的行 = 未测，不从相邻平台类推 |
| [23](23-media-matrix.md) | 出图 / 视频 / ASR 矩阵 | route × 平台 × 模型：请求怎么写、同步还是异步、怎么计费、哪些参数 400、哪些静默忽略 |
| [31](31-open-questions.md) | 待核实清单 | 知识库的负空间：没测的组合、证据不够的结论、超半年的旧事实；审查撞到一律写「待核实」 |

### A. 协议层（多家 AI API 的统一封装）

| 篇 | 主题 | 一句话 |
| --- | --- | --- |
| [01](01-provider-layering.md) | 分层模型与统一抽象 | L1 协议族 / L2 端点 / L3 模型 + 探测维；加一家供应商 = 加一行数据，不是加一个文件；中转站的渠道与上游也是作者声明的数据（§9） |
| [02](02-protocol-differences.md) | 四族协议差异对照 | §1 转置总对照表（四族 × 功能维度的字段形状）+ §1.1 非对话面与私有扩展；② Responses 单列 §7 |
| [03](03-reasoning.md) | 思考/推理统一处理 | 强度、取回、回传义务三分；「关闭」只是最低档的回退测法；第三方 ④ 面默认值与 `disabled` 三种结局（§3.5）；判想没想（§4.1） |
| [04](04-structured-output.md) | 结构化输出与降级链 | 强制 pseudo-tool → 收紧判据 → JSON mode 回退；`text.format` / `verbosity` |
| [05](05-tools-and-server-tools.md) | 工具协议与 server tools | tool_call 配对不变量；pause_turn 续跑循环；工具按需加载；服务端工具按模型放行、按请求丢弃 |
| [06](06-errors-probing-observability.md) | 错误、usage、探测与可观测性 | HTTP 200 ≠ 成功；上游报价怎么读；API 日志是兼容层第一调试工具；回显比对（`wireRewrites`）；付费实测纪律 |

### A′. 媒体生成与语音

| 篇 | 主题 | 一句话 |
| --- | --- | --- |
| [13](13-image-generation.md) | 图像生成与编辑 | 签名 URL 当场下载；已计费的只重试下载不重试生成；异步任务一个总 deadline；方舟流式与拆图层；xAI 质量档与 `cost_in_usd_ticks` |
| [14](14-video-generation.md) | 视频生成 | 任务 id 归调用方持久化；轮询可重试、提交不可重试；取消与过期；终态才有的报价与时长 |
| [16](16-speech-recognition.md) | 语音识别（ASR） | 三种线格式、时间码从哪来、静音切片、说话人分离、按步骤分类的错误、断点续跑 |

### B. Agent 体系（tool loop、工具系统、写入安全）

| 篇 | 主题 | 一句话 |
| --- | --- | --- |
| [07](07-agent-runtime.md) | tool loop、preset 与事件系统 | runtime 只做循环不做策略；出散文即完成；abort 也必须配平 |
| [08](08-tool-registry-and-write-safety.md) | 工具注册、权限分级与审批 | read / write-auto（备份先行）/ write-approval（Promise 挂起等卡片） |

### C. 子代理与长会话

| 篇 | 主题 | 一句话 |
| --- | --- | --- |
| [09](09-subagent.md) | 子代理机制 | 子代理只是一个工具；产出落盘，只回摘要+路径；路由=改工具集 |
| [10](10-context-management.md) | 工作区、压缩与会话持久化 | 记忆落盘 + 轮间折叠 + 轮内裁剪 + checkpoint 四层防线 |

### D. 横切

| 篇 | 主题 |
| --- | --- |
| [11](11-pitfalls.md) | 坑大全 · 协议层（坑 1–18、54–223；反查索引表：现象 → 对策 → 指针，原因段在正文） |
| [11b](11b-agent-pitfalls.md) | 坑大全 · Agent 部分（坑 19–53） |
| [CHANGELOG](CHANGELOG.md) | 知识库改动日志（新的在上面） |

设计层的计费（计费组 / 用量行快照 / 档位匹配 / 用量页）不在这套文档里，在 `llm-billing-model` skill；
渠道 / 线路 / 模型三层配置的产品形态在 `channel-route-model` skill；本套只记协议事实（06 §1、13 §7、14 §3）。

## 证据记法

一条事实靠不靠得住，看它从哪来、什么时候核实的。正文与矩阵统一用：

| 记法 | 含义 | 审查时怎么用 |
| --- | --- | --- |
| 【实测 YYYY-MM-DD】 | 真发过请求、看过响应（矩阵里另标样本量） | 可以直接据此判错 |
| 【文档 YYYY-MM】 | 官方文档或 API 参考页的口径 | 项目行为不一致时写「待核实」，并给出验证方法 |
| 【中继源码】 | 读中转站源码得出 | 只对那一类中转站成立 |
| 【实现】 | 某项目的代码这样写并在真实服务上用过，本库没独立复核报文 | 当线索用；判错前先实测 |
| ⚠ / 【未验】 | 推断，或文档含糊 | 不据此判错 |

矩阵格子另用结论记号：✅ 实测生效 ／ ❌ 拒绝且会响（带状态码）／ 🔇 **静默失败**（200 不生效、被丢、被改写）／
🔀 被中转站改写或劫持 ／ 📄 仅文档 ／ — 未测 ／ ⏳ 超半年待复核（列在 31 §4）。

## 体系鸟瞰

```
UI（面板 / 对话 / 各类 modal）
   │  以 TaskPreset 启动，提供回调（onEvent / onOutputText / requestApproval…）
   ▼
会话 store          审批三队列（proposal/plan/roundLimit，runId 作用域）
                    + chatHistory（wire 数组）/ turns（展示层）双层会话
   ▼
agent/runtime       runAgent：多轮 tool loop、trimHistory、checkpoint、round-limit、abort 配平
agent/registry      REGISTRY：工具定义 + access 分级 + 执行器；ToolContext 钩子
agent/presets       TaskPreset：tools / maxRounds / finishPolicy / scratchpad / serverTools
agent/subagent      delegate 工具：嵌套 runAgent，产出落盘 note，只回摘要+路径
agent/taskWorkspace .ai-writer/tasks/<id>/{task.md, notes/}：可暂停、可恢复的磁盘记忆
agent/compact       轮间折叠压缩（0.7 触发 / 0.45 目标，保 prompt cache）
   ▼
ai/index            streamCompletion：familyOf 分发 + 预检 + 日志接线
ai/{openai,gemini,anthropic}   每协议族一个 adapter（供应商是数据行，不是子类）
ai/reasoning        六档强度词汇、thinking 方言、思维链切分与回传载体
ai/conn             ConnOptions 配置收口（加字段 = 改一处）
```

## 六条贯穿性设计原则

比任何单条协议事实都耐用，全部文档反复引用：

1. **每协议族一个 adapter，供应商是数据行不是子类。** 只有「body 形状不同」才配一个
   枚举值；鉴权、默认值、私有字段全用配置数据表达。一家可以有多张脸，这也是数据；中转站上同一个
   模型 id 背后的几个后端渠道，同样是作者声明的数据，不是从 id 上猜的。（01 篇）
2. **最小公倍数发送、最大宽容接收。** 主动发出的每个字段都是某个中继可以 400 的字段；
   官方端点可乐观，兼容端点不行。（01/02/03 篇）
3. **凡跨轮回传的，原物整存。** thinking blocks、thoughtSignature、encrypted_content、
   reasoning 的字段名——「理解后重建」恰好丢掉的就是完整性校验依赖的那部分。载体带上 modelId，
   换模型时整组剥离。（03/05 篇）
4. **先问失败会不会响。** 会响的（400）靠错误驱动降级即可；不响的（静默降级/截断/忽略）
   必须主动验证，且只有这类才值得预先花设计预算。（03/06 篇）
5. **能力能声明就声明，只有数值才实测，出图永不探测。** 出图的每次探测都是一次真实计费。（06/13 篇）
6. **协议完整性是生死不变量。** 每个 tool_call 必有配对回复（abort 中途也要补桩）；
   history 即会话，一次畸形永久报废。（05/07 篇）

agent 层另有三条（runtime 只做循环、策略全在 preset 里；权限在工具执行器内执行；能力以「通道在不在」表达，
同一注册表在不同界面自动降级），见 07 / 08 篇。

## 如何使用这套文档

- **查「这个模型在这个平台这个面上能不能用、怎么用」**：先 [22](22-model-capability-matrix.md)（对话）/
  [23](23-media-matrix.md)（媒体）找到那一行，顺「详见」进正文；平台本身的事看 [20](20-platform-matrix.md)；
  命中 [31](31-open-questions.md) 的组合回答「待核实」。
- **审查一个项目**：按 [00](00-audit-playbook.md) 走，用 22 / 20 的结论格对照项目行为，用正文篇解释原因。
- **新项目起步**：读 [12](12-migration-roadmap.md)（协议层）再 [12b](12b-agent-roadmap.md)（agent 层），按阶段勾检查项。
- **只接一个协议族**：读 01/06 + 对应族在 02/03 中的列即可。
- **排查线上怪问题**：先查 [11](11-pitfalls.md) / [11b](11b-agent-pitfalls.md)——大部分「看起来成功其实失败」
  的现象都有先例。
- **有了新事实**：不在本目录改，按 [30](30-knowledge-ingestion.md) 写回 skill，再整目录同步。
- **对照源码**：参考实现均位于 simple-ai-writer 仓库的 `src/lib/ai/`、`src/lib/agent/`、
  `src/stores/`；本仓库的实现见 `../architecture/llm-three-layer.md`。
