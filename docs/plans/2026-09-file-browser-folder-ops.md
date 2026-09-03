# 文件浏览器：文件夹的新建 / 改名 / 删除 / 移动

**性质**：需求设计 + 实施拆分 + 给 Claude Design 的出稿 prompt。
**状态**：2026-09-03 按设计稿 `B1b 文件夹操作.dc.html`（13a–13g）实现完毕，见 §8。
**范围**：仅文件浏览器（`B1`）左栏目录树。工作台共用同一棵树组件，但这些操作**只在浏览器里出现**（与暂存区、拖放的门控一致）。
**一句话**：把左栏从「登记表」变成一个能管文件夹的树，但登记进来的根目录本身受保护。

---

## 0. 现状

| 部件 | 文件 | 现在能做什么 |
|---|---|---|
| 目录树 | `screens/workbench/folder_list.dart` · `directory_tree_item.dart` | 根目录列表（`sourceDirectories`）、勾选/点击切换活动目录、展开子目录（懒加载、按 `refreshCounter` 重扫）、根有 `×` 从列表移除 |
| 文件夹右键 | `screens/browser/widgets/folder_context_menu.dart` | 仅看此目录 / 取消全部 / 移动·复制 N 项到此 / 系统中显示 |
| 拖放 | `directory_tree_item.dart` `_MaybeDropTarget` | 只接受 `List<BrowserFile>`（文件）；默认移动，Ctrl 复制 |
| 文件搬运 | `services/file_transfer_service.dart` | `plan()` → 冲突（跳过/覆盖/改名）→ `execute()`，逐文件进度，跨盘退化为复制再删 |
| 状态 | `state/file_browser_state.dart` | `sourceDirectories` / `activeDirectories` 以 `|` 拼接持久化；`refresh()` 全量重扫活动目录 |
| 暂存 | `state/file_staging_state.dart` | 按路径持久化的搬运清单；`revalidate()` 把消失的路径标成「已失效」 |

树本身**没有**焦点概念（F2 / Delete 在屏幕层作用于网格里选中的文件），也**没有**目录监听（每次操作后靠 `refresh()`）。

---

## 1. 规则：根目录受保护

「添加进来的根目录」= `sourceDirectories` 里的路径。它不是磁盘上的一种文件夹，而是用户与应用之间的一份登记，所以对它的操作要按登记的语义来定：

| 操作 | 子目录 | 根目录 | 理由 |
|---|---|---|---|
| 新建子文件夹 | ✅ | ✅ | 根目录当然可以往里建 |
| 改名 | ✅ | ✅ **并同步改写登记路径** | 改名不改变「它是哪个文件夹」，登记跟着走即可 |
| 删除 | ✅ 需确认 | ❌ **菜单项替换为「从列表移除」** | 删磁盘上的根目录 = 删掉用户整个素材库；已有的 `×` 移除就是根目录的「删除」 |
| 移动 | ✅ | ❌ 灰置 | 把根挪进另一个根的子目录，登记就变成了子目录，语义塌了；要挪根请先移除再添加 |
| 作为移动目标 | ✅ | ✅ | 不受影响 |

第二条保护：**任何操作都不能让树里出现两份同一路径**。改名/移动后如果新路径已经是另一个根或活动目录，直接拒绝（见 §2.5）。

---

## 2. 四个操作

### 2.1 新建子文件夹

- **入口**：文件夹右键「新建子文件夹」；左栏头部现有「添加文件夹」图标钮**不变**（那是登记根目录，两件事不混）。
- **形式**：树内行内编辑（Finder / VS Code 的做法），不弹窗。父节点若折叠先展开，在子列表**顶部**插入一行：琥珀文件夹图标 + 输入框（预填「新建文件夹」并全选）。
- **提交**：Enter 或失焦提交，Esc 取消。提交后父节点重扫子目录，新行落到按字母排序后的正确位置，并短暂高亮（沿用行选中态的主色 14% 底，`AppMotion` 淡出）。
- **不做的事**：不自动勾选为活动目录（空文件夹勾上只会让网格变空），不改暂存区目标。用户下一步通常是右键它「移动 N 项到此」，那条路已经通。

### 2.2 改名

- **入口**：右键「重命名」；行获得焦点时 F2。
- **形式**：同一套行内编辑，预填当前名并全选。
- **提交后的连锁改写**（`old` → `new` 前缀替换，含所有后代）：
  1. `FileBrowserState.sourceDirectories` / `activeDirectories`（根改名时根路径本身也在内）
  2. `FileStagingState` 的条目路径与 `destination`——否则暂存里的文件会在下次 `revalidate()` 时被标成「已失效」，而它们明明还在
  3. 工作台 `GalleryState.sourceDirectories`：同一磁盘路径若也登记在工作台，一并改写，否则它在工作台里立刻变成「无法访问」
- **网格**：改名后 `refresh()`，网格里的文件路径自然更新；选中集按路径匹配会被清空，接受。

### 2.3 删除

- **入口**：右键「删除」；行焦点时 Delete / Backspace。根目录此位置显示「从列表移除」，走现有 `_confirmRemove`。
- **确认弹窗**（`AppDialog`，`AppButtonVariant.destructive`）分两态：
  - **空文件夹**：标题「删除文件夹？」+ 名称，一句说明，确认钮「删除」。
  - **非空**：弹窗打开时异步盘点（子文件夹数、文件数、总大小，`compute` 在 isolate 里走），盘点期间确认钮 `loading`；盘点完成后正文列出三格 mono 计数，确认钮文案带数量「删除 128 项」。计数是把「这不是空的」放到用户手指下面，而不是只放在正文里。
- **回收站**：平台支持就移到系统回收站，不支持就永久删除，弹窗文案随之切换（「移到回收站」/「删除 · 无法撤销」）。能力在启动时探测一次（`FolderOperationsService.trashSupported`），不是每次删除时试错：
  - **Windows**：`win32` 包（已是间接依赖，升为直接依赖）调 `SHFileOperationW`，`FO_DELETE | FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT`，路径要双 NUL 结尾。
  - **macOS**：`MainFlutterWindow.swift` 里加一个 MethodChannel，调 `FileManager.default.trashItem(at:resultingItemURL:)`。应用目前只有 `window_chrome_service.dart` 一条通道，照它的形状再开一条。
  - **Linux**：`Process.run('gio', ['trash', path])`；`gio` 不存在即视为不支持。
  - 回收站调用失败（权限、跨卷、网络盘）→ 报错，**不**静默退化为永久删除；用户点的是「移到回收站」，就不能拿到永久删除的结果。
- **善后**：`activeDirectories` 去掉该前缀下的所有路径；`FileStagingState.revalidate()`（条目正确变成「已失效」，这是它设计上的行为）；`refresh()`。

### 2.4 移动

两个入口，一个引擎：

- **拖放（主路径）**：树里的文件夹行成为 `Draggable<FolderDragPayload>`；`_MaybeDropTarget` 同时接受文件载荷与文件夹载荷。拖影是现有 `_DragChip` 同款深底胶囊，文案「移动「cha」」。
  - **非法目标**（拖到自己、自己的后代、当前父目录、根目录本身作为被拖者）：目标行**不亮**，指针不变——不亮就是答案，不弹提示。
  - 不支持 Ctrl 复制整个文件夹（复制目录树不是本需求；文件复制走暂存区）。
- **菜单「移动到…」**：调系统目录选择器（`FilePicker.getDirectoryPath`，已在用）。选定后进入同一引擎。选到非法目标（自身/后代/同名已存在）→ `AppSnackBar.warning`。
- **引擎规则**：
  - 目标下已存在同名文件夹 → 拒绝，不合并（合并 = 逐文件冲突决策，属于暂存区的活）。
  - 同盘 → `Directory.rename`，瞬时。
  - 跨盘 → `rename` 抛错后退化为递归复制再删，走一个**进度弹窗**（复用 `B1a` `12e/12f` 的 6px 主色进度轨 + 跨盘信息条 + 完成汇总）。中途取消：已复制的目标端保留、源端不删，汇总里说清楚。
  - 成功后连锁改写同 §2.2（活动目录、暂存、工作台登记）。

### 2.5 名称校验（新建/改名共用）

行内编辑框下方一行 `bodySmall` 错误文案（错误色），提交钮不可用：

| 情况 | 文案要点 |
|---|---|
| 空 / 全空白 | 名称不能为空 |
| 含 `/` `\`；Windows 另加 `< > : " \| ? *` 及控制字符 | 名称不能包含 … |
| Windows 保留名 `CON` `PRN` `AUX` `NUL` `COM1–9` `LPT1–9`（不分大小写、忽略扩展名） | 这是系统保留名 |
| 结尾是 `.` 或空格（Windows） | 自动裁掉，不报错 |
| 同级已存在（Windows/macOS 不分大小写比较） | 已有同名文件夹 |
| 新路径已是另一个登记根/活动目录 | 该路径已在列表中 |
| 与原名相同（改名） | 静默取消，不算错误 |

---

## 3. 架构落点

```
lib/
  services/folder_operations_service.dart   # 新：纯 IO + 校验，无 Flutter 依赖
  state/file_browser_state.dart             # +rewritePathPrefix(old,new) +pruneRemoved(path)
  state/file_staging_state.dart             # +rewritePathPrefix(old,new)
  state/gallery_state.dart                  # +rewritePathPrefix(old,new)
  screens/workbench/directory_tree_item.dart  # 行内编辑态、Focus、文件夹 Draggable、双载荷 DropTarget
  screens/browser/widgets/folder_context_menu.dart  # 四个新菜单项 + 根目录门控
  screens/browser/widgets/folder_delete_dialog.dart  # 新：删除确认（空/非空两态）
  screens/browser/folder_move_flow.dart      # 新：移动引擎 UI 侧（进度弹窗，参照 staging_paste_flow）
```

**`FolderOperationsService`**（`static`，与 `FileTransferService` 同构）：

```dart
enum FolderNameError { empty, illegalChars, reservedName, exists, registered }
FolderNameError? validateName(String parent, String name, {Set<String> registered});

Future<FolderInventory> inventory(String path);           // isolate 里数：dirs, files, bytes
Future<String> create(String parent, String name);        // 返回新路径
Future<String> rename(String path, String newName);
bool get trashSupported;                                  // 启动时探测一次
Future<void> delete(String path, {required bool toTrash}); // toTrash 仅在 trashSupported 时为 true
enum FolderMoveRejection { intoSelf, intoDescendant, sameParent, targetExists, isRoot }
FolderMoveRejection? canMove(String path, String destination, {Set<String> roots});
Future<FolderMoveOutcome> move(String path, String destination,
    {void Function(FileTransferProgress) onProgress, bool Function() isCancelled});
```

跨盘的递归复制在 `move` 内部处理，`onProgress` 沿用 `FileTransferProgress`（逐文件粒度，理由与文件搬运一样：`File.copy` 没有内部进度）。

**树的键盘**：现在的树没有焦点。每行包一个 `Focus`，点击（含右键）即取得焦点；F2 / Delete 在行焦点时由行处理并 `handled`，否则冒泡到屏幕层继续作用于网格文件。这是最小改动，但要注意 `_handleKeyEvent` 里的 F2 分支只在「网格里有选中文件」时命中——两者天然不冲突。

**状态规则**：行内编辑态、展开态是瞬时 UI 状态，留在 `DirectoryTreeItem` 的 `State` 里（规则针对的是共享/持久数据）。所有前缀改写都产生新列表实例再 `notifyListeners()`。

---

## 4. 文案键（`browser.arb`，四语同步）

`newSubfolder` · `newFolderDefaultName` · `renameFolder` · `moveFolderTo` · `deleteFolder` · `removeFromList`
`deleteFolderTitle` · `trashFolderTitle` · `deleteFolderEmptyDesc` · `deleteFolderInventory(dirs, files, size)` · `deleteFolderIrreversible` · `deleteFolderToTrashDesc` · `deleteFolderCount(count)` · `trashFolderCount(count)` · `folderTrashed`
`folderNameEmpty` · `folderNameIllegalChars(chars)` · `folderNameReserved` · `folderNameExists` · `folderPathRegistered`
`moveFolderIntoSelf` · `moveFolderTargetExists` · `moveFolderRootLocked` · `dragMoveFolderHint(name)`
`folderMovingTitle(name)` · `folderMoveCancelledDesc`
`folderCreated` · `folderRenamed` · `folderDeleted` · `folderMoved` · `folderOpFailed(error)`

---

## 5. 实施拆分

| PR | 内容 | 验证 |
|---|---|---|
| 1 | `FolderOperationsService` + 三个 state 的 `rewritePathPrefix` | 单测：临时目录下四个操作 + 全部校验分支 + 跨盘用两个临时根模拟不了，只测退化路径被调用。注意每测 `tearDown` 删临时目录会和懒打开的 DB 竞争，用全局一次性目录 |
| 1b | 回收站能力：`win32` 直接依赖 + macOS MethodChannel + Linux `gio`，`trashSupported` 启动探测 | 三平台各手测一次；单测只覆盖「不支持时 toTrash 被拒」 |
| 2 | 右键菜单四项 + 根目录门控 + 删除弹窗（回收站/永久两套文案） | 截图：`flutter test test/screenshots`，补一张菜单两态 |
| 3 | 行内新建/改名 + 行焦点 + F2/Delete | Widget 测试：校验错误态、Esc 取消、Enter 提交、与屏幕层 F2 不抢 |
| 4 | 文件夹拖放 + 「移动到…」 + 进度弹窗 | Widget 测试：非法目标不亮；服务层测跨盘退化 |
| 5 | l10n 四语 + `flutter analyze` 归零 | — |

---

## 6. 给 Claude Design 的 prompt

> 项目：Joycai Image Tool（`925a4d48-…`）。**新建文件** `B1b 文件夹操作.dc.html`，不要往 `B1 文件浏览器.dc.html` 里加帧——它已经 259 KB，超过读取上限。B1b 自身也请控制在 200 KB 内。

```
在 Joycai Image Tool 项目里新建一个页面文件「B1b 文件夹操作.dc.html」，画文件浏览器（B1）左栏目录树的文件夹管理交互。先读「Joycai 设计规范.dc.html」的 §1 基础规范和 §2 标准组件（10a），再读「B1 文件浏览器.dc.html」的左栏和「B1a 暂存区.dc.html」的 12d（文件夹右键菜单）、12e/12f（进度与汇总弹窗）——新帧要和它们是同一套东西，编号从 13a 起。

## 这棵树现在长什么样（照这个画，别重设计）
- 左栏宽 260（可拖 180–420），通栏 + 右侧 1px 发丝线，头 56：「DIRECTORIES」titleMedium + 灰底计数徽标，右侧两个 34px 图标钮（取消全选、添加文件夹）。
- 每行：16px 复选框 → 20px 琥珀文件夹图标 #E0A64B（展开时换 folder_open）→ 名称 titleSmall（选中 w600 主色，否则 w500）→ 右侧 18px 展开 chevron；根目录行多一个 16px「×」（从列表移除）。行左右外边距 6，圆角 8。
- 根目录行有一圈 outlineVariant 描边框住整棵子树；子行不描边，靠 24px 缩进表达层级。选中行：主色 14% 底 + 主色 60% 描边。
- 拖文件到文件夹上：行底变主色淡底 + 1.5px 主色实线 + 主色虚线框，拖影是深底白字圆角胶囊「移动 N 项」。
- 无法访问的目录：红色 lock_person 图标替换复选框，名称错误色。

## 规则（决定每一帧里什么可用什么灰置）
根目录 = 用户「添加文件夹」登记进来的路径，受保护：可以改名（登记路径跟着改）、可以往里新建、可以作为移动目标；**不能删除**（菜单该位置改成「从列表移除」）、**不能被移动**（灰置）。子目录四个操作全开。

## 要画的帧
13a 文件夹右键菜单，两张并排：子目录版 / 根目录版。在 12d 现有项目（仅看此目录 / 取消全部 / 移动·复制 N 项到此 / 系统中显示）基础上加一组：新建子文件夹、重命名 F2、移动到…、删除 Delete。分组分隔线，快捷键右对齐 mono。根目录版：「删除」变「从列表移除」，「移动到…」灰置并给一行 11px 灰说明「根目录不能移动」。菜单宽 230，行高 32，圆角 8，图标 16。

13b 树内新建：右键父目录「新建子文件夹」后，父节点展开，子列表顶部插入一行行内编辑：琥珀图标 + 输入框（预填「新建文件夹」全选态）。同一帧画三态：正常输入 / 错误态（框描边错误色，下方一行 bodySmall 错误文案，例如「已有同名文件夹」）/ 提交后新行落到排序位并带主色淡底高亮（说明会淡出）。输入框规格按规范 32 档。

13c 行内重命名：与 13b 同一套编辑行，预填现名全选。画根目录被重命名的情形，并用注释说明提交后左栏登记路径、暂存区、工作台的登记会一起改写。

13d 删除确认弹窗（AppDialog，宽 420，圆角 16）。平台支持回收站时移到回收站，不支持时永久删除，两种文案都要画，共四张：
  - 空文件夹 · 回收站：标题「移到回收站？」+ 副标题文件夹名，一句正文「可以从系统回收站找回」，按钮「取消」（文字钮）+「移到回收站」（危险实底）。
  - 空文件夹 · 永久：标题「删除文件夹？」，正文「此操作无法撤销」，按钮「删除」。
  - 非空 · 回收站：正文是三格 mono 计数「子文件夹 / 文件 / 大小」（参考 12f 的三格汇总），危险钮文案带数量「移到回收站 · 128 项」。
  - 非空 · 永久：同上三格，加一行「此操作无法撤销」，危险钮「删除 128 项」。另画一个盘点中的瞬间：三格显示占位、危险钮 loading 不可点。

13e 拖动文件夹到文件夹：画同一棵树的四个瞬间——① 拖起某子目录，拖影胶囊「移动「cha」」；② 悬停在合法目标上（与拖文件同款高亮）；③ 悬停在非法目标（自己的后代 / 当前父目录）——目标行完全不亮、指针不变，用注释说明「不亮就是拒绝，不弹提示」；④ 试图拖起根目录——行不响应拖动，注释说明。

13f 移动进度弹窗（仅跨盘时出现，同盘瞬时完成不弹）：复用 12e 的 6px 主色进度轨 + 「不同磁盘 · 先复制再删除，耗时较长且可能中途停止」信息蓝 8% 底提示条 + 当前文件名 mono + 取消钮；再画一个「已取消」汇总：说明已复制到目标的部分保留、源目录未删。

13g 平板宽度（<1000）：左栏收进抽屉时，抽屉内同一套右键菜单与行内编辑，验证 260 宽下 13a/13b 不溢出。

## 约束
- 只画浅色；蓝色系（主色 #4A72E8 / 深 #3355C4，冷蓝灰中性色），圆角：面板 12、弹窗 16、控件 8、小徽标 6；字体 IBM Plex Sans / 数字用 mono。
- 不用 emoji；图标用 Material Symbols 线性风格。
- 反馈用 snackbar 一句话（成功绿 / 失败红），不另设弹窗。
- 每帧带一段注释说明状态与规则；文件末尾像 B1a 一样给一段 mono 规格汇总（尺寸 / 状态 / 配色角色）。
- 不要动 B1、B1a 的任何帧。
```

---

## 7. 已拍板（2026-09-03）

1. **删除**：平台支持回收站就移到回收站，不支持就永久删除，文案随能力切换。见 §2.3。
2. **根目录不可移动**。
3. **「移动到…」用系统目录选择器**。拖放已经覆盖树里能看见的所有目标；这个菜单项存在的意义是拖放够不到的地方——折叠很深的目标，以及**登记根之外**的位置（把一个文件夹挪出素材库）。应用内树选择器只能到第一种，还要再画一帧、再养一个组件；系统选择器两种都到，而且「添加文件夹」在同一栏里已经在用它，用户不陌生。若之后发现深层目标用得多，再补应用内选择器。

---

## 8. 实现记录（2026-09-03）

按 §5 的拆分一次落地，`flutter analyze` 归零。落点与 §3 一致，另有：

| 文件 | 内容 |
|---|---|
| `services/folder_operations_service.dart` | 校验 / 盘点（isolate）/ 新建 / 改名 / 删除 / `canTransfer` / `transfer`（先 rename，失败走递归复制 + 按字节进度 + 取消，复制全部到达后才删源） |
| `services/trash_service.dart` | 回收站三平台胶水：Windows `SHFileOperationW`（`win32` 直接依赖 + `ffi`，在 `Isolate.run` 里跑）、macOS `joycai/trash` MethodChannel（`MainFlutterWindow.swift`）、Linux `gio trash`；能力按进程探测一次 |
| `core/file_utils.dart` | `rebasePath`：三个 state 前缀改写共用的唯一原语，按路径段匹配 |
| `state/*` | `FileBrowserState.rewritePathPrefix` / `pruneRemoved` / `flash`，`FileStagingState.rewritePathPrefix`，`GalleryState.rewritePathPrefix`（含输出目录），`DatabaseService.renameSourceDirectory` |
| `screens/browser/folder_move_flow.dart` | `runFolderTransfer`（拖放与「移动到…」共用）+ `applyFolderPathChange`（三处登记一起改，最后刷新一次）+ 13f 进度 / 已取消汇总 |
| `screens/browser/widgets/folder_delete_dialog.dart` | 13d：空 / 非空 / 盘点中，回收站与永久两套文案，Enter 落在取消 |
| `screens/browser/widgets/folder_name_editor.dart` | 13b/13c 行内编辑：Enter 提交 / Esc 取消 / 失焦提交 / 同名零 IO / 非法名抖动 |
| `screens/browser/widgets/folder_context_menu.dart` | 13a 第二组四项 + 根目录门控（灰置项带说明行，项高 46） |
| `screens/browser/widgets/transfer_dialog_parts.dart` | 从 `staging_paste_flow.dart` 抽出的 `TransferInfoNote` / `TransferStatCell`，13f 与 12f 共用 |
| `screens/workbench/directory_tree_item.dart` | 行焦点 + F2 / Delete、行内编辑态、`FolderDragPayload` 拖起（根目录不可拖）、拖放目标双载荷 + 700ms 悬停自动展开、落点脉冲高亮 |
| `widgets/app_button.dart` | 新增 `autofocus`，给危险弹窗的「取消」用 |

**测试**：`folder_operations_service_test`（校验全分支、四个操作、`canTransfer`、同盘 rename、强制复制路线、取消保留源与半份、自身拒绝）、`folder_path_rewrite_test`（`rebasePath`、暂存区与浏览器登记的改写、`pruneRemoved` 回退父目录）、`folder_name_editor_test`（六条契约）；截图新增 `fileBrowser_desktop_light_folderMenu / folderNew / folderDelete`。Windows 回收站用临时目录真实调用过一次。

**与设计稿的差异**：
- 13c 画的是根目录改名后按名称重排；实现保持登记顺序不变（根目录的顺序是用户添加的顺序，改名不应把它挪走）。
- 13b 写「编辑期间树的其他行不可点」；未做全树锁定，靠失焦即提交达到同一效果。
- 13e 的 Ctrl 复制整棵文件夹实现了（`FolderTransferMode.copy`，复用同一条复制路线），比 §2.4 原定范围多一项。
- 拖到根目录里的 `canTransfer` 允许根作为目标，与规则表一致；根作为被拖者不产生拖影（`Draggable` 不包根行）。
