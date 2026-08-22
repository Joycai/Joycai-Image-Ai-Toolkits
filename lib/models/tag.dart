import 'package:flutter/material.dart';
import '../core/constants.dart';

class PromptTag {
  final int? id;
  final String name;
  final int color;
  final bool isSystem;
  final int sortOrder;

  PromptTag({
    this.id,
    required this.name,
    this.color = AppConstants.defaultTagColor,
    this.isSystem = false,
    this.sortOrder = 0,
  });

  factory PromptTag.fromMap(Map<String, dynamic> map) {
    return PromptTag(
      id: map['id'] as int?,
      name: map['name'] as String,
      color: map['color'] as int? ?? AppConstants.defaultTagColor,
      isSystem: (map['is_system'] ?? 0) == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final Map<String, dynamic> data = {
      'name': name,
      'color': color,
      'is_system': isSystem ? 1 : 0,
      'sort_order': sortOrder,
    };
    if (includeId) {
      data['id'] = id;
    }
    return data;
  }

  Color get uiColor => Color(color);
}
