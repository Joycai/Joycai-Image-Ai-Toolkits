/// Which workbench panel a history entry belongs to. Image and video prompts
/// are kept apart so each panel only offers prompts written for its own medium.
enum PromptHistoryType { image, video }

/// A prompt the user has previously submitted from the workbench.
///
/// Recorded on submit and capped per [PromptHistoryType]; see
/// `PromptRepository.addPromptHistory`.
class PromptHistoryEntry {
  final int? id;
  final PromptHistoryType type;
  final String content;
  final DateTime usedAt;

  PromptHistoryEntry({
    this.id,
    required this.type,
    required this.content,
    required this.usedAt,
  });

  factory PromptHistoryEntry.fromMap(Map<String, dynamic> map) {
    return PromptHistoryEntry(
      id: map['id'] as int?,
      type: PromptHistoryType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => PromptHistoryType.image,
      ),
      content: map['content'] as String,
      usedAt: DateTime.tryParse(map['used_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final Map<String, dynamic> data = {
      'type': type.name,
      'content': content,
      'used_at': usedAt.toIso8601String(),
    };
    if (includeId) {
      data['id'] = id;
    }
    return data;
  }
}
