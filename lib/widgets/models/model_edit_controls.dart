import 'package:flutter/material.dart';

export 'model_edit_controls/model_edit_fields.dart';
export 'model_edit_controls/model_edit_menu_field.dart';
export 'model_edit_controls/model_edit_metrics.dart';
export 'model_edit_controls/model_edit_notices.dart';
export 'model_edit_controls/model_edit_track_slider.dart';

/// The pieces the model editor (design D1c) is built from.
///
/// Private to the editor in spirit: the fields, grids and notices exported
/// here are sized and coloured for that one form, on the two grounds it
/// renders on — the 920 dialog's panel and the phone page's column.

/// A kind's glyph — the one the model card's plate carries (D1a).
IconData modelKindIcon(String tag) {
  switch (tag) {
    case 'image':
      return Icons.image_outlined;
    case 'video':
      return Icons.movie_outlined;
    case 'multimodal':
      return Icons.apps;
    default:
      return Icons.forum_outlined;
  }
}

/// A token count grouped in threes with a narrow space, as `1d` sets
/// 「200 000 tokens」.
String formatGroupedTokens(int tokens) {
  final digits = tokens.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
