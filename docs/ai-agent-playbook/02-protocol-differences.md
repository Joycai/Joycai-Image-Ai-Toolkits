# 02 · 三家协议差异对照

> 本篇解决的问题：把 OpenAI Chat Completions（①）、Google GenAI generateContent（③）、Anthropic Messages（④）三族的 wire 差异一次性列全——消息容器、角色、工具、流式机制、鉴权、URL 约定——并给出适配器里必须做的结构性修补。
> 不读会踩的坑：Anthropic 的交替律 400、连续 tool 消息拆开发送被拒、Gemini 把 SSE chunk 当 delta 拼接导致内容重复、baseURL 归一化"修复对称"后中继路由全断、Gemini key 走查询串泄进代理日志。

参考实现：simple-ai-writer `src/lib/ai/openai.ts`、`gemini.ts`、`anthropic.ts`、`urls.ts`、`http.ts`；协议事实见其 `docs/api/landscape.md`。

---

## 1. 总对照表

| | ① OpenAI Chat Completions | ③ Google GenAI | ④ Anthropic Messages |
| --- | --- | --- | --- |
| 端点 | `POST {base}/chat/completions` | `POST {base}/models/{id}:streamGenerateContent?alt=sse`（模型名在 URL！） | `POST {root}/v1/messages` |
| 鉴权 | `Authorization: Bearer`（无 key 时**整个头省略**） | `x-goog-api-key` 头 | `x-api-key` + `anthropic-version: 2023-06-01`（pinned） |
| 历史容器 | `messages[]` | `contents[]` | `messages[]` |
| 模型侧角色 | `assistant` | **`model`** | `assistant` |
| system | `messages[0].role="system"` | 顶层 `systemInstruction:{parts:[{text}]}` | 顶层 `system` 字符串（消息数组内**无** system 角色） |
| 文本载体 | `content` 字符串或 part 数组 | `parts[].text` | `content` 字符串或 block 数组 |
| 图片 | `{type:"image_url", image_url:{url: dataURL}}` | `{inlineData:{mimeType,data}}` | `{type:"image", source:{type:"base64",media_type,data}}` |
| 工具定义 | `tools[].function.{name,description,parameters}`（嵌套） | `tools[0].functionDeclarations[]`（同名字段） | `tools[].{name,description,input_schema}`（唯一不叫 parameters） |
| 模型发起调用 | `assistant.tool_calls[]`（带 id；arguments 是 **JSON 字符串**） | `parts[].functionCall`（**无 id**；args 是**已解析对象**） | block `type:"tool_use"`（带 id；input 是对象） |
| 结果回传 | `role:"tool"` + `tool_call_id` | `role:"user"` 的 `parts[].functionResponse`，**靠函数名匹配** | `role:"user"` 的 `tool_result` block + `tool_use_id` |
| tool_choice | `"auto"/"none"/"required"/{type:"function",function:{name}}` | `toolConfig.functionCallingConfig.mode: AUTO/ANY/NONE` (+`allowedFunctionNames`) | `{type:"auto"/"any"/"tool"(+name)/"none"}` |
| 流式机制 | SSE 匿名 chunk，客户端拼 delta，`data: [DONE]` 收尾 | SSE，**每个 chunk 是完整响应对象**（parts 直接追加，不是 delta） | SSE **类型化事件** `message_start`→`content_block_*`→`message_delta`→`message_stop` |
| 结束原因 | `finish_reason: stop/length/tool_calls/content_filter` | `finishReason: STOP/MAX_TOKENS/SAFETY/RECITATION/...` | `stop_reason: end_turn/tool_use/max_tokens/refusal/pause_turn` |
| 输出上限 | `max_tokens`→`max_completion_tokens`（选填） | `generationConfig.maxOutputTokens`（选填） | `max_tokens` **必填、无服务端默认** |
| usage | `usage.prompt_tokens/completion_tokens`（**须开 `stream_options:{include_usage:true}`**，随末 chunk 到） | 每个 chunk 都带 `usageMetadata.promptTokenCount/candidatesTokenCount/thoughtsTokenCount` | 分两次：`message_start` 给 input，`message_delta` 给 output；**三桶不重叠** |
| 缓存计数 | `prompt_tokens_details.cached_tokens`，**input 的子集** | `cachedContentTokenCount`，子集 | `cache_read/creation_input_tokens` 与 `input_tokens` **互不重叠，要相加** |

## 2. 消息转换的结构性修补

内部消息是 OpenAI 形状（见第 1 篇），转换到 ③④ 时不是逐字段改名，而是要做**结构性修补**——这是适配器里真正的活。

### 2.1 Anthropic（最严格）

参考实现：simple-ai-writer `src/lib/ai/anthropic.ts` 的 `convertToAnthropicMessages` / `extractSystem`。

规则与修补，逐条：

1. **交替律**：首条必须是 `user`，相邻消息必须交替角色。OpenAI 形状允许连续同角色（agent 循环会自然产生 assistant+assistant）。转换器必须做三件事：
   - 丢弃开头的 assistant 消息；
   - 合并同角色相邻消息；
   - **把连续 tool 消息合并成一条 user 消息**——Anthropic 要求一轮的所有 `tool_result` 一起到达，拆开发既违反协议又破坏交替律。
2. **system hoist**：消息数组内没有 system 角色，全部 system 消息 hoist 到顶层 `system` 字段（多条用 `\n\n` join）。陷阱：内容若是 `ContentPart[]`，必须先用 `textOf` 拍平成字符串，否则序列化成 `[object Object]`。
3. **工具轮 assistant 消息的 content 顺序**：`[...thinkingBlocks, ...tool_use blocks]`——thinking 在前且原样（顺序即 400 红线，详见第 3 篇回传义务）。
4. **labelAuthorText**：tool_result 和作者（用户）的话都住在 `role:"user"` 里，合并可能产生 `[tool_result, "continue"]` 这种消息——作者的话被装进了模型当作工具输出读的信封。实测事故：作者一上午敲的三次重试（continue/retry/重试）混进 `read_file` 结果，被后续 39 轮反复重发，模型把它读成"用户要我一直继续"的常设指令。修法：合并进带 tool_result 的消息的第一条文本前加 【…】 标签，标明这是作者发言，使其可归因。
5. **tool_use 的 `name` 兜底链**：`tc.function.name || toolCallIdToName.get(tc.id) || "unknown_function"`——id→name 表预先扫全量 messages 建好。历史里的 tool_calls 可能来自持久化或另一族转换，name 缺失不能让整条请求炸掉。

### 2.2 Gemini

参考实现：simple-ai-writer `src/lib/ai/gemini.ts` 的 `convertToGeminiContents`。

1. `assistant` → `model` 角色。
2. tool 消息 → `role:"user"` 的 `functionResponse` parts。**Gemini 协议层没有调用 id**，靠预建的 id→name 表查函数名回填。推论：同名函数的并行调用，其结果对应关系在协议上**不可表达**——只能接受这个信息损失，不要试图发明私有配对机制。
3. 工具轮 assistant 若带 `_geminiModelParts`，**原样整组回传**而不重建——为保住 `thoughtSignature`（第 3 篇详述）。规则：能原样回传的历史，永远不要"理解后重建"。

## 3. 流式解析：共同骨架 + 三家差异

### 3.1 共同骨架（三族适配器共享同一 SSE 读法）

```
res.body.getReader() + TextDecoder({stream: true})
→ 按 "\n" split
→ 最后一个不完整行留到下次 read（行缓冲）
→ 流结束后再 flush 一次 buffer 尾巴
```

两条理由都来自真实事故：一个 `data:` 行可能跨两次网络 read 到达，**解析半行会静默丢 token/usage**；有的端点不发 `[DONE]`/`message_stop` 就断流，不 flush 尾巴就丢最后一段。

### 3.2 各族差异

**① OpenAI**：
- tool_calls 用 `Map<index, {id,name,args}>` 累积。**分组键是 `index` 不是 `id`——id 本身也可能分片到达**（参考实现里 `entry.id += partial.id`）。用 id 分组，流式下同轮多个交错调用会拼错。
- malformed SSE 行直接忽略，不抛错。

**③ Gemini**：
- **不是 delta！** 每个 chunk 是完整响应对象，`parts` 直接追加。按 delta 逻辑拼会重复内容。
- `functionCall` 一次给全不分片，但**没有 id**——适配器自造 `gtc_${Date.now()}_${n}` 补上，让上层的统一 tool 循环仍能用 id 关联。

**④ Anthropic**：按事件类型 switch。
- `content_block_start` 建块：**浅拷贝后整块留存，包括不认识的类型**——paused turn 要原样回话，重建会丢 `encrypted_content`（见第 5 篇）。
- `input_json_delta` 按**块索引**累积。
- `thinking_delta` 流出去展示 + 累积进块；`signature_delta` 只累积不展示。
- `message_delta` 收 stop_reason 和 output usage。
- `event:` 行无 payload，只认 `data:` 行。
- **空参数工具调用不会流任何 `input_json_delta`**：累积出的 `""` 必须转成 `"{}"`，否则 agent 循环拿到一个解析不了的调用。

## 4. baseURL 的不对称归一化

参考实现：simple-ai-writer `src/lib/ai/urls.ts`（`trimBase` / `anthropicRoot` / `migrateLegacyStandard`）。

三个生态对"base URL 是什么"的约定**不同**，归一化规则因此必须不对称——这是有依据的差异，不是随意：

- **OpenAI / Gemini 生态**：base **自带版本段**（`.../v1`、`.../v1beta`），照 `OPENAI_BASE_URL` 惯例，path 直接拼。**陷阱：不要"修复"这个不对称去给 OpenAI 补 `/v1`**——它的 base 本来就以 /v1 结尾，且中继合法地路由在 /v1 之下（如 `https://relay/openai`），补了就断。
- **Anthropic 生态**：base 是**根地址**（`ANTHROPIC_BASE_URL` 惯例，官方 SDK / Claude Code / 所有第三方文档都由客户端补 `/v1/messages`）。参考实现的历史 bug：曾只拼 `/messages`，于是照第三方文档粘贴的 base 一律 404——**你的 app 的约定若是全生态里唯一不同的那个，错的是你**。修法 `anthropicRoot`：先剥尾部 `/messages` 再剥 `/v1`，接受作者会粘贴的三种形状（根 / 根+`/v1` / 完整 curl 端点 URL），统一拼 `root + "/v1" + path`。
- **Gemini**：额外剥尾部 `/models`（把模型列表 URL 粘成 base 是易犯错误）。

官方端点存**空串** base（地址是厂商常量不是设置；域名变更 = 代码编辑而非数据迁移），适配器用 `baseUrl || DEFAULT_*` 兜底。

**读取时幂等迁移**：做 official/compat 拆分这类 schema 演进时，旧行的迁移放在读取时（base 非空且非官方地址 → 打 `_compat` 标），而非一次性 DB migration——因为导入旧版导出的配置也要走同一条规则；一处规则，两条路径不会漂移。

## 5. 鉴权矩阵

```ts
// 参考实现：simple-ai-writer src/lib/ai/types.ts
export type AuthMode = "default" | "bearer" | "both";
export function authModesFor(standard: ApiStandard): AuthMode[] {
  return standard === "anthropic_compat" || standard === "gemini_compat"
    ? ["default", "bearer", "both"] : ["default"];
}
```

| 族 | 默认（官方唯一方式） | compat 可选 | 不做的及原因 |
| --- | --- | --- | --- |
| OpenAI | `Authorization: Bearer`；**无 key 时整个头省略**（Ollama/LM Studio 收到空 Bearer 会拒） | 无 | Azure `api-key` 头：URL 形状（`/openai/deployments/{d}/...?api-version=`）与模型标识都不同，一个头救不了，要做是第四族不是 compat 选项 |
| Gemini | `x-goog-api-key` | `bearer` / `both` | `?key=` 查询串**故意不实现**：key 进代理日志/报错信息 = 泄漏 |
| Anthropic | `x-api-key` + `anthropic-version: 2023-06-01`（**pinned 不追 latest**——wire 形状按它版本化）+ `anthropic-dangerous-direct-browser-access: true` | `bearer` / `both` | — |

要点：

- **Anthropic 的 bearer 必须做**：生态里 `ANTHROPIC_API_KEY→x-api-key` 与 `ANTHROPIC_AUTH_TOKEN→Bearer` 是**两套一等约定**，大量网关只认后者且文档只写自己要的那个——读错头的网关看到的是未鉴权请求，401。
- **`both` 的存在理由**：给文档啥也不说的网关两个头都发。但**只在 compat 提供**——api.anthropic.com 对携带两种凭证的请求拒绝，在官方端点上提供这个选项 = 递给作者一个只能坏事的设置。
- 存储上 `default` 存 NULL（没碰过设置的行读回来逐字节不变），且**读取时按 standard 校验**——供应商从 compat 改回 official 时残留的 `bearer` 会失效而不是照发。
- 版本头 pin 死一个日期值，不追 latest：wire 形状按版本头版本化，追 latest 等于让服务端单方面改你的解析器契约。

## 6. CORS / 浏览器直连

桌面（Tauri/Electron 原生 HTTP）与浏览器环境的差异要显式处理：

- 打包版请求走原生 HTTP 栈（参考实现：Rust reqwest 经 Tauri IPC，`src/lib/http.ts` 的 fetch 包装），**没有 CORS preflight**，`anthropic-dangerous-direct-browser-access` 在打包版是 no-op。
- 带上它是为了 dev 模式纯浏览器环境（回落全局 fetch）也能连——不带则 Anthropic 直接拒绝浏览器 origin 的请求。
- 本地 Ollama 的 Windows 打包版 403 问题：靠 http 层覆盖 `Origin` 头修复。注意这个修复位于比 provider 枚举更底层的位置，拿不到枚举值，只能按"URL 指向本机"判断——这也是"Ollama 不做成枚举值"的理由之一（L2 数据能表达的就不进代码）。

---

## 本篇检查清单

- [ ] 三族各有一份对照表意识：容器名、模型侧角色、system 位置、工具字段名、流式机制、结束原因、usage 到达方式，写适配器前先对表。
- [ ] Anthropic 转换器实现了：丢头部 assistant、同角色合并、连续 tool 消息合并成单条 user、system hoist（ContentPart 拍平）、thinking 块在 tool_use 前。
- [ ] user 信封里混入作者文本时打了可归因标签（labelAuthorText）。
- [ ] tool_use name 有三级兜底（自带 → id→name 表 → `"unknown_function"`）。
- [ ] Gemini 转换：assistant→model、functionResponse 靠 id→name 表回填函数名、`_geminiModelParts` 原样整组回传。
- [ ] SSE 解析有行缓冲（半行留存）+ 流末 flush；malformed 行忽略不抛。
- [ ] OpenAI tool_calls 按 `index` 分组累积，id 用 `+=` 拼接。
- [ ] Gemini chunk 按完整对象处理（append，不是 delta 拼接）；自造 functionCall id。
- [ ] Anthropic 块整存（含不认识的块类型）；空参数工具调用 `""` → `"{}"`。
- [ ] baseURL 归一化不对称：OpenAI/Gemini 不补 `/v1`；Anthropic 走 `anthropicRoot`（剥 `/messages`、`/v1` 再统一拼）；Gemini 剥尾部 `/models`。
- [ ] 官方端点 base 存空串，适配器兜默认常量；旧配置走读取时幂等迁移。
- [ ] OpenAI 无 key 时省略整个 Authorization 头。
- [ ] Gemini 不实现 `?key=` 查询串鉴权。
- [ ] `both` 鉴权只对 compat 开放；authMode 读取时按 standard 校验残留值。
- [ ] anthropic-version pin 死，不追 latest。
