# AppMarkdown 执行清单（设计稿 `A1e Markdown 渲染`）

分支 `claude/app-markdown`。一片一个 commit；每片过两道门；阶段末 `/code-review high`。

## 目标

五处各配半张样式表的 `MarkdownBody` 收进一个原语 `AppMarkdown`（`lib/widgets/ui/app_markdown.dart`），
一张样式表、两档密度（prose / compact）。层级的主要手段是**间距不对称**（标题离上文远、贴自己的正文），
其次才是字号与记号。数值以 A1e 规格汇总为准。

## 做法（为什么不是一张 `MarkdownStyleSheet`）

`flutter_markdown_plus` 只有一个 `blockSpacing`，标题、段落、**列表项之间**全用它——今天列表比段落还松就是这么来的，
样式表拧不开。所以 `AppMarkdown` 自己解析（`package:markdown`）、自己排块：
间距、列表、引用、代码块、表格、分隔线自绘；**只有一段行内文字**（段落、标题、表格单元）交给库的 `MarkdownBuilder`。

## 分片

| # | 内容 | 文件 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | `AppMarkdownMetrics` + `AppMarkdown` + 断言测试 | `core/design_tokens.dart`、`widgets/ui/app_markdown.dart`、`test/app_markdown_test.dart`、`pubspec.yaml`（`markdown` 转直接依赖） | 字号序 H1>H2>H3>正文；标题上距 > 下距；compact 无竖条；单换行保留；图片不建 `Image`；链接无 recognizer；列表项距 < 段距 | ✅ |
| 2 | component_gallery 加一格 | `test/screenshots/component_gallery_test.dart` | 8 种子 × 明暗出图，肉眼过一遍 | ✅ `markdown_<seed>_<明暗>.png`，单独一页而不是接在长画廊后面 |
| 3 | 五处替换 | 两个编辑器、`prompt_optimizer_view`、`optimizer_prompt_card`、`prompt_card` | `grep MarkdownBody lib` 只剩 `app_markdown.dart`；截图前后对比 | ✅ |
| 4 | 收尾：台账、设计稿「实施出入」、版本 | `docs/plans/README.md`、`docs/architecture/design-tokens.md`、A1e 稿 | 本文件删除，台账留 `git show` 指针 | 待办 |

## 施工记录（与稿的出入记在这里，收尾时回写设计稿）

- **圆角 r8 → `AppRadius.sm`（6）**：稿里引用 / 代码块 / 表格 / 图片占位画的是 8，不在 4·6·10·16 的梯子上。
- **行内代码没有圆角与内距**：库把一段行内文字合成一个 `RichText`，行内代码只能是 `TextStyle.backgroundColor`；
  换成 widget 会把段落从那里劈成两个 `RichText`、断行就乱了。底色、mono、0.86em 照稿。
- **链接里的粗体 / 斜体不保留**：`a` 的 builder 以 `textContent` 重建一个无 recognizer 的 span（库自带的路径必带 recognizer，
  于是必带手形光标）。
- **列表、表格也自绘**（原计划用库的 `bulletBuilder`）：库把无序与有序的记号塞进同一个 `listIndent` 槽，做不到「圆点槽 16 / 数字槽 22」；
  已勾任务项的文字退到 `onSurfaceVariant` 也只有自绘拿得到。
- 选区：`selectable` = 外包一个 `SelectionArea`（不是库的逐块 `SelectableText`），可以跨块选。
- **表格不横向滚动，等宽列铺满限宽、单元格折行**（阶段 review 发现）：「窄则铺满、宽则自己横滚」要一个 `LayoutBuilder`，
  而工作台配置栏用 `IntrinsicHeight` 问小编辑器要高度（`MarkdownEditor.probeAvailableHeight` 的注释），预览里出现一张表就会抛。
  `app_markdown_test` 有一条「全部元素放进 IntrinsicHeight 不抛」钉住这件事。
