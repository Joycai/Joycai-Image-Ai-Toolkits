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
| 3 | 万相 usage 的 `input_tokens`/`output_tokens` 被当 token 计费 | `protocols/dashscope_images_protocol.dart` | 原始 usage 放私有键；token 计数不再出现；测试 | ⬜ |
| 4 | 上下文压缩继承联网搜索 | `assistant/assistant_context_window.dart`、配置解析 | 压缩请求不带服务端工具；测试 | ⬜ |

## 第二批 · 协议行为

| 片 | 问题 | 验收 | 状态 |
|---|---|---|---|
| 5 | `requestStream` 不续跑 `pause_turn` | 流式遇 pause_turn 续跑，与非流式同答；测试 | ⬜ |
| 6 | MiniMax ① 思考控制方言 | 先实测，再声明方言 | ⬜ |
| 7 | 结束原因 / 空回复：Gemini 未知 finishReason、百炼私有面空内容、① `sensitive` | 三处都抛错；测试 | ⬜ |

## 第三批 · 视频与计费

| 片 | 问题 | 验收 | 状态 |
|---|---|---|---|
| 8 | 视频放弃 / 下载失败后无「继续轮询 / 重新下载」入口 | 保留 operation 可续跑，不重新付费 | ⬜ |
| 9 | 视频计费不读上游回报的时长 | 有上游时长优先用之 | ⬜ |
| 10 | 按次计费不乘张数 | `request_count` = 张数 | ⬜ |

## 第四批 · 发送前校验

| 片 | 问题 | 验收 | 状态 |
|---|---|---|---|
| 11 | 各出图路由发送前不按模型规则校验尺寸 | R1 / R3 / R4 / R7 同百炼一样 normalize | ⬜ |
| 12 | ④ base 需自带 `/v1` | 自动剥掉尾部 `/messages`，缺 `/v1` 时补 | ⬜ |
| 13 | Anthropic 思考拒收判定过宽 | 收窄到明确的 thinking 字段错误；测试 | ⬜ |

## 第五批 · 结构

| 片 | 问题 | 验收 | 状态 |
|---|---|---|---|
| 14 | Veo 参数写死在面板 | 改为模型声明的数据 | ⬜ |
| 15 | `canRunVideoJob` 与 `startLongRunning` 百炼分支不一致 | 同一判断 | ⬜ |
| 16 | 连接测试手抄配置漏字段 | 走统一配置 | ⬜ |
| 17 | dispatcher 兜底 `_ => _openaiChat` 静默落 ① | 显式列举 | ⬜ |

## 施工记录

（每片完成后追加：偏离计划的地方与理由。）

- **片 1**：判定抽成顶层 `imageTaskFailure`（`@visibleForTesting`），执行器里的流式与非流式两路都把文字攒进同一个 buffer；取消的任务在判定前就已返回，不受影响。
- **片 2**：启发式收进 `StreamedImageTextGate`：可疑块不再丢弃而是从此「扣住」，流末只补发抽图后剩下、且此前没显示过的部分（按公共前缀算，data URI 跨块断开时也不重复）。去掉了「剩余 < 原长 10% 就不补」的规则——它会吞掉内联图之后的文字。`thinkFilter.flush()` 的尾巴以前若像 base64 就既不显示也不参与抽图，现在一样进闸门。
