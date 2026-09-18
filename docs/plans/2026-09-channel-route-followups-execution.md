# 渠道 × 线路的后续 · 执行清单

来源：`docs/plans/README.md`「还欠的 · 渠道 × 线路（2026-09-18）」六条。设计依据 Claude Design
`D1f 渠道与线路`（4b 向导「私有能力一词」、4d 联网矩阵「未实测 help」、4f 合并计数分写、4g 手机线路条横向滚动、
4c 路径四态）。分支 `claude/channel-route-followups`，一片一个 commit，两个阶段各跑一次 `/code-review high`。

闸：每个 commit 前 `flutter analyze` 为 "No issues found!"，`flutter test -x screenshots` 全绿；l10n 四语同改。

## 裁定（原「待定」的，本轮定下）

| 条 | 裁定 | 理由 |
|---|---|---|
| 换预设建哪些线路 | 与向导一致：`plannedChannelRoutes`，平台全部线路；「自定义」只建所选一条 | 换预设本来就整体替换线路表，建一半让人再去逐条「启用」没有意义；存量模型由 `afterChannelEdit` 改走主线路并提示 |
| 空串路径 | 显式「主机本身」一态：徽标 `主机本身 · 默认 /v1` + 恢复默认；未设时路径行给「用主机本身」文字钮 | 老数据能如实显示，界面也能写回 |
| 渠道栏副行不显示渠道标签 | 维持（设计 ① 原意），从欠账表划掉 | 实现与设计一致，不是出入 |
| 作用域灰字位置 / 手机线路条 / 合并计数 | 改代码对齐 D1f | 设计稿是依据；`AppSectionLabel` 加 `suffix`（紧跟标题），不动 `trailing` 语义 |
| 「未实测」数据从哪来 | 平台画像声明 `untestedWebSearch`（发得出、没实机验过的线路）：New API 与自定义的 Anthropic 面 | 画像是数据，适配层不分平台（不变量 4、5） |

## 阶段一 · 行为

| 片 | 内容 | 文件 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | 合并改写助手对话里的模型链接（`LLMMessage.modelDbId`） | `assistant_session_repository.dart`、`channel_merge_executor.dart` | 仓库测试：改写与计数只动命中的消息；执行器顺序测试 | ☑ |
| 2 | 合并引用计数分写：选择 · 用量记录 · 对话链接 | `channel_merge_executor.dart`、`channel_merge_review.dart`、l10n | 执行器测试；截图 4f | ☑ |
| 3 | 换预设建平台全部线路 | `channel_edit_dialog.dart` | 小部件测试：换到 MiniMax 后两条线路都建好、没有「启用」行 | ☑ |
| 4 | 空串路径「主机本身」 | `channel_routes.dart`、`channel_route_table.dart`、l10n | `withPath(k,'')` 存空串、默认为空的平台归一为 null；小部件测试 | ☑ |

阶段一评审：`/code-review high` 片 1–4 —— 1 条，已修：打开着的助手对话在内存里握着旧 `modelDbId`，压缩时
`compactAll` 会把旧 id 写回；合并时也改写 `PromptOptimizerAgent.sessions` 里的历史与对话条目（`remapModelLinks`）。

## 阶段二 · 界面

| 片 | 内容 | 文件 | 验收 | 状态 |
|---|---|---|---|---|
| 5 | 联网矩阵第三态「未实测」 | `platforms.dart`、`channel_routes.dart`、`model_edit_routes.dart`、l10n | 单测：New API Anthropic 未实测、百炼 Chat 可发 | ☐ |
| 6 | 向导「将建立的线路」每行私有能力一词 | `channel_routes.dart`（`featuresOf`）、`wizard_form_steps.dart`、l10n | 单测；截图 4b | ☐ |
| 7 | 作用域灰字紧跟标题；手机线路条横向滚动 | `app_section_label`、`model_edit_layouts.dart`、`model_edit_routes.dart` | 截图 4d / 4g；组件画廊不变 | ☐ |
| 8 | 文档收尾：欠账表划掉六条、架构笔记补裁定、退役本清单 | `docs/plans/README.md`、`docs/architecture/llm-three-layer.md` | — | ☐ |

阶段二评审：`/code-review high` 片 5–8。之后 bump minor（4.13.0）并开 PR。

## 施工记录

- 片 2：设计写「工作台、提示词助手里选着的 3 处」；助手的模型选择不落库（只有工作台、视频、AI 重命名三个设置键），
  所以文案是「N 处已选的模型」。第三类「助手对话里的模型链接」是片 1 新增的改写对象，一并分写；为零的类不出现。
- 片 4：「用主机本身」钮只在自定义平台（新增 `PlatformProfile.guessedPaths`）默认态的行上出现——New API 等中转的
  布局是已知的，每行都挂一个钮是噪音；已存成空串的任何平台都如实显示「主机本身 · 默认 /v1」并可恢复默认。
