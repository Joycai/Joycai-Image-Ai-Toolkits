import 'package:flutter/material.dart';

class PromptTag {
  final int? id;
  final String name;
  final int color;
  final bool isSystem;

  PromptTag({
    this.id,
    required this.name,
    this.color = 0xFF607D8B,
    this.isSystem = false,
  });

  factory PromptTag.fromMap(Map<String, dynamic> map) {
    return PromptTag(
      id: map['id'] as int?,
      name: map['name'] as String,
      color: map['color'] as int? ?? 0xFF607D8B,
      isSystem: (map['is_system'] ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'is_system': isSystem ? 1 : 0,
    };
  }

  Color get uiColor => Color(color);
}
