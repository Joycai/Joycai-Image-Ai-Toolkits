# 输入图计费：按规格计费组补上「输入」一侧

**分支** `claude/input-image-billing` · **设计稿** `D2c 计费组-输入图计费`（Claude Design 项目）
**性质**：方案 + 执行清单。一片一个 commit，状态与施工记录写在本文件里；收尾片把结论搬走后本文件删除。

---

## 0. 为什么

两家按张计费的图像模型，除了输出图还收**输入图**的钱，应用现在一分都没记：

| 模型 | 输入图 | 输出 | 出处 |
|---|---|---|---|
| xAI `grok-imagine-image-2.0` | **$0.01/张** | 分辨率 × 质量：1K·Low $0.04 … 2K·Medium $0.08 | docs.x.ai/developers/models/grok-imagine-image-2.0（2026-09-21） |
| 火山方舟 Seedream 5.0 pro | **0.02 元/张，首张免费** | 0.3 元/张（输出图 ≤261 万像素） | 方舟控制台模型详情页（2026-09-21） |
| GPT-Image-2 | token：图像输入 $8/M（文本 $5/M，缓存图像 $2/M） | 图像输出 $30/M | OpenAI pricing |
| Gemini 3 Pro Image / 3.1 Flash Image | token，文本与图像同价 $2/M / $0.50/M | token，折合 1K/2K $0.134、4K $0.24 | Gemini API pricing |

后两家的输入图已折进 `input_tokens`，按 token 模式本来就覆盖。前两家走按规格模式（`billing_mode = 'spec'`），
而 `SpecUsage.price` 只匹配输出规格、`TokenUsage.costParts` 的 spec 分支只算 `output_units × output_unit_price`
——每次改图都少记钱。

**不做（第二期，未立项）**：按 token 模式给图像输入单独定价（只有 GPT-Image-2 的 $8 对 $5 受益）；计费组币种
（应用一律显示 `$`，Seedream 以人民币计价，是已有问题）。

## 1. 设计

### 1.1 计费组：两个字段，不开新模式、不做输入档位表

`fee_groups.input_unit_price REAL DEFAULT 0.0`、`fee_groups.input_free_units INTEGER DEFAULT 0`
→ `PricingGroup.inputUnitPrice` / `inputFreeUnits` → `LLMModelConfig.inputUnitFee` / `inputFreeUnits`
（沿 `llm_config_resolver.dart` 搬 `outputUnit` / `outputRates` 的同一条路）。

一次请求的输入费 = `max(0, n − free) × price`。xAI 填 `0.01 / 0`，Seedream 填 `0.02 / 1`。
没有哪家按输入图的尺寸分价，所以不做表；出现了再加。只对按规格模式有意义，其余两种模式忽略、但编辑时保留
（和 `outputRates` 同一条规矩）。

### 1.2 `n` = 实际发给上游的参考图张数

- 六个 images 协议先按 `maxReferenceImages` 截断，**之后还会逐张读文件、读不到就跳过**
  （`ark_images_protocol.dart`、`xai_images_protocol.dart` 等）。所以「截断后的张数」≠「发出的张数」。
- 截断逻辑抽成一个共用函数（消掉六份重复）；**张数由各协议在组完请求体后按实际放进去的条数**写
  `metadata['input_image_count']`。与 `output_size` 回显对称，流式收尾块也带得到。
- 火山方舟 5.0 pro 自己回报 `usage.input_images`——**上游回报优先于本地计数**（与输出尺寸回显同理）。
  2026-09-21 实测：pro 发两张参考图 → `usage = {input_images: 2, generated_images: 1, …}`，是**原始张数**，
  免费张数由应用扣；lite 不回报这个字段（它也不收输入费）。
- 聊天面（①③④）不写这个键 → 读作 0。按 token 计费的 Gemini / OpenAI 本来就该是 0；
  「聊天面中转站 + 按张收输入费」会漏记，没有真实用例，挂进「还欠的」。

### 1.3 用量行：快照进 `UsageSpecBilling`

`token_usage.input_images INTEGER DEFAULT 0`（**实际发出的张数**，明细页显示用）、
`input_units REAL DEFAULT 0.0`（**扣掉免费后的计费张数**）、`input_unit_price REAL DEFAULT 0.0`。
（初稿把原始张数放进 `output_spec` JSON；视频结算会整列改写它，改成单独一列——见 §5。）

- `UsageSpecBilling` 加 `inputUnits` / `inputUnitPrice` / `inputCost`；`cost` 仍只是输出部分。
- `UsageCostParts` 加 `specInput`；`TokenUsage.costParts` 的 spec 分支填它，`TokenUsage.cost` 把它加进去。
- `UsageSpecBilling.fromMap` 的「全空 → null」判断把三个新列算进去。
- **`toMap()` 拆成输出四列与输入三列**：`UsageRepository.updateSpecBilling`（视频结算改写）只写输出四列，
  提交时记下的输入列不会被清零；新建行仍写全七列。不用「先读再写回」——那会引入读写竞争，
  而且 `settleVideoUsage` 是尽力而为的，读失败就整个跳过。
- 旧行三列为默认值 0，金额不变。

### 1.4 计价规则

- `SpecUsage.price` 增加 `inputImageCount` / `inputUnitPrice` / `inputFreeUnits`。
- **响应里没有图片就不计输入费**（Seedream 明文写失败不计费；xAI 没说，同一条规则）。单位为「秒 / 条」
  （视频）的组不收输入费（§5 的裁决，判据写在 `SpecUsage.price` 一处，`PricingGroup.chargesInputImages` 是它在界面侧的同一句话）。
- 「首张免费」**按每条用量记录扣一次**。批量任务一张图一个请求、失败重试是新请求，都各自扣一次。

### 1.5 界面（设计稿 `D2c`）

- 计费组编辑器，按规格模式：档位表与优先级说明**之后**一行「输入图 · 免费张数 + 单价」，只在单位为「张」时出现（§5）。
- 计费组摘要（`feeGroupSummary` / 价格标签 / 悬浮表）：带上「输入 $0.01/张 · 首 1 张免费」。
- 用量页：分组行的金额包含输入费；明细的规格列带出输入张数；明细展开处分列输入 / 输出。
- 四语一起改。

## 2. 三处文档没写、只能对账单的细节

挂进 `docs/plans/README.md` 的核实清单：

1. Seedream「首张免费」是否按每次请求——先按每次请求。
2. 一次请求出多张图（Seedream 组图、xAI `n>1`）时输入图收一次还是乘张数——先按收一次。
3. xAI 请求失败是否仍收输入费——先按不收。

## 3. 执行清单

| 片 | 内容 | 主要文件 | 验收 | 状态 |
|---|---|---|---|---|
| 0 | 实测 `usage.input_images` 口径 | — | 见 §1.2 | ✅ 原始张数 |
| 1 | 本文件 | `docs/plans/` | — | ✅ |
| 2 | 模型 + v48 迁移：`PricingGroup`、`UsageSpecBilling`（含 `toMap` 拆分与 `inputImages`）、`UsageCostParts.specInput`、`updateSpecBilling` 只写输出列 | `models/pricing_group.dart`、`models/token_usage.dart`、`db/database_migrations.dart`、`db/repositories/usage_repository.dart` | 迁移测试（v47→v48、幂等、旧行金额不变）；`token_usage_test`；结算后输入列不变 | ✅ |
| 3 | 计价：`LLMModelConfig` 两字段、resolver、`SpecUsage.price`、`specUsageFor` 读 `input_image_count` | `billing/spec_billing.dart`、`llm/llm_model_config.dart`、`llm/llm_config_resolver.dart`、`llm/llm_service.dart` | 免费张数扣减、零出图不计、聊天面读作 0 | ✅ |
| 4 | 共用截断函数；六协议写实际发出张数；方舟优先 `usage.input_images` | `llm/protocols/*_images*_protocol.dart` | 每协议一条「附件读不到 → 张数减少」；方舟回报优先 | ✅ |
| 5 | UI：编辑器、摘要、用量页；四语 | `widgets/models/*`、`screens/metrics/widgets/*`、`l10n/src/*` | widget 测试；截图三档宽度无溢出 | ✅ |
| 6 | 文档：`docs/api/` 定价与 `input_images` 实测、核实清单、台账行、本文件退役、设计稿回写出入 | `docs/` | — | ☐ |
| 7 | 独立 review（opus）→ 修 → 再 review，直到无新问题；bump version；PR | — | 两道门全绿 | ☐ |

## 4. 设计 brief（交给 Claude Design 项目的原文）

> 在项目 `925a4d48-684e-4733-bca2-1aa808b7e18f` 新建一份 `D2c 计费组-输入图计费.dc.html`（自成一份，不要改写
> `D2` / `D2b`——这个工具会整文件重写并丢掉旧 section）。先读 `D2b 计费组按规格计费` 与 `D2 用量统计` 的帧和
> 末尾的 mono 规格汇总，新稿是 D2b 的增量，几何、token、控件一律沿用。
>
> **要解决的事**：按规格计费组除了「输出单位 × 档位表」，再加「输入图」一侧——每张输入图的单价，和每次请求
> 免费的张数（Seedream 5.0 pro：0.02/张、首张免费；xAI grok-imagine-image-2.0：$0.01/张、无免费）。
> 只有两个标量，**不是第二张表**。大多数计费组不收输入费，默认态必须安静：不填就等于没有这回事。
>
> **要出的帧**（桌面为主，每组补一帧手机；暗色至少一帧）：
> 1. 计费组编辑器 · 按规格模式：输入图一行放哪、长什么样（与单位 chip、档位表的主次关系）；空态 / 已填 /
>    只填了免费张数没填单价（无意义，怎么提示）三态。
> 2. 计费组卡片与摘要：`feeGroupSummary` 一行、价格标签、悬浮的档位表里，输入费怎么并进去。
> 3. 用量页：分组行（金额已含输入费，数量列要不要带输入张数）、明细表的「规格」列（如 `2K · 输入 3 张`）、
>    明细展开处输入 / 输出分列的金额；全免（如只发 1 张且首张免费）时怎么写。
> 4. 末尾 mono 规格汇总：尺寸、间距、token、文案（中文为准，附 en / zh_Hant / ja）。
>
> **词汇**：用本应用的 `App*` 组件名（`AppSegmentedControl`、`AppTextField`、档位表用的 `SpecConditionField` /
> `_PriceField`、chip、玻璃 Float），不要标注 Material 组件名；只有没有封装时才写原生 Flutter 控件。
> 审美：Apple 式干净、主次分明、去杂，输入图一行是次要信息。

## 5. 施工记录

- **第 2 片** 原始张数不进 `output_spec` JSON，单独成列 `token_usage.input_images`：视频结算会整列改写
  `output_spec`，放在里面会被顺手抹掉。所以 v48 给 `token_usage` 加的是三列，不是两列。
- **第 3 片** 全免的请求（只发 1 张且首张免费）仍把计费组的单价记在行上、计费张数记 0——用量页靠行上的
  单价分清「免费」与「这个组不收输入费」。
- **第 4 片** 共用函数只管截断（`capReferenceImages`）；张数走另一个 `sentInputImages(sent, reported:)`，
  方舟的上游回报优先级写在这一个函数里。百炼异步协议没有走线测试（轮询间隔 3 秒），由共用的
  `dashscopeImageMetadata` 单测覆盖。
- **Review 第一轮（opus）** 无 BLOCKER / MAJOR；修了：① 流在出图之后、收尾块之前被放弃时输入费记 0
  ——每个图片块现在都带张数（`inputImageCountEntry`；`_asChunks` 与方舟 SSE）；② Midjourney 也往请求体里放
  参考图（`base64Array`）却不发布张数——补上，成为第七个；③「只有按张的组收输入费」原先只在 resolver 一处
  把关，`SpecUsage.price` 自己会给按条 / 按秒的组收费——判据搬进 `SpecUsage.price`；④ 英文「3 in」像英寸，
  改「input ×3」；⑤ 免费张数框限长 2 → 3（字段从库里的值打开，能显示却不能重打是陷阱）；⑥ 补了备份往返、
  提前退出计费两条测试，给「其他规格」价格框加 key 让对齐测试不会自己比自己。
- **Review 第二轮（opus）** 无 BLOCKER / MAJOR；修了：① 第一轮「每个图片块都带张数」漏了 Midjourney——它自己造
  图片块，不走 `_asChunks`；② 方舟 SSE 上，上游回报的 0 压不住图片块带的本地张数（`sentInputImages` 对 0 不发键，
  合并又不会丢键）——回报的 0 改为明发；③ 明细展开处把「请求没交付所以没收费」的图说成「免费」——没交付的行
  只写张数；④ 计费组下拉的 `trailing` 没有截断，带输入费的摘要长了一倍，英文窄屏会溢出——在共用的
  `AppDropdown` 上限宽 200 + 省略号（测试确认不修会溢出 542px）。
- **第 5 片 · 设计稿 `D2c` 的裁决**（设计子代理拿不到 DesignSync，稿子由主会话对照真实 `D2b` 校验后推送）：
  - 输入图一行放在档位表与优先级说明**之后**，不是 §1.5 写的「之上」——它和「其他规格」是同一种钉住的标量行，
    D2b 的块一个像素不动。
  - **只有单位为「张」的组收输入费**（`PricingGroup.chargesInputImages`，resolver 与所有摘要共用这一个判据）。
    单位为秒 / 条时整行收起、值保留不清、不计价——与 §1.4 的出入：没有视频协议回报输入张数，
    一个永远不计费的字段只会误导。
  - 只填免费张数不填单价：提示、数字降为 outline 色、不拦保存；单价非法：红边 + 错误提示、拦保存
    （只在该行可见时校验）。
  - 明细展开处，「输入图」「输入金额」两格各占一整行：算式「2 × $0.0200 = $0.0400」在平板的半栏里放不下
    （测试抓到 32px 溢出）。稿子是六格三行。
