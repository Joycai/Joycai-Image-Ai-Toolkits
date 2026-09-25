# 代码结构与风格审计（执行清单）

**基线** `6231534` 2026-09-25 v4.28.0 · **分支** `chore/code-structure-audit` · **状态** 全部已做

目标：对照 Flutter / Effective Dart 规范审一遍分包、组织与代码风格，能断言的钉进
`analysis_options.yaml` 或 `test/source_layout_test.dart`，不留只靠 review 守的规矩。

## 0. 审计结论（基线上的测量）

| 项 | 结果 | 处理 |
|---|---|---|
| `flutter analyze` / `source_layout_test` | 均为零问题 | — |
| 文件与目录命名 | 全部 snake_case（`l10n/src/zh_Hant` 是语言代码，照 ARB 约定） | — |
| import 风格 | `lib/` 内 1879 条全为相对路径，无 `package:` 自引 | 片 3 用 `prefer_relative_imports` 钉住 |
| 未被 import 的文件 | 0 | — |
| **`dart format`** | **789 个文件里 722 个不合格式**；任何行宽下都一样，说明从来没跑过 | 片 4 |
| **`widgets/` 只被一个 screen 用到的文件** | CLAUDE.md 与布局测试的提示语都写了「只有一个 screen 用的共享 widget 应当放在那个 screen 下」，但没有断言；按传递可达性算，14 个非设计系统文件（含 `channel_wizard/` 四个 part）违规 | 片 1 迁移 + 断言 |
| 重复声明 | `modelKindIcon` 在 `widgets/ui/model_tag_chip.dart` 与 `widgets/models/model_edit_controls.dart` 各一份（台账「还欠的」旧条目），默认值不同 | 片 2 |
| Effective Dart 规则抽样 | `directives_ordering` 217 · `omit_local_variable_types` 1373 · `unnecessary_lambdas` 53 · `prefer_final_in_for_each` 61 · `unawaited_futures` 46 · `prefer_const_*` 28 · `avoid_multiple_declarations_per_line` 16 · `use_colored_box` / `use_decorated_box` 4 | 片 3 |
| 未用依赖 | `cupertino_icons`（全仓无 `CupertinoIcons`，模板遗留）；`sqflite` 与 `video_player_win` 虽无直接 import，但分别是 macOS/iOS/Android 的数据库插件与 `video_player` 的 Windows 实现，**保留**，理由写在 `pubspec.yaml` 各自旁边 | 片 5 |

判定不做的：

- **行宽 80。** 80 / 100 / 120 三档实测改动量：+51744/−26913 · +25760/−22980 · +19654/−29130。取
  100：改动最小之一，且与 Flutter 框架仓库自己的 `formatter: page_width: 100` 一致（核对过
  flutter/flutter 的 `analysis_options_common.yaml`；尾逗号用默认的 automate，框架也没写 `preserve`——
  `preserve` 能少动 32 个文件，但那就不是框架的设置了）。
- `public_member_api_docs`（2969）、`sort_constructors_first`（354）、`discarded_futures`（233）、
  `avoid_redundant_argument_values`（195，显式写出的默认值常是有意的说明）、`cascade_invocations`、
  `avoid_dynamic_calls`、`avoid_catches_without_on_clauses`：不是 Flutter 推荐集的一部分，收益不抵噪音。
- workbench 根下的八个 widget 文件：它们是这个屏幕的顶层区块（画廊、侧栏、配置面板、布局），不是违规；
  A7 已裁定过不动。

## 1. 分片

| 片 | 内容 | 验收 | 状态 |
|---|---|---|---|
| 1 | 单屏 widget 归位：`widgets/dialogs/{library,prompt_history}_dialog` → `screens/workbench/widgets/config/`；`widgets/placeholders/permission_placeholder` → `screens/workbench/widgets/gallery/`；`widgets/dialogs/task_log_dialog` → `screens/batch/`；`widgets/models/{channel_avatar,channel_edit_dialog,channel_probe_result_card,channel_route_table,channel_wizard_dialog,channel_wizard/,discovery_dialog}` → `screens/models/widgets/`。测试跟着镜像；`source_layout_test` 新增断言（设计系统除外，`main.dart` 视为外壳而非 screen） | 双闸门绿；新断言在迁移前能失败 | 已做 |
| 2 | 合并 `modelKindIcon`：编辑器改用 `widgets/ui/model_tag_chip.dart` 那份（卡片用的就是它；编辑器注释本就写着「卡片那一个」） | 双闸门绿 | 已做 |
| 3 | lint（review 后加 `avoid_void_async`）：`directives_ordering` `prefer_relative_imports` ~~`omit_local_variable_types`~~ `unnecessary_lambdas` `prefer_final_in_for_each` `prefer_const_constructors` `prefer_const_declarations` `prefer_const_literals_to_create_immutables` `use_colored_box` `use_decorated_box` `avoid_multiple_declarations_per_line` `unawaited_futures`；`dart fix --apply` + 手工逐处（`unawaited_futures` 每处判断是漏了 `await` 还是有意不等） | `flutter analyze` 零问题；测试数不变 | 已做 |
| 4 | `dart format`：`analysis_options.yaml` 加 `formatter: page_width: 100`，全仓格式化一次（单独一个提交，只有格式），`.git-blame-ignore-revs` 记下它；CI 加格式闸门；CLAUDE.md 的闸门一节同步 | `dart format --set-exit-if-changed lib test tool` 通过 | 已做 |
| 5 | 去掉 `cupertino_icons` | `flutter pub get` + 双闸门绿 | 已做 |
| 6 | 收尾：review 循环、台账一行、删除本文件、bump version、开 PR | — | 已做 |

## 2. 施工记录

（偏离计划、review 发现记在这里。）

- 片 1：迁移前新断言列出的正是 14 个文件（含 `channel_wizard/` 四个 part），迁移后通过。
  `test/screenshots/shortcut_panel_test.dart` 有三个用例在本机失败（`widgets/shell/shortcut_panel.dart:364`
  的 Row 溢出 49px）——在基线 `6231534` 上同样失败，与本轮无关；`main` 上的 #346 已修，合入后消失。
- 片 2：两份的差别只在编辑器那份不转小写、未知 kind 落到 `forum`（卡片落到 `memory`）。编辑器的
  `tag` 来自 `model?.tag ?? 'chat'`，四个已知 kind 的图标两份相同；只有库里残留的未知 tag 会从
  `forum` 变成 `memory`——即与卡片一致，这正是编辑器注释要的。台账「还欠的」对应条目已销。
- 片 3：**`omit_local_variable_types` 撤回。** `dart fix` 对它的修复丢掉了声明类型给初始化式的上下文——
  `final double w = 10` 变成 int、`tester.widget<T>(…)` 的 T 退成 `Widget`、`Map<int, double> m = {}` 退成
  `Map<dynamic, dynamic>`——当场 24 个编译错误；更麻烦的是窄化后仍能编译的地方（插值里 `10.0` → `10`、集合元素
  变 `dynamic`）会静默变行为，1373 处没法逐一保证等价。Flutter 框架自己走的是反方向（`always_specify_types`），
  这条不是 Flutter 规范，判定不做。
  其余规则 `dart fix` 共 308 处（197 个文件），`unnecessary_lambdas` 53 处逐条看过：接收者都是局部 final、
  单例子状态或静态方法，改 tear-off 只是把接收者的求值提前到构建时，行为不变。
  `unawaited_futures` 46 处全部是有意不等：UI 回调里保存设置 / 刷新列表 / 后台扫描（后面紧跟
  `notifyListeners()`），任务队列在开始与结束时落库（sqflite 按提交顺序串行，不会乱序），Midjourney 的 IIFE
  往 controller 里推流，测试里打开对话框（其 future 在关闭时才完成）。一律 `unawaited(...)`，没有发现漏写
  `await` 的 bug——在 try/catch 里的那几处，加 `await` 反而会改行为（`ai_rename_dialog` 刷新失败会被当成
  「启动任务失败」报出来）。
  全量测试第一次跑时 `test/services/tasks/image_stream_save_test.dart` 的「fails after an image」失败一次，
  单独连跑六次全过：它在任务状态变 `failed` 后立刻断言用量行，而用量是异步落库的，高负载下会晚到——测试自身的
  竞态，与本片无关（`unawaited` 是恒等函数）；`main` 上的 #347 已修。
- 片 4：格式化后 10 处单行 `if` 被折成多行，触发 `curly_braces_in_flow_control_structures`，`dart fix` 补括号
  后并进同一个纯格式提交 `8fc956d`，记进 `.git-blame-ignore-revs`（本仓库用 merge commit 合 PR，SHA 会保留）。
  `flutter gen-l10n` 读同一份 formatter 设置，重新生成后格式检查仍是 0 改动，CI 里放在 gen-l10n 之后没问题。
  CLAUDE.md 的闸门从两道变三道（gate 0 = format）；两个写代码的项目 skill 的检查清单同步。
- **Review 第 1 轮（4 条）**：
  ① 分支落后 `main`（#346 / #347），合入后那四个文件没按行宽 100 格式化，CI 的格式闸门会挂——merge（不 rebase，
  否则 `8fc956d` 变了）、冲突的 `keyboard_section.dart` 我方只有格式改动，取 `main` 的；格式化单独一个提交
  `88767ce` 记进 `.git-blame-ignore-revs`。
  ② **片 3 的一处 `use_decorated_box` 不等价**：`wizard_form_steps.dart` 的线路列表带 `Border.all`，`Container`
  会按边框宽度给子组件让出 1px（`BoxDecoration.padding`），`DecoratedBox` 不会——每行贴到外框上、行间分隔线压住
  外框。补显式 `Padding(EdgeInsets.all(1))`；`channel_wizard_dialog_test` 加一条量位置的用例，修前失败
  （`536,661` 对 `537,662`）、修后通过。其余三处替换没有边框，等价。之前「行为不变」的说法对这一处不成立。
  ③ `source_layout_test` 的提示语里 `channel_avatar` 的旧路径。
  ④ `prompts_screen.dart` 还有五个 `void … async`（全仓仅此五处），加 `avoid_void_async` 并改成 `Future<void>`。
- **Review 第 2 轮（1 条）**：`use_decorated_box` 对带边框的 `Container` 照样报，照做就是第 1 轮那个 1px 问题，
  而且 `dart fix` 照样会做这个替换（第 3 轮实测：带边框也换）——在规则旁注明「带边框时不等价、`dart fix` 也会换，用 Padding 保住内缩」。其余（合并无丢失、
  `88767ce` 纯格式、位置用例去掉 Padding 会失败、升级日不会引入格式抖动）核过无问题。
- **Review 第 3 轮（4 条，目标覆盖度视角）**：① 上一条关于 `dart fix` 的说法是错的，改正 yaml 注释与本记录；
  ② CLAUDE.md 闸门一段并没理齐，重排；③ 四处早于本分支的 `// ignore: unawaited_futures`（两个截图测试、
  `real_async_test` 两处）在规则打开后与 `unawaited(...)` 的约定并存，改成后者；④ 片 1 搬的两个文件名与类名
  不符（里面是 `PromptLibrarySheet` / `PromptHistorySheet`，测试早已叫 `prompt_history_sheet_test`），趁这次已经
  断过一次历史，改名为 `prompt_library_sheet.dart` / `prompt_history_sheet.dart`。另：`pubspec.yaml` 里给
  `sqflite`、`video_player_win` 注明为何无 import 仍保留，免得下一轮审计再删。其余量过无问题：`lib/` 无 `print(`，
  剩下 5 处 `// ignore:` 都仍在起作用，测试文件命名、`part` 位置、pubspec 分组与资源路径都合规。
- **Review 第 4 轮**：No new findings。三道闸门在 HEAD 上全绿（format 0 改动 · analyze 零问题 · 3102 过 / 9 跳过）。
