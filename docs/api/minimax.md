# MiniMax 协议标准

> 一家供应商、一把 key、一个 host（`api.minimaxi.com`），三条 wire：
> 2 种 chat（①/④ 兼容面）+ 1 个私有视频任务面（v2，含管理端点）。
> 本文只写协议事实（本目录的规矩）；本项目怎么路由，见
> [`../plans/2026-08-vendor-protocol-model-refactor.md`](../plans/2026-08-vendor-protocol-model-refactor.md)。
> ①/④ 两面的兼容层砍削样本已收录于 [`landscape.md`](landscape.md) §7
> （第二、四样本），本文不重复，只补两面的最新差异与视频面全貌。
>
> **来源**：`platform.minimaxi.com` 官方 API reference，2026-08-25 抓取。

## 0. 总览：三条 wire 一张表

| # | Surface | 协议 | 路径（相对 host） | 同/异步 | 模型 |
| --- | --- | --- | --- | --- | --- |
| C1 | chat | OpenAI 兼容 | `/v1/chat/completions` | 同步/SSE | M 系全家：`MiniMax-M3`、`MiniMax-M2.7(-highspeed)`、`MiniMax-M2.5(-highspeed)`、`MiniMax-M2.1(-highspeed)`、`MiniMax-M2` |
| C2 | chat | Anthropic 兼容 | `/anthropic/v1/messages` | 同步/SSE | **与 C1 完全相同的 8 个 id** |
| V1 | videoJob | 私有 v2 任务面 | `POST /v2/video_generation` + 查询/列表/取消删除（§3） | **仅异步** | `MiniMax-H3`（文档仅此一个；无 Hailuo 旧拼写） |

认证全线 `Authorization: Bearer <API_KEY>`；C2 额外接受 `x-api-key`
（两个同时发时 Bearer 优先），且**不要求 `anthropic-version`**。

**错误信封一家三套**（对接时按端点分开解析）：

- C1：**成功和失败都带 `base_resp`**（`{status_code, status_msg}`，0=成功；
  1002 限流 / 1004 鉴权 / 1008 余额不足 / 1039 token 超限 / 2013 参数错）。
- C2：Anthropic 风格 `{type:"error", request_id, error:{type, message}}`，
  无 base_resp；429 `rate_limit_error`、529 `overloaded_error`（可重试）、
  413 `request_too_large`（body >64 MB）。
- V1：HTTP 状态码 + Anthropic 风格 error 对象，但 type 拼写自成一派
  （401 是 `authorized_error` 而非 authentication；402
  `insufficient_balance_error`；422 `unprocessable_entity_error` = 内容审核）。

## 1. C1 — OpenAI 兼容 chat

- `max_tokens` 已弃用 → `max_completion_tokens`（M3 上限 524288，其他 204800）。
- **不支持** `top_k` / `presence_penalty` / `frequency_penalty`；
  `tool_choice` 未见于文档（工具自动触发）。
- 思考控制是 `thinking: {type: "adaptive"|"disabled"}`（不是 OpenAI 的
  `reasoning_effort`），**默认 adaptive = 开**；`reasoning_split: true` 把
  思考拆到 `reasoning_content` / `reasoning_details`，否则混在 content 里。
- 多模态（仅 M3）：`image_url`（URL / base64 data URI / `mm_file://{file_id}`，
  `detail: low|default|high` 直接影响 token 量 ~600 到 15k+）、`video_url`
  （`fps` [0.2, 5]，URL/base64 ≤50 MB、Files API ≤512 MB）。
- 响应扩展：`input_sensitive` / `output_sensitive` 审查标志；usage 带
  `prompt_tokens_details.cached_tokens`。
- `service_tier: standard|priority`（priority 1.5× 计费），两面都有。

## 2. C2 — Anthropic 兼容 chat

- 与官方 ④ 的文档明列差异：无 `anthropic-version`、无 beta header；
  `tool_choice` 只有 `auto` / `none`（**没有强制档**，landscape §7 第四样本）；
  `max_tokens` 可选而非必填（M3 建议 131072，上限 524288）。
- **thinking 默认 `disabled`，开启用 `{type: "adaptive"}`** —— 与 C1 的默认
  **相反**（C1 默认开、C2 默认关），同一家两面对同一模型的开箱行为不同。
  无 `budget_tokens` 语义；M2.x 系列始终输出 thinking。
- thinking block 带 `signature`，多轮回传义务同官方 ④；SSE 事件词表与官方
  一致（`message_start` → `content_block_*` → `message_delta`，delta 含
  `thinking_delta` / `signature_delta`）。
- prompt caching：`cache_control: {type: "ephemeral"}`，usage 四桶齐全。
- 私有扩展 role：`user_system` / `group` / `sample_message_*`（标准客户端可无视）。
- 多模态（仅 M3）：`image`（`source: {type: url|base64, …}`，JPEG/PNG/GIF/WEBP
  ≤10 MB）、`video`（同 source 结构 + `fps`）。M2.x 仅文本 + 工具。

## 3. V1 — 视频任务面（v2，仅异步）

### 3.1 创建：`POST /v2/video_generation`

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `model` | 是 | `MiniMax-H3` |
| `content[]` | 是 | 多模态数组，**至少一个 `text` 项**（≤7000 字符）；媒体项 `type: image_url|video_url|audio_url`，`url` 三种形式：公网 URL / `mm_file://{file_id}` / `data:image/…;base64,…`；**首帧/尾帧/参考素材靠项上的 `role` 标注**：`first_frame` / `last_frame` / `reference_image` / `reference_video` / `reference_audio` |
| `resolution` | **是** | `768P` / `2K` |
| `duration` | **是** | 4–15 秒 |
| `ratio` | 否 | `adaptive`（默认）/ `21:9` / `16:9` / `4:3` / `1:1` / `3:4` / `9:16` |
| `callback_url` | 否 | HTTPS webhook；注册时 MiniMax 先发 `challenge`，需 **3 秒内原样回显** |
| `aigc_watermark` | 否 | 默认 false |

体积限制：请求总量 ≤64 MB；单图 ≤30 MB；视频 ≤50 MB；音频 ≤15 MB。

成功响应**极简**：`{"task_id": "424010985738629"}` —— 无 base_resp、无状态字段。

### 3.2 查询：`GET /v2/query/video_generation/{task_id}`

task_id 在**路径**里。响应包一层 `task`：

```
task: {
  id, model, status: queued|running|succeeded|failed|cancelled,
  error: {code, message},          // 仅 failed
  created_at / updated_at,         // Unix 秒
  content: { url,                  // 视频下载直链，仅 succeeded
             prompt },             // 仅 h3_context_ir 任务（modality=text）
  resolution, duration, ratio,
  usage: { total/input/output_seconds, input_image_count,
           input_audio_seconds, total/prompt/completion_tokens },
  task_type: generation|h3_context_ir|regeneration,
  modality: video|text
}
```

- **结果是直链** `task.content.url` —— v1 时代「file_id → files/retrieve
  换 URL」的二段式已废除。链接有时效（未给具体时长），及时下载转存。
- **任务记录仅保留 7 天**（单查与列表都受限）。
- 轮询间隔文档未给建议值。

### 3.3 列表：`GET /v2/query/video_generation`

分页 `page_num`（1 起）/ `page_size`；过滤 `filter.status` /
`filter.task_ids`（可多值）/ `filter.model` / `filter.task_type`。
响应 `{items: [task…], total}`，total 也只数最近 7 天。

### 3.4 取消/删除：`DELETE /v2/video_generation/{task_id}`

一个端点按状态自动分派，响应 `{task_id, action, status}`
（action = `cancelled` | `deleted`）：

| 任务状态 | 行为 |
| --- | --- |
| `queued` | 取消（**不扣费**） |
| `succeeded` / `failed` | 删除记录 |
| `running` | **不可操作**（报错）—— 跑起来就停不下 |
| `cancelled` | 不可操作 |

## 4. 模型 × 协议矩阵

| 模型 | C1 | C2 | V1 |
| --- | --- | --- | --- |
| `MiniMax-M3`（1M 上下文，唯一多模态输入） | ✅ | ✅ | — |
| `MiniMax-M2.x` 全家（纯文本+工具） | ✅ | ✅ | — |
| `MiniMax-H3` | — | — | ✅ 唯一 |

chat 两面模型 id **完全一致** —— 选面不改变可用模型，只改变路径、
thinking 默认值、错误信封和参数细节。

## 5. 对接注意事项（实现 checklist）

1. 错误解析按端点分三套（§0）：C1 看 `base_resp.status_code`（成功也有，
   0 才是成功）；C2/V1 看 HTTP 状态码 + error 对象，且两者的 type 词表不同。
2. **thinking 默认值两面相反**：C1 不发 `thinking` = 开（adaptive），
   C2 不发 = 关。跨面迁移一个模型，思考行为会静默翻转。
3. V1 的 `resolution` 与 `duration` 是**必填**，没有服务端默认 ——
   客户端必须有自己的缺省值。
4. 首帧/尾帧/参考素材不是独立字段，是 `content[]` 项上的 `role` 标注。
5. 视频结果直链有时效且任务记录 7 天即清 —— 下载要当场做；轮询超过 7 天的
   task_id 得到的不是 FAILED 而是查无此任务。
6. 取消只对 `queued` 有效，`running` 停不下来 —— 「取消任务」的 UI 语义
   要按这个降级（本地放弃 ≠ 上游停止计费）。
7. `MiniMax-M3` 与 `MiniMax-H3` 只差一个字母，一个是 chat 一个是视频 ——
   按前缀分类模型 id 时要精确到 `-H` / `-M`。
8. C1 面 `stream_options.include_usage` 是拿到流式 usage 的前提（同 OpenAI
   官方语义，这家实现了它）。
