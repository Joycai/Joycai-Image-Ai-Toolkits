# 火山方舟（Volcengine Ark）· Seedream 图片生成协议

> 一家供应商、一把 key、一个 host（`ark.cn-beijing.volces.com`），本文只写
> **图片生成面**（Seedream 4.0 / 4.5 / 5.0 lite / 5.0 pro）的协议事实。
> 本项目怎么路由，见
> [`../architecture/llm-three-layer.md`](../architecture/llm-three-layer.md)。
>
> **来源**：火山方舟控制台文档，2026-09-18 抓取（页面标注最近更新
> 2026-09-09）：《图片生成教程》`docs/ark/seedream-4-0-5-0`、
> 《Doubao Seedream 5.0 pro 教程》`docs/ark/seedream-5-0-pro`、
> 《图片生成 API》参考页。控制台文档是 SPA，WebFetch 只拿到标题，需要浏览器渲染。

## 0. 总览

| 项 | 值 |
| --- | --- |
| 端点 | `POST https://ark.cn-beijing.volces.com/api/v3/images/generations` |
| 认证 | `Authorization: Bearer $ARK_API_KEY`（控制台「API Key 管理」的长效 key） |
| 同/异步 | **仅同步**：一次请求等到全部图片画完才返回（`stream: true` 例外，见 §5） |
| chat 面 | 同 host 的 `/api/v3/chat/completions`，OpenAI 兼容（本文不展开） |
| 限流 | IPM（张/分钟）500，按「同模型同版本」计；图层拆分每次预扣 17 |
| 结果保存 | `url` 只保留 **24 小时** |

路径与 OpenAI Images API 的生成端点**同形**（`{base}/images/generations`），
body 是它的超集：`model` / `prompt` / `size` / `response_format` 同名同义，
没有 `n` / `quality`，参考图走 JSON 的 `image` 字段（不是 `/images/edits`
的 multipart）。所以一个转发 OpenAI Images 形态的中转站，只要把 body 原样
透传，就能服务 Seedream。

## 1. 模型

| 名称 | Model ID | 分辨率档位 | 参考图上限 | 组图 | 输出格式 | 提示词优化 | 流式 | 联网搜索 | 5.0 pro 专属 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Seedream 5.0 pro | `doubao-seedream-5-0-pro-260628` | 1K · 1.5K · 2K（默认 2K） | 10 | ✗ | png / jpeg | standard / fast | ✗ | ✗ | 交互编辑、图层拆分、透明背景 |
| Seedream 5.0 lite | `doubao-seedream-5-0-260128`（亦收 `doubao-seedream-5-0-lite-260128`） | 2K · 3K · 4K | 14 | ✓ | png / jpeg | 仅 standard | ✓ | ✓ | — |
| Seedream 4.5 | `doubao-seedream-4-5-251128` | 2K · 4K | 14 | ✓ | 仅 jpeg | 仅 standard | ✓ | ✗ | — |
| Seedream 4.0 | `doubao-seedream-4-0-250828` | 1K · 2K · 4K | 14 | ✓ | 仅 jpeg | standard / fast | ✓ | ✗ | — |

`model` 也可以填 Endpoint ID（`ep-…`，推理接入点），从 id 上看不出是哪一代。

## 2. 请求体

| 字段 | 类型 · 默认 | 说明 |
| --- | --- | --- |
| `model` | string，必填 | Model ID 或 Endpoint ID |
| `prompt` | string | 生成场景必填；图层拆分场景可省（省了＝自动拆全部主要元素）。建议 ≤300 汉字 / 600 英文词 |
| `image` | string \| string[] | 参考图，URL 或 `data:image/<fmt>;base64,<…>`（**`<fmt>` 必须小写**）。单张 ≤30 MB、宽高 >14px、宽高比 [1/16, 16]、总像素 [196, 3600 万]；格式 jpeg/png/webp/bmp/tiff/gif/heic/heif |
| `size` | string | 两种写法**不可混用**：档位（`"2K"`）或像素（`"2048x2048"`），见 §3 |
| `sequential_image_generation` | `auto` \| `disabled`，默认 `disabled` | 组图开关；`auto` 时模型按提示词**自行决定**出几张。5.0 pro 不支持 |
| `sequential_image_generation_options.max_images` | int [1, 15]，默认 15 | 组图上限。**参考图数 + 生成数 ≤ 15** |
| `optimize_prompt_options.mode` | `standard` \| `fast`，默认 `standard` | `fast` 只有 5.0 pro / 4.0 接受 |
| `output_format` | `png` \| `jpeg`，默认 `jpeg` | 只有 5.0 pro / 5.0 lite；4.5 / 4.0 恒为 jpeg |
| `response_format` | `url` \| `b64_json`，默认 `url` | |
| `watermark` | bool，**默认 `true`** | true = 右下角加「AI 生成」字样 |
| `stream` | bool，默认 `false` | 5.0 lite / 4.5 / 4.0 |
| `tools` | `[{type:"web_search"}]` | 仅 5.0 lite；模型自行判断是否真的搜索 |
| `layer_decomposition` | bool，默认 `false` | 仅 5.0 pro，见 §6 |
| `background` | `opaque` \| `transparent`，默认 `opaque` | 仅 5.0 pro，见 §6 |

**`watermark` 默认开**是这一面最容易被忽略的一条：文档里每个示例都显式写了
`"watermark": false`，不写就带水印出图，且照常计费。

## 3. 尺寸

### 3.1 档位（推荐）

填档位时宽高比由模型从提示词里判断。档位与宽高比对应的实际像素（文档「常见
值」，模型不限于这些比例）：

| 比例 | 5.0 pro 1K | 5.0 pro 1.5K | 5.0 pro 2K | 4.0 1K | 2K（lite / 4.5 / 4.0） | 3K（lite） | 4K（lite / 4.5 / 4.0） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1:1 | 1024x1024 | 1536x1536 | 2048x2048 | 1024x1024 | 2048x2048 | 3072x3072 | 4096x4096 |
| 4:3 | 1152x864 | 1792x1344 | 2368x1776 | 1152x864 | 2304x1728 | 3456x2592 | 4704x3520 |
| 3:4 | 864x1152 | 1344x1792 | 1776x2368 | 864x1152 | 1728x2304 | 2592x3456 | 3520x4704 |
| 16:9 | 1424x800 | 2048x1152 | 2816x1584 | 1280x720 † | 2848x1600 | 4096x2304 | 5504x3040 |
| 9:16 | 800x1424 | 1152x2048 | 1584x2816 | 720x1280 † | 1600x2848 | 2304x4096 | 3040x5504 |
| 3:2 | 1248x832 | 1872x1248 | 2496x1664 | 1248x832 | 2496x1664 | 3744x2496 | 4992x3328 |
| 2:3 | 832x1248 | 1248x1872 | 1664x2496 | 832x1248 | 1664x2496 | 2496x3744 | 3328x4992 |
| 21:9 | 1568x672 | 2352x1008 | 3136x1344 | 1512x648 † | 3136x1344 | 4704x2016 | 6240x2656 |

† 4.0 的 1K 行两份文档不一致：API 参考页写 1280x720 / 720x1280 / 1512x648，
教程页写 1312x736 / 736x1312 / 1568x672。两组都落在 4.0 的像素区间内。

### 3.2 像素（`WxH`）

| 模型 | 总像素区间 | 宽高比 |
| --- | --- | --- |
| 5.0 pro | [921600（1280x720）, 4624220（2048²×1.1025）] | [1/16, 16] |
| 5.0 lite | [3686400（2560x1440）, 16777216（4096²）]，默认 2048x2048 | [1/16, 16] |
| 4.5 | 同 5.0 lite | [1/16, 16] |
| 4.0 | [921600, 16777216]，默认 2048x2048 | [1/16, 16] |

约束的是**乘积**，不是单边：5.0 lite 的 `1500x1500`（225 万）无效。

## 4. 响应

```json
{
  "model": "doubao-seedream-4-0-250828",
  "created": 1757323224,
  "data": [
    {"url": "https://…", "size": "2048x2048"},
    {"error": {"code": "OutputImageSensitiveContentDetected", "message": "…"}}
  ],
  "usage": {"generated_images": 1, "output_tokens": 16384, "total_tokens": 16384}
}
```

- `data[]` 公共字段：`url` 或 `b64_json`、`size`（`WxH`）、`output_format`（5.0）。
- **组图里单张失败不影响其余**：失败的那一项只有 `error{code, message}`。审核
  不通过会继续画下一张；内部错误（500）则停止后续。
- 顶层 `error{code, message}`：整个请求一张都没画出来时返回。
- `usage.generated_images` 是**成功**张数，**计费按它**（按张，不按 token）；
  `output_tokens` = Σ(宽×高)/256，仅供参考；`input_images`（5.0 pro）；
  `tool_usage.web_search` = 实际搜索次数（0 = 没搜）。
- 错误码见方舟《错误码》页；内容审核类为 `InputTextSensitiveContentDetected` /
  `InputImageSensitiveContentDetected` / `OutputImageSensitiveContentDetected`。

## 5. 流式

`stream: true`：每画完一张就推一个事件（见《图片生成流式响应事件》页），单图与
组图都生效。5.0 pro 不支持。

## 6. 5.0 pro 专属

**交互编辑**：没有新字段。编辑位置靠两种写法之一：在参考图上手绘标记（框、
箭头、涂鸦）再用自然语言指代；或在 `prompt` 里写归一化坐标标签
`<bbox>x1 y1 x2 y2</bbox>` / `<point>x y</point>`（0–1000）。

**图层拆分**（`layer_decomposition: true`）：

- `image` 必填且**只能 1 张**（多张报错）；png / jpeg；总像素 [512², 3600 万]。
- `prompt` 可选：省略＝自动拆；自然语言指定元素；或 `<bbox>` 精确指定。
- `size` 只接受档位：`1K` / `1.5K` / `2K` / `auto`（**默认 `auto`** = 按输入尺寸，
  落在 [1280x720, 2048²×1.1025] 内原尺寸，小于 1K 按 1K，大于 2K 按 2K）。
- 输出 1 张底图 + 最多 16 个图层（带透明通道的 PNG；`output_format` 只管底图）。
  `data[]` 里 `z_index`：底图 0，图层从 1 递增；图层另带 `name`、`description`、
  `bounding_box.absolute`（底图像素坐标 `[l,t,r,b]`）与 `.normalized`（0–1000）。
- 任一图层失败＝整个请求失败，不支持部分成功。

**透明背景**（`background: "transparent"`）：只用于图生图，且**只能 1 张带
透明通道的参考图**；输出默认 png，同时写 `output_format: jpeg` 报错；传入 jpeg
这类没有透明通道的格式报错。典型用法：把图层拆分出来的某一层再单独编辑。

**原生多语种文字**：俄、阿、菲、泰、土、韩、马来、西、葡、印尼、法、德、越、日
14 种语言的文字生成。
