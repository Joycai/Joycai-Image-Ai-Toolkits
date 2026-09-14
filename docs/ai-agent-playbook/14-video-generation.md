# 14 · 视频生成管线（异步任务协议：千问万相 / MiniMax / xAI / Sora / Veo）

> 本篇解决的问题：在多协议 AI 层里加一条视频生成管线。视频没有同步形态——
> 全行业一律是「提交拿 task_id → 轮询 → 结果 URL」的异步任务协议，但五家的
> 提交 body、状态词表、结果位置、保留期、取消语义各不相同。
> 不读会踩的坑：失败任务装在 HTTP 200 里被通用错误检查放行，轮询循环把
> FAILED 当 PENDING 转到天荒地老；结果直链过期后入库，图库/画廊静默腐烂；
> 过期 task_id 被当成瞬时错误无限重试；「取消」只取消了本地轮询，上游照跑
> 照计费；必填参数无服务端默认，靠"不发字段用默认"的习惯直接 400。
>
> 2026-08 增补，来源：千问平台（阿里百炼）与 MiniMax 官方文档全量核对。
> 与第 13 篇共享异步轮询循环的设计点（总 deadline、可中断 sleep、瞬时失败
> 限次、task_id 先行入日志），此处不重复，只写视频独有部分。

---

## 1. 统一形状：submit / poll 两个入口，调用方只见归一化结果

视频任务天然跨请求（提交与轮询之间隔着分钟级时间，可能跨进程存活），所以
不能学出图藏在一个同步函数里——task_id 必须暴露给调用方持久化：

```ts
submitVideoJob(conn, req): Promise<string>            // 返回不透明 task id
pollVideoJob(conn, taskId): Promise<VideoJobStatus>   // 每次轮询调一次

type VideoJobStatus =
  | { done: false; status?: string }                  // status 仅展示，永不分支
  | { done: true; videoUrl: string };                 // 失败一律抛错，不进返回值

interface VideoJobRequest {
  prompt: string;
  media?: { role: "first_frame" | "last_frame" | "reference_image"
                 | "reference_video" | "reference_audio";
            url: string }[];        // data URL 或公网 URL，adapter 转各家拼写
  resolution?: string; duration?: number; ratio?: string; audio?: boolean;
  extraBody?: Record<string, unknown>;
}
```

- **首帧/尾帧/参考素材统一用 role 标注**，不做 `firstFrameImage` 这类独立
  字段——千问（`input.media[].type`）与 MiniMax（`content[].role`）都已收敛
  到这个形状，独立字段反而要在 adapter 里拆回去。
- **失败以抛错送达，不进 `done` 变体**——轮询方对失败唯一正确的反应是停止
  并上报，把它做成返回值就会有调用方漏检。

## 2. 五家事实速查

| | 千问 wan3.0 | MiniMax v2 (H3) | xAI | OpenAI Sora | Google Veo |
| --- | --- | --- | --- | --- | --- |
| 提交 | `POST /api/v1/services/aigc/video-generation/video-synthesis` + `X-DashScope-Async: enable` | `POST /v2/video_generation` | `POST /v1/videos/generations`（JSON） | `POST /v1/videos`（**multipart**） | `:predictLongRunning` |
| 轮询 | `GET /api/v1/tasks/{id}`（图片任务共用） | `GET /v2/query/video_generation/{id}` | `GET /v1/videos/{request_id}` | `GET /v1/videos/{id}` + `/content` 下载 | operations `GET` |
| 状态词表 | `PENDING/RUNNING/SUCCEEDED/FAILED/CANCELED/UNKNOWN` | `queued/running/succeeded/failed/cancelled` | `pending/done/expired/failed` | `queued/in_progress/completed/failed` | `{done: bool}` |
| 结果位置 | `output.video_url`（顶层扁平） | `task.content.url`（直链，v1 的 file_id→retrieve 二段式已废除） | 响应内 URL | `/content` 端点流式下载 | operation response 内 URI |
| 保留期 | task_id 24h | **任务记录 7 天** | — | — | — |
| 取消 | — | `DELETE /v2/video_generation/{id}`，**仅 `queued` 可取消**（免扣费），succeeded/failed 变删除记录，running 不可操作 | — | — | — |

千问 wan3.0 提交 body：`input.prompt`（≤2 万字符，可用「图1」指代素材）+
`input.media[]{type, url}`；`parameters`：`resolution`（480P/720P/1080P，
默认 1080P）、`ratio`（adaptive/16:9/…）、`duration`（2–30s，`-1` 智能）、
**`audio` 默认 true**、`prompt_extend` 默认 true。usage 报秒数/fps/分辨率，
无 token。

MiniMax v2 提交 body：`content[]`（至少一个 text 项 ≤7000 字符，媒体项
`image_url`/`video_url`/`audio_url` + `role`）；**`resolution`（768P/2K）与
`duration`（4–15s）必填、无服务端默认**——客户端必须自带缺省值。可选
`callback_url` webhook（注册时 3 秒内回显 challenge）。创建响应极简
`{"task_id": "…"}`。usage 报秒数 + token 双口径。

## 3. 横切不变量（每家都适用，漏一条就是一类静默失败）

1. **失败装在 HTTP 200 里。** `task_status: FAILED` + 错误码嵌在 body
   （千问在 `output.code/message`，MiniMax 在 `task.error`）。通用错误信封
   检查抢不到它——轮询面**必须跳过信封检查**，由自己的状态机负责报错，
   且把结构化 code 带上（内容审核类 code 丢了会被误判成别的失败）。
2. **状态词表逐家归一化，未知状态当"仍在跑"处理有上限。** 词表各不相同且
   随时增补；未知值先当 in-progress 容忍，但要受总 deadline 罩住——否则
   一个新终态（如千问的 `UNKNOWN`、xAI 的 `expired`）会让轮询永不停止。
   已知终态（CANCELED/expired/UNKNOWN）必须显式列入"抛错"分支。
3. **过期 task_id ≠ 失败任务。** MiniMax 7 天清记录、千问 task_id 24h——
   过期后查到的是"查无此任务"，必须报成独立的明确错误（「任务已过期」），
   落进重试循环或报成 FAILED 都是误导。
4. **结果 URL 当场下载。** 直链一律短时效（千问明文 24h，MiniMax 只说
   "有时效"）；下载 GET 通常**不带** API 认证头（OSS/CDN 签名在 URL 里，
   多带无益甚至有害；Sora 的 `/content` 是例外——它是 API 端点，要带）。
   下载校验 content-type + magic bytes，规则同第 13 篇 §6。
5. **取消要分两层语义。** 本地放弃轮询 ≠ 上游停止计费。有取消端点的
   （MiniMax）作为可选能力接上：用户取消时先试上游取消（仅排队态有效），
   失败静默降级为本地放弃；没有取消端点的家，UI 文案别承诺"已取消"。
6. **计费相关的默认值显式下发。** `audio: true`（千问）、`n: 4`（wan 图片，
   见 13 篇）这类服务端默认直接乘在账单上——不吃默认，全部显式发。
7. **必填且无默认的参数是 L3 参数表的责任。** MiniMax 的 resolution/duration
   不发就 400；缺省值由模型能力表声明，adapter 只读不编。
8. **usage 两套口径并存**（按秒/按张 vs token），与第 13 篇同规则：相加
   记账，不二选一。

## 4. 与中继的关系

中继（New API 等）把百家视频收敛到 OpenAI 式 `/v1/videos`（sora、
grok-imagine、wan2.5、kling、hailuo…同一张脸）。**同一个模型 id 在官方与
中继上走不同协议**——这正是第 1 篇 §8 的「协议选择按 L2 菜单解析」：官方
供应商行的 video 槽位指向私有协议，中继行指向 openai-videos，模型 id 不变。
按 model-id 硬编码路由的实现会在其中一边坏掉。

---

## 本篇检查清单

- [ ] submit/poll 分离，task_id 暴露给调用方持久化；失败以抛错送达。
- [ ] 首帧/尾帧/参考素材用 role 标注的统一形状，adapter 内转各家拼写。
- [ ] 轮询面跳过通用错误信封检查，状态机自己报错并保留结构化 code。
- [ ] 每家状态词表显式归一化；未知状态容忍但受总 deadline 罩住；已知终态
      （含 CANCELED/expired/UNKNOWN 类）全部在抛错分支里。
- [ ] 「任务已过期/查无此任务」是独立错误，不重试、不报成 FAILED。
- [ ] 结果 URL 当场下载；认证头按端点性质（签名直链不带，API 端点带）。
- [ ] 取消分两层：可选的上游取消（仅排队态）+ 本地放弃；文案不超售。
- [ ] 计费相关默认值全部显式下发；必填无默认参数有 L3 声明的缺省。
- [ ] 同一模型 id 在官方/中继两侧路由不同，经 L2 菜单解析，无 model-id 硬编码。
