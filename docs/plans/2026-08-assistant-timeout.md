# 提示词助手超时：诊断与修复

**性质**：一次真实故障的取证记录 + 两个 PR 的实施说明。
**证据**：`api_logs/` 里 2026-08-25 09:48–10:08 的连续 7 条日志（一次 nanoBanana cosplay 提示词会话）。
**结论**：超时**不是**「接口慢」，是三个结构性缺陷叠加的必然结果。三条修完之前，任何一次值得要的回答都注定超时。

---

## 0. 取证：日志实际说了什么

日志在请求发出时创建、在响应到达时追加，所以 `mtime − Timestamp` 就是真实耗时。

| # | 发出 | 响应落盘 | 耗时 | output tokens | 结果 |
|---|---|---|---|---|---|
| 1 | 09:48:47 | 09:50:16 | 89s | 25 | ✅ |
| 2 | 09:50:16 | 09:51:03 | 47s | 23 | ✅ |
| 3 | 09:51:03 | 09:54:22 | **198s** | 5543 | ❌ 120s 被丢弃 |
| 4 | 09:53:06 | 09:54:05 | 59s | 615 | ✅（#3 的重试，恰好走了短路径） |
| 5 | 10:01:09 | 10:04:14 | **185s** | 6525 | ❌ 丢弃 |
| 6 | 10:03:11 | 10:06:08 | **177s** | 6263 | ❌ 丢弃 |
| 7 | 10:05:13 | 10:08:53 | **220s** | 7131 | ❌ 丢弃 → 报超时 |

两条决定性的观察：

1. **#5 / #6 / #7 的请求体逐字节完全相同**（31305 chars，`commonprefix` 等于全长），发出间隔精确是 **122 秒 = 120s 超时 + 2s 退避**。#3 / #4 同理。
2. **模型每次都成功生成了完整答案**，只是在客户端放弃之后才送达。一次「超时」= 3 次 Opus 满负荷生成（约 2 万 output tokens）+ 约 24 MB 上传 + 6 分钟等待 + 零产出。

`Future.timeout` **不取消**底层 HTTP 请求，这就是为什么被放弃的响应仍然写进了日志——也意味着 #7 发出时 #6 还在传，三个请求在抢同一条上行带宽。#7 是全场最慢的 220s，正是这个原因。

---

## 1. 三个根因

### 1.1 每轮重传 8 MB 图片

日志里被截断的字符串合计省略 8,403,659 字符，其中三个是 base64 图。对真实文件实测：

| 文件 | 尺寸 | base64 |
|---|---|---|
| `yaxin_close-up_2.png` | 719×1244 | 0.79 MB |
| `arcanashadow_cos_combine_…_1.png` | 1470×1344 | 3.31 MB |
| `arcanashadow_cos_combine_…_2.png` | 1689×1344 | 3.87 MB |
| | | **合计 7.97 MB** |

agent 的 tool loop **每一轮**都完整重传这 7.97 MB。7 轮 = 55.8 MB。这解释了为什么 #2 只输出 23 个 token 却花了 47 秒——那 40 多秒全在传图。

`ImageCompressor.compress` 的 3 MB 阈值太高，而且**只做 JPEG 重编码、从不缩放分辨率**，三张图全部原样直传。

### 1.2 带 tools 强制非流式 + 平坦的 120s 超时

`LLMService.request` 把任何带 tools 的请求降级成非流式；`generateTimeout` 给非 midjourney/longRunning 的路径钉死 120 秒。

`submit_prompt` 的产物是一份 6000–7000 token 的提示词文档（`max_tokens` 默认 8192，几乎顶格）。加上 8 MB 上传和 TTFT，**结构上不可能落在 120s 内**。短的 tool call 能过，长的必挂。

`protocol.dart` 原先的理由是「agent loop 无法消费部分批次」——这针对的是*增量消费*。但需要流式的原因不是增量消费，是**保活**：流式分支用的是 `stream.timeout(120s)`，**每 chunk 重置**。

### 1.3 超时重试是纯亏损

`isRetryable(TimeoutException) == true` + `retryCount: 2`。输入没变、输出长度需求没变，重试必然再超时——而且旧请求还在跑、还在占带宽、还在计费。

---

## 2. PR1：让请求跑得完

| 提交 | 做了什么 |
|---|---|
| `perf: the assistant stops re-uploading megabytes…` | viewOnly 附件走 `compressForViewing`：长边 >1568px 缩放 + 超 512KB 转 JPEG q85。实测 7.97 MB → 0.89 MB（**8.9×**）。`compress()` 语义不变，仍然拒绝缩放——那是生成输入走的路，分辨率是用户要的东西 |
| `fix: a deadline the answer can actually meet…` | 超时改成 `60s + cap/25 tok每秒`，下限保持 120s、上限 10 分钟（④ 的 8192 默认落在约 6.5 分钟）；非流式超时抛 `LLMDeadlineExceeded`，**不重试** |
| `feat: ④ streams its tool calls…` | `AnthropicStreamAssembler` + `streamingDeclaresTools` + `LLMDispatcher.streamSupportsTools`；三条 agent 循环改走流式 |
| `feat: mark the reusable prefix so ④ can cache it` | `cache_control` 三个断点（system 末尾 + 最后两条消息），按 vendor opt-in |
| `fix: the debug log stops hiding the numbers…` | 掩码改精确匹配；新增 `Body bytes:` 和 `Elapsed:` |
| `perf: requests to the same endpoint reuse the connection` | 按 endpoint+proxy 复用 `http.Client`，句柄的 `close()` 是 no-op |

### 2.1 两个需要知道的取舍

**流式的空闲守卫对第一个 chunk 更宽容**（180s vs 后续 120s）。沉默在首字节前后含义不同：之后的两分钟无字节基本就是连接死了；之前则是歧义的——大 prompt 在繁忙中转站排队预填充，看起来一模一样。而把它判成死连接就会重发整个请求，正是这套改动要消除的浪费。顺带一个好处：这条路用 `StreamIterator` 写，`finally` 里的 `cancel()` **真的**拆掉了订阅，不像非流式的 `Future.timeout` 会把请求留在上游继续跑、继续计费。

**超时区分两种 TimeoutException。** 同一个词在两条路上含义相反：流式的守卫是**按 chunk** 的，它到期意味着「两分钟一个字节都没有」= 连接死了，重连完全正确；非流式的到期意味着「生成没写完」，重试是纯亏损。所以给后者一个专门的类型 `LLMDeadlineExceeded`，而不是一个布尔开关。

**`cache_control` 是按 vendor opt-in 的。** 标记前缀要求把 `system` 从字符串改成 block 数组，一个「重新拼装 payload 而不是原样转发」的中转站可能不认这个形状——而不认的后果是**整个请求失败**，不是只有缓存失效。`anthropicRest` / `newApiAnthropic` 开，`minimaxAnthropic` 关（它的 ④ 兼容层已经被发现缺过这个 App 会发的东西）。谁在真实端点上验过再打开。

### 2.2 只做了 ④，没做 ① / ③

① 的 `function.arguments` 按 `delta.tool_calls[].index` 分片（`docs/api/streaming.md` §1），要另写一套累积器。① / ③ 目前仍然降级到 `generate()`——但它们同时拿到了「超时随 output cap 伸缩」这条兜底，所以不是原地不动。

`Elapsed:` 目前只加在三条 chat 协议（standard + stream）上，图像/视频协议有自己的长任务语义，没有一并铺开。

---

## 3. PR2：会话管理调优

不是超时的成因，是同一次取证里顺带看到的账。

1. **附件独立的、更短的保留窗口**：`_keepAttachmentTurns = 2`，其它仍是
   `_keepRecentTurns = 6`。两种成本不可比——知识库读取的字符只付一次，附件是
   **每一轮的每一个请求**都重新上传、重新计图片 token。提前 elide 是廉价的，
   因为它可逆：liveness 是推导出来的，模型可以再 `view_image`，只在真正需要的
   那一轮付这张图的钱。

   `_elide` 和 `_liveViewedPaths` **必须读同一个边界**。它们是一条规则的两半：
   一半决定附件还在不在请求里，另一半决定模型能不能再要一次。指向不同的窗口，
   就是用两个各自看起来正确的一半重建出那个死锁。这条由
   `optimizer_image_liveness_test.dart` 里的「liveness agrees with what is
   actually sent, at every distance」直接钉住。

2. **`_attachmentChars` 2000 → 3300**（2200 token × `charsPerToken` 1.5）。旧值
   约等于 1300 token，只有真实值的一半。**单个常数之所以站得住，是因为 PR1 的
   `viewOnlyMaxLongEdge` 给输入封了顶**——在那之前附件可以是任意大小，任何常数
   都没有意义。

3. **流式 debug log 缓冲落盘**：新增 `appendStreamLine`（64 KB 阈值），`finish`
   负责冲刷。`appendLine` **保持直写**——有几条协议记完响应就不调 `finish`，缓
   冲了不冲刷的输出等于凭空消失。

4. 同步更新 `docs/architecture/assistant-context.md`：两个窗口写进 *The shape*，
   同边界要求写进不变量 4，「一个窗口管所有」进 *Rejected*。


---

## 4. 实测验证（2026-08-25 11:27–11:33，两个 PR 合并后同一条通道）

同一个中转站、同一个知识库、同样三张参考图。

| 起始 | body | 耗时 | in | cRead | cWrite | out | stop |
|---|---|---|---|---|---|---|---|
| 11:27:14 | 12 KB | 5.1s | 201 | 72 | 3677 | 8 | tool_use |
| 11:27:19 | 13 KB | 4.2s | 103 | 34 | 3922 | 16 | tool_use |
| 11:27:25 | 927 KB | 14.5s | 4772 | 4054 | 28 | 82 | tool_use |
| 11:27:41 | 1009 KB | 12.7s | 34916 | 8627 | 102 | 25 | tool_use |
| 11:27:55 | 1049 KB | 11.7s | 17572 | 41982 | 32 | 23 | tool_use |
| 11:28:08 | 1074 KB | 26.2s | 10087 | 58749 | 30 | 802 | tool_use |
| 11:28:35 | 1076 KB | 15.7s | 49 | 44 | **69106** | 419 | tool_use |
| 11:31:00 | 1078 KB | **143.4s** | 132 | 68386 | 1217 | **5861** | tool_use |
| 11:33:25 | 1092 KB | 29.9s | 23 | 69729 | 5587 | 664 | **end_turn** |

九个请求 `Type` 全部是 `Anthropic (Stream)`。

| | 修复前 | 修复后 |
|---|---|---|
| 上传总量 | ~56.3 MB | **7.2 MB** |
| Opus output（计费） | 26,125 | **7,900** |
| 逐字节重复的请求 | 3 | **0** |
| 图片 media type | `image/png` | `image/jpeg` |
| 跨度 | 16.4 分钟 | **6.2 分钟** |
| 结果 | 无 | `end_turn`，交付完成 |

**决定性的一条是 11:31:00**：143.4 秒、5861 个 output token、成功。这正是原来的
`submit_prompt`。旧代码下它是「120s 丢弃 → 重试 → 丢弃 → 重试 → 六分钟后报超时、
零产出」。output token 从 26,125 掉到 7,900 不是模型变简洁了，是**没有东西被扔掉
再重算**。

`cache_control` 被这家中转站接受了（无 4xx、无错误信封），而且确实按我们的断点缓
存：后两个请求 cRead 68,386 / 69,729。§2.1 里「谁在真实端点上验过再打开」这条对
`newApiAnthropic` 已经兑现。

### 4.1 一个未解释的异常

11:28:35 那条在会话中途整段重建了缓存（`cWrite 69106 / cRead 44`）。

我们这边的断点布局是对的：**每个请求的 system 断点都落在字节 2332**，位置完全稳
定，另外两个滚动断点按设计前移；system 前缀逐字节相同，本该命中。也排除了附件
elide（#6 / #7 都带 3 张图，`attachment elided` 计数为 0）。所以这是中转站侧的缓
存实现，从这里改不了。

代价是每个会话一次 69k 的 cache write（约 1.25× 输入价），一次性，之后恢复正常。
**判据**：如果在别的 ④ 通道上也看到同样的模式，那才说明是断点策略的问题；只在这
一家出现就是它自己的实现。


---

## 5. ① / ③ 呢？

这套改动大部分落在**共享层**，所以对 OpenAI 系和 Gemini 系自动生效；只有两项是
④ 专有的。

### 5.1 已经生效，与家族无关

| 改动 | 为什么自动覆盖 |
|---|---|
| 图片降采样 | `ImageCompressor.readForApi` 被三条 chat 协议共同调用（`anthropic_chat_protocol` / `gemini_payload` / `openai_chat_protocol`）——**这是最大的一项，8× 的上传削减三家都拿到** |
| 连接复用 | `LLMModelConfig.createClient` 是所有协议唯一的入口 |
| 超时随 output cap 伸缩 | `generateTimeout` 对 midjourney / longRunning 之外的全部路径生效 |
| 超时不重试 | `LLMDeadlineExceeded` 在 `LLMService` 层，与协议无关 |
| 日志掩码 + `Body bytes:` | `LLMDebugLogger` 全局；`Elapsed:` 在三条 chat 协议上都加了 |
| PR2 全部 | 附件窗口、`_attachmentChars`、流式日志缓冲都在 agent / logger 层 |

### 5.2 没有生效的两项

**`cache_control` —— 不需要补。** 这是 ④ 的概念。① 官方 API 是**自动**前缀缓存
（≥1024 token，无 opt-in、无断点）；③ 的 2.5 系列有隐式缓存，同样自动。③ 的显式
缓存是另一套 API（`cachedContents` 服务端资源 + TTL），对一个每轮都在增长的 agent
对话不划算——前缀每轮都变，建了就废。**结论：这一项对 ①/③ 无事可做。**

**流式 tool call —— 值得补，但两家成本差一个数量级。**

### 5.3 ③ 几乎是免费的

`geminiChunksFromSseLine` 走的是**和同步路径共用的 parser**，它已经在解析
`functionCall` 并且带上了 `thoughtSignature`（`gemini_payload.dart` 的
`functionCall` 分支）——③ 的 `functionCall` 是**整个 part 一次给全**，不分片，所
以没有累积器要写。`prepareGooglePayload` 本来就有 `tools:` 参数，只是流式那个调
用点没传。

需要改的：流式 payload 传 `tools` · `streamingDeclaresTools => true` · dispatcher
两处路由。约四行加测试。

要验的是 `thoughtSignature` 在流式路径上确实活着回到历史里——③ 对丢了签名的重放
是 `INVALID_ARGUMENT`（会报错，不像 ④ 那样静默降级，所以至少是响的）。

### 5.4 ① 是真活

`tool_calls` 在 `openai_chat_protocol.dart` 里只出现在**同步**响应解析和历史回放
中；流式解析器完全没有这条分支。要写的累积器：按 `delta.tool_calls[].index` 分组
（`id` / `name` 本身也会分片），而且 ① 没有 ④ 的 `content_block_stop`，只能靠
`finish_reason: tool_calls` 收尾。参考 `docs/api/streaming.md` §1。

### 5.5 现在的风险有多大

①/③ 目前唯一的保护是 `60 + 4096/25 = 223s` 的 deadline，而**那个 4096 是猜的**：
App 不给 ①/③ 发 `max_tokens`，真实上限由服务端定（`_outputCap` 的注释写明了这是
一个 stand-in）。

对照 §4 的实测：④ 的 `submit_prompt` 是 5861 token / 143.4s ≈ 41 tok/s。同样的活
在 ①/③ 上是 ~170s 生成 + TTFT + 上传——**223s 能过，但不宽裕**，模型再啰嗦一点就
压线。

三条路，按性价比：

1. **补 ③ 的流式**（四行，风险极低）。
2. **给 agent 显式传 `maxTokens`**，deadline 就有真实数字可依而不是 4096 这个
   猜测——这是最便宜的止血，不依赖任何流式工作。
3. **补 ① 的累积器**，单独一个 PR。

---

## 6. 顺带记一笔（不在这两个 PR 范围内）

出问题的 endpoint 是 `http://42.240.165.241:3000`，**明文 HTTP**。`x-api-key` 和整个知识库内容都是裸传的。这是渠道配置问题，不是代码问题，但值得在这里留一行。
