# 输入图计费：按秒 / 按条 / 按次的计费组也收，视频协议发布张数

**分支** `claude/input-images-all-modes` · **设计稿** `D2e 计费组-输入图全模式`（Claude Design 项目）
**性质**：方案 + 执行清单。一片一个 commit，状态与施工记录写在本文件里；收尾片把结论搬走后本文件删除。

---

## 0. 为什么

D2c（v4.25.0）给按规格计费组加了「输入图」一侧，但只让**单位为「张」**的组收（`PricingGroup.chargesInputImages`），
理由是「没有视频协议发布张数，一个只会碰巧记账的费率比没有更糟」。台账「还欠的 · 视频的输入图」写着：
「首帧 / 参考图是否单独计费，四家文档都没写；要做得两处一起开」。

2026-09-22 付费实测 xAI `grok-imagine-video-1.5` 给出了第一个真实用例（§1）：参考图 **$0.01/张、线性**，
标价页只写 $0.080/s，一个字没提。用户的提案由此成立：**计费组的「按秒」「按条」都可以按输入图张数计费**；
按次（`request`）模式同理——中转站上按次结算的出图 / 视频模型，参考图另收钱时今天也一分不记。

## 1. 事实

- **xAI 视频**（【实测 2026-09-22】，`grok-imagine-video-1.5`，1 s · 480p，`skills/ai-agent-architecture` 14 §2 / §3.8、坑 129）：
  文生视频 800 000 000 ticks = $0.08；`image`（首帧）×1 → 900 000 000（$0.09）；`reference_images` ×2 → 1 000 000 000（$0.10）。
  输入图 $0.01/张、线性、无免费张数——与它的出图面同价。
- xAI 视频的报价**只在终态轮询回包里**：pending 是 HTTP 202 `{status, progress}`；done 是 200
  `{status:'done', video:{url, duration:1, …}, usage:{cost_in_usd_ticks}, progress:100}`。`video.duration` 报**实际渲染秒数**。
  应用今天的 `xaiVideoPollEnvelope` 两者都不看：`renderedSeconds` 不传（秒数结算对 xAI 不生效），`usage` 丢弃（报价不落行）。
- 应用侧：`token_usage.input_images / input_units / input_unit_price`（v48）每行都有；`reported_cost`（v49）每行都有。
  **本轮不需要迁移**。`SpecUsage.price` 的输入一侧算式已经在（免费张数、零交付不收），只是被单位判据关着。
- 七个 images 协议已发布 `input_image_count`；按次计费的组挂着它们时，张数已经在 metadata 里，只是记账不读。
- 五个视频协议（Veo、Sora/OpenAI Videos、百炼、MiniMax、MiniMax H3 本地、xAI）的 `submit` 只返回任务 id（`String`），
  张数没有出口；提交行的 metadata 是 `{'operation': 'submit'}`。
- 按 token 的组不在本轮：GPT-Image-2 的 `image_tokens` 是台账里另一条（「按 token 模式的图像输入单价」）。

## 2. 设计

### 2.1 判据：三处一起开（`pricing_group.dart`、`spec_billing.dart`、`token_usage.dart`）

- `PricingGroup.chargesInputImages` → `(isSpecBilled || billingMode == 'request') && inputUnitPrice > 0`。
  单位不再参与：按张 / 按秒 / 按条的规格组，和按次的组，都收。按 token 不收（不变）。
- `SpecUsage.price` 去掉 `unit == OutputUnit.image` 的判据；保留 `units > 0`（一秒 / 一条 / 一张都没交付的请求不收输入费）。
  免费张数仍按每次请求。
- 按次模式的输入一侧：新增 `SpecUsage.inputsOnly(...)`——只算输入三列，输出四列留空（`unit: null, units: 0, unitPrice: 0, snapshot: null`）。
  `UsageSpecBilling.fromMap` 对「只有输入三列非零」的行本来就返回非 null（v48 的读法），所以按次行读回来就有 `spec.inputCost`。
  按次一律视为已交付（按次 = 「按成功请求」），有张数就收。
- `TokenUsage.costParts` 的 `request` 分支：`specInput: spec?.inputCost ?? 0.0`（今天写死 0）。`snapshotCost` 不变（已带 `spec`）。
  `unmatched` / `specLabel` 仍只对规格模式（按次行没有档位表）。

### 2.2 解析器与记账（`llm_config_resolver.dart`、`llm_usage_recording.dart`）

- 解析器照旧 `if (group.chargesInputImages)` 才复制两个标量——判据一开，按秒 / 按条 / 按次自动带上。
- `_writeUsageRow`：`spec: spec?.toBilling() ?? LLMService.requestInputBilling(config, metadata)`——
  按次模式且 `config.inputUnitFee > 0` 且 metadata 里有张数时写输入三列；否则 null，行与从前一字不差。

### 2.3 视频协议发布张数（`protocol.dart`、`llm_dispatcher.dart`、五个协议）

- `VideoJobProtocol.submit` 改回 **`VideoSubmission {requestId, inputImages}`**，不再是裸 `String`。
  张数按 D2c 的不变量①：**组完请求体之后**数——读不到的附件、互斥被丢的参考图、xAI 不支持的尾帧，都不算。
  - Veo：`prepareVeoPayload` 出的 instance 里 `image` + `lastFrame` + `referenceImages.length`（`veoInputImages(payload)` 纯函数）。
  - OpenAI Videos：`input_reference` + `images[]` 的 multipart 文件数。
  - 百炼：`input.media[]` 长度。
  - MiniMax：`partitionMiniMaxVideoMedia` 之后 `kept.length`；H3 本地同理（`partitionMiniMaxH3Media`）。
  - xAI：`image` 计 1，或 `reference_images.length`。
- `LLMOperationTicket` 加 `inputImages`（默认 0）；`startLongRunning` 原样带过。
- `LLMService.startLongRunning` 记提交行：`{'operation': 'submit', ...sentInputImages(ticket.inputImages)}`——
  `specUsageFor` 从此在视频提交行上读到张数，按秒 / 按条的组按 §2.1 收；按次的组走 §2.2。

### 2.4 xAI 视频面：实际秒数 + 报价（`xai_videos_protocol.dart`、`protocol.dart`、`task_executors.dart`、`llm_service.dart`、`usage_repository.dart`）

- `xaiVideoPollEnvelope` 的 done 分支：`videoDoneEnvelope(..., renderedSeconds: video['duration'], reportedCost: …)`，
  报价用 `reportedCostFromTicks(usage['cost_in_usd_ticks'])` 换算——键与 images 面同一个 `reported_cost_usd`，换算只有一处。
- `videoDoneEnvelope` 加 `reportedCost: double?`，落在信封顶层的 `reportedCostKey`（与 `renderedSeconds` 并排；
  0 或负数不发，与 images 面一致）。
- 执行器：`reportedCostOf(done)`；秒数或报价任一在，就调 `settleVideoUsage`。
- `settleVideoUsage({num? renderedSeconds, double? reportedCost})`：
  - 规格模式且有秒数 → 照旧 `updateSpecBilling`（只写输出四列）。
  - 有报价（任何模式）→ 新的 `UsageRepository.updateReportedCost(taskId, cost)`，**只写 `reported_cost` 一列**。
    D2d 的口径：报价压过整张表；提交行原先记的是档位估算，终态把报价补上，用量页自动变成「上游报价 | 档位估算」。
  - 两者都是尽力而为、各自 WARN。
- 不做：其它视频面的报价（都不报钱）；OpenAI Videos 的 `seconds` 回显（超出本轮）。

### 2.5 UI（设计稿 `D2e`，裁决见 §5）

- 编辑器（`spec_rate_table.dart`、`fee_group_editor_fields.dart`、`fee_group_draft.dart`）：
  规格模式下「输入图」一行对三种单位都显示（不再按单位折叠）；按次模式在请求单价下方也放这一行。
  `showsInputImages => isSpec || isRequest`；`ratesValid` 在按次模式也含 `!inputImagePriceInvalid`。
- 摘要与卡片（`fee_group_summary.dart`、`fee_group_row.dart`）：按次的 `feeGroupSummary` 尾巴带 `· 输入 $0.01/张`；
  按次的标签行多一个「输入图」标签（与规格模式的 `22e` 同样，只在收费时出现）。
- 用量页（`usage_list.dart`）：`_chargedInputImages` / `chargesInput` 去掉 `_isSpecRow` 判据——按次行的规格格只写「输入 3 张」；
  展开处按次行也分「输出金额 | 输入图 | 输入金额」三对（输出金额 = 请求数 × 请求单价）。
  `usage_group_costs.dart` 已按 `costParts` 汇总，不改。
- 文案：预计沿用 D2c 的四语键；新增的只有稿里要求的（若有）。

### 2.6 不做

- 按 token 模式的输入图（台账另一条）。
- 视频协议的中转报价、720p / 1080p 加价（未验）。
- 视频**失败**时是否退输入费：应用只在提交被接受时记账，失败与 D2c 口径一致（对账单）。

## 3. 执行清单

| 片 | 内容 | 主要文件 | 验收 | 状态 |
|---|---|---|---|---|
| 0 | 本文件 + 设计稿 `D2e` | `docs/plans/`、Claude Design | — | ✅ 帧 24a–24h |
| 1 | 判据三处：`chargesInputImages`、`SpecUsage.price` / `inputsOnly`、`costParts.request` | `pricing_group.dart`、`spec_billing.dart`、`token_usage.dart` | 单测：按秒 / 按条组收；按次行 `spec.inputCost` 进 `cost`；按 token 仍不收 | ✅ |
| 2 | 解析器 + 记账：按次模式写输入三列 | `llm_config_resolver.dart`、`llm_usage_recording.dart`、`llm_service.dart` | `recordUsageForTest`：按次 + 张数 → 三列有值；无张数 → NULL | ✅ |
| 3 | `VideoSubmission` + ticket 张数 + 五个协议数张数 + 提交行 metadata | `protocol.dart`、`llm_dispatcher.dart`、五个 `*_video*_protocol.dart`、`gemini_payload.dart`、`llm_service.dart` | 每个协议一条走线测试：请求体里的张数 = ticket 张数；提交行 `input_images` | ✅ |
| 4 | xAI 轮询读 `video.duration` 与 `usage.cost_in_usd_ticks`；信封；执行器；`settleVideoUsage` 写报价 | `xai_videos_protocol.dart`、`protocol.dart`、`task_executors.dart`、`llm_service.dart`、`usage_repository.dart`、`database_service.dart` | 信封测试；settle 测试：规格写四列 + 报价列；按次只写报价列 | ✅ |
| 5 | UI：编辑器 / 摘要 / 卡片 / 用量页；四语；截图 | `widgets/models/*`、`screens/metrics/widgets/usage_list.dart`、`l10n/src/*/models.arb` | widget 测试 + 截图无溢出 | ✅ |
| 6 | 文档：`api/usage.md` §5 加 xAI 视频表、`llm-three-layer.md` 不变量、台账、playbook 快照、`llm-billing-model` skill 02/03；bump 4.28.0 | `docs/`、七处版本号 | — | ⬜ |
| 7 | 独立 review（opus）→ 修 → 再 review，直到无新问题；PR | — | 两道门全绿 | ⬜ |

## 4. 设计 brief（交给 Claude Design 项目的原文）

> 在项目 `925a4d48-684e-4733-bca2-1aa808b7e18f` 新建一份 `D2e 计费组-输入图全模式.dc.html`（自成一份，不要改写
> `D2c` / `D2d`——这个工具会整文件重写并丢掉旧 section）。先读 `D2c 计费组-输入图计费` 的九帧（22a–22i）与末尾的
> mono 规格汇总，以及 `D2b` 的按秒 / 按条档位表帧；新稿是 D2c 的增量，几何、token、控件一律沿用。
>
> **要解决的事**：D2c 只让单位为「张」的规格组收输入图费。现在有了真实用例——xAI `grok-imagine-video-1.5`
> 每张首帧 / 参考图收 $0.01（按秒标价 $0.08/s 之外另收），所以：① 按秒、按条的规格组也要有「输入图」一行；
> ② 按次（`request`）的组也要有——它今天只有一个「请求单价」字段。默认态仍必须安静：不填就没有这回事。
>
> **要出的帧**（桌面 1440 为主，平板 834 与手机 390 各一帧；暗色至少一帧）：
> 1. 计费组编辑器 · 按规格 · 单位 = 秒：档位表下方的「输入图」一行（D2c 22a 的那一行）在按秒 / 按条时长什么样——
>    副标题要不要改（「每次请求随附的参考图」对视频也成立：首帧 / 尾帧 / 参考图），单价后缀仍是 `/张`。
> 2. 计费组编辑器 · 按次：只有「请求单价」一个字段，「输入图」一行放哪（同一行分栏 / 下方独立一行）、
>    与 `requestPriceHint` 那句提示的先后；空态 / 已填两态。
> 3. 计费组卡片与摘要：按次的 `feeGroupSummary`（`按次 · $0.0100/req`）尾巴怎么并入 `· 输入 $0.01/张`；
>    卡片标签行「请求单价」旁边的「输入图」标签（D2c 22e 的同款）。
> 4. 用量页：按次行的「规格」格（今天为空）只写「输入 3 张」；展开处按次行的三对
>    「输出金额（请求数 × 请求单价）| 输入图 | 输入金额」，与 D2c 22g 的写法对齐；
>    视频提交行（按秒）带输入图时的规格格「1080p · 5s · 输入 2 张」；xAI 视频终态补上报价后的
>    「上游报价 | 档位估算」（D2d 23b 的样子，这里只需确认与输入行并存时的顺序）。
> 5. 末尾 mono 规格汇总：顺序、字号、颜色 token、四语文案（中文为准附 en / zh_Hant / ja）；能沿用 D2c 的键就沿用，新增的单列。
>
> **词汇**：用本应用的 `App*` 组件名与档位表用的 `_PriceField` / `_Hint` / `FeePriceTag` / `_kindPlate` 等现有部件名，
> 不要标 Material 组件名。审美：Apple 式干净、主次分明；输入图一行是次要信息。

## 5. 施工记录

- **第 0 片 · 设计稿 `D2e`**（子代理拿不到 DesignSync，稿子由主会话校验 `dv-*` 词汇与帧 id 后推送，128 782 字节，
  section `t24`，帧 24a–24h + mono 规格汇总）。裁决：① 规格模式下「输入图」块对三种单位**常在**，D2c 22b 的
  AnimatedSize 收起作废；副题按单位换词——按张仍 `specInputSub`，按秒 / 按条用新键 `specInputSubVideo`「首帧 / 尾帧 / 参考图」；
  单价后缀始终 `/张`。② 按次模式：同一个部件放在 `requestPriceHint` **之下**（请求字段 → 6 → 提示 → 10 → 发丝线 → 6 → 行），
  不与请求字段分栏；去掉档位表删除列的 28 留白（`trailingBlank: false`），单价框右缘与请求字段右缘对齐；提示句不提输入图。
  ③ 摘要：按次分支拼同一条 `feeGroupInputSummary` 尾巴；卡片标签「请求」之后加「输入图」标签，不加悬浮表。
  ④ 用量页：按次行规格格只写「输入 2 张」；展开处 = 规格行减去「规格」格——请求数 | 单价（= 请求单价）| 输出金额 | 输入图 | 输入金额；
  与报价并存时顺序照 D2d 23b 一格不改。分组行不改。四语只新增一条 `specInputSubVideo`。
- **第 1 片** 按次行的输入侧不复用 `SpecUsage.price`（它会写单位 / 快照进输出四列），另开 `SpecUsage.inputsOnly` 与共享的
  `chargedInputImages`：输出四列留空，`UsageSpecBilling.fromMap` 对「只有输入三列非零」的行本来就返回非 null，读回即有 `inputCost`。
- **第 3 片** `VideoJobProtocol.submit` 的返回类型改成 `VideoSubmission`，五个协议一起改（编译器把漏网的都点出来）；
  Veo 的张数从 `prepareVeoPayload` 的产物里数（`veoInputImages`），不改那个函数的签名。
  新走线测试 `video_input_images_test.dart`：xAI / OpenAI Videos / 百炼 / MiniMax 各一条（含读不到的附件与首帧互斥），
  Veo 一条纯函数，加一条 `LLMService.startLongRunning` 端到端——提交行 `spec.inputImages == 2`、`cost == 0.10`（正是实测账单）。
- **第 4 片** `settleVideoUsage` 拆成两段独立的尽力而为（秒数 → `updateSpecBilling`，报价 → 新的 `updateReportedCost`），
  各自 try：一段失败不阻塞另一段（测试钉了两个方向）。`videoDoneEnvelope(reportedCost:)` 用 images 面同一个 `reportedCostKey`，
  执行器用 `reportedCostOf(done)` 读，不另起键。
- **第 5 片** 输入图行抽成 `SpecInputImagesBlock`（`spec_rate_table.dart` 内，与 `_PriceField` / `_Hint` 同文件），
  表与按次分支共用；`_inputImagesText` 的「免费」判据在按次行一律视为已交付。截图（`usage_desktop_light_addRequest.png`）：
  按次编辑器的行落在提示句下、单价框与请求字段右缘对齐，无溢出；卡片「按次计费 · 图片」带「输入图 $0.01/张」标签。
