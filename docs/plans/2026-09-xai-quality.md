# xAI 质量档：给 grok-imagine-image-2.0 补上质量控件与 1.5K

**分支** `claude/xai-quality` · **设计稿** `A1f 参数栏-xAI 质量档`（Claude Design 项目）
**性质**：方案 + 执行清单。一片一个 commit，状态与施工记录写在本文件里；收尾片把结论搬走后本文件删除。

---

## 0. 为什么

xAI `grok-imagine-image-2.0` 的输出按 **分辨率 × 质量** 六格标价，应用只发分辨率（1k / 2k）、不发质量，
上游按默认 **Medium** 计（1K $0.06）。后果两条：

1. 想省钱的人没法选 Low（1K 便宜三分之一）；1.5K 档根本选不到。
2. 按规格计费组的档位表只能按尺寸写、填 Medium 的价——写成 `1K · low` 的行永远命不中。

台账「还欠的」里的「xAI 的质量参数」就是这一条（`docs/plans/README.md`）。

## 1. 事实（2026-09-22 实测，`XAI_KEY`，读回包 `usage.cost_in_usd_ticks`，1 tick = $10⁻¹⁰）

xAI 的 OpenAPI（`docs.x.ai/openapi.json`）里请求体没列 `quality`，但 `ImagePricingTier` 写明「Medium is the
default quality a request serves at when it leaves `quality` unset」；`GET /v1/image-generation-models/{id}` 回
`pricing[]`（`price_per_image` 单位 1e-8 美分 = tick），六格与文档页一致。实测：

| 请求（`/images/generations` 除注明外） | 结果 |
|---|---|
| `quality: "bogus"` | **422** `quality: unknown variant, expected one of low, medium, high, auto` |
| `quality: "high"` | **400** `This model only supports the following quality value(s): low, medium, auto.` |
| `quality: "low"` | 200，400 000 000 = **$0.04**（1K · Low） |
| `quality: "low", resolution: "2k"` | 200，600 000 000 = $0.06（2K · Low） |
| `quality: "auto"` | 200，400 000 000 = $0.04（这一次选了 Low；由模型决定，**不可预算**） |
| 不带 `quality`（上一轮） | $0.06（1K · Medium） |
| `/images/edits` + 1 张参考图 + `quality: "low"` | 200，500 000 000 = $0.05 = 0.04 + 0.01 |
| 初代 `grok-imagine-image` + `quality: "low"` | 200，200 000 000 = $0.02（平价，参数被默默接受） |
| 初代 `grok-imagine-image` + `resolution: "1.5k"` | **400** `1.5K resolution is not supported for this model.` |

`/v1/image-generation-models` 列表：`grok-imagine-image` $0.02、`grok-imagine-image-quality` $0.05 都是
`pricing: []`（各质量同价）；只有 2.0 有六格矩阵。

## 2. 设计

### 2.1 能力表：2.0 一张、初代一张（`model_capability_tables.dart`）

- `_xaiImage`（family 默认、`forProtocol(xaiImages)` 兜底——新版本更可能长这个样子）：
  - `aspectRatio` 下拉，不变；
  - `quality` 分段 `low | medium`，**默认 `medium`**——与上游默认相同，加控件不改变任何人今天拿到的图和账；
    `auto` 不给：它把价钱交给模型决定，档位表没法命中；`high` 上游拒绝；
  - `imageSize` 分段 `1k | 1.5k | 2k`，默认 `1k`。
- `_xaiImageLegacy`（按 id 分流：`grok-imagine-image` 与 `grok-imagine-image-quality`，`endsWith`）：
  今天的表原样（比例 + 1k / 2k），**没有质量控件**（平价模型上它是一个骗人的旋钮）、**没有 1.5k**（上游 400）。
  进 `idRoutedTables`，让 `SpecKnownValues` 照旧收全词汇。
- 参数声明顺序决定面板排版（`_spansRow`：三选一的分段占整行）：**`aspectRatio`、`quality`、`imageSize`**
  → 第一行「比例 ▾ | 质量 低/中」，第二行「尺寸 1k / 1.5k / 2k」整行。设计稿裁决。

### 2.2 协议（`xai_images_protocol.dart`）

- `quality` 读 `options['quality']`，是 `low` / `medium` 才发 `quality`（白名单，与 `resolution` 同一写法；
  `auto` / `not_set` 不发）。
- `resolution` 白名单加 `1.5k`。

### 2.3 计费：不改一行

- `OutputSpec.from(options)` 已读 `options['quality']`，默认 `medium` 明发 → 规格 `1K · medium`，
  档位表按文档六格照抄即可命中；旧的只写尺寸的行（质量留空）仍然命中（空条件匹配一切）。
- `normalizeSize('1.5k')` → `1.5K`，`specRateTierOf` 的 `_tierPattern` 认小数——早为 Seedream 5.0 pro 铺好。
- `SpecKnownValues`：`low` / `medium` 来自 OpenAI 表、`1.5K` 来自 Seedream 表，本来就在菜单里。
- 用户已存的参数记忆里没有 `quality` → resolver 给默认 `medium`，行为等于今天。

### 2.4 界面（设计稿 `A1f`）

- 工作台参数栏：xAI 2.0 的三个控件怎么排（300 宽栏与手机）；初代 xAI 不变。
- 四语：`qualityLow` / `qualityMedium` / `optionAuto` 已有；`1.5k` 与 `1k` 一样原样显示。**预计没有新文案**。

## 3. 执行清单

| 片 | 内容 | 主要文件 | 验收 | 状态 |
|---|---|---|---|---|
| 0 | 实测参数名、取值、六格与初代的差异 | — | §1 | ✅ |
| 1 | 本文件 + 设计稿 `A1f` | `docs/plans/`、Claude Design | — | ✅ 帧 4a–4g |
| 2 | 能力表：`_xaiImage` 加质量 + 1.5k，`_xaiImageLegacy` 按 id 分流 | `llm/model_capability_tables.dart`、`llm/model_capabilities.dart` | 2.0 三控件 / 初代两控件；`SpecKnownValues` 含 `1.5K`、`low`、`medium` | ✅ |
| 3 | 协议：发 `quality`，`resolution` 收 `1.5k` | `llm/protocols/xai_images_protocol.dart` | 走线测试：默认发 `medium`；`low` / `1.5k` 落到请求体；`auto` 不发；规格 `1.5K · low` 命中档位 | ✅ |
| 4 | 面板排版测试（300 栏 + 手机无溢出）；截图夹具加一个 xAI 2.0 模型 | `test/screens/workbench/`、`test/screenshots/harness/` | 截图三档宽度 | ✅ |
| 5 | 文档：`api/usage.md` §5 实测表、台账「还欠的」行销掉、本文件退役、设计稿回写出入；bump 4.26.0 | `docs/`、`pubspec.yaml` 等六处 | — | ✅（退役在收尾片）|
| 6 | 独立 review（opus）→ 修 → 再 review，直到无新问题；PR | — | 两道门全绿 | ⬜ |

## 4. 设计 brief（交给 Claude Design 项目的原文）

> 在项目 `925a4d48-684e-4733-bca2-1aa808b7e18f` 新建一份 `A1f 参数栏-xAI 质量档.dc.html`（自成一份，不要改写
> `A1` / `D1e`——这个工具会整文件重写并丢掉旧 section）。先读 `A1 工作台-图像` 的帧 `1a`（参数栏两列网格）与末尾
> 的 mono 规格汇总，以及 `D1e 火山方舟 · Seedream` 里按版本列参数表的写法；新稿是 A1 参数栏的增量，几何、token、
> 控件一律沿用。
>
> **要解决的事**：xAI `grok-imagine-image-2.0` 的输出按 分辨率（1K / 1.5K / 2K）× 质量（Low / Medium）六格标价，
> 应用今天只有「比例」下拉和「尺寸 1k | 2k」分段。要加一个「质量 低 | 中」分段（默认 中 = 上游默认）和 1.5k 档。
> 初代 `grok-imagine-image` / `-quality` 平价、上游拒绝 1.5k，**不变**。
>
> **要出的帧**（桌面 300 宽参数栏为主，每组补一帧手机；暗色至少一帧）：
> 1. xAI 2.0 的参数栏：三个控件怎么排——两列网格里 `AppSegmentedControl` 三选一占整行、两选一占半行，
>    给出声明顺序的裁决（比例 | 质量 / 尺寸整行，还是尺寸整行在上）；与初代 xAI 的两控件并排对照。
> 2. 计费组编辑器的档位表按六格填好的样子（`D2b` 现成部件，只是示例数据），说明 `1K · low` 一行现在能命中。
> 3. 末尾 mono 规格汇总：顺序、尺寸、间距、token、文案（预计无新文案；如有，中文为准附 en / zh_Hant / ja）。
>
> **词汇**：用本应用的 `App*` 组件名（`AppSegmentedControl`（compact · expand · raised）、`AppDropdown`），
> 不要标注 Material 组件名。审美：Apple 式干净、主次分明，质量是次于尺寸的信息。

## 5. 施工记录

- **第 1 片 · 设计稿 `A1f`**（设计子代理拿不到 DesignSync，稿子由主会话对照真实 `A1` 校验、用真实 `support.js`
  预览后推送，90386 字节往返一致）：裁决 A——声明顺序 `aspectRatio → quality → imageSize`，比例 | 质量一行、尺寸整行在下；
  理由：老用户第一眼落点不变、尺寸是贵的那一维放收尾、与 Gemini / OpenAI 的排法一致。帧 4a–4f + 4g「实施出入」。
- **第 3 片** xAI 协议此前没接共用的 `optionsWithCheckedSize`：family 共用一份参数记忆，2.0 上选过的 `1.5k` 会原样发给初代
  （上游 400）。现在尺寸过共用闸回落到初代默认 `1k`；质量只在模型自己的表声明时才发（初代表没有，永不发）。
- **第 4 片 · 与稿的出入 ①** 稿按 1a 复述的几何（半格 126、轨道内边距 2）与真机不同：半格 137、轨道内边距 3、片水平内边距 10，
  标签只剩 43.5，而截图夹具的真实字体量得英文 "Medium" 要 45.8——尾巴两个字母省略。expand 轨道的标签本来由 Row 居中，
  水平内边距只决定何时省略，**在共用的 `AppSegmentedControl` 上把 expand 轨道的水平内边距降到 4**（测试确认不修会截）。
  ② 250 最小栏宽下英文 Medium 仍省略（槽 43 < 45.8），gpt-image-2 的四档轨道同宽同样，只在拖到极限时出现，不做。
  ③ 面板测试的省略断言在测试字体（每个字形一个字号宽）下对英文判不了，改为断言 Medium 的可用宽 ≥ 46；zh / ja 照常全断言。
- **Review 第一轮（opus）** 无 BLOCKER / MAJOR，两条 MINOR：① 把 expand 轨道的内边距一律降到 4 会波及放大编辑器的视图切换——
  它用 `IntrinsicWidth` 从片的固有宽算自己的宽（`markdown_editor_large.dart`），每格会窄 20px、触控区缩水。改为 opt-in
  `AppSegmentedControl.tightLabels`，只有参数栏的格子传 true；补一条「不传时 expand 轨道保持 10 内边距」的测试。
  ② 台账行里的 `git show <sha>` 占位——收尾片删本文件时填真实 sha。

