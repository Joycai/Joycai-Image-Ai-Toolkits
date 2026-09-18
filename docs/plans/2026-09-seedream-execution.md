# Seedream（火山方舟）生图接入 · 执行清单

> 分支 `claude/seedream-image-model-support-f4e87c`。一片一个 commit，片号写在
> commit body 里；每个阶段结束跑一次 `/code-review high <range>` 并修完再往下；
> 最后 bump minor（4.10.0）开 PR。协议事实在
> [`../api/volcengine-ark.md`](../api/volcengine-ark.md)，本文只写本项目的取舍。
> 设计稿：Claude Design 项目 `925a4d48…` 的新文件 **`D1e 火山方舟 · Seedream`**
> （新字母文件，不合并进 D1b / D1c，避免整文件重写截断旧 section）。

## 决策记录

1. **一个 vendor + 一个 protocol，不加 `ProtocolFamily`。** 方舟 chat 面是
   OpenAI 兼容（`/api/v3/chat/completions`），所以 `Vendors.volcengineArk`
   family = `openai`、bearer；生图面是方舟自己的 body，住在与 OpenAI Images
   同形的路径上，是一个 openai 家族下由 vendor 选择的替代协议——和 xAI 的
   `xaiImages` 同一类。判据（llm-three-layer「新增协议家族要不要动 Layer 3」）：
   auth / discovery 形状都没变。
2. **Layer 3：新 family `seedreamImage`**，按 id 含 `seedream` 分类（分类只在
   `model_family.dart`）。五张表：5.0 pro · 5.0 lite · 4.5 · 4.0 · 3.0 t2i，
   外加协议兜底表（`forProtocol(arkImages)`，给 `ep-…` 这类认不出的 id）。
3. **尺寸 = 档位 + 宽高比两个控件。** 档位必发（每个模型都有合法档位，不留
   `not_set`）；宽高比 `not_set` = 只发档位、由提示词决定比例，选了比例 =
   按该模型文档的映射表发精确 `WxH`。映射表是模型知识，挂在
   `ModelCapabilities.tierPixelSizes`，协议只查表不认模型。
4. **水印显式发、默认关。** 上游默认 `true` 且照常计费；本项目用户是出图的
   人，文档示例也全写 `false`。做成「水印 关 / 开」两段，永远发——与 wan3 的
   计费音频开关同一原则（明发，不继承上游默认）。
5. **组图 = 「组图上限」下拉 1–15**（1 = 关闭，不发 `sequential_*`）。只有
   lite / 4.5 / 4.0 的表声明它。参考图 + 上限 > 15 时协议收紧上限并 WARN。
6. **5.0 pro 的三种玩法收成一个「任务」三段控件**：生成 / 拆图层 / 透明编辑。
   两种特殊模式互斥且都要求恰好 1 张参考图，做成三个独立开关会出现非法组合。
   前置条件不满足时**在发请求前**报错（不花钱）。拆图层时宽高比不生效（档位只
   收 1K/1.5K/2K/auto）；透明编辑强制 png。交互编辑没有字段，靠提示词里的
   `<bbox>` / 参考图标记，不需要控件。
7. **中转站：认得出的 Seedream id 走方舟 body。** 与 grok-imagine 在中转上走
   Images API 同一先例（`_familyRoute` 的 ① 分支按 family 定 auto）；路径
   `{base}/images/generations` 与 OpenAI Images 同形，所以在中转 host 上推出
   的路径有意义——这正是「中转站不提供厂商原生协议」那条规矩的理由不成立的
   情形，记进 llm-three-layer。仍可点单回「对话出图」/ Images API。
   此前 Seedream id 分类为 `other`（对话面），标成图像类型的行 auto 走对话出
   图——对话面画不了 Seedream，这一挪是修正，不是回归。
8. **计费按张**：`metadata.image_count` = 实际落盘张数；方舟的 `output_tokens`
   不映射成 token 用量（方舟按张计价，映射过去会让按 token 的费用组算出假钱），
   原样放在 `ark_usage` 下留档。
9. **超时随组图上限放宽**：单发出图面 5 分钟起，`maxImages` 每多一张 +40 s，
   封顶 15 分钟（组图 15 张 4K 是分钟级的同步请求）。
10. **发现**：实测套餐 base 的 `GET /models` 是 404（按量 base 未能用套餐 key 验证）。
    vendor 声明 Seedream 目录为 `unlistedModels`：按量四款带日期 id + 套餐两款
    `doubao-seedream-5.0-pro` / `-5.0-lite`，副行写明属于哪种接入；404 时退回目录、成功时合并。
12. **两种接入 = 一个渠道类型的两个向导变体**（按量付费 `/api/v3`、订阅套餐
    `/api/plan/v3`）：key 互不通用、路径相同，区别只在 base，所以不拆 vendor——
    与 MiniMax / NewAPI 的变体同一句法，但两项的 `channelType` 相同。
13. **分类认两种版本拼写**：`5-0` 与 `5.0`（套餐用点号、回显不带日期），以及
    `5-0-lite` / `5.0-lite` / 不带 lite 的 `5-0-2601xx` 都是 5.0 lite。
11. **不做（记进台账「还欠的」）**：流式（`stream: true`，逐张推送）、联网搜索
    之外的 `tools`、图层的 `bounding_box` / `z_index` 落库与画布还原、Seedance
    视频面、方舟 chat 面的 `thinking` 方言（未经文档核实）。

## 切片

| # | 阶段 | 内容 | 主要文件 | 验收 | 状态 |
| --- | --- | --- | --- | --- | --- |
| S0 | A 调研 | 协议事实文档 + 本清单 | `docs/api/volcengine-ark.md`、本文件 | 文档齐 | ✅ |
| S1 | A 设计 | Claude Design `D1e`：向导预设行、模型编辑协议区、工作台四张参数表、手机 | 设计项目 | 稿已推送、规格汇总齐 | ✅ |
| S2 | B Layer 3 | `ModelFamily.seedreamImage` + 分类 + 六张表 + `tierPixelSizes` | `model_family.dart`、`model_capabilities.dart`、`model_capability_tables.dart`、`model_descriptor.dart` | 单测：分类、每表参数、映射 | ✅ |
| S3 | B Layer 1 | `ArkImagesProtocol` + `ark_payload.dart`（纯函数 body 构造 / 响应解析）+ `WireProtocol.arkImages` 与它的穷尽消费点 | `protocols/ark_*.dart`、`vendor_profile.dart`、`wire_protocol_labels.dart` | 单测：body 逐字段、组图收紧、任务前置条件、单张失败、全失败 | ✅ |
| S4 | B Layer 2 + 路由 | `Vendors.volcengineArk`、dispatcher（菜单 / auto / 生成 / 单发 / 计费 / 超时）、目录 | `vendors.dart`、`llm_dispatcher.dart` | 路由单测：方舟、中转、点单、未识别 id、本地 HTTP 端到端 | ✅ |
| — | B review | `/code-review high` S2..S4 | | 发现全修 | ⏳ |
| S5 | C 渠道 | 向导预设「火山方舟」+ 标题 / 副标题 / 类型名 + 协议名 / 路径 / 说明 + l10n 四语 | `channel_provider_presets.dart`、`wire_protocol_labels.dart`、`l10n/src/*` | 截图：向导 | ⏳ |
| S6 | C 参数 | 工作台参数标签与选项、编辑器参数摘要 + l10n 四语 | `model_selection_section.dart`、`model_protocol_section.dart` | 截图：工作台 Seedream 四表 | ⏳ |
| — | C review | `/code-review high` S5..S6 | | 发现全修 | ⏳ |
| S7 | D 收尾 | llm-three-layer 一节、CLAUDE.md、台账行、退役本清单；bump 4.10.0；PR | docs、版本文件 | 两道门绿 | ⏳ |

## 施工记录

（每片落地时追加偏离与发现。）

- **S1**：用户中途给了套餐 key 与 `…/api/plan/v3`。实测推翻了两处草案：方舟有两个 base
  且 key 不通用（→ 向导加「接入方式」两段，决策 12），套餐只认 5.0 两款、`lite` 拼写有讲究
  （→ 目录与分类，决策 10、13）。设计稿 D1e 3a 已按此改。工作台控件名沿用既有的「尺寸」
  （Gemini 的 1K/2K/4K 档位同一个 labelKey），不另造「分辨率」。
- **S2**：`WireProtocol.arkImages` 与 descriptor 的 `servedBy` 挪到 S3——枚举一加，
  标签表等穷尽 switch 全要跟，放在协议那片里一次补齐，每片都能单独编译。
  顺带补了一个既有的缺口：按规格计费的条件选单只收 family / 协议两类表，
  `forModel` 按 id 才走到的表（gpt-image-2 的像素、Seedream 的 1.5K / 3K……）
  一直不在里面；Layer 3 新出 `ModelCapabilities.idRoutedTables`，选单并进来，
  排序与 `OutputSpec.normalizeSize` 认小数档位（`1.5k` → `1.5K`）。
- **S3**：协议名按既有惯例叫「火山方舟图像」（与「MiniMax 图像」「xAI 图像」同构），
  不是设计稿草拟的「火山方舟生图」——C 阶段回写 D1e。路径标签不带版本前缀
  （`/images/generations`）：方舟是 `/api/v3` 或 `/api/plan/v3`，中转是 `/v1`。
  元数据不发布 `output_size`：按规格计费的档位行写的是 `2K`，回显的 `WxH` 会让它们一行都匹配不上。
- **S4**：中转菜单里方舟 body 排第一，靠 `_familyMediaSurfaces` 多收一个模型 family 参数
  （认得出的 Seedream 才加）——没有动「auto 不在菜单里就追加到末尾」的通用规则，其它
  vendor 的菜单次序一个不变。「每个 vendor 都有名字」与「目录持有者白名单」两条既有测试按预期
  报出，渠道类型名（`providerVolcengineArk`）提前到本片补上，白名单加方舟并写明理由（套餐 404
  实测）。**实机**：套餐端点、5.0 lite、2K + 16:9、水印关，经 `LLMDispatcher.generate`
  一次出图 26 s，2848×1600（= 表里的映射），右下角无水印；`ark_usage.output_tokens` 17800
  = 2848×1600/256。
