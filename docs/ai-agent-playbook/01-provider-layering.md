# 01 · 分层模型与统一抽象

> 本篇解决的问题：同时对接 OpenAI Chat Completions、OpenAI Responses、Google Gemini、Anthropic Messages 四个协议族，以及大量第三方"兼容"中继（New API、MiniMax、DeepSeek、千问 DashScope、OpenRouter、Ollama、LM Studio…）时，代码应当如何分层，才能做到「加一家新供应商 = 加一行数据，不是加一个文件」。
> 不读会踩的坑：为每家供应商建一个 Provider 子类，第三方之间 99% 相同的代码被复制 N 份；`switch (standard)` 写在消息形状分支上，每个新 `_compat` 值静默掉进 OpenAI 分支；传输配置在十几个调用点手工摊平，漏一处不是编译错误而是某个界面静默行为不一致。

参考实现：simple-ai-writer `src/lib/ai/`（`types.ts`、`index.ts`、`conn.ts`），设计文档 `docs/provider-layering.md`。

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

```ts
// 参考实现：simple-ai-writer src/lib/ai/types.ts
export type ApiStandard =
  | "openai" | "openai_compat"
  | "openai_responses" | "openai_responses_compat"   // ② 族，2026-09 加入
  | "gemini" | "gemini_compat"
  | "anthropic" | "anthropic_compat";

export type ProtocolFamily = "openai" | "responses" | "gemini" | "anthropic";

export function familyOf(standard: ApiStandard): ProtocolFamily {
  return PROTOCOL_FAMILY[standard] ?? "openai";  // DB 旧值的防御性兜底
}
```

`_compat` 不是装饰，两种契约实质不同：

| | official 契约 | compat 契约 |
| --- | --- | --- |
| 地址 | 锁定（存空串，域名变更是代码改动不是数据迁移） | 自填（要归一化） |
| 鉴权 | 锁定 | 可选（下拉，见第 2 篇鉴权矩阵） |
| `/models` | 缺失视为错误 | 缺失降级探测（见第 6 篇） |
| 能力默认值 | 乐观 | 保守 |

**分发规则（红线）**：凡是问"消息长什么样"的地方必须 `switch (familyOf(standard))` 而不是 `switch (standard)`——否则每个新增的 `_compat` 值都会静默掉进 default（OpenAI）分支。只有 official/compat 契约差异（地址校验、鉴权选项、探测策略）才允许直接看 standard。

### 3.1 案例：② Responses 为什么是第四族而不是 `useResponses` 开关

参考实现：simple-ai-writer `src/lib/ai/responses.ts`，决策记录 `docs/api/qianwen-compat-plan.md` §4.3。

按 §2 的判定标准，Responses 与 ① 同厂、同 base（官方 `https://api.openai.com/v1`，adapter 自己拼 `/responses`）、同 `Authorization: Bearer`、`/models` 探测复用 ① 族——**但"只改 URL 就跑通"不成立**：body（`instructions` + `input` 条目 vs `messages`）、流（类型化事件 vs `choices[].delta`）、工具形状（扁平 + 自动 strict vs 嵌套）、回传义务（整组 output 条目 vs assistant 消息）四样全不同。在 ① 族 adapter 里加 `useResponses` 布尔，等于把四处分支塞进一个文件、并让每个 `switch (familyOf)` 调用点读不到这个差异。落地做法：

- `ApiStandard` 加 `openai_responses` / `openai_responses_compat` 成对两值，`ProtocolFamily` 加 `"responses"`，统一入口多一个 `case "responses"`。
- **加族 = 逐个过 `familyOf` 调用点**（参考实现 12 处：模型/供应商抽屉、两个探测器、出图、入口、jsonMode、modelSummary、reasoning、serverTools、types、urls）。漏过的调用点会静默落进 default（① 族）分支。
- `authMode` 在此族无意义（只有 Bearer），`authModesFor` 只给 `default`。

## 4. 内部 lingua franca：OpenAI Chat Completions 形状

内部消息表示应当统一选一种形状，推荐 OpenAI chat.completions：`system/user/assistant/tool` 角色、`tool_calls`、`tool_call_id`、`image_url` data-URL 多模态 part。Gemini/Anthropic 适配器各自做**单向转换**（`convertToGeminiContents` / `convertToAnthropicMessages`），转换只发生在 adapter 内部、发出前的最后一刻。

跨协议无法用 OpenAI 形状表达的东西（思维链回传物、Gemini 的 thoughtSignature 等），用 **`_` 前缀私有字段**随消息携带，adapter 上线前按前缀统一剥除：

```ts
// 参考实现：simple-ai-writer src/lib/ai/types.ts —— 全部消息变体
export type StreamMessage =
  | { role: "system" | "user" | "assistant"; content: MessageContent }
  | {
      role: "assistant";
      content: null;
      tool_calls: AssistantToolCall[];
      _geminiModelParts?: unknown[];          // Gemini 原始 parts（含 thoughtSignature）
      _reasoning?: NativeReasoning;           // OpenAI 系思维链（{field, text}），工具轮回传用
      _thinkingBlocks?: ThinkingBlockCarry;   // Anthropic thinking blocks（{modelId, blocks}）
      _responseItems?: ResponseItemCarry;     // ② Responses 整组 output 条目（{modelId, items}）
    }
  | { role: "tool"; tool_call_id: string; content: string };

export type ContentPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string } }; // url = data:<mime>;base64,<data>
```

**剥除按前缀，不按名单。** 参考实现（`src/lib/ai/openai.ts` 的 `toWireMessages`）：

```ts
// "Drop by prefix rather than by name: every protocol that needs carry-back adds
// a field here, and an allow-list of names silently lets the next one through
// to the wire."
const wire = Object.fromEntries(Object.entries(bag).filter(([k]) => !k.startsWith("_")));
const reasoning = bag._reasoning as NativeReasoning | undefined;
return reasoning ? { ...wire, [reasoning.field]: reasoning.text } : wire;
```

陷阱：如果剥除逻辑是一张字段名白名单，下一个协议加的 `_` 字段会被静默放行到 wire 上——多数端点对未知顶层键直接 400。前缀约定使"新增一个载体字段"零成本地安全。

## 5. 统一流事件：StreamChunk 变体联合

调用方只见一种 chunk 流。判别一律用 **key 判别**（`"text" in chunk` 式），因此**新增变体对旧消费者天然是 no-op**——这是加 `reasoning`/`serverTool` 变体不破坏任何调用点的机制，也是这个联合可以持续生长的前提。

```ts
// 参考实现：simple-ai-writer src/lib/ai/types.ts
export type StreamChunk =
  | { text: string }                       // 正文（会进稿子的唯一变体）
  | { reasoning: string }                  // 思维链片段（绝不能混进正文，故独立变体）
  | { serverTool: ServerToolEvent }        // 端点自己跑的工具（纯上报，无需回传）
  | { turnResumed: { leg: number; final: boolean } }  // 一次调用变多次请求的可观测信号
  | { done: true; inputTokens: number; outputTokens: number;
      truncated?: boolean;                 // finish_reason=length / MAX_TOKENS / max_tokens
      stopReason?: string;                 // 端点原话，仅诊断，永不分支
      cachedTokens?: number;               // inputTokens 的子集（已归一化）
      wireRewrites?: WireRewrite[] }       // 端点回显与发出值不一致的字段（仅 ② 族能填，见第 6 篇 §4.1）
  | { toolCalls: AccumulatedToolCall[];
      _geminiModelParts?: unknown[];
      _reasoning?: NativeReasoning;        // 整轮思维链，随 toolCalls 交付（仅工具轮需要）
      _thinkingBlocks?: ThinkingBlockCarry;
      _responseItems?: ResponseItemCarry };  // ② 族：本轮 output_item.done 收集的原样条目

interface WireRewrite { field: "reasoning.effort" | "temperature"; sent: string; echoed: string }
```

设计准则：

- **正文与思维链必须是不同变体。** 混流的后果是思考散文进入用户稿子（见第 3 篇）。
- **`stopReason` 只做诊断，永不作为分支条件**——它是端点原话，各家拼写不同且随时增补；需要分支的语义（截断）单独归一化成 `truncated` 布尔。
- `done` chunk 携带归一化后的 usage（口径见第 6 篇）。

## 6. 统一入口 streamCompletion 与 StreamOptions

所有调用最终收敛到一个入口函数，在这里完成横切关注点（prefix 合并、上下文预检、日志接线），然后按族分发：

```ts
// 参考实现：simple-ai-writer src/lib/ai/index.ts —— 全文即此
export async function streamCompletion(opts: StreamOptions): Promise<void> {
  const merged = { ...opts, messages: applyPrefix(opts.messages, opts.prefix) };
  const log = beginApiLog(merged);
  if (merged.contextSize && merged.contextSize > 0) {
    const estimated = estimateMessagesTokens(merged.messages) + estimateToolsTokens(merged.tools);
    if (estimated > merged.contextSize) { /* throw ContextSizeError（发送前拦截） */ }
  }
  const wrapped = { ...merged,
    // 日志自己的管线——但必须串联调用方的钩子，不能覆盖（见第 6 篇 §4.2）
    _onRequestBody: (body) => { log.requestBody(body); merged._onRequestBody?.(body); },
    onChunk: (chunk) => { log.chunk(chunk); merged.onChunk(chunk); } };
  switch (familyOf(wrapped.standard)) {
    case "gemini": await streamGemini(wrapped); break;
    case "anthropic": await streamAnthropic(wrapped); break;
    case "responses": await streamResponses(wrapped); break;
    default: await streamOpenAI(wrapped);
  }
}
```

`StreamOptions` 的传输字段（节选）：`baseUrl / apiKey / standard / authMode / modelId / messages / onChunk / signal / tools / serverTools / toolChoice / extraBody / safetySettings / prefix / contextSize / maxOutput / reasoningEffort / thinkingDialect / _onRequestBody`。

其中几个字段的语义必须写进规范，因为它们在三族上行为不同：

- **`extraBody`** —— per-request escape hatch，优先级高于配置（OpenAI 路径最后 spread）；Gemini 路径也收（JSON 模式用它塞 `generationConfig`）；**Anthropic 路径故意不 spread**——它携带的是 OpenAI 形状字段（如 `response_format`），Messages API 对未知顶层字段直接 400。规则：escape hatch 的形状属于某一族时，其他族的适配器应当拒绝 spread 而不是"透传以示通用"。
- **`maxOutput`** —— 只有 Anthropic 路径真的发出去（`max_tokens` 必填、无服务端默认）；OpenAI/Gemini 路径上只作上下文预算的规划输入。
- **`contextSize`** —— 发送前用估算器拦截超窗请求，抛 `ContextSizeError`（携带 estimated/contextSize 两个数字供 UI 展示）。理由：ollama 这类本地栈会**静默从头部丢弃**超出部分（先丢的正是 system 指令），返回 200 装没事——事后无法发现，只能事前拦。
- **`prefix`** —— 模型级前缀 prompt，`applyPrefix` 合并进首条 system。**必须不可变、返回新数组**——agent 循环跨轮复用同一 history 数组，原地修改会把 prefix 重复叠加。

## 7. config→request 的收口：conn.ts 模式

背景教训（来自参考实现）：约 9 个传输字段全部可选，曾在 16 个调用点手工摊平、8 个参数类型重复声明——漏一处**不是编译错误，是某个界面静默行为不一致**（可选字段的遗漏类型系统查不出来）。

收口方案：

```ts
// 参考实现：simple-ai-writer src/lib/ai/conn.ts
export interface AiConn { provider: Provider; model: Model; apiKey: string }

export interface ConnOptions {   // StreamOptions 中"来自配置"的那一半，结构子集
  baseUrl: string; apiKey: string; standard: ApiStandard;
  safetySettings?: GeminiSafetySettings; authMode?: AuthMode;
  modelId: string; prefix?: string; contextSize?: number; maxOutput?: number;
  reasoningEffort?: ReasoningEffort; thinkingDialect?: ThinkingDialect;
  serverTools?: ServerToolId[];
}
export function connOptions(conn: AiConn): ConnOptions { /* 逐字段摊平 */ }
export function pickConnOptions(o: ConnOptions): ConnOptions { /* 反向收窄 */ }
export function resolveConn(models, providers, modelId): ConnResolution
  // 三种失败保持可区分：未选模型 / 模型已删 / 供应商已删
```

规则：

- 任何携带 provider 接线的参数类型 **`extends ConnOptions`**；调用点统一写 `{...connOptions(conn), messages, onChunk}`。
- **新增一个 L2/L3 传输字段 = 改 `ConnOptions` + `connOptions()` + `pickConnOptions()` 三处，且在同一文件。**"加字段 = 改一处（文件）"是这个模式的全部意义。
- 两份手写字段表（摊平与收窄）的分歧由**往返单测**盯住——类型系统查不出可选字段的遗漏。
- `resolveConn` 的三种失败（未选模型 / 模型已删 / 供应商已删）保持可区分，UI 才能给出正确的修复指引。
- 陷阱：`connOptions` 刻意**不给空 baseUrl 填默认值**。空串意为"用该协议自己的默认"，只有 URL 模块（`urls.ts`）知道那是哪个；在 conn 层填 `api.openai.com` 会把 Gemini 供应商指过去——参考实现历史上真发生过这个 bug。
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

```ts
interface VendorSurfaces {
  chat: WireProtocol;                 // 默认
  chatAlternates?: WireProtocol[];    // 菜单里的其它选项
  image?: WireProtocol; imageAlternates?: WireProtocol[];
  video?: WireProtocol;               // null = 这家没有该 surface
}
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

## 9. 供应商数据行样例：xAI（Grok）与 New API 中转站（2026-09）

> 来源：simple-ai-writer `docs/api/landscape.md` §7 第八、十、十一个样本（均为实测）。
> 用意：示范「加一家 = 加一行数据 + 一段厂商注记」，以及哪些行为只能写进注记、不能写进代码分支。

### 9.1 xAI：一行预设，零 adapter 改动

- **数据行**：`{ name: "xAI (Grok)", apiStandard: "openai_responses_compat", baseUrl: "https://api.x.ai/v1" }`，Bearer。
  xAI 自己把 Responses 标为推荐接口，Chat Completions 标 **Deprecated**（仍作 legacy 提供），
  Anthropic SDK 兼容面（`/v1/messages`）标完全弃用——所以预设选 ② 族。
- **实测差异（写进注记，不进分支）**：
  - effort：grok-4.5 / 4.6 **拒 `none`**（400），`max` 在 4.3/4.5/4.6 全部 400；默认回显 `high`。
    菜单不按型号裁剪，越界由端点 400 说话（第 3 篇 §7）——但作者要知道这两款**关不掉思考**。
  - 图片最小 **512 像素总数**（16×16 被拒；32×32 通过），宽高各 ≥8。测试夹具的小图会撞上。
  - 加密推理：不发 `include:["reasoning.encrypted_content"]` 时 reasoning 条目没有 `encrypted_content`；
    但不带它原样回传，工具第二轮照样 200 且答对——缺的只是往轮推理的延续。
  - 流里**有** `response.completed`（带 usage）+ `[DONE]` 收尾（文档没写终止事件，实测有）。
  - 推理模型上发 `frequency_penalty` 实测 200 未报错（文档说会报错）——文档与实测不符按实测记。
  - `tool_search` / `defer_loading` 实测 403（仅 alpha 用户），见第 7 篇 §4.6。

### 9.2 New API 中转站：只能写进注记的四种静默行为

两台 New API（`[Pro]` / `[Plus]` 档）上 GPT-5.x 的实测，全部是"不报错、只改账单或质量"：

1. **不发 `instructions`（system）就注入 Codex 系统提示**：一次 4.4K–9K 输入 token，**Chat 面同样注入**。
   规则：对这类端点永远显式发 system（② 族 adapter 恒发 `instructions`，哪怕空串）。
2. **改写 effort / temperature**：发 `max` 回显 `none` 且 0 推理 token；发 `none` 回显 `medium`；
   `temperature:0.5` 回显 `1.0`。对策是回显比对（第 6 篇 §4.1），不是重试。
3. **无视 `max_output_tokens`**（其中一台）：截断状态永远不会出现。
4. **一个档位背后多个上游**：同一请求的响应形状时有时无回显字段——每次落到哪个上游，请求侧无法决定。

另：档位前缀模型 id（`[Plus]gpt-5.6-terra`）让按 id 前缀查表的逻辑认不出——不要为此加剥前缀规则
（会吞掉别家中继的别名），让作者手动声明。

---

## 本篇检查清单

- [ ] 运行时 adapter 数量 = 协议族数量，没有任何"每供应商一个类/文件"的形态。
- [ ] 每个候选新参数都用"归属判断法"过了一遍（body 形状→L1；换端点变→L2；换模型变→L3；只能实测→探测维）。
- [ ] `ApiStandard` 只在 body 形状不同时增加值；official/compat 成对出现。
- [ ] 全部消息形状分支写的是 `switch (familyOf(standard))`，grep 不到直接 `switch (standard)` 的消息形状代码。
- [ ] `familyOf` 对未知/旧枚举值有防御性兜底（不抛错，落回默认族）。
- [ ] 内部消息统一为一种 lingua franca 形状；跨协议私有数据全部用 `_` 前缀字段承载。
- [ ] adapter 发出 wire 消息前按 `_` **前缀**（而非名单）剥除私有字段。
- [ ] `StreamChunk` 用 key 判别；新增变体后，跑一遍旧消费者确认是 no-op。
- [ ] `stopReason` 没有出现在任何 `if`/`switch` 条件里（只展示/记日志）。
- [ ] 存在唯一入口 `streamCompletion`，prefix 合并、上下文预检、日志接线都在入口做，不散落在调用方。
- [ ] `applyPrefix` 等消息变换函数是纯函数，不修改传入数组。
- [ ] 存在 `ConnOptions` 收口；所有携带 provider 接线的参数类型 `extends ConnOptions`；有摊平/收窄的往返单测。
- [ ] `connOptions` 不给空 baseUrl 填任何默认值。
- [ ] 多面供应商：L2 声明的是 per-surface 菜单而非单一协议族；surface 布尔
      开关（`usesXxxNativeSurfaces` 式）没有随供应商增多而平方增长。
- [ ] 模型级协议点单：解析顺序（点单→菜单默认→分类推导）单点实现；点单失效
      回退 auto + WARN；单项菜单不渲染任何选择 UI。
- [ ] 多 wire 共用一个 base 的路径推导幂等、只认路径不认 host，有纯函数测试。
- [ ] ② Responses 是独立族（`openai_responses` / `_compat` + `ProtocolFamily "responses"`），不是 ① 族里的布尔开关；加族时逐个过了全部 `familyOf` 调用点。
- [ ] 统一入口给自己装的钩子（`_onRequestBody` 等）**串联**调用方的同名钩子，不覆盖。
- [ ] 中转站的静默行为（注入 system、改写 effort/temperature、无视 `max_output_tokens`、多上游）记在厂商注记里，代码侧只有「恒发 instructions」「回显比对」两条通用对策，没有按中转站名分支。
