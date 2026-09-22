# 01 · 分层模型与统一抽象

> 本篇解决的问题：同时对接 OpenAI Chat Completions、OpenAI Responses、Google Gemini、Anthropic Messages 四个协议族，以及大量第三方"兼容"中继（New API、MiniMax、DeepSeek、千问 DashScope、OpenRouter、Ollama、LM Studio…）时，代码应当如何分层，才能做到「加一家新供应商 = 加一行数据，不是加一个文件」。
> 不读会踩的坑：为每家供应商建一个 Provider 子类，第三方之间 99% 相同的代码被复制 N 份；消息形状按 standard 原值分支，每个新 `_compat` 值都静默掉进 OpenAI 分支；传输配置在十几个调用点手工摊平，漏一处不是编译错误而是某个界面静默行为不一致。

出处：simple-ai-writer `src/lib/ai/`（`types.ts`、`index.ts`、`conn.ts`），设计文档 `docs/api/provider-layering.md`。

本篇目录：
- §1 四层模型：L1 / L2 / L3 + 探测维
- §2 协议族的判定标准
- §3 ApiStandard = 协议族 × official/compat（§3.1 案例：② Responses 为什么是第四族）
- §4 内部 lingua franca：OpenAI Chat Completions 形状
- §5 统一流事件：StreamChunk 变体联合
- §6 统一入口 streamCompletion 与 StreamOptions
- §7 config→request 的收口：连接参数单点摊平
- §8 多面供应商：surface × 协议菜单，与模型级协议选择（§8.1 事实 · §8.2 surface 与协议菜单 · §8.3 通道级选面 vs 模型级点单 · §8.4 路径推导 · §8.5 退化情形）
- §9 供应商数据行样例（§9.1 xAI · §9.2 New API 中转站的四种静默行为 · §9.3 火山方舟按量/套餐两个 base · §9.4 智谱：一把 key 走遍所有路径、路径决定计费）

---

## 1. 四层模型：L1 / L2 / L3 + 探测维

任何参数、任何差异，都应当先被归入下面四层之一，再决定放在哪：

```
L1  协议族      wire format 本身（body 长什么样）      服务商定义，一族一个 adapter
L2  端点        baseUrl / 鉴权方式 / 族方言参数        作者配置的一行（Provider 表）
L3  模型        能力、档位、上下文/输出上限、价格       端点下的一行（Model 表）
────────────────────────────────────────────────
探测维          真实行为的实测结果（带时间戳）          机器写入，不是配置
```

### 三条铁律

1. **只有 L1 允许"每族一份代码"。** 运行时永远只有"每个协议族一个 adapter"；"某一家供应商"（DeepSeek、Ollama…）是一张**预设数据表**，不是子类。禁止 `DeepSeekProvider extends OpenAIProvider` 这种形态——第三方之间 99% 相同，继承会把 99% 复制 N 份，而那 1% 的差异（一个 header、一个字段）一行配置就能表达。**加一家新供应商 = 加一行数据，不是加一个文件。**
2. **枚举值是稀缺的。** 只有"body 形状不同"才配拥有一个 `ApiStandard` 值。鉴权不同、默认值不同、私有字段不同，全用 L2 数据字段表达。
3. **新参数归属判断法**（按顺序问）：决定 body 形状？→ L1；换 key/baseUrl 会变？→ L2；同端点换模型会变？→ L3；作者答不上来只能实测？→ 探测维。同时命中 L2/L3 的放 L3（细粒度层永远能表达粗的）。

## 2. 协议族的判定标准

规则是一句话：**"能不能只改 URL 与鉴权头就跑通？能，就不是新族。"**

按这个标准，业内收敛成四族：

1. **OpenAI Chat Completions** —— 事实标准 + 全行业兼容层；
2. **OpenAI Responses** —— 与 ① 同厂却是独立一族（`input` vs `messages`、扁平 vs 嵌套工具定义、类型化事件 vs delta 拼接、服务端状态）；
3. **Google GenAI generateContent**；
4. **Anthropic Messages**。

Azure OpenAI、Vertex、Bedrock 上的 Claude 只是**部署变体**（同 body，换鉴权与 URL），不是新族。Bedrock Converse 实际是第五种独立 body（camelCase、SigV4）——接它就是接一个新族，不要伪装成 compat 选项；如果不打算写第五个 adapter，就明确不接。

## 3. ApiStandard = 协议族 × official/compat

每个协议族拆成 official 与 compat 两个枚举值，`familyOf()` 把它们折回族：

```text
ApiStandard    = openai | openai_compat
               | openai_responses | openai_responses_compat     # ② 族，2026-09 加入
               | gemini | gemini_compat
               | anthropic | anthropic_compat
ProtocolFamily = openai | responses | gemini | anthropic

familyOf(standard) -> ProtocolFamily
  查表折回族；表里没有的值（库里的旧值）落回 openai，不抛错
```

`_compat` 不是装饰，两种契约实质不同：

| | official 契约 | compat 契约 |
| --- | --- | --- |
| 地址 | 锁定（存空串，域名变更是代码改动不是数据迁移） | 自填（要归一化） |
| 鉴权 | 锁定 | 可选（下拉，见第 2 篇鉴权矩阵） |
| `/models` | 缺失视为错误 | 缺失降级探测（见第 6 篇） |
| 能力默认值 | 乐观 | 保守 |

**分发规则（红线）**：凡是问"消息长什么样"的地方，必须按 `familyOf(standard)`（折回后的族）分支，而不是按 standard 原值——否则每个新增的 `_compat` 值都会静默掉进 default（OpenAI）分支。只有 official/compat 契约差异（地址校验、鉴权选项、探测策略）才允许直接看 standard。

### 3.1 案例：② Responses 为什么是第四族而不是 `useResponses` 开关

出处：simple-ai-writer `src/lib/ai/responses.ts`，决策记录 `docs/api/qianwen-compat-plan.md` §4.3。

Responses 与 ① 同厂、同 base（官方 `https://api.openai.com/v1`，adapter 自己拼 `/responses`）、同 `Authorization: Bearer`、`/models` 探测复用 ① 族——**但"只改 URL 就跑通"不成立**：

- body：`instructions` + `input` 条目 vs `messages`；
- 流：类型化事件 vs `choices[].delta`；
- 工具形状：扁平 + 自动 strict vs 嵌套；
- 回传义务：整组 output 条目 vs assistant 消息。

反例：在 ① 族 adapter 里加 `useResponses` 布尔，等于把四处分支塞进一个文件、并让每个按族分支的调用点读不到这个差异。落地做法：

- `ApiStandard` 加 `openai_responses` / `openai_responses_compat` 成对两值，`ProtocolFamily` 加 `"responses"`，统一入口多一个 `case "responses"`。
- **加族 = 逐个过 `familyOf` 调用点**（参考实现 12 处：模型/供应商抽屉、两个探测器、出图、入口、jsonMode、modelSummary、reasoning、serverTools、types、urls）。漏过的调用点会静默落进 default（① 族）分支。
- `authMode` 在此族无意义（只有 Bearer），`authModesFor` 只给 `default`。

## 4. 内部 lingua franca：OpenAI Chat Completions 形状

内部消息表示应当统一选一种形状，推荐 OpenAI chat.completions：`system/user/assistant/tool` 角色、`tool_calls`、`tool_call_id`、`image_url` data-URL 多模态 part。Gemini/Anthropic 适配器各自做**单向转换**（`convertToGeminiContents` / `convertToAnthropicMessages`），转换只发生在 adapter 内部、发出前的最后一刻。

跨协议无法用 OpenAI 形状表达的东西（思维链回传物、Gemini 的 thoughtSignature 等），用 **`_` 前缀私有字段**随消息携带，adapter 上线前按前缀统一剥除：

```text
消息（三种之一）：
  { role: system|user|assistant, content: 文本 或 ContentPart[] }
  { role: assistant, content: null, tool_calls: [...],
    _geminiModelParts?  Gemini 原始 parts（含 thoughtSignature），原样
    _reasoning?         { field, text }  ① 系思维链：字段原名 + 全文，工具轮回传用
    _thinkingBlocks?    { modelId, blocks }  Anthropic thinking blocks，原样
    _responseItems?     { modelId, items }   ② Responses 整组 output 条目，原样 }
  { role: tool, tool_call_id, content: 文本 }

ContentPart = { type: text, text } | { type: image_url, image_url: { url: "data:<mime>;base64,<data>" } }
```

**剥除按前缀，不按名单。** 发出前：删掉所有以 `_` 开头的键；若有 `_reasoning`，再把
`_reasoning.text` 以 `_reasoning.field` 的**原名**写回（例如 `reasoning_content`）。参考实现的注释原话是：
每个需要回传的协议都会往这里加一个字段，名字白名单会静默地把下一个放行到 wire 上。

陷阱：如果剥除逻辑是一张字段名白名单，下一个协议加的 `_` 字段会被静默放行到 wire 上——多数端点对未知顶层键直接 400。前缀约定使"新增一个载体字段"零成本地安全。

## 5. 统一流事件：StreamChunk 变体联合

调用方只见一种 chunk 流。判别一律用 **key 判别**（`"text" in chunk` 式），因此**新增变体对旧消费者天然是 no-op**——这是加 `reasoning`/`serverTool` 变体不破坏任何调用点的机制，也是这个联合可以持续生长的前提。

```text
流事件（按「带哪个键」判别，六种之一）：
  { text }          正文——唯一会进用户内容的变体
  { reasoning }     思维链片段——绝不能混进正文，所以独立一种
  { serverTool }    端点自己跑的工具（纯上报，无需回传）
  { turnResumed: { leg, final } }   一次调用变成多次 HTTP 请求的可观测信号
  { done, inputTokens, outputTokens,
    truncated?      finish_reason=length / MAX_TOKENS / max_tokens 归一化后的布尔
    stopReason?     端点原话，只做诊断，永不作分支条件
    cachedTokens?   inputTokens 的子集（已归一化，见 06 §1）
    wireRewrites?   [{ field: reasoning.effort|temperature, sent, echoed }]  回显≠发出（06 §4.1） }
  { toolCalls, _geminiModelParts?, _reasoning?, _thinkingBlocks?, _responseItems? }
                    工具轮：整轮回传载体随 toolCalls 一起交付
```

设计准则：

- **正文与思维链必须是不同变体。** 混流的后果是思考散文进入用户稿子（见第 3 篇）。
- **`stopReason` 只做诊断，永不作为分支条件**——它是端点原话，各家拼写不同且随时增补；需要分支的语义（截断）单独归一化成 `truncated` 布尔。
- `done` chunk 携带归一化后的 usage（口径见第 6 篇）。

## 6. 统一入口 streamCompletion 与 StreamOptions

所有调用最终收敛到一个入口，在这里完成横切关注点（prefix 合并、上下文预检、日志接线），然后按族分发。按顺序做五件事（参考实现里这就是入口函数的全部内容）：

1. 把模型级前缀 prompt 合进首条 system（**返回新列表**，不改传入的）。
2. 开一条 API 日志记录。
3. 若声明了上下文窗口：估算 消息 + 工具定义 的 token，超窗即在发送前抛「上下文超限」错误。
4. 给日志装「请求体」「流事件」两个钩子——**串联**调用方已有的同名钩子，不覆盖（06 §4.2）。
5. 按 `familyOf(standard)` 分发到四个族适配器之一，默认落 ① 族。

统一入口的请求参数（节选）：`baseUrl / apiKey / standard / authMode / modelId / messages / onChunk / signal / tools / serverTools / toolChoice / extraBody / safetySettings / prefix / contextSize / maxOutput / reasoningEffort / thinkingDialect / _onRequestBody`。

其中几个字段的语义必须写进规范，因为它们在各族上行为不同：

- **`extraBody`** —— per-request escape hatch，优先级高于配置（OpenAI 路径最后 spread）；Gemini 路径也收（JSON 模式用它塞 `generationConfig`）；**Anthropic 路径故意不 spread**——它携带的是 OpenAI 形状字段（如 `response_format`），Messages API 对未知顶层字段直接 400。规则：escape hatch 的形状属于某一族时，其他族的适配器应当拒绝 spread 而不是"透传以示通用"。
- **`maxOutput`** —— 只有 Anthropic 路径真的发出去（`max_tokens` 必填、无服务端默认）；OpenAI/Gemini 路径上只作上下文预算的规划输入。
- **`contextSize`** —— 发送前用估算器拦截超窗请求，抛 `ContextSizeError`（携带 estimated/contextSize 两个数字供 UI 展示）。理由：ollama 这类本地栈会**静默从头部丢弃**超出部分（先丢的正是 system 指令），返回 200 装没事——事后无法发现，只能事前拦。
- **`prefix`** —— 模型级前缀 prompt，`applyPrefix` 合并进首条 system。**必须不可变、返回新数组**——agent 循环跨轮复用同一 history 数组，原地修改会把 prefix 重复叠加。

## 7. config→request 的收口：连接参数单点摊平

背景教训（来自参考实现）：约 9 个传输字段全部可选，曾在 16 个调用点手工摊平、8 个参数类型重复声明——漏一处**不是编译错误，是某个界面静默行为不一致**（可选字段的遗漏类型系统查不出来）。

收口方案（参考实现叫 `conn` 模块）：

```text
连接 = { 供应商行, 模型行, 密钥 }
连接参数 ConnOptions = 请求参数里「来自配置」的那一半：
  baseUrl, apiKey, standard, authMode?, safetySettings?, modelId, prefix?,
  contextSize?, maxOutput?, reasoningEffort?, thinkingDialect?, serverTools?
connOptions(连接)        -> ConnOptions      逐字段摊平，全项目只此一处
pickConnOptions(参数)    -> ConnOptions      反向收窄
resolveConn(模型表, 供应商表, modelId) -> 连接 | 未选模型 | 模型已删 | 供应商已删
```

规则：

- 任何携带供应商接线的参数结构都**包含** ConnOptions；调用点统一由 `connOptions(连接)` 展开再补 messages 等调用参数。
- **新增一个 L2/L3 传输字段 = 改 `ConnOptions` + `connOptions()` + `pickConnOptions()` 三处，且在同一文件。**"加字段 = 改一处（文件）"是这个模式的全部意义。
- 两份手写字段表（摊平与收窄）的分歧由**往返单测**盯住——类型系统查不出可选字段的遗漏。
- `resolveConn` 的三种失败（未选模型 / 模型已删 / 供应商已删）保持可区分，UI 才能给出正确的修复指引。
- 陷阱：`connOptions` 刻意**不给空 baseUrl 填默认值**。空串意为"用该协议自己的默认"，只有 URL 模块知道那是哪个；在 conn 层填 `api.openai.com` 会把 Gemini 供应商指过去——参考实现历史上真发生过这个 bug。
- 收口时机：调用点 ≥3 个时就该收口，别等到 16 个。

## 8. 多面供应商：surface × 协议菜单，与模型级协议选择

> 2026-08 增补，来源：阿里百炼（千问平台）与 MiniMax 官方文档全量核对 +
> Joycai Image AI Toolkits 的 vendor–protocol–model 路由重构。
> 解决的问题：**「一家供应商 = 一个协议族」的绑定撑不住了**。

### 8.1 事实：一家供应商可以在同一个 surface 上有多条协议，且与模型耦合

- **阿里百炼**一把 key 六条 wire：chat 有 OpenAI 兼容（`/compatible-mode/v1`）、
  DashScope 私有（`/api/v1/services/aigc/text-generation/…`）、Anthropic 兼容
  （`/apps/anthropic/v1/messages`）三张脸；生图分同步/异步（**提交路径不同**，
  不是加 header 切换）；视频只有异步任务。且协议可用性**按模型分**：
  Qwen-Audio 仅私有面、Anthropic 面只服务模型子集、qwen-image 仅同步、
  wan2.7-image 同步异步皆可（用户选）、wan3.0 视频仅异步。
- **OpenAI 官方**已有 Responses-only 模型（o1-pro / codex 系 /
  computer-use，截至 2026-08）——同一家的 chat surface 有两条结构不兼容的
  wire，走哪条由模型决定。Google 的 Interactions 与 generateContent 同构。
- **MiniMax** 的反例同样重要：①/④ 两张 chat 脸的**模型 id 完全一致**
  （无模型耦合），视频则是独立的私有任务面（`/v2/video_generation`）。

### 8.2 概念：surface 与协议菜单

- **Surface（调用面）**：chat / imageGen / videoJob / discovery。四个就够——
  三家官方的全部生成面都装得下；Responses/Interactions 是 chat 槽位的候选
  协议，不是新 surface。**同一个 wire format 可以服务两个 surface**
  （Gemini generateContent 既是 chat 也是出图），所以协议目录是
  Surface × WireProtocol 二维的。
- **L2 的声明从「一个协议族」升级为「per surface 的菜单 + 默认值」**：

```text
供应商的 surface 声明：
  chat:  默认 WireProtocol + 菜单里的其它选项
  image: 默认 WireProtocol（可空）+ 其它选项
  video: 默认 WireProtocol（空 = 这家没有该 surface）
```

- **L3 增加一个可选的「协议点单」字段**（用户配置，存库）：
  解析顺序 = 模型点单（且在菜单内）→ L2 该 surface 默认 → 按模型分类推导。
  点单不在菜单内（如供应商行改了类型）→ 静默回退 auto + WARN，不炸——
  点单是**偏好**不是路由事实，失效的偏好可以安全忽略。
  注意它**不是可推导数据的副本**（那种列是 bug 面，禁止落库），而是与
  「思考开关」同性质的用户选择，无处可推导。

### 8.3 裁决标准：通道级选面 vs 模型级点单

一家多协议有两种表达，标准一句话：**协议与模型有耦合才点单，没有就分行**。

| 手段 | 适用 | 例 |
| --- | --- | --- |
| **分成多个 L2 行**（UI 上做成一行 + 变体分段控件） | 各面**模型集合一致**，差异只是路径/auth/方言 | MiniMax ①/④、Google native/兼容面、New API 三格式 |
| **一个 L2 行 + 菜单 + 模型点单** | 协议可用性按模型分、或同一模型多条路可选 | 百炼全家、wan2.7 同步/异步、OpenAI Responses-only 模型 |

两者可并用：MiniMax 的 chat 保持双行，但视频槽位声明在**两行上各一份**
（无论用户配的是哪张 chat 脸，视频模型都可用）——视频面是供应商的 surface，
不是某张 chat 脸的附属。

### 8.4 路径推导：一个 base 服务多条 wire

模型点单要成立，前提是一个 L2 行（一个 baseUrl、一把 key）能到达所有面。
做法：**协议自己从 base 推导路径，只认路径、不认 host**（intl 域名同样成立），
且推导幂等（输入已是目标形状 / 裸 host / 带尾斜杠都得到同一结果）：

- 百炼：剥 `/compatible-mode/v1` → 拼 `/api/v1`（私有面）或
  `/apps/anthropic/v1`（④ 面）；
- MiniMax：剥 `/v1` 或 `/anthropic/v1` → 拼 `/v2/…`（视频面）。

反面（存后缀进配置）只在「分行」手段里用——变体切换重写 endpoint 是
通道级选面的实现，别和推导混用在同一家的同一个面里。

### 8.5 退化情形零开销

单协议供应商（Anthropic 官方、各中继、本地运行时）= 单项菜单：不出现任何
选择 UI、auto 即全部行为。通用化不向简单情形收税——这是这套设计能默认开启
而不是藏在高级选项里的原因。

## 9. 供应商数据行样例：xAI（Grok）、New API 中转站、火山方舟与智谱（2026-09）

> 来源：simple-ai-writer `docs/api/landscape.md` §7 第八、十、十一个样本（均为实测）。
> 用意：示范「加一家 = 加一行数据 + 一段厂商注记」，以及哪些行为只能写进注记、不能写进代码分支。

### 9.1 xAI：一行预设，零 adapter 改动

- **数据行**：`{ name: "xAI (Grok)", apiStandard: "openai_responses_compat", baseUrl: "https://api.x.ai/v1" }`，Bearer。
  xAI 自己把 Responses 标为推荐接口，Chat Completions 标 **Deprecated**（仍作 legacy 提供），
  Anthropic SDK 兼容面（`/v1/messages`）标完全弃用——所以预设选 ② 族。
- **实测差异（写进注记，不进分支）**：
  - effort：grok-4.5 / 4.6 **拒 `none`**（关不掉思考），`max` 在 4.3/4.5/4.6 全部 400——菜单与默认值见第 3 篇 §7.1。
  - 图片最小 **512 像素总数**（16×16 被拒；32×32 通过），宽高各 ≥8。测试夹具的小图会撞上。
  - 加密推理：须发 `include:["reasoning.encrypted_content"]` 才有 `encrypted_content`，缺了第二轮照样 200 且答对，见第 3 篇 §7.3。
  - 流里**有** `response.completed`（带 usage）+ `[DONE]` 收尾（文档没写终止事件，实测有）。
  - 推理模型上发 `frequency_penalty` 实测 200 未报错（文档说会报错）——文档与实测不符按实测记。
  - `tool_search` / `defer_loading` 实测 403（仅 alpha 用户），见第 5 篇 §7。

### 9.2 New API 中转站：只能写进注记的四种静默行为

两台 New API（`[Pro]` / `[Plus]` 档）上 GPT-5.x 的实测，全部是"不报错、只改账单或质量"：

1. **不发 `instructions`（system）就注入 Codex 系统提示**：一次 4.4K–9K 输入 token，**Chat 面同样注入**。
   规则：对这类端点永远显式发 system（② 族 adapter 恒发 `instructions`，哪怕空串）。
2. **改写 effort / temperature**（GPT-5.6）：sol 发 `max` 回显 `none` 且 0 推理 token；terra 发 `none` 两次都回显 `medium` 且照样推理；
   `temperature:0.5` 回显 `1.0`。对策是回显比对（第 6 篇 §4.1），不是重试。
3. **无视 `max_output_tokens`**（其中一台）：截断状态永远不会出现。
4. **一个档位背后多个上游**：同一请求的响应形状时有时无回显字段——每次落到哪个上游，请求侧无法决定。

另：档位前缀模型 id（`[Plus]gpt-5.6-terra`）让按 id 前缀查表的逻辑认不出——不要为此加剥前缀规则
（会吞掉别家中继的别名），让作者手动声明。

### 9.3 字节跳动 · 火山方舟（豆包 / Seedream）：两个 base 是同一行的两个变体

> 来源：Joycai Image AI Toolkits 接入 Seedream（2026-09-18，官方文档 + 套餐 key 实测）。
> 出图协议本身见第 13 篇 §4.1。

- **数据行**：一家、一把 key、一个 host（`ark.cn-beijing.volces.com`），Bearer。chat 是 ① 族
  （`{base}/chat/completions`），出图是同 base 下的 `/images/generations`（第 13 篇的 `ark` route），
  声明为该行 image surface 的菜单——**不新增协议族**：它的 auth、发现、错误信封都是 OpenAI 形。
- **两个 base、两种 key，互不通用**：按量付费 `…/api/v3`，订阅套餐（Agent / Coding Plan）
  `…/api/plan/v3`，路径后缀完全相同。套餐 key 打 `/api/v3` 得 401。按 §8.3 的裁决标准这是
  「分行」（差异只在 base，模型集合按套餐裁剪），UI 上做成**一行 + 两个变体**，且**两个变体
  同一个 channel type**——由此出现一个新不变量：
  - **变体必须按地址回读**。只按 type 找变体，套餐渠道会被读成按量变体，编辑器随即提议把地址
    「恢复」成它的 key 必定 401 的 base。回读 = 类型匹配后再比 endpoint（去尾斜杠），都不中才
    落回首个变体。
  - 变体卡的副标题不能只印协议族（两张一样），兄弟变体同族时印路径。
- **套餐没有模型列表**：`GET /api/plan/v3/models` → 404，非 JSON body。发现逻辑遇 404 退回
  L2 行自带的静态目录（按量带日期 id + 套餐别名），不当连接失败。
- **套餐按模型裁剪、且挑拼写**：只服务 5.0 pro / 5.0 lite；`doubao-seedream-5.0-pro`、
  `doubao-seedream-5.0-lite`（套餐文档写法）与带日期的 `…-5-0-pro-260628`、
  `…-5-0-lite-260128` 都收，**不带 `lite` 的** `doubao-seedream-5-0-260128`（按量文档里 lite 的
  正式 id）与 4.5 / 4.0 回 `404 UnsupportedModel`。模型分类因此要认「`5-0` 与 `5.0` 同一代、六位
  日期不是次版本、lite 有三种拼写」。
- **套餐 base 也服务对话**（同路径 `/chat/completions`）：可用 `doubao-seed-2.0-pro`、别名 `ark-code-latest`，其余 Seed 1.6 系回
  `404 UnsupportedModel`；思考控制就是 ① 的 `reasoning_effort`，不要给它声明别家的方言（第 3 篇 §3.2，实测 2026-09-18）。
- **Endpoint ID（`ep-…`，推理接入点）可以替代 model id**，从 id 上看不出是哪一代：分类失败是
  正常情况，让作者点单（声明它是出图模型 + 选 `ark` route），点单后落到协议兜底参数表。
- **中转站例外**：认得出的 Seedream id 挂在 ① 族中转上时，默认 route 也是 `ark`（菜单首项，
  Images API / chat 出图仍可点单）。理由：`ark` 的路径就是 Images API 的
  `{base}/images/generations`，在中转 host 上有意义——「中转不提供厂商私有协议」防的是
  **从 endpoint 推导出的私有路径**，这里没有推导，只是 body 形状不同。

### 9.4 智谱 BigModel 开放平台（GLM）：一把 key 走遍所有路径，路径决定计费

> 来源：simple-ai-writer `docs/api/landscape.md` §7 第十四个样本、`docs/api/zhipu-plan.md`（2026-09-19，按量 key 实测全部 11 个对话模型）。

- **数据行**：host `open.bigmodel.cn`，Bearer；① 族标准端点 `…/api/paas/v4`（`/chat/completions`、`/models`）。
  `/models` 是 OpenAI 形（`{object:"list", data:[{id,…}]}`），连接测试直接可用。【实测 2026-09-19】
- **四个前缀，一把 key 全通**：① `/api/paas/v4`（标准）、① `/api/coding/paas/v4`、④ `/api/anthropic`、② `/api/v1`。
  后三个是 GLM Coding Plan 的「编程端点」，按量 key 打上去同样 200。**与火山方舟（§9.3，两种 key 在对方路径上 401）
  正相反：这里是路径决定扣余额还是扣套餐**，选错不会失败、只会换一笔钱；套餐条款又只许「指定工具」使用，违规限流乃至封号。
  按 §8.3 裁决应「分行」，而且**不能把编程端点挂进按量行的线路菜单**——作者切一条线路就在不知情时换了计费与条款。
  【实测 2026-09-19 + 文档】
- **② 面的 `/api/v1/models` 不是 OpenAI 形**：是 Codex CLI 的模型目录（`{models:[{slug, context_window,
  supported_reasoning_levels, input_modalities, …}]}`），只列 3 个模型。④ 面 `/v1/models` 是 Anthropic 形。
- **模型集合**：11 个对话 id（glm-4.5 / 4.5-air / 4.6 / 4.7 / 5 / 5-turbo / 5.1 / 5.2 / 5.3 / 5.3-flash / 5.3-flashx）。
  **思考控制按代分三种**（第 3 篇 §3.1），**只有 5.3-flash / flashx 读图**，其余文本模型收到 `image_url` 直接 400。
  这是「协议族默认的思考参数在一家之内就不对」的样本：按族取默认值（① 族 = `reasoning_effort`）在 11 款上全错，
  所以参数必须**按模型 id 预填**（一张平台级校准表），不能只靠族默认 + 作者手选。
- **max_tokens 上界**（400 生成前拒、不计费，报出范围）：5.x 与 4.6 / 4.7 为 131,072，4.5-air 为 98,304，**glm-4.5 实测
  也是 131,072**（文档写 96K）。上下文：5.3 / 5.3-flash(x) / 5.2 1M，5-turbo 204,800，5.1 / 5 / 4.7 / 4.6 200K，4.5 系列 128K。

---

## 本篇检查清单

- [ ] 运行时 adapter 数量 = 协议族数量，没有任何"每供应商一个类/文件"的形态。
- [ ] 每个候选新参数都用"归属判断法"过了一遍（body 形状→L1；换端点变→L2；换模型变→L3；只能实测→探测维）。
- [ ] `ApiStandard` 只在 body 形状不同时增加值；official/compat 成对出现。
- [ ] 全部消息形状分支按折回后的族判断，找不到按 standard 原值判断消息形状的代码。
- [ ] `familyOf` 对未知/旧枚举值有防御性兜底（不抛错，落回默认族）。
- [ ] 内部消息统一为一种 lingua franca 形状；跨协议私有数据全部用 `_` 前缀字段承载。
- [ ] adapter 发出 wire 消息前按 `_` **前缀**（而非名单）剥除私有字段。
- [ ] `StreamChunk` 用 key 判别；新增变体后，跑一遍旧消费者确认是 no-op。
- [ ] `stopReason` 没有出现在任何 `if`/`switch` 条件里（只展示/记日志）。
- [ ] 存在唯一入口 `streamCompletion`，prefix 合并、上下文预检、日志接线都在入口做，不散落在调用方。
- [ ] `applyPrefix` 等消息变换函数是纯函数，不修改传入数组。
- [ ] 配置 → 请求参数只在一处摊平；所有携带供应商接线的参数结构都包含这份连接参数；有摊平/收窄的往返单测。
- [ ] `connOptions` 不给空 baseUrl 填任何默认值。
- [ ] 多面供应商：L2 声明的是 per-surface 菜单而非单一协议族；surface 布尔
      开关（`usesXxxNativeSurfaces` 式）没有随供应商增多而平方增长。
- [ ] 模型级协议点单：解析顺序（点单→菜单默认→分类推导）单点实现；点单失效
      回退 auto + WARN；单项菜单不渲染任何选择 UI。
- [ ] 多 wire 共用一个 base 的路径推导幂等、只认路径不认 host，有纯函数测试。
- [ ] ② Responses 是独立族（`openai_responses` / `_compat` + `ProtocolFamily "responses"`），不是 ① 族里的布尔开关；加族时逐个过了全部 `familyOf` 调用点。
- [ ] 统一入口给自己装的钩子（`_onRequestBody` 等）**串联**调用方的同名钩子，不覆盖。
- [ ] 同一 channel type 挂多个变体（火山方舟按量/套餐）时，变体按 endpoint 回读，编辑器不会把地址「恢复」到别的变体。
- [ ] 中转站的静默行为（注入 system、改写 effort/temperature、无视 `max_output_tokens`、多上游）记在厂商注记里，代码侧只有「恒发 instructions」「回显比对」两条通用对策，没有按中转站名分支。
- [ ] 一把 key 能打多个前缀、由路径决定计费的平台（智谱 BigModel），不同计费的前缀分在不同的行里，没有挂进同一行的线路菜单。
