import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/model_kind_palette.dart';

/// A small badge naming what a model is — CHAT, IMAGE, VIDEO, MULTIMODAL —
/// or, with [color] supplied, what channel a row belongs to.
///
/// The models screen and the discovery dialog each drew their own. They had
/// already agreed on the colour (via [modelTagAccent]) but not on the box:
/// one used an 8px radius with a hairline border, the other 6px with none, so
/// the same chip looked like two different components depending on which
/// screen you opened. The bordered form wins — it is the one on the screen a
/// user spends time in, and its radius is the app's control radius rather
/// than a number of its own.
///
/// The channel tag in the searchable pickers was a fourth copy, at a fourth
/// padding, and the chat selector's inline one a fifth. They differ from a
/// model kind in two ways only — the colour is the channel's own rather than
/// the palette's, and the text is the user's so it is not shouted — which is
/// what [color] and [uppercase] are for.
class ModelTagChip extends StatelessWidget {
  const ModelTagChip(this.tag, {super.key, this.color, this.uppercase = true});

  /// A [ModelTag] string value. Unrecognised tags take the palette's fallback
  /// rather than being hidden — a model with an odd tag should still say so.
  final String tag;

  /// Overrides [modelTagAccent], for a tag whose colour is an identity the
  /// user chose rather than a kind the app knows.
  final Color? color;

  /// Whether to shout the tag. True for the app's own kind names, false for
  /// free text someone typed.
  final bool uppercase;

  /// Vertical space the chip adds around its single line of type: the
  /// symmetric padding plus the ring, top and bottom.
  ///
  /// Public because a fixed-extent list has to know how tall its tallest row
  /// can be *before* laying one out, and a row carrying one of these is taller
  /// than the name beside it. See `SearchablePickerField`.
  static const double chromeHeight = 2 * 2 + 2 * 1;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? modelTagAccent(tag);

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
        uppercase ? tag.toUpperCase() : tag,
        // Free text has no length limit, so the chip gives way rather than
        // pushing its row over; callers cap the width.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
