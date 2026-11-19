# 视频编辑与视频延长功能设计文档（跨模型通用架构 · Wan 3.0 首发）

Created: 2026-11-19 · Status: 设计评审中（Design Only） · First Target: `wan3.0-video` / `wan3.0-video-prime`

> 本设计严格遵循 [`docs/architecture/llm-three-layer.md`](../architecture/llm-three-layer.md)（三层边界与硬编码红线）、[`docs/architecture/generation-parameters.md`](../architecture/generation-parameters.md)（共享参数 schema / v1 快照兼容 / 偏好隔离）、[`docs/architecture/media-accounting.md`](../architecture/media-accounting.md)（媒体计费结算）与 [`docs/architecture/ui-design-workflow.md`](../architecture/ui-design-workflow.md)（`joycai-ui-design` 视觉契约）。
>
> **参考依据**：
> - 阿里云百炼官方《万相 3.0 视频生成使用指南》（`wan3-video-generation-guide`）
> - 阿里云百炼官方《万相 3.0 视频生成 API 参考》（`wan3-video-generation-api-reference`）
> - 阿里云百炼官方《万相 3.0 视频生成 Prompt 指南》（`wan3-video-generation-prompt-guide`）
> - 仓库既有协议记录：[`docs/api/qianwen-bailian.md`](../api/qianwen-bailian.md)、[`docs/api/minimax.md`](../api/minimax.md)、[`docs/api/veo.md`](../api/veo.md)、[`docs/plans/2026-11-wan3-video-audit.md`](2026-11-wan3-video-audit.md)

---

## 1. 背景、问题与设计目标

### 1.1 当前基线

截至 Wan 3.0 Phase 1–3（`WAN-01`～`WAN-10` 音视频阶段），应用已经具备完整的视频生成底层能力：

- **三层协议栈**：`DashScopeVideoProtocol`（`POST /api/v1/services/aigc/video-generation/video-synthesis` + `GET /api/v1/tasks/{task_id}`）、百炼临时 OSS 上传（`dashscope_upload.dart`）、本地 MP4/MOV/WAV/MP3 容器探测（`reference_media_probe.dart`）、Wan 图像硬校验（`wan_reference_validation.dart`）。
- **声明式参数与快照**：`GenerationProtocolContract` + `GenerationSchema` + `GenerationRequest`（v1 编解码，免 DB 迁移）+ `GenerationPreferences`（按模型/渠道/协议/操作隔离草稿）。
- **工作台与闭环**：视频配置面板（模型参数、首尾帧、参考图、音视频参考文件）、画廊视频展示与预览、底部结果播放器 `VideoWorkbenchOverlay`。

### 1.2 为什么「已支持参考视频」≠「已支持视频编辑与视频延长」

虽然 Wan 3.0 Phase 3 允许用户在「参考素材」中附加 `reference_video`，但距离真正的**视频编辑**与**视频延长**功能仍存在六类结构性缺口：

1. **缺乏跨模型的一等操作语义**：Wan 3.0 碰巧通过同一端点 + `reference_video` + 提示词意图实现编辑与延长，但 xAI Grok 使用独立端点 `/v1/videos/edits` 与 `/v1/videos/extensions`、Google Veo 3.1 使用 `instances[0].video`、OpenAI Sora 2 使用 `/v1/videos/{id}/remix`。如果不把「编辑 / 延长」抽象为 `GenerationOperation` 与专属 `sourceVideo` 角色，后续接入其他视频模型时无法路由。
2. **源视频与辅助参考视频混杂**：编辑/延长必须明确区分「被操作的唯一主视频（在 Wan 3.0 中恒为 `视频1`）」与「可选辅助参考素材（参考图 `图1`、参考音频 `音频1`、额外参考视频）」，当前只有扁平的 `videoReferenceVideos` 列表。
3. **表单摩擦与默认值错误**：
   - 编辑/延长时，首尾帧（`first_frame`/`last_frame`）与视频输入互斥；当前面板仍常驻首尾帧卡，用户稍有残留就会触发 `conflictingMedia` 报错。
   - Wan 3.0 文档明确建议编辑与延长将 `duration` 设为 `-1`（智能时长）、`ratio` 设为 `adaptive`；当前文本生成默认 `duration: 5`，直接编辑 10 秒视频会意外截断，且修改后会覆盖用户的文生视频偏好。
   - Wan 3.0 延长支持 **向后 / 向前 / 双向** 三种方向，当前既无方向选择，也无意图提示或素材编号（`视频1`/`图1`）辅助。
4. **缺少从成品到二次创作的闭环入口**：
   - `VideoWorkbenchOverlay`（刚生成的视频播放器）只有「在系统播放器中打开」和「关闭」，无法一键「编辑此视频 / 延长此视频」。
   - 画廊视频卡右键菜单（`image_card_context_menu.dart`）只有预览/文件/导出/删除，没有任何送往视频工作台的入口。
   - 画廊视频卡本身已是 `Draggable<AppImage>`，但视频面板所有拖放区都只接受图片（`_isDroppableImage`），视频拖入无处可放。
5. **缺少入队前的源视频元数据反馈与时长预算校验**：用户选中视频后只看到文件名，看不到缩略图、分辨率、帧率与时长；例如刚用 Wan 3.0 生成了一段 20 秒视频（生成上限 30s），再拿去编辑/延长（输入上限 15s）或设了超限的固定输出时长（输入 + 输出 > 30s），只能在后台执行时才失败。
6. **存量计费结算缺陷（重要发现）**：Wan 3.0 API 返回的 `usage` 同时包含 `duration`（= `input_video_duration + output_video_duration`）、`input_video_duration` 和 `output_video_duration`。当前 `DashScopeVideoProtocol.poll` 直接把 `usage['duration']` 传给 `renderedSeconds`，导致携带输入视频（参考生视频 / 编辑 / 延长）的任务在结算时将**输入时长计入输出时长，造成双重计费**。

### 1.3 设计目标与边界

- **通用优先，Wan 3.0 首发**：先抽象跨模型的视频编辑/延长契约、操作类型、媒体角色与工作台交互，再以 `wan3.0-video` / `wan3.0-video-prime` 作为首个实现；后续接入 xAI Grok、Veo 3.1、Sora 2 时仅扩展 Layer 1 协议与 Layer 3 能力声明，不改工作台骨架。
- **严守架构纪律**：不绕过 `LLMDispatcher`、不在 UI/状态层做模型 ID 或厂商字符串判断、不新增数据库表/列迁移、不破坏历史 v1 任务快照与断点续轮询。
- **非目标（本轮不做）**：
  - 不在本地引入 FFmpeg / 视频剪辑时间轴 / 涂鸦遮罩编辑（均属独立重型编辑器范畴）。
  - 不顺带实现 `WAN-10` 的 `file`/`link` 文档网页输入（保持独立设计）。
  - 不在首版将视频送入 Prompt Assistant（当前助手参考附件体系为图片）。

---

## 2. 官方协议事实与跨模型对照

### 2.1 Wan 3.0 视频编辑与视频延长协议事实

以下事实全部核自阿里云百炼官方文档（2026-11-19 抓取）：

| 维度 | 视频编辑（Video Editing） | 视频延长（Video Extension） |
|---|---|---|
| **模型与端点** | `wan3.0-video` / `wan3.0-video-prime`；统一异步端点 `POST {base}/services/aigc/video-generation/video-synthesis` + `X-DashScope-Async: enable` + `X-DashScope-OssResourceResolve: enable` | 同左（All-in-One 单端点，由 `input.media` 与提示词意图路由） |
| **核心输入素材** | 待编辑视频以 `{"type": "reference_video", "url": "oss://..."}` 传入（在提示词中为 `视频1`）；**可组合** `reference_image`（如参考编辑换装/加物件，`图1`/`图2`…）与 `reference_audio`（`音频1`…） | 待延长原视频以 `{"type": "reference_video", "url": "oss://..."}` 传入（`视频1`）；可组合 `reference_image` / `reference_audio` |
| **互斥约束** | 与 `first_frame` / `last_frame` 严格互斥；不可混发 | 同左 |
| **视频文件规格** | MP4 / MOV；单段 **1–15 秒**，全部参考视频合计 **≤ 15 秒**（最多 5 段）；单文件 **≤ 100 MB**；边长 **240–4096 px**；长宽比 **≤ 8:1**；帧率 **≥ 16 fps**；仅支持公网 HTTP(S) 或百炼临时 OSS URL（`oss://`），不发 Base64 | 同左 |
| **素材总量上限** | 图像 ≤ 10、视频 ≤ 5、音频 ≤ 5、全部素材合计 ≤ 20 | 同左 |
| **提示词规则** | 支持中英文，≤ 20,000 字符；需含明确编辑意图（如「编辑视频」「去掉」「替换」「改成」「转换风格」「台词改为」等），可用「视频1」「图1」「音频1」指代；未指定修改部分保持不变 | 支持中英文，≤ 20,000 字符；需含明确延长意图关键词（如「延长」「延续」「续写」「向前/向后延长」等），描述新增镜头/动作/台词及延续角色特征 |
| **延长方向** | 不适用 | 支持 **向后延长**（尾帧续写）、**向前延长**（首帧前序）、**双向延长**（原视频为中间段同时前后续写） |
| **参数建议与约束** | `ratio` 建议 `adaptive`；`duration` 建议 `-1`（自动保持原视频时长）；固定 `duration` 时仍须满足 `输入视频总时长 + 输出时长 ≤ 30s`；支持 `resolution`（480P/720P/1080P）、`audio`、`prompt_extend`、`watermark`、`seed` | `ratio` 建议/需设为 `adaptive`；`duration` 建议 `-1`（智能时长），或指定 **最终输出视频总时长（输入视频时长 + 预期延长时长）**；固定 `duration` 时须满足 `输入视频总时长 + 输出时长 ≤ 30s`；其余参数同左 |
| **临时上传地域** | 百炼临时上传接口 `GET /api/v1/uploads?action=getPolicy` 仅官方 **北京**、**新加坡** 支持（有效期 48h，绑定模型与账号）；自定义网关沿用原生 base；其余官方地域（东京/法兰克福/弗吉尼亚/香港）本地拒绝 | 同左 |
| **轮询与计费回包** | `GET {base}/tasks/{task_id}`；结果 `output.video_url`（MP4 H.264 30fps，24h 有效，签名直链不带认证头）；`usage` 含 `duration`（输入+输出总和）、`input_video_duration`、`output_video_duration`、`SR`、`ratio`、`fps` | 同左 |

### 2.2 跨模型能力对比（决定通用抽象边界）

为保证架构不绑定 Wan 3.0，设计阶段横向对齐主流视频模型：

| 维度 | Wan 3.0 (`dashscopeVideo`) | xAI Grok Video (`xaiVideos`) | Google Veo 3.1 (`geminiVeo`) | OpenAI Sora 2 (`openaiVideos`) | MiniMax H3 (`minimaxVideo`) |
|---|---|---|---|---|---|
| **支持操作** | 生成 / **编辑** / **延长** | 生成 / **编辑** / **延长** | 生成 / **延长**（无通用编辑） | 生成 / **编辑(Remix)** / **延长** | 生成（含 Ref2V） |
| **协议路由方式** | 同端点 + `reference_video` + 意图提示词 | **独立端点**：`/v1/videos/edits`、`/v1/videos/extensions` | 同端点 `:predictLongRunning` + `instances[0].video` | **独立端点**：`/v1/videos/{id}/remix`、`/extensions` | 同端点 `/v2/video_generation` |
| **源视频输入形态** | 本地视频文件（临时 OSS 上传） | 本地视频 / URL / xAI `file_id` | **上游远端视频句柄**（Veo 产物 URI，约 48h 有效） | **上游 `video_id`** 或上传视频 | 本地视频（内联 data URI） |
| **附加参考素材** | 编辑/延长均支持图/音/额外视频 | 单主视频为主（不含首尾帧） | 仅源视频 | 仅源视频 / 文本 | — |
| **延长方向** | **向后 / 向前 / 双向** | 向后（部分版本支持 `start_time` 分支） | 仅向后 | 仅向后 | — |
| **时长参数语义** | `-1` 或 **最终总输出秒数**（且输入+输出 ≤ 30s） | **新增延长秒数**（2–10s）；编辑沿用原时长（不可调） | **固定增量 +7s**（单次不可自由调秒） | 视端点而定 | — |
| **比例/分辨率规则** | 推荐 `adaptive`；分辨率 480P/720P/1080P | 跟随源视频（编辑/延长不传或受限 720p） | **必须与原视频比例一致**（不一致 400）；720p | 跟随源视频 | — |

**架构抽象结论**：不同厂商在端点路径、源视频承载方式（本地文件 vs 远端句柄）、时长语义（总时长 vs 增量 vs 固定步长）、方向选项与附加素材上差异显著，但对上层应用来说，它们都归结为同一套语义模型：
- **操作**（`GenerationOperation`：`editVideo` / `extendVideo`）
- **唯一源视频角色**（`GenerationMediaRole.sourceVideo`）
- **声明式协议契约**（`VideoEditContract` / `VideoExtendContract`）

---

## 3. 系统架构设计

### 3.1 不新增 `TaskType`，以 `GenerationOperation` 表达视频编辑与延长

**决策**：视频编辑与视频延长继续复用 `TaskType.videoGenerate`，通过 `GenerationOperation` 区分具体操作，完全沿用 Seedream 5.0 Pro `imageTask`（`generate` / `layers` / `transparent`）的既定模式。

- **优点**：
  - 自动复用异步提交、持久化 `operation_name` / `operation_surface` / `video_usage_row_id`、重启断点续轮询、结果下载验收、失败/取消处理、结果文本伴生文件与结果播放器通知。
  - **零数据库 Schema 迁移**：所有操作类型、参数与媒体角色继续保存在 `tasks.parameters['generation']`（`GenerationRequest` v1 JSON）。
- **枚举扩展**（`lib/services/llm/generation/generation_schema.dart`）：
  ```dart
  enum GenerationOperation {
    textImage,
    editImage,
    subjectImage,
    layers,
    transparent,
    textVideo,
    firstFrame,
    firstLastFrame,
    referenceVideo,
    editVideo,    // 新增：视频编辑
    extendVideo,  // 新增：视频延长
  }
  ```
- **模式参数（Layer 3 Profile 声明）**：
  - `videoTask`：`ParamControl.segmented`，`defaultValue: 'generate'`，`options` 由模型 profile 按支持能力声明（Wan 3.0 声明 `['generate', 'edit', 'extend']`；未来 Veo 3.1 声明 `['generate', 'extend']`；不支持编辑/延长的模型**不声明**此参数）。
  - `extendDirection`：`ParamControl.segmented`，`defaultValue: 'backward'`，`options` 由模型声明（Wan 3.0 声明 `['backward', 'forward', 'bidirectional']`；仅支持单向延长的模型不声明此参数）。

### 3.2 新增专属源视频角色 `sourceVideo`

为彻底分离「被编辑/被延长的主视频」与「辅助参考视频」，在两处枚举新增对称角色：

1. `GenerationMediaRole.sourceVideo`（`lib/services/llm/generation/generation_schema.dart`）
2. `LLMReferenceType.sourceVideo`（`lib/services/llm/llm_messages.dart`）

**全链路流转**：

```text
WorkbenchUIState.videoSourceVideoPath
  → GenerationMedia(GenerationMediaRole.sourceVideo, path)
  → GenerationRequest.media[]  (v1 JSON: {"role": "sourceVideo", "path": "..."})
  → GenerationRequest.legacyOptions['sourceVideoPath']   (只读兼容视图)
  → snapshotTaskMedia()  (singles 列表加入 'sourceVideoPath'，同步拷贝私有快照至 media/tasks/)
  → task_executors._submitVideoJob()  (构造 LLMAttachment(..., referenceType: LLMReferenceType.sourceVideo)，不经过图片压缩)
  → Layer 1 协议：
      - DashScopeVideoProtocol: 映射为 {"type": "reference_video", "url": ossUrl} 且强制排在所有 reference_video 首位（保证恒为「视频1」）
      - 未来 XaiVideosProtocol: 映射为顶层 payload['video'] = {'url': ...}
      - 未来 GeminiVeoProtocol: 映射为 instances[0]['video'] = {'uri': ...}
```

### 3.3 声明式协议契约扩展（Layer 1 / Layer 3）

在 `lib/services/llm/protocols/generation_contract.dart` 中增加两个不可变 `const` 值对象，挂在 `GenerationProtocolContract` 上（沿用 `GenerationProtocolContract.forWire(protocol)` 与 `ModelCapabilities.nativeVideoContract` 覆写机制）：

```dart
enum VideoSourceKind {
  /// 本地视频文件（经协议上传或内联编码，如 Wan 3.0、xAI Grok）。
  localFile,
  /// 上游服务端视频句柄（如 Veo 3.1 文件 URI、Sora 2 video_id，预留扩展）。
  remoteHandle,
  either,
}

enum VideoExtendDirection { backward, forward, bidirectional }

enum VideoExtendDurationSemantics {
  /// 参数 duration 表示最终输出视频的总时长（原视频 + 延长部分），或 -1 智能时长（Wan 3.0）。
  totalOutputSeconds,
  /// 参数 duration 仅表示新增延长片段时长（如 xAI Grok）。
  addedSeconds,
  /// 每次固定增量，不支持自由设置秒数（如 Veo 3.1 +7s）。
  fixedIncrement,
}

enum VideoAspectPolicy {
  /// 允许编辑，默认 adaptive（Wan 3.0）。
  recommendedAdaptive,
  /// 强制锁定 adaptive（`GenerationFieldState.fixed`）。
  fixedAdaptive,
  /// 跟随源视频，隐藏比例控件（`GenerationFieldState.inactive`，如 xAI Grok）。
  inherited,
  /// 允许选择但要求与源视频一致（如 Veo 3.1）。
  mustMatchSource,
}

class VideoEditContract {
  const VideoEditContract({
    this.sourceKind = VideoSourceKind.localFile,
    this.allowsReferenceImages = false,
    this.allowsReferenceAudio = false,
    this.allowsExtraReferenceVideos = false,
    this.promptRequired = true,
    this.durationEditable = true,
    this.defaultDuration,
    this.aspectPolicy = VideoAspectPolicy.recommendedAdaptive,
    this.minSourceSeconds = 1,
    this.maxSourceSeconds = 15,
    this.maxCombinedSeconds,
    this.promptRouted = false,
  });
  // ...final fields
}

class VideoExtendContract {
  const VideoExtendContract({
    this.sourceKind = VideoSourceKind.localFile,
    this.directions = const [VideoExtendDirection.backward],
    this.allowsReferenceImages = false,
    this.allowsReferenceAudio = false,
    this.allowsExtraReferenceVideos = false,
    this.promptRequired = true,
    this.durationSemantics = VideoExtendDurationSemantics.totalOutputSeconds,
    this.defaultDuration,
    this.aspectPolicy = VideoAspectPolicy.recommendedAdaptive,
    this.minSourceSeconds = 1,
    this.maxSourceSeconds = 15,
    this.maxCombinedSeconds,
    this.promptRouted = false,
  });
  // ...final fields
}
```

**`WireProtocol.dashscopeVideo` 契约声明**：

- `videoEdit`:
  - `sourceKind: VideoSourceKind.localFile`
  - `allowsReferenceImages: true`、`allowsReferenceAudio: true`、`allowsExtraReferenceVideos: true`
  - `promptRequired: true`、`durationEditable: true`、`defaultDuration: '-1'`
  - `aspectPolicy: VideoAspectPolicy.recommendedAdaptive`
  - `minSourceSeconds: 1`、`maxSourceSeconds: 15`、`maxCombinedSeconds: 30`
  - `promptRouted: true`
- `videoExtend`:
  - `sourceKind: VideoSourceKind.localFile`
  - `directions: [backward, forward, bidirectional]`
  - `allowsReferenceImages: true`、`allowsReferenceAudio: true`、`allowsExtraReferenceVideos: true`
  - `promptRequired: true`、`durationSemantics: VideoExtendDurationSemantics.totalOutputSeconds`、`defaultDuration: '-1'`
  - `aspectPolicy: VideoAspectPolicy.recommendedAdaptive`
  - `minSourceSeconds: 1`、`maxSourceSeconds: 15`、`maxCombinedSeconds: 30`
  - `promptRouted: true`

> **中转站隔离原则**：`WireProtocol.openaiVideos` 不声明 `videoEdit` / `videoExtend`，因此挂在中转站的 `wan3.0-video` 不会错误暴露原生百炼的编辑/延长控件（遵守 `generation-parameters.md`「原生能力不越权覆盖中转协议」原则）。

### 3.4 Schema 状态机、操作级默认值与偏好隔离

1. **`GenerationSchema.operation(values, media)`**：
   - 当 `isVideo` 为真时，优先读 `values['videoTask']?.value`：`'edit'` → `editVideo`、`'extend'` → `extendVideo`；其余走原有首尾帧/参考/文生推断，对既有行为 100% 兼容。
2. **`GenerationSchema.fieldState(key, operation, values)`**：
   - `key == 'extendDirection'`：仅 `operation == GenerationOperation.extendVideo` 且 `contract.videoExtend != null` 时为 `active`，其余全部 `inactive`。
   - `key == 'seconds'`：
     - `editVideo` 且 `contract.videoEdit?.durationEditable == false` → `inactive`；
     - `extendVideo` 且 `contract.videoExtend?.durationSemantics == fixedIncrement` → `inactive`。
   - `key == 'aspectRatio'`：根据当前操作的 `aspectPolicy` 返回 `active` / `fixed`（`adaptive`）/ `inactive`。
3. **操作级默认值（关键细节）**：
   - 新增 `GenerationSchema.defaultValueFor(String key, GenerationOperation operation)`（及字符串辅助 `defaultStringFor(ParamSpec spec, GenerationOperation operation)`）：
     - 在 `editVideo` 下，若 `contract.videoEdit?.defaultDuration != null` 且 `key == 'seconds'`，返回该默认值（Wan 3.0 为 `-1` 智能时长）；`key == 'aspectRatio'` 若为 `recommendedAdaptive`/`fixedAdaptive` 则默认 `'adaptive'`。
     - 在 `extendVideo` 下同理读取 `contract.videoExtend?.defaultDuration`（Wan 3.0 为 `-1`）。
     - 在 `generate` 相关操作下，继续返回 `ParamSpec.defaultValue`（Wan 3.0 保持 `5s`，不改变现有文生/图生视频默认行为与测试）。
4. **修复 `AppStateWorkbench.effectiveVideoParams` 与偏好隔离**：
   - 当前 `app_state_workbench.dart` 的 `effectiveVideoParams` 直接返回所有 `caps.videoParams`，没有像 `effectiveImageParams` 一样经过 `schema.effective(draft, operation)` 过滤。改造为显式经过 `schema.effective(draft, operation)`，确保非延长模式下 `extendDirection` 不会泄漏进任务参数。
   - `GenerationPreferences.key(base, operation, param)` 将 `param == 'videoTask'` 与 `'imageTask'` 同等处理，存入 `$base.mode`；其余参数按 `$base.editVideo.<param>` / `$base.extendVideo.<param>` 独立存储。
   - `storedVideoParam` 在 `editVideo` / `extendVideo` 操作下**不回退读取旧 `${family}.<param>` 家族键**，防止历史文生视频配置（如 `seconds: 5`、`aspectRatio: 16:9`）污染首次进入编辑/延长模式时的推荐默认值（`-1` / `adaptive`）。
5. **提示词必填策略**：
   - `GenerationSchema.allowsEmptyPrompt(media, {GenerationOperation? operation})`：在 `editVideo` / `extendVideo` 下当对应契约声明 `promptRequired: true` 时恒返回 `false`——编辑与延长绝不允许空提示词提交。
6. **历史 v1 快照向后兼容**：
   - `validateGeneration`（`lib/services/llm/generation/generation_validator.dart`）将 `'videoTask'` 加入 `WireProtocol.dashscopeVideo` 允许历史快照省略默认值的集合（仅当有效值为默认 `'generate'` 时放行；显式修改仍拒绝）。`extendDirection` 在 `generate` 下为 `inactive`，不参与比对。

### 3.5 Wan 3.0 提示词意图路由机制（Layer 1 封装 + UI 透明预览）

Wan 3.0 的 All-in-One 端点不提供独立的 `mode` 或 `direction` JSON 字段，而是通过提示词中的意图关键词区分「全模态参考生成」「视频编辑」「向前/向后/双向延长」。

**方案对比与取舍**：
- *纯静默拼接*：可能与用户自己写的关键词冲突（重复或方向打架），且用户不知情，违背透明性原则。
- *完全不处理*：用户选了「向前延长 / 双向延长」却对线上请求毫无影响，构成「虚设旋钮（lying knob）」。
- **采用方案（语义参数 + 幂等双语前缀合成 + UI 透明预览）**：
  1. `GenerationRequest` 保存用户原始 `prompt` 及结构化 `operation` / `extendDirection`，保证提示词历史、重试快照与未来非提示词路由协议（Grok / Veo / Sora）完全纯净。
  2. 在 `lib/services/llm/protocols/dashscope_payload.dart` 提供纯函数 `composeDashScopeIntentPrompt({required String prompt, required GenerationOperation operation, String? extendDirection})`：
     - **幂等检测**：若用户提示词已包含对应模式的显式意图词，**原样返回不修改**：
       - `editVideo` 已有词例：`编辑视频`、`修改视频`、`重塑视频`、`视频1中的`、`将整个画面`、`替换`、`去掉`、`删除`、`改成`、`改为`、英文 `edit video` / `edit the video` / `replace` / `remove` / `change ... to` / `convert ... to` 等。
       - `extendVideo` 已有词例：`延长`、`延续`、`续写`、`向前`、`向后`、英文 `extend` / `continue` / `prepend` / `append`。
     - **未检测到意图词时**，按提示词语言（含汉字且无假名 → 中文；否则 → 英文）附加简洁、确定的前缀：
       - `editVideo` → `编辑视频，` / `Edit Video 1: `
       - `extendVideo` + `backward` → `将视频1向后延长，` / `Extend Video 1 backward from its last frame: `
       - `extendVideo` + `forward` → `将视频1向前延长，` / `Extend Video 1 forward before its first frame: `
       - `extendVideo` + `bidirectional` → `以视频1为中间段向前向后双向延长，` / `Extend Video 1 in both directions before the start and after the end: `
     - **方向冲突保护**：若用户选了 `forward` 但提示词里自己写了 `向后延长`，UI 给出柔和提示而非强行改写。
  3. **UI 透明化**：在编辑/延长模式下，若当前输入未含意图词，提示词框上方/下方以一行低饱和说明展示**将自动附加的意图前缀**（并允许一键将其直接插入编辑框以便自定义如「向前延长 15s」「向前续写 2 秒……向后续写 3 秒……」的精细写法）；一旦用户输入了显式意图词，该提示自动消失。
  4. **调试日志可见**：`DashScopeVideoProtocol` 调试日志落盘最终发送的 `input.prompt`，便于排查路由效果。

### 3.6 上传、预检与计费结算修复（DashScope Wire 层）

1. **`DashScopeVideoProtocol.submit` 适配**：
   - `needsUpload` 判断补入 `att.referenceType == LLMReferenceType.sourceVideo`。
   - `dashscopeVideoMediaRole` 将 `LLMReferenceType.sourceVideo` 映射为 `'reference_video'`。
   - **排序不变量**：构造上传与 `input.media[]` 时，确保 `sourceVideo` 恒在所有 `referenceVideo` 之前，使源视频始终绑定 **`视频1`**。
   - `inputImages` 统计排除 `sourceVideo`、`referenceVideo`、`referenceAudio`（仅计实际图片数）。
   - `buildDashScopeVideoPayload` 接收 `operation`（可从 `options['videoTask']` 推导），执行防御性校验：`edit`/`extend` 至少包含 1 个 `reference_video` 且提示词非空、与 `first_frame`/`last_frame` 互斥；超过 20,000 Unicode 码点（含附加前缀后的最终提示词）本地拒绝。
2. **修复 `DashScopeVideoProtocol.poll` 计费双重计数问题（P0）**：
   - 官方 API 文档（`wan3-video-generation-api-reference`）：
     - `usage.duration` = `input_video_duration + output_video_duration`（有视频输入时为两者之和！）
     - `usage.input_video_duration` = 输入视频秒数
     - `usage.output_video_duration` = 输出视频秒数
     - `usage.SR` = 实际输出分辨率（如 `720` / `1080`）
   - 修正 `DashScopeVideoProtocol.poll` 返回的 `videoDoneEnvelope`：
     ```dart
     final usage = data['usage'];
     final sr = usage is Map ? usage['SR'] : null;
     return videoDoneEnvelope(
       operationName,
       videoUrl,
       requiresAuth: videoUriNeedsAuth(videoUrl, config.endpoint),
       renderedSeconds: usage is Map
           ? (usage['output_video_duration'] ?? usage['duration'])
           : null,
       inputSeconds: usage is Map ? usage['input_video_duration'] : null,
       outputSize: sr is num && sr > 0 ? '${sr.toInt()}p' : null,
     );
     ```
   - `task_executors.dart` 与 `MediaAccounting.settle` 已原生支持 `input_video_seconds` 与 `output_size`，修改后输入视频秒数与输出视频秒数各自按对应费率准确结算，不再重复计费；智能时长 `-1` 在提交时按未知预估，完成后按 `output_video_duration` 精确结算。
3. **沙盒、隐私授权与地域限制**：
   - 源视频经 `PersistentMediaService.instance.importFile(path, appleBookmark: ...)` 导入私有目录，入队时经 `snapshotTaskMedia`（`singles` 新增 `'sourceVideoPath'`）固化至 `media/tasks/`，满足 macOS App Sandbox（MAS-02）与 Windows MSIX（WIN-02）。
   - 上传复用 `config.createClient()`，完整受控于 `AiConsentService`（MAS-04）、代理、取消令牌、`followRedirects = false` 及 API Key 隔离，仅最终 `video-synthesis` POST 触发 `llmBodySentKey`。
   - 新增只读纯函数 `dashscopeSupportsTemporaryUpload(String endpoint)`（封装 `dashscopeUploadBase` 判断），供 UI 在百炼非北京/新加坡官方地域（如东京、法兰克福、弗吉尼亚、香港）下前置提示「当前地域不支持临时视频上传，无法执行本地视频编辑/延长」。

---

## 4. UI / UX 设计简报（遵循 `joycai-ui-design`）

> 依据仓库维护中的设计规范（`docs/architecture/design-tokens.md`、`docs/architecture/ui-design-workflow.md`）与既有视频工作台源码/组件契约设计（无历史 Claude Design 原始帧）。所有新增卡片均保持**不透明内容层**（复用 `_PanelCard`、`colorScheme.surface` / `surfaceContainerLow`），**不新增任何液态玻璃层**（严守全屏 ≤ 1 宽幅玻璃、≤ 3 可见玻璃预算）。

### 4.1 信息层级与模式切换

在 `VideoConfigPanel` 右侧配置栏（及手机 BottomSheet）的 `head` 区域：

```text
┌──────────────────────────────────────────────┐
│ 模型选择（可折叠）      wan3.0-video       ▾ │  ← 既有 _PanelCard
│   [展开后显示 渠道 / 模型 / 当前模式有效参数] │
├──────────────────────────────────────────────┤
│ ┌────────────┬────────────┬────────────┐     │  ← 新增模式切换（仅当模型支持 edit 或 extend 时显示；
│ │    生成    │    编辑    │    延长    │     │     使用 AppSegmentedControl，不折叠隐藏！）
│ └────────────┴────────────┴────────────┘     │
├──────────────────────────────────────────────┤
│ [编辑 / 延长模式] 源视频（视频1）            │  ← 替换原「帧」卡（停放的首尾帧安全保留但不参与提交）
│   ┌─────────┐  clip_01.mp4           [预览]  │
│   │ 缩略图  │  1280×720 · 5.2s · 30fps [×]  │
│   └─────────┘  4.1 MB                        │
│   [仅延长模式] 延长方向：[ 向后 | 向前 | 双向 ]│
│   [仅延长模式] 时长预算：原 5.2s · 固定输出 ≤ 24s │
├──────────────────────────────────────────────┤
│ [编辑 / 延长模式，可选，默认折叠]            │
│ 附加参考素材（可选）  图 0 · 音 0          ▾ │  ← 仅契约 allowsReference* 为真时展示
├──────────────────────────────────────────────┤
│ [当存在参考图时] 压缩参考图           [开关] │
├──────────────────────────────────────────────┤
│ 提示词                         [历史] [库]   │
│ [视频1] [图1] [音频1]  ← 点击插入编号芯片    │
│ ⓘ 将自动附加前缀：「将视频1向后延长，」[插入]│  ← 仅 promptRouted 且未写关键词时显示
│ ┌──────────────────────────────────────────┐ │
│ │ 描述想要编辑的内容或延长后的画面变化…    │ │
│ └──────────────────────────────────────────┘ │
├──────────────────────────────────────────────┤
│ [         编辑视频 / 延长视频        ]  [⚙] │  ← 主按钮随模式切换文案与可用条件
└──────────────────────────────────────────────┘
```

### 4.2 核心交互与状态规范

1. **源视频卡（`SourceVideoCard`）状态机**：
   - **空态（Rest / Armed / Hover / Reject）**：
     - 复用 `AppDropZoneFrame`、`AppDropConfirmRing`、`AppDropNote` 与 `_DropSlot` 视觉语言。
     - 接受三种输入：① 点击打开系统文件选择器（`.mp4` / `.mov`）；② 从应用内画廊拖入视频卡片（`_isDroppableVideo`）；③ 从系统文件管理器拖入视频文件（`DropTarget`，保留 `appleBookmark`）。
     - 拖入非视频（如图片）时进入 `AppDropZoneState.reject`，提示「仅支持视频文件」。
   - **探测中（Probing）**：选中后立即在后台 Isolate 运行 `probeReferenceMedia`（先查文件大小 ≤ 100 MB 再读取），卡片内显示轻量进度状态，不阻塞 UI 线程，并带递增代数令牌防竞态覆盖。
   - **有效已填充（Valid）**：
     - 左侧展示视频首帧缩略图（复用 `VideoThumbnailService`）及 `视频1` 角标；
     - 右侧展示文件名（mono 截断）、技术参数行（`1280×720 · 5.2s · 30fps · 4.1 MB`）；
     - 顶部/右侧提供「全屏预览」与「清除」图标按钮（键盘聚焦可见，带 `AppControlLabel` / `Tooltip`）。
   - **校验不通过（Invalid / Error）**：
     - 例：用户拖入一段 20 秒视频（超出 Wan 3.0 的 15 秒输入上限）、或帧率 < 16fps、或超 100 MB、或损坏/不支持编码。
     - 仍保留视频槽位让用户可见并可一键清除/替换，在槽位下方以 `colorScheme.error` 展示清晰原因，并禁用主提交按钮。
   - **延长时长预算实时反馈（Extend Mode）**：
     - 根据已探测的 `sourceSeconds`（以及附加参考视频总时长）与当前 `seconds` 参数实时计算：
       - 若 `seconds == -1`（智能时长）：提示 `原视频 5.2s · 智能时长将由模型自动推荐最终长度（输入+输出 ≤ 30s）`。
       - 若 `seconds` 为固定值 `D`：
         - `inputSeconds + D > 30`：展示红色错误诊断并拦截提交（`输入视频 12.0s + 固定输出 20s 超过 30s 上限，请调至 ≤ 18s 或改用智能时长`）。
         - `D <= sourceSeconds`（仅延长模式）：展示柔和提醒（非硬阻断，因需实测上游是否接受短于原片的输出），提示建议设为智能时长或大于原视频时长。
         - 正常区间：显示预计新增时长（如 `目标总时长 10s · 约延长 4.8s · 预算 15.2 / 30s`）。
2. **延长方向控件（`extendDirection`）**：
   - 当 `contract.videoExtend.directions.length > 1` 时，直接呈现在源视频卡底部（无需展开模型参数卡即可操作），并与 `AppState` 的 `extendDirection` 参数双向绑定（在 `GenerationParamPanel` 中通过 `hiddenKeys: {'videoTask', 'extendDirection'}` 避免重复渲染）。
   - 切换为 `bidirectional` 时，提示词占位符动态提示同时描述前序与后续片段。
3. **停放素材隔离规则**：
   - `WorkbenchUIState` 独立持有 `videoSourceVideoPath`（及探测元数据），与 `videoFirstFrame` / `videoLastFrame` / `videoReferenceImages` / `videoReferenceVideos` / `videoReferenceAudios` 并存。
   - 新增 `WorkbenchUIState.videoGenerationMediaFor(GenerationOperation operation)`：
     - `generate` 相关操作：返回 `[firstFrame?, lastFrame?, ...referenceImages, ...referenceVideos, ...referenceAudios]`（与现状完全一致）。
     - `editVideo` / `extendVideo`：返回 `[sourceVideo?, ...(契约允许的 referenceImages / referenceVideos / referenceAudios)]`，**不包含** `firstFrame` / `lastFrame`，避免停放的首尾帧引发误报冲突。
   - 切换到一个不支持编辑/延长的模型时，`videoTask` 自动归一为 `generate`，`videoSourceVideoPath` 静默停放不参与提交；切回支持模型后立即可恢复。
4. **五大闭环入口（共享单点协调器）**：
   - 在 `AppStateWorkbench` 中新增 `openVideoInTaskMode({required String path, required String mode})`：
     1. 校验当前选中视频模型是否支持 `mode`（`edit` / `extend`）。
     2. **绝不静默切换付费模型**：若当前模型支持，直接切换 `videoTask = mode`；若当前模型不支持，则载入 `videoSourceVideoPath` 并切换到视频工作台，由调用方弹出清晰提示告知当前模型不支持并列出可用支持模型（若有），由用户主动切换。
     3. 切至 `WorkbenchTab.video`；手机端同步打开/展开视频配置表单。
   - **入口 1 · 底部结果播放器 `VideoWorkbenchOverlay`**（`video_workbench_view.dart`）：
     - 桌面面板（`areaWidth >= 760`）：在右侧路径下方新增紧凑次级操作行：`AppButton.secondary`「编辑视频」+「延长视频」（仅当文件存在且解码正常或可读时显示）。
     - 平板条（`480 <= areaWidth < 760`）与手机条（`< 480`）：使用 `AppMenuAnchor` 收纳「编辑视频 / 延长视频 / 系统播放器打开」，避免挤压窄条宽度并满足 Windows AXTree 无障碍约束。
   - **入口 2 · 画廊视频卡右键菜单**（`image_card_context_menu.dart`）：
     - 单选视频（`isVideo && !multi`）在「打开预览」下方新增分组：「编辑视频」「延长视频」「添加到参考视频」（选中后先经 `PersistentMediaService.importFile` 确保沙盒持久可读）。
   - **入口 3 · 拖放直达**：画廊视频卡与 OS 视频文件直接拖入 `SourceVideoCard`（并同步让 `video_reference_files.dart` 支持拖入参考视频）。
   - **入口 4 · 全屏预览顶栏**（`media_preview_dialog.dart`，Phase 3）：预览视频时顶栏新增「编辑 / 延长」图标动作（`AppControlLabel`），点击后关闭预览并跳入视频工作台对应模式。
   - **入口 5 · 任务队列卡片**（`task_card_details.dart`，Phase 3）：展示操作标签（`视频编辑` / `视频延长`）、源视频文件名与延长方向；已完成的视频任务菜单可一键「编辑 / 延长结果」。

### 4.3 响应式、无障碍与四语言规范

- **四宽度适配（390 / 834 / 1024 / 1440，浅色 & 深色）**：
  - `videoTask` 分段标签保持简短（`en`: `Generate` / `Edit` / `Extend`；`zh`: `生成` / `编辑` / `延长`；`zh_Hant`: `生成` / `編輯` / `延長`；`ja`: `生成` / `編集` / `延長`），确保 390px 手机与 280px 窄侧栏单行不溢出。
  - `extendDirection` 分段标签同样保持精炼（`en`: `After` / `Before` / `Both`；`zh`: `向后延长` / `向前延长` / `双向延长`；`zh_Hant`: `向後延長` / `向前延長` / `雙向延長`；`ja`: `後方` / `前方` / `前後`）。
  - 所有操作按钮满足手机 `AppSize.touch`（44px）触控高度。
- **键盘与语义**：
  - `AppSegmentedControl` 原生提供按钮/选中语义与 Tab 焦点；
  - 源视频槽位使用 `AppActionTarget` / `InkWell`，拖放确认通过 `SemanticsService.sendAnnouncement` 播报；
  - 弹出菜单统一使用 `AppMenuAnchor`。
- **本地化模块（四语同步：`en` / `zh` / `zh_Hant` / `ja`）**：
  - `lib/l10n/src/<lang>/generation.arb`：参数标签（`paramVideoTask`、`paramExtendDirection`）、选项文案（`videoTaskGenerate`/`Edit`/`Extend`、`extendDirectionBackward`/`Forward`/`Bidirectional`）、新诊断文案（`generationSourceVideoRequired`、`generationUnsupportedVideoEdit`、`generationUnsupportedVideoExtend`、`generationVideoDurationBudgetExceeded`、`generationUploadRegionUnsupported` 等）。
  - `lib/l10n/src/<lang>/workbench.arb`：主按钮文案（`editVideo`、`extendVideo`）、源视频槽位文案（`sourceVideo`、`dropSourceVideo`、`dropVideosOnly`、`sourceVideoDurationHint`、`videoIntentPrefixHint`、`insertIntentPrefix`）、右键菜单与播放器入口文案（`menuEditVideo`、`menuExtendVideo`、`sendToVideoReferenceClips`、`modelDoesNotSupportVideoEdit` 等）。
  - 改完必须依次执行 `dart tool/merge_l10n.dart` → `flutter gen-l10n`。

---

## 5. 跨模型扩展路径（验证通用性）

以下展示后续接入其他主流视频模型时所需改动量——**工作台 UI、任务队列与状态层均无需结构性重写**：

| 后续模型 | 只需修改的层与文件 | 说明 |
|---|---|---|
| **xAI Grok Imagine Video** (`grok-imagine-video-1.5`) | 1. `generation_contract.dart` / `video_profiles.dart`：给 `_grokImagineVideo` 声明 `videoTask: [generate, edit, extend]`、`videoEdit`（`durationEditable: false`, `aspectPolicy: inherited`, `promptRouted: false`）与 `videoExtend`（`directions: [backward]`, `durationSemantics: addedSeconds`, `maxSourceSeconds: 15`, `promptRouted: false`）。<br>2. `xai_videos_protocol.dart`：根据 `videoTask` 将 URL 切到 `/videos/edits` 或 `/videos/extensions`，把 `LLMReferenceType.sourceVideo` 编码为 `payload['video'] = {'url': ...}`（或接入 xAI Files API）。 | UI 自动隐藏编辑时的时长/比例控件、隐藏方向分段器、隐藏提示词前缀提示；延长时长提示自动切换为「新增时长」。 |
| **Google Veo 3.1** (`veo-3.1-*`) | 1. `generation_contract.dart` / `video_profiles.dart`：声明 `videoTask: [generate, extend]`（无 `edit`）与 `videoExtend`（`sourceKind: remoteHandle`, `durationSemantics: fixedIncrement`, `aspectPolicy: mustMatchSource`）。<br>2. 持久化任务产物对应的上游文件 URI（过期时间 48h）并在 `SourceVideoCard` 对 `remoteHandle` 显示近期 Veo 产物选择器。<br>3. `gemini_veo_protocol.dart`：将句柄写入 `instances[0]['video']`。 | 模式栏自动只显示「生成 / 延长」两段，时长控件自动隐藏。 |
| **OpenAI Sora 2** (`sora-2`) | 1. `generation_contract.dart` / `openai_profiles.dart`：声明 `videoEdit`（`sourceKind: remoteHandle`）/ `videoExtend`。<br>2. `openai_videos_protocol.dart`：`editVideo` 路由至 `POST /videos/{video_id}/remix`。 | 复用同一任务与结算管线。 |

---

## 6. 分阶段实施计划与影响文件清单

### Phase 1：协议契约、Schema 语义与 Wan 3.0 底层实现（纯业务层，零 UI 破坏）

- **影响文件**：
  - `lib/services/llm/llm_messages.dart`：新增 `LLMReferenceType.sourceVideo`。
  - `lib/services/llm/protocols/generation_contract.dart`：新增 `VideoSourceKind`、`VideoExtendDirection`、`VideoExtendDurationSemantics`、`VideoAspectPolicy`、`VideoEditContract`、`VideoExtendContract`；为 `WireProtocol.dashscopeVideo` 注册 `videoEdit` 与 `videoExtend`。
  - `lib/services/llm/generation/generation_schema.dart`：新增 `GenerationOperation.editVideo` / `extendVideo`、`GenerationMediaRole.sourceVideo`、操作级默认值 `defaultValueFor` / `defaultStringFor`、`fieldState` 与 `validate` / `validatePrompt` 规则。
  - `lib/services/llm/generation/generation_request.dart`：`legacyOptions` 暴露 `sourceVideoPath`。
  - `lib/services/llm/generation/generation_preferences.dart`：`videoTask` 共用 `$base.mode`。
  - `lib/services/llm/generation/generation_validator.dart`：支持 `sourceVideo` 映射、`edit`/`extend` 提示词非空校验，以及历史 v1 DashScope 快照缺失默认 `videoTask` 的向后兼容。
  - `lib/services/llm/generation/profiles/dashscope_profiles.dart`：`_dashscopeWanVideo.videoParams` 新增 `videoTask` 与 `extendDirection`。
  - `lib/services/llm/protocols/dashscope_payload.dart`：新增纯函数 `composeDashScopeIntentPrompt`；`buildDashScopeVideoPayload` 支持操作意图、防御性校验与 20,000 码点上限检查。
  - `lib/services/llm/protocols/dashscope_video_media.dart`：`dashscopeVideoMediaRole` 映射 `sourceVideo` → `'reference_video'` 并保证排序首位。
  - `lib/services/llm/protocols/dashscope_upload.dart`：暴露 `dashscopeSupportsTemporaryUpload(String endpoint)`。
  - `lib/services/llm/protocols/dashscope_video_protocol.dart`：`needsUpload` 纳入 `sourceVideo`、`inputImages` 排除 `sourceVideo`、**修复 `poll` 使用 `output_video_duration` + `input_video_duration` + `SR` 结算**。
  - `lib/services/tasks/generation_task_data.dart` & `lib/services/tasks/task_media_snapshot.dart` & `lib/services/tasks/task_executors.dart`：`sourceVideoPath` 快照、沙盒复制与 `LLMAttachment` 组装。
  - `lib/widgets/models/model_protocol_section.dart`：`_paramName` 补齐 `videoTask` / `extendDirection`（或忽略内部模式键以免污染摘要）。

### Phase 2：状态管理、源视频探测与视频工作台 UI

- **影响文件**：
  - `lib/state/workbench_ui_state.dart`：新增 `videoSourceVideoPath`、异步探测状态（`ReferenceMediaInfo` / 字节数 / 探测错误 / 代数防竞态）、`setVideoSourceVideo` / `clearVideoSourceVideo`、`videoGenerationMediaFor(GenerationOperation)`。
  - `lib/state/app_state_workbench.dart`：`_paramKey` 支持 `videoTask`；`getVideoParam` / `storedVideoParam` 支持操作级默认值并隔离 `editVideo`/`extendVideo` 旧家族回退；`effectiveVideoParams` 改为经 `schema.effective(...)` 过滤；`submitTask` 识别 `sourceVideoPath`；新增闭环协调方法 `openVideoInTaskMode`。
  - `lib/screens/workbench/widgets/generation_params/generation_param_panel.dart` & `generation_param_texts.dart` & `param_presentation.dart`：支持 `hiddenKeys`（避免顶层模式/方向重复渲染）、补齐新标签/选项/诊断文案映射。
  - `lib/screens/workbench/widgets/video/video_config_panel.dart`、`video_model_section.dart`、`video_drop_parts.dart`、`video_reference_files.dart`、`video_reference_images.dart`：
    - 顶层 `videoTask` 分段切换；
    - 新增 `video_source_slot.dart`（`part of 'video_config_panel.dart'`，承载 `SourceVideoCard`、缩略图、探测徽章、延长方向分段器、延长时长预算条与拖放）；
    - 编辑/延长模式下隐藏首尾帧卡、折叠可选附加参考素材区、展示素材序号徽章与快捷插入芯片、透明意图前缀条、动态主按钮文案。
  - `lib/screens/workbench/widgets/video/video_workbench_view.dart`：结果播放器新增「编辑视频 / 延长视频」入口（桌面次级按钮行、窄屏/手机 `AppMenuAnchor`）。
  - `lib/screens/workbench/widgets/gallery/image_card_context_menu.dart`：画廊视频卡右键菜单新增「编辑视频」「延长视频」「添加到参考视频」。
  - `lib/l10n/src/{en,zh,zh_Hant,ja}/{generation,workbench}.arb` + 合并与代码生成。

### Phase 3：任务历史完善、预览入口与全量可视化验收

- **影响文件**：
  - `lib/screens/workbench/widgets/preview/media_preview_dialog.dart`：全屏预览视频时顶栏新增编辑/延长入口。
  - `lib/screens/batch/task_card/task_card_details.dart` & `task_card_menu.dart`：展示编辑/延长操作标签、源视频名、延长方向，及已完成视频结果的一键再编辑/再延长。
  - `docs/api/qianwen-bailian.md` & `docs/architecture/generation-parameters.md`：同步长期协议与架构约定。
  - 截图与行为回归测试补齐，验收完成后按台账约定归档至 `docs/plans/README.md`。

---

## 7. 测试与验收计划

### 7.1 自动化测试清单

1. **协议与 Schema 单元测试**（`test/services/llm/`）：
   - `dashscope_video_payload_test.dart`：`editVideo` / `extendVideo` 请求体、`sourceVideo` 始终排在 `reference_video` 首位、`composeDashScopeIntentPrompt` 中英文幂等/不重复/三方向断言、超 20,000 码点拒绝。
   - `dashscope_video_upload_test.dart`：`sourceVideo` 触发临时上传、非京/新官方地域预检拒绝、`inputImages` 排除 `sourceVideo`、**`poll` 正确提取 `output_video_duration` / `input_video_duration` / `SR` 且不双重计数**。
   - `generation_schema_test.dart` & `generation_validator_test.dart` & `generation_preferences_test.dart`：`editVideo`/`extendVideo` 操作解析、操作级默认值（`-1` vs `5`）、`extendDirection` 仅在 `extendVideo` 激活、历史 v1 快照缺失默认 `videoTask` 兼容、空提示词拒绝、`sourceVideo` 必填与帧互斥校验。
   - `test/services/tasks/generation_task_data_test.dart` & `video_settlement_test.dart`：`sourceVideoPath` 沙盒快照与双桶时长结算。
2. **UI 与交互测试**（`test/screens/workbench/wan_video_inputs_test.dart`）：
   - 模式切换时首尾帧隐藏且停放不报错；
   - 切换不支持模型时模式自动降级且不提交 `sourceVideo`；
   - 源视频超 15s / 超时长预算拦截提交；
   - `VideoWorkbenchOverlay` 与画廊右键菜单闭环跳转不静默切换付费模型；
   - 提示词意图前缀在输入关键词后自动隐藏。
3. **既有架构测试**：`test/source_layout_test.dart`、`test/architecture/ui_database_access_scan_test.dart`、`test/architecture/channel_flat_columns_scan_test.dart` 全部通过。

### 7.2 必过代码门禁与可视化渲染验收

- **三道必过门禁**（每次提交前全绿）：
  1. `dart format lib test tool`
  2. `flutter analyze`（必须 `No issues found!`）
  3. `flutter test -x screenshots`
- **视觉截图验收**（`joycai-ui-design`）：
  - 扩展 `test/screenshots/wan_video_shots_test.dart` 覆盖「视频编辑（空态 / 已选源视频+参考图 / 超限诊断）」与「视频延长（三方向 + 时长预算条）」及 `VideoWorkbenchOverlay` 新操作按钮；
  - 覆盖 390 / 834 / 1024 / 1440 四宽度 × 浅深色 × 四语（特别复查英文/日文分段标签与窄桌面预算文案）；
  - 逐图打开 `build/ui-screenshots/` 核查无溢出、无截断、无额外玻璃层。

---

## 8. 风险、待实测项与待确认决策

### 8.1 需真实百炼账号实测核验项（不得以本地 Mock 冒充线上验收）

1. **延长 `duration` 输出形态与短时长边界**：官方文档说明延长时 `duration` 为「输入视频时长 + 预期延长时长总和」（如 5s 延长 2s 填 7），但官方 curl 样例中亦出现 `duration: 5`。需实测确认返回 MP4 是否包含原片段拼接，以及固定 `duration <= 原视频时长` 时上游如何表现。
2. **英文编辑/延长指令的路由稳定性**：官方 API 称支持中英文，但编辑/延长示例全部为中文。需实测纯英文提示词 + 英文前缀能否稳定触发编辑与向前/双向延长。
3. **编辑/延长 `usage` 字段实测核对**：核实 `usage.duration`、`usage.input_video_duration`、`usage.output_video_duration`、`usage.SR` 在编辑/延长与 `-1` 智能时长下的真实返回形态，确认结算零偏差。
4. **编辑/延长传入非 `adaptive` 固定 `ratio` 的行为（关联 `WAN-09`）**：官方建议/要求设为 `adaptive`；需实测传入固定比例是裁切重绘、静默忽略还是 400。
5. **MP4/MOV 音频轨编码宽容度**：当前 `reference_media_probe.dart` 仅放行 `mp4a` / `.mp3` / `mp3 ` 音轨（源自 MiniMax 要求），需确认 Wan 3.0 对常见手机/桌面录制 MOV（如 PCM/ALAC）的兼容情况，并在必要时解耦 MiniMax 与 Wan 的音轨检查策略。
6. **大文件探测内存优化（后续可做）**：当前 `probeReferenceMedia` 接收完整 `Uint8List`（最大 100 MB）；后续可升级为基于 `RandomAccessFile` 仅读取 MP4 box 头与 `moov` 原子，降低选片时的瞬时内存占用。

### 8.2 进入编码前建议确认的三项产品决策

1. **决策 A · Wan 3.0 提示词意图前缀策略**：默认采用「透明预览 + 未写关键词时 Wire 层自动附加（不污染用户原文与历史）」，还是改为「仅 UI 一键插入模板、Wire 层完全原样发送」？（推荐前者：避免方向分段器成为无效果的虚设控件，同时对用户完全透明。）
2. **决策 B · 延长模式下 `ratio` 是否默认可编辑**：在 `WAN-09` 实测前，延长模式默认选中 `adaptive` 但允许用户修改，还是按 API 参考文案（“需将 ratio 设为 adaptive”）先保守锁定为 `fixed(adaptive)`？（推荐默认 `adaptive` 并可编辑 + 附说明文案；若倾向零 400 风险可改为锁定 `adaptive`。）
3. **决策 C · 跨模型闭环跳转行为**：当用户当前选中的是 Veo/MiniMax 等暂不支持视频编辑的模型，而在画廊或播放器点击「编辑视频」时，推荐方案为**保持当前模型不静默切换付费渠道**，跳转至视频工作台并弹出提示引导切换至已配置的 Wan 3.0 模型；确认是否认可此保守策略。
