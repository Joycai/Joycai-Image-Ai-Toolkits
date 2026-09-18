# 渠道 × 线路 × 模型 · 执行清单

设计：[`2026-09-channel-route-model.md`](2026-09-channel-route-model.md) · 设计稿：Claude Design `D1f 渠道与线路`（4a–4g）。
分支 `claude/channel-route-model-refactor-15eebf`，**一片一个 commit**（commit 正文写片号），每期末跑 `/code-review high` 并修完再进下一期，
最后 bump minor 版本并开 PR。每片提交前两道闸门：`flutter analyze` 无问题、`flutter test -x screenshots` 全绿。

状态：☐ 未开始 · ◐ 进行中 · ☑ 完成

## A 期 · 数据与迁移（请求逐字节不变，界面不变）

| 片 | 内容 | 文件 | 验收 | 状态 |
|---|---|---|---|---|
| A1 | `RouteKind`（六值、稳定 id、↔ 对话 wire）+ `PlatformProfile` 表 + 平台推断（主线路 vendor + 主机）+ 线路 vendor 解析规则 | `services/llm/vendors/platforms.dart` | 每个 vendor × 官方/非官方主机推断正确；迁移后线路 vendor = 今天的点单 vendor | ☑ |
| A2 | `ChannelRoutes`（内嵌文档：主机、线路表、写入标记）：解析逐字段收窄、序列化、读时由旧 (type, endpoint) 推出、规范化（扁平字段 = 主线路）、地址拼接（缺省 / 相对 / 绝对） | `services/llm/channel_routes.dart` | **每个预设 × 每个面迁移后地址逐字节等于今天的推导**；非 URL 地址整条保留；规范化幂等 | ☑ |
| A3 | v45：`llm_channels.routes`、`llm_models.active_route`、`llm_models.route_params`；`LLMChannel` / `LLMModel` 字段；`RouteParams`（三字段一类）+ 模型读时迁移（旧对话面点单 → `active_route`）；仓库读写都过规范化 | `database_migrations.dart`、`llm_channel.dart`、`llm_model.dart`、`model_repository.dart` | onCreate 与 onUpgrade 同步；旧行读出 = 今天；写入标记识别扁平字段被他方改写 | ☑ |
| A4 | 按模型的线路看渠道：`ChannelRouteView`；`LLMConfigResolver` 走它，线路不存在 → `LLMConfigErrorKind.routeNotFound`；`LLMModelConfig.faceBases` + `_faceTarget` 先查它；`AppState` 的 `descriptorForModel` / `_supportsVideoForType`、模型编辑、卡片、发现改走视图；源码扫描测试挡住 `channel.type` 直读 | `services/llm/channel_route_view.dart`、`llm_config_resolver.dart`、`llm_model_config.dart`、`llm_dispatcher.dart`、`state/app_state.dart`、调用方 | 旧数据下所有 `wire_protocol_routing_test` 不变；线路缺失请求侧报错、展示侧回退 | ☑ |
| A5 | 切线路：`RouteParams.forRoute` 一条规则同时用于保存与切换；`LLMModel.switchRoute`（停放 / 载入 / 覆盖全部 / id 不变）；改主线路前钉住跟随者（纯函数） | `models/llm_model.dart`（`withRouteState`）、`services/catalogue/route_switching.dart` | 标准 03 §6 的六条性质各一条测试 | ☑ |
| A6 | 备份：`schema_version` 45；旧备份新列为空 → 同一读时迁移；导入/导出往返保留线路与停放参数 | `database_service.dart` | 旧版本备份导入后请求地址不变；新备份在 44 版被拒（已有检查，补测试） | ☑ |

A 期末：`/code-review high`，修复。☑（3 条，见施工记录「A 期评审」）

## B 期 · 合并

| 片 | 内容 | 验收 | 状态 |
|---|---|---|---|
| B1 | 候选检测 + 合并计划（纯函数）：同平台 / 同主机 / 同密钥 / 线路不相交 / 空密钥同主机 / 每渠道至多一组；计划：线路并入、同名一对一合一、搬迁并钉住线路、id 映射 | 标准 04 §5 前三条 | ☑ |
| B2 | 执行：单事务 渠道 → 模型 → 删被并模型 → 删余下 → 删渠道；提交后按映射改写设置里的模型选择与用量记录 | 写入顺序与改写的测试（断言调用顺序） | ☑ |

B 期末：`/code-review high`，修复。☑（2 条，见施工记录「B 期评审」）

## C 期 · 界面（按 D1f）

| 片 | 内容 | 状态 |
|---|---|---|
| C1 | l10n：线路名、作用域、线路表、切换差异、合并文案（四语）；`AppRouteBadge`（cur / cfg / off / quiet） | ☑ |
| C2 | 模型页：渠道栏副行（平台 · 线路徽标）、渠道头（平台 · 主机 · 徽标）、模型卡线路徽标（≥2 条线路时）、手机布局同步 | ☑ |
| C3 | 渠道编辑：主机 + 线路表（路径四态、实际地址、测试、设为主线路、移除/启用及不可用原因）；单线路且平台无第二条时保持原输入框 | ☐ |
| C4 | 添加渠道：平台优先，去掉线路类变体步骤，「将建立的线路」预览；百炼两行合一；新渠道建平台全部线路 | ☐ |
| C5 | 模型编辑：线路条、作用域灰字与引导线、切换差异卡、联网搜索各线路矩阵；单线路渠道与媒体模型不变 | ☐ |
| C6 | 合并提示卡 + 预览对话框（逐组） | ☐ |
| C7 | 截图场景：多线路渠道列表、渠道编辑线路表、模型编辑三态、合并预览、手机 | ☐ |

C 期末：`/code-review high`，修复。

## D 期 · 收尾

| 片 | 内容 | 状态 |
|---|---|---|
| D1 | `docs/architecture/llm-three-layer.md` 新增「渠道 × 线路」一节；台账行；本目录两份文档退役；CLAUDE.md map | ☐ |
| D2 | bump minor（4.11.0）并开 PR | ☐ |

## 决策记录

1. 线路 vendor 按「主线路 vendor 的 `chatMenu` 含该面 → 主线路 vendor，否则画像表」计算、不存——迁移按构造逐字节不变，画像更新自动生效。
2. 平台不存：由（主线路 vendor, 主机）推断；三个通用 vendor 看主机。
3. 线路参数只有三个（推理强度、思考、最大输出）：有 `reasoningLadder` / `outputCapField` / ④ 方言三处证据；联网搜索是授权。

## 施工记录

- **A2**：文件落在 `services/llm/channel_routes.dart` 而非 `models/`——推导要读 vendor 表（services），models 层只存原始字符串（与 `wire_protocol` / `reasoning_effort` 同一惯例）。
  百炼两个 vendor 的 `protocolBases` 补上 `dashscopeChat: dashscopeNativeBase`：原生协议自己也从任意面推导原生 base（幂等），所以请求不变；
  补上之后原生线路读出来的地址才是 `/api/v1` 而不是兼容面地址。MiniMax 的主面本来就经推导，所以扁平 `endpoint` = 主线路地址 = 推导结果（去尾斜杠），
  下一次保存会把存着的地址规范化成它——媒体面从任意面推导，同样不变。
- **A3**：`RouteParams` 与模型侧解析放在 `services/llm/model_routes.dart`。模型**不做**写时迁移：旧行 `active_route` 为空时由对话面的
  `wire_protocol` 读出线路（`explicitRoute`），读法稳定，无需改写。一个区别于标准的点：**旧的对话面点单若渠道已不提供，仍退回主线路**
  （今天它就是这样静默失效的），只有新写的 `active_route` 失效才让请求报错——这是让每一条旧行请求逐字节不变的唯一读法。
  仓库的 `updateChannel` 在调用方没带线路文档时沿用库里的那份，于是 C3 之前的渠道编辑框保存不会丢掉其余线路。
- **A4**：视图叫 `RoutedChannel`（与 `ModelRoutes` 同在 `model_routes.dart`）。本片只换了**会影响请求或能力判断**的三处：
  `LLMConfigResolver`、`AppState.descriptorForModel` / `_supportsVideoForType`、模型页的「获取模型」。模型编辑器、模型卡、选择器仍读
  `channel.type`——它们在 C2 / C5 整体改成按线路，届时再加挡住直读的源码扫描测试（现在加会把要重写的界面一起钉住）。
  逐字节的证明不再只比地址：`test/route_resolution_test.dart` 起一个本地服务器，**真实发出**旧配置与新配置的请求，比较方法、URL、
  鉴权头和请求体——每个预设 × 每个对话面 × 有无点单，外加合并后的中转四条线路对照原先四个独立渠道。
- **A5**：共用规则 `RouteSwitching.forRoute` 以线路的推理挡位表为准：挡位表里没有的强度丢弃，旧的「深度思考」开关只剩强度的影子
  （仅开关 = Medium，与 `effectiveReasoningEffort` 一致）。保存时写显式 `active_route`，并按「主线路 vendor 能否点单到该面」写兼容用的
  `wire_protocol`。钉住跟随者只钉真正在跟随的（含渠道已不提供的旧点单），**已失效的显式线路不钉**——那种模型要继续报错直到用户选择。
  会话中跨线路：回传载体本来就按协议成形、按模型 id 作用域，切线路后新协议读不到旧协议的载体，测试钉在 `route_resolution_test`。
- **A6**：备份格式本身不用改——行是原样导出导入的，新列随行走；`schema_version` 跟着 dbVersion 到 45，旧版本的「更新的版本 → 拒绝」检查早已存在。
  唯一要改的是恢复时保留密钥用的渠道身份 `_channelIdentity`：改成比较**规范化后的**主线路 vendor 与地址，否则本机库里还是旧写法、
  备份里是规范化写法的同一个渠道（MiniMax 带尾斜杠）会认不出，密钥丢失。
- **A 期评审**（`/code-review high`，3 条全修）：
  1. `_Doc.tryParse` 把 `kind` 强转 `String?`，非字符串会抛错、拖垮所有渠道读取 → 改为收窄，跳过该条。
  2. 写标记失配且扁平列已换到**另一个平台**（旧编辑器换预设）时，文档里的其余线路被按新平台的 vendor/默认路径重新解读并保留
     → 判定平台变更（由 mark 推断旧平台）时只取扁平列自己的线路（`legacy`），视为换了渠道。同平台改地址仍保留其余线路。
  3. `RouteSwitching.forRoute` 把不在阶梯上的档位一律丢掉，但有的面仍会发出它（开关式面把 High 发成 on，Gemini 把 Max 发成顶档），
     保存/停放会悄悄关掉思考 → 改为映射到在该面发出同样请求的档：不高于它的最高「开」档，否则最低「开」档；Off 或无「开」档 → 不设。
     这偏离了设计文档「不在阶梯上即丢弃」的原话，理由是那条规则会改变已发出的请求。
- **B1**：`services/catalogue/channel_merge.dart`（`ChannelMerge.candidates` / `plan`，`MergePlan`）；`LLMModel.movedTo` 是唯一的换归属。
  在标准的五个条件之外加了一条**请求不变**的闸：合并后每条线路的 vendor 与地址都要与合并前相同，否则不成对——线路 vendor 由保留方主线路
  vendor 推出（决策 1），换了保留方就可能换 vendor（例：New API 的 OpenAI vendor 自己就服务 Responses 面，以 Gemini 为主线路时
  Responses 会改由平台的 Responses vendor 服务）。被并线路在两边主机写法不同（大小写）时存成完整地址，逐字节不变。
  **图像 / 视频模型**恒走主线路，搬过去就换了地址和 vendor，所以被并方有无同名对应的媒体模型时，这个方向不成立；此时试反方向
  （后者保留），两个方向都不成立才不提示——偏离「靠前者保留」，理由同上。有同名对应的媒体模型照常合一。
  保留方的模型也要看：旧点单指向渠道原本不提供的面、因而一直跟随主线路的模型，合并后那个面有了会突然改走——计划把它钉在原线路。
  被并模型的当前线路参数和它在被并线路上停放的参数都带过去（保留方已有的优先），都经 `forRoute` 同一条规则。
- **B2**：`ModelRepository.mergeChannels`（单事务、标准顺序）+ `services/catalogue/channel_merge_executor.dart`（`ChannelMergeExecutor`
  经 `MergeStore` 接口一步一方法，测试断言调用顺序；失败的事务之后不改写任何引用）。提交后先改写选择（设置里的
  `last_model_id` / `last_video_model_id` / `last_ai_rename_model_id`），再改写历史（`token_usage` 与 `tasks` 的 `model_pk`）；
  `AppState.mergeChannels` 再把内存里的同一批选择（含提示词优化器与下载器的选择）按映射改掉并刷新缓存。
  **没有「最后删凭据」一步**：密钥是渠道行里的明文列，随事务删掉被并渠道时一起消失，保留方持有同一把。
  够不到的引用：已保存的助手对话里「跳到该模型」的链接（`LLMMessage.modelDbId`，存在 JSON 里）按标准读作「已删除的模型」，
  与手动删除该模型一致，不做 JSON 扫描。预览里的「将改写的引用数」= 选择数 + 历史行数（`referenceCount`）。
- **B 期评审**（`/code-review high`，2 条全修）：
  1. 候选检测把密钥 `trim()` 后比较，但发送时不裁剪——只差空白的两把密钥会被配对，被并线路改发保留方的密钥字节 → 改为逐字节比较。
  2. `mergeChannels` 按计划快照写整行模型，预览打开期间写入的改动（编辑、任务队列的耗时估计）会被回滚 → 只写合并改变的四列
     （`channel_id`、`active_route`、`route_params`、`wire_protocol`）。
- **C1**：`widgets/models/app_route_badge.dart`（四态 × 四尺寸：small 18 / card 22 / strip 28 / touch 34，可点时带 InkWell）与
  `widgets/models/route_labels.dart`（`routeLabel` 短 / 全名一张表；只有百炼原生需要翻译，其余是产品名）。49 条文案一次加齐（`models.arb`，四语），
  英文计数用 ICU plural。徽标不进组件画廊：画廊是按种子色拍的整页金图，放进 C7 截图场景一起看。
- **C2**：渠道行第一行 = 名称 + 模型数（靠右），副行 = 平台名（`platformLabel`，封顶 112 宽）+ `ChannelRouteBadges`（一行，放不下的裁掉）；
  渠道自己的标签不再出现在副行（设计 ①：平台名取代「官方 / 中转」），头像仍用标签色。渠道头副行 = 平台 · 主机 · 徽标。
  模型卡：对话模型的点单就是线路——渠道有 ≥2 条线路时卡尾一枚 card 尺寸 cur 徽标（全名），不再出协议 chip；线路失效（显式线路或旧点单
  渠道都不提供）沿用「协议失效」警示牌，名字换成线路名。图像 / 视频照旧（失效判断改读主线路 vendor）。手机卡本来就不出 chip 行，
  手机上的线路靠渠道 tab 的行副行表达；分组头不加徽标（40 高一行放不下）。截图用例里「阿里云百炼」现在既是渠道名也是平台名，悬停查找取 `.first`。
