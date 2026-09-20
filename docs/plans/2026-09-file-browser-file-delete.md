# 文件浏览器 · 删除文件（施工说明书）

设计稿：Claude Design 项目 `925a4d48-684e-4733-bca2-1aa808b7e18f` 的
**`B1c 文件浏览器-删除文件.dc.html`**（2026-09-20 出稿，五帧 `1a`–`1e` + 规格汇总）。
本轮只做文件删除；文件夹删除（`B1b · 1d`）已在 `folder_operations_service.dart` 里，
本轮沿用它的全部语汇，不重造。

## 立场

- 有废纸篓就进废纸篓，没有就说明「永久删除」——两者永不混为一谈，
  `toTrash` 失败绝不降级为永久删除（`TrashService` 既有约定）。
- **不做撤销、不做自制回收站。** 能还原的那条路就是系统废纸篓。
- 守卫落两层（见 memory `destructive-action-guards`）：对话框是一层，
  服务层执行时**重新自证**是另一层，不相信 UI 查过。

## 分片

| # | 片 | 文件 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | 服务层 | 新 `lib/services/files/file_delete_service.dart`、新 `test/file_delete_service_test.dart` | 目录 / 注册根 / 无废纸篓三条拒绝各有测试；单条失败不拖垮整批；删成功即 `ImageLayerRepository().forget` | ☑ |
| 2 | l10n | `lib/l10n/src/{en,zh,zh_Hant,ja}/browser.arb` | 四语同步，`merge_l10n` + `gen-l10n` 通过 | ☑ |
| 3 | 确认框 | 新 `lib/screens/browser/widgets/file_delete_dialog.dart` | `B1c · 1d / 1e`：warn+delete / err+delete_forever、清单卡 4 行 + 汇总行、Delete 键确认、取消 autofocus | ☑ |
| 4 | 右键菜单 | `lib/screens/browser/widgets/file_context_menu.dart` | `B1c · 1a / 1b`：末组独占一行、`danger: true`、trailing `Delete`、多选写进标签 | ☑ |
| 5 | 悬浮条 + Delete 键 | `lib/screens/browser/widgets/browser_selection_bar.dart`、`file_browser_screen.dart` | `B1c · 1c`：加入暂存 ┊ 红色字形删除 ┊ AI 重命名；恒为字形；宽度测量计入；Delete/Backspace 走同一条流程，搜索框有焦点时让位 | ☐ |
| 6 | 收尾 | 本文件退休 + `docs/plans/README.md` 台账行 | 两道闸门绿；`/code-review` 结论已处理 | ☐ |

## 施工记录（与稿的偏离写在这里）

（施工中填写）
