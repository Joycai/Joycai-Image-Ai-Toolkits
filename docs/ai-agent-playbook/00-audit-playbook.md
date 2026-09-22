# 00 · 审查手册：用本库审一个项目的模型支持

回答两个问题：
- **完整度**：它声称支持的厂商与功能，是否每个维度都接上了？
- **正确性**：接上的部分，是否与本库记录的已验证事实一致？

本手册与目标项目用什么语言、什么框架无关。线格式里的字面量（端点路径、请求头、字段名、事件名）在任何语言里都是同一串字符，所以用它们来定位实现，比找类名可靠。

## 1. 盘点：它到底支持什么

用下表的线格式字面量搜目标代码库，列出**协议族 × 厂商 × 面**的清单。搜不到的，就是没接。

| 要找的 | 搜这些字面量 |
| --- | --- |
| ① Chat Completions | `/chat/completions`、`tool_calls`、`finish_reason`、`stream_options`、`include_usage` |
| ② Responses | `/responses`、`instructions`、`response.output_item.done`、`function_call_output`、`store` |
| ③ Gemini | `generateContent`、`streamGenerateContent`、`alt=sse`、`x-goog-api-key`、`functionDeclarations`、`thoughtSignature` |
| ④ Anthropic | `/v1/messages`、`anthropic-version`、`x-api-key`、`tool_use`、`content_block_delta`、`pause_turn` |
| 思考 | `reasoning_effort`、`reasoning_content`、`thinking`、`budget_tokens`、`thinkingConfig`、`thinkingLevel`、`enable_thinking`、`<think>` |
| 结构化输出 | `response_format`、`json_object`、`json_schema`、`responseMimeType`、`text.format` |
| 服务端工具 | `web_search`、`max_uses`、`enable_search`、`code_interpreter`、`server_tool_use` |
| 出图 | `/images/generations`、`/images/edits`、`b64_json`、`:predict`、`responseModalities`、`multimodal-generation`、`/v1/image_generation`、`/mj/submit` |
| 视频 | `/videos`、`video_generation`、`X-DashScope-Async`、`task_id`、`predictLongRunning`、`operations` |
| 语音识别 | `/audio/transcriptions`、`verbose_json`、`timestamp_granularities`、`input_audio`、`asr_options`、`-filetrans`、`getPolicy`、`/audio/asr/transcription`、`diarization_enabled`、`silencedetect` |
| 厂商 | 厂商的 base host（`api.openai.com`、`api.anthropic.com`、`generativelanguage.googleapis.com`、`api.x.ai`、`dashscope`、`minimax`、`volces.com`、`openrouter.ai`、`:11434`…） |
| 错误通道 | `base_resp`、`status_code`、`"error"`、`promptFeedback`、`blockReason`、`content_filter`、`refusal` |

盘点结果写成一张清单，每项带实现位置（文件:行）。项目自己的文档或设置界面里「宣称支持」的东西也列进来，留到第 2 步对照。

## 2. 完整度：覆盖矩阵

对盘点出的每个**族**、每家**厂商**，按下表逐格填 ✅ 已接 / ⚠ 部分 / ❌ 未接 / — 不适用。每一列对应本库的一篇，格子里填的判断要能指到那一篇的小节。

| 维度 | 对照 | 典型的「部分」 |
| --- | --- | --- |
| 请求形状与消息转换 | 02 §1–2、§7.1 | ④ 的交替律没修补；③ 的 tool 结果没按函数名匹配 |
| 流式解析 | 02 §3、§7.2 | ① 的 tool_calls 按 id 拼接；③ 当成 delta 拼接 |
| 地址与鉴权 | 02 §4–5 | Anthropic base 按 OpenAI 惯例拼 `/v1`；空 key 仍发空 Bearer |
| 思考：强度 / 取回 / 回传 | 03 全篇 | 只做了强度，没做回传义务 |
| 结构化输出 | 04 全篇 | 没有强制工具失败后的 JSON mode 回退 |
| 工具与服务端工具 | 05 全篇 | 没有 `max_uses`；② 族工具没写 `strict:false` |
| 错误通道与 usage | 06 §1–2 | 只认 `error`、不认 `base_resp`；Anthropic usage 没三桶相加 |
| 回显比对与日志 | 06 §4 | 没有请求体日志，中转改写无从发现 |
| 出图 | 13 全篇 | URL 存库不下载；单张失败判整次失败 |
| 视频 | 14 全篇 | 没有总 deadline；失败放进了返回值 |
| 语音识别 | 16 全篇（§11 是逐条清单） | 同步接口上开说话人分离；403 / 404 不分步骤 |
| 厂商特有事实 | 15（索引）→ 各节 | 火山方舟没显式发 `watermark:false` |

「宣称支持、实际 ❌」的格子本身就是一条发现。

## 3. 正确性：先查静默失败

优先级按「出错时会不会响」排：**不会响的先查**。会响的 400 用户迟早会撞见；不会响的只会以「效果变差」「账单变贵」「数据慢慢坏掉」的形式出现，只有对照事实才发现得了。

### 3.1 横切（每个项目都查）

| # | 检查 | 事实 | 坑 |
| --- | --- | --- | --- |
| 1 | HTTP 200 不等于成功：SSE 体内的 `error`、MiniMax 的 `base_resp.status_code`、半截文本后才到的内容拦截，三种都要当失败处理 | 06 §2 | 6、7 |
| 2 | 按族分发的地方用的是「折回族」后的值，新增的 compat 值不会掉进 ① 分支 | 01 §3 | — |
| 3 | 跨协议的回传载体按前缀剥除，不按名单 | 01 §4 | — |
| 4 | usage 口径：Anthropic 三桶相加；Gemini 思考 token 另算；① 的 `include_usage` 在兼容层可能没有 | 06 §1 | 8、18 |
| 5 | 本地栈超窗会从头部静默截断：发送前要有估算拦截 | 01 §6 | 5 |
| 6 | 统一入口装的钩子**串联**调用方的钩子，不覆盖 | 06 §4.2 | 72 |
| 7 | 所有可能动到 effort / temperature 的端点做了回显比对（至少记日志） | 06 §4.1 | 61 |

### 3.2 按族

| 族 | 检查 | 事实 | 坑 |
| --- | --- | --- | --- |
| ① | tool_calls 按 `index` 累积；`<think>` 标签跨 chunk 能切分；`json_object` 的上下文里有 json 字样 | 02 §3、03 §6、04 §2 | 12、14、15 |
| ① | 思维链字段按原名回传（DeepSeek 两个方向都会 400） | 03 §5 | — |
| ① | 中转的接收侧畸形都防住：拼接的多对象参数、空串调用 id、空的 `reasoning_content` 盖住 `reasoning`、usage 末块 `choices:[]`、数组形 `content` | 02 §3.2、03 §4、05 §3 | 105–108 |
| ② | `instructions` 恒发（中转站会注入几千 token）；`store:false` 下整组 output 条目回传；工具显式 `strict:false`；`text.format` 不带 `strict` | 02 §7、04 §5 | 62–64 |
| ③ | 每个 chunk 是完整对象不是 delta；`thoughtSignature` 原样回传；三层错误都认 | 02 §2.2、§3.2、03 §5、06 §2 | 2 |
| ④ | thinking block 原样回传，换模型时整组剥离；`display` 不是默认的 omitted；`max_tokens` 必发；base 用根地址 | 03 §3、§5、02 §4 | 1、3、4、16、17 |
| 全部 | 每个 tool_call 都有配对的结果消息，**中断路径也要补上** | 05 §4 | 19（agent 侧） |

### 3.3 出图与视频

| # | 检查 | 事实 | 坑 |
| --- | --- | --- | --- |
| 1 | 返回的 URL 当场下载，不存链接；下载要校验 content-type | 13 §6 | 56、78 |
| 2 | 编辑失败后的降级重生成只认「路由缺失」证据（否则二次计费） | 13 §5 | 57 |
| 3 | 单交付物端点 200 但零张图 = 失败；组图里单张失败不拖垮整次 | 13 §4.1、§6 | 84、87、90 |
| 4 | 按张计费的端点，别把像素折算的 token 塞进 token 用量；按次计费的用量元数据不为空 | 13 §7 | 83 |
| 5 | 超时与请求可能画的张数、流式首块等待相匹配 | 13 §4.1 | 82、85 |
| 6 | 异步任务：task id 提交后立刻入日志；总 deadline；轮询间的等待可以被取消；放弃的付费任务不重试 | 13 §4、14 §3 | 60 |
| 7 | 上游默认值有坑的字段要显式发：Seedream `watermark`、wan2.7 `n` 默认 4、千问 / 万相省略 `size` 落 2K 档 | 13 §4、§4.1 | 79、102 |
| 8 | 尺寸发送前按目标模型的规则（面积 / 单边 / 固定值 / 不收）校验，规则是数据而非按模型名分支 | 13 §4「自由尺寸的规则」 | 103 |

### 3.3.1 语音识别

直接按 16 §11 的 12 条清单走；对应的现象在坑 115–122。重点三条：时间码从哪来（服务端 / 切片位置 / 兜底的 `[0, duration]`）、
说话人分离所选路线是否真的会给编号、403 / 404 是否按步骤区分。

### 3.4 厂商

对盘点出的每家厂商，打开 `15-vendor-index.md` 那一行，把列出的小节逐条和实现对照。

## 4. 判定与证据

每条发现都要写清三样：
- 目标代码的位置（文件:行）。
- 本库的依据（篇 §节 或 坑号）。
- 依据的证据等级（记法见 SKILL.md）。

判定时注意：
- **本库只记了【文档】的事实**，项目行为与之不同，不能直接判为错误——可能是 API 已经更新，也可能是文档本来就写错了。写成「与文档口径不一致，建议实测」，并给出最便宜的验证方法（06 §8；能用非法参数零成本探测的优先，例 13 §4.1）。
- **证据超过半年**（按日期标注算），或标了 ⚠ 的，同样按「待核实」处理。
- **本库没覆盖的厂商或字段**（15 末尾的清单），不做对错判定，只列为「未核实」。
- 发现目标项目里有本库没有、且证据可靠的事实（测试断言、实测注释、抓包记录），单独列出来，交给维护者按 SKILL.md「维护知识库」决定要不要写回本库。

**严重度**：
1. 静默错误：数据丢失、错算钱、功能悄悄失效。
2. 会响的错误：确定会 400 或崩溃的路径。
3. 宣称支持、实际缺失。
4. 结构问题：会让下一次扩展静默出错的分层问题（01 §1 的三条铁律）。

## 5. 报告模板

```markdown
# <项目> 模型支持审查（<日期>，依据 ai-agent-architecture 知识库）

## 盘点
| 族 / 厂商 | 面 | 实现位置 |

## 覆盖矩阵
| 族 / 厂商 | 请求 | 流式 | 鉴权 | 思考 | 结构化 | 工具 | 错误/usage | 出图 | 视频 |

## 发现（按严重度）
### [1-静默] <一句话>
- 位置：`path:line`
- 依据：<篇 §节 / 坑 N>【证据等级】
- 现象：<会怎样出错，给出具体输入或场景>
- 建议：<合格的样子>

## 待核实（本库证据不足或已过期）
## 项目里有、本库没有的事实（供回写本库）
```

要按发现去**修改**项目、或者**新增**支持时，改用 12 篇的配方。
