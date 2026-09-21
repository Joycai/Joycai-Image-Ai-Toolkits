# 架构审计 · 2026-09-21

对照 Flutter 架构手册（分层隔离、MVVM、仓储模式、不可变状态、构造函数注入）把 `lib/`
整体过了一遍，在 `73aaa68`（v4.24.0，`flutter analyze` 干净）上逐条核实。

**结论**：分层本身比手册要求得更严，而且是 `test/source_layout_test.dart` 用九条规则钉死的；
真正的偏离只有两个方向——**依赖注入**（用单例当服务定位器，A1）与**数据边界上的领域模型**
（两个仓储在传裸 map，A2）。**两条都已做**，A3（门面绕 map 一圈）、A4（模型带展示逻辑）、A5（队列交出内部列表）也已做，结论见
[`README.md`](README.md) 那行指针。剩下三条是局部的。

**怎么用这份文件**：一条一条做，每条自带验收。做完一条就把它从本文件删掉，并在
[`README.md`](README.md) 的「已执行」表里登记结论住在哪；条目清空后删掉本文件。
末尾「不要重复立项」一节是本轮**明确判定不做**的，别再提。

## 总表

| 编号 | 一句话 | 触及 | 状态 |
|---|---|---|---|
| A6 | `test/` 269 个文件平铺在根下，而 `lib/` 的分组目录根下一个散文件都不许有 | `test/` | 未开工 |
| A7 | workbench 一个目录占 lib 的 21%，提示词助手实质是独立功能 | `screens/workbench/` | 未开工 |
| A8 | 16 个 UI 文件直连 `DatabaseService`，绝大多数只为存侧栏宽度 | `screens/`、`widgets/` | 未开工 |

---

## A6 · `test/` 平铺

**现状**：269 个测试文件全部平铺在 `test/` 根下（另有 `test/screenshots/` 与 `test/support/`）。
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
前提是 A1–A5 先落地——现在都已落地。

---

## A8 · UI 直连 `DatabaseService`

**现状**：16 个文件在 `screens/` / `widgets/` 里直接调 `DatabaseService()`。分两类：

- **偏好设置**（8 处）：侧栏宽度一类，`file_browser_screen.dart:151/528`、
  `models_screen.dart:84/198`、`prompts_screen.dart:101`、`workbench_layout.dart:278/452`。
- **真数据操作**：`data_section.dart`（备份/还原/重置）、`wizard_import.dart`、
  `usage_list.dart:335`（`clearTokenUsage`）。

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
| 引入 `get_it` 之类的容器 | A1 做的是构造函数注入（结论见 [`README.md`](README.md) 那行指针）；要的就是它，不是再加一套查找规则 |
| 每个功能一套 ViewModel | 状态层是 11 个 `ChangeNotifier`，各自按屏幕/领域切，并且 `app_state.dart:70` 那段注释记录了「子状态各自当 provider」这个决定的由来（合并广播导致全app重建的回归）。手册的 per-feature VM 在这里只会把同一件事再切一刀 |

## 审计基线（复核时对表）

- 提交 `73aaa68`（v4.24.0），`flutter analyze` **No issues found**。
- `lib/` 非生成代码 142,160 行：screens 56,391 / services 40,922 / widgets 34,809 /
  state 4,076 / core 3,789 / models 1,290 / bench 473。测试 293 文件 / 55,729 行。
- `lib/services/` 里 `BuildContext` **0** 处、l10n 导入 **0** 处、`material.dart` **2** 处。
- 全仓 `TODO/FIXME/HACK` **0**、`print(` **0**、`// ignore:` **7** + `ignore_for_file` **4**、
  硬编码用户可见文案 **0**。
- 13 个模型中 11 个完全不可变；状态层交出的列表是整体重新赋值（`_transcript`
  `prompt_optimizer_session.dart:330` 一类），任务队列曾是唯一的例外（A5，已收）。
