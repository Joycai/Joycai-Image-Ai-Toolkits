import 'tag.dart';

class Prompt {
  final int? id;
  final String title;
  final String content;
  final int sortOrder;
  final bool isMarkdown;
  final List<PromptTag> tags;

  Prompt({
    this.id,
    required this.title,
    required this.content,
    this.sortOrder = 0,
    this.isMarkdown = true,
    this.tags = const [],
  });

  factory Prompt.fromMap(Map<String, dynamic> map) {
    return Prompt(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
      isMarkdown: (map['is_markdown'] ?? 1) == 1,
      tags: (map['tags'] as List?)?.map((t) => PromptTag.fromMap(t)).toList() ?? [],
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final Map<String, dynamic> data = {
      'title': title,
      'content': content,
      'sort_order': sortOrder,
      'is_markdown': isMarkdown ? 1 : 0,
    };
    if (includeId) {
      data['id'] = id;
    }
    return data;
  }
}

/// What a task preset has the Prompt Assistant hand back (`A3e`).
///
/// Stored by [name]. A property of the preset rather than of the session: the
/// same instructions under the other kind's framing are, more often than not,
/// simply wrong.
enum PresetOutputKind {
  /// A prompt, delivered as a versioned card that can be applied.
  prompt,

  /// An answer in the chat, in whatever structure the preset lays down.
  analysis;

  /// Anything unrecognised — a column not there yet, a file from a later
  /// build — reads as [prompt], which is what every preset was before this.
  static PresetOutputKind parse(Object? value) =>
      values.asNameMap()[value] ?? PresetOutputKind.prompt;
}

class SystemPrompt {
  final int? id;
  final String title;
  final String content;
  final String type; // one of [types]

  /// What the Prompt Assistant loads as a task preset.
  static const String typeRefiner = 'refiner';

  /// What AI rename loads as its instructions.
  static const String typeRename = 'rename';

  static const List<String> types = [typeRefiner, typeRename];

  /// Only a [typeRefiner] preset has one; every other row is [PresetOutputKind.prompt].
  final PresetOutputKind outputKind;
  final bool isMarkdown;
  final int sortOrder;
  final List<PromptTag> tags;

  SystemPrompt({
    this.id,
    required this.title,
    required this.content,
    required this.type,
    PresetOutputKind outputKind = PresetOutputKind.prompt,
    this.isMarkdown = true,
    this.sortOrder = 0,
    this.tags = const [],
  }) : outputKind = type == typeRefiner ? outputKind : PresetOutputKind.prompt;

  factory SystemPrompt.fromMap(Map<String, dynamic> map) {
    return SystemPrompt(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      type: map['type'] as String,
      outputKind: PresetOutputKind.parse(map['output_kind']),
      isMarkdown: (map['is_markdown'] ?? 1) == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
      tags: (map['tags'] as List?)?.map((t) => PromptTag.fromMap(t)).toList() ?? [],
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final Map<String, dynamic> data = {
      'title': title,
      'content': content,
      'type': type,
      'output_kind': outputKind.name,
      'is_markdown': isMarkdown ? 1 : 0,
      'sort_order': sortOrder,
    };
    if (includeId) {
      data['id'] = id;
    }
    return data;
  }
}
