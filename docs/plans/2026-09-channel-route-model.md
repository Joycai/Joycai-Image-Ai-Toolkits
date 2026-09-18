# 渠道 × 线路 × 模型（2026-09）

> 按 `channel-route-model` 标准重组模型与渠道。设计稿：Claude Design `D1f 渠道与线路`。
> 执行清单：[`2026-09-channel-route-model-execution.md`](2026-09-channel-route-model-execution.md)。

## 0. 为什么要做

今天一条 `llm_channels` 记录 = **地址 + 渠道类型（vendor id）+ 密钥**，而 vendor id 同时编码了两件事：
「哪家平台」和「对话打头走哪个协议」。于是：

| 现象 | 今天的样子 |
|---|---|
| 一把 New API 密钥打四个协议 | 向导里选「OpenAI / OpenAI Responses / Gemini / Anthropic」四选一，要四个协议就建四个渠道、密钥存四份、同一个模型建四次 |
| MiniMax 一把密钥两个对话面 | `minimax` 与 `minimax-anthropic` 两个渠道 |
| 百炼两个预设 | 「OpenAI 兼容」「DashScope 原生」两行，两个 vendor id 只差对话打头的面 |
| OpenAI / xAI 的 Chat 与 Responses | 渠道级二选一（`openai-api-rest` / `openai-responses-rest`），模型再点单另一个 |
| 模型切协议 | 模型的「请求方式」点单可以在 vendor 菜单内切对话面，但**推理强度 / 最大输出 / 思考开关原样带过去**——一个面上的 `reasoning_effort: high` 被带到 ④ 面、一个 ④ 必发的 `max_tokens` 被带到 ① |
| 另一个面的地址 | 由 `protocolBases` 从存着的那一个地址推导，**用户改不了**；中转把某协议放在子域名上就接不了 |

已经在按线路粒度思考、只是存储没有的信号（标准 01 §3）：`VendorProfile.chatMenu`、`protocolBases`、
`thinkingByProtocol`、`serverWebSearchFaces` 全部是「按对话面」声明的；`reasoningLadder` 按解析出的面分派。

## 1. 目标形状

```
平台画像 PlatformProfile   随软件发布（lib/services/llm/vendors/platforms.dart）
   │ 由 (主线路 vendor, 主机) 推断，不存
渠道 Channel               llm_channels 一行 = 一份密钥
   └─ 线路 Route ×N         llm_channels.routes（JSON）：每个 RouteKind 至多一条，第一条为主线路
模型 Model                  llm_models 一行，id 永不因切线路改变
   ├─ active_route          当前线路（null = 跟随主线路）
   └─ route_params（JSON）  其余线路停放的参数
```

## 2. 四个决定

### 决定 1 · 线路集合：六个 `RouteKind`

| RouteKind（存储 id） | 对话 wire | 界面短名 / 全名 |
|---|---|---|
| `chat` | `openaiChat` | Chat · Chat Completions |
| `responses` | `openaiResponses` | Resp · Responses |
| `anthropic` | `anthropicChat` | Anth · Anthropic |
| `gemini` | `geminiChat` | Gemini · Gemini |
| `dashscope` | `dashscopeChat` | 百炼 · 百炼原生 |
| `midjourney` | `midjourney` | MJ · Midjourney |

- **线路 = 一个对话 wire 在某个地址上**。Chat 与 Responses 分成两条（标准 05 §2 的 Chat · Resp），
  哪怕默认路径相同——它们在同一模型上的推理挡位、输出上限字段、服务端工具都不同（`reasoningLadder`、`outputCapField`）。
- **出图 / 视频是专用接口，不是线路**（标准 01 §5）：`llm_models.wire_protocol` 对 image / video 模型保持原义（媒体点单，
  参数留在模型上）；它们的地址取主线路（与今天「取存着的那个地址」相同），不显示线路徽标，不进线路切换器。
- 每个 `RouteKind` 映射到一个 **对话 wire**；wire → 协议实现仍由 `llm_dispatcher.dart` 唯一决定（协议层不动）。

### 决定 2 · 平台画像：vendor id 退为「(平台, 线路) → 画像叶子」

`VendorProfile` 已经是数据（鉴权、思考方言、联网面、输出上限字段、媒体菜单…），所以**不改协议层、不改 vendor 表**，
在它上面加一层 `PlatformProfile`：

| 平台 | 主机匹配 | 提供的线路（默认路径 → vendor） |
|---|---|---|
| `openai` | `api.openai.com` | chat `/v1` → `openai-api-rest` · responses `/v1` → `openai-responses-rest` |
| `anthropic` | `api.anthropic.com` | anthropic `/v1` → `anthropic-api-rest` |
| `google` | `generativelanguage.googleapis.com` | gemini `/v1beta` → `google-genai-rest` · chat `/v1beta/openai` → `openai-api-rest` |
| `xai` | `api.x.ai` | responses `/v1` → `xai-api-rest` · chat `/v1` → `xai-api-rest` |
| `deepseek` | `api.deepseek.com` | chat `` → `deepseek-api` |
| `minimax` | `api.minimaxi.com` · `api.minimax.io` | chat `/v1` → `minimax-api` · anthropic `/anthropic/v1` → `minimax-anthropic` |
| `dashscope` | `dashscope*.aliyuncs.com` | chat `/compatible-mode/v1` → `dashscope-api` · anthropic `/apps/anthropic/v1` → `dashscope-api` · dashscope `/api/v1` → `dashscope-native` |
| `ark` | `ark.*.volces.com` | chat `/api/v3` → `volcengine-ark` |
| `newapi` | （用户填） | chat `/v1` → `newapi-openai` · responses `/v1` → `newapi-openai-responses` · anthropic `/v1` → `newapi-anthropic` · gemini `/v1beta` → `newapi-gemini` |
| `midjourney` | （用户填） | midjourney `` → `midjourney-proxy` |
| `ollama` / `lmstudio` / `h3base` | localhost | chat `/v1` → 各自 vendor |
| `custom` | （推断不出） | chat / responses `/v1` → `openai-api-rest` / `openai-responses-rest` · anthropic `/v1` → `anthropic-api-rest` · gemini `/v1beta` → `google-genai-rest` |

- **平台不存**：由（主线路的 vendor id，主机）推断。vendor id 本身就编码了平台
  （`newapi-*` → newapi、`dashscope*` → dashscope…）；只有三个通用 vendor（`openai-api-rest`、`anthropic-api-rest`、
  `google-genai-rest`）要看主机：官方主机 → 厂商平台，否则 → `custom`。一次保存永远不会冻结推断（标准 01 §4 末）。
- **线路的 vendor 按构造保持今天的行为**：主线路 = 存着的 `type`；其它线路若在主线路 vendor 的 `chatMenu` 里
  （今天就能点单到的面）→ 仍用主线路 vendor + 该面；否则 → 画像表里的 vendor。
  于是迁移后的每一条线路都与今天的点单**逐字节相同**；只有用户新加的、今天到不了的线路才换 vendor。
- `custom` 与中转平台上**没有私有扩展**——它们指向的 vendor 本来就没有（`openAIRest` 不声明方言与联网面）。

### 决定 3 · 字段归属

判据：「同一渠道、同一模型，换一个线路，这个值会变吗？」——**只下沉有证据的三个**。

| 字段 | 归属 | 证据 |
|---|---|---|
| `reasoning_effort` | **线路参数** | `reasoningLadder` 按面给不同挡位：① 六档、④ adaptive 无「关闭」、④ budget 只有默认/开启、百炼 ① 面是开关 |
| `enable_thinking` | **线路参数** | 只有 ④ 读它（`anthropic_payload`），方言按面声明 |
| `max_output_tokens` | **线路参数** | ④ 每次必发（缺省 8192 兜底）、① 可选；字段名按 `outputCapField`（面的 vendor）|
| `enable_web_search` | 模型（**授权**） | 能否发出按（线路 vendor, 面）查 `serverWebSearch`；切线路不清（标准 03 §3）|
| `wire_protocol` | 模型：image / video 的媒体点单；**chat 模型改由 `active_route` 表达**，读时把旧的对话面点单迁成线路 | |
| `context_window`、费率组、类型、流式开关、查看全部参考图 | 模型 | 与传输格式无关 |

### 决定 4 · 存储与迁移：内嵌 JSON、读时迁移、不自动合并

- v45 加三列：`llm_channels.routes TEXT`、`llm_models.active_route TEXT`、`llm_models.route_params TEXT`（全部可空）。
  满足内嵌条件（标准 02 §1）：线路从不单独查询、参数按面稀疏、写一个渠道 / 模型仍是一条写。
- **扁平视图**：`llm_channels.type / endpoint` 永远是主线路的 vendor 与完整地址；`llm_models` 的三个线路参数列永远是当前线路的。
  读与写都过同一个幂等规范化（`ChannelRoutes.normalize`）。
- **读时迁移**（纯函数）：`routes` 为空 → 线路 = 主线路 vendor 的 `chatMenu` 每一面各一条（今天已经能点单到的面，
  地址 = 今天的推导结果 `protocolBases[face](endpoint)`）；主机按原始字符串切（不经 URL 解析）；
  路径恰好等于平台默认时不存。chat 模型的 `active_route` 为空 → 由旧的对话面点单推出。
  **唯一需要证明的性质：每个预设 × 每个面迁移后的请求地址逐字节不变**——一条测试一个组合。
- **写入标记**：`routes` 文档里记下写入时的扁平 `type`/`endpoint`；读到二者与标记不同（别的写入方只改了扁平字段——
  旧版本、首次向导、旧备份）→ 按扁平字段重建主线路，其余线路保留。
- **请求侧**：`LLMConfigResolver` 按「模型的线路看渠道」解析；模型选的线路已不存在 → 抛 `LLMConfigException.routeNotFound`，
  **不静默改走主线路**。展示侧（卡片、列表、估算）退回主线路。
- **协议层的一处改动**：`LLMModelConfig.faceBases`——渠道每条线路的地址按对话 wire 列出；
  `LLMDispatcher._faceTarget` 先查它，查不到才走 `protocolBases` 推导（今天的行为）。于是线路的路径覆盖对
  对话、发现（`GET /models` 走 chat 线路）都生效，而没有线路的面仍按今天推导。
- **备份**：`schema_version` 随 dbVersion 到 45（旧版本已有「更新的版本 → 拒绝」检查）；导入旧备份时新列为空，
  由同一个读时迁移处理，不写第二份迁移。`_channelIdentity`（跨恢复保留密钥）读的是扁平字段，不受影响。
- **合并只检测、由用户确认**（§4）。

## 3. 切线路（标准 03）

- 线路参数清单 `RouteParams { maxOutputTokens, enableThinking, reasoningEffort }`，一个类、一处定义。
- 切换：当前参数停放到旧线路名下 → 取出新线路停放的参数（**没配过 = 全空，不复制**）→ 覆盖清单**全部**字段 →
  从停放区移除新线路 → `active_route` = 新线路。模型 id 不变。
- **保存与切换共用 `RouteParams.forRoute(kind)`**：清掉对该面无意义的字段（`enableThinking` 只对 ④；
  不在该面挡位表里的 `reasoningEffort`）。
- 模型「启用过的线路」= `active_route` ∪ `route_params` 的键；编辑器的线路条：已启用实线、渠道提供但未启用虚线加号。
- 改主线路前**钉住跟随者**：`active_route` 为空的 chat 模型显式写成旧主线路。
- 有模型在用的线路、渠道唯一的线路不可移除（界面说明原因）。
- 媒体模型（image / video）没有线路条，地址恒取主线路。

## 4. 合并（标准 04）

- 候选：同平台、同主机（去尾斜杠、忽略大小写）、**同密钥**（只在内存比较，永不显示、永不记日志）、线路集合不相交；
  空密钥只与同主机的空密钥配对；每个渠道至多出现在一个候选对里。密钥是本地明文列，读取无代价（不弹钥匙串）。
- 计划是纯函数：保留渠道 K（排序靠前者）+ 被并渠道 A → 新线路表（K 在前）；A 的模型按
  （上游名, 类型）一对一并入 K 的同名模型（A 当前线路的参数成为 K 在该线路的停放参数，K 的 id 与字段保留），
  找不到的搬到 K 下并**显式钉住原线路**。
- 执行：一个事务内 写渠道 → 写模型 → 删被并模型 → 删 A 余下模型 → 删 A；提交后按 id 映射改写设置里的模型选择与用量记录。
- 入口：渠道栏顶部一条提示「发现 N 组可合并的渠道」→ 预览（线路并入、同名合一、搬迁、将改写的引用数）→ 确认。

## 5. 界面（D1f，标准 05）

| 视图 | 变化 |
|---|---|
| 渠道栏 | 行副行 = 平台标签 + 线路徽标（只列已启用的）；顶部合并提示 |
| 模型列表 | 多线路渠道里，每个 chat 模型卡尾一枚当前线路徽标（全名）；单线路渠道不显示 |
| 渠道头部 | `type · endpoint` 换成 平台 · 主机 · 线路徽标 |
| 添加渠道 | **先选平台，不再选协议**：New API / MiniMax / 百炼 / OpenAI / Google 的「对话接口」一步去掉，换成「将建立的线路」预览；只剩地址类变体（方舟 按量 / 套餐） |
| 渠道编辑 | 主机一次 + 线路表（每族一行：路径 默认/已改/独立主机、实际请求地址、测试、设为主线路、移除） |
| 模型编辑 | 右栏顶部线路条（单线路渠道不显示）；分区标注作用域「模型」/「本线路 · Responses」；切到别的线路前就地展开差异；联网搜索下一行「各线路能否发出」小矩阵 |
| 用词 | 界面「渠道」「线路」成对；「接口协议」只留给出图 / 视频的请求方式 |

## 6. 明确不做

- 线路级密钥、同族多条线路、按单次请求切线路（标准 01 §5）。
- 把 vendor id 改名或删除旧 vendor：存储与内部命名不动（标准 06 §15）。
- 为「升级 → 回退 → 再升级」丢失其余线路参数加机制（标准 02 §4 已知缺口）。
