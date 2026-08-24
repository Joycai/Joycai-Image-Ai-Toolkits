import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../models/llm_channel.dart';

/// A channel's identity as a disc: its tag's first letter on its own colour.
///
/// The design draws this wherever a channel is *named* rather than *chosen* —
/// the channel rows on the models screen, and the summary card in the model
/// editor. It is the round counterpart to [ModelTagChip], which is what a
/// channel wears inside a picker row, where the full tag has to stay readable
/// beside a name.
///
/// Untagged channels fall back to a cloud glyph rather than an empty disc: a
/// coloured circle with nothing in it says less than an icon that at least
/// says "endpoint".
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar(this.channel, {super.key, this.size = 24});

  final LLMChannel channel;

  /// Diameter. The models screen uses 24/28/32 depending on the row; the
  /// editor's summary card uses 24.
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? tag = channel.tag;
    if (tag == null || tag.isEmpty) {
      return Icon(Icons.cloud_queue, size: size * 0.8);
    }

    return CircleAvatar(
      backgroundColor: Color(channel.tagColor ?? AppConstants.defaultTagColor),
      radius: size / 2,
      child: Text(
        tag[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
