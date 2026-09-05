# LLM 端点对照审计：问题清单与修复计划

**性质**：一次静态对照的结论 + 分片实施计划。
**依据**：另一项目（simple-ai-writer）2026-09-05 导出的《LLM 端点对接与测试全书》——九台真实端点（New API / MiniMax / DashScope / OrcaRouter）的实测记录——逐条对到本仓 `lib/services/llm/`。
**方法**：只读代码、只读文档，**没有打过任何真实 API**。凡标「需实测」的条目，结论要等一次真实请求；其余条目是两份文档一致、代码与之相悖的确定项。
**排序依据**：借用那份文档的第一条经验——先问「失败会不会响」。会 400 的可以晚修；不报错、只多收钱或只少功能的必须先修。

---

## 0. 一页总览

| # | 问题 | 失败形态 | 位置 | 优先级 | 片 |
|---|---|---|---|---|---|
| 1 | wan2.7 图片不发 `n`，上游默认 4 张 | **静默四倍计费**，落 4 个文件 | `dashscope_payload.dart:137` | P0 | 1 |
| 2 | wan2.7 body 把 `messages` 放顶层，两份文档都说是 `input.messages` | 若拒收是 400（会响）；若接受则无害 —— **需实测** | `dashscope_payload.dart:143` | P0 | 1 |
| 3 | qwen-image 不发 `size` 出 2048²，按 2K 双倍计费；改图同样放大到 2K | **静默双倍计费** | `model_capabilities.dart` `_dashscopeQwenImage` | P0 | 1 |
| 4 | Anthropic 官方通道 thinking 固定 `{type:enabled,budget_tokens}`；4.7+ 直接 400；新代默认 `display:omitted` 拿不到思考文本但照计费 | 400（会响）+ 静默计费 | `vendors.dart` `anthropicRest` / `newApiAnthropic`、`anthropicThinkingRequest` | P0 | 4 |
| 5 | Gemini 请求 snake_case（`inline_data`/`mime_type`/`system_instruction`），New API ③ 面只认 camelCase | **图片、system 静默丢弃**，响应 200 | `gemini_payload.dart:273,324,357` | P0 | 2 |
| 6 | 生成图落盘一律 `.png`，不嗅字节 | 中转 `mimeType` 说谎 → `.png` 里是 JPEG | `task_executors.dart:126` | P0 | 3 |
| 7 | ④ `pause_turn` 翻成 `stop`；`server_tool_use` / `web_search_tool_result` 块回传时被丢 | **服务端搜索 turn 静默截断**，续跑不可能 | `anthropic_chat_protocol.dart:533`、`buildAnthropicHistory` | P0 | 5 |
| 8 | `imageConfig.imageSize` 对没有该参数的 gemini-2.5-flash-image 也发（默认 `1K`，无 `not_set`） | 可能 400 或被忽略 | `model_capabilities.dart` `_geminiImage` | P1 | 6 |
| 9 | wan2.7 收到 `prompt_extend`；对方文档说 2.7 不支持，本仓文档只说 `negative_prompt` 不支持 | 400 或忽略 —— **需实测** | `_dashscopeWanImage` | P1 | 1 |
| 10 | Images 编辑恒用 `image[]`；旧端点只认单数 `image` | 400 | `openai_images_protocol.dart:79` | P1 | 8 |
| 11 | DeepSeek 关闭思考发 `reasoning_effort:"none"`；DeepSeek 的关闭是顶层 `thinking:{type:"disabled"}` | **思考照常、照常计费、无报错** | `deepseek` vendor 无方言字段 | P1 | 9 |
| 12 | Chat 路由生图回包缺三种形状：裸 base64 当 content、裸 URL 当 content、`image_b64_json`；不按值去重 | 有图当无图；或一图三份 | `openai_chat_protocol.dart:447-512, 958` | P1 | 7 |
| 13 | Chat 路由无附件时 `content` 发字符串；中转翻 images 时 400 | 400 | `openai_chat_protocol.dart:1032` | P1 | 7 |
| 14 | Gemini usage 只读 `candidatesTokenCount`，`thoughtsTokenCount` 未加 | **少记最贵的那部分输出** | `llm_service.dart:470` | P1 | 10 |
| 15 | Gemini `finishReason` 不进 metadata；`finish_reason=='length'` 截断判据对 ③ 永远失效；`MISSING_THOUGHT_SIGNATURE` 等只打 INFO | 截断当完整；签名丢失当正常短回复 | `gemini_payload.dart:184-213` | P1 | 10 |
| 16 | 连接探测把 402 余额闸读成「连通」 | 误报 | `channel_probe_service.dart` `_completionProbe` | P2 | 11 |
| 17 | Gemini `thought:true` 的 text part 直接进正文 | 思考混进交付物（目前不发 `includeThoughts`，仅中转可能触发） | `gemini_payload.dart:218` | P2 | 12 |
| 18 | 流式路径零 chunk 静默成功（同步路径同情况会抛） | HTML-200 当空回复 | `openai_chat_protocol.dart` stream loop | P2 | 12 |
| 19 | `web_search_tool_result_error`（content 是对象、带 `error_code`）未识别 | 当 0 条结果 | `parseAnthropicContent` | P2 | 12 |

**不在范围内**（那份文档有、本仓没有对应功能，不为对齐而加）：结构化输出阶梯（`response_format` / `json_schema`）、强制 `tool_choice` 与失败降级、② Responses 族、ComfyUI 路由、`enable_search` / PDF `file` 块。本仓的 agent 只用 `tool_choice: auto` 且靠 prompt 约束 JSON，这些手段目前没有调用方。

---

## 1. 分片计划

十二片，按优先级分三批。每片列**改什么 / 动哪些文件 / 怎么验收 / 风险**。验收分三层沿用那份文档的结构：L1 单元测试断言「我们发了什么」，L2 实机断言「对面怎么理解」（拿到 key 时手动跑一次，修前修后各一次），L3 把花钱换来的事实回填到 `docs/api/`。

### 第一批 · P0（静默计费 / 静默失效）

#### 片 1 · DashScope 图片方言收口（#1 #2 #3 #9）— ◐ 2026-09-05 第 1/3/4a 条 L1 已落；第 2 条与 `prompt_extend` 待 L2

**改什么**

1. ✅ `buildDashScopeImagePayload` 的 `parameters` 永远带 `n: 1`（两种 shape）。qwen-image-edit 基础版只收 1、其余 1–6、wan 1–4，`n: 1` 人人都收；原「1 是所有端点默认」的注释已删，它与本仓 `docs/api/qianwen-bailian.md` §4.1/§8 自相矛盾。`parameters` 块因此永远存在。
2. **先 L2 再改 #2**：用一条 wan2.7-image 请求分别发顶层 `messages` 与 `input.messages`，看哪种 200。若 `input.messages` 通而顶层不通（两份文档都这么说），`ImageRequestShape.dashscopeWan` 改成同 qwen 的三段式，只保留「text 在前 / image 在前」与 `type:"image"` 的差别；测试 `wan puts messages at the top level` 反转。若两种都通，只补文档不改代码。
3. ✅ qwen 方言永远发 `size`，默认 1K 面积。`not_set` 保留为选项值（UI 标签仍是「自动」），但语义从「不发」改为「方言默认」：文生图 `1024*1024`；改图从第一张输入图读宽高（`ImageCompressor.dimensionsOf`，只读文件头不解码），按其比例在 1K 面积内重算——短边先取 16 的倍数、长边由短边推导再取 16 的倍数、面积超 1024² 则长边回退一步、比例夹在 1:8–8:1（`dashscopeQwenDefaultSize`）。**发现一条计划没写的例外**：基础版 `qwen-image-edit` 没有 `size`（本仓文档 §4.1 第 5 条，发了 400），所以新增 Layer 3 表 `_dashscopeQwenImageEdit`（不声明 `imageSize`），协议经 `dashscopeModelTakesSize` 读「模型是否声明尺寸控件」决定发不发；`-max` / `-plus` 及其日期版仍走共享表。
4. ◐ wan 方言：`imageSize` 的 `not_set` 现在发 `"1K"`（上游默认 2K 是双倍价）✅。`prompt_extend` 是否对 wan2.7 发，等 L2 结论：发一次带 `prompt_extend:false` 的 wan2.7 请求，400 就把 `_dashscopePromptExtend` 从 `_dashscopeWanImage` 摘掉，被忽略就保留并在文档记一笔。

**文件**：`protocols/dashscope_payload.dart`、`protocols/dashscope_images_protocol.dart`、`protocols/dashscope_images_async_protocol.dart`（两者读输入图尺寸、传 `sendsSize`，且 data URL 的 mime 走片 3 的 `resolveImageMime`）、`model_capabilities.dart`、`image_compression.dart`（`dimensionsOf`）、`test/dashscope_payload_test.dart`、`docs/api/qianwen-bailian.md` §8。

**验收**
- L1：`n` 在两种 shape 上恒为 1；qwen 无 `imageSize` 选项时 `size` 仍为 `1024*1024`；改图给一张 768×1376 的输入图，`size` 落在 1K 面积、比例误差 < 1 个 16 步、两边被 16 整除；wan 默认 `size: "1K"`；`prompt_extend` 未设不发。
- L2：qwen-image-3.0-pro 与 wan2.7-image-pro 各一张，断言回包张数 == 1、`usage.output_image_type == qima_output_1k`（qwen）、字节尺寸 == 请求尺寸。拒绝用例免费：发 `size:"1K"` 给 qwen 应 400 `InvalidParameter`。
- L3：回填 `docs/api/qianwen-bailian.md` §4.1（wan shape 定论、prompt_extend 定论），并把「省略 size 按 2K 计费」写进 §8 计费默认值那条。

**风险**：改图按输入比例重算会让 qwen 不再「跟随输入」而是「跟随输入的比例、1K 面积」——那份文档的结论是这个端点上不存在不花双倍钱的跟随写法。UI 侧 `not_set` 仍显示为「自动」，没有加说明文案；要说明的话改 `model_selection_section.dart` 的 `_optionLabel`，按 `paramKey == 'imageSize'` 且模型是 DashScope 图片族时给「自动（1K）」一类标签，属 UI 层，本片未动。

#### 片 2 · Gemini 请求改 camelCase（#5）— ✅ 2026-09-05 L1 已落，L2 待 key

**改什么**：`prepareGooglePayload` 的 `inline_data`→`inlineData`、`mime_type`→`mimeType`、`system_instruction`→`systemInstruction`。响应侧 `parseGoogleChunks` 已两种都读，不动。Veo 的 `bytesBase64Encoded` 是另一套（AI Studio 实测形状），不碰。

**文件**：`protocols/gemini_payload.dart`、`test/image_relay_compat_test.dart`（新增两条：三个键的 camelCase 断言 + 遍历全 payload 断言无下划线结构键，`parameters` / `args` / `response` / `safetySettings` 下的调用方 JSON 不在遍历范围内）、`docs/architecture/llm-three-layer.md`（共享机制一节补一条）。

**验收**
- L1：payload 里不出现任何 snake_case 键（用一条遍历断言而不是逐键，防止下一个新字段又写回 snake）。
- L2：在 `newApiGemini` 通道上发一张 16×16 纯色图问「什么颜色」，答对即通；官方 `*.googleapis.com` 通道同一请求仍通。

**风险**：极低。Google 自家 proto3 JSON 两种都收，中继只收 camelCase，改后是严格更宽的集合。

#### 片 3 · 生成图按字节定 mime（#6）— ✅ 2026-09-05 L1 已落，L2 待 key

**改什么**：新增 `core/image_magic.dart`：`imageMimeFromBytes(Uint8List)`（PNG / JPEG / WEBP / GIF / BMP 魔数，其余 null）、`imageExtensionFromBytes`（落盘扩展名，嗅不出退 `.png`）、`resolveImageMime`（声明与字节不符以字节为准）。`task_executors.dart` 的生成图落盘改用 `imageExtensionFromBytes`；`ImageCompressor.readForApi` 经 `resolveImageMime` 定 `mimeType`——这是同一条铁律的输入侧，④ 校验字节与 `media_type` 一致。图片下载任务（`_executeImageDownloadTask`）是把网络流直接 pipe 进文件、按 URL 取扩展名，不是 LLM 生成产物，**未改**；要接入得先缓冲再写。

**文件**：`core/image_magic.dart`（新）、`image_compression.dart`、`task_executors.dart`、`task_queue_service.dart`（import）、`test/image_magic_test.dart`（新）、`test/image_compression_test.dart`、`docs/architecture/llm-three-layer.md`。

**验收**
- L1：四种魔数各一条 + 一条非图片字节返回 null；声明 `image/png` 而字节是 JPEG 的附件，`readForApi` 报 `image/jpeg`。
- L2：在中转的 `[R]gemini-3.1-flash-image-preview` 或任何 New API ③ 通道出一张图，落盘扩展名与 `file` 命令一致。

**风险**：已存在的 `.png` 文件名不追溯改名。

#### 片 4 · Anthropic thinking 方言按模型、可降级（#4）

**背景**：`ThinkingDialect` 挂在 vendor 上，同一通道的 Claude 4.5 与 Claude 5 无法分别处理；而在中转上模型名是自由文本，代次从名字猜不可靠（`docs/api/reasoning.md` §1.8）。那份文档给的可移植做法是「默认不发，或发了失败再降级」。

**改什么**

1. `ThinkingDialect` 新增 `anthropicAdaptive`：发 `{type:"adaptive", display:"summarized"}` + `output_config: {effort}`，`effort` 由 `ReasoningEffort` 翻译（low/medium/high/max→`max`，五档词表里 `xhigh` 本仓没有，不映射）。`anthropicBudget` 保留给旧代。
2. 方言的**解析顺序**改为：模型级覆盖（layer 3，`ModelDescriptor.anthropicThinkingDialect`，只允许在 `model_family.dart` 里按 id 规则判代次）→ vendor 默认。官方与 New API ④ 的 vendor 默认改为 `anthropicAdaptive`——它是当前代的形状，也是对方实测在 DashScope ④ 面上被接受的形状；旧代 4.5 及更早由 layer 3 规则点回 `anthropicBudget`。
3. **一次性降级**：`AnthropicChatProtocol` 收到 400 且报文含 `thinking` 字样时，换另一种方言重试一次，并把 (endpoint, model) → 方言记在进程内备忘（那份文档的 `toolChoice.ts` 备忘模式）。不是本参数的 400 不重试。
4. `budget_tokens` 必须 < `max_tokens` 且 ≥ 1024，现有逻辑已满足；`adaptive` 下不发 `budget_tokens`。
5. UI：模型编辑器的思考档位对 ④ 生效（现在五档折叠成开/关），文案说明 `max` 只在新代可用。

**文件**：`vendors/vendor_profile.dart`、`vendors/vendors.dart`、`model_family.dart` / `model_descriptor.dart`、`protocols/anthropic_chat_protocol.dart`、`test/anthropic_chat_test.dart`、`docs/architecture/llm-three-layer.md` §④ 第 5 条。

**验收**
- L1：adaptive 方言的 JSON 形状；effort 五档翻译；off 不发；budget 方言不变；400 含 `thinking` → 重试另一方言、备忘生效、第二次不再试；400 不含 `thinking` → 不重试。
- L2（阻断项，那份文档的未验清单第一条）：官方 ④ 通道上 `adaptive` 是否真的开出思考——看响应 `content` 里有无 `thinking` block 且 `thinking` 字段非空；工具轮第二次请求 200 且仍有 thinking block。**这条配置不合法时是静默关闭，不报错**，只能靠这个观察验证。
- L3：更新 `llm-three-layer.md` 的「两套词表」为三套；`docs/api/reasoning.md` 补实测日期。

**风险**：中。触及 layer 2/3 的接口与 UI。降级重试会让第一次 400 多花一次请求，但只发生一次。

#### 片 5 · `pause_turn` 与服务端工具块的原样回传（#7 #19）

**改什么**

1. `LLMMessage` 增加 `rawContentBlocks`（④ 专用，与 `rawThinkingBlocks` 同性质）：当响应含 `server_tool_use` / `web_search_tool_result` 时，整个 `content` 数组原样保存（含 `encrypted_content`）。`buildAnthropicHistory` 对带 `rawContentBlocks` 的 assistant 轮**整块回放**，不再从 text/toolCalls 重建；模型不匹配时退回今天的重建路径。
2. `anthropicFinishReason('pause_turn')` 不再映射为 `stop`，改为新值 `'pause'`，并在 metadata 保留原始 `stop_reason`（已有）。`LLMService.request` 看到 `pause` 时：把这条 assistant 消息原样追加进历史再发一次，最多 N 次（默认 3），每次记一条 INFO 日志——用户在为搜索付费。
3. MiniMax 变体（`end_turn` 停在 `*_tool_result` 上）：`parseAnthropicContent` 检测「最后一个 block 是 `web_search_tool_result` 且其后无 text」，标记 `metadata['turn_incomplete'] = true`；续跑走**纯文本回填**——把搜索结果渲染成文本当 user 消息送回（MiniMax 拒收自己发出的 `server_tool_use` 块，那份文档 §D 6.1 实测）。
4. `web_search_tool_result` 的 `content` 是对象且带 `error_code` 时，记成 `ServerToolRun` 的错误并打 WARN；`max_uses_exceeded` 不是失败。
5. 声明 `web_search_20250305` 时顺带发 `max_uses`（默认 5）：那份文档说它是「唯一的刹车」。

**文件**：`llm_types.dart`、`protocols/anthropic_chat_protocol.dart`、`llm_service.dart`、`test/anthropic_chat_test.dart`。

**验收**
- L1：含 `server_tool_use` 的响应转 history 后逐字节相等（含 `encrypted_content`）；`pause_turn` → `finish_reason: pause`；MiniMax 形状 → `turn_incomplete`；error block → WARN 不抛。
- L2（阻断项）：官方 ④ 通道开 `enableWebSearch` 问一个需要联网的问题，看是否出现 `pause_turn` 及续跑后是否 200；MiniMax ④ 通道同一问题，看 `end_turn` 停在结果块上是否被检出、纯文本回填是否让模型接着写。
- L3：`llm-three-layer.md` ④ 第 6 条补「续跑」。

**风险**：中高。是这批里唯一改 `LLMService` 请求循环的一片；`rawContentBlocks` 要随会话持久化（`toJson`/`fromJson`），并影响上下文预算的估算（`context_budget.dart` 要把它算进去）。

### 第二批 · P1（参数规范性与回包解析）

#### 片 6 · Gemini 图片参数按模型拆表（#8）

**改什么**：`_geminiSizeParam` 加 `not_set` 且作为默认；`prepareGooglePayload` 与 `_applyGeminiCompatExtensions` 对 `not_set` 不发 `imageSize`（aspectRatio 已是这个写法）。`gemini-2.5-flash-image` 在 `forModel` 里落到一张没有 `imageSize` 的表（它只有 1024px 一档）。

**验收**：L1 三条（默认不发、显式发大写 K、2.5-flash-image 表无该参数）；L2 一张 2.5-flash-image 不带 size 200，一张 3.1-flash-image `9:16`+`1K` 出 768×1376（按字节量尺寸）。

#### 片 7 · Chat 路由生图：请求恒 part 数组，回包五形状去重（#12 #13）

**改什么**
1. `_prepareChatPayload`：`target.model.capabilities.isImageGenerator` 时，无附件也发一元 `[{type:"text",text}]`。只对生图模型，普通聊天保持字符串（最小公倍数）。
2. 回包：`extractStructuredImages` 补 `message.image_b64_json`；`_processTextAndExtractImages` 补两种整段形状——`^https?://\S+$` 是链接（下载）、`≥64` 字符 + 纯 base64 字母表 + **魔数嗅得出图片格式**（片 3 的函数）才是裸 base64，短散文仍按文字。所有来源按解码后字节哈希去重。流式路径的 `_isBase64Heuristic` 压掉的文本在末尾同样走这条解码。
3. `imageUrlsInText` 的「只抓 storage.googleapis.com」保留给正文里*夹杂*的链接；整段裸链接是另一条规则。

**验收**：L1 五形状各一条 + 去重一条 + 短散文不误判一条；L2 在 New API 的 `[R]gpt-image-2` 经 chat 出一张（那份文档实测一小时内回包形状会变，跑两次）。

#### 片 8 · Images 编辑单图用 `image`（#10）

**改什么**：`OpenAIImagesProtocol` 一张输入图时字段名 `image`，两张以上 `image[]`。L1 两条。L2 gpt-image-2 官方 `/images/edits` 一张。

#### 片 9 · DeepSeek 关闭思考的方言（#11）

**改什么**：`ThinkingDialect` 扩到 ① 家族：`deepseek` vendor 声明 `openaiThinkingObject`，off 时发顶层 `thinking:{type:"disabled"}`，其它档位发顶层 `thinking:{type:"enabled"}` + `reasoning_effort`（DeepSeek 两处都收）。其余 ① vendor 保持只发 `reasoning_effort`。`chatConsumesReasoningEffort` 不变。

**验收**：L1 deepseek 通道 off 的 body 含 `thinking.type == disabled` 且不含 `reasoning_effort:"none"`；非 deepseek 通道 byte-identical。L2 DeepSeek 官方 V4 关思考后响应 `reasoning_content` 为空——**这条不报错，只能看字段**。

#### 片 10 · Gemini 结束原因与思考 token（#14 #15）

**改什么**
1. `parseGoogleChunks` 把 `finishReason` 写进 metadata：原值存 `finish_reason_raw`，并翻译成 ① 词表存 `finish_reason`（`MAX_TOKENS`→`length`、`STOP`→`stop`、安全类→`content_filter`、`MISSING_THOUGHT_SIGNATURE` / `UNEXPECTED_TOOL_CALL` / `TOO_MANY_TOOL_CALLS`→`stop` 但日志升 WARN，且 parts 为空时抛）。与 ④ 的 `anthropicFinishReason` 同一套翻译表，抽到 `protocol.dart`。
2. `LLMService._recordUsage` 输出侧：`candidatesTokenCount + thoughtsTokenCount`（缺省 0）。

**验收**：L1 翻译表穷举；usage 相加一条；`MISSING_THOUGHT_SIGNATURE` + 空 parts 抛。

### 第三批 · P2

#### 片 11 · 探测把 402 单独报失败（#16）
`_completionProbe` 对 `statusCode == 402` 返回 `unreachable`（或新增 `quotaExhausted` 状态）并原样转出 `error.message`。L1 一条。

#### 片 12 · 三条小修（#17 #18 #19 的剩余部分）
- `parseGoogleChunks`：`part['thought'] == true` 的 text 走 `reasoningPart`，不进 `textPart`。
- ① 与 ④ 的流式路径：整条流没有产出任何 chunk（无文本、无图、无工具调用、无 usage）时抛 `LLMApiException`，与同步路径「no choices」对齐；DashScope C2 同理。
- `#19` 若片 5 已含则跳过。

---

## 2. 顺序与依赖

```
片 3 (mime 嗅探)  ──→ 片 7 (裸 base64 判定要用魔数)
片 1 (DashScope)      独立；#2 #9 两条先跑 L2 再改代码
片 2 (camelCase)      独立
片 4 (④ thinking)  ──→ 片 5 (续跑要在方言稳定后测)
片 6 / 8 / 9 / 10     独立
片 11 / 12            独立
```

建议第一周：片 2、3、1（#1 #3 先落，#2 #9 等 key）；第二周：片 4、5；之后按 P1 顺序。片 2 与片 3 各不到半天，先合。

---

## 3. 需要真实 key 才能定论的清单

| 条 | 要验什么 | 怎么看 | 为什么静默 |
|---|---|---|---|
| #2 | wan2.7 顶层 `messages` vs `input.messages` | 各发一次，看状态码 | 会响（400），但不试就不知道现在这条路通不通 |
| #9 | wan2.7 收不收 `prompt_extend` | 发 `prompt_extend:false` | 可能被忽略 |
| 片 4 | 官方 ④ `adaptive` 是否真的开出思考 | 响应 `content` 有无非空 `thinking` block | **配置不合法时静默关闭** |
| 片 5 | `pause_turn` 续跑；MiniMax `end_turn` 停在结果块 | 第二次请求是否 200、模型是否接着写 | MiniMax 变体无任何字段说明 |
| 片 9 | DeepSeek 官方 `thinking:{type:disabled}` 是否关掉 | 响应 `reasoning_content` 是否为空 | 不报错 |
| 片 7 | 中转 chat 路由回包形状 | 同一请求跑两次 | 形状随渠道轮换 |

每条跑完把日期与端点写回 `docs/api/` 对应文件，未跑的留在这张表里。

---

## 4. 已对齐、不需要动的部分

对照时逐项确认过与那份文档一致，列在这里是为了下次审计不必重查：

- ①：`tool_calls` 按 `index` 分片、`id` 也分片、`content: null` 必带、`role: tool` + `tool_call_id`、reasoning 按收到的字段名回传、`<think>` 跨片、`stream_options.include_usage`、200 内 `error` 与 `base_resp` 两种信封、SSE 半行、无 key 时不发空 Bearer。
- ④：`max_tokens` 必填兜底 8192、system 提升、`tool_result` 进 user 消息、同角色合并、`input_schema`、usage 三桶相加、thinking 与 `redacted_thinking` 原样回传且只留封好的、`x-api-key` + Bearer 双发、不发采样参数、`tool_choice` 只用 `auto`、`cache_control` 断点。
- ③：`functionResponse` 按名回指、`thoughtSignature` 回传、每 chunk 当完整对象、`safetySettings` 显式、`promptFeedback.blockReason`、`responseModalities` 保留 TEXT、`imageConfig` 只在有字段时出现、`imageSize` 大写 K。
- 图片：Images API 不发 `response_format`、`size`/`quality` 未设不发、`b64_json` 与 `url` 都收、multipart 不手写 Content-Type、DashScope 24h URL 当场下载、异步轮询 3s→6s、3 次瞬时失败容错、9 分钟封顶、`DataInspectionFailed` 带 code 抛出、caller abort 立即停轮询。
- 配对硬要求：agent 取消时给剩余调用合成 cancelled 结果、悬空 `ask_user` 自修复、批内 N 个结果装同一条 user 消息。
