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

## 4. 顺带记一笔（不在这两个 PR 范围内）

出问题的 endpoint 是 `http://42.240.165.241:3000`，**明文 HTTP**。`x-api-key` 和整个知识库内容都是裸传的。这是渠道配置问题，不是代码问题，但值得在这里留一行。
