# 06 · 错误处理、usage、探测与可观测性

> 本篇解决的问题：在兼容层世界里回答三个问题——「这次调用成功了吗」（默认答案 HTTP 200=成功在兼容层上是**错**的）、「这次花了多少钱」（两个口径陷阱会让你少报一个数量级）、「这个端点实际能接受什么」（文档/网关/作者说的都不算数）。
> 不读会踩的坑：过期密钥被读成一次正常空回复；长 prompt + 缓存命中时 input 少报一个数量级；Gemini 思考 token 全部漏计；被限流的探测请求被记录成上下文上限的证据；API key 泄进日志与错误消息。

参考实现：simple-ai-writer `src/lib/ai/usage.ts`、`modelHealth.ts`、`apiLog.ts`、`providerProbe.ts`、`endpointProbe.ts`、`probeAnalysis.ts`，以及三个适配器的错误通道处理。

---

## 1. usage 归一化：两个口径陷阱

内部统一口径：

- `inputTokens` —— 总输入；
- `outputTokens` —— 总输出，**含思考**；
- `cachedTokens` —— **inputTokens 的子集**，按缓存价计费的部分。

计费公式：`(input − cached) × 全价 + cached × 缓存价`。

两处**必须**归一化，否则数字直接错：

1. **Anthropic 三桶不重叠**（参考实现：`anthropic.ts` 的 `readUsage`）：`input_tokens` 只是未命中缓存的余量，`cache_read_input_tokens`、`cache_creation_input_tokens` 单列。总输入 = 三者之和——直接读 `input_tokens` 会在长 prompt + 缓存命中时**少报一个数量级**。cache write 计价高于基础价而费率表通常没这档，归入全价桶——宁可高估（用户拿这个数决定跑不跑，高估是安全方向）。另外 `message_delta` 只报 output，不能让它缺失的 input 字段清零 `message_start` 已立的数（`input || prev.inputTokens`）。
2. **Gemini 思考不在 `candidatesTokenCount` 里**：`outputTokens = candidatesTokenCount + thoughtsTokenCount`——只读前者会把"思考 5k、回答 500"记成 500，少算的正是最贵的部分。（①④ 的输出已含思考，details 只是明细。）

### 持久化与 rollup

参考实现：`src/lib/ai/usage.ts`。

- `persistUsage` 每次调用一行（model_id / task / prompt / cached / completion / cost / created_at），**best-effort 永不抛**——记账不能炸调用方。
- 读侧两个 GROUP BY rollup（byModel / byTask）；`total` **从 byModel 求和派生而非单独查**——标题数字与明细行永远不可能不一致。
- SUM 空组的 NULL 在边界强转 0——否则一路 NaN 渲染成 "NaN tokens"。

## 2. 错误处理：HTTP 200 不等于成功

核心论点：失败通道的差异是**正确性**问题——它决定"这次调用成功了吗"这个判断本身，而默认答案（HTTP 200 = 成功）在兼容层上是错的。必须处理的**四种"看起来成功"的失败**：

1. **SSE 体内 `data: {"error":...}`**（三族适配器都要处理）：审核拦截、上游故障、余额耗尽经常这样送达（OpenRouter routinely）。不处理 = 流在此结束、之前的部分文本被当成正常短回复。
2. **`base_resp.status_code`**（OpenAI 系适配器单独处理）：同一件事的第二种拼法（MiniMax：1004 鉴权失败、1008 余额不足、1002 限流），0 为成功。只认 `error` 字段的客户端会**把过期密钥读成一次正常空回复**。
3. **内容拦截在文本已开始后到达**：
   - Gemini：请求级 `promptFeedback.blockReason` 与响应级 `finishReason ∈ {SAFETY, PROHIBITED_CONTENT, BLOCKLIST, RECITATION, SPII, IMAGE_SAFETY}`（后者可能在半截文本后到）；
   - Anthropic：`stop_reason: "refusal"`；
   - OpenAI：`finish_reason: "content_filter"`（Azure 及多家网关用它而非错误状态码，且几乎不带文本）。
   三者都必须 **throw** 而不是当正常结束——已交付上层的文本需要作废。
4. **请求缺陷伪装成正常短答**：Gemini 的 `GEMINI_REQUEST_FAULTS` 集合——`MISSING_THOUGHT_SIGNATURE`（我方丢了签名，不是用户的错，报错措辞刻意区分，否则用户会去自己的内容里找根本不存在的敏感词）、`UNEXPECTED_TOOL_CALL`、`TOO_MANY_TOOL_CALLS`、`MALFORMED_RESPONSE`。这组说明 finishReason 检查**不能只是 in blocked-set**：HTTP 200 + 不认识的 finishReason，不处理就读成正常短回复。

推论规则：**健壮解析器要把"200 且没有任何内容"当可疑而非成功。**

### 错误消息的两条纪律

- **一律带上实际请求的 URL**：第三方端点最常见的故障是 base 解析到了意料之外的地方，裸的 "404: \<html\>" 让用户无从对照自己粘贴的地址。
- **永不带 key**（同一原则贯穿 apiLog、`?key=` 不实现，见第 2 篇）。

### safety-block 粘性标记

参考实现：`src/lib/ai/modelHealth.ts` 的 `isSafetyBlockMessage`。安全拦截类错误由正则识别（匹配三族的措辞），把该模型标记为 blocked——**跨会话粘性，直到该模型完成一次成功运行才清除**。模型选择器用它提示"这个模型刚拒绝过这类内容，换一个"。

## 3. 重试 / abort / 超时

- **主聊天路径不重试**：一次 streamCompletion 一次机会，错误直接上抛给任务层决定。（用户在看着流，静默重试 = 内容闪回重来。）
- **探测路径重试**：`RETRY_ATTEMPTS = 3`、线性退避 1.2s×n、**只对 `isTransient`（429/5xx）重试**。关键理由：**被限流的请求绝不能被记录成上下文上限的证据。**
- **abort**：`AbortSignal` 一路穿透到 fetch。探测用 `requestSignal` 合并外部 signal 与每请求超时 timer，并把 controller 交出——error probe 在 `res.ok` 时**读到响应头就主动 abort**，不为一次探测付整段生成的钱。
- **超时**：探测每请求 180s（本地后端吃大上下文会 paging 数分钟，探测不能继承聊天级耐心）；**主聊天路径不设自有超时**（长生成合法），交给 signal。
- **ContextSizeError**：发送前估算拦截（第 1 篇 §6），错误对象携带 estimated / contextSize 两个数字供 UI 展示。

## 4. API 日志：为兼容层调试而生

参考实现：`src/lib/ai/apiLog.ts`。**强烈建议第一批实现**——后续所有兼容层坑都靠它定位。

设计规则：

- 开关在设置里；关着时返回 **noop logger**（调用点无条件调用，无 if）。
- JSONL 按天一文件。
- **永不写 apiKey。**
- base64 图片替换成 `<image data url, N chars omitted>` 占位——结构化递归裁剪任何 >2048 字符的字符串，**协议无关**（适配器 body 形状变了照样工作）。
- **写入串行化**——agent 循环并发调用不能交错行。
- 三类条目：
  - `request` —— 调用方意图（消息形状）；
  - `request-body` —— **适配器实际发出的每个 HTTP body，带 leg 序号**。续跑腿的 body 除此之外无处可看；参考实现的经验是"resume 路径上每个已发现的 bug 都是靠读这些 body 找到的"；
  - `response` / `error` —— 含 stopReason / truncated。"回答就这么停了"是这份日志要解释的头号问题：只有 stop reason 能区分 max_tokens 截断 / tool_use 该继续 / end_turn 模型自认写完。

验证方法论：所有"文档说支持但未实测"的能力（thinking 各方言等），验证方式就是**打开 API 日志直接读 body**——这个日志是兼容层适配的第一调试工具。

## 5. providerProbe：连接测试与模型列表（配置时点）

参考实现：`src/lib/ai/providerProbe.ts`。

- **先打 `/models`**：存在时一次回答两个问题（可达 + 已鉴权）且零成本。三族响应形状：OpenAI `{data:[{id}]}`、Gemini `{models:[{name:"models/x", displayName}]}`、Anthropic `{data:[{id, display_name}]}`。
- **compat 且 `/models` 404/405/501**（`ENDPOINT_ABSENT` 集合——"服务器不 serve 这个路径"，区别于 401/429/500 "served 了但拒绝"）→ 不报失败，降级到 **completion probe**：POST 一个最小 body，模型名用**不可能存在的** `__connection_probe__`——连接测试发生在用户选模型之前，真名会计费一次真实生成。
- completion probe **读的是被拒绝的形状，不是结果**：
  - 401/403 → 鉴权失败；
  - 非 2xx 但 body 是**该协议自己的 JSON error 结构** → **判连通成功**（只有真在说这套协议的服务才这样回话）；
  - body 是 HTML/空/非 JSON → 报错——这正是要抓的"base URL 指向了不是 API 的东西"（nginx 404、登录页、CDN）；它与"没有 /models"同样是 404，唯一区别是回话的形状；
  - 2xx → 连通（端点无视了 model 字段，少见但可达且收了 key）。
- **没有 `/models` 的中继是正常配置不是坏的**（模型 id 可手填）。报错文案必须说清这一点而不是甩状态码——否则用户会读成"我的 key 错了"。

## 6. endpointProbe：模型真实上限的实测

参考实现：`src/lib/ai/endpointProbe.ts`（HTTP 管线）+ `probeAnalysis.ts`（纯判断）。回答的问题是"这个端点**实际**接受什么"，而不是文档/网关/用户猜的。四步递进、花钱递增：

```
Step 0  discover()   免费元数据：/models 扩展字段（OpenRouter context_length、
                     LM Studio max_context_length…）；Gemini/Anthropic 的
                     per-model 端点直接给 inputTokenLimit/outputTokenLimit、
                     max_input_tokens/max_tokens（这两族后续步骤基本可省）；
                     本地栈加测 ollama /api/show 与 llama.cpp /props    0 token
Step 1  errorProbe() 两个词的 prompt + max_tokens=10,000,000（荒谬值）：
                     执行上限的服务器会把真实上限写进 4xx body——花几个
                     token 换一个精确数字；接受了的（stream:true）读到
                     响应头就挂断，不付生成费                        ~0 token
Step 2  calibrate()  两个已知字符数的 padding → 该端点真实 chars-per-token
                     （模板开销在两点间抵消）
        truncation() 发已知大小 prompt（快测 8k，正中 ollama 默认 num_ctx
                     2048/4096 的雷区）对比服务器报的 prompt_tokens：
                     short fall = 静默截断实锤；一致 ≠ 无截断——
                     不对称性一路带到报告，UI 对两种结果措辞不同
Step 3  deep(opt-in) 从声明值开始的二分搜索找真实接受上限（声明值直接过 =
                     一次请求收工，永不从零盲扫；不能定论的错误直接停，
                     不当证据）；真实生成测输出长度——任务必须是模型
                     不可能自然写完的（"从 1 数数"），否则 stop 分不清
                     是上限还是写完了；capped 才是上限证据 high，
                     跑满只是下界 low
```

配套设计原则：

- **判断逻辑独立可单测**：所有判断（这个错误是上限还是限流？这个差距是截断还是分词噪音？）抽在无网络依赖的 `probeAnalysis.ts`，probe 本体只是管线。
- 每个 finding 带 source / detail / confidence：描述"实际加载运行的值"的键（`num_ctx` / `max_model_len`）置 high，理论能力键置 medium——ollama 的 `model_info` 与 `parameters` 常差 30 倍，**小的那个才算数，这个差值本身就是静默截断 bug**。
- **探测成本先告知**：探测前 `planProbeCost` 给用户看预估花费（"看不见成本的同意不是同意"），结束给实际花费回执。
- `max_tokens` 被拒时自动换名 `max_completion_tokens` 重试一次（记 param-switched 警告）。
- **`probedAt` 过期语义**：测量会过期——中继明天可能把同一模型名路由到另一个上游。UI 呈现为"某日实测"而非永久事实。
- 存储上给"作者填的值"与"实测值"**各留位置**——直接覆盖同名字段后，"这个 128k 是填的还是测的"答不上来，且用户填的值不可恢复。

## 7. 探测的边界：能声明的声明、能从失败恢复的不预探、只有数值才实测

**endpointProbe 探测的是上下文/输出上限，不是"这个端点说哪种方言"。** 分工规则：

- **方言（协议族）**：作者选择 ApiStandard 声明；
- **thinking 代次（dialect）**：作者声明（理由见第 3 篇：中继上模型 id 是自由文本，代次不可探测）;
- **tools / JSON mode 能力**：不主动探测，靠**运行时降级**（structured 的错误正则回退、providerProbe 的错误形状判定）；
- **上下文窗口 / 输出上限**：作者自己也不知道的**数值**，才花钱实测。

这是刻意取舍，配合三条贯穿性原则收尾：

1. **最小公倍数发送、最大宽容接收。** 官方端点可乐观假设可选部分存在，兼容端点不行；主动发出的每个字段都是某个中继可以 400 的字段（`max_uses` 是唯一有记录的刻意例外，见第 5 篇）。
2. **凡跨轮回传的，原物整存**（thinking blocks、thoughtSignature、encrypted_content、reasoning 字段名）；"理解后重建"恰好丢掉的就是完整性校验依赖的那部分。
3. **先问失败会不会响。** 会响的（400）靠错误驱动降级即可；不响的（静默降级/静默截断/静默忽略）必须主动验证（API 日志对照、探测、"结果之后模型说话了吗"式的间接判据），并且**只有这类才值得预先花设计预算**。

---

## 本篇检查清单

- [ ] usage 内部口径三字段（input / output 含思考 / cached 为 input 子集）+ 计费公式有文档。
- [ ] Anthropic input = 三桶求和；`message_delta` 不清零已立的 input。
- [ ] Gemini output = `candidatesTokenCount + thoughtsTokenCount`。
- [ ] `persistUsage` best-effort 永不抛；total 从明细 rollup 派生；NULL→0 在边界处理。
- [ ] 三族适配器都处理 SSE 体内 `data:{"error":...}`；OpenAI 系另处理 `base_resp.status_code`。
- [ ] content_filter / SAFETY / refusal 都 throw 作废已流出文本，不当正常结束。
- [ ] Gemini 的 finishReason 检查覆盖 `GEMINI_REQUEST_FAULTS`，且我方缺陷（丢签名）与内容拦截的报错措辞区分。
- [ ] 错误消息带实际请求 URL，永不带 key；apiLog 永不写 key。
- [ ] safety-block 有跨会话粘性标记，成功一次即清除。
- [ ] 主路径不重试不设超时；探测路径仅对 429/5xx 重试、每请求超时、限流结果不入证据。
- [ ] apiLog：noop 开关、按天 JSONL、图片/长串裁剪、写入串行化、request-body 带 leg 序号、response 含 stopReason/truncated。
- [ ] providerProbe：/models 优先；compat 对 `ENDPOINT_ABSENT` 降级 completion probe；probe 用不可能模型名；按被拒形状判定；"没有 /models"的文案不吓人。
- [ ] endpointProbe 四步递进；判断逻辑在独立纯函数模块可单测；探测前告知成本；finding 带 confidence；probedAt 呈现为"某日实测"。
- [ ] 作者填的值与实测值分开存储。
- [ ] 新能力接入时先过一遍"声明 / 运行时降级 / 花钱实测"三分法，只有数值才实测。
