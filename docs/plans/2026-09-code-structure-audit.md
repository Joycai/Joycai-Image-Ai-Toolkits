# 代码结构与风格审计（执行清单）

**基线** `6231534` 2026-09-25 v4.28.0 · **分支** `chore/code-structure-audit` · **状态** 进行中

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
| **`widgets/` 只被一个 screen 用到的文件** | CLAUDE.md 与布局测试的提示语都写了「只有一个 screen 用的共享 widget 应当放在那个 screen 下」，但没有断言；按传递可达性算，10 个非设计系统文件（含 `channel_wizard/` 四个 part）违规 | 片 1 迁移 + 断言 |
| 重复声明 | `modelKindIcon` 在 `widgets/ui/model_tag_chip.dart` 与 `widgets/models/model_edit_controls.dart` 各一份（台账「还欠的」旧条目），默认值不同 | 片 2 |
| Effective Dart 规则抽样 | `directives_ordering` 217 · `omit_local_variable_types` 1373 · `unnecessary_lambdas` 53 · `prefer_final_in_for_each` 61 · `unawaited_futures` 46 · `prefer_const_*` 28 · `avoid_multiple_declarations_per_line` 16 · `use_colored_box` / `use_decorated_box` 4 | 片 3 |
| 未用依赖 | `cupertino_icons`（全仓无 `CupertinoIcons`，模板遗留）；`sqflite` 虽无直接 import 但 macOS/iOS/Android 的 `openDatabase` 靠它的插件实现，**保留** | 片 5 |

判定不做的：

- **行宽 80。** 80 / 100 / 120 三档实测改动量：+51744/−26913 · +25760/−22980 · +19654/−29130。取
  100：改动最小之一，且与 Flutter 框架仓库自己的 `formatter: page_width: 100` 一致。
- `public_member_api_docs`（2969）、`sort_constructors_first`（354）、`discarded_futures`（233）、
  `avoid_redundant_argument_values`（195，显式写出的默认值常是有意的说明）、`cascade_invocations`、
  `avoid_dynamic_calls`、`avoid_catches_without_on_clauses`：不是 Flutter 推荐集的一部分，收益不抵噪音。
- workbench 根下的八个 widget 文件：它们是这个屏幕的顶层区块（画廊、侧栏、配置面板、布局），不是违规；
  A7 已裁定过不动。

## 1. 分片

| 片 | 内容 | 验收 | 状态 |
|---|---|---|---|
| 1 | 单屏 widget 归位：`widgets/dialogs/{library,prompt_history}_dialog` → `screens/workbench/widgets/config/`；`widgets/placeholders/permission_placeholder` → `screens/workbench/widgets/gallery/`；`widgets/dialogs/task_log_dialog` → `screens/batch/`；`widgets/models/{channel_avatar,channel_edit_dialog,channel_probe_result_card,channel_route_table,channel_wizard_dialog,channel_wizard/,discovery_dialog}` → `screens/models/widgets/`。测试跟着镜像；`source_layout_test` 新增断言（设计系统除外，`main.dart` 视为外壳而非 screen） | 双闸门绿；新断言在迁移前能失败 | 已做 |
| 2 | 合并 `modelKindIcon`：编辑器改用 `widgets/ui/model_tag_chip.dart` 那份（卡片用的就是它；编辑器注释本就写着「卡片那一个」） | 双闸门绿 | 待做 |
| 3 | lint：`directives_ordering` `prefer_relative_imports` `omit_local_variable_types` `unnecessary_lambdas` `prefer_final_in_for_each` `prefer_const_constructors` `prefer_const_declarations` `prefer_const_literals_to_create_immutables` `use_colored_box` `use_decorated_box` `avoid_multiple_declarations_per_line` `unawaited_futures`；`dart fix --apply` + 手工逐处（`unawaited_futures` 每处判断是漏了 `await` 还是有意不等） | `flutter analyze` 零问题；测试数不变 | 待做 |
| 4 | `dart format`：`analysis_options.yaml` 加 `formatter: page_width: 100`，全仓格式化一次（单独一个提交，只有格式），`.git-blame-ignore-revs` 记下它；CI 加格式闸门；CLAUDE.md 的闸门一节同步 | `dart format --set-exit-if-changed lib test tool` 通过 | 待做 |
| 5 | 去掉 `cupertino_icons` | `flutter pub get` + 双闸门绿 | 待做 |
| 6 | 收尾：review 循环、台账一行、删除本文件、bump version、开 PR | — | 待做 |

## 2. 施工记录

（偏离计划、review 发现记在这里。）

- 片 1：迁移前新断言列出的正是 14 个文件（含 `channel_wizard/` 四个 part），迁移后通过。
  `test/screenshots/shortcut_panel_test.dart` 有三个用例在本机失败（`widgets/shell/shortcut_panel.dart:364`
  的 Row 溢出 49px）——在基线 `6231534` 上同样失败，与本轮无关，本机 Flutter 3.47.5，不在这一轮修。
