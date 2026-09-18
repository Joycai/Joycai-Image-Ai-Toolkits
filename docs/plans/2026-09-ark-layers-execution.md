# 拆图层落库与画布还原 · 执行清单

分支 `claude/ark-layers`，一片一个 commit。来源：`docs/plans/README.md`「还欠的 · 火山方舟」第一条。
响应形状已实测（`docs/api/volcengine-ark.md` §7「图层拆分」）：`data[]` 每项 `z_index`（0 = 底图）、
`name`、`description`、`bounding_box.absolute: [x0, y0, x1, y1]`（**底图像素**）。

## 决定（动手前写下，附理由）

1. **位置信息走类型化字段，不塞 `metadata`。** `LLMResponse.imageLayers` 与 `generatedImages` 一一对齐，
   `LLMResponseChunk.imageLayer` 随 `imagePart` 同行。`metadata` 是计费与收尾的口袋，跨 chunk 合并；
   逐图的信息放进去会在合并时丢对齐。协议无关的名字（`GeneratedImageLayer`），将来别家出图层也走它。
2. **对齐靠逐张下载。** `resolveImageRefs` 会跳过下载失败的项，下标就错位；方舟协议改为逐项
   `resolveImageRef`，失败的那项连同它的图层信息一起丢。
3. **落库 = 新表 `image_layers`（v46），按文件路径为主键。** 一行一个落盘文件：`set_id`（同一次响应
   的一组）、`z_index`、`name`、`description`、`box_*` 四列（底图为空）、`created_at`。不进备份（与
   `tasks` 同理：路径是本机的），`clearAllData` 不清。文件被改名 / 删掉后行成孤儿：读时按文件存在性
   过滤，不做后台清理。
4. **画布是一个全屏页，不是新的工作台标签。** 只有 5.0 pro 的一种任务产出图层，常驻标签是杂讯。
   入口：图片卡右上角「图层」铭牌角标（只在属于某组的文件上出现，点它打开）+ 右键菜单快捷格下方一行「打开图层」。
5. **画布只做「还原」，不做编辑。** 按 `bounding_box` 把每层放回底图坐标；逐层显隐、选中描框；
   「导出合成图」把可见层按底图分辨率合成一张 PNG 存到底图旁边。不做拖动、重排、改名。
6. 设计稿先行：Claude Design 新文件 `A7 图层画布.dc.html`。

## 切片

| # | 内容 | 主要文件 | 验收 | 状态 |
|---|---|---|---|---|
| 1 | 协议带出图层：`ArkImageItem` 加 `description` / `box`；`GeneratedImageLayer`；`LLMResponse.imageLayers`、`LLMResponseChunk.imageLayer`；方舟逐项下载保对齐；`_asChunks` 与 `requestStream` 的累加保对齐 | `ark_payload.dart`、`ark_images_protocol.dart`、`llm_types.dart`、`llm_dispatcher.dart`、`llm_service.dart` | 解析测试（框、缺框、z 排序）；一项下载失败时其余对齐；stream / 非 stream 都拿到图层 | ✅ |
| 2 | 落库：v46 `image_layers`（onCreate + onUpgrade）、`ImageLayer` / `ImageLayerSet` 模型、`ImageLayerRepository`；执行器存图后写行（同一响应一个 `set_id`） | `database_migrations.dart`、`database_service.dart`、`models/image_layer.dart`、`repositories/image_layer_repository.dart`、`task_executors.dart` | 迁移测试；回环服务器跑一次拆图层任务，库里 1 底图 + N 层、框对得上 | ✅ |
| 3 | 设计稿 `A7 图层画布` 推到设计项目 | scratchpad → DesignSync | 桌面 / 平板 / 手机三帧 + 规格汇总 | ✅ |
| 4 | 画布页 + 入口 + 导出合成 + 四语 | `screens/workbench/widgets/layers/…`、`image_card.dart`、`image_card_context_menu.dart`、`l10n/src/*/workbench.arb` | widget 测试（按框定位、显隐、孤儿行、导出像素）；截图 390 / 1024 / 1440 | ✅ |
| 5 | 文档收尾：`api/volcengine-ark.md`、`llm-three-layer.md`、台账划掉欠账、删本清单 | docs | — | ✅ |

之后：`/code-review high`、bump 4.15.0、开 PR；再用套餐 key 实测流式出图（lite 两张）。

## 施工记录

（按片追加偏离与理由）

- **片 2**：清单只写了落库，施工时补了「改名跟随」：应用内四处改名 / 移动（改名对话框、AI 重命名、
  文件夹改名与搬运、文件搬运）调 `ImageLayerRepository.move`，否则 AI 重命名一跑，整组图层就成了孤儿。
  `move` 先查内存里的 `layeredPaths`，与图层无关的文件不碰数据库（文件服务的测试因此不会开库）；
  目录前缀用 `substr` 比较，不用 `LIKE`（路径里可能有 `%` / `_`）。库版本 46 意味着本版写出的备份
  4.14 读不了——与每次升 schema 相同，不另处理。
- **片 3**：设计稿 `A7 图层画布.dc.html` 已推到设计项目（7a 桌面、7b 入口、7c 平板 / 手机、规格汇总）。
  与清单的出入：右键入口不进快捷格——四格与悬停条一一对应、菜单 230 宽塞不下第五格——改为快捷格下方一行；
  角标在右上（左下已有文件名与尺寸两块铭牌）。
- **片 4**：与稿的出入——① 「显示边框」的虚线用 `accentRule`（35%）而非稿上的 45%：阶梯上已有「引导线」
  这一档，`design_tokens_test` 也禁止手搓强调色透明度；② 选中的 3px 光环画成第二道描边而不是
  BoxShadow（阴影是实心的，会把被选中的层整块染色）；③ 角标只看内存索引，不查盘：稿上「整组无上层时
  不出角标」对右键菜单成立（菜单打开前查一次），角标点开若已无可叠之层给一条提示；④ 手机的导出是
  40×40 的实心 `FilledButton`——设计系统没有实心图标按钮。画布读底图尺寸用新加的
  `ImageMetadataService.readNow`：网格那条按帧排队的读法对单张全屏页只是多等一帧，测试里还永远不跑。
  截图：`test/screenshots/app_screens_layer_canvas_test.dart`（桌面亮 Blue、平板暗、手机亮 Orange、画廊角标）。
- **review（`/code-review high`，3 条，全修）**：① 覆盖目标时旧行残留——AI 重命名「覆盖」或搬运覆盖把
  一张普通图放到图层文件的路径上，旧行会把它当成那一层画进画布；`move` 先退掉目标自己的行，复制覆盖
  调新的 `forget`。② 英文「1 layers」——三条计数改 ICU 复数。③ 点图片外的棋盘地不取消选中——外层再包
  一个清空选中的点按。
