import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../models/llm_channel.dart';
import '../../../widgets/ui/tag_avatar.dart';

/// A channel's identity as a plate: its tag's first letter on its own colour.
///
/// `D1a`: drawn wherever a channel is *named* — the channel rows, the detail
/// header, the model editor's summary. The plate itself and the lettering are
/// [TagAvatar]'s, a primitive that takes a bare tag string; this is the wrapper
/// that knows an [LLMChannel]'s two cases.
///
/// Untagged channels keep the plate and swap the letter for a cloud glyph on
/// the default tag colour: a column of rows reads as one column only if every
/// row has the same plate, and an empty plate says less than a glyph that at
/// least says "endpoint".
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar(this.channel, {super.key, this.size = 24});

  final LLMChannel channel;

  /// Side length. The models screen uses 24/28/32 depending on the row; the
  /// editor's summary card uses 24.
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? tag = channel.tag;
    if (tag == null || tag.isEmpty) {
      return TagPlate(
        color: const Color(AppConstants.defaultTagColor),
        size: size,
        child: Icon(Icons.cloud_queue, size: size * 0.55, color: Colors.white),
      );
    }
    return TagAvatar(tag, color: Color(channel.tagColor ?? AppConstants.defaultTagColor), size: size);
  }
}
