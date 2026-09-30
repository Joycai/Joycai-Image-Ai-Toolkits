# 06 · 错误处理、usage、探测与可观测性

> 本篇解决的问题：在兼容层世界里回答三个问题——「这次调用成功了吗」（默认答案 HTTP 200=成功在兼容层上是**错**的）、「这次花了多少钱」（两个口径陷阱会让你少报一个数量级）、「这个端点实际能接受什么」（文档/网关/作者说的都不算数）。
> 不读会踩的坑：过期密钥被读成一次正常空回复；长 prompt + 缓存命中时 input 少报一个数量级；Gemini 思考 token 全部漏计；被限流的探测请求被记录成上下文上限的证据；API key 泄进日志与错误消息。

出处：simple-ai-writer `src/lib/ai/usage.ts`、`modelHealth.ts`、`apiLog.ts`、`providerProbe.ts`、`endpointProbe.ts`、`probeAnalysis.ts`，以及三个适配器的错误通道处理。

目录：
- §1 usage 归一化：两个口径陷阱（Gemini `toolUsePromptTokenCount` 在 prompt 之外 · 第四种口径：上游直接报钱，含上游报价进账的信任边界与合并规则 · 中转站估算的 usage · ② 账号池的 `attribution`：注入量的读数 · 官方回包里的新字段：思考 / 服务端工具 / 缓存写入 / 检索费 · 持久化与 rollup）
- §2 错误处理：HTTP 200 不等于成功（含同一非法参数四个上游四种报法、中转站自己下载 URL 图片、中转站改写错误信封）
- §3 重试 / abort / 超时
- §4 API 日志（§4.1 回显比对，含 GPT 上游的改写与回显抓不到的输出上限 · §4.2 包装器装钩子必须串联）
- §5 providerProbe：连接测试与模型列表（含目录的 `supported_endpoint_types` 不等于这把 key 能用）
- §6 endpointProbe：模型真实上限的实测
- §7 探测的边界
- §8 付费实测（live probe）纪律（含流式 / 非流式各测一遍、跨模型逐字相同、同台至少测两个渠道、非法参数分反代 / 正向、一档之内注入量要多测几次、经网关先按面判后端、「收下」与「生效」怎样分开测）
- §9 按 400 学降级：一个执行器、学到的上限持久化（比对发出了什么、终止性论证、cue 的位置、7 天过期与作废、主动 / 被动两种值）

---

## 1. usage 归一化：两个口径陷阱

内部统一口径：

- `inputTokens` —— 总输入；
- `outputTokens` —— 总输出，**含思考**；
- `cachedTokens` —— **inputTokens 的子集**，按缓存价计费的部分。

计费公式：`(input − cached) × 全价 + cached × 缓存价`。

三处**必须**归一化，否则数字直接错：

1. **Anthropic 三桶不重叠**（出处：`anthropic.ts` 的 `readUsage`）：`input_tokens` 只是未命中缓存的余量，`cache_read_input_tokens`、`cache_creation_input_tokens` 单列。总输入 = 三者之和——直接读 `input_tokens` 会在长 prompt + 缓存命中时**少报一个数量级**。cache write 计价高于基础价而费率表通常没这档，归入全价桶——宁可高估（用户拿这个数决定跑不跑，高估是安全方向）。另外 `message_delta` 只报 output，不能让它缺失的 input 字段清零 `message_start` 已立的数（`input || prev.inputTokens`）。
2. **Gemini 思考不在 `candidatesTokenCount` 里**：`outputTokens = candidatesTokenCount + thoughtsTokenCount`——只读前者会把"思考 5k、回答 500"记成 500，少算的正是最贵的部分。（①④ 的输出已含思考，details 只是明细。）
   **输入侧同形**：内置工具（读网页、代码执行）回填给模型的 token 记在 `usageMetadata.toolUsePromptTokenCount`，**在 `promptTokenCount` 之外**
   （【实测 2026-09-26，3.8 Flash 经 OrcaRouter（Vertex）】prompt 20 + candidates 65 + toolUse 77 = total 162）——`inputTokens = promptTokenCount + toolUsePromptTokenCount`，
   不加就少记输入（05 §5「③ Gemini 的内置工具」）。
3. **DeepSeek 的缓存命中不在标准位置**：它报顶层 `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`，没有
   `prompt_tokens_details.cached_tokens`；`prompt_tokens` 已含命中。只读标准拼写 = 每次命中都按全价记【文档；Joycai 2026-09-14 修复】。
   对策：宿主没发标准字段时，把命中数以标准拼写补进去，原字段保留。

**第四种口径：上游直接报钱。** 有的面不报 token 也不报张数，只报这次的实扣金额（xAI images `usage.cost_in_usd_ticks`，
1 tick = $10⁻¹⁰，含输入图，13 §7；xAI 视频面同样报，但只在轮询的 done 回包里，提交回包没有，14 §2【实测 2026-09-22】）。归一化成一个中性键（美元 double），**换算只写一处**；持久化时它是一列
**可空**的 `reported_cost`，有值就是这行的成本、其余口径归零。与「按次 / 按张与 token 相加」不同：报价含全部，**替换**不叠加。
「没报」与「报了 0」必须分得开——NULL 不是 0。
网关也常这样报钱，但**字段按面不同、有的要请求头才报、同一端点也可能时有时无**：OrcaRouter ④ `message_delta.usage.cost_usd`、③ 末块 `usageMetadata.costUsd`
（这两面都要带 `X-OrcaRouter-Include-Cost: true`，不带就没有）、① 末块 `usage.cost`、② 默认线路 `usage.cost`、② 原样线路一个都没有【实测 2026-09-26，流式，第 1 篇 §9.5】。
按面各读各的键，读不到就按表算，不要因为「这台网关报钱」就省掉表算那条路。

**上游报价进账的规则**（【实现】simple-ai-writer `reportedCost.ts` + `platforms.ts` `reportsCost`，2026-09-26 起；设计层见 `llm-billing-model` skill）。
报价一旦记上用量行就压过整张价格表，所以**收不收它是信任问题，不是解析问题**：

- **信任声明在平台上，不在字段上。** 只收测过「报的数 = 实扣」的平台（拿回包里的数与平台账单接口逐笔对过，例：OrcaRouter 的 `GET /v1/generation`）。
  不选「任何回包带 `usage.cost` 都收」：没测过的中转报的数是不是它实际扣的，没人知道；OpenRouter 形态的翻译层在 ① 上本来就回 `usage.cost`。
- **请求地址也得指向那个平台。** 平台标签是作者贴的，可以贴在任何主机上（选了某平台再改地址，标签不跟着变）。标签与「从地址推断出的平台」
  一致才发请求头、才收数——贴错标签的中转既收不到头，回的数也不收。
- **换算只写一处**：各族字段（④ `cost_usd` · ③ `costUsd` · ① `cost_usd ?? cost` · ② `cost`）翻成一个中性值只在一个模块；只收有限且 ≥ 0 的数，
  其余一律算「没报」。请求头也从那里出，四个适配器不各写一份。④ 从 `message_delta` 读，不指望 `message_start` 的快照。
- **「没报」≠ 0**：没报是空，`0` 是上游说这次免费，会把整行记成 0。
- **几次请求记一行时：全报才加，缺一次整行为空**（agent 多轮、④ `pause_turn` 续接、分段摘要都是几次请求记一行）。半截的和会把没报的那几次
  当免费；整行为空则回落到价格表按**全部** token 算。代价：没配价格的模型这一行记 0，与没报价的行一样。
- **显示的钱与账上的钱走同一个算式**：草稿卡片、会话上显示的花费也接报价、仍经唯一的 `costOf()`，不会是两个数。
- **漏传要在编译时报错**：少传报价不会出错，那一行只是按表算——没配价格的模型静默记 0。写入口的参数类型里把报价做成**必填键**
  （`reportedCost: number | null`，没有就显式写 `null`），显示算式的这个参数也不给默认值：每个调用点都得表态。参考实现先写过扫描源码的护栏
  （找调用括号里有 token 字段却没带报价的），review 发现它看不见**先构造好的参数对象**、展开写法和导入别名，变异一处照样全绿——换成类型后
  三种写法都编译不过，护栏删掉（坑 189）。
- 参考实现里不经四个对话适配器的路径（本地翻译模型、出图、转写）显式写 `null` 并注明理由，照旧只按价格表；出图 / 视频面自己报的钱（xAI ticks）是另一套换算，见 13 §7。

**中转站估算的 usage：总数大致可信，缓存分段是拼的**（New API 中转站 Kiro 渠道的 Claude，④ 面，【实测 2026-09-23】，landscape.md §7 第十五个样本；背景见第 1 篇 §9.2）。
后端不是 Anthropic API，usage 由中转站估算：

- 输入随内容增长（7.7k 前缀报 7,762），三桶相加的总输入可用。
- 缓存两项是拼出来的：**不带 `cache_control` 的请求也固定报几十 token 的 `cache_read_input_tokens`**；流式的 `message_delta` 还报
  `cache_creation:{ephemeral_5m_input_tokens: 265}`。
- **`cache_control` 只写不读**：同一 7.4k 前缀连发两次，两次都报 `cache_creation_input_tokens: 7360`，`cache_read` 永远只有几十。
  若中转站按写缓存价计费，**打断点比不打更贵**。
- 对策：兼容 ④ 线路默认不发 `cache_control`（参考实现的 `cachesPrompt` 只对官方标准开，在这里恰好是对的）；这类端点上按
  `cache_read` / `cache_creation` 分段算出的缓存成本标为估算、不可信，别拿它判断「缓存有没有生效」。验证缓存只能连发同一前缀，
  看第二次 `cache_read` 是否接近前缀长度。
- 同一端点 `max_tokens` 被无视、`stop_reason` 永远不是 `max_tokens`：截断归因不能假设「没报截断 = 没超长」（坑 65 同形）。

**同一台上别的渠道**（【实测 2026-09-23】，landscape.md §7 第十六个样本）：CC 与 AWSb 的缓存是真的（第二次 `cache_read` = 前缀）；
anti **没有任何缓存字段**、两次都按全价输入，且每个请求多约 30 token（「Say OK.」不带 system 报 39，别的渠道 9–10）——渠道自己注入了提示。
usage 与缓存的可信度也按渠道记，不按中转站记。

**② 账号池上游的 `usage.attribution`：注入量的直接读数**（New API 中转站的 ChatGPT 账号档，【实测 2026-09-24】，landscape.md §7 第十七个样本；背景见第 1 篇 §9.2「同一个 GPT，两类上游」）：

```jsonc
"usage": {
  "input_tokens": 4389,
  "input_tokens_details": { "cached_tokens": 0, "cache_write_tokens": 0 },
  "attribution": {
    "items": { "<item id>": {…} },                          // 按输出条目计
    "request_fields": { "instructions": { "input_tokens": 4380 } }  // 作者没发 instructions，却记了 4,380
  }
}
```

- `attribution.request_fields.instructions.input_tokens` 与作者实发的 `instructions` 长度一比，就知道中转站 / 上游往里塞了多少——比「Say OK.」对照更直接，每个真实请求都能顺手核。
- 网关类上游没有这个字段；它追加的护栏只能从终止响应回显的 `instructions` 看出（+1.2K 输入）。
- 同一档注入量不固定（0 / 11 / 296 / 4.4K / 17K 都见过），所以「输入 token 比预估多」要逐请求看，不能测一次就下结论；计费按报上来的 `input_tokens`，注入的部分作者照付。
- `input_tokens_details.cache_write_tokens` 是另一个新键；内部口径不变（cached 仍是 input 子集），读不到就当 0。

**官方回包里的新字段**（【实测 2026-09-26】，经 OrcaRouter，均在判定为上游原样的面上看到，第 1 篇 §9.5）：

| 族 | 字段 | 怎么读 |
| --- | --- | --- |
| ④ | `usage.output_tokens_details.thinking_tokens` | 思考量明细，是 `output_tokens` 的**子集**（Sonnet 5：22 = 21 思考 + 1 正文）——不另加 |
| ④ | `usage.server_tool_use.{web_search_requests, web_fetch_requests}` | 服务端工具的按次读数，按次价另计 |
| ④ | 没发 `cache_control` 也有 `cache_creation_input_tokens` | `web_search` 结果被服务端自动写缓存（一次 2,834）；`cache_creation` 不能当「我方打了断点」的判据，三桶照样相加。手打断点实测：9,848 token 的 system 第一次写 $0.0247（1.25× 输入价），第二次读 $0.0020 |
| ② | `usage.input_tokens_details.cache_write_tokens` | OpenAI 原样线路上也有（一次 `web_search` 4,388）——不是中转站私有键 |
| ③ | `usageMetadata.trafficType`（`"ON_DEMAND"`） | Vertex 专有，可当后端判据；流式只有最后一块带计数 |
| ③ | `usageMetadata.toolUsePromptTokenCount` | 内置工具结果回灌给模型的 token（`codeExecution`、`urlContext` 等，第 5 篇 §5）；**在 `promptTokenCount` 之外**，计进输入（上面第 2 条） |

- **检索费压倒 token 费**：③ `googleSearch` **按查询条数**计费，约 **$0.014 一条**，一次回答搜几条由模型定（实测一题 6 条、$0.084），协议里没有上限字段可发；
  token 部分只是零头（④ 一次带 `web_search` 的请求合计 $0.051）。只按 token 估成本会大幅低估——服务端工具的次数要单独读、单独计（有上游报价时直接用报价）。
  **改口留痕**：此前写「一次 $0.028」，是按请求记的；同日再补测按条数核对后改为每条约 $0.014【实测 2026-09-26】。

### 持久化与 rollup

出处：`src/lib/ai/usage.ts`。

- `persistUsage` 每次调用一行（model_id / task / prompt / cached / completion / cost / created_at），**best-effort 永不抛**——记账不能炸调用方。
- 读侧两个 GROUP BY rollup（byModel / byTask）；`total` **从 byModel 求和派生而非单独查**——标题数字与明细行永远不可能不一致。
- SUM 空组的 NULL 在边界强转 0——否则一路 NaN 渲染成 "NaN tokens"。

（自 11 篇坑 8 移入）① 族兼容层最先没实现的就是 `stream_options.include_usage`：现象是 usage 全 0、不报错。照发，但把 0 当「没报」处理（NULL 不是 0，见上）；探测结果标 `no-usage-reported`。

## 2. 错误处理：HTTP 200 不等于成功

核心论点：失败通道的差异是**正确性**问题——它决定"这次调用成功了吗"这个判断本身，而默认答案（HTTP 200 = 成功）在兼容层上是错的。必须处理的**四种"看起来成功"的失败**：

1. **SSE 体内 `data: {"error":...}`**（各族适配器都要处理）：审核拦截、上游故障、余额耗尽经常这样送达（OpenRouter routinely）。不处理 = 流在此结束、之前的部分文本被当成正常短回复。
2. **`base_resp.status_code`**（OpenAI 系适配器单独处理）：同一件事的第二种拼法（MiniMax：1004 鉴权失败、1008 余额不足、1002 限流），0 为成功。只认 `error` 字段的客户端会**把过期密钥读成一次正常空回复**。
3. **内容拦截在文本已开始后到达**：
   - Gemini：请求级 `promptFeedback.blockReason` 与响应级 `finishReason ∈ {SAFETY, PROHIBITED_CONTENT, BLOCKLIST, RECITATION, SPII, IMAGE_SAFETY}`（后者可能在半截文本后到）；
   - Anthropic：`stop_reason: "refusal"`；
   - OpenAI：`finish_reason: "content_filter"`（Azure 及多家网关用它而非错误状态码，且几乎不带文本）；
   - 智谱 BigModel：`finish_reason: "sensitive"`（同义，不用 `content_filter` 这个值）。
   三者都必须 **throw** 而不是当正常结束——已交付上层的文本需要作废。
   同一家的另两个私有值【文档 2026-09，名字无歧义可对全体 ① 族生效】：`network_error`（推理中途异常——文档明写
   「流式中途失败不回错误码，只在 `finish_reason` 里说」，必须 throw）、`model_context_window_exceeded`（按截断处理，同 `length`）。
4. **请求缺陷伪装成正常短答**：Gemini 的 `GEMINI_REQUEST_FAULTS` 集合——`MISSING_THOUGHT_SIGNATURE`（我方丢了签名，不是用户的错，报错措辞刻意区分，否则用户会去自己的内容里找根本不存在的敏感词）、`UNEXPECTED_TOOL_CALL`、`TOO_MANY_TOOL_CALLS`、`MALFORMED_RESPONSE`。这组说明 finishReason 检查**不能只是 in blocked-set**：HTTP 200 + 不认识的 finishReason，不处理就读成正常短回复。

推论规则：**健壮解析器要把"200 且没有任何内容"当可疑而非成功。**

**错误信封里的业务码是字符串，而且可能不指向真因**（智谱，【实测 2026-09-19】）：`{"error":{"code":"1210","message":"…"}}`，
HTTP 状态另给。多数文案具体（`temperature参数非法：限制数值范围[0,1]`、`max_tokens参数非法：限制数值范围[1,98304]`），
但有两类不可信：同一句「该模型始终思考，不支持关闭思考」覆盖 5.3 代**所有**非法思考参数（连关思考时的图片请求也报它）；
「API 调用参数有误，请检查文档」不说是哪个参数（被拒的强制 `tool_choice`、glm-5 的非法 effort 都是它）。
按文案关键词做错误驱动降级前，先看这家的文案是否点名参数。错 key 是 401 `{"code":"401","message":"令牌已过期或验证不正确"}`；
**未知顶层字段一律放过**。同一句 1210 在 ④ `/api/anthropic` 上原样出现，外面多包一层 `[1210][…][<request id>]`，`thinking.type:"bogus"` 回的也是它【实测 2026-09-28】（03 §3.5）。

**翻译层把上游的拒绝原样传回，点名的是别家协议的字段**（阿里百炼 ④ `/apps/anthropic`，【实测 2026-09-28】，第六个样本补测）：
④ 面的 `thinking:{type:"disabled"}` 被翻成百炼自家 ① 方言 `enable_thinking` 再下发，MiniMax-M2.5 / glm-5.3 拒绝时连 ① 的字段名一起回来：
`<400> InternalError.Algo.InvalidParameter: The value of the enable_thinking parameter is restricted to True.`——与 ① 面那句是**同一个校验**。
一个 ④ 客户端收到的拒绝里点名的是 `enable_thinking`，按本族的 `thinking` 找原因找不到；「按 400 学降级」按本族字段名写的正则在这里失配（§9）。
百炼 ④ 自己的校验则不点名字段：`thinking.type:"bogus"` → 400 `Request body format invalid`；未知模型 → 400 ``The model `qwen-nonexistent` does not exist or you do not have access to it.``；
`temperature:2.5` → 400 `Temperature should be in [0.0, 2.0)`；`budget_tokens:1024` 配 `max_tokens:512` → 400 `max_completion_tokens [512] must be greater than thinking_budget [1024]`（03 §3.5）。

**未知模型名不报错、静默改映射**——「模型名错了」只有拿响应里的 `model` 核对才看得出：
- MiniMax ④ `api.minimaxi.com/anthropic`【实测 2026-09-28】：`MiniMax-M3.1-Flash-Preview`（文档列着、该 key 的 `/v1/models` 里没有）200，响应的 `model` 是 `MiniMax-M3`。同一面上 `thinking.type:"bogus"` 200 且开始想、`top_k:99999` / `temperature:2.5` 都 200；唯一撞出来的 400 是 `top_p:1.5` → `{"type":"invalid_request_error","message":"invalid params, param 'top_p' should be in (0,1] (2013)"}`。
- DeepSeek ④ `api.deepseek.com/anthropic`【文档 2026-09】：`claude-opus*` 映射到 deepseek-v4-pro，`claude-haiku*` / `claude-sonnet*` 映射到 deepseek-flash，**不认识的模型名也映射到 deepseek-flash**，不报错。同一面上非法思考值会响：`thinking.type:"bogus"` 422 并点名枚举（03 §3.5）。
- 对照：百炼 ④ 未知模型 400（上文）。对策：回显比对（§4.1）把响应 `model` 与请求 `model` 不同记成一条告警；作者填错 id 时 MiniMax / DeepSeek 上不会有任何报错（坑 221）。

**同一个非法参数，四个上游四种报法**（New API 中转站，同一个 `gpt-5.6-sol`，【实测 2026-09-24】，第十七个样本）：

| 请求 | `[Pro]`（账号池） | `[Plus]`（账号池） | `[特价Pro]`（账号池） | `[Azure]`（网关） |
| --- | --- | --- | --- | --- |
| ② `reasoning.effort:"bogus"` | 400 官方原文 `Invalid value: 'bogus'. Supported values are: 'none', 'minimal', …` | 502 `Upstream request failed` | HTTP 200，流里 `response.failed`（`upstream_error`） | 500 `Upstream gateway error` |
| ① `reasoning_effort:"bogus"` | 400 官方原文 | 502 | 流里一个「Upstream service temporarily unavailable」错误 | 500 |
| ② `code_interpreter` / `file_search` | 400 `Unsupported tool type` | 502 | 流式 `response.failed` | 500 |
| ② `temperature:0.5` | 200，回显 `1.0` | 200，回显 `1.0` | 200，回显 `1.0` | **500**（`temperature:1` 则 200） |
| ② `store:true` | 200 | 200 | 200 | 500 |
| ① 具名 `tool_choice` | 200 | 200 | 200 | **500**（9/9） |

- 「**上游的校验与官方同文吗**」是最便宜的分类器：只有同文 400 能被「按 400 学降级」的机制读懂；502 / 500 / 流内 `response.failed` 看起来就是上游故障，
  学降级的正则不该匹配它们，重试也没用——同一个请求形状永远失败。
- 网关的 500 会响，但它让**整条请求**失败：一个对中转站默认发 `temperature` 的 ② 实现，在这个上游上每个请求都挂。所以参考实现给这个上游的 ② `temperature` 判「不发」（第 1 篇 §9.2）。
- 流式时的 `response.failed` 是 HTTP 200——必须按本节第 1 条处理成失败，不能读成一次空回复。

**中转站为了算 token，自己先下载 URL 图片**（同一样本，【实测 2026-09-24】）：`input_image` / `image_url` 给一个 http 地址，图放在拒爬虫的主机上（回 403 的维基共享资源）时：

| 上游 | 结果 |
| --- | --- |
| 网关 | **500 `count_token_failed`**——中转站计 token 前自己下载，下载失败整条失败，请求根本没到上游 |
| `[Pro]` | 400 `Error while downloading file` |
| `[特价Pro]` | 流里一个 `error` 事件后接**空答**（200） |

同一张图放在 raw.githubusercontent 上四档都 3/3 读到。所以「URL 图片支持」还依赖**图在哪**：公网 URL 会被中转站与上游各下载一次，
下载方的 User-Agent 被拒就整条失败或空答。对策：图片一律内联 base64 / data URL（与第 2 篇 §1 表后「整台可移植的只有内联 base64」同一结论），
把「空答 + 流内 error」当失败（本节第 1 条）。

**中转站改写错误信封**（OrcaRouter，【实测 2026-09-26】，第 1 篇 §9.5）：③④ 的回包是上游原样，**错误却不是**——全部改写成 OpenAI 形：

| 面 | 改写后的样子 |
| --- | --- |
| ③ | `{"error":{"message", "type":"invalid_argument", "param":"", "code":400}}`——原文保留，但**路径与 URL 被打成 `***`** |
| ④ | `{"error":{"type":"<nil>", "message":"***.***.content.0: … (request id: …)"}, "type":"error"}`——**`type` 是 Go 的空值 `<nil>`**（New API 系的指纹），字段路径被遮 |
| 上游 5xx | `api_error` + 固定文案 `The upstream provider is temporarily unavailable` |

它的文档说上游错误的 `type` 是 `claude_error` / `gemini_error`，实测一次都没出现。
- **分类不靠 `error.type`、`param`、字段路径**：只靠 HTTP 状态 + 报文里仍保留的关键字。按 ④ 官方 `error.type`（`invalid_request_error` 等）分支的代码在这里全部落空。
- 依赖报文里字段路径的降级正则（「是哪个参数被拒」）遇到 `***` 会失配——正则匹配参数名本身，不匹配路径。
- 「回包原样」的面，错误通道也要单独验：两条通道可以不是同一个后端在说话。

### 错误消息的两条纪律

- **一律带上实际请求的 URL**：第三方端点最常见的故障是 base 解析到了意料之外的地方，裸的 "404: \<html\>" 让用户无从对照自己粘贴的地址。
- **永不带 key**（同一原则贯穿 apiLog、`?key=` 不实现，见第 2 篇）。

### safety-block 粘性标记

出处：`src/lib/ai/modelHealth.ts` 的 `isSafetyBlockMessage`。安全拦截类错误由正则识别（匹配三族的措辞），把该模型标记为 blocked——**跨会话粘性，直到该模型完成一次成功运行才清除**。模型选择器用它提示"这个模型刚拒绝过这类内容，换一个"。

## 3. 重试 / abort / 超时

- **主聊天路径不重试**：一次 streamCompletion 一次机会，错误直接上抛给任务层决定。（用户在看着流，静默重试 = 内容闪回重来。）
- **探测路径重试**：`RETRY_ATTEMPTS = 3`、线性退避 1.2s×n、**只对 `isTransient`（429/5xx）重试**。关键理由：**被限流的请求绝不能被记录成上下文上限的证据。**
- **取消**：调用方的取消信号一路穿透到 HTTP 请求。探测把外部取消信号与每请求超时合成一个信号，并保留主动取消的句柄——错误探测在响应 2xx 时**读到响应头就主动断开**，不为一次探测付整段生成的钱。
- **超时**：探测每请求 180s（本地后端吃大上下文会 paging 数分钟，探测不能继承聊天级耐心）；**主聊天路径不设自有超时**（长生成合法），交给 signal。
- **ContextSizeError**：发送前估算拦截（第 1 篇 §6），错误对象携带 estimated / contextSize 两个数字供 UI 展示。

## 4. API 日志：为兼容层调试而生

出处：`src/lib/ai/apiLog.ts`。**强烈建议第一批实现**——后续所有兼容层坑都靠它定位。

设计规则：

- 开关在设置里；关着时返回 **noop logger**（调用点无条件调用，无 if）。
- JSONL 按天一文件。
- **永不写 apiKey。**
- base64 图片替换成 `<image data url, N chars omitted>` 占位——结构化递归裁剪任何 >2048 字符的字符串，**协议无关**（适配器 body 形状变了照样工作）。新增一种大载荷（如 ① 族 `file` 内容块里的整份 PDF）时消息级脱敏要跟上：同样的重量问题在 PDF 尺度上是 100MB 级，一条没脱敏的日志行等于没人打得开的日志文件（结构化递归裁剪是兜底，消息级替换保住 filename 等可读信息）。
- **写入串行化**——agent 循环并发调用不能交错行。
- 三类条目：
  - `request` —— 调用方意图（消息形状）；
  - `request-body` —— **适配器实际发出的每个 HTTP body，带 leg 序号**。续跑腿的 body 除此之外无处可看；参考实现的经验是"resume 路径上每个已发现的 bug 都是靠读这些 body 找到的"；
  - `response` / `error` —— 含 stopReason / truncated。"回答就这么停了"是这份日志要解释的头号问题：只有 stop reason 能区分 max_tokens 截断 / tool_use 该继续 / end_turn 模型自认写完。

验证方法论：所有"文档说支持但未实测"的能力（thinking 各方言等），验证方式就是**打开 API 日志直接读 body**——这个日志是兼容层适配的第一调试工具。

### 4.1 回显比对：端点悄悄换了你的参数

出处：`src/lib/ai/responses.ts` 的 `readTerminalUsage`，`types.ts` 的 `WireRewrite`，决策记录 `docs/api/gpt56-plan.md` P2。

**失败形态**：请求 200、输出正常，但端点跑的不是你发的参数（New API 中转站改写 effort / temperature，实测样本见第 1 篇 §9.2）。作者以为开了（或关了）深思考，其实没有——典型的"不响"类失败。

**可利用的事实**：② Responses 族的终止响应（`response.completed` / `incomplete` 的 `response`）**回显请求字段**。

规则：

1. **比对的是最终 body 里真正发出的值**（extraBody 覆盖之后），与终止响应回显的 `reasoning.effort` / `temperature` 对比；数值用容差比较。
2. **不一致 → 报告，不重试、不改请求、不抛错**：改写可能来自中转站、档位或后端，客户端分不清；输出本身可用。
   产出 `done` chunk 上的 `wireRewrites?: {field, sent, echoed}[]` → 写进 API 日志的 response 条目 + 执行日志该轮一行（「端点把 effort 从 max 改成了 none」），作者看见就能换档。
3. **回显缺失时什么都不说**：实测同一档位背后有多个上游，有的响应根本没有这些字段。只报告"有回显且不一致"，缺字段 ≠ 被改写。
4. ① Chat Completions 没有回显字段，这条机制在那一族上不存在——不要去伪造。

**同一台中转站上 GPT 四个上游的实测**（【实测 2026-09-24】，第十七个样本；上游分类见第 1 篇 §9.2）：
- `effort:"none"` 四个上游都回显 `medium`、照样推理——回显比对抓得到（「端点把 effort 从 none 改成了 medium」）；
- `temperature:0.5` 三个账号档回显 `1.0`——抓得到；网关直接 500，是会响的失败，不需要比对；
- 第十个样本里 sol 的「发 `max` 回显 `none`」这次没出现（四档都原样回显 `max`）——这类改写随时间与上游出现又消失，**比对要常开**，不能测一次就把规则写死。
- **回显比对抓不到的**：`max_output_tokens` 被无视（三个账号档：设 16 照样写完、`status: completed`、没有 `incomplete`；网关执行）——回显里的上限就是你发的数，没被「改写」，只是没执行。
  截断归因不能假设「没报截断 = 没超长」（坑 65）。`text.format` 被丢时回显 `{type:"text"}`，这一项可以比对，参考实现尚未做（第 4 篇 §5.1）。

### 4.2 包装器装钩子必须串联，不能替换

**事故**：统一入口为了把请求体写进 API 日志，把 `_onRequestBody` 设成自己的函数——**覆盖了调用方传入的同名钩子**。
live 实测文件通过这个钩子读自己发出的 body，所有 `bodies[0]` 断言从此读到 `undefined`：一轮 12 条实测里 6 条"失败"不是端点的错，是这个。

规则：横切层给选项对象装任何回调（日志、计时、看门狗），一律「先调自己的，再调调用方原有的（若有）」；并加一条单测钉住"调用方钩子仍被调用"。
`onChunk` 早就是这么包的，偏偏"调用方一般不传"的内部钩子最容易被写成替换。

## 5. providerProbe：连接测试与模型列表（配置时点）

出处：`src/lib/ai/providerProbe.ts`。

- **先打 `/models`**：存在时一次回答两个问题（可达 + 已鉴权）且零成本。三族响应形状：OpenAI `{data:[{id}]}`、Gemini `{models:[{name:"models/x", displayName}]}`、Anthropic `{data:[{id, display_name}]}`。
- **compat 且 `/models` 404/405/501**（`ENDPOINT_ABSENT` 集合——"服务器不 serve 这个路径"，区别于 401/429/500 "served 了但拒绝"）→ 不报失败，降级到 **completion probe**：POST 一个最小 body，模型名用**不可能存在的** `__connection_probe__`——连接测试发生在用户选模型之前，真名会计费一次真实生成。
- completion probe **读的是被拒绝的形状，不是结果**：
  - 401/403 → 鉴权失败；
  - 非 2xx 但 body 是**该协议自己的 JSON error 结构** → **判连通成功**（只有真在说这套协议的服务才这样回话）；
  - body 是 HTML/空/非 JSON → 报错——这正是要抓的"base URL 指向了不是 API 的东西"（nginx 404、登录页、CDN）；它与"没有 /models"同样是 404，唯一区别是回话的形状；
  - 2xx → 连通（端点无视了 model 字段，少见但可达且收了 key）。
- **402 是「钱包空了」，不是「已连通」**：欠费的中转对**任何**真实请求都回 402，而且是完整的、协议形状的 JSON 错误，发生在解析模型名之前
  【实测 2026-09-05，Joycai 连接测试】。按上面的规则它会被读成「在说这套协议 → 连通」，用户于是去排查模型列表。402 在任一步都报不可达，
  并带上提供方自己的文案；它也不是鉴权失败（key 有效，余额为零）（坑 112）。OrcaRouter 同形：`402 {"error":{"code":"insufficient_user_quota",…}}`，先于模型解析【实测 2026-09-03】。
- **`/models` 回 401 也不一定是 key 错**：火山方舟套餐的 ④ 面 `/v1/models` 对**有效** key 回 401（该前缀下根本没有模型列表），
  ① 面同一 key 的 `/models` 回 404【实测 2026-09-18】。把 401 / 403 也算进「再发一次 completion probe 定论」的集合——补全端点对错 key
  同样 401，对造的模型 id 回协议形状的 404，二者分得开（坑 136）。
- **目录声明的端点类型不等于这把 key 能用**（New API，【实测 2026-09-24】）：`GET /v1/models` 对 GPT 的三个账号档声明 `supported_endpoint_types` 含 `anthropic` / `gemini`，
  同一把 key 打 `/v1/messages` 却回 `This group does not allow Anthropic Messages requests`；目录里列着的 `[Azure]gpt-5.6-sol`、`[官key]gpt-5.6-sol` 请求时 503
  `No available channel for model … under group …`（这一档当时没有这个模型的线路）。所以不能按 `supported_endpoint_types` 自动给模型开线路，也不能把「目录里有」当「能用」——
  线路以作者选的为准，「No available channel」要报成「中转站这一档当前没有这个模型的线路」，而不是模型名写错（它与假模型名是同一个 503 报法）。
  反方向也有：OrcaRouter 的 `gpt-6-luna` / `-sol` 只声明 `openai`，打 `/v1/responses` 照样 200【实测 2026-09-26】——声明多了、少了都见过，这个字段只是建议。
- **没有 `/models` 的中继是正常配置不是坏的**（模型 id 可手填）。报错文案必须说清这一点而不是甩状态码——否则用户会读成"我的 key 错了"。

## 6. endpointProbe：模型真实上限的实测

出处：`src/lib/ai/endpointProbe.ts`（HTTP 管线）+ `probeAnalysis.ts`（纯判断）。回答的问题是"这个端点**实际**接受什么"，而不是文档/网关/用户猜的。四步递进、花钱递增：

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
- **tools / JSON mode 能力**：不主动探测，靠**运行时降级**（structured 的错误正则回退、providerProbe 的错误形状判定）；学到的上限怎样执行、存多久，见 §9；
- **上下文窗口 / 输出上限**：作者自己也不知道的**数值**，才花钱实测。

这是刻意取舍，配合 SKILL.md「六条贯穿性设计原则」的 2–4 条收尾，本篇只补两点：

- 「主动发出的每个字段都是某个中继可以 400 的字段」有一个有记录的刻意例外：`max_uses`（见第 5 篇）。
- 不响的失败除 API 日志对照、探测外，还可用「结果之后模型说话了吗」式的间接判据主动验证。

## 8. 付费实测（live probe）纪律

出处：simple-ai-writer `src/lib/__tests__/live.openai-responses.test.ts`、`live.qianwen.test.ts`；结果记录在 `docs/api/landscape.md` §7 的编号样本。

中转站与新型号的真实行为只能花钱测。每一次都要留下可复跑、可引用的产物：

1. **驱动真实 adapter**：经 `streamCompletion` 发请求，验证的是应用自己的请求体与流解析，而不是手写的 curl 仿制品。先用 curl 便宜地摸清形状，再写 live 文件。
2. **env 门控、不进常规套件**：`describe.skipIf(!KEY)`；base / 模型列表也走 env（中转站模型 id 常带档位前缀）。key 只在命令行 env 里，**永不进仓库文件**。
3. **"全部 skipped" = key 没加载，不是通过。** 典型原因：key 写在 shell 配置文件里，而工具/CI 的非交互 shell 不读它——每条命令显式经登录 shell 加载（或显式 export）。看到 0 passed / N skipped 先查 env。
4. **控制 token 成本**：多型号共有的能力只在最便宜的那款上跑全套，其余型号只补"可能不同"的几条（默认力度、上限档位、专有模式）；按型号差异写小谓词（如"哪些型号 `max` 会 400""哪些型号拒 `none`"），避免一个已知 400 把无关用例全拖红。
5. **夹具要满足端点下限**：xAI 拒绝总像素 < 512 的图片——16×16 的测试图会让图片用例失败在夹具上。
6. **结果写成编号样本**：每条结论标"实测 / 文档口径 / 中转站干的 / 未验"，与文档不符的按实测记并注明；中转站行为与协议事实分开记，别让中转站的改写污染协议事实页。
7. **流式与非流式各测一遍，以应用实际走的那条为准。** 中转站可能是两套转换：Kiro 渠道的 Claude 同一请求流式报 `prompt_tokens` 301、
   非流式 102；强制 `tool_choice` 非流式生效、流式被无视（04 §4「第四种变体」）；`web_search` 与函数工具同发时流式真搜、非流式被丢
   （05 §5「中转站自己做服务端工具」）【实测 2026-09-23】。curl 探形状通常是非流式的，而应用多半永远流式——**最便宜的探测恰好朝「支持」的方向撒谎**。
   服务端工具再加一维：单独挂与和函数工具同发也要分开测。
   计费字段同理：OrcaRouter ④③ 的花费字段非流式测时看得到，流式不带请求头就没有（01 §9.5，坑 186）【实测 2026-09-26】——
   「按应用真实会发的形态」包括流式、真实的工具组合、真实的请求头。
8. **「跨模型逐字相同」是模型没参与的信号**：同一请求在两款模型上输出与 `output_tokens` 完全一样（Kiro 渠道单独挂 `web_search` 时固定 644 / 568 / 478），
   说明回答是中转站的模板，不是模型写的。测多模型时顺手比一次。
9. **同一台中转站至少测两个渠道，再给结论归属。**几个渠道都一样的是中转站转换层的（按平台 × 面记），不一样的才是渠道的。
   只测一个渠道会把转换层的缺口记成渠道特性——第十五个样本就这样把 ① `max` = 不想、`response_format` 被丢记成了 Kiro 特有（第 1 篇 §9.2）【实测 2026-09-23】。
10. **先用一个非法参数给渠道分类。**④ 发 `output_config.effort:"bogus"`：正向渠道回官方原文的 400，反代一律 200，几乎零成本。
    知道是反代，就要预期所有缺口都静默，每一项都用模型猜不出的内容验证（秘密词 PDF、纯色图、与 prompt 冲突的 schema）。
    ② 族同法：`reasoning.effort:"bogus"`——回官方原文 400 的上游校验同源，502 / 500 / 流内 `response.failed` 说明中间还有一层（§2「四个上游四种报法」）【实测 2026-09-24】。
    但校验同源不等于能力同源：GPT 的 `[Pro]` 档校验与官方同文，却是唯一丢结构化输出的账号档。
    **这条分类法测的是请求侧校验，不是后端是谁**：会重新序列化请求的网关上，④ 乱写 effort 也 200，回包却是 Anthropic 原样（OrcaRouter，【实测 2026-09-26】）——
    先用第 12 条的回包证据判后端，再用它判「请求有没有被原样送到」。
11. **注入与计费类的结论，同一请求多跑几次。**同一档背后不止一个账号：第十七个样本 `[特价Pro]` 同一类请求的注入量有 0 / 11 / 296 / 4.4K / 17K 五种、延迟从 3 s 到超时，
    不带 `instructions` 时「Say OK.」3 次不注入、创作题 2 次多出 11 token，① 面多数请求注入 4.4K【实测 2026-09-24】——只测一次，结论取决于落到哪个账号。随机性大的项（结构化输出、力度、温度、强制工具、缓存、图片 URL、创作请求）各补跑 3–4 次；
    有 `usage.attribution` 的上游直接读注入量（§1）。创作类应用另加一条：用一道创作题（写个短鬼故事）测护栏——网关上游 6 次拒 2 次，只跑一次很可能漏掉。
12. **经网关，先按面判后端，再决定一条观察记在哪。**同一台网关的各面背后可以是不同的东西（OrcaRouter：④ Anthropic 原样、③ Vertex 原样、① 与 ② 默认线路是 OpenRouter 形态的翻译层、
    ② 带 `store:true` 才换到 OpenAI 原样），而且请求侧会被重新序列化（未知字段、非法枚举静默丢掉）【实测 2026-09-26】。判据是第 1 篇 §9.5 的透传证据清单与漏出的上游响应头。
    回包形状、事件、计费数字在「原样」的面上可以记成官方事实；**「发 X 会不会 400」只记成网关事实**，不改写协议事实页。
    计数端点（③ `:countTokens`、④ `count_tokens`）先确认没被当成生成执行——OrcaRouter 的 `:countTokens` 是一次计费的 `generateContent`。
    花费以网关报的字段或 `GET /v1/generation?id=` 一类查询记账，不只靠估算；要让报价**进账**，先拿回包里的数与账单查询逐笔对过（「报的数 = 实扣」），
    再把这个平台声明为受信（§1「上游报价进账的规则」）。
13. **「收下了」不等于「生效了」——一个 200 的采样参数要用分布去测。**问的是温度这类「发了不报错、效果只在统计上看得见」的字段（03 §3.4 的 ④ 关思考温度）【实测 2026-09-28】：
    - 用**只有几个常见答案**的题（「随便说一种水果」「1 到 50 随便挑一个数」，只答一个词），每档 20 次，记 20 次中最多的那个答案出现几次；低温度收敛到同一个答案（19–20/20）才算生效。
    - 开放题分不出来：每句都不一样，温度 0 下句子开头明显趋同，不同句子的个数照样是 5。
    - **一道题不够**：模型的缺省若已把那道题收敛（MiniMax-M3 不发温度就 19–20/20 答同一种水果），那道题对它什么也说明不了——至少两道，看缺省最分散的那道。
    - 同一档的边界值单测：`0` 要单列一档，它可能被当成「未设」（火山方舟 ④：`0` 与不发分不开，`0.01` 收敛）。
    - 请求体用真实适配器产出，只在发送层补上要测的字段——测的正是「改了规则之后适配器会发的那个请求」。

---

（自 11 篇坑 54、55、67 移入）调研方法两条与一条报错原文：
- **指南页 ≠ 参考页**：判断能力边界看 API 参考页；大文档抓原文自己搜——网页摘要工具连续漏掉 295KB 参考页里的关键定义，curl+grep 一次找到（坑 54）。
- **兼容层文档四条规律**：结构照抄；扩展在响应侧；枚举是子集；最需要确认的部分（流式格式、错误通道、回传规则）不写且滞后上游一年。推论：兼容层文档不能当能力清单——「没列」按「未知、需实测」处理（坑 55）。
- 第 5 条的 xAI 图片下限报错原文：16×16 夹具 400 `below the minimum of 512 pixels`，看起来像图片输入不支持（坑 67）。

## 9. 按 400 学降级：一个执行器、学到的上限持久化

出处：simple-ai-writer `docs/api/capability-resolution-lld.md` §3.7、§9.13（2026-09-28 落地），HLD §6 D3 改判，`provider-layering.md` §7 第一条。

能从失败恢复的能力不预探（§7）：强制 `tool_choice`、结构化输出的档位（schema → json_object → off；④ 只有 schema / off，04 §2）都等端点 400 了再降。
降级规则、执行循环、学到的存储各只有一份：

- **一张分类表**：每行「报错正则 → 事实 → 本次请求用了这个事实吗 → 降到哪一档」。今天两行：`/tool[_ ]?choice/` → 强制工具（降成 `auto`），
  `/response_format|text\.format|response_?json_?schema|output_config\.format|output_format/` → 结构化档位（降一档）。以后学温度、学 effort，都是加一行。`AbortError` 一律不学。
- **一个执行器**：统一入口是一个循环——每轮先出请求计划（这次实际要发的强制、档位、JSON 的 body 字段与 cue），发送；**首块之前**的错误交给分类表，
  学到就记下、重新出计划、再发，学不到原样抛出。首块之后不重试（已交付的内容不能重来）；已经到底（off）的不重试。调用方只说意图（「这次要 JSON，schema 是 X」），
  拿回成功那次的档位；各调用方自带的「JSON 被拒再试」包装一律删掉。任务层「强制工具没调用就改走 JSON」是路径选择，不是学习，它保留，但读计划里**发出的**强制。

### 9.1 比对的是计划实际发出了什么，不是请求了什么

一个请求要了强制 `tool_choice`，适配器已按类目 / 平台格把它降成了 `auto`（04 §4）；这时再来一个点名 `tool_choice` 的 400，那不是强制的错。
按「请求了」比对，会学一次、原样重发一次、再失败——白付一趟。分类表的「用了这个事实吗」读计划里的 `sent`，JSON 档位读实际拼进 body 的那一档
（没有 schema 时它会低于决定的档）。

### 9.2 终止性：不靠「这次调用降低了上限」

- 论证：分类表只在「本次请求用了该事实」**且**「存在更低一档」时才报；下一轮计划受该上限约束，所以每次重试发出的**严格更少**。格是有限的（开关两级、档位三级），最多重试三次（请求数 ≤ 4）。
- 常见的加法——「只有 `noteLearned` 这次严格降低了上限才许重试」——变异测试表明它对终止性是**空的**（去掉它循环照样终止），而且在并发下是**错的**：
  两个并行请求撞同一个 400，先学到的那个把上限降了，后到的发现「不是我降的」就抛错，而它只要按已降的上限重发就能成功。所以是「学到即重试」，并为并发写一条测试。
- 测法：随机 400 序列跑几百例，钉住请求数 ≤ 4、上限只降、每次重试发出的严格更少；变异「分类不看计划的档」会让循环不终止——测试要能抓到它。

### 9.3 JSON cue 接在最后一条 user 消息里，不另起一条

执行器替调用方追加「只输出 JSON」的 cue（04 §2）时，接在**最后一条 user 消息末尾**（字符串空一行接上；分块内容追加一块），不新加一条 user 消息。
两条连续的 user 消息在要求严格交替的本地模型 chat 模板上会报错；④ 也要求交替（02 §2.1）。

### 9.4 持久化：学到的是端点的事实，不是作者的配置

原先是会话级（进程内存，重启即忘）。【2026-09-28 改判】持久化，但带时间、会过期、作者的新说法能作废它。收益要照实说：拒绝发生在生成之前，重学只花一个 400 的往返、不花 token；
省下的是每次重启后第一次结构化任务多出的那一趟——本地模型上强制工具那一趟可能是几十秒。

- **读仍只读内存、仍同步**：计划、适配器、界面都不改签名。启动时先注册写出口，再删过期行、读回内存，与内存里已学到的取更低者；每次降低经出口**异步写穿**到库。
- **库侧 upsert 只降**：只在新值更弱、或旧行已过期时覆盖——多个窗口各自从自己的 400 学到，谁也不许把别人写下的抬高。这条规则写在 SQL 里，不靠调用方。
- **写与删串成一条链**：紧跟在写入后面的「忘掉」不能先落库。
- **7 天过期**（读时判断，载入时删）。这个数没有实测依据：端点与中转站会升级，重学只花一个 400。更低者保留它自己的时间，它过期时后来学到的弱一档随之丢掉——代价是再撞一次 400，为此给存储第二种形状不值。
- **未来时间的余量一小时**：学到的时间在未来一小时以上（学到后时钟被拨回）不算数、载入时删掉，否则它会多活出时钟错开的那么久。
  留一小时而不是零，是因为两个窗口用同一个时钟盖时间、落库却不分先后，差几毫秒是常事，不是时钟被拨回。
- **提前作废**：作者改了这条线路的结构化输出声明（换线路时载入停放的声明不算）→ 忘掉那一项；作者在界面里对这条线路做了探测、**且端点答上了话**
  （探测报告带一个「答没答话」的字段；取消的、一次都没答的不算）→ 忘掉这条线路的全部事实；应用重置 → 整表清空。换地址、换模型 id 不需要规则：键变了，旧条目不再命中，7 天后自然清掉。
- **不随配置备份与配置同步走，也不进项目库**：这台机器、这条网络上端点说过的话，换一台机器未必成立。已知缺口：导入配置备份不走「改声明」的路径，最多再压 7 天；要补，更干净的是「导入即清空学到的」一条规则。
- **界面的读者要订阅存储**：说明文字从「本会话」改成「什么时候会再试」；模型面板若只在打开时读一次，探测清掉上限之后它仍显示旧的拒绝（实际发生过）——存储给订阅入口 / 版本号，面板随之重绘。
- 不加「忘掉」按钮：点一次探测就能清。

### 9.5 被动的值会过期，主动的值不会

探测维（第 1 篇 §1）其实有两半，过期规则相反：

| | 从哪来 | 落在哪 | 过期 | 与作者的值谁优先 |
| --- | --- | --- | --- | --- |
| **被动**：学到的上限 | 端点自己的 400 | 不在作者看得见、改得了的字段里 | 7 天；改声明 / 重新探测即作废 | 压住作者的声明（端点亲口说不收），作者的新说法作废它 |
| **主动**：探测值（上下文 / 输出上限等） | 作者点的探测 | 写进作者的字段，出处可见 | **不过期**，重新探测时覆盖 | 作者填的值优先，探测值其次 |

理由在「落在哪」：被动的值过期只是多撞一次 400；主动的值写在作者的字段里，过期会让字段无声地变。

---

## 本篇检查清单

- [ ] usage 内部口径三字段（input / output 含思考 / cached 为 input 子集）+ 计费公式有文档。
- [ ] Anthropic input = 三桶求和；`message_delta` 不清零已立的 input。
- [ ] Gemini output = `candidatesTokenCount + thoughtsTokenCount`；input = `promptTokenCount + toolUsePromptTokenCount`。
- [ ] `persistUsage` best-effort 永不抛；total 从明细 rollup 派生；NULL→0 在边界处理。
- [ ] 各族适配器都处理 SSE 体内 `data:{"error":...}`；OpenAI 系另处理 `base_resp.status_code`。
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
- [ ] ② 族终止事件做回显比对（effort / temperature，比最终 body 的值）；不一致进 `wireRewrites` → API 日志 + 执行日志；不重试不抛错；回显缺失不报告。
- [ ] 入口/包装层装的每个回调都串联调用方的同名回调，有单测钉住。
- [ ] live 实测：驱动真实 adapter、env 门控、key 不落仓库；"全部 skipped"按 key 未加载排查；共有能力只在最便宜型号上跑全套；结果记为编号样本并区分实测/文档/中转站/未验。
- [ ] 中转站的实测覆盖流式与非流式两条路径（服务端工具再分单独挂 / 与函数工具同发），结论以应用实际走的路径为准；多模型实测时比对过「跨模型逐字相同」。
- [ ] 中转站估算的 usage（缓存分段拼出来、`cache_control` 只写不读）没被当成缓存生效的证据；兼容 ④ 线路默认不发 `cache_control`。
- [ ] ② 读 usage 时容忍 `attribution`、`cache_write_tokens` 等新键；需要核注入时读 `attribution.request_fields.instructions.input_tokens`。
- [ ] 按 400 学降级的正则不匹配 502 / 500 / 流内 `response.failed` 这类「上游故障」形状；流式 200 里的 `response.failed` 与流内 `error` 事件后接空答都当失败。
- [ ] 按 400 学降级只有一个执行器、一张分类表：比对计划**发出的**强制与档位；只在首块之前重试；「学到即重试」（不要求「这次是我降的」），有并发与随机 400 序列的测试；JSON cue 接在最后一条 user 消息里。
- [ ] 学到的上限若持久化：读仍是同步内存、写穿到库；SQL 只降（或覆盖过期行）；写与删串行；有过期（参考值 7 天）与一小时的未来余量；改声明、探测答上话、重置时作废；不进配置备份 / 同步；界面订阅存储。
- [ ] 采样参数（温度）「生效」的结论来自有限答案题 × 每档 20 次的分布，至少两道题，`0` 单列一档；不以 200 当生效。
- [ ] 模型列表的 `supported_endpoint_types` 不用来自动开线路；503「No available channel」报成「这一档当前没有线路」，不报成模型名错误。
- [ ] 图片内联 base64 / data URL，不依赖中转站或上游能下载公网 URL（中转站自己下载失败会 500 `count_token_failed`）。
- [ ] ④ `thinking_tokens` 当 `output_tokens` 的子集读；`server_tool_use` 与 ③ 检索的按次费用单独计；没发 `cache_control` 出现的 `cache_creation` 不当异常。
- [ ] 错误分类只靠 HTTP 状态 + 报文关键字，不靠 `error.type` / `param` / 字段路径（中转站会改写成 `<nil>`、遮成 `***`）。
- [ ] 花费字段按面各读各的，同一端点读不到时退回表算；经网关的实测结论区分「回包事实」与「这台网关会不会 400」。
- [ ] 上游报价只对声明过「报价 = 实扣」的平台、且请求地址也指向它时才收；换算一处；「没报」≠ 0；多次请求合一行时全报才加；显示与记账同一算式；写入口的报价是必填键。

## 补遗（自 22 篇移入，2026-09-28）

自 22 篇移入的平台级值已归 20 §3（注入实数 / 护栏 / file_id / 上限 / 原样线路字段 / 图片下限 / countTokens 计费），本篇不再重复。
