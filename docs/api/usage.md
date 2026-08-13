# 用量与上限：token 怎么算，窗口怎么问

> 边界见 [`README.md`](README.md)：只写协议事实。族的编号沿用
> [`landscape.md`](landscape.md)：① Chat Completions ② Responses ③ Google GenAI
> ④ Anthropic Messages。

## 1. usage 字段对照

| | ① Chat Completions | ② Responses | ③ Google GenAI | ④ Anthropic |
| --- | --- | --- | --- | --- |
| **输入** | `usage.prompt_tokens` | `usage.input_tokens` | `usageMetadata.promptTokenCount` | `usage.input_tokens` |
| **输出** | `usage.completion_tokens` | `usage.output_tokens` | `usageMetadata.candidatesTokenCount` | `usage.output_tokens` |
| **缓存命中** | `prompt_tokens_details.cached_tokens` | `input_tokens_details.cached_tokens` | `usageMetadata.cachedContentTokenCount` | `usage.cache_read_input_tokens` |
| **缓存写入** | — | — | — | `usage.cache_creation_input_tokens` |
| **思考 token** | `completion_tokens_details.reasoning_tokens` | `output_tokens_details.reasoning_tokens` | `usageMetadata.thoughtsTokenCount` | `output_tokens_details.thinking_tokens` |

## 2. 两个口径陷阱

### 2.1 缓存计数：子集 vs 不重叠

**①②③ 的"缓存命中"是输入的子集**——`cached_tokens ≤ prompt_tokens`，计费时
只有未命中的余量按全价算：

```
成本 = (input − cached) × 全价 + cached × 缓存价
```

**④ 的三个桶互不重叠**：`input_tokens` **只是未命中缓存的余量**，缓存读与
缓存写各自单列。要得到可比的"总输入"必须**相加**：

```
总输入 = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
```

直接读 ④ 的 `input_tokens` 当作总输入，会在长提示词 + 缓存命中时把输入量少报
一个数量级。另外**缓存写入的价格高于基础输入价**，若数据模型里没有这一档费率，
把它算进全价桶会高估成本——那是这个方向上安全的一侧。

### 2.2 思考 token：已含 vs 未含

**①②④ 的"输出"已经包含思考 token**，`*_details.reasoning_tokens` 只是其中的
明细。

**③ 的 `candidatesTokenCount` 不含思考**，思考单列在 `thoughtsTokenCount`。
只读前者会把"思考 5k、回答 500"的一次请求记成 500 —— 少算的正是最贵的部分。
可比的输出是二者之和。

## 3. 输出上限

| 协议 | 字段 | 必填 | 备注 |
| --- | --- | --- | --- |
| **①** | `max_tokens` → **`max_completion_tokens`**（新名） | 否 | 旧名多数端点仍接受，部分已标记弃用 |
| **②** | `max_output_tokens` | 否 | |
| **③** | `generationConfig.maxOutputTokens` | 否 | |
| **④** | `max_tokens` | **是** | **没有服务端默认值**，不传就是错误 |

④ 的必填是跨族移植时最容易漏的一条：其余三族省略即用服务端默认，只有它必须
自带一个兜底常量。

**上限与思考的相互作用**：④ 的手动思考模式下 `budget_tokens` 必须 <
`max_tokens`（思考 token 计入同一个上限）；而在高 effort 下若 `max_tokens` 给
得太小，模型会把额度全用在思考上、正文被截断。JSON 输出场景尤其危险——截断的
JSON 解析失败，看起来像"模型不听话"。

## 4. 上下文窗口：协议不告诉你

**四族的请求响应里都没有"这个模型的上下文窗口有多大"。** 这不是遗漏，是分层
——窗口是模型属性，而协议只描述一次调用。

后果是：**超出窗口的表现各不相同，且最坏的一种是静默的。** 托管端点通常返回
一个明确的错误；本地栈（ollama 等）则可能**从头部丢弃**并返回 200 —— 丢掉的
一般正是 system 指令，而没有任何字段会说明这件事发生过。

可用的信息来源，可靠性递减：

1. **`/v1/models` 的扩展字段** —— 非标准，各家自定：OpenRouter 的
   `context_length` / `top_provider.max_completion_tokens`、LM Studio 的
   `max_context_length` 等。
2. **ollama 的 `/api/show`** —— `model_info` 里有 `<arch>.context_length`，
   `parameters` 里可能有实际生效的 `num_ctx`（**后者才算数**，且默认常常远小于
   模型本身的能力，2048/4096 是常见值）。
3. **llama.cpp 的 `/props`**。
4. **实测**：发一个已知长度的填充请求，看是被拒绝还是被截断。成本高但唯一
   可靠。

**测量会过期。** 中继随时可能把同一个模型名路由到另一个上游，所以任何探测结果
都应带时间戳，呈现为"某日实测"而非永久事实。

## 5. 计费维度不止 token

- **按张计价的图像端点**（Imagen、xAI 等）用"每张图"计费，而 OpenAI 的图像模型
  把生成计为 token。同一个模型可能两种都有，所以**两者相加**比二选一更安全。
- **③ 的多模态**在 `prompt_tokens_details` 下还有 `image_tokens` / `audio_tokens`
  等明细（部分兼容层也提供），且图片 token 用量随分辨率档位变化很大——同一张图
  在 low / default / high 三档下可能相差一个数量级。
