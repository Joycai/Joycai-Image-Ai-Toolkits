# 多目录导航条（目录大纲）· 设计方案

> 一次性施工说明书。落地后按 [README](README.md) 的做法删除本文件，在「已执行」表补一行。
> 出稿 brief 已交给 Claude Design（目标文件 `A1b 目录导航条.dc.html`），brief 文件随之删除。
>
> **进度（2026-09-13）：全部落地。** 逻辑层：`lib/core/folder_outline_geometry.dart`（偏移表 + 二分定位）、
> `folder_outline_spy.dart`（scroll-spy，含判定线与跳转期间锁定）、`folder_outline_labels.dart`（basename 消歧）、
> `FileBrowserState.groupByFolder / folderSections / isGrouped`（设置键 `browser_group_by_folder`）。
> UI 层按稿 `A1b 目录导航条.dc.html`：`widgets/folder_outline_bar.dart`（三种宿主、四级降级、右键菜单、折叠形态）、
> `widgets/folder_group_header.dart`（共享组标题，画廊 28 / 列表 32）、画廊与浏览器接入、排序菜单「按文件夹分组」、
> 四语 l10n。截图见 `flutter test test/screenshots/app_screens_folder_outline_test.dart`。
> 与稿子的两处出入：跳转落点是组标题顶边贴判定线（标题自带 10px 上留白，视觉上即稿子的 +12）；
> 折叠 chip 的菜单行没有路径副行（`AppGlassMenuItem` 只有尾部计数）。

## 1. 问题

工作台「画廊」和「文件浏览器」左侧的目录树都能勾选多个目录，把内容合并到中央区域。
勾了 a/b/c/d 四个目录之后，中央区域只能靠滚动找，无法在四个目录之间快速来回切换。

现状两处并不一样，方案要分别对待：

| | 画廊（`screens/workbench/gallery.dart`） | 文件浏览器（`screens/browser/file_browser_screen.dart`） |
|---|---|---|
| 数据 | `GalleryState.getGrouped()` 按父目录分组，`getSortedPaths()` 目录路径不区分大小写排序 | `FileBrowserState.filteredFiles` 一个平铺列表，按名称/日期/类型**全局**排序 |
| 渲染 | `CustomScrollView`，每组一个标题行（文件夹图标 + 全路径 + 数量）+ 一个 `SliverGrid`；≥2 组或「全部来源」模式才画标题 | `GridView.builder` / `ListView.builder`，无组标题，目录内容互相交错 |
| 滚动控制 | `primary: false`，没有 `ScrollController` | 同样没有 |
| 单元几何 | 正方形，`maxCrossAxisExtent = thumbnailSize`，间距 12 | 网格 `mainAxisExtent = FileCard.mainAxisExtentFor(width)`；列表 `itemExtent = BrowserFileListRow.height` |

画廊缺的只是「跳过去 + 告诉我现在在哪」。浏览器则连跳转目标都不存在——目录交错时
「跳到目录 b」没有意义。所以浏览器要先补**按文件夹分组**，再复用同一个导航控件。

树本身已经有「点名字只浏览这一个目录」（提交 939816d），它是**切换视图**，不是在合并视图里定位；
本方案不改树的语义，只在中央区域加定位手段。

## 2. 方案：目录导航条（Folder Outline）

一条横向的 chip 条，一枚 chip 对应当前视图里的一个目录，钉在滚动区顶部：

- **点 chip** → 中央区域动画滚动到该目录的组标题（M3 `panel` 280ms；系统减弱动效时 `jumpTo`）。
- **滚动时**（scroll-spy）→ 当前视口顶部所在的目录 chip 点亮，并自动把它滚进条内可见范围。
- **只在需要时出现**：当前视图有 ≥2 个目录组时才渲染；单目录、工作区（temp）视图不出现。
  这和画廊现在「≥2 组才画组标题」是同一条件。
- 顺序与网格一致（路径排序），不可拖动重排——重排就得让网格也跟着动，那是另一件事。

### 2.1 chip 内容

- 文本：目录 basename；两个目录 basename 相同时补上父级一段（`out/a` vs `tmp/a`）。全路径进 tooltip。
- 尾部数量：该组文件数，mono 小字（沿用组标题里的数量样式）。
- 不可达目录（`unreachableDirectories`）：锁图标替换文件夹图标、文字降为 `outline`，点它走已有的重新授权流程。
- 右键 / 长按 chip 弹 `AppGlassMenu`（先关菜单再执行，沿用约定）：
  - 只看这个文件夹（= 树里点名字）
  - 从视图移除（= 取消勾选）
  - 在目录树中定位（展开并滚动树到该行，行高亮沿用现有 focus 样式）

### 2.2 放在哪

- **画廊（A1）**：浮动玻璃工具条正下方，再来一条 `GlassGrade.bar` 的浮层，网格从它底下滚过；
  与工具条同 inset，高度取 `AppSize.compact`（28）+ 上下各 `s6`。
  `WorkbenchLayout` 的 `topClearance` 在导航条出现时相应增加，出现/消失用常驻节点 + `AnimatedOpacity`
  （M2），不做 `AnimatedSwitcher`，网格 inset 变化用 `AnimatedPadding`（M2）。
- **文件浏览器（B1a）**：在 `BrowserFilterBar` 之下、网格之上，**不透明**、画在列底色上，
  和 header / filter bar 一样是「不能被网格盖住」的固定 chrome，不用玻璃。

### 2.3 宽度降级（量出来的，不写像素阈值）

按 `crop_resize_toolbar.dart` 的 `needed()` 套路，逐级降：

1. 全 chip 带数量与图标。
2. 去数量。
3. chip 条整体横向 `SingleChildScrollView` + `ScrollEdgeFade`，点亮的 chip 用 `ensureVisible` 保持可见。
4. 超过某个**测量**结果（chip 总宽 > 可用宽的 2 倍，或手机布局 `rightPanelDetached`）：
   折叠为一枚「当前目录 · 2/4 ▾」chip，点开 `AppGlassMenu` 列出全部目录，勾表示当前所在。

手机（Phone dock 布局）直接取第 4 档。

### 2.4 文件浏览器先补分组

- `FileBrowserState` 新增 `groupByFolder`（持久化 `browser_group_by_folder`，默认 `true`），
  放进现有排序菜单（`BrowserFilterBar._buildSortControl`）作为一个可勾选项「按文件夹分组」。
- `_applyFilterAndSort()`：分组开启且 `activeDirectories.length > 1` 时，先按所属活动目录
  （路径排序、与树一致）分区，区内再按现有字段/方向排序。**保持 `filteredFiles` 是一个平铺列表**
  （Shift 范围选择、全选都读它的顺序），另外暴露 `folderSections`：`[(dir, start, count)]`。
  两者都在同一次赋值里换成新实例，`select` 靠身份判变。
- `_FileArea` 的网格改成 `CustomScrollView`：每个 section 一个组标题 + `SliverGrid`（几何与现在的
  `GridView.builder` 完全一致，`mainAxisExtent` 不变）；列表视图对应组标题 + `SliverFixedExtentList`。
  组标题复用画廊那一行的样式（文件夹图标 + 全路径 + 数量），抽成共享 widget `FolderGroupHeader`。
- 分组关闭或只有一个活动目录时，行为与今天完全一致，导航条也不出现。

## 3. 实现要点

### 3.1 偏移量是算出来的，不是量出来的

两个滚动区的单元尺寸都由宽度决定，没有不定高的项，所以每个组标题的滚动偏移可以**精确计算**：

```
offset(i) = topInset + Σ_{j<i} ( headerHeight + gap*2 + rows_j * cellHeight + gap*(rows_j-1) )
rows_j    = ceil(count_j / columns)
```

`columns` 与 `cellHeight` 按各自 delegate 的公式算（浏览器网格里已经有这段算法，
`_buildGrid` 的 `usable / columns / cardWidth`，抽出来共用）。

放一个纯函数 `FolderOutlineGeometry`（`lib/core/folder_outline_geometry.dart`），输入
`(viewportWidth, cellExtent, gap, headerHeight, counts)`，输出每组的起始偏移；
scroll-spy 就是对这张表做二分。它能单测，且不依赖 sliver 是否已 build——
`Scrollable.ensureVisible` 走不通，视口外的 sliver 根本没被构建。

### 3.2 rebuild 边界

- 滚动位置进一个 `ValueNotifier<int>`（当前组索引），**只有 chip 条监听它**；网格一个字都不能因为滚动重建。
  `rebuild_scope_test.dart` 加一条：滚动 3 屏，`ImageCard` / `FileCard` 的 build 计数为 0。
- 导航条读的输入用 `select` 收成一个 record：`(sortedPaths, counts, unreachable, currentIndex)`；
  选择/悬停/缩略图拖尺寸都不能让它重建。缩略图尺寸变了偏移表要重算，但 chip 不用重建——
  偏移表挂在 `ScrollController` 旁边的一个小 `ChangeNotifier` 里，按 `(width, thumbnailSize, counts)` 记忆化。

### 3.3 动效（`AppMotion`，全部经 `durationOf`）

| 动作 | 令牌 |
|---|---|
| chip hover / 按下 / 点亮 | M1 `hover` |
| 导航条出现 / 消失、网格 inset 变化 | M2 `state` |
| 点 chip 跳转滚动 | M3 `panel`，减弱动效 → `jumpTo` |
| 折叠 chip 的菜单 | 沿用 `AppGlassMenu` 自带 |

滚动跳转很长时（跨过 > 5 屏）仍是 280ms，不按距离拉长——用户要的是「到」，不是看它飞。

### 3.4 l10n（四语同步）

`folderOutlineViewOnly`（只看这个文件夹）· `folderOutlineRemove`（从视图移除）·
`folderOutlineRevealInTree`（在目录树中定位）· `folderOutlineCollapsed`（`{index}/{total}` 位置串）·
`browserGroupByFolder`（按文件夹分组）。tooltip 全路径不需要键。

### 3.5 测试

- `folder_outline_geometry_test.dart`：几组 count/宽度组合的偏移表；与真实 `SliverGrid` 布局对拍一次（`tester.getTopLeft`）。
- `rebuild_scope_test.dart`：滚动不重建卡片；勾选不重建导航条以外的东西。
- 宽度扫描测试：断言降级**顺序**（数量 → 滚动 → 折叠），不断言像素。
- `file_browser_state` 单测：分组开启时 `filteredFiles` 先按目录再按字段；Shift 范围选择跨组仍按平铺顺序。
- 截图 harness：工作台与浏览器各加一个 ≥3 目录的种子场景，四个宽度出图看一眼。

## 4. 考虑过并放弃的

- **只做组标题 pinned（`SliverPersistentHeader`）**：知道「在哪」但不能「去哪」；画廊的标题还会和浮动玻璃工具条打架。
- **右缘竖向 rail / minimap**：桌面独占，手机没地方放，和右侧配置面板抢边。
- **树里点目录名即滚动到该组**：会和已经定下的「点名字 = 只看这个目录」冲突。
- **chip 可拖动重排**：网格顺序必须跟着变，等于给画廊加「自定义目录顺序」的持久化，本轮不做。
- **画廊用 `Scrollable.ensureVisible` 跳转**：视口外的 sliver 没有 RenderObject，不可靠；见 3.1。

## 5. 分期

1. 共享件：`FolderGroupHeader`、`FolderOutlineGeometry`、`FolderOutlineBar`（chip 条 + 折叠形态 + 降级）。
2. 画廊接入：`ScrollController` + scroll-spy + 工具条下浮层 + `topClearance`。
3. 浏览器分组：state 的 `groupByFolder` / `folderSections`、排序菜单项、`_FileArea` 改 sliver。
4. 浏览器接入导航条。
5. l10n、测试、截图。

每期独立可合，1+2 先出一个 PR 让画廊先用起来。
