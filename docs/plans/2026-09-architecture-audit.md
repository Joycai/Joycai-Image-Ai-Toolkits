# 架构审计 · 2026-09-21

对照 Flutter 架构手册（分层隔离、MVVM、仓储模式、不可变状态、构造函数注入）把 `lib/`
整体过了一遍，在 `73aaa68`（v4.24.0，`flutter analyze` 干净）上逐条核实。

**结论**：分层本身比手册要求得更严，而且是 `test/source_layout_test.dart` 用十条规则钉死的；
真正的偏离只有两个方向——**依赖注入**（用单例当服务定位器，A1）与**数据边界上的领域模型**
（两个仓储在传裸 map，A2）。**两条都已做**，A3（门面绕 map 一圈）、A4（模型带展示逻辑）、A5（队列交出内部列表）、
A6（`test/` 分层镜像 `lib/`）、A8（UI 直连 `DatabaseService` 存面板宽度）也已做，结论见
[`README.md`](README.md) 那行指针。只剩 A7。

**怎么用这份文件**：一条一条做，每条自带验收。做完一条就把它从本文件删掉，并在
[`README.md`](README.md) 的「已执行」表里登记结论住在哪；条目清空后删掉本文件。
末尾「不要重复立项」一节是本轮**明确判定不做**的，别再提。

## 总表

| 编号 | 一句话 | 触及 | 状态 |
|---|---|---|---|
| A7 | workbench 一个目录占 lib 的 21%，提示词助手实质是独立功能 | `screens/workbench/` | 未开工 |

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

**注意**：**这条排在最后**。跟已经做完的 A6 一样是大 diff，而且比 A6 更容易和别人的分支撞车。
前提是 A1–A6 先落地——现在都已落地。

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
