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

  /// This preset with its wording replaced and everything else kept — what
  /// the workbench writes when an edited preset is saved back over itself.
  /// Copied here rather than field by field at the call site: a field listed
  /// by hand there is a field the next one added to this class is lost from.
  SystemPrompt withContent(String content) => SystemPrompt(
    id: id,
    title: title,
    content: content,
    type: type,
    outputKind: outputKind,
    isMarkdown: isMarkdown,
    sortOrder: sortOrder,
    tags: tags,
  );

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

  /// This preset as an export file carries it.
  ///
  /// `output_kind` is written only when it is not the default. The column
  /// arrived with `A3e` (schema v47), and a build older than that inserts these
  /// rows column by column: a key it has never heard of fails the statement,
  /// inside the import's transaction, so one preset costs the user the tags and
  /// prompts that came with it. Leaving the default out costs nothing on the way
  /// back in — [PresetOutputKind.parse] reads a missing value as
  /// [PresetOutputKind.prompt], which is what every preset was before the column
  /// existed — and keeps a library without an analysis preset readable by those
  /// builds.
  ///
  /// A preset that *is* [PresetOutputKind.analysis] still carries the key.
  /// Dropping it would import cleanly and quietly change what the preset does,
  /// which is worse than a file an old build refuses.
  ///
  /// [toMap] is left alone: it is also the database write path, where an update
  /// has to be able to set the kind back to the default.
  ///
  /// Reached through [promptLibraryExport], which is the one shape both export
  /// writers hand out; the tags come along for the same reason the key is
  /// conditional — a rule kept in two places is a rule kept in one.
  Map<String, dynamic> toExportMap() {
    final data = toMap();
    if (outputKind == PresetOutputKind.prompt) data.remove('output_kind');
    data['tags'] = tags.map((t) => t.toMap()).toList();
    return data;
  }
}

/// The `tags` / `user_prompts` / `system_prompts` trio every export file
/// carries, in the one shape both writers hand out.
///
/// There are two of them — the prompt-library file (`exportPrompts`) and the
/// full backup (`getPromptDataRaw`) — and they are not interchangeable to the
/// reader: the backup's `schema_version` gate guards only Settings → restore,
/// while the Prompt Library's import accepts either file and gates neither. So
/// both owe the same compatibility, and the way to keep that true is to give
/// them nothing of their own to get wrong. They used to build these rows
/// separately, and when [SystemPrompt.toExportMap] was introduced only one of
/// them was taught about it.
Map<String, dynamic> promptLibraryExport({
  required List<PromptTag> tags,
  required List<Prompt> userPrompts,
  required List<SystemPrompt> systemPrompts,
}) {
  return {
    'tags': tags.map((t) => t.toMap()).toList(),
    'user_prompts': userPrompts
        .map((p) => {...p.toMap(), 'tags': p.tags.map((t) => t.toMap()).toList()})
        .toList(),
    'system_prompts': systemPrompts.map((p) => p.toExportMap()).toList(),
  };
}
