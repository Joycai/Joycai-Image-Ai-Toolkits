import 'package:flutter/material.dart';

import 'constants.dart';

/// Identity colours for what a model *is* — chat, image, video, multimodal.
///
/// A kind's hue follows it across the models screen's chips, the discovery
/// dialog's list and the type picker in the model editor, so a user scanning
/// a long list can find every video model without reading a word. Like
/// `core/fee_group_palette.dart` and `core/metric_palette.dart`, these name a
/// category rather than state a condition, which is why they are literals and
/// not roles on the [ColorScheme]: seeded hues would collapse four categories
/// into four shades of one colour.
///
/// This existed three times before — as two byte-identical `switch` statements
/// in `models_screen.dart` and `discovery_dialog.dart`, and again as a tuple
/// list in `model_edit_dialog.dart`. They happened to agree; nothing made them.

/// The colour belonging to [tag], matched against [ModelTag]'s string values.
///
/// Falls back to blue for anything unrecognised, which is also where
/// [ModelTag.refiner] lands. That is inherited rather than chosen — all three
/// of the original copies omitted refiner too — so a refiner model shows the
/// same neutral blue as an unknown tag. Worth giving its own hue if refiners
/// ever need to be picked out of a list; noted rather than done here, because
/// this file is a de-duplication and inventing a colour is not.
Color modelTagAccent(String tag) {
  switch (tag.toLowerCase()) {
    case 'image':
      return Colors.purple;
    case 'video':
      return Colors.red;
    case 'multimodal':
      return Colors.orange;
    case 'chat':
      return Colors.green;
    default:
      return Colors.blue;
  }
}
