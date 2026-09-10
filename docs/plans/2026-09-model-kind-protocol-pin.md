# 模型类型声明 + 多媒体协议点单（中转站不再靠 id 猜）

**性质**：高层设计 + 分期实施计划。不含逐行实现；每期开工前按本文档拆任务。
**输入**：`docs/architecture/llm-three-layer.md`（分层铁律；文末"模型 family 仍由 modelId 字符串规则推断……将来若要改成'路由看配置'，改动点只有 Layer 3 的 `ModelDescriptor.of`"一条预告了本方案）、v36 `llm_models.wire_protocol` 点单、D2 设计稿 18a / 18f。
**UI 稿**：交给 Claude Design，prompt 见 [2026-09-model-kind-protocol-pin-design-prompt.md](2026-09-model-kind-protocol-pin-design-prompt.md)。

---

## 0. 结论：不加协议族，不加列——两个已有的用户字段各升一级职责

| 字段 | 今天 | 之后 |
| --- | --- | --- |
| `llm_models.tag`（对话 / 生图 / 视频 / 多模态） | 只给工作台选择器过滤（`app_state.dart:263`）；路由完全不看，另从 id 再猜一次 surface | **声明 surface**：决定这个模型出现哪张协议菜单 |
| `llm_models.wire_protocol`（v36） | 只能在「厂商声明的菜单 ∩ id 猜出的 family」里点；中转站交集为空，下拉不渲染 | 在「该 surface 的完整菜单」里点；点了同时决定**路由**和**参数表** |

**铁律：`wire_protocol` 为 null（自动）且 tag 与 id 猜测一致时，路由与今天逐位相同。** 这覆盖了几乎所有现存行——tag 本来就是发现模型 / 向导时 `ModelFamilyClassifier.inferTag` 填的，而 `inferTag` 与 `surfaceForModel` 读的是同一对谓词（`isVideo` / `isImageGeneration`），一致性是构造出来的。只有两种情况路由会变：用户显式点单；用户手动把 tag 改成与 id 猜测不一致。

---

## 1. 现状：为什么现有点单救不了中转站

| # | 关卡 | 位置 | 中转站上的后果 |
| --- | --- | --- | --- |
| 1 | surface 从 id 猜，tag 不参与 | `LLMDispatcher.surfaceForModel` (`llm_dispatcher.dart:108`) | `nano-banana-pro` 被判成 chat，根本拿不到生图菜单 |
| 2 | 生图菜单 = `vendor.imageMenu ∩ _imageProtocolsFor(family)` | `protocolMenuFor` (`llm_dispatcher.dart:141`) | 中转 vendor 的 `imageMenu` 为空 → 菜单空 → `_showProtocolSection` 为 false；`_pinnedProtocol` 把菜单外的存储值当失效丢掉 |
| 3 | 参数表按 id | `ModelCapabilities.forModel(modelId)` 的 7 个调用点 | 路由就算对了，未识别 id → 空表 → 工作台参数面板空白 |
| 4 | 参数记忆命名空间按 id family | `app_state_workbench.dart:130` `_familyKey` | 同上 |
| 5 | 视频：① 家族下 id 不是 `openaiVideo` 直接抛错 | `startLongRunning` (`llm_dispatcher.dart:766`)、`canRunVideoJob` | 中转上的视频模型在工作台视频选择器里**完全不出现** |

---

## 2. 解析顺序（全部在 dispatcher，单点）

```
declared  = surfaceOfTag(config.tag) ?? surfaceOfFamily(classify(modelId))
            // tag 为 null ＝ 旧调用方 / 测试夹具，行为与今天完全相同
menu      = LLMDispatcher.protocolMenu(channelType, modelId, tag)   // ProtocolMenu { options, auto, fixed }
pinned    = parse(config.wireProtocol)，且 ∈ menu.options；否则 null（沿用 18a 态④ 失效语义）
effective = pinned ?? menu.auto          // null ＝ 该渠道不提供此 surface
descriptor= ModelDescriptor.of(modelId, servedBy: effective)
```

`surfaceOfTag`：`image` → imageGen；`video` → videoJob；`chat` / `multimodal` / `refiner` → chat。

### 2.1 `ProtocolMenu` 取代 `List<WireProtocol>`

今天"auto = 菜单第一项"被三处默认：编辑器、`autoProtocolFor`、`_nativeImageProtocol` 的兜底。新菜单里 auto 不一定排第一——例：MiniMax 渠道上的 `qwen-image`，今天走 chat，但用户可以显式点 MiniMax Images——所以 auto 单独成字段。

- **约束 `auto ∈ options`**（不在就补进去）：保证「自动 · 当前解析为 X」永远是真话。
- **`fixed`**：Midjourney 家族——路由固定、没有选择，协议区不渲染。与 `auto == null`（"该渠道没有这个 surface"）区分开，否则 MJ 渠道会被 UI 当成"不支持生图"。

### 2.2 菜单构成

**chat surface**：不变，`vendor.menuFor(Surface.chat)`。

**imageGen surface**（显示顺序：厂商声明 → 家族默认 → 对话出图）：

| 来源 | 条目 |
| --- | --- |
| 厂商声明 | `vendor.imageMenu` 全部——**不再**与 id family 求交集；交集只用来算 auto |
| 家族默认，仅当 `vendor.offersFamilyMediaSurfaces` | ① `openaiImages`；③ `geminiImagen`；④ / DashScope 原生：无 |
| 通用（Midjourney 除外） | 新值 `WireProtocol.chatImage`「对话出图」（§2.4） |
| 补位 | auto（§2.3）若不在上面，补进去 |

DashScope 异步项按 `supportsAsyncImageTask` 过滤：**只在 id 被识别时生效**；未识别 id 两项都给。

**videoJob surface**：

| 来源 | 条目 |
| --- | --- |
| 厂商声明 | `vendor.videoProtocol` |
| 家族默认，仅当 `offersFamilyMediaSurfaces` 且厂商未声明 | ① `openaiVideos`；③ `geminiVeo` |
| 补位 | auto 若不在上面，补进去 |

### 2.3 auto ＝ 今天的路由（逐分支对照，这张表就是回归测试的期望值）

**imageGen**

| vendor 家族 | 条件（按顺序） | auto |
| --- | --- | --- |
| ③ Gemini | id family == `geminiImagen` | `geminiImagen` |
| | 其它 | `chatImage`（今天 `_geminiChat.generate`） |
| ① OpenAI | `_hasNativeImageRoute` | 厂商菜单里服务该 family 的首项（DashScope / MiniMax） |
| | id family == `openaiImage` | `openaiImages` |
| | id family == `xaiImage` | vendor 声明 `xaiImages` 则它，否则 `openaiImages` |
| | 其它 | `chatImage` |
| ④ Anthropic / DashScope 原生 | `_hasNativeImageRoute` | 厂商首项 |
| | 其它 | `chatImage` |
| Midjourney | — | `fixed` |

**videoJob**

| vendor 家族 | 条件 | auto |
| --- | --- | --- |
| ③ | 无条件 | `geminiVeo` |
| ① | id family == `openaiVideo` | 厂商声明 ?? `openaiVideos` |
| DashScope 原生 | id family == `openaiVideo` 且声明 `dashscopeVideo` | `dashscopeVideo` |
| ④ | id family == `openaiVideo` 且有声明 | 声明 |
| ① / ④ / DashScope 原生 | **tag = 视频但上面都不命中**（今天抛 `UnsupportedError`） | `options.first`；options 为空 → null |
| Midjourney | — | `fixed` |

### 2.4 新值 `WireProtocol.chatImage('chat-image', Surface.imageGen)`

不违背"枚举值稀缺、只有已实现的协议配拥有一个"：它解析到已存在的代码（`_chatGenerate`，按渠道的 chat 面走），只是给"生图 surface 上走 chat"这条**今天就存在、却无法被点名**的路由一个名字。没有它，中转站上的 `gpt-image-1` 无法强制走 chat。

### 2.5 `VendorProfile.offersFamilyMediaSurfaces`（默认 false）

默认 false 的理由：百炼 compatible-mode 没有 `/images`，xAI 没有 Sora 形态的 `/videos`，DeepSeek 两者都没有——把家族默认面塞给一方厂商，等于在菜单里放一个必然 404 的选项。

| 值 | vendor |
| --- | --- |
| true | `openAIRest`、`newApiOpenAI`、`googleRest`、`officialGoogle`、`newApiGemini` |
| false | 其余全部（xai、deepseek、minimax×2、dashscope×2、minimaxH3Base、anthropic×2——④ 本无家族默认面、midjourney） |
| **待定** | `ollama`、`lmStudio`（§8.1） |

---

## 3. Layer 3：descriptor 由 (id, servedBy) 决定

### 3.1 family

```
idFamily = classify(modelId)
servedBy == null                   → idFamily
servedBy 能服务 idFamily（下表）    → idFamily        // 识别到的模型保留按 id 的精细表
否则                                → familyOf(servedBy)
```

| servedBy | familyOf | 能服务的 idFamily |
| --- | --- | --- |
| `openaiImages` | `openaiImage` | `openaiImage`、`xaiImage` |
| `xaiImages` | `xaiImage` | `xaiImage` |
| `geminiImagen` | `geminiImagen` | `geminiImagen` |
| `dashscopeImagesSync` / `Async` | `dashscopeImage` | `dashscopeImage` |
| `minimaxImages` | `minimaxImage` | `minimaxImage` |
| `openaiVideos` / `xaiVideos` / `dashscopeVideo` / `minimaxVideo` / `minimaxH3BaseVideo` | `openaiVideo` | `openaiVideo` |
| `geminiVeo` | `geminiVideo` | `geminiVideo` |
| `chatImage`、chat 面各值 | **降为同源 chat family**：`gemini*` → `geminiChat`，其余 → `other` | 所有**没有专属非 chat 路由**的 family（`geminiImage`、`geminiChat`、`openaiChat`、`other`、`midjourney`） |

降级只作用于"有专属路由"的 family（`openaiImage`、`xaiImage`、`geminiImagen`、`dashscopeImage`、`minimaxImage`、`openaiVideo`、`geminiVideo`）。`geminiImage`（nanoBanana）**必须保留**：它本来就走 chat，而且 `ModelDescriptor` 靠 Gemini 系 family 判断"经 OpenAI 兼容面访问 Gemini 时要带方言扩展"——降成 `other` 会静默丢掉这些扩展。

关键例：

- 中转上的 `gpt-image-1` 点 `chatImage` → family `other` → ① 分支不再命中 `openaiImage` → 落到 chat。
- `nano-banana-pro` 点 `openaiImages` → family `openaiImage` → Images API。
- 百炼上未收录的新 id 点 `dashscopeImagesSync` → family `dashscopeImage` → `_hasNativeImageRoute` 为真 → 原生路由（顺带解决"分类器还没收录新模型就用不了"）。

**dispatcher 的 family 分支一行不改**——这是选"从协议反推 family"而不是"把 dispatcher 改成按协议 switch"的原因。后者更干净，但要重写 generate / generateStream / startLongRunning / generateTimeout / streamSupportsTools 五处，列为后续（§8.4）。

### 3.2 capabilities

`ModelCapabilities.forModel(modelId, {WireProtocol? servedBy})`：

- 3.1 得出的 family == idFamily → 今天的按 id 精细表，逐位不变；
- 否则 → 新增 `forProtocol(servedBy)`：

| servedBy | 保底表 |
| --- | --- |
| `openaiImages` | `_openaiImage` |
| `xaiImages` | `_xaiImage` |
| `geminiImagen` | `_imagen` |
| `dashscopeImagesSync` / `Async` | `_dashscopeQwenImage`（参考图上限更小、尺寸词表更严的那张） |
| `minimaxImages` | `_minimaxImage` |
| `chatImage`、chat 面各值 | `ModelCapabilities()` |
| `openaiVideos` | `_openaiVideo` |
| `xaiVideos` | `_grokImagineVideo` |
| `dashscopeVideo` | `_dashscopeWanVideo` |
| `minimaxVideo` | `_minimaxVideo` |
| `minimaxH3BaseVideo` | `_minimaxH3Base` |
| `geminiVeo` | `ModelCapabilities(isVideoGenerator: true)` |

这就是"协议的默认能力表"——表几乎都已存在，只是今天按 family 挂着。

### 3.3 缓存键

`ModelDescriptor._cache` 的键从 `modelId` 改为 `'$modelId|${servedBy?.id}'`。

不改的后果：两个渠道各有一个同名模型、点单不同，先解析的那个会被后解析的读到——同一个 id 拿到别人的 family 和参数表，**不报错**。

---

## 4. 调用方：从"只给 id"升级为"给模型行"

新增单一入口 `LLMDispatcher.descriptorForModel(LLMModel model, String channelType)`（static，内部走 §2），UI / state 一律用它，不各自拼。

| 位置 | 今天 | 改为 |
| --- | --- | --- |
| `app_state_workbench.dart:130` `_familyKey` | `classify(id).name` | `descriptor.family.name`——已识别 id 的命名空间不变，已存的参数记忆不丢 |
| `app_state_workbench.dart:152` / `:191` `effective*Params` | `forModel(id)` | `descriptor.capabilities`；签名从 modelId 改为模型行（调用方一并改） |
| `workbench_config_panel.dart:754` | `forModel(id)` | 同上 |
| `model_selection_section.dart:165` | `forModel(id)` | 同上 |
| `video_config_panel.dart:368` / `:502` | `forModel(id)` | 同上 |
| `app_state.dart:310` `_supportsVideoForType` | config 不带 tag | 补 `tag: m.tag` |
| `models_screen.dart:1121` 失效 chip | `isStaleProtocolSelection(type, id, pin)` | 加 tag 参数 |
| `model_edit_dialog.dart:954` | `protocolMenuFor(type, id)` | `protocolMenu(type, id, tag)` |
| `task_executors.dart:177` / `:223` | `ModelDescriptor.of(id).acceptsImageInput` | **不改**：这里问的是 chat 模型能否看图，多媒体点单不影响 |

数据通路：`LLMModelConfig` 加 `final String? tag`（null ＝ 旧调用方 ＝ 按 id 猜，现有测试夹具零改动），`withEndpoint` 带上，`LLMConfigResolver` 读 `modelData.tag`。与 `wire_protocol` 同规矩：**列只由 resolver 读进路由**。

---

## 5. 数据

- **不加列，不迁移。** `tag` 与 `wire_protocol` 都是用户配置，v36 注释里"不是可推导副本、v32 教训不适用"的论证原样适用。
- **禁止**保存时把 `inferTag` 或 auto 解析结果写进任一列——那就是 v32：存了个可推导的副本，分类规则一改就过时。自动 ＝ null。
- 要改的注释：`llm_model.dart:5`（`tag` 还写着 `image, chat, multimodal`，且须写明它现在参与路由）。
- 失效语义多一个成因——**tag 改了，点单落在另一个 surface 上**。仍按 18a 态④契约：打开时显形不改，保存时静默清空。
- **编辑框内**切换类型 chip：点单回到自动，但本次对话框会话内按 surface 记住，切回来恢复（用户自己的动作，不是背后改；也不弹确认）。

---

## 6. 分期

**P1 · Layer 2/3 + 路由（无 UI）**

1. `WireProtocol.chatImage`；`VendorProfile.offersFamilyMediaSurfaces` + §2.5 的五个 true。
2. `ProtocolMenu` + `LLMDispatcher.protocolMenu(channelType, modelId, tag)` + `surfaceOfTag`；`autoProtocolFor` / `isStaleProtocolSelection` / `_pinnedProtocol` / `_nativeImageProtocol` 改读它。旧 `protocolMenuFor` 删除，不留兼容壳（UI 与路由共用的单点查询只能有一个）。
3. `LLMModelConfig.tag` + resolver。
4. `ModelDescriptor.of(id, servedBy:)` + 缓存键；`ModelCapabilities.forModel(id, servedBy:)` + `forProtocol`。
5. `resolveTarget` 先算 effective 再取 descriptor。`startLongRunning` 与 `canRunVideoJob` 的"未识别视频 id"由 family 反推自然打通——核对两者仍逐分支镜像。
6. `wire_protocol_labels.dart`：给 `chatImage` / `openaiImages` / `geminiImagen` / `openaiVideos` / `geminiVeo` / `xaiImages` 等补用户语言名与说明。它们以前"从不出现在菜单里"所以保留未翻译技术名，现在会出现了。四语言，走 joycai-l10n。

**P2 · 调用方** —— §4 表。

**P3 · UI** —— 等 Claude Design 的 `D2a` 稿后按稿实现。读稿先验完整性（`</x-dc>` 在不在、字节数是否贴着 262144）：D2 本体已经顶到 256 KiB 读取上限，18b 之后的帧工程侧读不到。

**P4 · 文档** —— `llm-three-layer.md`：删掉"模型 family 仍由 modelId 推断"那条遗留说明，写入 §2 解析顺序与 §3.1 映射表；红旗表加两行："`llm_models.tag` 在 `LLMConfigResolver` 之外被当路由事实读取"、"`ModelCapabilities.forModel(id)` 不带 `servedBy` 出现在 `services/llm/` 之外"。

---

## 7. 测试

**回归门（必须原样全绿）**：`test/wire_protocol_routing_test.dart` 的全部现有用例。它们构造的 config 不带 tag，走 id 猜测路径，§2.3 保证逐位相同。**任何一个需要改期望值，都说明 auto 语义漂了——停下来查，不要改测试。**
例外只有一处是有意的：直接断言 `protocolMenuFor` 返回列表的用例，要随 API 改成断言 `ProtocolMenu.options` / `.auto`，值本身不应变化（chat 面与原生菜单的顺序照旧）。

新增（先写、先确认红）：

| 场景 | 期望 |
| --- | --- |
| `openai-api-rest` · `nano-banana-pro` · tag=image · 无点单 | auto `chatImage`；options ⊇ {`openaiImages`, `chatImage`} |
| 同上 · 点 `openaiImages` | 路由 Images API；capabilities == `_openaiImage` |
| `openai-api-rest` · `gpt-image-1` · 点 `chatImage` | 走 chat；不点 → Images API（今天的路） |
| `openai-api-rest` · `my-sora` · tag=video · 无点单 | auto `openaiVideos`；`canRunVideoJob` 为 true |
| 同上 · tag=chat | 不出现在视频面；`canRunVideoJob` 为 false |
| `newapi-anthropic` · 未识别 id · tag=image | options == {`chatImage`} |
| `newapi-anthropic` · 未识别 id · tag=video | auto == null |
| `deepseek-api` · `sora-2` · tag=video | auto `openaiVideos`（今天的路，补位进 options） |
| `dashscope-api` · 未收录的 `wan3.5-image` · 点 `dashscopeImagesSync` | 原生路由；capabilities == `_dashscopeQwenImage` |
| `minimax-api` · `qwen-image` · tag=image | auto `chatImage`（今天的路）；options 含 `minimaxImages` 但它不是 auto |
| `midjourney-proxy` · 任意 id · tag=image | `fixed` |
| 缓存隔离：同一 id、两个 servedBy | 两个不同 family |
| 存 `dashscopeImagesAsync`，tag 改 chat | `isStaleProtocolSelection` 为 true；路由回 chat 面 auto |
| 已识别 id 的 `_familyKey` | 与改前字符串相同（参数记忆不丢） |
| 编辑器 widget：中转 + tag=image | 协议区渲染；切 chip 到对话再切回生图 → 点单恢复 |

变异验证（改前用**文件备份**，不要 `git checkout --`——那会拿回 HEAD 上的旧版本，吞掉未提交的修复）：去掉缓存键里的 `servedBy`、去掉 `offersFamilyMediaSurfaces` 判断、去掉 `auto ∈ options` 补位，对应用例必须各自变红。

widget 测试注意：不要对工作台 `pumpAndSettle`（会挂）；AppState 的 setter 在 `testWidgets` 下多数不触发通知，每条新测试都要确认它能红。

---

## 8. 决定与待定

**已决定（2026-09-10）**

1. **Ollama / LM Studio 的 `offersFamilyMediaSurfaces`：先关着。** LM Studio 没有图像面；Ollama 的 OpenAI 兼容图像接口未核实，对照上游文档后再开。
2. **中转站不提供厂商原生协议，先不管。** 原生协议从 endpoint 推导路径（DashScope 推 `/api/v1`，MiniMax 推 `/v1`、`/v2`），在中转 host 上推出来的路径没有意义。

**实现时相对 §2 / §3 的三处收紧**（非 UI 部分已落地，见 `docs/architecture/llm-three-layer.md`「模型类型声明与多媒体协议点单」）

- **`chatImage` 不是"所有渠道都给"。** 只在 `offersFamilyMediaSurfaces` 为真，或它恰好是 auto（今天的路由）时出现在菜单里。一方厂商（百炼、xAI、MiniMax）的图像菜单保持原样，不平白多出一个用不上的选项。
- **`servedBy` 的判据是"effective ≠ id 自身路由"，不是"有点单"。** 否则点单点到 auto 本来就走的那条路（中转上的 `qwen-image` 点「对话出图」）会把 DashScope 参数表和 5 分钟超时一起剥掉——路由没变，参数面板和 deadline 却变了。
- **`chatImage` 的保底表是 `ModelCapabilities(isImageGenerator: true)`，不是空表。** 两条 chat wire 都按这个 flag 决定要不要出图（③ 的 `responseModalities`、① 的"整条回复是链接即图片"），空表会让图片静默丢失。顺带修好了一个存量问题：中转上未识别的生图别名以前这个 flag 就是假的。

**待定**

3. **"对话出图"在 ④ 上该不该是可选项**：Anthropic 协议本身不产图，放进菜单等于一个几乎必然无图的选项。保留是为了 auto 诚实（今天 ④ 上的未识别图像模型确实走 chat）。UI 上是否降为说明句而非可选项，交给设计稿（prompt 态⑨）。
4. **dispatcher 改为按 effective 协议 switch**，取代 §3.1 的 family 反推：更干净，后续重构。
5. ~~编辑框内切换类型 chip 的中间态~~ —— **已按 D2a 落地（2026-09-10）**，见下方「P3 · UI 落地记录」。

## P3 · UI 落地记录（D2a 模型类型与多媒体协议）

设计稿 `D2a 模型类型与多媒体协议.dc.html`（20a–20k）。实现分三处：
`lib/widgets/models/protocol_section_form.dart`（裁决 1/2/4 的纯函数，`test/protocol_section_form_test.dart` 钉住）、
`lib/widgets/models/model_protocol_section.dart`（区块本体：下拉 / 只读行 / 说明句 / 参数行 / 窄屏底部弹层 / 卡片预览值）、
`model_edit_dialog.dart`（状态与接线）。截图：`flutter test test/screenshots/app_screens_test.dart --plain-name "modelEditor editor"`。

**与稿子的有意偏差**

- **类型记忆按 surface 记，不按类型记。** 稿子画的是 `typeMemo[类型]`，但对话与多模态共用一张菜单，按类型记会让"对话 ↔ 多模态"来回切时丢掉仍然有效的对话面点单。
- **"未识别"只对生图/视频成立。** 20f「联动 中」在对话面也画了未识别句；但对话模型几乎全部落在 `other` 家族，按字面实现会让每个 qwen-max 都挂一句"未识别"。`ProtocolMenu.recognized` 在对话面照常计算，UI 只在媒体面读它。
- **辅助句用 `onSurfaceVariant`，不用 `outline`。** 截图里 `outline` 比下拉自带的 helper 淡一档，只读行和说明句看着像禁用态；Material 给字段 helper 的就是 `onSurfaceVariant`。
- **窄屏协议行自动态是单行**（「自动 · 当前解析为「X」」），点单态才是"名字 + mono 路径"双行。
- **底部弹层用 ListTile + 单选图标，不用 `RadioListTile`**：`groupValue` 已弃用（analyze 计 info），弹层点选即关，没有组状态可管。

**没做的**

- **18a 的右栏 2px 引导线与下级缩进**：18a 时期就没实现，D2a 的"引导线补间到主色"依赖它；补上要重排能力/代理行为两个区块的结构，单开一轮。
- **菜单选中项的 check + 主色 10% 底**：`AppDropdown` 基于 Material `DropdownButton`，选中高亮是它自带的；自绘选中态要换组件，单开。
- **协议字段值用主色深**（点单态）：只换了描边与底两个 token，值仍是正文色。
