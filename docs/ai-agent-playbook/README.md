# AI Provider 协议层 + Agent/子代理体系 · 复用规范文档集

这套文档提炼自 simple-ai-writer（Tauri + React 桌面写作应用）的 AI 层实战：它同时对接
OpenAI Chat Completions、Google Gemini generateContent、Anthropic Messages 三个协议族与
大量第三方兼容中继（New API、MiniMax、DeepSeek、OpenRouter、Ollama、LM Studio…），并在
统一 tool loop 之上实现了权限分级、审批通道、子代理委派与长会话上下文管理。

文档以**通用规范**口吻撰写，可直接放进新项目的 `docs/` 作为搭建标准；关键处均标注
simple-ai-writer 的参考实现文件，迁移时可对照抄写接口与骨架。

## 目录

### A. 协议层（多家 AI API 的统一封装）

| 篇 | 主题 | 一句话 |
| --- | --- | --- |
| [01](01-provider-layering.md) | 分层模型与统一抽象 | L1 协议族 / L2 端点 / L3 模型 + 探测维；加一家供应商 = 加一行数据，不是加一个文件 |
| [02](02-protocol-differences.md) | 三家协议差异对照 | 消息/工具/流式/鉴权/URL 的逐字段对照表与适配器转换规则 |
| [03](03-reasoning.md) | 思考/推理统一处理 | 强度、取回、回传义务三分；跨轮回传的东西原物整存 |
| [04](04-structured-output.md) | 结构化输出与降级链 | 强制 pseudo-tool → 收紧判据 → JSON mode 回退 |
| [05](05-tools-and-server-tools.md) | 工具协议与 server tools | tool_call 配对不变量；pause_turn 续跑循环 |
| [06](06-errors-probing-observability.md) | 错误、usage、探测与可观测性 | HTTP 200 ≠ 成功；API 日志是兼容层第一调试工具 |

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
| [11](11-pitfalls.md) | 坑大全（现象 → 原因 → 对策，按危险程度与主题分组） |
| [12](12-migration-roadmap.md) | 分阶段落地路线图（按依赖顺序的最小实现清单） |

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
   枚举值；鉴权、默认值、私有字段全用配置数据表达。（01 篇）
2. **最小公倍数发送、最大宽容接收。** 主动发出的每个字段都是某个中继可以 400 的字段；
   官方端点可乐观，兼容端点不行。（01/02/03 篇）
3. **凡跨轮回传的，原物整存。** thinking blocks、thoughtSignature、encrypted_content、
   reasoning 的字段名——「理解后重建」恰好丢掉的就是完整性校验依赖的那部分。（03/05 篇）
4. **先问失败会不会响。** 会响的（400）靠错误驱动降级即可；不响的（静默降级/截断/忽略）
   必须主动验证，且只有这类才值得预先花设计预算。（03/06 篇）
5. **runtime 只做循环，策略全在数据（preset）里；权限不在 runtime 执行，在工具执行器
   内执行；能力以「通道在不在」表达。** 同一注册表在不同界面自动降级。（07/08 篇）
6. **协议完整性是生死不变量。** 每个 tool_call 必有配对回复（abort 中途也要补桩）；
   history 即会话，一次畸形永久报废。（05/07 篇）

## 如何使用这套文档

- **新项目起步**：直接读 [12 落地路线图](12-migration-roadmap.md)，按阶段勾检查项；
  每个阶段的细节回到对应主题篇。
- **只接一个协议族**：读 01/06 + 对应族在 02/03 中的列即可。
- **排查线上怪问题**：先查 [11 坑大全](11-pitfalls.md)——大部分「看起来成功其实失败」
  的现象都有先例。
- **对照源码**：参考实现均位于 simple-ai-writer 仓库的 `src/lib/ai/`、`src/lib/agent/`、
  `src/stores/`；设计文档见其 `docs/`（provider-standards、subagent-lld、
  unified-agent-plan 等）。
