import 'dart:io';

import 'package:path/path.dart' as p;

import 'knowledge_base_service.dart';

/// Outcome of a [KnowledgeBaseStarter.scaffold] run.
class KbScaffoldResult {
  /// Relative paths actually written.
  final List<String> created;

  /// Relative paths left untouched because they already existed.
  final List<String> skipped;

  const KbScaffoldResult({required this.created, required this.skipped});

  bool get isNoop => created.isEmpty;
}

/// Generates a starter knowledge base: a small tree of Chinese markdown files
/// that is structurally complete but intentionally skeletal, so the user has
/// something correct to edit instead of a blank folder.
///
/// The directory conventions encoded here (`always/` always-apply, `templates/`
/// pick-exactly-one, `conditional/` read-on-trigger) are the same ones the
/// built-in knowledge-mode system prompt already asserts — the entry file is
/// what makes them discoverable to the user.
///
/// File names are ASCII while the content is Chinese: the app ships on Windows
/// and ASCII paths are easier for a model to reproduce verbatim in tool
/// arguments.
class KnowledgeBaseStarter {
  const KnowledgeBaseStarter._();

  static const Map<String, String> files = {
    'README.md': _readme,
    'always/output-rules.md': _outputRules,
    'templates/text-to-image.md': _textToImage,
    'templates/image-to-image.md': _imageToImage,
    'templates/character-design.md': _characterDesign,
    'conditional/character-consistency.md': _characterConsistency,
    'conditional/chinese-text-render.md': _chineseTextRender,
  };

  /// Whether [root] looks like a knowledge base this class generated.
  ///
  /// [entryFileName] is excluded on purpose — every valid knowledge base has
  /// one, so it tells us nothing. A user's own knowledge base shares none of
  /// the other names, which is what distinguishes "a starter base missing a
  /// file" from "someone else's base entirely". Offering to fill in the latter
  /// would bury it in files its file map never mentions, so the agent could
  /// never read them anyway.
  static bool looksScaffolded(String root) => files.keys
      .where((relPath) => relPath != KnowledgeBaseService.entryFileName)
      .any((relPath) => File(p.join(root, relPath)).existsSync());

  /// Writes any starter file that does not already exist under [root].
  ///
  /// Non-destructive by construction: an existing file is never opened for
  /// writing, so running this against a populated knowledge base only fills in
  /// what is missing.
  static Future<KbScaffoldResult> scaffold(String root) async {
    final kb = KnowledgeBaseService();
    final created = <String>[];
    final skipped = <String>[];
    for (final entry in files.entries) {
      final relPath = entry.key;
      if (File(p.join(root, relPath)).existsSync()) {
        skipped.add(relPath);
        continue;
      }
      await kb.writeFile(root, relPath, entry.value);
      created.add(relPath);
    }
    return KbScaffoldResult(created: created, skipped: skipped);
  }
}

const String _readme = r'''
# 提示词知识库

本文件是知识库的入口与文件地图。助手每次对话都会完整读取本文件，
再按下表**按需**读取具体文件——不要一次读完整个知识库。

## 目录约定
| 目录 | 作用 | 读取时机 |
| --- | --- | --- |
| `always/` | 始终生效的全局规则 | **每次任务都必须读取并遵守** |
| `templates/` | 按任务类型划分的提示词骨架 | 只读取与当前任务类型匹配的**那一个** |
| `conditional/` | 跨任务的条件规则 | 仅当触发条件命中时读取 |

## 始终生效
| 文件 | 说明 |
| --- | --- |
| `always/output-rules.md` | 输出格式与通用底线要求 |

## 任务模板（按类型择一）
| 任务类型 | 文件 | 适用场景 |
| --- | --- | --- |
| 文生图 | `templates/text-to-image.md` | 仅有文字描述，无参考图 |
| 图生图 | `templates/image-to-image.md` | 有参考图，需风格迁移或改写 |
| 角色设定 | `templates/character-design.md` | 需要产出可复用的角色设定卡 |

## 条件规则（命中才读）
| 文件 | 触发条件 |
| --- | --- |
| `conditional/character-consistency.md` | 同一角色需要在多张图中保持一致 |
| `conditional/chinese-text-render.md` | 画面中需要出现中文文字 |

## 维护约定
- 新增任务类型 → 在 `templates/` 建文件，并在上表登记。
- 新增跨任务规则 → 放入 `conditional/`，写明触发条件。
- **任何文件的增删改，都必须同步更新本文件的表格**，否则助手无法发现它。
''';

const String _outputRules = r'''
# 输出规则（始终生效）

本文件的规则对**所有**任务类型无条件生效。

## 底线要求
- 只使用用户提供或参考图中确实存在的信息，**不要编造**角色、服装、场景的细节。
- 用户未指定的要素，宁可省略，也不要臆造。
- 不确定时，先提一个澄清问题，而不是猜测后直接产出。

## 输出格式
<!-- 在此补充：你希望提示词以什么语言、什么结构交付 -->
- 提示词语言：<!-- 例如：英文 -->
- 结构：<!-- 例如：主体 + 场景 + 光线 + 镜头 + 风格 + 画质 -->

## 通用负面词
<!-- 在此补充：每次都应排除的内容 -->

## 画质与技术词
<!-- 在此补充：你惯用的画质/渲染词条 -->
''';

const String _textToImage = r'''
# 任务模板：文生图

**适用**：用户只给了文字描述，没有参考图。

## 骨架
按以下顺序组织提示词，缺项则跳过，**不要用臆造内容填充**：

1. **主体**：<!-- 谁/什么，处于什么状态 -->
2. **外观细节**：<!-- 仅写用户明确提到的 -->
3. **场景与环境**：<!-- 地点、时间、天气 -->
4. **光线**：<!-- 例如：柔和逆光、正午硬光 -->
5. **镜头**：<!-- 例如：中景、35mm、俯拍 -->
6. **风格**：<!-- 例如：写实摄影、水彩插画 -->
7. **画质**：<!-- 见 always/output-rules.md -->

## 注意
- 用户描述含糊时，优先就**主体**提一个澄清问题。
- 遵守 `always/output-rules.md`。

## 示例
<!-- 在此补充一个你满意的实际案例，助手会以它为标杆 -->
''';

const String _imageToImage = r'''
# 任务模板：图生图

**适用**：用户提供了参考图，需要风格迁移、改写或延续。

## 前置动作
**先看图**：调用 `list_reference_images` 与 `view_image` 看过参考图后再动笔。
不要基于文件名猜测图片内容。

## 骨架
1. **保留什么**：<!-- 从参考图中必须延续的要素 -->
2. **改变什么**：<!-- 用户要求修改的部分 -->
3. **风格目标**：<!-- 目标风格描述 -->
4. **一致性约束**：<!-- 见 conditional/character-consistency.md（若涉及人物） -->
5. **画质**：<!-- 见 always/output-rules.md -->

## 注意
- 明确区分「参考图已有的」与「用户新要求的」，不要把二者混为一谈。
- 遵守 `always/output-rules.md`。

## 示例
<!-- 在此补充一个你满意的实际案例 -->
''';

const String _characterDesign = r'''
# 任务模板：角色设定

**适用**：需要产出可复用的角色设定卡，供后续多张图复用。

## 骨架
1. **身份**：<!-- 年龄段、性别、职业/身份 -->
2. **面部**：<!-- 脸型、眼睛、发型发色 -->
3. **体型**：<!-- 身高体态 -->
4. **服装**：<!-- 分层描述：上装 / 下装 / 鞋 / 配饰 -->
5. **标志性特征**：<!-- 疤痕、纹身、随身物等辨识度锚点 -->
6. **风格**：<!-- 画风 -->

## 注意
- **每一项都必须来自用户或参考图**，缺失项直接留空并向用户询问，不要自行发挥。
- 设定卡的价值在于可复用——描述要具体到能被逐字复现。
- 若后续要多图复用，同时阅读 `conditional/character-consistency.md`。

## 示例
<!-- 在此补充一个你满意的实际案例 -->
''';

const String _characterConsistency = r'''
# 条件规则：人物一致性

**触发条件**：同一角色需要在多张图中保持一致。

## 规则
- 把角色的**标志性特征**（发型发色、瞳色、服装、配饰）逐字固定下来，
  每张图的提示词中都原样重复，**不要换措辞**。
- 措辞的稳定性比辞藻的丰富度更重要——同义替换会漂移。
- 把可变项（姿势、表情、镜头、场景）与不可变项（外观设定）分开书写。

## 固定描述块
<!-- 在此补充：你的角色固定描述模板 -->

## 注意
- 与 `templates/character-design.md` 配合使用：设定卡负责定义，本文件负责复用。
''';

const String _chineseTextRender = r'''
# 条件规则：画面内中文文字

**触发条件**：画面中需要出现中文文字（招牌、标题、海报字等）。

## 规则
- 明确写出**要渲染的确切文字内容**，并用引号包裹。
- 说明文字的**位置**、**字体风格**、**大小占比**。
- 中文字形对多数模型仍不稳定：
  - 优先控制在**短字数**（建议 ≤ 6 字）。
  - 在提示词中强调字形正确、笔画完整。
  - 告知用户可能需要多次生成或后期修正。

## 模板片段
<!-- 在此补充：你惯用的文字渲染措辞 -->

## 注意
- 若用户未指定确切文字，**先询问**，不要自行拟定。
''';
