# 模型能力审查修复 · 执行清单（2026-09-19）

来源：2026-09-19 用 `ai-agent-architecture` skill 审查模型能力支持（不含 Sora）。
分支 `claude/model-capability-fixes`，**一片一个 commit**，commit 正文写片号；每片完成时在
本表把状态改成 ✅ 并写施工记录。每一批结束跑一次 `/code-review`，最后 bump version。

门禁：`flutter analyze` → "No issues found!"；`flutter test -x screenshots` 全绿。

## 第一批 · 静默失败（改动小）

| 片 | 问题 | 文件 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | 出图收到 0 张也算成功 | `services/tasks/task_executors.dart` | `received == 0` 抛错，带模型回复文字；测试钉住 | ✅ |
| 2 | ① 流式 base64 启发式：前缀重复 / 小块被吞 | `protocols/openai_chat_protocol.dart` | 普通长文本逐块下发且不重复；真 base64 不刷屏；测试 | ✅ |
| 3 | 万相 usage 的 `input_tokens`/`output_tokens` 被当 token 计费 | `protocols/dashscope_images_protocol.dart` | 原始 usage 放私有键；token 计数不再出现；测试 | ✅ |
| 4 | 上下文压缩继承联网搜索 | `assistant/assistant_context_window.dart`、配置解析 | 压缩请求不带服务端工具；测试 | ✅ |

## 第二批 · 协议行为

| 片 | 问题 | 验收 | 状态 |
|---|---|---|---|
| 5 | `requestStream` 不续跑 `pause_turn` | 流式遇 pause_turn 续跑，与非流式同答；测试 | ✅ |
| 6 | MiniMax ① 思考控制方言 | 先实测，再声明方言 | ✅ |
| 7 | 结束原因 / 空回复：Gemini 未知 finishReason、百炼私有面空内容、① `sensitive` | 三处都抛错；测试 | ✅ |

## 第三批 · 视频与计费

| 片 | 问题 | 验收 | 状态 |
|---|---|---|---|
| 8 | 视频放弃 / 下载失败后无「继续轮询 / 重新下载」入口 | 保留 operation 可续跑，不重新付费 | ✅ |
| 9 | 视频计费不读上游回报的时长 | 有上游时长优先用之 | ✅ |
| 10 | 按次计费不乘张数 | ~~`request_count` = 张数~~ 裁定不改计费；修误导提示 | ✅ |

## 第四批 · 发送前校验

| 片 | 问题 | 验收 | 状态 |
|---|---|---|---|
| 11 | 各出图路由发送前不按模型规则校验尺寸 | R1 / R3 / R4 / R7 同百炼一样 normalize | ✅ |
| 12 | ④ base 需自带 `/v1` | 自动剥掉尾部 `/messages`，缺 `/v1` 时补 | ✅ |
| 13 | Anthropic 思考拒收判定过宽 | 收窄到明确的 thinking 字段错误；测试 | ✅ |

## 第五批 · 结构

| 片 | 问题 | 验收 | 状态 |
|---|---|---|---|
| 14 | Veo 参数写死在面板 | 改为模型声明的数据 | ✅ |
| 15 | `canRunVideoJob` 与 `startLongRunning` 百炼分支不一致 | 同一判断 | ✅ |
| 16 | 连接测试手抄配置漏字段 | 走统一配置 | ⬜ |
| 17 | dispatcher 兜底 `_ => _openaiChat` 静默落 ① | 显式列举 | ⬜ |

## 施工记录

（每片完成后追加：偏离计划的地方与理由。）

- **片 1**：判定抽成顶层 `imageTaskFailure`（`@visibleForTesting`），执行器里的流式与非流式两路都把文字攒进同一个 buffer；取消的任务在判定前就已返回，不受影响。
- **片 2**：启发式收进 `StreamedImageTextGate`：可疑块不再丢弃而是从此「扣住」，流末只补发抽图后剩下、且此前没显示过的部分（按公共前缀算，data URI 跨块断开时也不重复）。去掉了「剩余 < 原长 10% 就不补」的规则——它会吞掉内联图之后的文字。`thinkFilter.flush()` 的尾巴以前若像 base64 就既不显示也不参与抽图，现在一样进闸门。
- **片 3**：私有键叫 `dashscope_usage`（同 `ark_usage`）。顺带：原来 `...usage` 在 `image_count` 之后展开，上游的 `image_count` 会盖掉实际落盘张数，现在以落盘张数为准。token 计费组配万相会得到「usage 缺失」警告，与方舟一致。
- **片 4**：新增请求选项 `llmNoServerToolsKey`，只在 `LLMService._resolveConfig` 一处翻成 `config.withoutServerTools()`，协议层不知道这个键。`withEndpoint` 与它共用一个 `_copy`，免得再手抄 20 个字段。方舟出图的 `webSearch` 是出图参数，不受影响。
- **片 5**：续跑放在 `requestStream` 原有的重试循环里（同 `request()` 的 `continue` 写法），每段自己攒 text / reasoning / 回传载体给 `continuationFor`。续跑段是新请求：`attempt` 与「已下发」标记归零，所以续跑段在首块之前失败仍可重试；前段已下发的块不会重放。段与段之间下发一个 `\n\n`，与 `mergeTurnParts` 的拼法一致。测试用本地 SSE 服务器跑两段 ④ 流。
- **片 6**：用户中途提供了 `MINIMAX_KEY`，实测（2026-09-19，M3）：`reasoning_effort:"none"` 静默无视仍计 34 个 reasoning token；`thinking:{type:"disabled"}` 关；`adaptive` 开；`enabled` 400。新增 `ThinkingDialect.openaiAdaptiveObject`（开关型，不发强度），编辑器给三档。事实写回 `docs/api/minimax.md` §1。
- **片 7**：③ 的「异常结束且无输出」改为整段响应末尾判一次（`geminiEmptyEndFailure`，同步与流式共用），原来按块判，流式最后一块 parts 常为空，会把已有正文的回复误判失败；集合补 `MALFORMED_RESPONSE`，出图模型的 `IMAGE_PROHIBITED_CONTENT` / `IMAGE_RECITATION` 归 `content_filter`，`OTHER`/`LANGUAGE`/`NO_IMAGE`/`IMAGE_OTHER` 无输出时失败。百炼私有面补上 ① 的空回复规则（`dashscopeEmptyReplyFailure`，同样放行 `length`/`content_filter`/`emptyReplyEndsTurnKey`）。① 的 `finish_reason` 经 `openaiFinishReason` 归一：GLM 的 `sensitive` → `content_filter`，原拼写留在 `finish_reason_raw`。GLM 的 `network_error` 没动（没有实测样本）。
- **第一批 review**（`1f437c1..bee72c8`）：无发现。**第二批 review**（`bee72c8..2b72e88`）：1 条——提示词级拦截的 `blockReason: OTHER` 被 `geminiEmptyEndFailure` 当成协议失败抛出（丢了拦截语义与用量记录），改为凡 `finish_reason == content_filter` 一律放行给服务层；已补测试。
- **片 8**：没有分「放弃」与「下载失败」两个入口，合成一个「继续原任务」（`TaskQueueService.resumeVideoJob`）：执行器本来就会对持久化的 job id 续轮询，轮询到已完成就直接下载，所以一条路径覆盖两种情况，失败或取消的视频任务只要有 job id 都能用；「重试」语义不变（提交新任务、再付费）。入口放在任务卡菜单与详情操作行，排在「重试」之前，用现有控件、未走设计稿。四语文案 `resumeVideoJob`。
- **片 9**：没做成「提交时就用上游时长」（提交时没有这个数），而是「提交按请求计、完成后按上游回报改写同一行」：提交行的 `task_id` 改为可复查的 `video:<job id>`（重启续跑也找得到），轮询 done 信封新增 `renderedSeconds`（百炼 `usage.duration`、MiniMax `usage.output_seconds` / `task.duration`，均为【文档】口径），执行器拿到后调 `LLMService.settleVideoUsage` 按规格重新匹配档位、改写单位数 / 单价 / 规格。只影响按规格计费组。Sora 按本轮范围排除；Veo、xAI 的轮询不报时长。旧版本写下的 `req_…` 行匹配 0 行，静默跳过。
- **片 10（裁定）**：核对后「按次」的含义就是每次调用计一次——计费组的设计里按张计价由「按规格 · 单位张」承担（`OutputUnit.image` 已按实际落盘张数计），Midjourney 一次任务回四张图，乘张数会把它计成四次。所以 `request_count` 不改。真正误导的是规格表：只剩「其他规格」一档时无论单位都提示「效果与按次相同」并给「改用按次」按钮，但只有单位为「条」时才成立（张 × 张数、秒 × 时长）。改为仅在 `OutputUnit.clip` 时出现。
- **片 11**：共享 `optionsWithCheckedSize`（protocol.dart），按模型声明的 `imageSize` 控件（`ParamSpec.isValid`：选项表或 `ImageSizeRules`）检查，不合法就换成控件默认值并记 WARN——与百炼 `normalize` 同一策略，只是多了日志。接在 OpenAI Images、Gemini chat（同步 + 流式）、Imagen、方舟四处；没声明尺寸控件的模型（聊天模型）原样放行。
- **片 12**：`anthropicApiBase` 在 `/messages` 与发现用的 `/models` 前统一规整：去尾部 `/messages`；末段不是版本段（`v\d+…`）就补 `/v1`。已经以版本段结尾的 base（官方 `/v1`、MiniMax `/anthropic/v1`、百炼 `/apps/anthropic/v1`）逐字节不变。地址预览走同一函数，所以编辑器里看到的就是实际请求地址。
- **片 13**：判定改为「点名 `thinking.type` / `output_config`，或字段级的 thinking 类型 / tag 报错」，并排除回放与上限类报错（`messages.`、`signature`、`thinking block`、`redacted_thinking`、`budget_tokens`、`max_tokens`）——学到的方言整个会话都生效，误翻一次就一直发错。未改「提到 effort 就不算」这条旧规则：4.7+ 拒收 `enabled` 的原文是否会顺带提 `output_config.effort` 没有实测样本，手上也没有 Anthropic key，记入欠账。
- **第三批 review**（`6a7aa71..13a375a`）：无发现。**第四批 review**（`13a375a..194fb21`）：1 条——Anthropic 文档里「tool_choice 强制调用时不能开 thinking」「开 thinking 时 temperature 只能为 1」两类 400 仍会命中字段级正则而翻方言；排除表补 `tool_choice` / `temperature` / `top_p` / `top_k` / `when thinking is enabled`，已补测试。
- **片 14**：Veo 的 `resolution` / `aspectRatio` 成为 `_veoVideo.videoParams`（按家族与按 wire 两条路都给），面板删掉固定的一对下拉框，提交只发模型声明的参数。Sora 的 `size` 由这两项推出（`resolveVideoSize`），所以 `_openaiVideo` 也声明了同一对，行为不变。MiniMax H3 原来会看到一个它不读的分辨率框，现在没有了。旧设置 `last_video_resolution` / `last_video_aspect_ratio` 在加载时迁入 Veo、Sora 两个家族的参数存储（`legacyVeoVideoParams`，不覆盖已有值）；`VeoResolution` / `VeoAspectRatio` 两个枚举与 AppState 的两个字段删除，计费的已知取值改由家族参数表覆盖。l10n 的 `videoResolution` / `videoAspectRatio` 两个键已无引用，未删。截图：模型卡默认折叠，参数格走的是 grok / 万相 / MiniMax 已在用的同一渲染路径。
- **片 15**：抽出 `_videoSubmitRoute(target)`（返回协议 + surface 或 null），`startLongRunning` 先按它提交、为 null 时才按家族报原因，`canRunVideoJob` 直接等于「它非 null」。复核发现目前唯一的百炼私有家族厂商本身就声明了 `video-synthesis`，所以原来的不一致是潜伏的，行为不变。
