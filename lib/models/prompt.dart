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

class SystemPrompt {
  final int? id;
  final String title;
  final String content;
  final String type; // e.g. 'refiner'
  final bool isMarkdown;

  SystemPrompt({
    this.id,
    required this.title,
    required this.content,
    required this.type,
    this.isMarkdown = true,
  });

  factory SystemPrompt.fromMap(Map<String, dynamic> map) {
    return SystemPrompt(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      type: map['type'] as String,
      isMarkdown: (map['is_markdown'] ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final Map<String, dynamic> data = {
      'title': title,
      'content': content,
      'type': type,
      'is_markdown': isMarkdown ? 1 : 0,
    };
    if (includeId) {
      data['id'] = id;
    }
    return data;
  }
}
