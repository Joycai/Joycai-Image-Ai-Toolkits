# 上游报价：直接读 xAI 回报的 `cost_in_usd_ticks`

**分支** `claude/xai-reported-cost` · **设计稿** `D2d 用量-上游报价`（Claude Design 项目）
**性质**：方案 + 执行清单。一片一个 commit，状态与施工记录写在本文件里；收尾片把结论搬走后本文件删除。

---

## 0. 为什么

xAI 的 Images API 在每个回包的 `usage` 里写明**这次请求实扣了多少钱**（`cost_in_usd_ticks`，1 tick = $10⁻¹⁰，
`api/usage.md` §5 两轮实测）。它比任何档位表都准：`auto` 质量由模型定档、档位表写不出；用户抄错一格、
上游调价、参考图张数——上游一句话全对上。应用今天把这个字段**原样落在 metadata 里然后不看**，仍按计费组的
档位表算钱。台账「还欠的」里的「xAI 的 `cost_in_usd_ticks`」就是这一条。

## 1. 事实

- xAI images 协议（`xai_images_protocol.dart`）已把 `data['usage']` 整个铺进 `LLMResponse.metadata`，
  所以 `metadata['cost_in_usd_ticks']` 对 `/images/generations` 与 `/images/edits` 都已经在。
- 数值含**输出 + 输入图**两部分（$0.06 + 5 × $0.01 = 1 100 000 000），所以它压过的是档位表的**两侧**，不是叠加。
- **2026-09-22 补测**：`/images/edits`，1 张参考图，`quality: low`，`n: 2` → 200，两张图，
  `900 000 000` = $0.09 = 2 × $0.04 + **1** × $0.01。输入图**按请求收一次，不乘输出张数**
  （台账「输入图 2」定论：应用「每次请求收一次」是对的）。
- 失败 / 被审核拦下的请求在应用里根本走不到记账（协议抛 `LLMApiException`，`_recordUsage` 只在响应返回后跑），
  所以「失败是否仍收输入费」这一条读回包解决不了，仍只能对账单（台账「输入图 3」不动）。
- 只有 xAI 自家 vendor 的 image 菜单含 `WireProtocol.xaiImages`（`vendors.dart:222`，`llm_dispatcher.dart:783`）；
  中转站上的 grok-imagine 走 OpenAI Images 协议。所以「xAI 自家协议回报的价」= 用户直接付给 xAI 的价。

## 2. 设计

### 2.1 协议层发布一个中性键（`xai_images_protocol.dart`、`output_spec.dart`）

- 与 `output_size` / `input_image_count` 同一做法：协议把 vendor 的原始字段翻成一个 vendor 无关的 metadata 键
  **`reported_cost_usd`**（`reportedCostKey`，double，美元），`cost_in_usd_ticks / 1e10`。原始键照旧铺着（日志要看）。
- 只在 `usage.cost_in_usd_ticks` 是有限、非负的数时发布；别的形状不发（不猜）。
- 读口 `reportedCostOf(metadata) → double?` 放在 `output_spec.dart`，与 `inputImageCountOf` 并排；
  `LLMService` 只认这个键，不认 `cost_in_usd_ticks`——分层：单位换算是 layer 1 的事。
- 中转的 OpenAI Images 协议**不**翻这个键：中转有自己的价，用户填的档位表才是他付的钱。
  接受的边界：把 xAI vendor 指到一个原样转发 `usage` 的中转——那时报的是 xAI 收中转的价。不加开关。

### 2.2 用量行多一列：`token_usage.reported_cost`（v49）

- `REAL`，无默认（NULL = 上游没报）。`onUpgrade` + `onCreate` 同步（`_createV49Columns`）。
- `TokenUsage.reportedCost: double?`，`fromMap` / `toMap` 走 `_double` 的宽松读法（v48 那一套：错类型的格读作缺失）。
- 记账（`llm_usage_recording.dart`）：`reportedCost: reportedCostOf(metadata)`，**不看计费模式**——
  按 token 的组（默认组、$0）挂着 xAI 出图模型时今天记 $0，有了报价就记对；按次 / 按规格同理。
- 档位表那一侧**照旧写**（`spec` 七列不变）：行上同时留着「上游报了多少」与「表算出多少」，两者不同就是档位表该改的信号。
- `UsageRepository.updateSpecBilling`（视频 settle）只写输出四列，不碰这一列——xAI 视频本来也不报价。

### 2.3 算钱：报价压过一切（`token_usage.dart`）

- `UsageCostParts` 加一项 **`reported`**。`reportedCost != null` 时：其余六项全 0，`reported = reportedCost`；
  `cost` 求和照旧。上游说 0 就是 0（按 D2c 的口径：一张没交付的请求本来就不收）。
- `unmatched`：有报价的行**不算**未匹配——「档位表没覆盖」的提示是让人去补表，报价在手就没这个缺口。
- `specLabel` 不变：规格列照常写 `1K · low · 输入 1 张`。

### 2.4 用量页（设计稿 `D2d`）

- `GroupUsage.reportedCost`：分组条上与 request / spec 同一中性色（都是买输出的钱）；tooltip 里自己一行。
- 明细行展开：一行「上游报价 $0.0700」；档位表那两行（输出金额 / 输入金额）保留，变为次要（灰）——
  这是「表 vs 实扣」的对照面。收起态的费用格显示报价；要不要标记（一个小字形 / 副标）由稿定。
- 手机 / 平板 / 桌面三种表单同一规则。
- 四语新文案预计两条：`usageReportedCost`（上游报价）、`usageTableEstimate`（档位估算）——以稿为准。

### 2.5 不做

- 其它 vendor 的报价字段（方舟不报钱、OpenAI 不报钱）；按 token 的报价对照（没有用例）。
- 计费组级「信任上游报价」开关（§2.1 的边界接受）。
- 币种：应用一律 `$`，xAI 恰是美元；键名把 `usd` 写死，别的币种来了再说。

## 3. 执行清单

| 片 | 内容 | 主要文件 | 验收 | 状态 |
|---|---|---|---|---|
| 0 | 补测 `n:2` 的输入费 | — | §1 | ✅ |
| 1 | 本文件 + 设计稿 `D2d` | `docs/plans/`、Claude Design | — | ✅ 帧 23a–23f |
| 2 | 协议发布 `reported_cost_usd`；`reportedCostOf` | `output_spec.dart`、`xai_images_protocol.dart` | 走线测试：`600000000` → `0.06`；缺失 / 非数不发 | ✅ |
| 3 | v49 列 + `TokenUsage.reportedCost` + `costParts.reported` + `unmatched` | `database_migrations.dart`、`token_usage.dart` | 往返、报价压过三种模式、未匹配不再计 | ✅ |
| 4 | 记账读键（三条路径共用 `_writeUsageRow`） | `llm_usage_recording.dart` | `recordUsageForTest` 带键 → 行上有值；不带 → NULL；spec 七列照写 | ✅ |
| 5 | 用量页：分组条 / tooltip / 明细行 / 费用格；四语；截图夹具加一行报价 | `usage_stats.dart`、`usage_group_costs.dart`、`usage_list.dart`、`l10n/src/*/metrics.arb`、`fixture_seed.dart` | widget 测试 + 截图 | ✅ |
| 6 | 文档：`api/usage.md` §5、`llm-three-layer.md` metadata 键、台账两行；bump 4.27.0 | `docs/`、七处版本号 | — | ✅（台账在收尾片） |
| 7 | 独立 review（opus）→ 修 → 再 review，直到无新问题；PR | — | 两道门全绿 | ⬜ |

## 4. 设计 brief（交给 Claude Design 项目的原文）

> 在项目 `925a4d48-684e-4733-bca2-1aa808b7e18f` 新建一份 `D2d 用量-上游报价.dc.html`（自成一份，不要改写
> `D2` / `D2b` / `D2c`——这个工具会整文件重写并丢掉旧 section）。先读 `D2c` 里明细行展开的六格网格（22f / 22g）
> 与规格列的写法、`D2b` 的分组条与 tooltip；新稿是 D2c 明细行的增量，几何、token、控件一律沿用。
>
> **要解决的事**：xAI 在每个出图回包里报这次请求实扣的美元数（含输入图）。应用要把它记到用量行上，
> 并**压过**计费组档位表算出的数。用量页要能看出：① 这一行的钱是上游报的，不是表算的；② 表算的是多少
> （对不上就是档位表该改）；③ 分组条的 tooltip 里「上游报价」自己一行；④ 有报价的行不再算「档位表未覆盖」。
>
> **要出的帧**（桌面 1440 为主，平板 834 与手机 390 各一帧；暗色至少一帧）：
> 1. 用量明细一行收起态：费用格 `$0.0700` 要不要带标记（字形 / 副标 / 不带），与旁边表算的行对照。
> 2. 同一行展开：六格网格里「上游报价」放哪、档位表的「输出金额 / 输入金额」怎么退为次要；
>    表算与报价不等（表 $0.06 · 报 $0.07）和相等两种。
> 3. 分组条 tooltip 多一行。
> 4. 末尾 mono 规格汇总：顺序、字号、颜色 token、四语文案（中文为准附 en / zh_Hant / ja）。
>
> **词汇**：用本应用的 `App*` 组件名与 `UsageDot` / `_kindPlate` 等现有部件名，不要标 Material 组件名。
> 审美：Apple 式干净、主次分明；报价是主，表算是次。

## 5. 施工记录

- **第 0 片** `n:2` 探针见 §1。
- **第 1 片 · 设计稿 `D2d`**（设计子代理拿不到 DesignSync，稿子由主会话对照真实 `D2c` 的类词汇校验后推送，75 317 字节）：
  四条裁决——① 收起态费用格**不带任何标记**（无字形、无副标、无颜色）：最可信的数字不能长得像可疑的那个，
  只有部分行带字形会打断右对齐的扫读；桌面 / 平板的费用格加一个两行 `Tooltip`「上游报价 / 档位估算」，手机不加。
  ② 展开网格**第一对**是「上游报价（onSurface）| 档位估算（outline）」，其后原顺序不动；凡是档位表**算出来**的值
  （档位估算、单价、输出金额、输入金额）一律退为 outline，请求**事实**（请求数、规格、输入图张数）照旧；
  不写「档位表过期」的句子、不用警示色——这一行上不一致是常态（`auto` 由模型定档），退色的一对就是全部信号；
  相等时几何相同；档位估算永不隐藏（按 token 的默认组下就是 `$0.0000`）。③ 分组条：报价并入 request / spec 的
  中性段，tooltip 末尾多一行「上游报价」（>0 才出现）；「档位表未覆盖」的提示靠 `unmatchedCount` 的定义自动排除报价行，
  `UsageGroupCosts` 本身不改。④ 三种表单共用同一个 `pairs` 列表，手机展开为单列。
  四语：`usageReportedCost` 上游报价 / Reported cost / 上游報價 / 上流の請求額；`usageTableEstimate` 档位估算 /
  Table estimate / 檔位估算 / 料金表の見積。实现与稿一致，无出入。
- **第 3 片** `TokenUsage.snapshotCost` 不在方案里：明细行要写「档位估算」，就得把报价拿掉再算一遍——
  用同一行的其余字段重建一个没有报价的 `TokenUsage` 取 `cost`，算式只有一份。
- **第 5 片** 用量页截图（`usage_desktop_light.png`）：两条 xAI 行按报价显示 $0.0400 / $0.0500，分组行 $0.0900 · 2 张 · 2 次，
  没有溢出。
- **Review 第一轮（opus）** 无 BLOCKER / MAJOR，两条 MINOR + 三条 NIT：① xAI 出图走 `requestStream`（单发流），报价只在收尾块上——
  流在出图后被放弃时，兜底记账拿不到它、退回档位表。与 `input_image_count` 同一处理：`_asChunks` 把 `reportedCostEntry`
  也挂到每个图片块上（走线测试钉住图片块带 0.06）。② 「中转协议不翻这个键」只是说说：五处把上游 `usage` 原样铺进 metadata，
  上游若恰好有个字段叫 `reported_cost_usd` 就直接成了记账数。加 `upstreamUsage()`（`protocol.dart`）统一做 cast 并剔掉这个保留键，
  五处都改走它；只有协议自己的换算能写这个键（xAI 走线测试：上游伪造 99 → 仍记 0.06；只伪造不带 ticks → 不记）。
  ③ `reportedCostFromTicks` 注释里的复数是假的（只有一个调用者）——改。④ `updateSpecBilling` 不碰 `reported_cost` 没有测试钉——
  `usage_and_task_repository_test` 加一条。⑤ 台账两行的 `git show <sha>` 占位——收尾片填。
- **Review 第二轮（opus，只查第一轮那一个 commit）** 一条 MINOR + 一条 NIT：① 第一轮只堵了五处，聊天面还有三处原样铺 `usage`
  （百炼 chat 流式面、④ `anthropicUsageMetadata`、③ `parseGoogleChunks`）——记账对所有 vendor 都读这个键，聊天路由上的中转同样能
  伪造。三处都改走 `upstreamUsage`，纯函数各钉一条（`upstream_usage_sites_test.dart`）。② `upstreamUsage` 的注释写「保留键」是复数、
  只剔一个：`input_image_count` 同样是应用自己的结论、同样可伪造（文生图不发布这个键，伪造的会活下来、按规格组收根本没发的参考图）——
  一起剔。方舟走 `sentInputImages(reported: usage['input_images'])` 读的是 vendor 字段，不受影响。
- **Review 第三轮（opus，只查第二轮那一个 commit）** 一条 NIT（只改注释）：`parseGoogleChunks` 的文档还说 `usageMetadata`「原样」带过去——
  现在剔了两个保留键。六项核对（方舟的 `input_images` 走 vendor 字段不受剔键影响；三家 images 协议的 `sentInputImages` 都在铺之后、
  last-wins 仍发布张数；③ 非 Map 的 `usageMetadata` 由运行时 TypeError 变成 null；④ `usage == null` 结果同前；无 import 环；
  `lib/services/llm/` 下再无原样铺；百炼流式逐帧覆盖仍对）全部通过。
- **Review 第四轮（opus，只查第三轮那一个 commit）** 一条 MINOR + 一条 NIT，都在三层文档的新段落：① 「images 协议在各自的走线测试里钉」
  夸大了——只有 xAI 钉了伪造用例，OpenAI Images（正是中转会走的那条）与 MiniMax 没有。不改文档改测试：`input_image_count_test.dart`
  给这两家各加一条伪造 `usage` / `metadata` 的走线用例，文档改成点名三个文件。② 不变量 ② 只点名 `_asChunks`，同段的
  `input_image_count` 写的是「凡是自己造 `imagePart` 块的地方」——改成同一措辞，把方舟 SSE 与 Midjourney 的 controller 列为
  「哪天也报价就同样要带」。
