# ai-agent-architecture · 回写稿（2026-09-22，来源：Joycai #337 / #338 / #339，全部【实测】）

对照的是 `~/.claude/skills/synced/…/ai-agent-architecture/`（比仓库 `docs/ai-agent-playbook/` 快照新）。
下面按「放对地方」的规则分到 13 / 06 / 11 / 15 / 00 五处；每条给出**要改的原句**（如有）与**新文**。
一条纠错（xAI 参考图上限），其余是新增。设计层面的东西（计费组、用量行快照、匹配算法）不进这里，
放在 `llm-billing-model` skill，本稿只在 13 §7 留一个指针。

---

## 13 §4.2 · `xai-images`（改写该条）

**原句要改的一处**：「`images:[…]` 最多 3 张」→ 文档写 3，**实测 5 张参考图 HTTP 200 并按 5 张收费**
（`/images/edits`，2026-09-21，`cost_in_usd_ticks` = $0.06 + 5 × $0.01）。写成「文档 3 张【文档】，实测 5 张被接受【实测 2026-09-21】；
应用按 5 截断」。

**新增到该条末尾**：

> **质量与分辨率（`grok-imagine-image-2.0`，【实测 2026-09-22】）**：请求字段 `quality`，枚举 `low | medium | high | auto`
> （别的值 → 422，错误信息列出枚举）；2.0 只收 `low / medium / auto`（`high` → 400 `This model only supports the following
> quality value(s): low, medium, auto.`）；**不带 = medium**。`resolution` 枚举 `1k | 1.5k | 2k`。
> OpenAPI（`docs.x.ai/openapi.json`）的请求体**没列** `quality`，只有 `ImagePricingTier` 的一句
> 「Medium is the default quality a request serves at when it leaves `quality` unset」——文档与 OpenAPI 不一致时以实测为准。
> `GET /v1/image-generation-models/{id}` 回 `image_price` + `pricing[{quality, resolution, price_per_image}]`，
> `price_per_image` 单位 1e-8 美分（= tick，见 §7）；2.0 六格：1K·Low $0.04 / 1.5K·Low $0.05 / 2K·Low $0.06 /
> 1K·Medium $0.06 / 1.5K·Medium $0.07 / 2K·Medium $0.08。**初代 `grok-imagine-image`（$0.02）与 `grok-imagine-image-quality`（$0.05）
> 是 `pricing: []`（各质量同价）**：它们**默默收下** `quality`（一个骗人的旋钮，别在 UI 上给），而 `resolution: 1.5k` → 400
> `1.5K resolution is not supported for this model.`。`quality: auto` 由模型定档（一次实测选了 Low，$0.04）——**按规格计价的表写不出它**。

## 13 §7 · 计费与观测（新增四条）

> - **有的端点直接报钱。** xAI images 的 `usage` 只有一个字段 `cost_in_usd_ticks`，**1 tick = $10⁻¹⁰**
>   （OpenAPI 把 `price_per_image` 定义为 "1/100,000,000ths of a USD cent"；实测 400 000 000 = 1K·Low $0.04）【实测 2026-09-21/22】。
>   它**含输入图**（$0.06 + 5 × $0.01 = 1 100 000 000），所以是**整单实扣**，压过任何本地算式而不是叠加；
>   回包里**没有**输入张数，张数只能自己数。「没报」（字段缺）与「报了 0」必须分开存（NULL vs 0）。
>   经中转（走 Images API 形状）时这个字段可能原样透传，但**那是 xAI 收中转的价，不是用户付中转的价**——只在自家协议上读它。
> - **输入图按张计费，与输出分开标价**（2026-09-21 查证）：xAI 2.0 **$0.01/张、线性、无免费张数**，`n:2` 时**按请求收一次、不乘输出张数**
>   （1 张参考图 + `n:2` + low = 900 000 000 = 2 × 0.04 + 1 × 0.01【实测 2026-09-22】）；Seedream 5.0 pro 0.02 元/张、**每次请求首张免费**，
>   且回报 `usage.input_images`（原始张数）。gpt-image / Gemini image 的输入图在 `input_tokens` 里（图像输入单价与文本不同：$8/M vs $5/M，
>   `input_tokens_details.image_tokens` 有明细）。**张数要在组完请求体之后数**：按上限截断、再丢掉读不出的附件——截断后的长度会为没发出去的图收钱。
>   **一张没交付就不该收输入费**（方舟明说失败免费）。失败 / 被审核拦下的请求上游是否仍收输入费：**【未验】**——失败的回包走不到记账，只能对账单。
> - **计费相关的请求默认值要明发**（与 14 §3.6 同一条）：xAI 不带 `quality` 按 Medium 计（$0.06），不是标价表第一格的 Low（$0.04）；
>   客户端只发分辨率、本地按「表第一行」估价，会把每张图**低估三分之一**而不报错。默认值写死并发出去，用量记录才带得上规格。
> - **记账读的中性键是保留键。** 记账层对所有 vendor 一视同仁地读 `input_image_count` / `reported_cost_usd` 这类**应用自己**的键；
>   凡把上游 `usage`（或任何上游 map）**原样铺进** metadata 的地方，都要先剔掉这些键——否则中转或供应商起个同名字段就能定账。
>   只有协议自己的换算（tick → 美元、数出来的张数）能写它们，且写在铺之后。聊天四族与 images 各家都有这种原样铺的代码（DeepSeek 补
>   `cached_tokens` 那条就是同一类地方）。**流式出图的每个图片块也要带**这两个键：流在出图后、收尾块前被放弃时，记账只看到图片块。
>   设计层（计费组 / 用量行快照 / 档位匹配 / 用量页）见 `llm-billing-model` skill。

## 06 §1 · usage 归一化（在「三处必须归一化」后加一段）

> **第四种口径：上游直接报钱。** 有的面不报 token 也不报张数，只报这次的实扣金额（xAI images `cost_in_usd_ticks`，13 §7）。
> 归一化成一个中性键（美元 double），**换算只写一处**；持久化时它是一列可空的 `reported_cost`，有值就是行的成本，其余口径归零。
> 与「按次 / 按张与 token 相加」不同：报价含全部，**替换**不叠加。

## 11 · 坑（接着 122 往下编）

> ### 123-静默 · 不发 `quality` 的 xAI 出图按 Medium 计，本地按表第一行（Low）估
> 现象：账单比应用记的高三分之一，没有任何错误。原因：xAI 2.0 六格标价按 分辨率 × 质量，`quality` 缺省 = medium；客户端只发 `resolution`。
> 对策：默认值明发（`quality: "medium"`），用量行才带得上规格；本地估价与 `cost_in_usd_ticks` 对照【实测 2026-09-22】。
>
> ### 124-静默 · `quality: auto` 让模型定档，账单不可预算
> 现象：同一请求两次价格不同（实测一次选了 Low）。对策：按规格计价的表写不出 `auto`——UI 不提供；若上游报钱（123 的字段）就按报价记。
>
> ### 125-静默 · 初代 `grok-imagine-image` 默默收下 `quality`
> 现象：发 `quality: low` 200、价格不变（$0.02 平价，`pricing: []`）。对策：能力表按 id 尾巴分流，初代不给质量控件；`1.5k` 在初代 400。
>
> ### 126-静默 · 上游同名字段改写了你的记账键
> 现象：某中转的 `usage` 里恰好有个 `input_image_count` / `reported_cost_usd`（或你内部用的任何中性键名），原样铺进 metadata 后成了账。
> 对策：所有原样铺上游 map 的地方走一个剔保留键的函数；每处一条伪造用例。见 13 §7 末条。
>
> ### 127-静默 · 报价只在收尾块，流被放弃就退回表算
> 现象：出图流在图片到达后被取消 / 空闲守卫掐断，用量行按档位表记而不是按上游报价。对策：图片块携带报价与张数（同 `input_image_count` 的既有做法）。
>
> ### 128 · 记录：xAI 参考图上限文档 3、实测 5 张 200 并计费
> 见 13 §4.2 的纠错；按 5 截断。

## 15 · 厂商索引（改 xAI 一行）

> | **xAI Grok** | …；Grok Imagine 出图（2.0：`quality` low/medium，`resolution` 1k/1.5k/2k，`usage.cost_in_usd_ticks` 报实扣；初代平价）/ 视频 | …；13 §4.2「xai-images」（质量 / 分辨率 / 定价端点）、§7（报价、输入图按张）；14 §2；坑 66–67、123–128 | 【实测 2026-09-22】 |

方舟那一行的指针补「13 §7（`usage.input_images`、首张免费、失败免费）」。

## 00 §3.3 · 出图与视频的审查项（新增三条）

> - [ ] 按张计费的端点：输入图有没有单独计费？张数是**实际放进请求体**的（截断后、丢掉读不出的之后）还是附件数？一张没交付时收不收？
> - [ ] 上游报了钱（`cost_in_usd_ticks` 类）的面：读了吗？读了的话「没报」与「0」分得开吗？经中转时是否误读？
> - [ ] 计费相关的请求默认值（质量、分辨率、`n`、`audio`）是否**明发**？不明发 = 用量记录缺规格 + 本地估价按错档。

## 14 · 一条待核实

> xAI 视频面的轮询回包是否也报 `cost_in_usd_ticks`：**【未验】**（本轮只测了 images）。若报，14 §3.8「两套口径相加」对它要改成「报价替换」。
