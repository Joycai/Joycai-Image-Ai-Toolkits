# 架构审计 · 2026-09-21

对照 Flutter 架构手册（分层隔离、MVVM、仓储模式、不可变状态、构造函数注入）把 `lib/`
整体过了一遍，在 `73aaa68`（v4.24.0，`flutter analyze` 干净）上逐条核实。

**结论**：分层本身比手册要求得更严，而且是 `test/source_layout_test.dart` 用八条规则钉死的；
真正的偏离只有两个方向——**依赖注入**（用单例当服务定位器，A1，**已做**，见
[`README.md`](README.md) 那行指针）与**数据边界上的领域模型**（还有两个仓储在传裸 map，A2）。
其余六条是局部的。

**怎么用这份文件**：一条一条做，每条自带验收。做完一条就把它从本文件删掉，并在
[`README.md`](README.md) 的「已执行」表里登记结论住在哪；条目清空后删掉本文件。
末尾「不要重复立项」一节是本轮**明确判定不做**的，别再提。

## 总表

| 编号 | 一句话 | 触及 | 状态 |
|---|---|---|---|
| A2 | `UsageRepository` / `TaskRepository` 是仅有的两个不返回领域模型的仓储，裸行一路穿到 UI | `models/`、`db/repositories/`、`screens/metrics/` | 未开工 |
| A3 | `DatabaseService` 门面把模型摊成 map 再让仓储拼回去 | `db/database_service.dart` | 未开工 |
| A4 | `BrowserFile` 带展示逻辑，其中 `.color` 是死代码且用裸 Material 颜色 | `models/browser_file.dart` | 未开工 |
| A5 | `TaskItem` 可变，队列把内部列表原样交出去并原地改 | `services/tasks/task_queue_service.dart` | 未开工 |
| A6 | `test/` 266 个文件平铺在根下，而 `lib/` 的分组目录根下一个散文件都不许有 | `test/` | 未开工 |
| A7 | workbench 一个目录占 lib 的 21%，提示词助手实质是独立功能 | `screens/workbench/` | 未开工 |
| A8 | 16 个 UI 文件直连 `DatabaseService`，绝大多数只为存侧栏宽度 | `screens/`、`widgets/` | 未开工 |

---

## A2 · 用量与任务两个仓储传裸 map

**现状**：其余仓储一律返回领域模型（`Prompt` / `LLMModel` / `LLMChannel` / `PricingGroup` /
`AssistantNote` / `AssistantSessionMeta` / `ImageLayerSet` / `CookieRetention`）。只有两个例外：

- `UsageRepository`：`getTokenUsage` 返回 `List<Map<String, dynamic>>`，`recordTokenUsage` /
  `updateTokenUsage` 收 map。**`models/` 里根本没有 `TokenUsage`。**
- `TaskRepository`：`saveTask(Map)` / `getRecentTasks` 返回 map，尽管 `TaskItem` 就在
  `models/task_item.dart`，队列拿到手第一件事是 `TaskItem.fromMap(t)`
  （`task_queue_service.dart:124`）。

后果是裸行穿过三层到 UI：`usage_controller.dart` 里 `List<Map<String, dynamic>> _rows`，
`usage_list.dart` 与 `usage_stats.dart` 按字符串键取值，连 `output_spec` 那一列的 JSON 快照
都是在 screens 层现解的（`usage_stats.dart:167` 的 `usageRowSpec`）。数据层的表结构就这样
漏到了最上面。

**为什么要改**：这是全仓唯一一处「换一个列名要改 UI」的地方。计费口径本身还分 token /
request / spec 三种模式，今天靠 `row['billing_mode'] as String? ?? 'token'` 这种写法在 UI 里
分叉——该由类型来分。

**改法**：
1. 新建 `lib/models/token_usage.dart`，对着 `token_usage` 表的列
   （`database_migrations.dart:664` 的 onCreate 加后续 ALTER：`model_pk`、`cache_tokens`、
   `cache_price`、`cache_input_price`、`output_spec` 等）写一个不可变模型 + `fromMap`/`toMap`，
   并把 `output_spec` 的 JSON 快照在模型里解成类型（`matched` 与各维度），
   而不是留给 `usageRowSpec`。
2. `UsageRepository` 改成收发 `TokenUsage`；`DatabaseService` 的对应门面方法跟着改签名。
3. `usage_controller` 的 `_rows` 换成 `List<TokenUsage>`；`usage_stats.dart` 里
   `usageRowCostParts` / `usageRowUnmatched` / `calculateRowCost` 这组自由函数变成
   `TokenUsage` 上的方法或扩展。
4. `TaskRepository` 同法改成收发 `TaskItem`，删掉队列侧的 `fromMap` 转手。

**验收**：`usage_stats_test.dart`、`usage_group_costs_test.dart`、`usage_summary_test.dart`、
`usage_list_test.dart`、`spec_billing_test.dart`、`task_pending_restore_test.dart`、
`task_queue_remove_task_test.dart` 全绿，且这些测试里不再出现手搓的 `{'billing_mode': ...}`
字面量——改完它们应该构造 `TokenUsage` / `TaskItem`。

**注意**：整库备份与导入（`database_service.dart` 的 `getAllDataRaw` / `restoreBackupInto`）
**继续用 map**，那一头要的就是按表按列的原样搬运，套模型只会在加列时丢数据。本条不碰它。

---

## A3 · 门面把模型绕着 map 转一圈

**现状**：

```
lib/services/db/database_service.dart:261  addPrompt(Map) => PromptRepository().addPrompt(Prompt.fromMap(prompt), ...)
lib/services/db/database_service.dart:262  updatePrompt(...)
lib/services/db/database_service.dart:275  addModel(Map) => ModelRepository().addModel(LLMModel.fromMap(model))
lib/services/db/database_service.dart:276  updateModel(...)
```

调用方手里本来就是 `Prompt` / `LLMModel`，先 `toMap()` 摊平，门面再 `fromMap` 拼回来。

**为什么要改**：既丢类型又没换来任何东西；一个拼错的键在编译期无人拦截，运行时变成静默的
「这一列没存上」。

**改法**：门面签名直接收模型，把 `fromMap` 从门面里删掉。改调用方（数量很少，逐个跟着编译错误走）。

**验收**：`flutter analyze` 干净；`prompt_history_test.dart`、`model_id_uniqueness_test.dart`、
`channel_ordering_test.dart` 全绿。做完这条，`database_service.dart` 里 `Map<String, dynamic>`
的出现次数应当从 49 明显下降——剩下的该只有备份/导入那一族。

---

## A4 · `BrowserFile` 带展示逻辑，`.color` 是死代码

**现状**：`lib/models/browser_file.dart`

```
:15  extension FileCategoryExtension on FileCategory
:16    IconData get icon   → Icons.image / movie / audiotrack / description
:26    Color   get color   → Colors.blue / red / green / orange / grey
:52  BrowserFile.icon  => category.icon
:53  BrowserFile.color => category.color
```

`.icon` 有人用（`browser_file_list_row.dart:135`、`file_card.dart:169`）。
**`.color` 全仓零引用**——`file.color`、`category.color` 都搜不到调用方，两层 getter 都是死的。

**为什么要改**：`models/`（第 1 层）不该知道 `Icons` 和 `Colors`；而且这几个裸 Material 颜色
违反你自己的设计令牌规则（见 `docs/architecture/design-tokens.md`：状态色不跟种子走的名单里
没有它们，该走 `AppSemanticColors`）。这是全仓仅有的两个导入 `package:flutter` 的模型之一
（另一个是 `AppImage.imageProvider`，见下）。

**改法**：
1. 删掉 `FileCategoryExtension.color` 与 `BrowserFile.color`（死代码，零风险）。
2. `icon` 挪到浏览器的 widget 层——两个调用点同一个文件夹，放
   `screens/browser/widgets/` 下一个 `file_category_icon.dart` 的自由函数即可。
3. 顺带判一下 `AppImage.imageProvider`（`models/app_image.dart:22`）：它让 `models/` 依赖
   `material.dart` 只为一个 `FileImage(File(path))`。调用点不多，值得一并挪走；
   **如果发现挪动要牵动画廊的缓存策略就停手**，单独记一条，不要在本条里扩大。

**验收**：`browser_file_scanner_test.dart`、`file_browser_group_by_folder_test.dart` 全绿；
`grep -rn "package:flutter" lib/models` 只剩下（或不剩）你有意保留的那一处。

---

## A5 · `TaskItem` 可变 + 队列交出内部列表

**现状**：`TaskItem` 是 13 个模型里唯一可变的（`task_item.dart:46-79`：`status`、`startTime`、
`endTime`、`progress`、`operationSurface`、`operationName`）。
`TaskQueueService` 把内部列表原样交出去（`task_queue_service.dart:90`
`List<TaskItem> get queue => _queue;`），并原地改它（`:120` clear、`:124` addAll、`:243` add、
`:353` removeAt），同时原地改元素（`:264`、`:323-326`、`:393-394`、`:418-440`、`:519`）。

**今天没有 bug**，这点要说清楚：所有消费方取的都是标量（`queue.where(...).length`）或
`task.id`，标量比较照样灵——`nav_lens_group.dart:71`、`phone_dock.dart:30`、
`assistant_tab.dart:29/95` 都是这样，后两处特意只取 id 而不取对象。

**为什么还是要改**：这是全仓唯一一处「交出去的列表身份不随内容变」的地方，而这正是
`CLAUDE.md` 里那条硬规矩、`test/state_list_identity_test.dart` 与
`workbench_rebuild_scope_test.dart` 在别处专门盯的失效模式。将来只要有人写一个返回
这个列表（或它的切片、或含它的 record）的 `Selector`，就会静默地永不重建——静默是重点。

**改法**（按投入从小到大，做第一档就够止血）：
1. `queue` 改成返回 `List.unmodifiable(_queue)`，或在每次结构性改动后整体重建 `_queue`，
   让列表身份随内容变。先量一下代价：队列长度是用户级的（几十条），重建不心疼。
2. 如果要做彻底的：`TaskItem` 转不可变 + `copyWith`，队列改成整表替换。**这一档先别做**，
   它会牵动 `task_executors.dart` 里所有就地写进度的路径，收益与风险不成比例。

**验收**：`state_list_identity_test.dart` 增一条钉住「队列结构性变化后 `queue` 的身份变了」；
`task_queue_row_test.dart`、`task_capsule_bounds_test.dart`、`task_list_ordering_test.dart`、
`render_performance_test.dart` 全绿（最后一条用来确认第 1 档没有把队列页拖慢）。

---

## A6 · `test/` 平铺

**现状**：266 个测试文件全部平铺在 `test/` 根下（另有 `test/screenshots/` 与 `test/support/`）。
而 `lib/services` 与 `lib/widgets` 的根下一个散文件都不许有——`source_layout_test.dart` 的
「分组目录根下没有散文件」那条规则只管 `lib/`。

**为什么要改**：找某个模块对应的测试只能靠 grep；反过来，加了新模块也没有地方提示
「测试该放哪」。这是项目唯一一处自家结构规则没有自适用的地方。

**改法**：按 `lib/` 的分层镜像分目录（`test/llm/`、`test/assistant/`、`test/db/`、`test/tasks/`、
`test/ui/`、`test/screens/`…），纯 `git mv`。两件事必须一起做，否则会静默失效：

- CI 的分片按文件切（`.github/workflows/flutter-ci.yml`，三个 runner），确认它的
  文件发现方式在有子目录后仍然覆盖全部。
- `dart_test.yaml` 的 `screenshots` tag 与 `test/screenshots/` 的相对路径、
  `test/support/private_data_dir.dart` 的导入路径全部跟着改。

**验收**：`flutter test -x screenshots` 的**用例总数**与迁移前一致（这是唯一能证明没有文件
掉出发现范围的指标，先记下迁移前的数字）；CI 三个分片都绿。做完给
`source_layout_test.dart` 加一条：`test/` 根下除了约定的几个入口外不留散文件。

**注意**：这条纯搬文件、零逻辑改动，但会制造一个巨大的 diff。**单独一个 PR**，不要和别的条
混在一起。

---

## A7 · workbench 过度集中

**现状**：`lib/screens/workbench/` 85 个文件 / 29,646 行 = **整个 lib 的 21%**，其中 31 个文件
散在 `widgets/` 根下。里面至少住着五个彼此独立的东西：图像工作台、视频工作台、提示词助手
（`widgets/optimizer/`、`widgets/optimizer_config/`、`workbench_assistant/`，约 15 个文件）、
蒙版/裁剪编辑器、对比视图。

**为什么要改**：提示词助手有自己的服务层（`services/assistant/`，九个文件）、自己的状态
（`WorkbenchUIState.optimizerSession`）、自己的一整套测试（`optimizer_*_test.dart` 三十余个），
却没有自己的屏幕目录——它是穿着 workbench 目录的独立功能。

**改法**：只做提示词助手这一刀，其余不动。把上述三处并成 `screens/workbench/assistant/`
（或提到 `screens/assistant/`，取决于它是否还算工作台的一个页签——**先裁定这件事再动手**）。
`widgets/` 根下剩余的散文件按 `preview/`、`layers/`、`size_picker/`、`crop_resize/`、`video/`
已有的分法收一收。

**验收**：`source_layout_test.dart` 全绿（它会抓到任何变成横向或向上的导入）；
`flutter test -x screenshots` 全绿；截图 harness 跑一遍确认没有哪个屏幕因为 part/import
挪动而掉了。

**注意**：**这条排在最后**。它和 A6 一样是大 diff，而且比 A6 更容易和别人的分支撞车。
在 A1–A5 落地之前不要开。

---

## A8 · UI 直连 `DatabaseService`

**现状**：16 个文件在 `screens/` / `widgets/` 里直接调 `DatabaseService()`。分两类：

- **偏好设置**（8 处）：侧栏宽度一类，`file_browser_screen.dart:151/528`、
  `models_screen.dart:84/198`、`prompts_screen.dart:101`、`workbench_layout.dart:278/452`。
- **真数据操作**：`data_section.dart`（备份/还原/重置）、`wizard_import.dart`、
  `usage_list.dart:336`（`clearTokenUsage`）。

**为什么要改**：第一类是在 `initState` / 手势回调里做持久化，属于业务逻辑落在了 widget 里；
第二类量少且本来就是「设置页对着数据库干活」，可以接受。

**改法**：只处理第一类。加一个薄封装（`services/system/ui_prefs.dart` 或直接挂在
`WorkbenchUIState` 一类已有状态上），把 `getSetting('xxx_width')` / `saveSetting` 收进去，
UI 侧只见 `UiPrefs.sidebarWidth(...)`。**别为此发明新层**，这是一个文件的事。

**验收**：`flutter analyze` 干净；`grep -rl "database_service.dart" lib/screens lib/widgets`
从 16 降到 8 上下；`workbench_panel_toggle_test.dart`、`file_browser_staging_column_test.dart`
全绿。

**A1 留下的服务层尾巴**（A1 已做完删除，这几处记在这里免得随它一起丢）：状态层与
任务队列已经全部改成构造函数注入，助手与 LLM 侧还有六处写死的 `DatabaseService()`——
`assistant/knowledge_base_service.dart:174/190/352/357`、`assistant/prompt_optimizer_agent.dart:937`、
`llm/context_budget.dart:167`，外加 `tasks/ai_rename_agent.dart:380` 的 `ImageLayerRepository()`。
它们都不对外声称能注入，所以不是「半通的口子」，只是还没接上；做本条时顺手一起收掉，
形状照 `DatabaseService.forDatabase` 那一套（仓储收 `db:`、服务收 `database:`）。

---

## 不要重复立项（本轮明确判定不做）

| 手册条目 | 为什么不做 |
|---|---|
| `freezed` / `built_value` 生成模型 | 13 个手写模型共 1290 行，已经不可变、`==`/`hashCode` 齐全。引入 `build_runner` 要给 CI 和每次改模型都加一道生成步骤，换来的是已经有的东西 |
| 声明式路由（`go_router`） | 全仓 `Navigator.push` 只有 6 处，导航是外壳 + 索引式目的地（`widgets/shell/app_destinations.dart`）。桌面工具这样是对的，换路由器等于为深链接重写外壳，而没有深链接的需求 |
| 拆 `llm_dispatcher.dart`（1720 行） | `docs/architecture/llm-three-layer.md` 写明了它是**故意**做成唯一一张路由表；拆开就退回「分支到处散」的老问题。大文件拆分那一轮（`git show 59e392c:docs/plans/2026-09-large-file-split.md`）已经把它排除过一次 |
| 引入 `get_it` 之类的容器 | 见 A1 的「注意」。要的是构造函数注入，不是再加一套查找规则 |
| 每个功能一套 ViewModel | 状态层是 11 个 `ChangeNotifier`，各自按屏幕/领域切，并且 `app_state.dart:70` 那段注释记录了「子状态各自当 provider」这个决定的由来（合并广播导致全app重建的回归）。手册的 per-feature VM 在这里只会把同一件事再切一刀 |

## 审计基线（复核时对表）

- 提交 `73aaa68`（v4.24.0），`flutter analyze` **No issues found**。
- `lib/` 非生成代码 142,160 行：screens 56,391 / services 40,922 / widgets 34,809 /
  state 4,076 / core 3,789 / models 1,290 / bench 473。测试 293 文件 / 55,729 行。
- `lib/services/` 里 `BuildContext` **0** 处、l10n 导入 **0** 处、`material.dart` **2** 处。
- 全仓 `TODO/FIXME/HACK` **0**、`print(` **0**、`// ignore:` **7** + `ignore_for_file` **4**、
  硬编码用户可见文案 **0**。
- 13 个模型中 11 个完全不可变；状态层交出的列表是整体重新赋值（`_transcript`
  `prompt_optimizer_session.dart:330` 一类），A5 是唯一的例外。
