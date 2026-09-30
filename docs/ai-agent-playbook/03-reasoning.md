# 03 · 思考/推理的统一处理

> 本篇解决的问题：把各家"thinking / reasoning"支持拆解成三件可以独立设计的事——**强度**（请求怎么说"想多久"）、**思维链取回**（响应怎么给你看）、**回传义务**（下一轮要不要还回去），并给出每一件的三族实现规范。
> 不读会踩的坑：回传义务是唯一会让请求被拒的一件，却最少被文档放在显眼处——Anthropic 不回传 thinking block 是**静默**关闭思考（无任何报错）；Gemini 丢 thoughtSignature 是 HTTP 200 + 特殊 finishReason（3.8 Flash 上 functionCall 缺签名则直接 HTTP 400，§5）；DeepSeek 系不回传直接 400。三种失败模式完全不同，排查方式也不同。另外：`<think>` 标签混进正文、`display` 默认 omitted 付全额思考费拿不到一个字、换模型不剥 thinking block 静默计费。

出处：simple-ai-writer `src/lib/ai/reasoning.ts`（词汇、翻译表、切分器）、三个适配器的接线、设计文档 `docs/api/reasoning-plan.md` / `docs/api/anthropic-plan.md` / `docs/api/gemini-plan.md`。

目录：
- §1 三分法：强度 / 取回 / 回传义务
- §2 强度：自有六档词汇 + 每族翻译表（§2.1「关闭」只是最低档时：回退要既发 off 又带一句提示）
- §3 ThinkingDialect：代次差异由作者声明，不猜（§3.1 智谱 GLM、§3.2 火山方舟豆包：三面控制、思考摘要与加密原文、§3.3 中转站上的 Claude：① `max` = 不想是转换层的；④ 思考随渠道——Kiro effort 只有 low 生效、anti 不想、CC opus-5 空文本、Bedrock 真分档 · §3.4 ④ 开关型方言关思考时的温度：火山方舟听（`0` 等于没发）、MiniMax 不听；事实挂在类目上 · §3.5 第三方 ④ 面：思考默认值与 `disabled` 三种结局按平台 × 模型；未知字段／非法思考值四家四种）
- §4 思维链的流式暴露：三族三种读法，统一产出 `{reasoning}` chunk（§4.1 判「想没想」看文本或签名，至少一个非空）
- §5 回传义务：三族三种载体、三种失败模式
- §6 `<think>` 标签兜底切分器
- §7 ② Responses 族：强度 / 取回 / 回传（§7.4 中转站上的 GPT：账号池真分档、`none` 在 ② 上哪都关不掉，① `none` 只在网关上生效）

---

## 1. 三分法：强度 / 取回 / 回传义务

规范的第一条是概念拆分。三件事各自独立变化，混在一个"thinking 开关"里必然顾此失彼：

| | 问题 | 谁定义 | 失败方式 |
| --- | --- | --- | --- |
| 强度 | 请求体里怎么表达"想多久" | 每族一套字段与枚举 | 发了对面不认的档位 → 400 |
| 取回 | 思维链在响应流的哪里 | 每族一个读取位置 | 读不到（少看一段），或混进正文（严重） |
| 回传义务 | 工具轮历史要不要携带思考物 | 每族一种载体 | **三族三种**：400 / 特殊 finishReason / 静默降级 |

## 2. 强度：自有六档词汇 + 每族翻译表

```text
ReasoningEffort = default | off | low | medium | high | max
```

核心原则：**配置层存储的是本项目自己的词汇，绝不让某一家的拼写进配置层。** 各家档位名"像但语义不像"是陷阱：DeepSeek 的 medium 被折进 high；`minimal`/`none` 有的模型 400；Gemini 要 token 预算/level 不要档位名。

`"default"`/缺省的语义是 **一个字段都不发**，让端点用自己的默认——"任何主动发出的字段都是某个中继可以拒绝的字段"。

翻译表（`reasoningBody(standard, effort, dialect)`）：

| 本项目档位 | ① OpenAI 系 `reasoning_effort` | ③ Gemini `generationConfig.thinkingConfig.thinkingLevel` | ④ Anthropic `output_config.effort` |
| --- | --- | --- | --- |
| off | `"none"` | `"LOW"`（③ 关不掉，降级为所有型号都收的最低档；**2026-09-26 前写的是 `MINIMAL`**，3.8 Flash 对它 400，见下） | `"low"`（disabled 会被多款模型 400，官方也建议降 effort 而非关；【实测 2026-09-26】Opus 5.5 / Fable 5.1 对 `thinking:{type:"disabled"}` 回 400 `requires adaptive thinking; omit thinking or use thinking.type=adaptive and output_config.effort`） |
| low/medium/high | 同名 | `LOW/MEDIUM/HIGH`（**全大写**！小写 `thinking_level` 属于另一个 surface：Interactions API；值本身小写 `"low"` 在 AI Studio 也收【实测 2026-09-28】，见下） | 同名 |
| max | `"max"` | `"HIGH"`（枚举到头） | `"max"` |

必须写进实现的细节：

- ③ 发 level 时**强制搭配 `includeThoughts: true`**——思考横竖在跑、横竖计费，这个开关只决定你能不能看见；只调深度不开显示等于"付钱买看不见的思考"。
- ③ 的旧字段 `thinkingBudget` 与新字段 `thinkingLevel` 并存于同一对象，靠"用错模型报错"区分。规则：**只发一代字段**，选目标支持范围对应的那代（参考实现支持 Gemini 3 起，只发 level）。
  【实测 2026-09-26，3.8 Flash 经 OrcaRouter】`thinkingBudget` 仍被接受，但 **`thinkingBudget: 0` 照样思考**（312 token）——网关会重新序列化请求（第 1 篇 §9.5），可能是它把 `0` 当空值丢了，所以只能说「经那台网关关不掉」；无论哪种，都不能拿它代替缺席的 `minimal`。
- **③ 的 `MINIMAL` 不是每个型号都有，缺的时候是 400 而不是降级。**【实测 2026-09-26，3.8 Flash（Vertex）经 OrcaRouter】400 `Thinking level MINIMAL is not supported for this model.`（枚举由上游校验，报文是 Vertex 原文）；【文档】3.1 Pro 的档位也只有 `low/medium/high`。`minimal` 本来也不等于关闭（文档：*does not guarantee that thinking is off*）。所以「关闭 / 尽量少想」要映射到**每个型号都收的最低档 `LOW`**：多想几百 token 是便宜的一边，报错是最坏的一边。同题 `thoughtsTokenCount`：`LOW` 193 / `MEDIUM` 641 / `HIGH` 1,348（单调），不发时 685（单次采样）。
- **③ 的档位值小写也收，运行时不分大小写；会 400 的是枚举外的值。**【实测 2026-09-28，Google AI Studio 官方直连 `generateContent`，gemini-3-flash-preview / gemini-3.8-flash，同一道一词题】`"low"` 与 `"LOW"` 都 200。
  gemini-3-flash-preview 上思考 token 落在同一范围（小写几次 19–41，大写三次 21–72，随机波动）；gemini-3.8-flash 两种写法各一次，usage **都不带 `thoughtsTokenCount`**（`low` 答一个词时）。
  `"lowest"` → 400 `Invalid value at 'generation_config.thinking_config.thinking_level' (type.googleapis.com/google.ai.generativelanguage.v1beta.ThinkingConfig.ThinkingLevel), "lowest"`，`details[].fieldViolations[].field` 同名。
  参考页只列大写（`THINKING_LEVEL_UNSPECIFIED` / `MINIMAL` / `LOW` / `MEDIUM` / `HIGH`）。**发小写不算错，审查时别据此判错**；照参考页发大写仍是稳妥写法。这是本库第一条 AI Studio 直连实测（此前 3.8 Flash 全部经 OrcaRouter 即 Vertex）；`MINIMAL` 400、`thinkingBudget:0`、内置工具在 AI Studio 上仍未直验（31 OQ-021）。
- ④ 的 `output_config.effort` 管的是**整个回复**（正文 + 工具调用 + 思考），不只思考深度。UI 上仍然只放一个拨盘，变的是标签——因为没有任何端点把"回复深度"与"思考深度"作为两个独立输入暴露，两个拨盘 = 两个控件写一个值。
- **① 的 off = `"none"` 不是全族通用的关闭**：DeepSeek 的档位表没有 `none`，发了被无视、照想照计费，只有顶层 `thinking:{type:"disabled"}` 关得掉【文档 2026-08；Joycai 2026-09-05 按文档修复，未实测】；GLM 各代见 §3.1，火山方舟见 §3.2（在那里 `none` 实测关得掉）。所以「关」是按厂商声明的方言，不是一个族级常量。
- 私有方言开关（DeepSeek 的 `thinking:{type}`、千问的 `enable_thinking`）**默认不发**——OpenAI 官方端点对未知顶层字段直接拒绝，为一家的方言破坏官方路径不值。唯一的例外是作者在模型上**声明了 `switch` 方言**（见 §3）：那时该字段就是这个端点的思考词汇，改发它并停发 `reasoning_effort`。未声明方言的默认路径必须一个字节不变。

### 2.1 「关闭」只是最低档时：要它少想，发 off 还要带一句提示（2026-09-28）

上表里 ③ 的 off 是 `thinkingLevel:"LOW"`、④ 的 off 是 adaptive + `effort:"low"`——线上**没有真正的关**。把这件事做成思考方言 / 类目上的一个数据字段
`offSpelling: "disable" | "lowest"`（真关 / 落到最低档），凡是「想让它少想」的地方都读它，不按族名判断。

碰到它的典型场景是 agent 的思考护栏（agent-runtime-architecture）：一轮思考吃掉窗口剩余的一半就中止，余下的请求「关思考」重发。
【实测 2026-09-28，经 OrcaRouter，回包原样；simple-ai-writer landscape.md 第十八个样本「思考回退补测」】一道计数题（只答数字），每格 5 次，
输出 token（含思考）中位数，括号里是答对次数；「提示」= 一句「不要展开思考，直接调用工具或给出回答」：

| | 不设 | 高 | 关闭（= 低） | 高 + 提示 | 关闭 + 提示 |
| --- | --- | --- | --- | --- | --- |
| Claude Sonnet 5（④ adaptive） | 6,962（5/5） | 6,825（5/5） | 2,270（5/5） | 1,090（5/5） | 1,396（4/5） |
| Gemini 3.8 Flash（③） | 1,980（5/5） | 4,973（5/5） | 1,977（5/5） | 1,830（**3/5**） | 1,300（5/5） |

- **Gemini 不设档位时本来就在最低档附近**：不设 1,980 与「关闭」1,977 分不开。一行没设档位的 Gemini 被护栏中止后，只发 off 的回退和被中止的那次一样想。Claude 不设 ≈ 高，「关闭」省约三分之二。
- **只换提示、保留作者的档位，效果是两极的**：两家都出现 1–3 个输出 token、直接报数的回答（Claude 高 + 提示 1 次、关闭 + 提示 2 次；Gemini 高 + 提示 2 次）；
  Claude 那几次都答对，Gemini 那两次都答错。其余几次照常思考，只是短一些。
- **关闭 + 提示两家都最省**（1,396 / 1,300），正确率 4/5、5/5；Claude 答错的那次是想过的，不是跳过思考的那两次。
- 花费 Claude $0.94、Gemini $0.23（网关报价）。一道题、每格 5 次，只看方向。

做法：`offSpelling:"lowest"` 的类目**既发 off 又带提示**；真能关的（`disable`）只发 off；菜单里根本没有「关闭」的只带提示。提示发完即撤，执行日志记成单独一种恢复（「压到最低档」≠「关掉」）。
off 照发意味着作者点得到的值没被换掉，只是多一句话——所以「作者选了 off 就该是 off」的反对理由在这里不成立。

## 3. ThinkingDialect：代次差异由作者声明，不猜

思考参数**换代改形、换厂改拼**，且**代次无法从模型 id 恢复**——中继上模型 id 是作者输入的自由文本（如 `特价kiro | claude-opus-4-6-thinking`）。因此方言做成 **L3 模型字段由作者声明**，不做探测、不做猜测启发式。

关键的建模决定：**方言值是跨族的"参数形状"词汇，族决定拼法**。`extended` 同时描述 Claude ≤4.5 与 Gemini 2.5；`switch` 同时描述 MiniMax-M3 的 ④ 族端点与千问 DashScope 的 ① 族端点——写侧函数先按族分派、再看方言，同一个值在不同族拼出不同字段。这让"支持下一家的开关型端点"不需要新增枚举值、不动 parse 白名单、不动存储列：

ThinkingDialect = `adaptive | extended | switch | none`，各族发出的 body 片段：

| 方言 | ④ Anthropic 发出 | ① OpenAI 系发出 |
| --- | --- | --- |
| `adaptive` | `{"thinking":{"type":"adaptive","display":"summarized"}}` | `{"reasoning_effort": …}` |
| `extended` | `{"thinking":{"type":"enabled","budget_tokens":N,"display":"summarized"}}` | `{"reasoning_effort": …}` |
| `switch` | 关：`{"thinking":{"type":"disabled"}}`；其余：`{"thinking":{"type":"adaptive"}}` | `{"enable_thinking": effort ≠ off}`，**且不发** `reasoning_effort` |
| `none` / 未声明 | 不发 `thinking` | `{"reasoning_effort": …}`，与未引入方言时逐字节相同 |

四种方言的语义：

- **`adaptive`**（Claude 4.6+）：`display:"summarized"` **必须显式发**——当前代默认 `"omitted"`，返回的 thinking block 文本为空串但**照全额计费**（omitted 省的是延迟不是钱）。
  【实测 2026-09-26，Sonnet 5 / Opus 5.5 经 OrcaRouter，回包 Anthropic 原样】**不发 `thinking` 也在思考**（adaptive 是默认；Sonnet 5 一题 141 思考 token），回来的 thinking block 文本空、只有签名——即连「跟随默认」档都在付思考费；显式 `summarized` 才有文本。思考量单独报在 `usage.output_tokens_details.thinking_tokens`，是 `output_tokens` 的**子集**（06 §1）。`output_config.effort` 的 `low`–`max` 都收，adaptive 下低档常直接不想（`low` 0 思考 token），单次采样噪声大、看不出单调；`thinking:{type:"enabled", budget_tokens}` 在 Sonnet 5 上也 200、照样思考。Fable 5.1 那一题没思考。
- **`extended`**（Claude ≤4.5；Gemini 2.5 同形）：固定 token 预算。预算钳制：`Math.max(1024, Math.min(16384, maxTokens/2))`——budget 必须 < max_tokens（二者共享一个上限，预算贴顶 = 正文没地方存在）。
- **`switch`**（为"只有纯开关"的端点建，每族一种拼法）：声明此方言同时意味着"该端点没有深度拨盘"——effort 唯一的用途是区分「关」与「其余」（其余一律开）。两个真实样本：
  - **④ 族拼法**（MiniMax-M3 的 `/anthropic/v1/messages`）：只有 `{type:"adaptive"|"disabled"}`，无 `display`、无 `output_config`——`reasoningBody` 对它返回 undefined。schema 没有的字段（如 display）不发——兼容层"忽略未知键"与"400 未知键"一样常见，文档没写的不发。
    关思考时发不发 `temperature`：同一个拼法，MiniMax 与火山方舟 ④ 结论相反，见 §3.4。
  - **① 族拼法**（千问 DashScope compatible-mode）：顶层 `enable_thinking: bool`（官方 SDK 示例写在 `extra_body`，那只是 OpenAI SDK 的透传机制——落到 wire 就是 body 顶层字段）。声明后**停发 `reasoning_effort`**：千问文档写明它与 `thinking_budget` 互斥，且"声明 switch"本身就是"此端点没有深度档"的陈述。`thinking_budget` 刻意不接——没有 UI 载体的字段只会变成噪音（与 ③ 的 thinkingBudget 同一判断）。另一条联动：千问文档明载**思考开启时 `tool_choice` 只接受 `auto|none`**，forced 的降级条件见 04 篇 §4。
  - 两个样本共同的动机：这些端点上思考对相当一部分模型**默认关**（旧：MiniMax-M3 全部 → 新：MiniMax ④ 面按型号——M3 默认关且 `disabled` 真关，M2.7 默认想、`disabled` 收下照想，2026-09-28 实测，见 §3.5；千问的 Qwen3-Max/Plus 等商业款——Qwen3.5+/3.7+ 则默认开），不发开关就永不思考。千问的附加事实：新款 Qwen3.7+ 直接接受标准 `reasoning_effort`（与 budget 互斥），**不必声明方言**；部分开源模型思考模式强制 `stream: true`。同一端点、两代模型、两套控制字段——"默认值要按模型代问"的又一实例。
- **`none`**：不发任何 thinking 字段。

**缺省方言的猜测规则**：anthropic 族猜 `adaptive`，其他族 `none`。乐观猜的理由：对支持范围（4.6+）全对；错的方式是旧模型 400 且报出字段名——比默认"不思考"让作者纳闷"我的推理模型怎么从不推理"好得多。原则：**乐观猜测只在"错的方式会响"时使用**。注意 ① 族的缺省语义不是"不发"：openai 分支对未声明方言的模型照走标准 `reasoning_effort` 路径——所以 ① 族适配器把**作者声明的原值**传给写侧函数即可，不要先过缺省替换。

### 3.1 一家三代三种控制：智谱 GLM（2026-09-19 实测全部 11 款）

同一个 ① 族端点、同一家的模型，思考控制分三种，而且三种都**默认开**。按族默认发 `reasoning_effort` 在每一代上都错：

| 代 | 关 | 深度 | 陷阱 |
| --- | --- | --- | --- |
| glm-5.3 / 5.3-flash / 5.3-flashx | **不能关**：`thinking:{type:"disabled"}` 400 | `reasoning_effort` 只收 `low/high/max`，真分档（同一道题 ~30 / 50 / ~120 推理 token） | 其余值（含 `none`、`medium`）400，文案一律是「不支持关闭思考」，不指向出错的值 |
| glm-5.2 | `thinking:{type:"disabled"}` | 七值都收（乱写 400）；`low/medium` 折成 high、`xhigh` 折成 max——实有两档，`max` 多想 ~35% | **`reasoning_effort:"none"` 关不掉**（与 `low` 想得一样多），文档却说 none 放弃思考 |
| glm-4.5 / 4.5-air / 4.6 / 4.7 / 5 / 5-turbo / 5.1 | `thinking:{type:"disabled"}` | **没有**：`reasoning_effort` 任何值（含乱写的）都 200、照常思考——静默丢弃 | 给这几款一个档位菜单 = 三个效果完全相同的假控件 |

- 开关字段是**顶层** `thinking:{type:"enabled"|"disabled"}`（与 DeepSeek 同形）；`reasoning_effort:"high"` 与 `disabled` 同发**不报错**（豆包会 400）。
- 另有 `thinking.clear_thinking`（默认 `true`，丢弃历史轮的 `reasoning_content`）；`false` = 「保留式思考」，要求跨轮原样回传全部历史推理，
  厂商推荐 5.3-flash 用 `false`。缺 `type` 只发 `{clear_thinking:false}` 在智谱自家端点 200（经千问转发时在非 GLM 模型上 400）。
- 推理从 `reasoning_content` 流出；工具轮回传被接受（交错思考，文档要求回传）。`usage.completion_tokens_details.reasoning_tokens`
  4.5-air 从不给，glm-5 / 4.6 / 4.5 关思考时缺席（不是 0）。
- **同一个模型换一个面，默认值就变**：glm-4.7 在 ④ `/api/anthropic` 上默认**不**思考（只回 text 块），在 ① 上默认思考——
  「默认值要按模型 × 面问」（第 1 篇 §8）。
- 对实现的推论：参数形状由「模型 id → 控制方式」查表预填（关不掉 / 关 + 两档 / 只有开关三类），作者可改；
  「开关」类在未设置时应显示为**开**，因为不发字段 = 端点默认在想。

### 3.2 火山方舟对话（豆包 Seed）：① 的 `reasoning_effort` 就是开关，别家的开关被静默无视（2026-09-18 实测）

来源：Joycai Image AI Toolkits，订阅套餐 base `…/api/plan/v3/chat/completions`，`doubao-seed-2.0-pro` 与别名 `ark-code-latest` 结果一致；
经应用的 dispatcher 真发一遍复核（默认 66、关 0、低 68、最高 145 个 reasoning token）。

| 发送 | `usage…reasoning_tokens` |
| --- | --- |
| 不发（默认） | 60–67（默认在想） |
| `reasoning_effort:"none"` / `"minimal"` | **0** |
| `"low"` / `"medium"` / `"high"` / `"max"` / `"xhigh"` | 60–145（真分档） |
| `thinking:{type:"disabled"}` | 0 |
| `thinking:{type:"enabled"}` | 66 |
| `thinking:{type:"auto"}` | `400 InvalidParameter`（本模型不支持 auto） |
| `thinking:disabled` + `reasoning_effort:"high"` | `400`（组合非法；GLM 同发不报错，§3.1） |
| `thinking:enabled` + `reasoning_effort:"none"` | 0（effort 说了算） |
| `enable_thinking:false`（千问的拼法） | **照想**——未知字段静默忽略，不报错（坑 114） |

- 推论：方舟**不需要声明任何方言**，① 的默认写法（关 = `"none"`）就关得掉。反过来，把为千问声明的 `switch` 方言挂到方舟模型上，
  「关」不报错、只是失效——方言按厂商声明，不能因为「都是 ① 兼容」就复用。
- 回包 `message` 里除 `reasoning_content` 外还有 `encrypted_content`（加密推理）；Joycai 不读也不回传，多轮未见报错，是否影响质量未测。
  **→ 已由 2026-09-23 的文档与实测回答**，见下「思考摘要与加密原文」：不回传不报错，但厂商明说推理效果下降（静默降级）。

**三个面的思考控制**（simple-ai-writer，套餐 key，`doubao-seed-2.0-lite` / `-mini` / `2.1-turbo`【实测 2026-09-18】）：

| 面 | 默认 | 关 | 强度 | 注意 |
| --- | --- | --- | --- | --- |
| ① | 开（「用一句话说你好」想 590 token） | `thinking:{type:"disabled"}` 或 `reasoning_effort:"none"/"minimal"` | `reasoning_effort` 收 `none / minimal / low / medium / high / xhigh / max`，乱写 400 并列出参数名；`medium` 是真的一档（同题 1,541 token，`max` 反而 136——平凡题上档位差被噪声淹没） | `high` + `disabled` 同发 400「Invalid combination of reasoning_effort and thinking type」→「关」只发开关、不带强度 |
| ② | 开 | `reasoning:{effort:"none"}`（三款都 0 推理）；也认顶层 `thinking:{type:"disabled"}` | `reasoning.effort` 七档全收 | 标准 ② 写法原样可用 |
| ④ | 开 | `thinking:{type:"disabled"}` | `adaptive` 与 `enabled + budget_tokens` 都收，`output_config.effort` 不报错（效果未比） | thinking 块**没有 `signature`**（**仅 2.0 系**；2.1-turbo 带签名，见下「④ 面的签名」【实测 2026-09-23】），原样回传照样 200；Claude 式的 `enabled` / 什么都不发 = 关不掉（它默认在想），要一个「adaptive / disabled」开关类目 |

- 厂商文档对 2.x 只写 `enabled`（默认）/ `disabled`，没有一款列 `auto`（与上表 2.0-pro 的 `auto` → 400 一致）【文档 2026-09】。
- 推理从 ① `reasoning_content` 流出；`reasoning_tokens` 在 ① 末尾 `choices:[]` 的 chunk 的 `usage.completion_tokens_details` 里、② 在
  `usage.output_tokens_details` 里（已含在 completion / output tokens 中，不读不影响计费）【实测 2026-09-23】。
- **强制 `tool_choice` 在思考开时照常可用**（① `required` / 具名、④ `{type:"tool"}` 都 200），但**强制时推理 token 为 0**——静默跳过思考，
  不报错（与 MiniMax 那种思考开时拒绝强制的相反，不需要把强制降成 auto）。

#### 思考摘要与加密原文（① 面，2026-09-23）

【文档 2026-09】2.1 系（及 seed-evolving、2.0-lite-260428 起）默认开「思考摘要」：`reasoning_content` **只是摘要**，原始思维链加密在
`encrypted_content`。【实测 2026-09-23，2.1-turbo】流式下密文**整串落在某一个 delta 上**，与一段摘要同帧：

```json
{"choices":[{"delta":{"reasoning_content":"\n","encrypted_content":"djEN…"}}]}
```

- 回传义务：工具轮的 assistant 消息要把 `reasoning_content` 与 `encrypted_content` **一起**带回，`encrypted_content` 优先。只回摘要**不报错**，
  模型改在摘要上推理——厂商原话「推理效果下降」。这是 §5 表里「静默降级」的第四种载体（39 条功能用例全过，照样丢了原文）。
- 载体与 ④ 的 thinking block 同一约定：**带上产出它的 modelId**，同一模型才回传；换模型解不开。只按 modelId 绑定时，
  同一个 id 换渠道（套餐 ↔ 按量 ↔ 中继）回传能否解密**未测**；厂商只说篡改过的密文「无法还原」，没说报不报错【未验】。
- 密文只为回传，**不显示**；多个 delta 各带一段时按到达顺序拼接（实测只见过一段）。摘要为空（只有密文）时，回传只写 `encrypted_content`。
- ② 面不受影响：整条 `reasoning` output item 原样回传（§7.3），`encrypted_content` 本来就在里面。

**④ 面的签名（2026-09-23）**：上表「thinking 块没有 `signature`」是 2026-09-18 在 2.0 系上测的；【实测 2026-09-23】2.1-turbo 的 thinking 块
**带 `signature`**（非流式在块上；流式走 `signature_delta`，`dj…` 开头，与 ① `encrypted_content` 前缀相同，推测同一种密文），2.0-mini / 2.0-lite 流式非流式都没有。
工具轮回传第一轮 content 时，**原样、篡改末尾、删掉 `signature` 三种都 200**——与 Anthropic 官方的文档口径（篡改即 400，§5）不同，回传出错不会响（坑 137）。
按 §5 的 ④ 约定整块原样回传即可；删签名是否像 ① 那样让推理变差【未验】。
- 套餐 base 上服务的对话模型：`doubao-seed-2.0-pro`、`ark-code-latest` 可用；`doubao-seed-1-6-250615`、`doubao-seed-1.6`、`doubao-seed-code`
  回 `404 UnsupportedModel`（「does not support the agent plan feature」）。`max_tokens` 照收。

### 3.3 中转站翻译层上的 Claude（New API）：档位随渠道变，① `max` 是转换层的（2026-09-23 实测）

来源：simple-ai-writer `docs/api/landscape.md` §7 第十五个样本、`live.relay-kiro.test.ts`（④ `claude-adaptive`、① `openai-generic` 两条路都驱动真实 adapter）。
模型 `[特价kiro量]claude-opus-4-6` / `-opus-5`，两款结果一致。背景见第 1 篇 §9.2：后端是 Kiro、不是 Anthropic API，中转站在中间翻译。

**④ 面**（`/v1/messages`）：

| 发送 | 结果 |
| --- | --- |
| `thinking:{type:"adaptive"}` / `{type:"enabled", budget_tokens}` / `{type:"disabled"}` | ✅ 三种都照办；thinking 块带 `signature`（300–380 字符），流式有 `thinking_delta` / `signature_delta` |
| `display:"summarized"` / `"omitted"` | **无效果**：永远返回完整原文，`omitted` 也不清空（§4 表 ④ 行说的「只有 summarized 才看得见」在这里不成立——反方向，总是看得见） |
| `budget_tokens ≥ max_tokens` | 200（官方 400）；`max_tokens` 本身也被无视（第 1 篇 §9.2） |
| `output_config.effort` | **只有 `low` 有效果**：同一道难题每档 3 次，输出 token 均值 low ≈ 750，medium / high / max 都 ≈ 1,050、分不出；简单题上 `low` 直接不想。乱写的值（`bogus`）也 200 |
| 只发 effort、不发 `thinking` | 不想（与官方 4.6 一致） |
| 工具轮回传 thinking 块 | ✅；**签名不校验**：原样、篡改末尾、删掉 `signature` 三种都 200 且答对（与火山方舟 ④ 同，坑 137） |

**① 面**（`/v1/chat/completions`，中转站先翻成 Messages）：

| 发送 | 结果 |
| --- | --- |
| `reasoning_effort:"low"` / `"medium"` / `"high"` | 思考开，从 `delta.reasoning_content` 流出；`completion_tokens_details.reasoning_tokens` **恒为 0**，思考算在 `completion_tokens` 里 |
| `reasoning_effort:"max"` / `"none"` / 乱写的值 | **不想**——`max` 与 `none` 同效，乱写也不报错 |
| 顶层 `thinking:{type:"enabled", budget_tokens}` / `{type:"adaptive"}` | 静默忽略，不想 |

> **更正（2026-09-23，同日第十六个样本）**：① 面这三行**不是 Kiro 特有**——同一台上 CC / anti / AWSb 渠道的 Claude 发 `max` / `none` 也都不想，
> 顶层 `thinking` 也都被忽略。是这台 New API 的 ①→④ 转换。上表保留，归属改正（坑 147）。

**同一台上别的渠道**（④ 面，`claude-opus-4-6`；landscape.md §7 第十六个样本）：

| | Kiro | CC | anti | AWSb（Bedrock 正向） |
| --- | --- | --- | --- | --- |
| 思考 | ✅ | ✅；**opus-5 的 thinking 块文本恒为空**（带 `display:"summarized"`、难题上 765 输出 token 也空），opus-4-6 有文本 | ❌ **不想**：没有 thinking 块；`-thinking` 变体也一样 | ✅ |
| `display:"omitted"` | 无视，照给全文 | ✅ 块在、文本空 | — | ✅ 块在、文本空 |
| effort low / max（同一难题的输出 token） | 只有 low 有效 | 分不开（745–1,804 对 768–1,929） | — | ✅ **真分档**：low 6 / 207，max 1,037–1,156 |
| 乱写 effort、思考时 `temperature:0.3` | 200 | 200 | 200 | 400，报错与官方同文 |
| 回传篡改过的 `signature` | 200 | 200 | —（没调用工具） | ✅ 400 `Invalid signature in thinking block` |
| `budget_tokens ≥ max_tokens` | 200 | 200 | 200 | 200（正向也不校验这一条） |

推论与做法：

- **§2 翻译表里「max → `"max"`」在这里等于关。** 同一个 `max`：xAI 400（§7.1）、火山方舟真分档（§3.2）、这台中转站 = 不想——又一种。
  它不报错，作者选了「最高」只会觉得这次答得又快又浅。参考实现没有为此改代码，只在作者说明里写「别选最高，低 / 中 / 高都在想」；
  若要在代码里防，做法是把 ① 的 `max` 夹到 `high`【未实现】——范围是这台中转站 ① 面上**所有** Claude（转换层的），不是 Kiro 名单。
- **④ 的档位拨盘在这里只有两态**：「关」（发 `low`，§2 的 off 映射）真的变浅，其余几档等价。不是 bug 就别修，UI 说明写清即可。
- **`reasoning_tokens` 为 0 不能当「没想」的判据**（① 面），看 `reasoning_content` 有没有文本；反过来 ④ 的 `display` 无效意味着
  你以为发了 `omitted` 省掉的展示，其实全文照回。
- **「思考开了」要看渠道**：anti 渠道任何思考参数都不想，UI 上的档位全是摆设；CC 的 opus-5 按思考计费，却没有思考文本可显示。都 200。
  思考能力也得按渠道声明（第 1 篇 §9.2 第 7 条），不能由「这是 Claude」推出；验证看有没有 thinking 块的**文本**，不看请求发了什么。
- 只有正向渠道会让「按 400 学降级」生效（乱写 effort、思考时带 temperature 都会响）；反代上同样的错一律静默。
- 签名不校验 = 回传出错不会响：按 §5 的 ④ 约定整块原样回传，验证只能看 API 日志里存下的块，不能靠第二轮是否报错。

### 3.4 ④ 开关型方言关思考时的温度：拼法相同的两家，一家听、一家不听（2026-09-28 实测）

背景：官方 Messages API 思考开着时只收 `temperature: 1`（别的值 400）。把作者的 0.2 夹成 1 是「以尊重之名发出相反的东西」，所以 ④ 的通行做法是**在想就不发温度**，
界面上的温度框也收起。这对 adaptive / extended 是对的——它们的「关闭」是最低档（§2.1），关了也在想。
但 ④ 上的 `switch` 方言（MiniMax、火山方舟 Coding Plan 的 ④ 线路）关闭时发 `thinking:{type:"disabled"}`，是**真关**。问题只剩一个：关了之后，对面听不听温度。

【实测 2026-09-28】（simple-ai-writer landscape.md §7 第四、第十二个样本「B6 补测」；真实 ④ 适配器，只在发送层补上 `temperature`；每档 20 次，
记 20 次中最多的那个答案出现几次；测法见第 6 篇 §8 第 13 条）：

| | 火山方舟 Coding Plan ④（`doubao-seed-2.0-mini`） | MiniMax ④（`MiniMax-M3`，国内站） |
| --- | --- | --- |
| 关思考 + `0.3` | 200，确实没想 | 200，确实没想 |
| 关思考 + `0.01` | **收敛**：数字题 19/20、水果题 19–20/20（`0.1` / `0.3` 也收敛：18/20、17/20） | **不收敛**：数字题 10–11/20，与不发、与 `1` 分不开 |
| 关思考 + `0` | **等于没发**：四轮 9–13/20，全落在不发温度的范围（8–13/20）里 | 同样分不开 |
| 开思考 + `0.3` | **200**（官方是 400），推理照常 | **200**（官方是 400） |
| 开思考 + `0.01` | 不收敛：数字题 10–13/20，远不到关思考时的 19–20 | 不收敛 |
| ① 面对照 | `0` / `0.1` / `0.3` 都收敛（17–19/20）、`1` 分散（9/20）——**「0 等于没发」只在 ④ 面** | 同样看不出温度（M3 在 ① 面总在想） |

- **火山方舟 ④：关思考时听**，但 `0` 像是被当成「未设」落回缺省——非零的最小值才是贪心。
- **MiniMax ④：收下、不理会**，开关两种状态都一样。不发是对的，理由从「在想」换成「没人听」。
- **两家开思考时都 200 而不收敛**：官方的 400 在这里不响，「按 400 学降级」学不到任何东西（第 6 篇 §9）；「在想就不发」照旧成立，理由从「会 400」换成「发了没人听」。

做法与理由：

- **事实挂在思考类目上，不挂在平台格上。** 两家拼法相同，差在对面听不听——与「MiniMax 把强制工具一律降成 auto」（04 §4）同一种厂商事实，所以拆成两个类目
  （`minimax` / `doubao-switch`），只在后者上声明 `temperatureWhenOff: { zeroIsUnset: true }`。「听不听温度」由一个函数回答：
  不发任何思考字段的类目听；其余只有声明了 `temperatureWhenOff`、且**线上**思考状态是关（`offSpelling:"disable"` 的 off）时听。发送端与界面问同一个函数，不会分叉。
- 平台格做不到：能力裁决里**请求条件先于平台格**（第 1 篇 §9.2 的裁决次序：思考在上游格、平台格之前），条件一触发就返回；
  要让格子盖过条件，就得给求值顺序加特例。挂在类目上还有一个好处：中转站 / 自定义渠道上作者手选了这个类目的行也得到它——类目本来就是作者对「对面是谁」的声明。
- **被否掉的写法**：把条件整条换成「线上没在想就发」。它对火山对、对 MiniMax 错——MiniMax 关思考时会发一个没人听的字段，界面还要画一个改了没用的框。
- **`0` 只加说明，不改值**：这个类目上温度框下写「这条线路把 0 也当作没填，要最稳的输出，填 0.01」，填 0 时不挂「确定性」标签。
  不在适配器里把 0 改发成极小正数——那是改写作者写下的值。温度框随「开 / 关」出现与收起，收起时值留着。
- 声明了 `temperatureWhenOff` 的类目，其 off 必须是真关（`offSpelling:"disable"`）；测试逐格比对「标准 × 类目 × 强度」上发送端的决定与界面的问法。

### 3.5 第三方 ④ 面：思考默认值与 `disabled` 三种结局按平台 × 模型；未知字段／非法值四家四种（2026-09-28 实测）

来源：simple-ai-writer `docs/api/reasoning.md` §1.2 / §1.7 / §2.2、`docs/api/landscape.md` §7 第四（MiniMax 补测）、第六（百炼补测）、第十四（智谱补测）、第二十（DeepSeek）个样本。
四家都是**官方直连**、非中转，**每格一次请求**（样本量 1，只看方向；结论记号按「收下不生效 = 🔇」记）。

官方 Claude 有两派（4.6+ 省略 = 用默认（开），≤4.5 省略 = 关着，§3）；第三方的 ④ 兼容层还要**再按平台 × 模型分一次**——同一个百炼 ④ 面，千问默认想、qwen-turbo 从不想；同一家智谱，4.7 默认不想、5.3 关不掉：

| 平台 · ④ 面 · 模型 | 不发 `thinking` | `{type:"disabled"}` | 细节与证据 |
| --- | --- | --- | --- |
| DeepSeek 官方 `https://api.deepseek.com/anthropic/v1/messages`（`x-api-key` + `anthropic-version`）：deepseek-v4-pro、deepseek-flash | **想**（输入 token 从 11 涨到 90，思考模式带了自己的前缀） | ✅ 收，真关（200，只回 text 块；同时带 `temperature` / `top_p` / `top_k` 也收） | `{type:"adaptive"}` 与 `{type:"enabled", budget_tokens}` 都 200、都想（文档说 `budget_tokens` 被忽略）【实测 2026-09-28】 |
| 阿里百炼 `/apps/anthropic`（普通 `sk-` key 走 `x-api-key`）：qwen3.8-flash、qwen3.7-flash、qwen3.5-plus | **想** | ✅ 收，真关（同时带 `temperature` / `top_p` / `top_k` 也收；qwen3.8-flash 关时只回 text 块） | 新旧 host 等价：文档给 `https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/apps/anthropic`，旧的 `https://dashscope.aliyuncs.com/apps/anthropic` 同一把 key 照样 200【实测 2026-09-28】 |
| 百炼上的 qwen-turbo | 不想（从不想） | — | 【实测 2026-09-28】 |
| 百炼上的 MiniMax-M2.5 | 想 | ❌ **400，关不掉**：`<400> InternalError.Algo.InvalidParameter: The value of the enable_thinking parameter is restricted to True.` | 翻译层把上游拒绝原样传回，点名的是 ① 的字段名（见下）【实测 2026-09-28】 |
| 百炼上的 glm-5.3 | —（来源表格留空，未测） | ❌ 400，同上一句 | 【实测 2026-09-28】 |
| 百炼上的 kimi-k2-thinking | — | 🔇 收下，**照想**（200，thinking 块有文本） | 【实测 2026-09-28】 |
| 百炼上的 kimi-k2.6 | 回一个**文本与签名都空**的 thinking 块（内容上没想） | ✅ 收下，同样回空块（没想）；显式 `enabled` 才有文本——空块不等于「关不掉」（§4.1） | 空块行为【实测 2026-09-28】；文档默认表：kimi-k2.6 / 2.5 默认关 📄——「显式 `enabled` 才有文本」是否等于「默认关」待核实（31 OQ-074） |
| 百炼上的 deepseek-v4-pro | — | ✅ 收，真关 | 【实测 2026-09-28】 |
| 智谱 `/api/anthropic`：glm-5.3、glm-5.3-flash | **想** | ❌ **400（1210），关不掉**：`{"type":"invalid_request_error","code":"1210","message":"[1210][该模型始终思考，不支持关闭思考；请使用 low、high 或 max。][<request id>]"}` | `output_config:{effort:"low"}` → 200 **无 thinking 块**；`adaptive`、`enabled` 都 200、都想【实测 2026-09-28】 |
| 智谱 glm-4.6 | — | ✅ 200，真关 | 【实测 2026-09-28】 |
| 智谱 glm-4.7 | 不想（只回 text 块，与 ① 面相反，§3.1） | — | 【实测 2026-09-19，只探两次】 |
| MiniMax 国内站 `api.minimaxi.com/anthropic`：MiniMax-M3 | **不想**（不发 `thinking` 不想，「默认 `disabled`」成立） | ✅ 收，真关（200，只回 text 块） | 【实测 2026-09-28】 |
| MiniMax M2.7 | 想 | 🔇 收下，**照想**（200，回 thinking 块，不报错——与文档「M2.x 思考无法关闭」一致，但它不拒） | 【实测 2026-09-28】 |

#### 兼容层上 `disabled` 的三种结局

1. **收下且真关**：DeepSeek v4-pro / flash、百炼千问三款与 deepseek-v4-pro、智谱 glm-4.6、MiniMax-M3。
2. **拒绝并说明关不掉**（会响）：智谱 `1210 该模型始终思考，不支持关闭思考`（① 面那句 1210 在 ④ 面原样出现，外面多包一层 `[1210][…][id]`）；百炼则借自家 ① 方言的字段名 `The value of the enable_thinking parameter is restricted to True.`。
3. **收下但照想**（🔇 静默）：MiniMax M2.7、百炼上的 kimi-k2-thinking。**请求侧没有任何信号**（200，没有警告字段），只能看回复里还有没有思考内容（§4.1）。
   不这样会怎样：作者选了「关闭」、账单照付思考 token，界面上还以为关了。对策：思考类目的 `offSpelling` 按 (平台, 模型) 声明；「关没关」的验证看响应块，不看请求发了什么（同 §3.3 的教训）。

**百炼 ④ 的拒绝点名的是别家协议的字段**：上文「MiniMax-M2.5 除外，400」和 ① 面那句 `The value of the enable_thinking parameter is restricted to True` 是**同一个校验**——④ 面的 `thinking` 被翻成百炼自家 ① 方言 `enable_thinking` 再下发，拒绝时连 ① 的字段名一起回来（glm-5.3 同样）。一个 ④ 客户端收到的拒绝里点名的是 `enable_thinking`，按 `thinking` 找原因会找不到；「按 400 学降级」的正则若按本族字段名匹配，在这里失配（06 §2、坑 219）。

#### 未知顶层字段／非法思考值：四家四种报法

顶层未知字段**四家都 200 放过**（① 族的 `reasoning_effort` 也放过）。`thinking.type:"bogus"` 则四家四种：

| 平台 · ④ 面 | `thinking.type:"bogus"` | 其它 |
| --- | --- | --- |
| MiniMax ④（型号未标：M3／M2.7 补测块，每条一次；31 OQ-072） | 🔇 **200，而且开始想**——非法值被当成了「开」 | 什么都收（同块，型号未标）：`enabled` + `budget_tokens`、`adaptive` + `display:"summarized"`、`top_k:99999`、`temperature:2.5`（文档说 [0, 2] 外报错）都 200；唯一撞出来的 400 是 `top_p:1.5` → `{"type":"invalid_request_error","message":"invalid params, param 'top_p' should be in (0,1] (2013)"}`；**未知模型名静默改映射**：`MiniMax-M3.1-Flash-Preview`（文档列着、该 key 的 `/v1/models` 里没有）200，响应的 `model` 是 `MiniMax-M3`——只有拿响应里的 `model` 核对才看得出 |
| DeepSeek | ❌ **422，点名枚举**：``Failed to deserialize the JSON body into the target type: thinking.type: unknown variant `bogus`, expected one of `adaptive`, `enabled`, `disabled` at line 1 column 142``——四家 ④ 兼容层里唯一在请求形状上严格的一家 | 文档（2026-09）：`top_k` 忽略；`top_p` 只在思考模式生效（下限 0.95），非思考模式固定 1.0；`temperature` [0, 2]；`claude-opus*` 映射到 deepseek-v4-pro，`claude-haiku*` / `claude-sonnet*` 映射到 deepseek-flash，**不认识的模型名也映射到 deepseek-flash，不报错** 📄 |
| 智谱（glm-5.3 / 5.3-flash） | ❌ 回的也是那句 1210「该模型始终思考」，不是「非法值」 | 顶层未知字段 200 放过，与 ① 面一致 |
| 阿里百炼 | ❌ 400 `Request body format invalid`（不点名字段） | 未知模型 → 400 ``The model `qwen-nonexistent` does not exist or you do not have access to it.``；`temperature:2.5` → 400 `Temperature should be in [0.0, 2.0)`；`budget_tokens:1024` 配 `max_tokens:512` → 400 `max_completion_tokens [512] must be greater than thinking_budget [1024]`（2048 时 200）；`thinking.type` 文档只列 `enabled` / `disabled`，实测 `adaptive` 也收 |

- 06 §8 第 10 条「非法参数分类法」在四家 ④ 面上各有一种答案：DeepSeek 与百炼、智谱会响（但智谱的文案不指向值），MiniMax 不响且反向生效——「按 400 学降级」只在前三家学得到东西，在 MiniMax 上什么都学不到、还会把思考打开（坑 217、220）。
- 百炼 ④ 的文档（2026-09）默认表：qwen3.8-max / 3.8-flash、deepseek-v4 系、glm 系默认开；kimi-k2.6 / 2.5 默认关；kimi-k2.7-code、kimi-k2-thinking、MiniMax-M2.5 / 2.1 只有思考模式 📄。与实测一致的部分已并进上表；glm-5.3 的默认值未测（31 OQ-073）。

## 4. 思维链的流式暴露：三族三种读法，统一产出 `{reasoning}` chunk

| 族 | 读哪里 |
| --- | --- |
| ① | `delta.reasoning_content` / `delta.reasoning`（候选字段表 `REASONING_CONTENT_FIELDS`，按序试；**非字符串值忽略不强转**——有端点在旁边发结构化 `reasoning_details` 数组，`String()` 会给用户看 `[object Object]`）+ 内联 `<think>` 切分（见 §6） |
| ①（火山方舟 2.1 起） | `delta.reasoning_content` 是**摘要**；原文密文在 `delta.encrypted_content`（整串落在某一个 delta 上），只留存不显示（§3.2） |
| ③ | `part.thought === true` 的文本 part（3.8 Flash：思考摘要是**一个**整段给出的 `{text, thought:true}` part，流式也不逐字；`thoughtSignature` 挂在正文 text part 上【实测 2026-09-26】） |
| ④ | `thinking_delta.thinking` 事件（仅当请求发了 `display:"summarized"` 才会有；中转站翻译层可能无视 `display`、总给全文，§3.3）。流形：`content_block_start` 的 thinking 块带空 `signature:""`，`thinking_delta` 连续出，末尾一条 `signature_delta`【实测 2026-09-26，Sonnet 5】 |

**候选字段按「有非空文本」取，不按「字段存在」取**：有中转同时发 `reasoning_content:""` 与非空的 `reasoning`，`a ?? b` 式的取法拿到空串——思考文本丢失，且回传时记住了错误的字段名【实测 2026-09-14，中转流量；坑 107】。按序试，第一个非空字符串连同它的字段名一起留下。

扩展规则：支持一家新端点的思维链拼写 = 往 `REASONING_CONTENT_FIELDS` 加一个字符串。**刻意设计成永远不会变成 per-vendor 分支**——候选字段表是数据，分支是代码。

产出侧统一为 `{reasoning: string}` chunk（与 `{text}` 是不同变体，见第 1 篇）：思维链绝不能混进正文流。

### 4.1 判「这一轮想没想」看文本或签名，至少一个非空（2026-09-28）

空的 `thinking` 字段本身什么也说明不了【实测 2026-09-28，各家 ④ 面；simple-ai-writer `docs/api/reasoning.md` §2.2】：

| 来源 | `thinking` 文本 | `signature` | 想了没有 |
| --- | --- | --- | --- |
| Claude 当前代，默认 `display:"omitted"` | 空 | 有 | 想了（照计费） |
| 百炼 ④ 上的千问 | 有 | 恒为空串 | 想了 |
| 百炼 ④ 上的 kimi-k2.6（不发 `thinking`，或 `disabled`） | 空 | 空 | 没想 |

只认文本，会把 Claude 的 `omitted` 读成「没想」；只认块在不在，会把 kimi-k2.6 读成「关不掉」（它显式 `enabled` 时块里才有文本）。
按型号分的空块【实测 2026-09-28，百炼 ④】：qwen3.8-flash 关时只回 text 块；kimi-k2.6 不发 `thinking` 与 `disabled` 时都回 `{type:"thinking",thinking:"",signature:""}` 空块——适配器要容忍这个空块（旧结论「关掉思考时响应里仍有一个空块」是按型号的，不是整个面的）。
对策：判据写成「文本或签名至少一个非空」；这也是 §3.5 第三种结局（收下照想）与 §5 ④ 行「缺失 → 静默降级」的唯一验证手段（坑 218）。

## 5. 回传义务：三族三种载体、三种失败模式

**心法：跨轮要回传的东西必须整块留存原物，不能归一化后重建。**"理解后重建"恰好丢掉的就是完整性校验依赖的那部分（signature、encrypted payload、字段拼写、块顺序）。

| 族 | 不回传的后果 | 载体 |
| --- | --- | --- |
| ① DeepSeek 系 | **400**（会响，逼你修） | `_reasoning: {field, text}`——收到什么字段名就用什么名字还回去，无需知道对面是谁 |
| ① 火山方舟（豆包 2.1 起） | **静默降级**：只回摘要不报错，模型在摘要上推理（厂商：「推理效果下降」） | `_reasoning` 旁加 `encrypted: {modelId, value}`——原样留存密文，同一模型才回传（§3.2） |
| ① MiniMax（M3，`api.minimaxi.com/v1`） | **不报错，不强制**：文档要工具轮带回完整 assistant 消息（「务必完整保留模型思考内容……才能保证 Interleaved Thinking 生效」），指的是效果不是校验。【实测 2026-09-28，样本量未标】工具轮的 assistant 消息保留 `<think>…</think>`、去掉、`content: null`、改放 `reasoning_content` 四种写法都 200、答案正常；保留时思考照计 prompt token（多 26），服务端不剥 | 思考以 `<think>…</think>` 内联在 `content`（M3 默认内联思考、不出 `reasoning_content`，`completion_tokens_details.reasoning_tokens` 有值）；§6 切分器切出的只展示不回传，与本行不冲突——回不回都 200，回了多付 26 token 换交错思考 |
| ③ Gemini | 多轮工具失效；HTTP 200 + `finishReason: MISSING_THOUGHT_SIGNATURE`（第三种形态：不是 400 也不是静默）。**【2026-09-26 补】3.8 Flash（Vertex，经 OrcaRouter）上 `functionCall` part 缺签名是 HTTP 400** `Function call is missing a thought_signature in functionCall parts`——两种形态都要认成「我方丢了签名」。签名位置：正文 text part、并行调用的**第一个** `functionCall` part，流式时落在最后一块 `{text:"", thoughtSignature}` 上 | `_geminiModelParts: unknown[]`——整组原始 parts 原样回传（含 thought parts 与 thoughtSignature）；**例外：流末光秃秃的 `{text:""}` 剔除**（第 5 篇 §3） |
| ④ Anthropic | **静默降级**：API 不报错，直接关掉这轮思考（最危险——唯一验证手段是看响应里还有没有 thinking block）；**改动/重排/部分丢弃才是 400**。【实测 2026-09-26，Sonnet 5 adaptive + 并行工具，经 OrcaRouter】原样回灌 200；**改 `signature` → 400** ``Invalid `signature` in `thinking` block``；改 thinking 文本、留原签名 200（`summarized` 的摘要文本本来就不是被签的那份）；整块丢掉也 200——正是上面的「缺失 → 静默降级」，印证而非例外；改文本留签名 200 是经网关的请求侧结论（第 1 篇 §9.5）。对策仍是原样带回 | `_thinkingBlocks: {modelId, blocks}`——有序块数组原样回传（`redacted_thinking` 只有不透明 data 也要回） |

实现规则：

1. **只在带 tool_calls 的 assistant 消息上携带**（三个载体一致）：这些端点把"调用工具前的思考"视为同一条回复的一部分（工具调用是模型暂停自己回复的构造，去等外部信息）；普通轮次端点自己会过滤，带上 = 白付 token。

   ⚠️ **DeepSeek 的回传义务是分场景的，两个方向都会 400，别只记住一半**：
   - **有工具调用的轮次**：该轮 assistant 消息的 `reasoning_content` **必须回传**——官方文档原文"若您的代码中未正确回传 `reasoning_content`，API 会返回 400 报错"。
   - **没有工具调用的轮次**：**不要携带**——官方文档（另一处，历史更久）规定输入 messages 含 `reasoning_content` 直接 400（新版端点部分改为忽略，但不可依赖）。
   本条"只在带 tool_calls 的消息上携带"的规则**同时满足两侧约束**，这正是它的由来。诊断线索：多轮工具调用第二轮 400 → 缺回传；400 body 出现 "reasoning_content is not allowed in the input messages" → 无工具轮误携带。两种症状同一条规则修复。
2. **`_thinkingBlocks` 带 `modelId`**：thinking block 与产出它的模型绑定。允许会话中途换模型的应用，换了就整组丢弃（`thinkingBlocksFor` 比对 modelId）——别的模型不会拒绝，会**静默忽略且照 input 计费**，最坏的组合。
3. **三个 `_` 字段并存是刻意选择，不要泛化承载**：④ 的载体是有序数组、成员可能只有不透明 payload、顺序受完整性校验，无法复用 `{field,text}`；泛化载体会把 modelId 特例变成所有人的负担。真正泛化的是**剥除**（`_` 前缀丢弃，见第 1 篇），不是承载。
4. **`redacted_thinking` 块必须回传**：它只有不透明 `data` 字段。按 `type === "thinking"` 过滤内容块的代码会静默丢掉它——过滤条件应当是"是思考类块"而不是精确类型匹配。

## 6. `<think>` 标签兜底切分器

部分 ① 族中继（MiniMax 等）不分离思维链，直接把 `<think>…</think>\n\n正文` 塞进 `delta.content`。不切分则思考散文会进用户稿子。

出处：simple-ai-writer `src/lib/ai/reasoning.ts` 的 `createThinkTagSplitter()`。状态机三阶段（start / thinking / body），两条安全性质是规范的核心：

1. **只认响应最开头的 `<think>`**（允许前导空白）。正文中途出现的 `<think>` 视为作者/模型自己的文本。理由：对内容生产类应用，静默吃掉一段正文比留一个标签在稿子里严重得多——切分器宁可漏切不可误切。
2. **跨 chunk 标签拼接**：`<thi` + `nk>` 分两片到达是常态。用 `danglingPrefix`（缓冲区尾部"是标签真前缀的最长后缀"）扣住可能成为标签的尾巴不发；下一片到达后拼接再判。流结束时未闭合的块按 reasoning flush——被截断的思考不是作者要的散文。

第三条规则：**切出来的 reasoning 只展示、不并入 `_reasoning` 回传**——它没有自己的 wire 字段名，编一个名字 = 往下一个请求塞没人认识的键。

## 7. ② Responses 族：强度 / 取回 / 回传

出处：simple-ai-writer `src/lib/ai/reasoning.ts`（思考类目 `responses-effort`）、`src/lib/ai/responses.ts`；事实见 `docs/api/responses.md` §2.1、§5、§10 与 `landscape.md` 第十一个样本。

### 7.1 强度：嵌套对象，复用 ① 族词表

| 本项目档位 | ② wire |
| --- | --- |
| default / 未设 | 一个字段都不发（各模型默认不同：5.4 `none`，5.5/5.6 `medium`，Grok 4.5/4.6 `high`——"未设"不能拼成其中任何一个） |
| off | `reasoning: { effort: "none" }`（无 summary） |
| low / medium / high / xhigh / max | `reasoning: { effort: <同名>, summary: "auto" }` |

- 端点枚举是 `none/minimal/low/medium/high/xhigh/max` 七档，菜单取其中六档（去掉 `minimal`）。【实测 2026-09-26，`gpt-6-luna` 经 OrcaRouter 的 OpenRouter 形态线路】`none`–`max` 六档都 200，`minimal` 被改写成 `low`（回显看得见；是翻译层干的还是上游，分不出）。
- **`summary: "auto"` 随非 off 档位一起发**：不发就没有任何摘要事件（与 Gemini 的 `includeThoughts` 同理——付了思考钱却看不见）；`auto` 回显 `detailed`。
- **按模型的上限不同，但菜单不按型号裁剪**：GPT-5.4 到 `xhigh`（`max` → 400 且报文列出合法值）；5.5 / 5.6 收 `max`；Grok 4.5/4.6 **拒 `none`**、全系拒 `max`。越界 400 就是端点自己的声明——按 id 猜上限会在中转站别名、新型号上错；这与 ① 族各类目一致。代价要写进 UI 提示：Grok 4.5/4.6 上「关闭」芯片必然 400，而这两款本来就关不掉思考。
- `reasoning.mode:"pro"`、`reasoning.context` 不接：前者两台中转站都回显 `standard`、无从确认生效（2026-09-24 一个网关上游回显了 `pro`，只测 1 次，§7.4）；后者默认 `all_turns` 恰是回传想要的效果。

### 7.2 取回

`response.reasoning_summary_text.delta` 与 `response.reasoning_text.delta` 都产出 `{reasoning}` chunk（后者在 GPT-5.x 上从未出现，千问的 Responses 面文档里有）。模型没真推理（`reasoning_tokens: 0`）时即使发了 summary 也没有 reasoning 条目——同一请求可能一次有一次没有，不是 bug。

### 7.3 回传

载体是 `_responseItems: {modelId, items}`（第 2 篇 §7.3）：reasoning 条目连同 **`encrypted_content` 原样**放回 `input`，不解释内容。事实边界：

- OpenAI（经中转站）：`store:false` 时 reasoning 条目自带 `encrypted_content`，不需要 `include`。
- xAI：**必须**发 `include:["reasoning.encrypted_content"]` 才有；不带它回传第二轮照样 200——缺的只是推理延续。
- 千问 Responses 面：没有 `encrypted_content`，回传的是明文 `summary`。

所以载体设计成"不解释、整组带回"才能同时装下三家；回传缺失在此族**不报错**，与 ④ 族一样只能靠日志对照验证。官方端点不发 `include` 是否丢加密推理**未经官方 key 验证**，参考实现暂不发。

### 7.4 中转站上的 GPT：账号池真分档，`none` 关不掉（2026-09-24 实测）

来源：simple-ai-writer `docs/api/landscape.md` §7 第十七个样本（一台 New API，`gpt-5.6-sol` 在三个 ChatGPT 账号档与一个网关上游下，网关用同档 terra 顶替）；
上游是什么、怎么分见第 1 篇 §9.2「同一个 GPT，两类上游」。

【实测 2026-09-24】② 面（`reasoning.effort`）：

| | 三个账号档（特价Pro / Plus / Pro） | 网关（`[Azure]`，terra） |
| --- | --- | --- |
| 各档回显 | 原样（`none` 除外） | 原样（`none` 除外） |
| 真分档？（同一道数论题各 3 次，`reasoning_tokens` low / xhigh） | ✅ 295–428 / 583–588、197–237 / 344–356、170–200 / 259–349 | 弱：131–155 / 163–245 |
| `effort:"none"` | **关不掉**：回显 `medium`，照样推理 | 同左 |
| `effort:"max"` | ✅ 回显 `max`、有推理 | ✅ |
| 乱写 `effort` | `[Pro]` 400 官方原文（列出七档合法值）；另两档 502 / 流式 `response.failed` | 500 |
| `reasoning.mode:"pro"` | 回显 `standard` | 回显 `pro`，同题输入 6,445（别的请求 1.2K，只测 1 次） |

① 面（`reasoning_effort`，中转站把 ① 翻成 ② 再发）：low / high / xhigh / max 都在想，`reasoning_content` 是摘要标题式的短文本（账号池 25–107 字符，网关 400–540）；
**`"none"` 只在网关上真关**（没有推理，同一道题 3 次答出三个错数，有推理时都答对）——账号池照样推理。

推论与做法：

- **§7.1 的 off → `{effort:"none"}` 在这类中转站的 ② 面上是空操作**，不报错、回显还会告诉你它变成了 `medium`（回显比对抓得到，第 6 篇 §4.1）。
  同一个「关」字：xAI 400（§7.1）、DeepSeek 要另一个字段（§2）、这里被改写——作者说明里写「这个上游关不掉思考」，不为此改翻译表。
- **第十个样本的「sol 发 `max` 回显 `none`、0 推理 token」这次没有出现**（四档都正常）——旧结论保留，按「当时当档」理解（第 1 篇 §9.2 第 2 条）。
- 「分得开」要看 `reasoning_tokens` 的分布，不看回显：网关回显照办，low 与 xhigh 却几乎重叠。
- ① 与 ② 在同一个上游上可以不同（网关 ① `none` 真关、② 关不掉），思考能力的格子按面记。

---

## 本篇检查清单

- [ ] 思考支持在设计文档里拆成了强度/取回/回传三节，各自有三族对照。
- [ ] 配置层存自有六档词汇（含 `default`/`off`/`max`），任何一家的拼写都没有进入存储。
- [ ] `default` 档一个字段都不发。
- [ ] Gemini 翻译用全大写 `thinkingLevel` 枚举，且发 level 必带 `includeThoughts: true`；只发一代字段。
- [ ] Gemini 的「关闭」映射到 `LOW`（所有型号都收），不是 `MINIMAL`（3.8 Flash / 3.1 Pro 没有，发了 400）；不拿 `thinkingBudget: 0` 当关闭。
- [ ] Claude 5 系「跟随默认」也在思考并计费（adaptive + `omitted` 是默认）：成本估算与「思考面板为什么空」的说明都按这个默认写。
- [ ] Anthropic `off` 翻译为降 effort 而不是 disabled。
- [ ] 每个思考类目声明 off 在线上是真关还是最低档（`offSpelling`）；「让它少想」的回退在最低档类目上既发 off 又带提示，真关的只发 off，没有 off 的只带提示。
- [ ] 第三方 ④ 面的思考默认值与 `disabled` 结局按 (平台, 模型) 查 §3.5，不从「这是 ④ 面」推；「关没关」看响应块的文本或签名（§4.1），不看请求；MiniMax 上 `thinking.type` 非法值会把思考打开，不拿它探测。
- [ ] ④ 的温度：在想就不发；开关型类目关思考时发不发，按类目声明（火山方舟 ④ 听、`0` 等于没发；MiniMax 不听），不按「线上没在想」一刀切，也不写成平台格；`0` 只加说明，不改写成极小正数。
- [ ] `ThinkingDialect` 是作者声明的 L3 字段，没有任何"从模型 id 猜代次"的启发式。
- [ ] `adaptive`/`extended` 恒发 `display:"summarized"`；`switch` 方言不发 display。
- [ ] `extended` 的 budget 钳在 `[1024, min(16384, maxTokens/2)]`。
- [ ] 缺省方言的猜测方向满足"错的方式会响"。
- [ ] ① 族的 `switch` 方言发 `enable_thinking` 且**停发** `reasoning_effort`（互斥）；未声明方言的请求与实现前逐字节相同。
- [ ] 方言选择 UI 的选项**按族给**：给 ① 族显示 `adaptive`/`extended` 是"按了没反应的控件"（写侧对它们无映射）。
- [ ] ① 族思维链读取走 `REASONING_CONTENT_FIELDS` 候选表；非字符串值忽略不强转；新拼写 = 表加一项。
- [ ] 三个回传载体（`_reasoning` / `_geminiModelParts` / `_thinkingBlocks`）只挂在带 tool_calls 的 assistant 消息上。
- [ ] `_thinkingBlocks` 带 modelId，换模型整组丢弃。
- [ ] `redacted_thinking` 不会被内容过滤丢掉。
- [ ] `<think>` 切分器只认响应开头、有 danglingPrefix 跨片处理、流末未闭合按 reasoning flush。
- [ ] 切分出的 reasoning 不进回传载体。
- [ ] 有一条验证手段确认 Anthropic 多轮工具会话中 thinking block 仍然出现（静默降级的唯一判据）。
- [ ] ② 族：`reasoning:{effort, summary:"auto"}`，off → `{effort:"none"}`，default 不发；菜单不按型号裁剪，越界交给端点 400，UI 提示写明 Grok 4.5/4.6 关不掉思考。
- [ ] ② 族 `reasoning_summary_text.delta` 与 `reasoning_text.delta` 都进 `{reasoning}`；无 reasoning 条目不当错误。
- [ ] ② 族回传的 reasoning 条目（含 `encrypted_content`）原样整组带回，载体带 modelId。
- [ ] ② 族的「关闭」在中转站上逐上游核实过：GPT 账号池与网关 ② `effort:"none"` 都被改写成 `medium`，① `none` 只在网关生效；关不掉的写进作者说明，靠回显比对报告，不重试。
- [ ] 经中转站（尤其翻译层后端，如 Kiro 渠道的 Claude）的思考档位逐档实测过：「最高」有没有变成不想（① `max`）、各档是否真分得开、`display` 是否被无视；结论写进作者说明或按 id 夹档，不假设翻译表处处成立。

## 补遗（自 22 篇移入，2026-09-28）

- （§2 Gemini 档位）Vertex 经 OrcaRouter ③：`thinkingLevel:"BOGUS"` ❌ 400，Vertex 原文（与 `MINIMAL` 400 同属会响，网关重序列化不吞这条）。【实测 2026-09-26】坑 170
- （§3.3 New API · AWSb 渠道的 Claude ④）乱写 `effort`／思考时带 `temperature:0.3` ❌ 400，文案与官方同文 `Input should be 'low', 'medium', 'high' or 'max'`——四渠道里唯一在思考参数上校验的。【实测 2026-09-23】坑 147
- （§7.2 OrcaRouter ② 默认线路的 GPT-6）流式 reasoning item 只有 `encrypted_content`、`summary: []`、无 `reasoning_summary_text.delta`（非流式时 luna 有摘要文本）；`summary:"auto"` 回显 `"detailed"`。【实测 2026-09-26】坑 175
