# `wan3.0-video` 官方规范核查与修复计划

Created: 2026-11-19 · Baseline: `main` @ `1e102d8` · Status: Phase 1/2 WAN-01～08 已完成；Phase 3 音视频已实现并本地验收；WAN-09 实测及 file/link 待办

本文档记录对照阿里云百炼（Model Studio / DashScope）官方 `wan3.0-video` / `wan3.0-video-prime` API 文档核查后的问题清单与分阶段修复计划。执行完毕并验收通过后，按 [台账](README.md) 约定将结论归档至 `docs/plans/README.md`、`docs/api/qianwen-bailian.md` 和 `docs/architecture/generation-parameters.md`，并删除本施工文档。

## 核查范围与依据

- 官方文档：阿里云百炼 Model Studio 万相 3.0 视频生成 API 参考（`help.aliyun.com` / `alibabacloud.com`，涵盖 `wan3.0-video`、`wan3.0-video-prime`）
- 仓库基线代码：`main` @ `1e102d8`
- 相关架构约束：
  - [`../architecture/llm-three-layer.md`](../architecture/llm-three-layer.md)（三层边界与红线）
  - [`../architecture/generation-parameters.md`](../architecture/generation-parameters.md)（共享参数 schema、排队快照兼容、wire contract）
  - [`../api/qianwen-bailian.md`](../api/qianwen-bailian.md)（千问/百炼协议事实）

### 已确认对齐部分（无需返工）

- **模型识别与路由**：`lib/services/llm/model_family.dart` 已通过 `wan3*` + `-video` 将 `wan3.0-video` / `wan3.0-video-prime` 归入 `ModelFamily.openaiVideo`；`Vendors.dashscope` 与 `Vendors.dashscopeNative` 均声明 `videoProtocol: WireProtocol.dashscopeVideo`，中转站走 `/v1/videos`。
- **提交与轮询端点**：`POST {base}/services/aigc/video-generation/video-synthesis`（携带 `Authorization: Bearer`、`Content-Type: application/json`、`X-DashScope-Async: enable`）→ `GET {base}/tasks/{task_id}`（`checkEnvelope: false`、六态处理、`output.video_url` 签名直链下载不带认证头、`usage.duration` 结算）。
- **核心已对齐参数**：`parameters.resolution`（`480P`/`720P`/`1080P`，默认 `1080P`）、`parameters.audio`（`true`/`false`，默认 `true`）、`parameters.prompt_extend`（`not_set` 省略、`on`/`off` 显式下发）。
- **取消语义**：官方无标准视频任务 REST 取消端点，保持本地放弃轮询即可。

---

## 问题清单

| 编号 | 级别 | 类别 | 官方规范 vs. 当前实现 | 涉及文件 |
|---|---|---|---|---|
| **WAN-01** | P0 | 参考图互斥 | 官方规定 `first_frame` / `last_frame` 与 `reference_image` 等参考素材**严格互斥**（混发直接报 `InvalidParameter`）；`last_frame` 必须配 `first_frame`。当前 `WireProtocol.dashscopeVideo` 未注册到 `GenerationProtocolContract.declarations`，回退为 `exclusiveFrames: false`，UI 与 `validateGeneration` 均放行混发，`DashScopeVideoProtocol.submit` 会把首尾帧与参考图一起拼进 `input.media[]`。 | `lib/services/llm/protocols/generation_contract.dart`<br>`lib/services/llm/protocols/dashscope_video_protocol.dart` |
| **WAN-02** | P0 | 参考图校验 | 官方对 Wan 图像有硬限制：格式限 JPEG / JPG / PNG（**不支持透明通道**）/ BMP / WEBP，单张 ≤ 20 MB，单边 240–8000 px，长宽比 ≤ 8:1。仓库已有 `validateWanReference`，但 `validateGeneration` 仅对 `imageRequestShape == ImageRequestShape.dashscopeWan`（图片模型）触发，`wan3.0-video` 完全跳过校验。 | `lib/services/llm/generation/generation_validator.dart`<br>`lib/services/llm/generation/wan_reference_validation.dart` |
| **WAN-03** | P1 | 参数缺失 | 官方 `parameters.ratio` 支持 `adaptive`（默认）、**`21:9`**、`16:9`、`4:3`、`1:1`、`3:4`、`9:16`。当前 `_dashscopeWanVideo` 缺少 **`21:9`**。 | `lib/services/llm/generation/profiles/dashscope_profiles.dart` |
| **WAN-04** | P1 | 参考图上限 | 官方 `reference_image` 上限为 **10 张**（多模态素材总数上限 20）。当前 `_dashscopeWanVideo.maxReferenceImages` 设为 **9**（沿用了 `wan2.7-image` 的上限）。 | `lib/services/llm/generation/profiles/dashscope_profiles.dart` |
| **WAN-05** | P1 | 参数缺失 | 官方支持 `parameters.watermark`（boolean，默认 `false`）。仓库同家族图片模型已有 `_dashscopeImageWatermark` 控件且四语文案齐全，但 `_dashscopeWanVideo` 与 `DashScopeVideoProtocol` 未声明、未发送。 | `lib/services/llm/generation/profiles/dashscope_profiles.dart`<br>`lib/services/llm/protocols/dashscope_video_protocol.dart`<br>`lib/services/llm/generation/generation_validator.dart` |
| **WAN-06** | P1 | 接入域名 | 官方生产推荐使用业务空间专属域名 `https://{WorkspaceId}.{region}.maas.aliyuncs.com/api/v1/...`（`dashscope.aliyuncs.com` 仍兼容）。`dashscopeNativeBase` 路径推导已支持任意 host，但 `Platforms.dashscope.hosts` 未包含 `.maas.aliyuncs.com`，导致自定义入口填 MaaS 域名时无法自动识别为百炼平台。 | `lib/services/llm/vendors/platforms.dart` |
| **WAN-07** | P1 | 文档与测试 | ① 代码注释与 `docs/api/qianwen-bailian.md` 仍写“`audio: true` 默认计费/关掉省费”，而官方现注明 `audio: false` **不影响价格**；且协议文档 §6 缺 `21:9`、10 张参考图、互斥规则与 `maas.aliyuncs.com`；② 缺少专门覆盖 `DashScopeVideoProtocol` 请求体、互斥规则与 Wan 图像校验的单元测试。 | `lib/services/llm/protocols/dashscope_video_protocol.dart`<br>`lib/services/llm/generation/profiles/dashscope_profiles.dart`<br>`docs/api/qianwen-bailian.md`<br>`test/services/llm/` |
| **WAN-08** | P2 | 参数扩展 | 官方 `duration` 支持 `-1`（智能时长）；`input.prompt` 上限 20,000 字符且有 `media` 时允许空 prompt；支持 `seed`（`-1` 或 `[0, 2147483647]`）。当前仅支持 2–30s 整数滑块、UI 强制 prompt 非空、无 20,000 字符上限校验、无 `seed`。 | `lib/services/llm/generation/profiles/dashscope_profiles.dart`<br>`lib/screens/workbench/widgets/video/video_config_panel.dart`<br>`lib/services/llm/generation/generation_schema.dart` |
| **WAN-09** | P2 | 首尾帧比例 | 官方建议首帧/首尾帧下 `ratio` 设为 `adaptive`。当前默认值已是 `adaptive`，但未设 `frameRatioAdaptive: true`；在实测确认“首帧+固定比例”是生效、忽略还是 400 前，不宜贸然锁死。 | `lib/services/llm/protocols/generation_contract.dart` |
| **WAN-10** | P3 | 多模态素材 | 官方 `input.media[]` 还支持 `reference_video`（≤5段/≤15s/≤100MB）、`reference_audio`（≤5段/≤15s/≤15MB）、`file`/`link`（二选一且必须 `prompt_extend: true`），总素材 ≤20。当前未接入，且：① `generation_schema.dart` 的音视频限额（`3/3/12`）按 MiniMax 硬编码；② 百炼对大体积音视频 Base64 的容忍度/请求体上限未实测，且应用暂无对象存储上传通道。 | `lib/services/llm/generation/generation_schema.dart`<br>`lib/services/llm/protocols/dashscope_video_protocol.dart` |

---

## 实施状态

- [x] WAN-01：原生视频声明首尾帧与参考图互斥。
- [x] WAN-02：所有视频图片复用 Wan 本地硬校验，更新合法 RGB 测试夹具。
- [x] WAN-03 / WAN-04：21:9 与 10 张参考图能力表。
- [x] WAN-05：共用水印控件、纯函数 payload 与旧 v1 默认快照兼容。
- [x] WAN-06：MaaS 平台识别与原生路径推导。
- [x] WAN-07：协议/架构文档及 payload、校验、快照、域名单测与截图覆盖。
- [x] Phase 2 / WAN-08：独立 prompt 长度/必填契约、素材空提示词、智能时长、seed、默认快照兼容与四语控件。
- [ ] Phase 2 / WAN-09：固定首帧比例的真实上游行为仍待单独授权实测；保持默认 adaptive 和可编辑比例。
- [x] Phase 3 / WAN-10 音视频：官方 URL 约束确认、临时上传、本地硬校验、参数化限额及四语工作台。
- [ ] Phase 3 / WAN-10 file/link：独立输入槽位、二选一互斥和 prompt_extend 依赖设计。
- [ ] 真实区域账号上传与生成联调：本轮仅本地 mock，不调用付费上游。

- [x] Phase 1 验收：format 973 文件、0 变更；analyze `No issues found!`；
  非截图测试 3603 通过、11 skip；参数表和 Wan 工作台截图 56 项通过，
  手机滚动水印复拍的工作台 8 项亦通过。日志无溢出/截图异常。

- [x] Phase 2 / WAN-08 本地验收：format 975 文件、0 变更；analyze `No issues found!`；
  非截图测试 3608 通过、11 skip；参数表和 Wan 工作台截图 56 项通过。
  四宽度浅深色实图已查看，修复英文智能时长截断，日志无异常/溢出。

- [x] Phase 3 音视频本地验收：format 978 文件、0 变更；analyze `No issues found!`；
  非截图测试 3617 通过、11 skip；参数表与 Wan 工作台截图 64 项通过。
  四宽度浅深色素材卡实图已逐图查看，手机说明区补拍可见，无异常/溢出。

Phase 1/2 验收记录保留；本轮完成 Phase 3 音视频，WAN-09 实测与 file/link 保留，计划暂不删除。验证环境为 macOS、
Flutter 3.47.9 / Dart 3.13.7；未调用付费上游、未验证原生手机设备。
归档结论见 [台账](README.md) 各阶段条目。

## 修复计划

### Phase 1：协议对齐与防错修复（覆盖 WAN-01 ~ WAN-07，默认执行范围）

不涉及数据库 schema 变更，不新增 L10n key（`paramWatermark`、`promptExtendOn`/`Off`、`optionAuto`、`generationConflictingMedia` 等四语文案均已存在）。

#### 1.1 注册 DashScope 视频协议契约（WAN-01）
- 修改 `lib/services/llm/protocols/generation_contract.dart`：
  - 在 `GenerationProtocolContract.declarations` 中新增：
    ```dart
    WireProtocol.dashscopeVideo: GenerationProtocolContract(exclusiveFrames: true),
    ```
  - 说明：`lastFrame` 默认 `true`、`standaloneLastFrame` 默认 `false` 保持不变（支持首尾帧，禁止单独尾帧，禁止首尾帧与参考图混用）。

#### 1.2 补齐 Wan 视频参考图本地校验（WAN-02）
- 修改 `lib/services/llm/generation/generation_validator.dart`：
  - 将 20 MB 文件大小预检与 `validateWanReference(bytes)` 的触发条件，从仅检查 `schema.capabilities.imageRequestShape == ImageRequestShape.dashscopeWan`，扩展为同时覆盖 `schema.protocol == WireProtocol.dashscopeVideo`（提取清晰谓词如 `needsWanReferenceValidation`）。
  - 注意：`validateWanReference` 运行在 isolate 中，检查 ≤20 MB、JPEG/PNG/BMP/WEBP、240–8000 px、1:8–8:1、PNG 无 alpha 通道。
- **既有测试夹具适配**：
  - `test/services/llm/video_input_images_test.dart` 中 `wan3.0-video` 用例当前使用 1×1 `_png`（<240px），需改为合法的 ≥240×240 不含 alpha 通道的 PNG（参考同文件 MiniMax 用例的做法，并注意 `img.Image(width: 256, height: 256)` 默认 3 通道无 alpha）。

#### 1.3 更新能力表、抽取纯函数 payload builder 并接入 `watermark`（WAN-03 / WAN-04 / WAN-05）
- 修改 `lib/services/llm/generation/profiles/dashscope_profiles.dart`：
  - `_dashscopeWanVideo.maxReferenceImages`：`9` → `10`。
  - `_dashscopeWanVideo` 的 `aspectRatio` 选项追加 `ParamOption('21:9')`（顺序与官方一致：`adaptive`、`21:9`、`16:9`、`4:3`、`1:1`、`3:4`、`9:16`）。
  - `_dashscopeWanVideo.videoParams` 追加共用的水印控件（复用 `_dashscopeImageWatermark`，可重命名为 `_dashscopeWatermark`，保持 `key: 'watermark'`、`defaultValue: 'not_set'`、`options: [not_set, off, on]`）。
  - 修正 `_dashscopeWanVideo` 注释中关于 `videoAudio` 计费的过时描述。
- 修改 `lib/services/llm/protocols/dashscope_payload.dart` 与 `lib/services/llm/protocols/dashscope_video_protocol.dart`：
  - 抽取纯函数 `buildDashScopeVideoPayload(...)`（IO-free，便于单测），统一拼装 `model`、`input`（`prompt` + `media[]`）与 `parameters`（`audio`、`resolution`、`ratio`、`duration`、`prompt_extend`、`watermark`）。
  - 在 `buildDashScopeVideoPayload` 中：
    - `watermark`：`on` → `true`、`off` → `false`、`not_set`/缺省不发；
    - 防御性检查首尾帧与参考图互斥（`first_frame`/`last_frame` 不得与 `reference_image` 同发，单独 `last_frame` 缺 `first_frame` 拒绝），确保直接调用协议时也不会静默发错。
  - `DashScopeVideoProtocol.submit` 调用 `buildDashScopeVideoPayload`，修正 `audio` 注释（显式下发 `true`/`false`，不依赖上游默认，但注明关闭不影响价格）。
- **排队快照向后兼容（必须处理）**：
  - 修改 `lib/services/llm/generation/generation_validator.dart` 的旧快照缺失默认字段兼容判断：除 `schema.capabilities.imageRequestShape != ImageRequestShape.none` 外，允许 `schema.protocol == WireProtocol.dashscopeVideo` 的历史 v1 排队快照在缺失 `watermark` 字段且其有效值为默认 `not_set` 时通过校验，防止升级后已有排队 `wan3.0-video` 任务被误拒；显式变更的值仍须拒绝。

#### 1.4 补齐 MaaS 专属域名平台识别与文档同步（WAN-06 / WAN-07）
- 修改 `lib/services/llm/vendors/platforms.dart`：
  - `Platforms.dashscope.hosts` 增加 `'.maas.aliyuncs.com'`（与 Ark 的 `'.volces.com'` 同模式）。
- 更新 `docs/api/qianwen-bailian.md`：
  - 同步 §6（`wan3.0-video` / `wan3.0-video-prime`）：补入 `21:9`、10 张参考图上限、图片硬限制（20MB / 240–8000px / 1:8–8:1 / PNG 禁 alpha）、`first_frame`/`last_frame` 与 `reference_image` 互斥、`watermark`、`audio: false` 不影响价格、业务空间专属域名 `{WorkspaceId}.{region}.maas.aliyuncs.com`。
  - 追加 2026-11-19 `wan3.0-video` 复核记录与覆盖边界说明。
- 更新 `docs/architecture/generation-parameters.md`：
  - 补充一条简短的 `Wan 3.0 video` 契约/快照兼容说明（遵循同文件 `Qwen editing contract` / `GPT Image 2.6` 风格）。

#### 1.5 测试补齐与验收门禁
- 新增 `test/services/llm/dashscope_video_payload_test.dart`，覆盖：
  1. 默认参数与全参数 payload（`resolution` 大小写转换与 4k 钳位、`ratio` 含 `21:9`、`duration` 2–30 钳位、`audio`、`prompt_extend`、`watermark` 的 `not_set`/`on`/`off`）。
  2. `input.media[]` 角色映射与防御性互斥校验（首帧+参考图拒绝、尾帧缺首帧拒绝、纯参考图最多 10 张通过/11 张拒绝）。
  3. `validateGeneration` 对 `WireProtocol.dashscopeVideo` 触发 `validateWanReference`（PNG 带 alpha 拒绝、<240px 拒绝、>8:1 拒绝、合法 RGB PNG 通过）。
  4. 历史 v1 排队快照（缺少 `watermark`）在默认态下兼容通过，显式篡改 `watermark: on` 仍被拒绝。
  5. `Platforms.inferPlatform` 识别 `{WorkspaceId}.cn-beijing.maas.aliyuncs.com` / `ap-southeast-1.maas.aliyuncs.com` 为 `Platforms.dashscope`，且 `dashscopeNativeBase` 正确推导出 `https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1`。
- 必过三道代码门禁（提交前全绿）：
  1. `dart format lib test tool`
  2. `flutter analyze`（必须 `No issues found!`）
  3. `flutter test -x screenshots`
- UI 截图验收（因 `wan3.0-video` 表单新增 `watermark` 一行控件）：
  - 运行 `flutter test test/screenshots/generation_params_shots_test.dart`（及相关工作台视频面板截图），检查 `build/ui-screenshots/` 在 390 / 834 / 1024 / 1440 浅深色下无溢出。

---

### Phase 2：参数与交互增强（WAN-08 已实现；WAN-09 实测待办）

本轮基于合并 PR #417 后 `main` @ `df646dd`，分支 `codex/wan3-video-phase2`。
交互简报：保留现有模型参数卡和控件层级，时长改为下拉菜单（智能/2–30s），
默认仍为 5 秒；seed 全行数字输入，空值表示随机。复用 AppDropdown/AppTextField、
既有间距与浅深色主题；窄屏沿用滚动面板。依据维护中的设计规范与 Phase 1 实际截图，
基线副本保存在 `/tmp/wan-phase2-before/`。验收覆盖四语、四宽度、浅深色，以及
空提示词按钮随素材增删变化、seed 边界/清空、智能时长与快照往返。

1. **Prompt 20,000 字符上限与空 prompt 策略（已实现）**：
   - `promptMaxCharacters`、`promptRequired`、`promptOptionalWithMedia` 独立声明；
     原生 Wan 接受有素材的空提示词，按 Unicode 码点计数，超长提交显示四语提示。
     MiniMax 保留必填和 7,000 字符限制。素材本身仍经独立校验。
2. **`duration: -1` 智能时长（已实现）**：
   - 下拉选择智能或 2–30 秒，保留默认 5 秒。智能值直接编码为 -1，
     不新增 autoDuration 状态或改变已有排队任务的时长。时长全行展示避免长文案截断。
3. **`seed`（已实现）与 `frameRatioAdaptive`（待实测）**：
   - 共用整数编辑器仅由原生 Wan profile 声明；不向其他视频协议推广。
     空值 `not_set` 省略，-1 或 0–2147483647 下发整数；旧快照可缺默认值，
     显式篡改拒绝。四语源文件合并和生成已完成。
   - 本轮仅本地测试/截图，不调用付费上游。WAN-09 真实首帧+固定比例行为
     仍未确认，继续保留 adaptive 默认及可编辑比例；不启用强制锁定。

---

### Phase 3：音视频参考与临时上传（WAN-10 阶段实现）

基于 PR #418 合并后的 `main` @ `3d51240`，分支 `codex/wan3-video-phase3`。
按计划推荐，将 file/link 留待独立设计；本轮完成音视频、上传与素材限额。

1. **官方约束确认**：复核[视频 API](https://help.aliyun.com/zh/model-studio/wan3-video-generation-api-reference)
   和[临时上传](https://help.aliyun.com/zh/model-studio/get-temporary-file-url/)。
   音视频使用 HTTP(S)/OSS URL；无 Base64 请求体探针。临时存储 48 小时、模型/账号绑定，
   仅北京/新加坡；MaaS 映射到同区域 policy API，自定义网关沿用 base。
2. **契约与校验**：将 3/3/12 参数化，Wan 5/5/20、MiniMax 原值保留。
   图片仍检查 20 MB/Wan 格式规格；视频 100 MB、240–4096 px、1:8–8:1、≥16 fps；
   音频 15 MB；单段 1–15 秒、每类总长 ≤15 秒、输入视频+固定输出 ≤30 秒。
   全部校验完后再上传，私有临时副本防止校验后源文件改变。智能 -1 交给上游。
3. **上传与任务生命周期**：签名 multipart 不带 API key，复用 consent/proxy/abort；
   policy/上传不触发付费 body-sent，仅 synthesis 触发。临时 URL 不持久化，失败重试重新上传，
   已接单任务恢复只轮询。音视频不计入输入图片数；视频秒数随 ticket 返回。
   清理副本失败不会丢失已经接受的任务句柄。素材空提示词可正确入队，无 DB 迁移。
4. **交互简报**：沿用现有参考文件卡、按钮、移除动作与停放素材行为，
   四语提示按契约显示数量/时长，Wan 增加格式、大小、临时上传期限说明。
   四宽度浅深色截图覆盖参数卡及实际音视频素材卡；基线 `/tmp/wan-phase3-before/`。
5. **继续待办**：file/link 工作台输入、二选一约束、prompt_extend:true 依赖独立立项；
   WAN-09 固定首帧比例与真实区域账号上传/生成联调仍需单独授权，不能把本地 mock 当作线上验收。
