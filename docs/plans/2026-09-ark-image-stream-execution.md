# 方舟 Seedream 流式出图 · 执行清单

分支 `claude/ark-live-tests`（与套餐实测文档同一 PR）。事件形状见
`api/volcengine-ark.md` §5（2026-09-18 套餐实测）。

## 决策

1. **只在方舟自家渠道上流式。** 中转转发 Ark body 时是否透传 SSE 未知；拒收
   `stream` 的中转会让原本能出图的请求 400。中转照旧同步。
2. **能力按版本声明**：`ModelCapabilities.streamsImages` —— 5.0 lite · 4.5 · 4.0
   为真；5.0 pro（实测 400）、3.0、兜底表为假。
3. **协议对 JSON 回答照单全收**：`stream: true` 下仍回 `application/json` 时按
   同步响应解析（参数错误 400 就是这样回的）。
4. **空闲守卫按「一张图」计**：真流式的每个 chunk 是一整张图，两张之间的沉默是
   在画图，不是断线。首块与后续块都用单图的生成期限（5 分钟），首块超时算期限
   （不重试）。
5. **执行器边到边存**：流式路径每收到一张就落盘、发 `imageResult`，不再等流结束。
   已落盘的图在后续失败 / 取消时保留（已计费）。

## 切片

- [x] S1 能力 + payload + 事件解析（纯函数，带测试）
- [ ] S2 协议 `generateImageStream` + dispatcher 路由 + 守卫（loopback 服务器测试）
- [ ] S3 执行器边到边存
- [ ] S4 文档：§5 标已实现、欠账表删行、三层架构笔记
- [ ] review → 修 → 升版本 → PR
