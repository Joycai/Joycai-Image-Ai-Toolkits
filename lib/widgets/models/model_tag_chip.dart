import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/model_kind_palette.dart';

/// A small badge naming what a model is — CHAT, IMAGE, VIDEO, MULTIMODAL.
///
/// The models screen and the discovery dialog each drew their own. They had
/// already agreed on the colour (via [modelTagAccent]) but not on the box:
/// one used an 8px radius with a hairline border, the other 6px with none, so
/// the same chip looked like two different components depending on which
/// screen you opened. The bordered form wins — it is the one on the screen a
/// user spends time in, and its radius is the app's control radius rather
/// than a number of its own.
class ModelTagChip extends StatelessWidget {
  const ModelTagChip(this.tag, {super.key});

  /// A [ModelTag] string value. Unrecognised tags take the palette's fallback
  /// rather than being hidden — a model with an odd tag should still say so.
  final String tag;

  @override
  Widget build(BuildContext context) {
    final color = modelTagAccent(tag);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        // The accent ladder, even though this is an identity colour rather
        // than the theme accent: "a tint to sit on, a ring to be edged with"
        // is the same relationship, and a second set of alphas for the same
        // job is how the first set stopped being followed.
        color: color.withValues(alpha: AppAlpha.tint),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color.withValues(alpha: AppAlpha.ring)),
      ),
      child: Text(
        tag.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
