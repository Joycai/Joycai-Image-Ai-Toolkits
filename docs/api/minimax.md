# MiniMax 协议标准

> 一家供应商、一把 key、一个 host（`api.minimaxi.com`），四条 wire：
> 2 种 chat（①/④ 兼容面）+ 1 个私有图像面（同步）+ 1 个私有视频任务面
> （v2，含管理端点）。
> 本文只写协议事实（本目录的规矩）；本项目怎么路由，见
> [`../plans/2026-08-vendor-protocol-model-refactor.md`](../plans/2026-08-vendor-protocol-model-refactor.md)。
> ①/④ 两面的兼容层砍削样本已收录于 [`landscape.md`](landscape.md) §7
> （第二、四样本），本文不重复；两条 chat 面只补最新差异，图像面（§3）与视频面
> （§4）写全貌。
>
> **来源**：`platform.minimaxi.com` 官方 API reference，2026-08-25 抓取；
> 图像面（§3）与视频面的复核为 2026-08-29 抓取；模型列表端点（§5.1）
> 为 2026-08-29 抓取。

## 0. 总览：四条 wire 一张表

| # | Surface | 协议 | 路径（相对 host） | 同/异步 | 模型 |
| --- | --- | --- | --- | --- | --- |
| C1 | chat | OpenAI 兼容 | `/v1/chat/completions` | 同步/SSE | M 系全家：`MiniMax-M3`、`MiniMax-M2.7(-highspeed)`、`MiniMax-M2.5(-highspeed)`、`MiniMax-M2.1(-highspeed)`、`MiniMax-M2` |
| C2 | chat | Anthropic 兼容 | `/anthropic/v1/messages` | 同步/SSE | **与 C1 完全相同的 8 个 id** |
| I1 | imageGen | 私有图像面 | `POST /v1/image_generation` | **仅同步** | `image-01`、`image-01-live` |
| V1 | videoJob | 私有 v2 任务面 | `POST /v2/video_generation` + 查询/列表/取消删除（§4） | **仅异步** | `MiniMax-H3`（文档仅此一个；无 Hailuo 旧拼写） |

**路径版本不齐**：chat 与图像在 `/v1`，视频独自在 `/v2`，④ 面又多一层
`/anthropic`。四条 wire 由同一个 host + 同一把 key 服务，但**没有一个公共
前缀**——从渠道存的任意一面推导另外三面是接入这家的第一件事。

认证全线 `Authorization: Bearer <API_KEY>`；C2 额外接受 `x-api-key`
（两个同时发时 Bearer 优先），且**不要求 `anthropic-version`**。

**错误信封一家三套**（对接时按端点分开解析）：

- C1：**成功和失败都带 `base_resp`**（`{status_code, status_msg}`，0=成功；
  1002 限流 / 1004 鉴权 / 1008 余额不足 / 1039 token 超限 / 2013 参数错）。
- C2：Anthropic 风格 `{type:"error", request_id, error:{type, message}}`，
  无 base_resp；429 `rate_limit_error`、529 `overloaded_error`（可重试）、
  413 `request_too_large`（body >64 MB）。
- I1：**同 C1**——`base_resp.status_code`，成功也带（0 才是成功）。
  1026 是「内容审核」这条面独有的码。
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

## 3. I1 — 图像面（`/v1/image_generation`，仅同步）

**这不是 OpenAI Images API**，尽管挂在 `/v1` 下：body 是自己的、结果在
`data.image_urls` 而非 `data[].url`、错误走 `base_resp`。同一个端点服务
文生图与「参考图」两种模式，差别只有 `subject_reference` 一个字段。

### 3.1 请求

| 字段 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `model` | 是 | — | `image-01` / `image-01-live` |
| `prompt` | 是 | — | ≤1500 字符 |
| `aspect_ratio` | 否 | `1:1` | `1:1` `16:9` `4:3` `3:2` `2:3` `3:4` `9:16` `21:9` |
| `width` / `height` | 否 | — | 512–2048 且为 8 的倍数；**仅 `image-01`**。与 `aspect_ratio` 是同一件事的两种拼法 |
| `n` | 否 | 1 | 1–9 |
| `response_format` | 否 | `url` | `url` / `base64`；**URL 24 小时过期** |
| `seed` | 否 | — | 复现用 |
| `prompt_optimizer` | 否 | false | 服务端改写 prompt |
| `aigc_watermark` | 否 | false | 水印 |
| `style` | 否 | — | **仅 `image-01-live`**：`style_type`（`漫画`/`元气`/`中世纪`/`水彩`）+ `style_weight` (0, 1]，默认 0.8 |
| `subject_reference` | 否 | — | 参考图数组，见下 |

`subject_reference[]`：`{type, image_file}`。`type` **只有 `character` 一个
取值**；`image_file` 是公网 URL 或 base64 data URI，JPG/PNG ≤10 MB，文档建议
正面单人肖像。

### 3.2 这不是图生图

`subject_reference` 是**主体参考**，不是编辑：它把参考图里的**人物**带进一张
新生成的画面，端点没有任何字段表示「改这张图」。喂一张风景图要求调色会
正常返回，返回的东西与输入无关——这条 wire 上不存在「编辑」这个操作。

### 3.3 响应

```json
{
  "id": "...",
  "data": { "image_urls": ["..."] },      // 或 image_base64，取决于 response_format
  "metadata": { "success_count": 1, "failed_count": 0 },
  "base_resp": { "status_code": 0, "status_msg": "success" }
}
```

**两层失败**：`base_resp.status_code != 0` 是请求级失败；
`status_code == 0` 但 `success_count == 0` 是**逐图**失败（通常是审核）。
只看前者，后者的症状就只是「结果为空」。

**`success_count` / `failed_count` 实际是字符串**（样例里是 `"0"` / `"3"`），
尽管字段描述写的是整数。按数字类型判会静默永不命中 —— 两种拼法都要认。

## 4. V1 — 视频任务面（v2，仅异步）

### 4.1 创建：`POST /v2/video_generation`

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `model` | 是 | `MiniMax-H3` |
| `content[]` | 是 | 多模态数组，**至少一个 `text` 项**（≤7000 字符）；媒体项见下 |
| `resolution` | **是** | `768P` / `2K` |
| `duration` | **是** | 4–15 秒 |
| `ratio` | 否 | `adaptive`（默认）/ `21:9` / `16:9` / `4:3` / `1:1` / `3:4` / `9:16`。**纯文本请求必须显式给值**——`adaptive` 的含义是「跟随输入素材」，没有素材就没有可跟随的对象 |
| `callback_url` | 否 | HTTPS webhook；注册时 MiniMax 先发 `challenge`，需 **3 秒内原样回显** |
| `aigc_watermark` | 否 | 默认 false |

**`content[]` 项的形状**（这里最容易写错，且写错不报错）：

```json
{"type": "text",      "text": "..."}
{"type": "image_url", "image_url": {"url": "..."}, "role": "first_frame"}
{"type": "video_url", "video_url": {"url": "..."}, "role": "reference_video"}
{"type": "audio_url", "audio_url": {"url": "..."}, "role": "reference_audio"}
```

一句话：**`role` 是 `type` 的兄弟键，但 URL 是嵌在同名对象里的**。两半只有一半是
扁平的，很容易连带把 URL 也写成扁平的 `url` —— 那样上游不会报错，会当成没带素材
正常出片并计费，日志里看不出是 body 的问题。

`url` 三种形式：公网 URL / `mm_file://{file_id}` / `data:image/…;base64,…`。
`role` 取值：`first_frame` / `last_frame` / `reference_image` /
`reference_video` / `reference_audio` —— 首帧/尾帧/参考素材没有独立字段，全靠这个
标注区分。

体积限制：请求总量 ≤64 MB；单图 ≤30 MB（256–5760 px）；视频 ≤50 MB（2–15 s）；
音频 ≤15 MB（2–15 s）。

**图像模式与参考模式互斥**：`first_frame`/`last_frame` 属于前者，
`reference_image`/`reference_video`/`reference_audio` 属于后者，同时给会被拒。
两者只由 `role` 区分，body 结构本身拦不住——这条得客户端自己保证。

成功响应**极简**：`{"task_id": "424010985738629"}` —— 无 base_resp、无状态字段。

### 4.2 查询：`GET /v2/query/video_generation/{task_id}`

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

### 4.3 列表：`GET /v2/query/video_generation`

分页 `page_num`（1 起）/ `page_size`；过滤 `filter.status` /
`filter.task_ids`（可多值）/ `filter.model` / `filter.task_type`。
响应 `{items: [task…], total}`，total 也只数最近 7 天。

### 4.4 取消/删除：`DELETE /v2/video_generation/{task_id}`

一个端点按状态自动分派，响应 `{task_id, action, status}`
（action = `cancelled` | `deleted`）：

| 任务状态 | 行为 |
| --- | --- |
| `queued` | 取消（**不扣费**） |
| `succeeded` / `failed` | 删除记录 |
| `running` | **不可操作**（报错）—— 跑起来就停不下 |
| `cancelled` | 不可操作 |

## 5. 模型 × 协议矩阵

| 模型 | C1 | C2 | I1 | V1 |
| --- | --- | --- | --- | --- |
| `MiniMax-M3`（1M 上下文，唯一多模态输入） | ✅ | ✅ | — | — |
| `MiniMax-M2.x` 全家（纯文本+工具） | ✅ | ✅ | — | — |
| `image-01` / `image-01-live` | — | — | ✅ 唯一 | — |
| `MiniMax-H3` | — | — | — | ✅ 唯一 |

chat 两面模型 id **完全一致** —— 选面不改变可用模型，只改变路径、
thinking 默认值、错误信封和参数细节。

### 5.1 模型列表端点只覆盖 chat

两个 chat 面各自带一个列表端点，**没有第三个**：

| 端点 | 协议 | 返回 |
| --- | --- | --- |
| `GET /v1/models` | OpenAI 兼容 | M 系 chat 模型（官方示例：`MiniMax-M3`、`MiniMax-M2.7`、`MiniMax-M2.5`） |
| `GET /anthropic/v1/models` | Anthropic 兼容（带 `limit` / `after_id` / `before_id` 分页） | 同上 |

`image-01` / `image-01-live` / `MiniMax-H3` **不在里面，也不可能在里面**：
兼容层枚举的是兼容层，而这三个模型只存在于私有的 `/v1/image_generation`
与 `/v2/video_generation` 上，那两条 wire 在 OpenAI/Anthropic 的模型对象里
没有对应词汇。

结论：**任何"拉取模型列表"的流程都必须自带这三个 id**。不带的话，接了
图像面和视频面的客户端在 UI 上仍然是一家纯 chat 供应商——按钮能按、请求
成功、列表返回、就是没有那两条 wire 的模型，而且不会有任何报错说明原因。

`/v2` 上没有 `models`：把渠道地址填成视频文档里的 `…/v2`，模型列表和 chat
一起 404，图像和视频却正常——因为那两条自己推导 base。

## 6. 对接注意事项（实现 checklist）

1. 错误解析按端点分三套（§0）：C1/I1 看 `base_resp.status_code`（成功也有，
   0 才是成功）；C2/V1 看 HTTP 状态码 + error 对象，且两者的 type 词表不同。
   I1 还多一层 `metadata.success_count`（§3.3）。
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
9. I1 的 `subject_reference` 是主体参考不是编辑（§3.2）；把它接到「图生图」
   按钮上，用户会得到一张与输入无关的图而没有任何报错。
10. V1 的 `resolution` / `duration` 必填、`ratio` 在纯文本时必须显式，
    三者都没有服务端默认——客户端必须各有一个缺省值。
11. 四条 wire 没有公共前缀（§0）：`/v1`、`/anthropic/v1`、`/v2`。
    渠道只存一个地址，另外三条得推导出来。**chat 面自己也要推导**：用户照
    视频文档填 `…/v2` 是常见操作，这时只有不推导 base 的通用协议会 404。
12. 模型列表端点只枚举 chat（§5.1）——图像和视频的模型必须由客户端自带
    目录补进去，否则用户只能背 id 手输。

## 7. 本项目的接法

| wire | 实现 | 备注 |
| --- | --- | --- |
| C1 | 通用 ① 协议 + `Vendors.minimax` | 无专属代码 |
| C2 | 通用 ④ 协议 + `Vendors.minimaxAnthropic` | `ThinkingDialect.adaptive` |
| I1 | `MiniMaxImagesProtocol` | `WireProtocol.minimaxImages` |
| V1 | `MiniMaxVideoProtocol` | `WireProtocol.minimaxVideo` |
| 列表（§5.1） | 通用 ①/④ 发现协议 + `VendorProfile.unlistedModels` | 实测面 + 自带目录合并 |

两个 vendor id **都**声明 I1 和 V1：chat 走哪一面是渠道的选择，图像和视频
端点是哪个则不是。base 推导在 `minimax_payload.dart`（`minimaxOpenAIBase` /
`minimaxAnthropicBase` / `minimaxV2Base`，幂等、只看路径），四条 wire 全部
经过它——包括 chat 面自己（`protocolBases`），所以渠道存哪一面都能打全。

§5.1 那三个模型由 `VendorProfile.unlistedModels` 声明，`mergeUnlistedModels`
追加在实测列表**之后**并按 id 去重（大小写不敏感——转发站可能给小写）。
追加而非替换：Midjourney 那种"根本没有列表端点"的才用内置目录整体顶替。

取消（§4.4）接在 `CancellableJobProtocol` 上，是全项目唯一实现：先查状态、
**只对 `queued` 发 DELETE**。`succeeded`/`failed` 上的 DELETE 是「删记录」，
对一个刚跑完的任务发出去就是把用户付过钱的视频删了——而任务完全可能在最后
一次轮询和这次调用之间跑完。

**未实测**（没有 key）：I1 的 `subject_reference` 能否给多于 1 张（文档只说
`type: character`，没给数量上限，本项目按 1 张接）；V1 的 `2K` 档实际出的
分辨率；`mm_file://` 引用形式。
