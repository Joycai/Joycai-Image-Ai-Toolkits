# 16 · 语音识别（ASR）：OpenAI 兼容转写 / 百炼同步识别 / 录音文件转写

> 本篇解决的问题：给一个应用接语音转文字（字幕、会议转写），要拿到**可用的时间码**，
> 必要时还要**说话人编号**。ASR 在行业里有三种互不相干的线格式——multipart 上传的
> OpenAI 转写、JSON 里塞 base64 的同步识别、「上传 → 提交 → 轮询 → 下载」的异步文件转写——
> 同一家厂商往往两三种都有，按模型名分。
> 不读会踩的坑：同步接口**不给句级时间戳**，整段 25 秒只得到一行字；请求里的
> `diarization_enabled` 被同步接口**静默忽略**，字幕里一个说话人都没有却照常 200；
> 切片时为了「留余量」多截了邻段真实音频，半个词被识别两次；没人声的片段回 400，被当成
> 失败把整个任务打断；filetrans 的 403 被当成
> 鉴权失败直接放弃，其实只是上传凭证或结果签名地址过期。
>
> 2026-09 增补，来源：pyVideoTrans 的 Flutter 重写版（subtitle_studio，`app/lib/services/`）
> 与原 Python 版（`archive/python/videotrans/recognition/`）。百炼两条路在官方服务上
> 实测跑通【实测 2026-09-13】；OpenAI 兼容这条路只有实现、没有实测，也没有离线测试。
> 另有一份更细的操作手册：独立 skill **dashscope-qwen-asr**（含 Dart 参考代码、Python / Node
> 移植注意事项、完整的离线测试清单）。本篇只记事实与判据，不重复代码。

---

## 1. 三种线格式，先分清再写代码

| | ⓐ OpenAI 兼容转写 | ⓑ 百炼同步识别 | ⓒ 百炼录音文件转写（filetrans） |
| --- | --- | --- | --- |
| 端点 | `POST {base}/audio/transcriptions` | `POST {base}/services/aigc/multimodal-generation/generation` | `GET /uploads?action=getPolicy` → OSS 表单上传 → `POST /services/audio/asr/transcription`（异步）→ `GET /tasks/{id}` → 下载结果 JSON |
| 音频怎么传 | multipart 文件字段 `file` | base64 data URI 放进 JSON 请求体 | 上传到百炼临时 OSS，得到 `oss://` 地址（48 小时有效） |
| 单次上限 | OpenAI 25 MB【文档】；各家不同 | 约 10 MB、3–5 分钟（文档两种说法都有）【文档】 | 以凭证返回的 `max_file_size_mb` 为准；时长 12 小时【文档】 |
| 时间码 | `verbose_json` 给 `segments[].start/end`（**秒**，浮点）；部分模型不给 | **无句级时间戳**，时间码只能来自「送去识别的那一片在哪」 | 句级 + 词级（**毫秒**整数），相对整个文件 |
| 说话人 | 标准 whisper 无 | 【实测】传了也被忽略 | 【实测】qwen-audio-3.0 族可用，整文件内编号一致 |
| 代表 | OpenAI `whisper-1`、Groq、硅基流动、中转站、本地 OpenAI 兼容服务 | `qwen3-asr-flash`、`qwen-audio-3.0-asr-flash`、`fun-asr-flash-*` | 模型名以 `-filetrans` 结尾 |

按原则 1，这是**三个适配器**，不是一个适配器加一堆 if：body 形状、流程步数、时间码来源都不一样。
同一厂商（百炼）在同一个 baseUrl、同一把 key 下有 ⓑ ⓒ 两张脸，**按模型名后缀分发**
（`model.endsWith('-filetrans')` → ⓒ），不要按厂商分发。

选哪条：

- 要说话人 → 只有 ⓒ 实测可用（`qwen-audio-3.0-asr-flash-filetrans`）。
- 要准确时间码、模型没指定 → ⓒ，省掉整套切片逻辑。
- 用户点名同步模型又要时间码 → ⓑ + 静音切片（§4），并告诉用户 ⓒ 这个替代方案；不要擅自换模型。
- 已经在用 OpenAI 兼容服务、只要文本和粗时间码 → ⓐ，但注意 §3 的体积上限与模型差异。

## 2. 统一形状

```text
识别(音频路径, 语言, 取消令牌, 进度回调, 检查点?) -> [字幕条]
  字幕条   = { startMs, endMs, text, speaker?: int, confidence?: 0..1 }
  语言     = 主标签（zh / en / ja），"auto" 表示不下发语言参数
  检查点   = 逐段记录（ⓑ）或 { fileUrl?, taskId? }（ⓒ），失败与取消都保留
```

- **输入音频统一成 16 kHz、单声道、pcm_s16le 的 wav**：
  `ffmpeg -i in -vn -ac 1 -ar 16000 -c:a pcm_s16le out.wav`。这是各家的公约数；
  代价是体积：约 1.9 MB / 分钟，1 小时约 115 MB。
- **语言代码只取主标签**，`zh-CN` → `zh`。选「自动检测」时**整个字段不发**，不要发 `"auto"`。
- **字幕里存不带硬换行的干净文本**，折行只在导出时做；否则用户编辑后再导出会叠加换行。
- **参数在任务入队时定死**（模型、提示词、是否分离），运行时不回头读全局设置。ASR 任务动辄几十分钟，
  排队期间用户改了设置，前面的任务不该跟着变。
- 结果统一后还要过一道**与服务无关的时间轴规整**（§6），不要指望每个适配器自己把结果洗干净。

## 3. ⓐ OpenAI 兼容 `/audio/transcriptions`

请求（multipart/form-data，`Authorization: Bearer <key>`；本地服务不需要密钥时**不发这个头**，见 02 §5）：

```text
file                       音频文件
model                      whisper-1 | whisper-large-v3 | FunAudioLLM/SenseVoiceSmall | …
response_format            verbose_json      ← 要时间码必须是它
timestamp_granularities[]  segment           ← 只在 verbose_json 下有效；可再加 word
language                   zh                ← 可选，主标签；自动检测时不发
prompt                     术语、专有名词      ← 可选，给模型做偏置
```

响应（`verbose_json`）：

```json
{ "text": "…", "duration": 12.5, "language": "chinese",
  "segments": [ { "start": 0.0, "end": 3.2, "text": " 你好…", "avg_logprob": -0.21 } ] }
```

- 时间是**秒**（浮点），乘 1000 取整转毫秒；`text` 前面常带一个空格，要 trim。
- `avg_logprob` 是自然对数，`exp()` 后夹到 0..1 可当置信度；没有时再找 `confidence`。
- **没有 `segments` 时退回整段 `text`**，时间码记 `[0, duration]`。这是兜底，不是正常路径：
  整段一条字幕，要靠 §6 的按字数拆分才能看。

模型差异：

| 模型 / 服务 | 事实 | 证据 |
| --- | --- | --- |
| OpenAI `whisper-1` | 支持 `verbose_json` 与 `timestamp_granularities[]`；文件上限 25 MB | 【文档】 |
| OpenAI `gpt-4o-transcribe` / `gpt-4o-mini-transcribe` | `response_format` 只支持 `json` / `text`，不给 segments；原 Python 版因此对它改走切片、只取 `text` | 【文档 + 实现】 |
| Groq `whisper-large-v3(-turbo)` | OpenAI 兼容地址 `https://api.groq.com/openai/v1` | 【实现】 |
| 硅基流动 `FunAudioLLM/SenseVoiceSmall` | 支持语种 zh / yue / en / ja / ko | 【实现】 |

## 4. ⓑ 百炼同步识别

请求头：`Authorization: Bearer <key>`、`Content-Type: application/json`、`X-DashScope-SSE: disable`。
默认地址 `https://dashscope.aliyuncs.com/api/v1`；专属域名（token-plan 类）要允许覆盖 baseUrl。

**两族 body 形状不同**，按模型名前缀分：

`qwen3-asr-flash`（百炼原生 `audio` 内容块）【实测 2026-09-13】：

```json
{ "model": "qwen3-asr-flash",
  "input": { "messages": [
    { "role": "system", "content": [ { "text": "术语：Kubernetes、通义千问" } ] },
    { "role": "user",   "content": [ { "audio": "data:audio/wav;base64,…" } ] } ] },
  "parameters": { "result_format": "message",
                  "asr_options": { "language": "zh", "enable_lid": true, "enable_itn": true } } }
```

- 没有提示词时整条 system 消息都不发；自动检测时 `asr_options` 里不带 `language`。
- `enable_lid` 与 `language` 同时发，实测正常。`enable_itn`（「二零二六年」→「2026年」）本项目开着。

`qwen-audio-3.0-asr-flash` / `fun-asr-flash-*`（`input_audio` 内容块）【实测 2026-09-13】：

```json
{ "model": "qwen-audio-3.0-asr-flash",
  "input": { "messages": [ { "role": "user", "content": [
    { "type": "input_audio", "input_audio": { "data": "data:audio/wav;base64,…" } } ] } ] },
  "parameters": { "format": "wav", "sample_rate": "16000" } }
```

三个模型识别同一段两句合成中文，都正确【实测 2026-09-13】。

**响应文本在两个位置之一**，都要兼容：`output.text`（字符串），或
`output.choices[0].message.content`（字符串，或 `[{text}]` 数组、拼接）。取不到 → 归「服务端问题」；
取到空串 → 这段没话。可能存在的词级信息在 `output.sentence.words[]`，**同步接口会不会给没有实测**，代码要允许它不存在。

**没有人声的片段回 `400` + 响应体含 `ASR_RESPONSE_HAVE_NO_WORDS`**【实测】。这是「这段没话」，按成功（空文本）处理；
当成失败的话，一段背景音乐就能让整个任务停下。

### 4.1 静音切片：同步接口的时间码从这里来

```text
ffmpeg -i audio.wav -af silencedetect=noise=-35dB:d=0.6 -f null -
```

- 结果在 **stderr**：`silence_start: 12.345`、`silence_end: 13.9 | silence_duration: …`。
  文件末尾可能只有 start 没有 end，这段静音一直到结尾。
- 静音按起点排序、裁到 `[0, total]`、合并重叠；**补集就是语音**，开头和结尾都算。
- 短于 1 s 的语音段并入前一段（第一段就并入后一段）；长于 25 s 的按 `ceil(len/25s)` **等分**，
  不按固定秒数切（固定秒数更容易切在词中间）。
- 原 Python 版用的是 VAD 模型而不是 silencedetect（默认 ten-vad、可选 silero，§10.1）。

切出单片：

```text
ffmpeg -y -ss <start> -t <dur> -i audio.wav -af adelay=200:all=1,apad=pad_dur=0.200 \
       -ac 1 -ar 16000 -c:a pcm_s16le clip.wav
```

- **前后补 200 ms 的是静音，不是邻段真实音频**。早期版本为了「留余量」多截了邻段 200 ms，结果
  邻段的半个词被识别进来、跨段重复【实测，2026-09-13 修复】。字幕时间码仍用 `[start, end]`，
  另记 `fileStartMs = start − 200` 用来换算词级时间。
- 用 `-ss` + `-t`，不用 `-to`：`-to` 放在 `-i` 之前时各 ffmpeg 版本行为不一致。wav 无关键帧，输入端 seek 精确到样本。

### 4.2 限流

- 限流额度按账号共享，文档默认约 100 RPM【文档】，以控制台为准。
- Retry-After 只认秒数（夹到 1–300 s），日期形式或缺失时按 5 / 10 / 20 / 40 / 60 s 阶梯。
- 本项目逐段串行请求；连续等待的计数决定走到阶梯哪一档，一次成功就清零。

## 5. ⓒ 百炼录音文件转写（`-filetrans`）

【实测 2026-09-13】`qwen-audio-3.0-asr-flash-filetrans` 在官方地址跑通全部五步；`qwen3-asr-flash-filetrans` 只按文档实现。

1. **取上传凭证** `GET {base}/uploads?action=getPolicy&model=<model>` → `data.{upload_host, upload_dir,
   oss_access_key_id, policy, signature, x_oss_object_acl, x_oss_forbid_overwrite, max_file_size_mb}`。
   `model` 必须与提交时一致。没有 `data` = 这个地址不支持临时上传。**上传前先按 `max_file_size_mb` 和时长拦截。**
2. **表单上传到 `upload_host`**，**不带 `Authorization`**。字段顺序：`OSSAccessKeyId`、`policy`、`Signature`、
   `key`（`<upload_dir>/<时间戳>_<只保留 [A-Za-z0-9._-] 的文件名>`）、`x-oss-object-acl`、`x-oss-forbid-overwrite`、
   `success_action_status=200`，**`file` 必须最后**。200 / 204 成功，地址为 `oss://<key>`。
3. **提交** `POST {base}/services/audio/asr/transcription`，头带 `X-DashScope-Async: enable` **和
   `X-DashScope-OssResourceResolve: enable`**（少了后者服务端不认 `oss://`）。两族参数不同：

   ```json
   { "model": "qwen-audio-3.0-asr-flash-filetrans",
     "input": { "file_urls": ["oss://…"] },
     "parameters": { "channel_id": [0], "enable_words": true,
                     "diarization_enabled": true, "language_hints": ["en"] } }
   ```
   qwen3 族【文档】：`input.file_url: "oss://…"`（单数、字符串）、`parameters.language: "en"`。
   两族都带 `enable_words: true` 才有词级时间戳。任务号在 `output.task_id`。**提交不幂等**，超时重试可能重复计费，重试要少。
4. **轮询** `GET {base}/tasks/{id}`，`output.task_status ∈ PENDING / RUNNING / SUCCEEDED / FAILED / CANCELED / UNKNOWN`
   （与万相视频共用，14 §2）。间隔 2 → 3 → 5 → 8 → 10 s 封顶；超时保留任务号。
   结果地址在 `output.results[].transcription_url`（`subtask_status` 缺失按成功），兼容 `output.transcription_url`。
5. **下载结果**：直接 GET 签名地址，**不带鉴权头**。解析 `transcripts[0].sentences[]`：
   `{begin_time, end_time, text, speaker_id, words:[{begin_time, end_time, text, punctuation, speaker_id}]}`，
   毫秒、相对整个文件。`speaker_id` 可能是数字也可能是数字字符串，从 0 开始；词上缺失时沿用句子的。
   **末尾偶尔多一句只有标点的空句**，至少含一个字母或数字才收。

**【实测】Dart `http` 包的 `MultipartRequest` 传 OSS 被拒 `MalformedPOSTRequest`，手拼 multipart 立即成功。**
`http` 1.x 与手拼的差异有三处：boundary 字符集含 `+` 和 `.`、part 头全小写、文件段先写 `content-type` 再写
`content-disposition`。具体是哪一处触发的**没有定位**。手拼时三处都按规范写（boundary 只用字母数字、
`Content-Disposition` 规范大小写且在 `Content-Type` 之前）。其他语言遇到同样的错也先手拼一份对照。
（早期提交说明里写的「boundary 含 `()+,?:=`」不准确，保留在此以解释旧代码。）

## 6. 时间轴：从服务结果到字幕

### 6.1 词级时间 → 字幕小块（ⓑ 有 words 时、ⓒ 总是）

- 词时间 = `offset + begin_time`，夹进 `[min, max]`。ⓑ：`offset = fileStartMs`，区间取片段起止；ⓒ：`offset = 0`，区间取句子起止。
- 词正文 = `text + punctuation`。
- 下一个词加入**之前**断开，满足任一条件：说话人换了；上一个词的标点是句末 `[。！？.!?;；]`；
  当前块已超过 10 s；当前块长度 + 这个词 > 上限。上限按**当前块是否已含中日韩字符**：含则 40 字，
  否则 90 字符（中英混排只要出现一个汉字就按 40）。
- 拼接时的空格：下一个词以拉丁字母或数字开头、且前文以拉丁字母 / 数字 / 英文标点结尾才加
  （`"Hi," + "let's"` → `"Hi, let's"`）；中文之间不加。
- `end <= start` 时令 `end = start + 1`。

### 6.2 与服务无关的规整（断句阶段）

各渠道结果质量参差，统一在一个纯函数里兜底：

- 先修重叠；短于 500 ms、与上一条间隔小于 200 ms、**且说话人相同**的并进上一条（换人的短应答不并）。
- 长于 10 s 的按字数比例拆开、时间按字符比例分配；切点优先落在标点 / 空白之后，
  中日韩只在目标位置附近找、找不到硬切，拉丁文宁可不均匀也不劈开单词。
  没有词级时间戳的渠道，一条就是一整片（最长 25 s），全靠这一步变得可读；时间码是估算，误差约 1 s。
- 单行字数上限（中日韩 15、其他 40）只在导出时应用。
- 识别被跳过的空文本占位条，**不送去翻译**（白花钱），导出时不写入并提示用户。

## 7. 说话人分离：矩阵与判据

| 路 | 结论 | 证据 |
| --- | --- | --- |
| ⓑ `qwen-audio-3.0-asr-flash` / `fun-asr-flash` 带 `diarization_enabled: true` | **静默忽略**：200、有文本、没有 `speaker_id` | 【实测 2026-09-13】；文档称支持 |
| ⓑ `qwen3-asr-flash` | 不支持，不要下发 | 【文档】 |
| ⓒ `qwen-audio-3.0-asr-flash-filetrans` | 可用；一男一女英文对话标成 0 / 1，整文件编号一致 | 【实测 2026-09-13】 |
| ⓒ `qwen3-asr-flash-filetrans` | 不支持 | 【文档】 |
| ⓒ `fun-asr`、`fun-asr-mtl`、`paraformer-v2` 等 | 文档称支持，建议单声道、≤ 2 小时 | 【文档，未测】 |
| ⓐ 标准 whisper | 无 | 【文档】 |

- 编号从 0 开始，只是「第几个声音」；「主持人 / 嘉宾」的名字映射归上层。
  本项目界面按**首次出现顺序**重新编号；原 Python 版的 302.AI 渠道曾用「当前条数」当新编号，同一个人拿到不同编号（已修复）。
- 用户开了分离、结果里一个编号都没有：不报错，提示「所选模型可能不支持说话人分离」。
- ⓑ 实测不返回编号，所以把片段放长（例如 2 分钟）也换不来编号；要分离只能走 ⓒ。
- 测分离不能用两个合成中文女声（Tingting / Meijia 太像，服务端分不开）；要一男一女英文嗓音
  （macOS `say -v Samantha` / `-v Daniel`）【实测】。没安装的嗓音会让 `say` 退出码 0 但生成**空文件**。

## 8. 错误分类：按「哪一步」而不是按状态码

同一个状态码在不同步骤里含义不同，不要写全局的「状态码 → 致命与否」表：

| 步骤 | 状态 | 含义 | 处理 |
| --- | --- | --- | --- |
| ⓐ / ⓑ 识别、ⓒ 提交 | 401 / 403 | 鉴权 | 致命 |
| 同上 | 404 | 模型没开通或地址错（专属域名对不存在的模型也回 404 `Model not exist`【实测】） | 致命，提示同时核对模型名和地址 |
| ⓑ | 413 | 片段太大 | 致命，切短 |
| ⓑ | 400 + `ASR_RESPONSE_HAVE_NO_WORDS` | 没人声 | 成功，空文本 |
| ⓑ | 其他 400 / 422 | 语种不支持、内容审核拒了这段 | 非致命：记失败，可跳过这段 |
| 任一 | 200 但不是 JSON | baseUrl 填成了网页 / 缺 `/api/v1` | 致命 |
| 任一 | 429、断网、超时 | 等待 | 不计失败，按 Retry-After 或退避阶梯等待 |
| 任一 | 5xx、200 却取不到文本 | 服务端问题 | 计一次失败；同段 3 次后跳过，留空占位条 |
| ⓒ 取凭证 / 上传 | 403 | 凭证过期 | 重取凭证再传，什么都不丢 |
| ⓒ 提交 | 400 | 多半是 `oss://` 过期（48 h） | 丢 fileUrl，重新上传 |
| ⓒ 轮询 | 404 | 任务不在了 | 只丢 taskId，重新提交 |
| ⓒ 任务 FAILED | 原因含 download / url / file / format | 文件取不到 | taskId、fileUrl 都丢 |
| ⓒ 任务 FAILED | 其他 | — | 只丢 taskId；当次最多自动重来 1–2 轮 |
| ⓒ 下载结果 | 403 / 404 | 签名地址过期 | 丢 taskId，保留 fileUrl |

错误详情只截响应体前 600 字符；**密钥不进日志与错误详情**；响应体按 UTF-8 字节解码，不信 HTTP 库按 header 猜的编码。

## 9. 断点续跑

ASR 是长任务里最贵、最慢的一步，失败与取消都必须保留已完成的部分。

- **ⓑ 按片段的 `(startMs, endMs)` 记检查点**，每段 `{text?, pieces?, failures, skipped, lastError}`；
  `text != null || skipped` 即完成（空串 = 没话）。
- 续跑时判断检查点可用：**记录过的每一段都能在新切分里找到完全相同的起止**就沿用。
  **不要要求段数相等**——中途被限流停下时后面的段还没记，按段数比会误判「音频变了」而整份重跑
  （本项目踩过，2026-09 修复）。对不上才清空；重新抽音频时也清空。
- 被跳过的段续跑时仍算完成；想重试它们要有显式的「清除跳过」操作。
- **ⓒ 检查点存 `fileUrl` 与 `taskId`**，每步拿到立刻落盘，分三步续跑：有 taskId → 轮询；只有 fileUrl → 提交；
  都没有 → 上传。音频**懒抽取**——提交 400 丢掉 fileUrl 之后又需要音频文件。
- 两种运行模式分类完全一样，只是分类之后的动作不同：交互模式遇到等待类立即停下保留进度；
  自动模式原地退避重试、失败 3 次跳过。
- 本项目的等待按 250 ms 小步睡眠、每步检查取消令牌；取消时杀掉 ffmpeg 子进程；睡眠函数可注入，测试里立即返回。

## 10. 原 Python 实现（pyVideoTrans）的渠道事实

证据等级统一为【实现】：来自原项目 `archive/python/videotrans/recognition/` 的代码与 2026-09-11 的修复提交，
代码在真实服务上跑过，但本库没有独立复核报文。用来**找线索、知道有这回事**；据此判错前先实测。
路径相对 `archive/python/videotrans/`。

### 10.1 共同的骨架

- **大多数在线渠道不信任服务端的时间码**：先用 VAD（默认 ten-vad，可选 silero）切片，每片单独请求，
  **一片的文字 = 一条字幕，时间码 = 切片位置**。VAD 参数：最短语音 1 s、**单片硬上限 25 s**、最短静音 600 ms、阈值 0.45
  （`recognition/_base.py` `_vad_split`）。切片前后各补静音——注释写 200 ms，代码实际是 **400 ms**（`cut_audio`）。
- 有词级时间戳的渠道（whisper 本地、Gemini）走规则重断句 `process/_stt_utils.py` `_resegment`：
  时间单位是**秒**；时长已在 `[min, max + 1.5 s]` 内的段**整段保留、直接用段的 `text`**；
  更长的在词边界切：句末标点、停顿 ≥ 400 ms、逗号且停顿 ≥ 200 ms、过半后停顿 ≥ 100 ms，`max + 1.5 s` 强切。
  不加空格的语言：zh / ja / th / yue / ko / km。
- **LLM 重断句 / 校对**（`prompts/resegment/llm.txt`）：每 20 条 SRT 一批发给对话模型，要求「只修错字和标点、
  **不改序号、时间码和条数**」，输出包在 `<SRT>…</SRT>` 里；剥掉 `<think>`；`finish_reason == "length"` 报错让用户调大
  max tokens；结果条数 ≤ 原来一半就整批丢弃。与翻译的行号协议是同一个问题（条数对不上 → 时间轴错位），
  这里的判据比翻译宽松得多：条数少了三成也会被接受。
- 结果后处理 `_post_fix`：丢掉只有符号的条目；上一条的 end 夹到下一条的 start 修重叠；可选去掉行尾标点。

### 10.2 各渠道速查

| 渠道 | 端点与鉴权 | 音频与切片 | 取什么 | 值得记的 |
| --- | --- | --- | --- | --- |
| OpenAI 官方 | SDK `audio.transcriptions.create` | **整文件**转 16 kHz 单声道 mp3，无 25 MB 检查 | `verbose_json` + `timestamp_granularities=["segment"]` → `segments[].start/end`（秒） | 响应没有 `segments` 就改走下一行的切片路径——**这就是 `gpt-4o-transcribe` 的处理方式**（它不给 verbose_json） |
| OpenAI 兼容第三方 | 同上，非 `api.openai.com` 的地址 | VAD 切片逐段 | `response_format: "json"`，只取 `text`，时间码来自切片 | 第三方对 `verbose_json` 支持不齐，干脆不要 |
| `gpt-4o-transcribe-diarize` | 同上 | 整文件，`chunking_strategy: "auto"`，不带 prompt | `response_format: "diarized_json"` → `segments[].start/end/text/speaker` | 说话人按首次出现顺序重编号 |
| 302.AI | `POST https://api.302.ai/v1/audio/transcriptions`，Bearer | whisper 整文件；`gpt-4o-*` 切片 | whisper `verbose_json`；gpt-4o 只能 `json`（代码注释原话） | 请求**没有超时**；带 `error` 或缺 `text` 的片段记下后跳过，全部失败才报错 |
| 智谱 GLM-ASR | `POST https://open.bigmodel.cn/api/paas/v4/audio/transcriptions`，Bearer；multipart `file` + `model=glm-asr-2512`、`stream=false` | VAD 切片 | 只有 `text` | 错误体 `error.code` 为 `1302` / `1303` / `1214` 是**限流**（HTTP 状态之外的第二层判据，06 §2）；401 / 403 / 404 / 422 致命 |
| 百炼 `qwen3-asr-flash` | DashScope SDK `MultiModalConversation.call`，`content: [{audio: <本地路径>}]` | VAD 切片 | `output.choices[0].message.content[].text` 拼接 | SDK 替你上传本地文件；与 §4 的 base64 形态等价 |
| 百炼 `qwen-audio-3.0` / `fun-asr-flash` | 裸 HTTP，同 §4 | VAD 切片 | `output.text` | 400 / 422 且体含 **`DataInspectionFailed`** = 这一片被内容审核拒了，**跳过这一片**，不要停整个任务；空间专属地址 `https://{spaceid}.cn-beijing.maas.aliyuncs.com/api/v1` |
| 火山引擎豆包（大模型录音识别极速版） | `POST https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash`；头 `X-Api-App-Key`、`X-Api-Access-Key`、`X-Api-Resource-Id: volc.bigasr.auc_turbo`、`X-Api-Request-Id: <uuid>`、`X-Api-Sequence: -1` | 整文件 mp3 → base64 放进 `audio.data` | `result.utterances[].start_time/end_time`（**毫秒**）、`text`、`additions.speaker` | **成败看响应头 `X-Api-Status-Code == 20000000`**，不看 HTTP 状态；`20000003` 静音、`45000001` 参数错、`45000002` 空音频、`45000151` 格式错、`55000031` 服务忙。请求开 `enable_speaker_info` 可得说话人 |
| 小米 MiMo | OpenAI SDK 打 `https://api.xiaomimimo.com/v1` 的 **`chat/completions`**，`model: mimo-v2.5-asr` | VAD 切片、每片 mp3 | `choices[0].message.content` | 音频走 ① 族的 `input_audio` 内容块；语言走 `extra_body.asr_options.language`（只认 zh / en / auto） |
| Gemini | `google-genai` SDK：Files API 上传后 `interactions.create`，`generation_config.transcription_config = {mode:{type:"verbatim", timestamp_granularities:["word"]}, language_codes:[…]}`，模型 `gemini-3.5-transcribe` | ≤ 300 s 整段；更长用 silero 切 60–300 s、静音 2 s、不补静音 | `steps[].content[].annotations[]` 里 `type == "word_info"` 的词 | 词时间是**带 `s` 后缀的字符串**（`"1.23s"`）；多把 key 逗号分隔轮换；把 400 / 403 / 404 / 429 / 500 都当「不重试」，429 也不等 |
| Deepgram | SDK `listen.rest.v("1").transcribe_file`，超时 600 s | 大于 50 MB 先转 mp3 | 分离时 `results.utterances[].start/end`（秒）、`transcript`、`speaker` | 选项 `smart_format / punctuate / paragraphs / utterances`、`diarize`、`utt_split=<静音秒数>`；中文结果要去空格、繁转简 |
| ElevenLabs | SDK `speech_to_text.convert`，指定语言用 `scribe_v2`、自动用 `scribe_v1`，`diarize: true` | 整文件 | `words[]`：`type / text / start / end`（秒）/ `speaker_id`（`speaker_N`） | 跳过 `type == "audio_event"` 的词；换人必断句，标点 +（停顿 ≥ 200 ms 或行长 ≥ 500 ms）断句 |
| CAMB AI | SDK：提交得 `task_id`，每 3 s 轮询，上限 600 s | 整文件 | `transcript[]`：`start / end`（秒）、`text`、`speaker` | 语言是**整数 ID**，查不到默认 1（英语）——静默按英语识别 |
| Gladia（自定义 API 的特例） | `POST /v2/upload`（头 `x-gladia-key`）→ `POST /v2/pre-recorded` → 每 1 s 轮询 `GET /v2/pre-recorded/{id}` | 整文件 | `result.transcription.subtitles[0].subtitles`（直接要 SRT） | 典型的 ⓒ 型三步异步 |
| 自定义 API | `POST {url}?sk={key}`——**密钥在查询串里** | multipart 字段名 `audio` | `{"code": 0, "data": "<SRT 字符串>"}` | 修复前把 URL 整体 `.lower()`，大小写敏感的路径全坏；曾对服务端输出 `eval()` |
| 本地服务（WhisperX / Parakeet / STT） | OpenAI SDK 或自定义 `/api` | 整文件 | WhisperX 用 `diarized_json`；Parakeet、STT 直接要 `response_format: "srt"` | 本地服务要 SRT 省掉解析，但丢了置信度与词级信息 |

### 10.3 原实现修过的坑（2026-09-11，都是「看不出来」型）

- **重试次数、请求间隔在类定义时读设置**（装饰器参数、类属性默认值），用户改了设置要重启才生效。改成每次重试时读。
- **共享常量被就地修改**：`self.flag = PUNC_FLAGS` 后 `append(" ")`，中日韩任务把空格塞进全局标点表，后面的任务全受影响。
- **计数器在成功时也递增**（GLM-ASR），重试额度被成功请求吃光后片段静默变成空文本，最后的错误信息也是空的。
- **Gemini 的汇总段用了相对时间和空 `text`**：总时长恰好在断句上限内时整段被原样保留——输出一条**空字幕**，不报错。
- **未列举的 API 错误被吞掉返回 None**（Gemini 502 / 503），下游迭代 None 崩溃；应重新抛出让重试层处理。
- **302.AI 说话人编号不稳定**：用「当前条数」当新说话人编号，同一个人拿到不同编号。改成首次出现顺序。
- **百炼 flash 关了 TLS 校验、没有超时**，任意 400 / 422 终止整个任务（包括只是一片被审核拒掉）。
- **Faster-Whisper-XXL 的逐行正则吞掉了行尾 `\n`**，相邻字幕行被跳过——静默丢字幕。
- 缺密钥的提示永远写「Deepgram」——提示文案里的渠道名硬编码。

注：这次修复在分支 `fix/security-and-stt-bugs` 上，`archive/python/` 里存的是修复前的代码，上面的坏样子在归档里还能看到。

## 11. 审查清单

对一个项目的 ASR 支持逐条核对（每条都是一个静默失败的反面）：

1. 三种线格式是否分成了三个适配器；百炼是否按模型名后缀分发 ⓑ / ⓒ。
2. ⓐ 是否对每个模型发了它支持的 `response_format`；`gpt-4o-*-transcribe` 有没有被发 `verbose_json`。
3. ⓐ 整段上传前是否检查了文档规定的体积上限（OpenAI 25 MB）。
4. ⓑ 时间码是否来自切片位置；切片补的是静音还是邻段真实音频。
5. ⓑ `ASR_RESPONSE_HAVE_NO_WORDS` 是否按空文本处理。
6. 开了说话人分离时，所选路线是否真的会给编号；没给时有没有提示。
7. ⓒ 上传与下载有没有误带 `Authorization`；提交有没有带 `X-DashScope-OssResourceResolve`；`file` 是否在最后。
8. 403 / 404 是否按步骤区分「致命」与「回退一步」。
9. 429 是否不计失败、按 Retry-After 等待，等待能否取消。
10. 检查点匹配是按「记录过的段都对得上」还是按段数；ⓒ 是否三步分别续跑。
11. 任务参数是否入队即定死；语言「自动」时是否真的不发字段。
12. 识别跳过的空条是否被送去翻译或写进产物。
